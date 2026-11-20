MERGE INTO demo_ledger_postings p
USING (
    SELECT 1 AS posting_id, 'OPERATING' AS account_code, DATE '2025-06-01' AS posted_on, 1000 AS amount FROM dual
    UNION ALL SELECT 2, 'OPERATING', DATE '2025-06-02', -200 FROM dual
    UNION ALL SELECT 3, 'OPERATING', DATE '2025-06-02', -50 FROM dual
    UNION ALL SELECT 4, 'RESERVE', DATE '2025-06-02', 300 FROM dual
) fixture
ON (p.posting_id = fixture.posting_id)
WHEN NOT MATCHED THEN
  INSERT (posting_id, account_code, posted_on, amount)
  VALUES (fixture.posting_id, fixture.account_code, fixture.posted_on, fixture.amount);
COMMIT;
