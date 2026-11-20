# Seven databases for local integration tests

From this directory, use Docker Engine or Docker Desktop with Linux containers, Compose v2.24 or newer, Bash, Python 3, and OpenSSL. Allow roughly **4–8 vCPUs, 12 GiB of RAM for Docker, and 25–35 GiB of free disk space** for images, initial volumes, and small test datasets. A host with at least 16 GiB of RAM leaves room for the OS and application. These are planning estimates. Cassandra uses a 1 GiB heap, Couchbase allocates 512 MiB each to Data and Index, and Oracle Database Free has a 2 CPU, 2 GB database RAM, and 12 GB user-data limit. [Oracle Database Free limits](https://docs.oracle.com/en/database/oracle/oracle-database/23/xeinl/database-free-installation-guide-linux.pdf)

## Start and verify

```bash
cp -n .env.example .env
./scripts/stack.sh secrets
./scripts/stack.sh start
docker compose -f compose.yaml ps
./scripts/stack.sh smoke
```

For host access, use Docker Engine 28 or newer for loopback isolation and run this startup command in place of the base startup command. The script provisions with ports closed, registers Couchbase's external addresses, then applies the override and waits for all seven checks. Rerunning with the override can briefly recreate published containers while the script applies and verifies both configurations. [Docker loopback publishing](https://docs.docker.com/engine/network/port-publishing/)

```bash
./scripts/stack.sh start --host
docker compose -f compose.yaml -f compose.host.yaml ps
./scripts/stack.sh smoke
```

`smoke` runs seven independent authenticated checks and exits nonzero if any fail. They exercise MySQL SQL against `app`, PostgreSQL schema access, Oracle SQL in `FREEPDB1`, Cassandra CQL against `app.health`, MongoDB a read in `app`, Couchbase a SQL++ document lookup in the configured bucket, and Redis named-user `PING`. To run individual checks, use the corresponding lines below.

```bash
docker compose exec -T mysql     bash /opt/playground/database.sh mysql check
docker compose exec -T postgres  bash /opt/playground/database.sh postgres check
docker compose exec -T oracle    bash /opt/playground/database.sh oracle check
docker compose exec -T cassandra bash /opt/playground/database.sh cassandra check
docker compose exec -T mongo     bash /opt/playground/database.sh mongo check
docker compose exec -T couchbase bash /opt/playground/database.sh couchbase check
docker compose exec -T redis     bash /opt/playground/database.sh redis check
```

Each individual check reports status via its exit code. Startup failures report the service name. Client output is suppressed because error messages can include credential-bearing input.

## Example projects

With the stack running, load synthetic data and run example queries for all seven databases.

```bash
./scripts/stack.sh examples
```

The command reports PASS or FAIL for each service and exits nonzero if any service fails. See the [database project scripts](scripts/examples/README.md) for expected query results and rerun behavior.

## Connections

Connect from another container on the same Compose network using the service name and internal port. Connect from the host using `127.0.0.1` and the published port after starting with `--host`. Edit the corresponding values in `.env` before running startup to apply new mappings. Stop application workloads before switching between configurations or rotating the credentials.

| Database | Service | Internal TCP | Default host TCP | Database or namespace |
| --- | --- | --- | --- | --- |
| MySQL | `mysql` | 3306 | 13306 | `app` |
| PostgreSQL | `postgres` | 5432 | 15432 | `app`, schema `public` |
| Oracle Database Free | `oracle` | 1521 | 11521 | Service `FREEPDB1`, schema named for the application user in uppercase |
| Apache Cassandra | `cassandra` | 9042 | 19042 | Keyspace `app`, local DC `datacenter1` |
| MongoDB Community | `mongo` | 27017 | 27018 | Database and authentication source `app` |
| Couchbase Server Community | `couchbase` | 8091 management, 8093 query, 11210 KV | 18091 management, 18093 query, 21210 KV | Bucket `app`, scope and collection `_default` |
| Redis | `redis` | 6379 | 16379 | DB 0, key prefix `app:` |

Pass the username and password as separate driver settings whenever supported. Choose clients that support MySQL `caching_sha2_password` and PostgreSQL SCRAM-SHA-256. Set MongoDB's `authSource=app`. For Redis, configure both fields for `AUTH username password`. For Oracle, use an Easy Connect address such as `//oracle:1521/FREEPDB1` or `//127.0.0.1:11521/FREEPDB1`. For Cassandra, supply the local DC and the published contact point on the host. If the driver follows advertised container endpoints, configure its address translator to map the single node to the loopback endpoint. Couchbase SDKs can use `couchbase://couchbase?network=default` in Docker and `couchbase://127.0.0.1:21210?network=external` on the host. The Couchbase node advertises the Docker DNS alias `couchbase.playground.test` internally. Its HTTP ports use plain HTTP. The enabled Couchbase services are Data, Query, and Index. [MySQL authentication](https://dev.mysql.com/doc/refman/8.4/en/caching-sha2-pluggable-authentication.html) · [PostgreSQL password authentication](https://www.postgresql.org/docs/17/auth-password.html) · [Couchbase port reference](https://docs.couchbase.com/server/7.6/install/install-ports.html) · [Couchbase alternate addressing](https://docs.couchbase.com/server/7.6/rest-api/rest-set-up-alternate-address.html)

## Credentials, initialization, and permissions

- `DB_USERNAME` comes from `.env`. `DB_PASSWORD` is the Compose secret read from `secrets/DB_PASSWORD`. The generator creates independent administrator credentials and preserves existing secret files. The secret directory is owner-only, with readable individual files for each image UID inside its mounted container.
- The portable username format is `app_[a-z0-9_]{1,26}`. The password is 16–30 ASCII characters from letters, digits, and `_+!-`, with at least one uppercase letter, lowercase letter, digit, and allowed symbol. Files accept an optional final LF. The scripts validate this conservative common subset before starting, quote values where needed, and encode `+` for HTTP form data. If using a URI, percent-encode the username and password as separate URI userinfo components. Generated passwords can be copied through your application's secret input without printing them in a terminal.
- The MySQL, PostgreSQL, Oracle, and MongoDB images read their administrator secret through their native `_FILE` setting. Image bootstrap occurs on a fresh volume. MySQL restricts its root account to localhost, and PostgreSQL provisions through local peer authentication. On every managed start, the provisioning script checks existing application access and creates missing application identities or objects. Existing passwords survive a rerun. Redis initializes an ACL file containing password hashes once and stores subsequent ACL changes alongside AOF data.
- The MySQL account has read/write and migration privileges scoped to `app`. PostgreSQL grants database connection and schema usage/creation, with the application owning objects it creates. Oracle grants session and common schema creation privileges plus a 512 MiB tablespace quota. Cassandra grants SELECT and MODIFY on `app`. MongoDB grants `readWrite` on `app`. Couchbase grants `bucket_full_access[app]` for application data and `ro_admin` for read-only web console access. Redis disables the default user and restricts the application to `app:*`, common data commands, and required connection and transaction commands.
- Cassandra enables password authentication and role authorization before accepting connections. On the first boot its built-in administrator is available on the project network while the script creates a separate administrator, then disables the built-in login. Couchbase establishes its administrator during that same private provisioning phase. Keep untrusted containers off the project network and use the startup script to publish ports.
- These images use public Docker Hub repositories. The Oracle image is the community-maintained `gvenzl/oracle-free` packaging of Oracle Database Free. It uses Docker Hub and normal Oracle Database Free terms, with no Oracle Container Registry login in this configuration. The image pins target Linux amd64 and arm64. Apple Silicon should use native arm64 Linux containers. MongoDB requires ARMv8.2-A or later on arm64 and AVX on x86-64. [Oracle image maintainer documentation](https://hub.docker.com/r/gvenzl/oracle-free) · [MongoDB CPU requirements](https://www.mongodb.com/docs/manual/administration/production-notes/) · [Couchbase Community roles](https://docs.couchbase.com/server/7.6/learn/security/authorization-overview.html)

### Rotate the shared password on existing volumes

Keep the stack running, pause clients, and use the same host mode as startup. The script changes all seven native accounts, verifies each new login, installs the new secret file, and recreates containers to refresh their secret bind mounts. Update application secret stores and reconnect after it completes.

```bash
./scripts/stack.sh next-password
./scripts/stack.sh rotate         # use ./scripts/stack.sh rotate --host if published
./scripts/stack.sh smoke
```

For an interrupted rotation, keep both password files and rerun the same rotation command. It accepts a database that already switched to the staged password and continues. If a container is down, start the existing container before retrying so it retains its current configuration. Keep `DB_USERNAME` fixed once a volume is in use. Changing identities requires creating a new native account and transferring databases or object ownership where applicable. Administrator password changes also require the engine's native rotation procedure.

## Stop or reset

Stop and remove the containers while retaining all named volumes.

```bash
docker compose -f compose.yaml down
```

**Delete all database data for this project.** The following command removes the named volumes. Local secret files survive.

```bash
docker compose -f compose.yaml down --volumes
```

## Image and configuration references

| Image | Primary verification source |
| --- | --- |
| `mysql:8.4.13` | [Docker Official Image](https://hub.docker.com/_/mysql) |
| `postgres:17.12-bookworm` | [Docker Official Image](https://hub.docker.com/_/postgres) |
| `gvenzl/oracle-free:23.26.4-slim-faststart` | [Maintainer tags and initialization](https://hub.docker.com/r/gvenzl/oracle-free) |
| `cassandra:5.0.9` | [Docker Official Image](https://hub.docker.com/_/cassandra) · [Apache Cassandra authentication](https://cassandra.apache.org/doc/latest/cassandra/managing/operating/security.html) |
| `mongo:8.0.38-noble` | [Docker Official Image](https://hub.docker.com/_/mongo) · [Per-tag platform metadata](https://github.com/docker-library/official-images/blob/master/library/mongo) |
| `couchbase:community-7.6.1` | [Per-tag platform metadata](https://github.com/docker-library/official-images/blob/master/library/couchbase) · [Cluster bootstrap](https://docs.couchbase.com/server/7.6/rest-api/rest-initialize-cluster.html) · [Local user REST API](https://docs.couchbase.com/server/7.6/rest-api/rbac.html) |
| `redis:7.4.12-bookworm` | [Docker Official Image](https://hub.docker.com/_/redis) · [Redis ACLs](https://redis.io/docs/latest/operate/oss_and_stack/management/security/acl/) |

## Verification

- Ran Compose configuration validation in both modes, checked the nine unique loopback port mappings and all secret, volume, and script references, and checked Bash syntax and Git ignore behavior.
- Inspected registry manifests for all seven exact tags and confirmed Linux amd64 and arm64 builds. Checked the image settings and authentication behavior against the linked primary documentation.
- On Apple Silicon with OrbStack, started all seven databases from empty volumes, ran all authenticated smoke checks, and confirmed rejection of an unknown application user. Checked the nine published endpoints, Couchbase's advertised address and host SQL++ access, Redis's named login and key restriction, and MySQL's localhost-only root account.
- Rotated the shared password using special characters, verified that every database rejected the previous password, and checked that a Redis data marker survived rotation and a separate stop and restart. Scanned Docker logs from the restart run for generated plaintext passwords. Runtime coverage was ARM64.
