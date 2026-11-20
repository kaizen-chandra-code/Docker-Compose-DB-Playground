# Database projects

From the repository root, start the stack with `./scripts/stack.sh start` if needed. Run all seven projects with one command.

```sh
./scripts/stack.sh examples
```

The command prints each project's output and a PASS or FAIL based on whether all its scripts completed successfully. It continues through all seven services and exits with status 1 if any service fails.

To run one project, replace both instances of `postgres` with one of the Compose services below.

```sh
docker compose exec -T postgres bash /opt/playground/examples/run.sh postgres
```

The runner executes the numbered files in the service directory. Run `01` for schema or setup, `02` for synthetic seed data, and `03` for the example queries. The runner uses the existing application credentials and databases. Cassandra table creation uses the configured administrator because the application role has SELECT and MODIFY privileges on `app`. The seed and queries use the application role.

| Service | Project and database features | Expected results after seeding |
| --- | --- | --- |
| `postgres` | Amazon-style orders use foreign keys and check constraints across customers, products, orders, line items, payments, and shipments. The seed records checkout prices and related rows in a transaction. | Asha's history shows order 302 for 15.00, pending with no shipment, and order 301 for 65.00, paid and shipped. Paid revenue by UTC order date is 65.00 on June 1 and 25.00 on June 2, 2025. |
| `cassandra` | Netflix-style catalog metadata uses one table for title lookup and another for browsing by genre and year. | Title `t01` is *Signal at Dawn*. Sci-Fi in 2025 returns `t01` and `t03` in that order. Drama in 2025 returns `t01`. |
| `mysql` | Warehouse availability uses an InnoDB table with a stored generated column for on-hand stock minus reservations. A composite index supports low-stock lookup by warehouse. | BLR flags BAG at 0 and MUG at 5. DEL can fulfill the bag request with 16 available. |
| `oracle` | An account ledger uses Oracle analytic functions to compute running balances by account with a posting ID tie-breaker. | OPERATING runs through 1000, 800, and 750. RESERVE has one posting of 300. Closing balances are 750 and 300, respectively. |
| `mongo` | Help desk tickets embed event histories and optional delivery metadata. A compound index supports the open queue, and an array query finds replies. | The open queue shows `ticket-001` ahead of `ticket-002`. Only `ticket-001` is open with an agent reply. |
| `couchbase` | Store menus use known document keys for direct reads and SQL++ to expand nested item arrays across selected stores. | The Central menu contains mint tea and unavailable lemon cake. Mint tea qualifies at Central for 4 and Harbor for 5. |
| `redis` | An arcade leaderboard uses a hash for season settings and a sorted set for ranking and score lookup. | The top three are pixel at 1200, orbit at 950, and nova at 950. Nova has zero-based rank 2. Redis breaks equal-score ties in reverse lexicographic order for this query. |

Cassandra uses `title_id` as the partition key for single-title reads. Browsing reads a single `(genre, release_year)` partition, and the `title_id` clustering column orders results within it. The year groups each genre into smaller partitions. The seed copies each title into every relevant genre partition. If a title's genre or year changes, an application must update both tables and remove entries for old genre/year keys.

The examples use dedicated tables, a dedicated MongoDB collection, and reserved document IDs or key prefixes in the shared application stores. Seed a fresh set of demo records for the results in the table. PostgreSQL, MySQL, Oracle, MongoDB, and Redis preserve existing fixture rows, documents, hash fields, or scores on rerun. Cassandra and Couchbase upsert their fixture rows or documents using deterministic keys. Rerunning those seeds restores the shipped fixture values for those keys.
