SET LINESIZE 150
COLUMN account_code FORMAT A15
COLUMN posting_day FORMAT A12

-- The posting ID breaks ties for entries made on the same day.
SELECT account_code, posting_id, TO_CHAR(posted_on, 'YYYY-MM-DD') AS posting_day, amount,
       SUM(amount) OVER (
           PARTITION BY account_code ORDER BY posted_on, posting_id
           ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
       ) AS running_balance
FROM demo_ledger_postings
ORDER BY account_code, posted_on, posting_id;

SELECT account_code, SUM(amount) AS closing_balance
FROM demo_ledger_postings GROUP BY account_code ORDER BY account_code;
