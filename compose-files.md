# Complete Docker Compose file contents

See [README.md](README.md) for startup, the connection table, credential rotation, and cleanup.

## `compose.yaml`

```yaml
x-database: &database
  environment: &app-env
    DB_USERNAME: ${DB_USERNAME:?Copy .env.example to .env and set DB_USERNAME}
  volumes:
    - ./scripts:/opt/playground:ro
  healthcheck: &health
    interval: 15s
    timeout: 12s
    retries: 20
    start_period: 30s
    start_interval: 5s

services:
  mysql:
    <<: *database
    image: mysql:8.4.13
    environment:
      <<: *app-env
      MYSQL_ROOT_HOST: localhost
      MYSQL_ROOT_PASSWORD_FILE: /run/secrets/mysql_admin
    secrets: [DB_PASSWORD, mysql_admin]
    volumes:
      - ./scripts:/opt/playground:ro
      - mysql_data:/var/lib/mysql
    healthcheck:
      <<: *health
      test: [CMD, bash, /opt/playground/database.sh, mysql, check]

  postgres:
    <<: *database
    image: postgres:17.12-bookworm
    command: [postgres, -c, log_min_error_statement=panic]
    environment:
      <<: *app-env
      POSTGRES_PASSWORD_FILE: /run/secrets/postgres_admin
      POSTGRES_INITDB_ARGS: --auth-local=peer --auth-host=scram-sha-256
      POSTGRES_HOST_AUTH_METHOD: scram-sha-256
    secrets: [DB_PASSWORD, postgres_admin]
    volumes:
      - ./scripts:/opt/playground:ro
      - postgres_data:/var/lib/postgresql/data
    healthcheck:
      <<: *health
      test: [CMD, bash, /opt/playground/database.sh, postgres, check]

  oracle:
    <<: *database
    image: gvenzl/oracle-free:23.26.4-slim-faststart
    environment:
      <<: *app-env
      ORACLE_PASSWORD_FILE: /run/secrets/oracle_admin
    secrets: [DB_PASSWORD, oracle_admin]
    volumes:
      - ./scripts:/opt/playground:ro
      - oracle_data:/opt/oracle/oradata
    healthcheck:
      <<: *health
      test: [CMD, bash, /opt/playground/database.sh, oracle, check]

  cassandra:
    <<: *database
    image: cassandra:5.0.9
    entrypoint: [bash, /opt/playground/entrypoint.sh, cassandra]
    environment:
      <<: *app-env
      CASSANDRA_CLUSTER_NAME: Playground
      CASSANDRA_DC: datacenter1
      CASSANDRA_ENDPOINT_SNITCH: GossipingPropertyFileSnitch
      MAX_HEAP_SIZE: 1G
      HEAP_NEWSIZE: 256M
    secrets: [DB_PASSWORD, cassandra_admin]
    volumes:
      - ./scripts:/opt/playground:ro
      - cassandra_data:/var/lib/cassandra
    healthcheck:
      <<: *health
      test: [CMD, bash, /opt/playground/database.sh, cassandra, check]

  mongo:
    <<: *database
    image: mongo:8.0.38-noble
    command: [mongod, --auth, --bind_ip_all]
    environment:
      <<: *app-env
      MONGO_INITDB_ROOT_USERNAME: playground_admin
      MONGO_INITDB_ROOT_PASSWORD_FILE: /run/secrets/mongo_admin
    secrets: [DB_PASSWORD, mongo_admin]
    volumes:
      - ./scripts:/opt/playground:ro
      - mongo_data:/data/db
      - mongo_config:/data/configdb
    healthcheck:
      <<: *health
      test: [CMD, bash, /opt/playground/database.sh, mongo, check]

  couchbase:
    <<: *database
    image: couchbase:community-7.6.1
    hostname: couchbase.playground.test
    networks:
      default:
        aliases: [couchbase.playground.test]
    secrets: [DB_PASSWORD, couchbase_admin]
    volumes:
      - ./scripts:/opt/playground:ro
      - couchbase_data:/opt/couchbase/var
    healthcheck:
      <<: *health
      test: [CMD, bash, /opt/playground/database.sh, couchbase, check]

  redis:
    <<: *database
    image: redis:7.4.12-bookworm
    entrypoint: [bash, /opt/playground/entrypoint.sh, redis]
    secrets: [DB_PASSWORD, redis_admin]
    volumes:
      - ./scripts:/opt/playground:ro
      - redis_data:/data
    healthcheck:
      <<: *health
      test: [CMD, bash, /opt/playground/database.sh, redis, check]

secrets:
  DB_PASSWORD:
    file: ./secrets/DB_PASSWORD
  mysql_admin:
    file: ./secrets/mysql_admin
  postgres_admin:
    file: ./secrets/postgres_admin
  oracle_admin:
    file: ./secrets/oracle_admin
  cassandra_admin:
    file: ./secrets/cassandra_admin
  mongo_admin:
    file: ./secrets/mongo_admin
  couchbase_admin:
    file: ./secrets/couchbase_admin
  redis_admin:
    file: ./secrets/redis_admin

volumes:
  mysql_data:
  postgres_data:
  oracle_data:
  cassandra_data:
  mongo_data:
  mongo_config:
  couchbase_data:
  redis_data:
```

