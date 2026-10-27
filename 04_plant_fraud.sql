-- =====================================================================
-- 04_plant_fraud.sql  (UPI-Guard, MySQL 8.0 / Workbench)
-- Run AFTER 03_data_generation.sql. Run it ONCE (it refuses to run twice).
-- Plants 6 fraud patterns and records every planted transaction in
-- fraud_ground_truth, so precision / recall can be measured later.
--
--   velocity           150 users x 8 txns inside 6 minutes   = 1200 txns
--   amount_anomaly     100 users, one txn of 60,000-90,000   =  100 txns
--   impossible_travel  100 users, 2nd txn in another city    =  100 txns
--   new_device_large    80 users, new device + 40,000-60,000 =   80 txns
--   mule               10 receivers x 15 distinct senders    =  150 txns
--   night_spike       300 users, 12,000-32,000 at 1-4 AM     =  300 txns
--                                                     total   = 1930 txns
-- Select ALL (Cmd+A / Ctrl+A) and press the lightning bolt.
-- =====================================================================
USE upi_guard;

-- safety: digits helper (already created by file 3)
CREATE TABLE IF NOT EXISTS digits (d INT PRIMARY KEY);
INSERT IGNORE INTO digits VALUES (0),(1),(2),(3),(4),(5),(6),(7),(8),(9);

