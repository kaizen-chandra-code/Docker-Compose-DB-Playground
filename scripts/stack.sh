#!/usr/bin/env bash
set -euo pipefail
export LC_ALL=C
cd "$(dirname "${BASH_SOURCE[0]}")/.."
source scripts/credentials.sh

services=(mysql postgres oracle cassandra mongo couchbase redis)
base=(docker compose --env-file .env -f compose.yaml)
compose=("${base[@]}")
mode=${1-}
case "${2-}" in
  '') ;;
  --host) compose+=(-f compose.host.yaml) ;;
  *) printf 'Unknown option.\n' >&2; exit 2 ;;
esac

fail() {
  printf '%s\n' "$*" >&2
  exit 1
}

lock() {
  (umask 077; mkdir -p secrets)
  chmod 700 secrets
  mkdir secrets/.operation-lock || fail 'Another stack operation holds the lock.'
  trap 'rmdir secrets/.operation-lock' EXIT
  trap 'exit 130' INT
  trap 'exit 143' TERM
}

generate() {
  local output=$1 random staged
  if [[ ! -e $output ]]; then
    random=$(openssl rand -hex 12) || return
    staged=$(mktemp secrets/.generated.XXXXXX)
    printf 'Aa1!%s\n' "$random" > "$staged"
    # Let the different container UIDs read their individual bind mounts.
    chmod 644 "$staged"
    ln "$staged" "$output"
    rm -f "$staged"
  fi
  validate_file "$output"
}

validate_file() {
  local file=$1 value
  [[ -f $file ]] || fail "Missing $file. Run scripts/stack.sh secrets."
  value=$(cat "$file")
  valid_password "$value" || fail "Invalid password format in $file."
  # A single optional LF is accepted. Reject CR, NUL, and extra line breaks.
  if ! cmp -s "$file" <(printf '%s' "$value") &&
     ! cmp -s "$file" <(printf '%s\n' "$value"); then
    fail "Invalid file format in $file."
  fi
}

db() {
  local service=$1
  shift
  local -a exec_args=(exec -T)
  if [[ $service == postgres && $1 != check ]]; then
    exec_args+=(-u postgres)
  fi
  "${base[@]}" "${exec_args[@]}" "$service" \
    bash /opt/playground/database.sh "$service" "$@"
}

run_examples() {
  local service=$1
  printf '\n== %s examples ==\n' "$service"
  "${compose[@]}" exec -T "$service" \
    bash /opt/playground/examples/run.sh "$service"
}

configuration() {
  "${compose[@]}" config --format json | python3 -c '
import json, re, sys
services = json.load(sys.stdin)["services"]
username = services["mysql"]["environment"]["DB_USERNAME"]
if not re.fullmatch(r"app_[a-z0-9_]{1,26}", username):
    sys.exit("DB_USERNAME must match app_[a-z0-9_]{1,26}.")
ports = [p for service in services.values() for p in service.get("ports", [])]
published = [int(p["published"]) for p in ports]
if (len(set(published)) != len(published)
    or any(p["host_ip"] != "127.0.0.1" for p in ports)
    or any(not 1 <= port <= 65535 for port in published)):
    sys.exit("Use distinct loopback host ports from 1 to 65535.")
couchbase = {p["target"]: p["published"] for p in services["couchbase"].get("ports", [])}
if couchbase:
    print(couchbase[8091], couchbase[8093], couchbase[11210])
'
}

provision() {
  local service=$1
  local end=$((SECONDS + 600))
  until db "$service" provision </dev/null; do
    if (( SECONDS >= end )); then
      printf '%s failed provisioning or authentication. Check service logs and existing credentials.\n' "$service" >&2
      return 1
    fi
    sleep 5
  done
  printf '%s ready\n' "$service"
}

wait_ready() {
  "${compose[@]}" up -d --wait --wait-timeout 600 "$@"
}

case $mode in
  secrets)
    lock
    generate secrets/DB_PASSWORD
    for service in "${services[@]}"; do generate "secrets/${service}_admin"; done
    printf 'Secret files are ready.\n'
    ;;
  start)
    lock
    validate_file secrets/DB_PASSWORD
    for service in "${services[@]}"; do validate_file "secrets/${service}_admin"; done
    external=$(configuration)
    "${base[@]}" up -d
    pids=()
    for service in "${services[@]}"; do
      provision "$service" &
      pids+=("$!")
    done
    failed=0
    for pid in "${pids[@]}"; do wait "$pid" || failed=1; done
    (( failed == 0 )) || exit 1
    if [[ -n $external ]]; then
      read -r mgmt query kv <<< "$external"
      db couchbase external "$mgmt" "$query" "$kv" </dev/null
    fi
    wait_ready
    ;;
  next-password)
    lock
    generate secrets/DB_PASSWORD_NEXT
    printf 'Next application password is staged.\n'
    ;;
  rotate)
    lock
    validate_file secrets/DB_PASSWORD
    validate_file secrets/DB_PASSWORD_NEXT
    for service in "${services[@]}"; do validate_file "secrets/${service}_admin"; done
    configuration >/dev/null
    for service in "${services[@]}"; do
      db "$service" rotate < secrets/DB_PASSWORD_NEXT ||
        fail "Rotation paused at $service. Keep both secret files and rerun the same command."
      printf '%s password verified\n' "$service"
    done
    staged=$(mktemp secrets/.rotation.XXXXXX)
    cat secrets/DB_PASSWORD_NEXT > "$staged"
    chmod 644 "$staged"
    mv "$staged" secrets/DB_PASSWORD
    wait_ready --force-recreate
    rm -f secrets/DB_PASSWORD_NEXT
    printf 'Application password rotated on all seven databases.\n'
    ;;
  smoke|examples)
    failed=0
    for service in "${services[@]}"; do
      if { [[ $mode == smoke ]] && db "$service" check; } </dev/null ||
        { [[ $mode == examples ]] && run_examples "$service"; } </dev/null; then
        printf '%s PASS\n' "$service"
      else
        printf '%s FAIL\n' "$service" >&2
        failed=1
      fi
    done
    exit "$failed"
    ;;
  *)
    fail 'Usage: scripts/stack.sh {secrets|start|smoke|examples|next-password|rotate} [--host]'
    ;;
esac