## `compose.host.yaml`

```yaml
services:
  mysql:
    ports: ["127.0.0.1:${MYSQL_HOST_PORT:-13306}:3306"]
  postgres:
    ports: ["127.0.0.1:${POSTGRES_HOST_PORT:-15432}:5432"]
  oracle:
    ports: ["127.0.0.1:${ORACLE_HOST_PORT:-11521}:1521"]
  cassandra:
    ports: ["127.0.0.1:${CASSANDRA_HOST_PORT:-19042}:9042"]
  mongo:
    ports: ["127.0.0.1:${MONGO_HOST_PORT:-27018}:27017"]
  couchbase:
    ports:
      - "127.0.0.1:${COUCHBASE_HTTP_HOST_PORT:-18091}:8091"
      - "127.0.0.1:${COUCHBASE_QUERY_HOST_PORT:-18093}:8093"
      - "127.0.0.1:${COUCHBASE_KV_HOST_PORT:-21210}:11210"
  redis:
    ports: ["127.0.0.1:${REDIS_HOST_PORT:-16379}:6379"]
```

## `.env.example`

```dotenv
# Set an application login. The bootstrap script generates secrets/DB_PASSWORD.
DB_USERNAME=app_user

# Loopback ports used only with compose.host.yaml
MYSQL_HOST_PORT=13306
POSTGRES_HOST_PORT=15432
ORACLE_HOST_PORT=11521
CASSANDRA_HOST_PORT=19042
MONGO_HOST_PORT=27018
COUCHBASE_HTTP_HOST_PORT=18091
COUCHBASE_QUERY_HOST_PORT=18093
COUCHBASE_KV_HOST_PORT=21210
REDIS_HOST_PORT=16379
```

## `.gitignore`

```gitignore
.env
.env.*
!.env.example
/secrets/
```

## `scripts/credentials.sh`

```bash
#!/usr/bin/env bash

valid_username() {
  local name=$1
  [[ $name =~ ^app_[a-z0-9_]{1,26}$ ]]
}

valid_password() {
  local password=$1
  [[ $password =~ ^[A-Za-z0-9_+!-]{16,30}$ &&
     $password =~ [A-Z] && $password =~ [a-z] &&
     $password =~ [0-9] && $password =~ [_+!-] ]]
}

secret() {
  cat "/run/secrets/$1"
}

# The ACL file contains only hashes. Redis treats the leading # as an ACL rule.
redis_hash() {
  local hash
  hash=$(printf '%s' "$1" | sha256sum) || return
  printf '%s' "${hash%% *}"
}
```

## `scripts/entrypoint.sh`

