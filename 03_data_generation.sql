-- =====================================================================
-- 03_data_generation.sql  (UPI-Guard, MySQL 8.0 / Workbench)
-- Run AFTER 01_schema.sql and 02_seed_manual.sql
-- Result: 500 merchants, 15,000 users, 50,000 transactions (100 batches x 500)
-- Select ALL (Cmd+A / Ctrl+A) and press the lightning bolt.
-- =====================================================================
USE upi_guard;

-- helper table of digits 0-9 (replaces recursive CTEs, no depth limit)
DROP TABLE IF EXISTS digits;
CREATE TABLE digits (d INT PRIMARY KEY);
INSERT INTO digits VALUES (0),(1),(2),(3),(4),(5),(6),(7),(8),(9);

-- ---------------------------------------------------------------------
-- PART A: master data. Guarded, so a second run cannot create duplicates.
-- ---------------------------------------------------------------------
SET @m_before = (SELECT COUNT(*) FROM merchants);
SET @u_before = (SELECT COUNT(*) FROM users);

-- 3a. 500 merchants
INSERT INTO merchants (name, category, city, onboarded_date)
SELECT CONCAT('Merchant_', n),
       ELT(1+FLOOR(RAND()*8),'Grocery','Food','Transport','Electronics','Fashion','Health','Entertainment','Fuel'),
       ELT(1+FLOOR(RAND()*8),'Mumbai','Delhi','Bengaluru','Chennai','Hyderabad','Pune','Kolkata','Jaipur'),
       DATE_ADD('2023-01-01', INTERVAL FLOOR(RAND()*700) DAY)
FROM (SELECT a.d + b.d*10 + c.d*100 + 1 AS n
      FROM digits a, digits b, digits c) x
WHERE n <= 500 AND @m_before = 10;

-- 3b. 15,000 users (ids 21 to 15020)
INSERT INTO users (name, city, kyc_status, signup_date)
SELECT CONCAT('User_', n),
       ELT(1+FLOOR(RAND()*8),'Mumbai','Delhi','Bengaluru','Chennai','Hyderabad','Pune','Kolkata','Jaipur'),
       ELT(1+FLOOR(RAND()*10),'VERIFIED','VERIFIED','VERIFIED','VERIFIED','VERIFIED','VERIFIED','VERIFIED','VERIFIED','PENDING','REJECTED'),
       DATE_ADD('2025-01-01', INTERVAL FLOOR(RAND()*600) DAY)
FROM (SELECT a.d + b.d*10 + c.d*100 + e.d*1000 + f.d*10000 + 1 AS n
      FROM digits a, digits b, digits c, digits e, digits f) x
WHERE n <= 15000 AND @u_before = 20;

-- 3c. one bank account per new user
INSERT INTO bank_accounts (user_id, bank_name, account_type)
SELECT u.user_id,
       ELT(1+FLOOR(RAND()*7),'SBI','HDFC','ICICI','Axis','Kotak','PNB','Canara'),
       IF(RAND()<0.9,'SAVINGS','CURRENT')
FROM users u
WHERE u.user_id > 20
  AND NOT EXISTS (SELECT 1 FROM bank_accounts b WHERE b.user_id = u.user_id);

-- 3d. one device per new user
INSERT INTO devices (user_id, device_type, first_seen)
SELECT u.user_id,
       ELT(1+FLOOR(RAND()*3),'ANDROID','IOS','WEB'),
       TIMESTAMP(u.signup_date, '10:00:00')
FROM users u
WHERE u.user_id > 20
  AND NOT EXISTS (SELECT 1 FROM devices d WHERE d.user_id = u.user_id);

-- CHECK: expect users 15020, merchants 510, accounts 15020, devices 15012
SELECT (SELECT COUNT(*) FROM users)         AS users,
       (SELECT COUNT(*) FROM merchants)     AS merchants,
       (SELECT COUNT(*) FROM bank_accounts) AS accounts,
       (SELECT COUNT(*) FROM devices)       AS devices;

-- ---------------------------------------------------------------------
-- PART B: pools used by the batch generator
-- ---------------------------------------------------------------------
DROP TABLE IF EXISTS user_pool;
CREATE TABLE user_pool (
  rn         INT AUTO_INCREMENT PRIMARY KEY,
  user_id    INT,
  account_id INT,
  device_id  INT,
  city       VARCHAR(40)
);
INSERT INTO user_pool (user_id, account_id, device_id, city)
SELECT u.user_id, MIN(ba.account_id), MIN(d.device_id), u.city
FROM users u
JOIN bank_accounts ba ON ba.user_id = u.user_id
JOIN devices d        ON d.user_id  = u.user_id
GROUP BY u.user_id, u.city;