DROP PROCEDURE IF EXISTS sp_plant_fraud;
DELIMITER $$
CREATE PROCEDURE sp_plant_fraud()
main: BEGIN
  DECLARE v_start BIGINT;

  -- guard: file 2 leaves 8 ground-truth rows; more than that means already planted
  IF (SELECT COUNT(*) FROM fraud_ground_truth) > 8 THEN
    SELECT 'Fraud already planted. Nothing done. (Rerun 01, 02, 03 to start over.)' AS message;
    LEAVE main;
  END IF;

  -- -------------------------------------------------------------------
  -- 4a. VELOCITY: users 100-249 each fire 8 txns, 45 seconds apart
  -- -------------------------------------------------------------------
  SELECT COALESCE(MAX(txn_id), 0) INTO v_start FROM transactions;

  INSERT INTO transactions
    (sender_id, sender_account_id, receiver_id, amount, txn_time, status, device_id, city)
  SELECT x.user_id, x.account_id,
         IF(x.r = x.user_id, x.r + 1, x.r),
         x.amt, x.t, 'SUCCESS', x.device_id, x.city
  FROM (
    SELECT u.user_id, ba.account_id, d.device_id, u.city,
           21 + FLOOR(RAND()*15000)  AS r,
           ROUND(20 + RAND()*150, 2) AS amt,
           TIMESTAMP('2026-05-10 15:00:00')
             + INTERVAL (u.user_id MOD 60) DAY + INTERVAL (k.i * 45) SECOND AS t
    FROM users u
    CROSS JOIN (SELECT d + 1 AS i FROM digits WHERE d < 8) k
    JOIN bank_accounts ba ON ba.user_id = u.user_id
    JOIN devices d        ON d.user_id  = u.user_id
    WHERE u.user_id BETWEEN 100 AND 249
  ) x;

  INSERT INTO fraud_ground_truth (txn_id, pattern)
  SELECT txn_id, 'velocity' FROM transactions WHERE txn_id > v_start;

  -- -------------------------------------------------------------------
  -- 4b. AMOUNT ANOMALY: users 300-399 send one huge txn (60,000-90,000)
  -- -------------------------------------------------------------------
  SELECT MAX(txn_id) INTO v_start FROM transactions;

  INSERT INTO transactions
    (sender_id, sender_account_id, receiver_id, amount, txn_time, status, device_id, city)
  SELECT x.user_id, x.account_id,
         IF(x.r = x.user_id, x.r + 1, x.r),
         x.amt, x.t, 'SUCCESS', x.device_id, x.city
  FROM (
    SELECT u.user_id, ba.account_id, d.device_id, u.city,
           21 + FLOOR(RAND()*15000)       AS r,
           ROUND(60000 + RAND()*30000, 2) AS amt,
           TIMESTAMP('2026-06-15 13:00:00') + INTERVAL (u.user_id MOD 30) DAY AS t
    FROM users u
    JOIN bank_accounts ba ON ba.user_id = u.user_id
    JOIN devices d        ON d.user_id  = u.user_id
    WHERE u.user_id BETWEEN 300 AND 399
  ) x;

  INSERT INTO fraud_ground_truth (txn_id, pattern)
  SELECT txn_id, 'amount_anomaly' FROM transactions WHERE txn_id > v_start;

  -- -------------------------------------------------------------------
  -- 4c. IMPOSSIBLE TRAVEL: users 500-599, home-city txn, then another
  --     city 10 minutes later. Only the 2nd txn is the fraud.
  -- -------------------------------------------------------------------
  INSERT INTO transactions
    (sender_id, sender_account_id, merchant_id, amount, txn_time, status, device_id, city)
  SELECT x.user_id, x.account_id, x.mid, 800, x.t, 'SUCCESS', x.device_id, x.city
  FROM (
    SELECT u.user_id, ba.account_id, d.device_id, u.city,
           1 + FLOOR(RAND()*500) AS mid,
           TIMESTAMP('2026-07-04 11:00:00') + INTERVAL (u.user_id MOD 20) DAY AS t
    FROM users u
    JOIN bank_accounts ba ON ba.user_id = u.user_id
    JOIN devices d        ON d.user_id  = u.user_id
    WHERE u.user_id BETWEEN 500 AND 599
  ) x;

  SELECT MAX(txn_id) INTO v_start FROM transactions;

  INSERT INTO transactions
    (sender_id, sender_account_id, merchant_id, amount, txn_time, status, device_id, city)
  SELECT x.user_id, x.account_id, x.mid, 1500, x.t, 'SUCCESS', x.device_id,
         IF(x.city = 'Delhi', 'Chennai', 'Delhi')
  FROM (
    SELECT u.user_id, ba.account_id, d.device_id, u.city,
           1 + FLOOR(RAND()*500) AS mid,
           TIMESTAMP('2026-07-04 11:10:00') + INTERVAL (u.user_id MOD 20) DAY AS t
    FROM users u
    JOIN bank_accounts ba ON ba.user_id = u.user_id
    JOIN devices d        ON d.user_id  = u.user_id
    WHERE u.user_id BETWEEN 500 AND 599
  ) x;

  INSERT INTO fraud_ground_truth (txn_id, pattern)
  SELECT txn_id, 'impossible_travel' FROM transactions WHERE txn_id > v_start;

  -- -------------------------------------------------------------------
  -- 4d. NEW DEVICE + HIGH VALUE: users 700-779 get a brand new device,
  --     then send 40,000-60,000 about 45 minutes later
  -- -------------------------------------------------------------------
  INSERT INTO devices (user_id, device_type, first_seen)
  SELECT user_id, 'ANDROID',
         TIMESTAMP('2026-08-12 01:30:00') + INTERVAL (user_id MOD 25) DAY
  FROM users WHERE user_id BETWEEN 700 AND 779;

  SELECT MAX(txn_id) INTO v_start FROM transactions;

  INSERT INTO transactions
    (sender_id, sender_account_id, receiver_id, amount, txn_time, status, device_id, city)
  SELECT x.user_id, x.account_id,
         IF(x.r = x.user_id, x.r + 1, x.r),
         x.amt, x.t, 'SUCCESS', x.device_id, x.city
  FROM (
    SELECT u.user_id, ba.account_id, u.city,
           (SELECT MAX(d.device_id) FROM devices d WHERE d.user_id = u.user_id) AS device_id,
           21 + FLOOR(RAND()*15000)       AS r,
           ROUND(40000 + RAND()*20000, 2) AS amt,
           TIMESTAMP('2026-08-12 02:15:00') + INTERVAL (u.user_id MOD 25) DAY AS t
    FROM users u
    JOIN bank_accounts ba ON ba.user_id = u.user_id
    WHERE u.user_id BETWEEN 700 AND 779
  ) x;

  INSERT INTO fraud_ground_truth (txn_id, pattern)
  SELECT txn_id, 'new_device_large' FROM transactions WHERE txn_id > v_start;

  -- -------------------------------------------------------------------
  -- 4e. MULE ACCOUNTS: receivers 901-910 are each paid by 15 different
  --     senders (users 1021-1215) on 2026-09-01
  -- -------------------------------------------------------------------
  SELECT MAX(txn_id) INTO v_start FROM transactions;

  INSERT INTO transactions
    (sender_id, sender_account_id, receiver_id, amount, txn_time, status, device_id, city)
  SELECT u.user_id, ba.account_id, 900 + m.mule,
         ROUND(1000 + RAND()*3000, 2),
         TIMESTAMP('2026-09-01 12:00:00') + INTERVAL (k.i * 7) MINUTE,
         'SUCCESS', d.device_id, u.city
  FROM (SELECT d + 1 AS mule FROM digits WHERE d < 10) m
  CROSS JOIN (SELECT i FROM
                (SELECT a.d + b.d*10 + 1 AS i FROM digits a, digits b) z
              WHERE i <= 15) k
  JOIN users u          ON u.user_id = 1000 + (m.mule * 20) + k.i
  JOIN bank_accounts ba ON ba.user_id = u.user_id
  JOIN devices d        ON d.user_id  = u.user_id;

  INSERT INTO fraud_ground_truth (txn_id, pattern)
  SELECT txn_id, 'mule' FROM transactions WHERE txn_id > v_start;

  -- -------------------------------------------------------------------
  -- 4f. NIGHT SPIKE: users 1500-1799 send 12,000-32,000 between 1 and 4 AM
  -- -------------------------------------------------------------------
  SELECT MAX(txn_id) INTO v_start FROM transactions;

  INSERT INTO transactions
    (sender_id, sender_account_id, receiver_id, amount, txn_time, status, device_id, city)
  SELECT x.user_id, x.account_id,
         IF(x.r = x.user_id, x.r + 1, x.r),
         x.amt, x.t, 'SUCCESS', x.device_id, x.city
  FROM (
    SELECT u.user_id, ba.account_id, d.device_id, u.city,
           21 + FLOOR(RAND()*15000)        AS r,
           ROUND(12000 + RAND()*20000, 2)  AS amt,
           TIMESTAMP('2026-09-10 00:00:00') + INTERVAL (u.user_id MOD 15) DAY
             + INTERVAL (60 + FLOOR(RAND()*180)) MINUTE AS t
    FROM users u
    JOIN bank_accounts ba ON ba.user_id = u.user_id
    JOIN devices d        ON d.user_id  = u.user_id
    WHERE u.user_id BETWEEN 1500 AND 1799
  ) x;

  INSERT INTO fraud_ground_truth (txn_id, pattern)
  SELECT txn_id, 'night_spike' FROM transactions WHERE txn_id > v_start;

  SELECT 'Fraud planted successfully' AS message;
END$$
DELIMITER ;

CALL sp_plant_fraud();

-- ---------------------------------------------------------------------
-- VERIFY. Expected ground truth: velocity 1206, amount_anomaly 100,
-- impossible_travel 101, new_device_large 81, mule 150, night_spike 300
-- (the extra 6, 1 and 1 are the hand-written rows from file 2)
-- ---------------------------------------------------------------------
SELECT pattern, COUNT(*) AS planted FROM fraud_ground_truth GROUP BY pattern ORDER BY pattern;
SELECT COUNT(*) AS total_ground_truth FROM fraud_ground_truth;
SELECT COUNT(*) AS total_transactions FROM transactions;
SELECT COUNT(*) AS self_payments FROM transactions WHERE sender_id = receiver_id;   -- must be 0