```bash
#!/usr/bin/env bash
set -euo pipefail
export LC_ALL=C
source /opt/playground/credentials.sh

case $1 in
  cassandra)
    sed -Ei '
      s/^authenticator:.*/authenticator: PasswordAuthenticator/
      s/^authorizer:.*/authorizer: CassandraAuthorizer/
      s/^role_manager:.*/role_manager: CassandraRoleManager/
      s/^credentials_validity:.*/credentials_validity: 0ms/
    ' "$CASSANDRA_CONF/cassandra.yaml"
    grep -qx 'authenticator: PasswordAuthenticator' "$CASSANDRA_CONF/cassandra.yaml"
    grep -qx 'authorizer: CassandraAuthorizer' "$CASSANDRA_CONF/cassandra.yaml"
    exec docker-entrypoint.sh cassandra -f
    ;;
  redis)
    valid_username "$DB_USERNAME"
    if [[ ! -e /data/users.acl ]]; then
      umask 077
      app_password=$(secret DB_PASSWORD)
      admin_password=$(secret redis_admin)
      valid_password "$app_password"
      valid_password "$admin_password"
      staged=$(mktemp /data/users.acl.XXXXXX)
      trap 'rm -f "$staged"' EXIT
      {
        printf 'user default off resetpass\n'
        printf 'user playground_admin on #%s +ping +acl|setuser +acl|save\n' "$(redis_hash "$admin_password")"
        printf 'user %s on #%s ~app:* +@read +@write -@dangerous +ping +hello +client|setinfo +client|getname +client|setname +multi +exec +discard +watch +unwatch\n' \
          "$DB_USERNAME" "$(redis_hash "$app_password")"
      } > "$staged"
      chown redis:redis "$staged"
      mv "$staged" /data/users.acl
      trap - EXIT
    fi
    exec docker-entrypoint.sh redis-server --appendonly yes --aclfile /data/users.acl
    ;;
  *) exit 2 ;;
esac
```

## `scripts/database.sh`

