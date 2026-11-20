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