DROP TABLE IF EXISTS merchant_pool;
CREATE TABLE merchant_pool (rn INT AUTO_INCREMENT PRIMARY KEY, merchant_id INT);
INSERT INTO merchant_pool (merchant_id) SELECT merchant_id FROM merchants;

DROP TABLE IF EXISTS txn_stage;
CREATE TABLE txn_stage (
  s_rn INT, r_rn INT, m_rn INT,
  kind DOUBLE, amt DECIMAL(12,2), t DATETIME, st DOUBLE
);

-- ---------------------------------------------------------------------
-- PART C: batch procedure. Each loop inserts p_batch_size rows (500).
-- ---------------------------------------------------------------------
DROP PROCEDURE IF EXISTS sp_generate_txns;
DELIMITER $$
CREATE PROCEDURE sp_generate_txns(IN p_batch_size INT, IN p_batches INT)
BEGIN
  DECLARE i INT DEFAULT 0;
  DECLARE v_pool  INT;
  DECLARE v_mpool INT;
  SELECT COUNT(*) INTO v_pool  FROM user_pool;
  SELECT COUNT(*) INTO v_mpool FROM merchant_pool;

  WHILE i < p_batches DO
    TRUNCATE TABLE txn_stage;

    -- draw the random numbers for ONE batch (stored once so every column matches)
    INSERT INTO txn_stage (s_rn, r_rn, m_rn, kind, amt, t, st)
    SELECT 1 + FLOOR(RAND() * v_pool),
           1 + FLOOR(RAND() * v_pool),
           1 + FLOOR(RAND() * v_mpool),
           RAND(),
           ROUND(10 + POW(RAND(), 3) * 5000, 2),
           TIMESTAMP('2026-01-01') + INTERVAL FLOOR(RAND() * 270 * 86400) SECOND,
           RAND()
    FROM (SELECT a.d + b.d*10 + c.d*100 + 1 AS n
          FROM digits a, digits b, digits c) x
    WHERE n <= p_batch_size;

    -- ~60% merchant payments, ~40% person-to-person, ~94% SUCCESS
    INSERT INTO transactions
      (sender_id, sender_account_id, merchant_id, receiver_id,
       amount, txn_time, status, device_id, city)
    SELECT s.user_id, s.account_id,
           IF(g.kind < 0.6, m.merchant_id, NULL),
           IF(g.kind < 0.6, NULL, r.user_id),
           g.amt, g.t,
           IF(g.st < 0.94, 'SUCCESS', IF(g.st < 0.97, 'FAILED', 'PENDING')),
           s.device_id, s.city
    FROM txn_stage g
    JOIN user_pool s     ON s.rn = g.s_rn
    JOIN user_pool r     ON r.rn = IF(g.r_rn = g.s_rn,
                                      IF(g.s_rn < v_pool, g.s_rn + 1, g.s_rn - 1),
                                      g.r_rn)
    JOIN merchant_pool m ON m.rn = g.m_rn;

    SET i = i + 1;
  END WHILE;

  TRUNCATE TABLE txn_stage;
  SELECT COUNT(*) AS total_transactions FROM transactions;
END$$
DELIMITER ;

-- ---------------------------------------------------------------------
-- RUN: 100 batches x 500 rows = 50,000 transactions
-- ---------------------------------------------------------------------
CALL sp_generate_txns(500, 100);

-- ---------------------------------------------------------------------
-- VERIFY (expect 50,019 total = 50,000 generated + 19 seed rows)
-- ---------------------------------------------------------------------
SELECT COUNT(*) AS total_transactions FROM transactions;
SELECT status, COUNT(*) AS cnt FROM transactions GROUP BY status;
SELECT COUNT(*) AS self_payments FROM transactions WHERE sender_id = receiver_id;  -- must be 0
SELECT SUM(merchant_id IS NOT NULL) AS merchant_txns,
       SUM(receiver_id IS NOT NULL) AS p2p_txns FROM transactions;
SELECT MIN(txn_time) AS first_txn, MAX(txn_time) AS last_txn,
       MIN(amount) AS min_amt, MAX(amount) AS max_amt FROM transactions;