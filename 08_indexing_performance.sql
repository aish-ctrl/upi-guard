
-- =====================================================================
-- 08_indexing_performance.sql
-- UPI-Guard | MySQL 8.0.18+
-- Run after Files 01–07
-- =====================================================================

USE upi_guard;

-- =====================================================================
-- PART 1: CHECK EXISTING INDEXES
-- =====================================================================

SHOW INDEX FROM transactions;

SELECT COUNT(*) AS total_transactions
FROM transactions;


-- =====================================================================
-- PART 2: BASELINE PERFORMANCE — CORRELATED SUBQUERY
-- =====================================================================
-- Run this query 3 times and record the execution time.
-- Do this before creating idx_sender_time.
-- Do not drop existing primary or foreign-key-supporting indexes.

EXPLAIN ANALYZE
SELECT
    t1.txn_id,
    t1.sender_id,
    (
        SELECT COUNT(*)
        FROM transactions AS t2
        WHERE t2.sender_id = t1.sender_id
          AND t2.txn_time BETWEEN
              t1.txn_time - INTERVAL 10 MINUTE
              AND t1.txn_time
    ) AS cnt
FROM transactions AS t1
WHERE t1.sender_id BETWEEN 100 AND 400;


-- =====================================================================
-- PART 3: CREATE THE COMPOSITE INDEX
-- =====================================================================
-- Run this CREATE INDEX statement only if the index does not exist.
-- Check SHOW INDEX FROM transactions first.

CREATE INDEX idx_sender_time
ON transactions (sender_id, txn_time);

-- Verify the index.
SHOW INDEX FROM transactions;

-- Run the same query again 3 times and record the execution time.

EXPLAIN ANALYZE
SELECT
    t1.txn_id,
    t1.sender_id,
    (
        SELECT COUNT(*)
        FROM transactions AS t2
        WHERE t2.sender_id = t1.sender_id
          AND t2.txn_time BETWEEN
              t1.txn_time - INTERVAL 10 MINUTE
              AND t1.txn_time
    ) AS cnt
FROM transactions AS t1
WHERE t1.sender_id BETWEEN 100 AND 400;


-- =====================================================================
-- PART 4: WINDOW FUNCTION COMPARISON
-- =====================================================================
-- Compare its result and execution time with the correlated query.

EXPLAIN ANALYZE
SELECT
    txn_id,
    sender_id,
    COUNT(*) OVER (
        PARTITION BY sender_id
        ORDER BY txn_time
        RANGE BETWEEN INTERVAL 10 MINUTE PRECEDING
                  AND CURRENT ROW
    ) AS cnt
FROM transactions
WHERE sender_id BETWEEN 100 AND 400;


-- =====================================================================
-- PART 5: EXTRA INDEXES
-- =====================================================================
-- Create each index only once. If it already exists, skip its
-- CREATE INDEX statement and run the corresponding test query.

-- 5.1 Receiver + time: useful candidate for receiver activity
CREATE INDEX idx_receiver_time
ON transactions (receiver_id, txn_time);

EXPLAIN ANALYZE
SELECT receiver_id, COUNT(*) AS received_txns
FROM transactions
WHERE receiver_id IS NOT NULL
  AND txn_time >= '2026-01-01'
  AND txn_time <  '2027-01-01'
GROUP BY receiver_id;


-- 5.2 Merchant: useful candidate for merchant analytics
CREATE INDEX idx_merchant
ON transactions (merchant_id);

EXPLAIN ANALYZE
SELECT
    merchant_id,
    COUNT(*) AS total_txns,
    ROUND(SUM(amount), 2) AS total_amount
FROM transactions
WHERE merchant_id IS NOT NULL
GROUP BY merchant_id;


-- 5.3 Transaction time: useful candidate for date-range reporting
CREATE INDEX idx_txn_time
ON transactions (txn_time);

EXPLAIN ANALYZE
SELECT
    DATE(txn_time) AS txn_day,
    COUNT(*) AS total_txns,
    ROUND(SUM(amount), 2) AS total_amount
FROM transactions
WHERE txn_time >= '2026-01-01'
  AND txn_time <  '2026-07-01'
GROUP BY DATE(txn_time)
ORDER BY txn_day;


-- Refresh optimizer statistics and verify indexes.
ANALYZE TABLE transactions;
SHOW INDEX FROM transactions;


-- =====================================================================
-- PART 6: BONUS — MONTHLY PARTITIONING ON A SEPARATE COPY
-- =====================================================================
-- This section is optional.
-- It never partitions or drops the original transactions table.
-- It drops and recreates only transactions_part.
--
-- CREATE TABLE ... LIKE copies the table definition and indexes,
-- but does not copy foreign keys. Therefore, do not DROP FOREIGN KEY
-- constraints on transactions_part.

DROP TABLE IF EXISTS transactions_part;

CREATE TABLE transactions_part LIKE transactions;

-- A partitioned table's primary key must include txn_time.
ALTER TABLE transactions_part
    MODIFY COLUMN txn_id BIGINT NOT NULL AUTO_INCREMENT,
    DROP PRIMARY KEY,
    ADD PRIMARY KEY (txn_id, txn_time);

-- Partition transactions by month.
ALTER TABLE transactions_part
PARTITION BY RANGE (TO_DAYS(txn_time)) (
    PARTITION p202601 VALUES LESS THAN (TO_DAYS('2026-02-01')),
    PARTITION p202602 VALUES LESS THAN (TO_DAYS('2026-03-01')),
    PARTITION p202603 VALUES LESS THAN (TO_DAYS('2026-04-01')),
    PARTITION p202604 VALUES LESS THAN (TO_DAYS('2026-05-01')),
    PARTITION p202605 VALUES LESS THAN (TO_DAYS('2026-06-01')),
    PARTITION p202606 VALUES LESS THAN (TO_DAYS('2026-07-01')),
    PARTITION p202607 VALUES LESS THAN (TO_DAYS('2026-08-01')),
    PARTITION p202608 VALUES LESS THAN (TO_DAYS('2026-09-01')),
    PARTITION p202609 VALUES LESS THAN (TO_DAYS('2026-10-01')),
    PARTITION pmax VALUES LESS THAN MAXVALUE
);

-- Copy the original transactions into the partitioned copy.
INSERT INTO transactions_part
SELECT *
FROM transactions;

-- Verify row counts.
SELECT
    (SELECT COUNT(*) FROM transactions) AS original_rows,
    (SELECT COUNT(*) FROM transactions_part) AS partitioned_rows;

-- Verify the partition definitions.
SELECT
    PARTITION_NAME,
    PARTITION_DESCRIPTION,
    TABLE_ROWS
FROM INFORMATION_SCHEMA.PARTITIONS
WHERE TABLE_SCHEMA = 'upi_guard'
  AND TABLE_NAME = 'transactions_part'
ORDER BY PARTITION_ORDINAL_POSITION;

-- Check partition pruning for May 2026.
EXPLAIN
SELECT COUNT(*)
FROM transactions_part
WHERE txn_time >= '2026-05-01'
  AND txn_time <  '2026-06-01';

-- In the EXPLAIN result, inspect the partitions column.
-- It should identify p202605 for this date range.


-- =====================================================================
-- PART 7: FINAL VERIFICATION
-- =====================================================================

-- The original transactions table should still be intact.
SELECT COUNT(*) AS original_transaction_count
FROM transactions;

-- List indexes on the original table.
SHOW INDEX FROM transactions;

-- End of File 08