```bash
#!/usr/bin/env bash
set -euo pipefail
export LC_ALL=C
source /opt/playground/credentials.sh

service=$1
action=$2
user=$DB_USERNAME
password=$(secret DB_PASSWORD)
valid_username "$user"
valid_password "$password"
admin=playground_admin

mysql_admin() {
  MYSQL_PWD=$(secret mysql_admin) mysql --protocol=socket --user=root --batch
}

pg_admin() {
  psql -X -q --set ON_ERROR_STOP=1 --username postgres --dbname postgres
}

oracle_app() {
  local pass=$1
  sqlplus -s -L /nolog <<SQL
whenever oserror exit failure
whenever sqlerror exit failure
set define off
connect $user/"$pass"@//127.0.0.1:1521/FREEPDB1
set heading off feedback off
select 1 from dual;
exit
SQL
}

oracle_admin() {
  sqlplus -s -L /nolog <<SQL
whenever oserror exit failure
whenever sqlerror exit failure
set define off
connect / as sysdba
alter session set container = FREEPDB1;
$(cat)
exit
SQL
}

cql() (
  local login=$1 pass=$2
  shift 2
  umask 077
  local config
  config=$(mktemp /tmp/playground-cql.XXXXXX)
  trap 'rm -f "$config"' EXIT
  printf '[PlainTextAuthProvider]\nusername = %s\npassword = %s\n' "$login" "$pass" > "$config"
  cqlsh --credentials "$config" "$@" 127.0.0.1 9042
)

mongo_shell() {
  APP_LOGIN="$user" APP_PASS="$1" NEXT_PASS="${2-}" MONGOSH_DISABLE_TELEMETRY=1 \
    mongosh --nodb --quiet --file /dev/stdin
}

# Supply basic authentication through curl's stdin config, and response bodies
# only to the callers that need them. Both inputs use the validated alphabet.
cb() {
  local login=$1 pass=$2
  shift 2
  printf 'user = "%s:%s"\n' "$login" "$pass" |
    curl -q --config - --silent --show-error --max-time 8 "$@"
}

cb_admin() {
  cb "$admin" "$(secret couchbase_admin)" "$@"
}

cb_create_user() {
  local pass=$1
  printf 'password=%s&roles=bucket_full_access%%5Bapp%%5D%%2Cro_admin' "${pass//+/%2B}" |
    cb_admin_body PUT "/settings/rbac/users/local/$user"
}

# Curl has one stdin stream. Pass form fields separately from the credentials
# via an in-memory curl config, so neither value is in the process arguments.
cb_admin_body() {
  local method=$1 endpoint=$2 body
  body=$(cat)
  {
    printf 'user = "%s:%s"\n' "$admin" "$(secret couchbase_admin)"
    printf 'data = "%s"\n' "$body"
  } | curl -q --config - --silent --show-error --fail --max-time 8 \
    --request "$method" "http://127.0.0.1:8091$endpoint"
}

check() {
  local pass=$1
  case $service in
    mysql)
      MYSQL_PWD=$pass mysql --protocol=tcp -h 127.0.0.1 -u "$user" \
        --database=app --batch --skip-column-names --execute='SELECT 1' | grep -qx 1
      ;;
    postgres)
      PGPASSWORD=$pass psql -X -h 127.0.0.1 -U "$user" -d app -Atq \
        -c "SELECT has_schema_privilege(current_user, 'public', 'USAGE') AND has_schema_privilege(current_user, 'public', 'CREATE')" | grep -qx t
      ;;
    oracle)
      oracle_app "$pass" | grep -E '^[[:space:]]*1[[:space:]]*$' >/dev/null
      ;;
    cassandra)
      cql "$user" "$pass" -e 'SELECT id FROM app.health WHERE id = 1;' |
        grep -E '^[[:space:]]*\([01] rows?\)[[:space:]]*$' >/dev/null
      ;;
    mongo)
      mongo_shell "$pass" <<'JS'
const app = new Mongo("mongodb://127.0.0.1:27017").getDB("app");
if (!app.auth(process.env.APP_LOGIN, process.env.APP_PASS)) quit(1);
app.getCollection("health").findOne({});
JS
      ;;
    couchbase)
      cb "$user" "$pass" --fail \
        --data-urlencode 'statement=SELECT RAW META(d).id FROM `app` AS d USE KEYS "playground-health"' \
        http://127.0.0.1:8093/query/service |
        grep -E '"status"[[:space:]]*:[[:space:]]*"success"' >/dev/null
      ;;
    redis)
      REDISCLI_AUTH=$pass redis-cli -e --raw --user "$user" -h 127.0.0.1 PING | grep -qx PONG
      ;;
    *) return 2 ;;
  esac
}

provision() {
  case $service in
    mysql)
      mysql_admin <<SQL
CREATE DATABASE IF NOT EXISTS app;
CREATE USER IF NOT EXISTS '$user'@'%' IDENTIFIED BY '$password';
GRANT SELECT, INSERT, UPDATE, DELETE, CREATE, ALTER, DROP, INDEX, REFERENCES
  ON app.* TO '$user'@'%';
SQL
      ;;
    postgres)
      pg_admin <<SQL
SELECT format('CREATE ROLE %I LOGIN PASSWORD %L', '$user', '$password')
WHERE NOT EXISTS (SELECT FROM pg_roles WHERE rolname = '$user') \gexec
SELECT 'CREATE DATABASE app'
WHERE NOT EXISTS (SELECT FROM pg_database WHERE datname = 'app') \gexec
REVOKE CONNECT ON DATABASE postgres, template1, app FROM PUBLIC;
GRANT CONNECT ON DATABASE app TO "$user";
\connect app
GRANT USAGE, CREATE ON SCHEMA public TO "$user";
SQL
      ;;
    oracle)
      oracle_admin <<SQL
declare
  existing_user number;
begin
  select count(*) into existing_user from dba_users where username = upper('$user');
  if existing_user = 0 then
    execute immediate 'create user $user identified by "$password" default tablespace users quota 512M on users';
  end if;
end;
/
grant create session, create table, create sequence, create view,
      create trigger, create procedure to $user;
SQL
      ;;
    cassandra)
      local admin_password
      admin_password=$(secret cassandra_admin)
      if ! cql "$admin" "$admin_password" -e 'LIST ROLES;' >/dev/null 2>&1; then
        cql cassandra cassandra <<CQL
CREATE ROLE IF NOT EXISTS $admin WITH PASSWORD = '$admin_password' AND LOGIN = true AND SUPERUSER = true;
CQL
      fi
      cql "$admin" "$admin_password" <<CQL
ALTER ROLE cassandra WITH LOGIN = false AND SUPERUSER = false;
CREATE KEYSPACE IF NOT EXISTS app WITH replication = {'class': 'NetworkTopologyStrategy', 'datacenter1': 1};
CREATE TABLE IF NOT EXISTS app.health (id int PRIMARY KEY);
CREATE ROLE IF NOT EXISTS $user WITH PASSWORD = '$password' AND LOGIN = true;
GRANT SELECT ON KEYSPACE app TO $user;
GRANT MODIFY ON KEYSPACE app TO $user;
CQL
      ;;
    mongo)
      mongo_shell "$password" <<'JS'
const root = new Mongo("mongodb://127.0.0.1:27017").getDB("admin");
const secret = require("fs").readFileSync("/run/secrets/mongo_admin", "utf8").trimEnd();
if (!root.auth("playground_admin", secret)) quit(1);
const app = root.getSiblingDB("app");
const user = process.env.APP_LOGIN;
if (!app.getUser(user)) {
  app.createUser({user, pwd: process.env.APP_PASS, roles: [{role: "readWrite", db: "app"}]});
}
JS
      ;;
    couchbase)
      local status admin_password
      admin_password=$(secret couchbase_admin)
      status=$(cb_admin --output /dev/null --write-out '%{http_code}' \
        http://127.0.0.1:8091/pools/default)
      case $status in
        200) ;;
        404)
          printf 'hostname=couchbase.playground.test&services=kv,n1ql,index&memoryQuota=512&indexMemoryQuota=512&port=SAME&username=%s&password=%s' \
            "$admin" "${admin_password//+/%2B}" | cb_admin_body POST /clusterInit
          ;;
        *) return 1 ;;
      esac
      status=$(cb_admin --output /dev/null --write-out '%{http_code}' \
        http://127.0.0.1:8091/pools/default/buckets/app)
      case $status in
        200) ;;
        404) cb_admin --fail --data 'name=app&bucketType=couchbase&ramQuota=256&replicaNumber=0' \
          http://127.0.0.1:8091/pools/default/buckets ;;
        *) return 1 ;;
      esac
      status=$(cb_admin --output /dev/null --write-out '%{http_code}' \
        "http://127.0.0.1:8091/settings/rbac/users/local/$user")
      case $status in
        200) ;;
        404) cb_create_user "$password" ;;
        *) return 1 ;;
      esac
      ;;
    redis) ;;  # Created atomically before Redis first starts.
    *) return 2 ;;
  esac
}

rotate() {
  local next=$1
  valid_password "$next"
  if check "$next" >/dev/null 2>&1; then
    if [[ $service == redis ]]; then
      redis_admin ACL SAVE | grep -qx OK
    fi
    return
  fi
  check "$password" >/dev/null 2>&1 || return 1

  case $service in
    mysql)
      mysql_admin <<SQL
ALTER USER '$user'@'%' IDENTIFIED BY '$next';
SQL
      ;;
    postgres)
      pg_admin <<SQL
ALTER ROLE "$user" PASSWORD '$next';
SQL
      ;;
    oracle)
      oracle_admin <<SQL
alter user $user identified by "$next";
SQL
      ;;
    cassandra)
      cql "$admin" "$(secret cassandra_admin)" <<CQL
ALTER ROLE $user WITH PASSWORD = '$next';
CQL
      ;;
    mongo)
      mongo_shell "$password" "$next" <<'JS'
const root = new Mongo("mongodb://127.0.0.1:27017").getDB("admin");
const secret = require("fs").readFileSync("/run/secrets/mongo_admin", "utf8").trimEnd();
if (!root.auth("playground_admin", secret)) quit(1);
root.getSiblingDB("app").changeUserPassword(process.env.APP_LOGIN, process.env.NEXT_PASS);
JS
      ;;
    couchbase)
      printf 'password=%s' "${next//+/%2B}" |
        cb_admin_body PATCH "/settings/rbac/users/local/$user"
      ;;
    redis)
      redis_admin ACL SETUSER "$user" resetpass "#$(redis_hash "$next")" | grep -qx OK
      redis_admin ACL SAVE | grep -qx OK
      ;;
    *) return 2 ;;
  esac
  check "$next"
}

redis_admin() {
  REDISCLI_AUTH=$(secret redis_admin) redis-cli -e --raw --user "$admin" -h 127.0.0.1 "$@"
}

# Suppress client output, including error messages that can echo input.
exec >/dev/null 2>&1
case $action in
  check) check "$password" ;;
  provision)
    if ! check "$password"; then
      provision
      check "$password"
    fi
    ;;
  rotate)
    next=$(cat)
    rotate "$next"
    ;;
  external)
    [[ $service == couchbase && $# == 5 ]]
    cb_admin --fail --request PUT \
      --data "hostname=127.0.0.1&mgmt=$3&n1ql=$4&kv=$5" \
      http://127.0.0.1:8091/node/controller/setupAlternateAddresses/external
    ;;
  *) exit 2 ;;
esac
```

## `scripts/stack.sh`

```bash
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
  smoke)
    failed=0
    for service in "${services[@]}"; do
      if db "$service" check </dev/null; then
        printf '%s PASS\n' "$service"
      else
        printf '%s FAIL\n' "$service" >&2
        failed=1
      fi
    done
    exit "$failed"
    ;;
  *)
    fail 'Usage: scripts/stack.sh {secrets|start|smoke|next-password|rotate} [--host]'
    ;;
esac
```
