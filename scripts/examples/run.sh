#!/usr/bin/env bash
set -euo pipefail
export LC_ALL=C
source /opt/playground/credentials.sh

service=${1-}
case $service in
  postgres|mysql|oracle) extension=sql ;;
  cassandra) extension=cql ;;
  mongo) extension=js ;;
  couchbase) extension=sqlpp ;;
  redis) extension=redis ;;
  *) echo 'Usage: run.sh {postgres|mysql|oracle|cassandra|mongo|couchbase|redis}' >&2; exit 2 ;;
esac

directory="/opt/playground/examples/$service"
user=$DB_USERNAME
password=$(secret DB_PASSWORD)
valid_username "$user"
valid_password "$password"

cassandra_query() (
  umask 077
  local config
  config=$(mktemp /tmp/playground-example-cql.XXXXXX)
  trap 'rm -f "$config"' EXIT
  printf '[PlainTextAuthProvider]\nusername = %s\npassword = %s\n' "$1" "$2" > "$config"
  # cqlsh -f can report statement failures on stderr and still exit zero.
  local errors
  if ! errors=$(cqlsh --credentials "$config" -f "$3" 127.0.0.1 9042 2>&1 >&3); then
    printf '%s\n' "$errors" >&2
    return 1
  fi
  if [[ -n $errors ]]; then
    printf '%s\n' "$errors" >&2
    return 1
  fi
) 3>&1

couchbase_query() {
  local response
  response=$(
    printf 'user = "%s:%s"\n' "$user" "$password" |
      curl -q --config - --silent --show-error --max-time 30 \
        --data-urlencode "statement@$1" http://127.0.0.1:8093/query/service
  ) || return
  printf '%s\n' "$response"
  [[ $response =~ \"status\"[[:space:]]*:[[:space:]]*\"success\" ]]
}

run_file() {
  local file=$1
  case $service in
    mysql)
      MYSQL_PWD=$password mysql --protocol=tcp -h 127.0.0.1 -u "$user" --database=app --batch < "$file"
      ;;
    postgres)
      PGPASSWORD=$password psql -X -h 127.0.0.1 -U "$user" -d app -v ON_ERROR_STOP=1 -P pager=off -f "$file"
      ;;
    oracle)
      sqlplus -s -L /nolog <<SQL
whenever oserror exit failure rollback
whenever sqlerror exit failure rollback
set define off
connect $user/"$password"@//127.0.0.1:1521/FREEPDB1
@$file
exit
SQL
      ;;
    cassandra)
      if [[ $file == */01-* ]]; then
        cassandra_query playground_admin "$(secret cassandra_admin)" "$file"
      else
        cassandra_query "$user" "$password" "$file"
      fi
      ;;
    mongo)
      APP_LOGIN=$user APP_PASS=$password EXAMPLE_FILE=$file MONGOSH_DISABLE_TELEMETRY=1 \
        mongosh --nodb --quiet --file /dev/stdin <<'JS'
const app = new Mongo("mongodb://127.0.0.1:27017").getDB("app");
if (!app.auth(process.env.APP_LOGIN, process.env.APP_PASS)) quit(1);
load(process.env.EXAMPLE_FILE);
JS
      ;;
    couchbase) couchbase_query "$file" ;;
    redis)
      REDISCLI_AUTH=$password redis-cli -e --raw --user "$user" < "$file"
      ;;
  esac
}

for file in "$directory"/*."$extension"; do
  printf '\n== %s ==\n' "${file##*/}"
  run_file "$file"
done
