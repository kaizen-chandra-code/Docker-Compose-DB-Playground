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
