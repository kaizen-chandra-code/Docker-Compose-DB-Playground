CREATE TABLE IF NOT EXISTS demo_ledger_postings (
    posting_id NUMBER(10) PRIMARY KEY,
    account_code VARCHAR2(20) NOT NULL,
    posted_on DATE NOT NULL,
    amount NUMBER(12,2) NOT NULL CHECK (amount <> 0)
);
