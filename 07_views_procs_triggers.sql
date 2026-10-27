-- =====================================================================
-- 07_views_procs_triggers.sql  (UPI-Guard, MySQL 8.0 / Workbench)
-- Run AFTER 05_fraud_rules.sql (needs vw_txn_risk).
-- Safe to re-run: every object is dropped and re-created.
-- Select ALL (Cmd+A / Ctrl+A) and press the lightning bolt.
-- =====================================================================
USE upi_guard;

-- =====================================================================
-- PART 1: VIEWS
-- =====================================================================
CREATE OR REPLACE VIEW vw_high_risk_txns AS
SELECT * FROM vw_txn_risk WHERE risk_score >= 40;

CREATE OR REPLACE VIEW vw_merchant_summary AS
SELECT m.merchant_id, m.name, m.category, m.city,
       COUNT(t.txn_id)              AS txns,
       COALESCE(SUM(t.amount), 0)   AS revenue,
       ROUND(AVG(t.amount), 2)      AS avg_ticket
FROM merchants m
LEFT JOIN transactions t
       ON t.merchant_id = m.merchant_id AND t.status = 'SUCCESS'
GROUP BY m.merchant_id, m.name, m.category, m.city;

CREATE OR REPLACE VIEW vw_daily_kpis AS
SELECT DATE(txn_time)                                     AS day,
       COUNT(*)                                           AS txns,
       ROUND(SUM(amount), 2)                              AS val,
       ROUND(100 * SUM(status = 'SUCCESS') / COUNT(*), 2) AS success_pct
FROM transactions
GROUP BY DATE(txn_time);

CREATE OR REPLACE VIEW vw_alert_details AS
SELECT a.alert_id, a.txn_id, a.severity, a.risk_score, a.rule_name, a.created_at,
       t.sender_id, u.name AS sender_name, t.receiver_id, t.merchant_id,
       t.amount, t.txn_time, t.city
FROM fraud_alerts a
JOIN transactions t ON t.txn_id = a.txn_id
JOIN users u        ON u.user_id = t.sender_id;

-- =====================================================================
-- PART 2: STORED PROCEDURES
-- =====================================================================
DROP PROCEDURE IF EXISTS sp_flag_fraud_range;
DROP PROCEDURE IF EXISTS sp_flag_fraud;
DROP PROCEDURE IF EXISTS sp_user_report;

DELIMITER $$

-- Runs all rules once and writes alerts for every txn between two dates.
-- Skips transactions that already have an alert, so it is safe to re-run.
CREATE PROCEDURE sp_flag_fraud_range(IN p_from DATE, IN p_to DATE)
BEGIN
  INSERT INTO fraud_alerts (txn_id, rule_name, risk_score, severity)
  SELECT r.txn_id,
         CONCAT_WS(',',
           IF(r.f_velocity, 'VELOCITY',          NULL),
           IF(r.f_amount,   'AMOUNT_ANOMALY',    NULL),
           IF(r.f_travel,   'IMPOSSIBLE_TRAVEL', NULL),
           IF(r.f_newdev,   'NEW_DEVICE_HIGH',   NULL),
           IF(r.f_mule,     'MULE',              NULL),
           IF(r.f_night,    'NIGHT_SPIKE',       NULL)),
         r.risk_score,
         CASE WHEN r.risk_score >= 80 THEN 'CRITICAL'
              WHEN r.risk_score >= 60 THEN 'HIGH'
              WHEN r.risk_score >= 40 THEN 'MEDIUM'
              ELSE 'LOW' END
  FROM vw_txn_risk r
  WHERE r.txn_time >= p_from
    AND r.txn_time <  p_to + INTERVAL 1 DAY
    AND r.risk_score >= 40
    AND NOT EXISTS (SELECT 1 FROM fraud_alerts a WHERE a.txn_id = r.txn_id);

  SELECT ROW_COUNT() AS alerts_created;
END$$

-- Single-date version (what the project plan calls sp_flag_fraud @date)
CREATE PROCEDURE sp_flag_fraud(IN p_date DATE)
BEGIN
  CALL sp_flag_fraud_range(p_date, p_date);
END$$

-- Full risk profile of one user (returns 5 result sets)
CREATE PROCEDURE sp_user_report(IN p_user_id INT)
BEGIN
  -- 1. who
  SELECT u.user_id, u.name, u.city, u.kyc_status, u.signup_date
  FROM users u WHERE u.user_id = p_user_id;

  -- 2. activity summary
  SELECT COUNT(*)                  AS total_txns,
         ROUND(SUM(amount), 2)     AS total_value,
         ROUND(AVG(amount), 2)     AS avg_amount,
         MAX(amount)               AS max_amount,
         SUM(status = 'FAILED')    AS failed_txns,
         MIN(txn_time)             AS first_txn,
         MAX(txn_time)             AS last_txn
  FROM transactions WHERE sender_id = p_user_id;

  -- 3. fraud alerts on this user's transactions
  SELECT a.alert_id, a.txn_id, a.rule_name, a.risk_score, a.severity, t.amount, t.txn_time
  FROM fraud_alerts a
  JOIN transactions t ON t.txn_id = a.txn_id
  WHERE t.sender_id = p_user_id
  ORDER BY t.txn_time;

  -- 4. devices
  SELECT device_id, device_type, first_seen
  FROM devices WHERE user_id = p_user_id ORDER BY first_seen;

  -- 5. latest 10 transactions
  SELECT txn_id, amount, txn_time, status, city, merchant_id, receiver_id
  FROM transactions WHERE sender_id = p_user_id
  ORDER BY txn_time DESC LIMIT 10;
END$$

-- =====================================================================
-- PART 3: TRIGGERS
-- =====================================================================
DROP TRIGGER IF EXISTS trg_large_txn$$
DROP TRIGGER IF EXISTS trg_block_self_payment$$
DROP TRIGGER IF EXISTS trg_status_change$$

-- Large transaction (>= 50,000): write an audit row and raise an alert
CREATE TRIGGER trg_large_txn
AFTER INSERT ON transactions
FOR EACH ROW
BEGIN
  IF NEW.amount >= 50000 THEN
    INSERT INTO txn_audit_log (txn_id, action)
    VALUES (NEW.txn_id, 'LARGE_TXN_INSERTED');

    INSERT INTO fraud_alerts (txn_id, rule_name, risk_score, severity)
    VALUES (NEW.txn_id, 'TRIGGER_LARGE_AMOUNT', 50, 'MEDIUM');
  END IF;
END$$

-- Reject a payment from a user to themselves
CREATE TRIGGER trg_block_self_payment
BEFORE INSERT ON transactions
FOR EACH ROW
BEGIN
  IF NEW.receiver_id IS NOT NULL AND NEW.receiver_id = NEW.sender_id THEN
    SIGNAL SQLSTATE '45000'
      SET MESSAGE_TEXT = 'Sender and receiver cannot be the same user';
  END IF;
END$$

-- Audit every status change (e.g. PENDING -> SUCCESS)
CREATE TRIGGER trg_status_change
AFTER UPDATE ON transactions
FOR EACH ROW
BEGIN
  IF NEW.status <> OLD.status THEN
    INSERT INTO txn_audit_log (txn_id, action)
    VALUES (NEW.txn_id, CONCAT('STATUS_', OLD.status, '_TO_', NEW.status));
  END IF;
END$$

DELIMITER ;

-- =====================================================================
-- PART 4: RUN AND TEST
-- =====================================================================

-- 4a. Flag fraud for the whole period in ONE call (takes a few seconds)
CALL sp_flag_fraud_range('2026-01-01', '2026-12-31');

-- 4b. Or flag a single day (this day was already flagged above, so 0 new alerts)
CALL sp_flag_fraud('2026-05-10');

-- 4c. Alerts by severity and by rule
SELECT severity, COUNT(*) AS alerts FROM fraud_alerts GROUP BY severity
ORDER BY FIELD(severity, 'CRITICAL', 'HIGH', 'MEDIUM', 'LOW');

SELECT rule_name, COUNT(*) AS alerts FROM fraud_alerts
GROUP BY rule_name ORDER BY alerts DESC;

-- 4d. User report for the velocity-fraud user from file 2 (user 2)
CALL sp_user_report(2);

-- 4e. Views in action
SELECT * FROM vw_alert_details ORDER BY risk_score DESC, amount DESC LIMIT 10;
SELECT * FROM vw_merchant_summary ORDER BY revenue DESC LIMIT 10;
SELECT * FROM vw_daily_kpis ORDER BY day LIMIT 10;
SELECT COUNT(*) AS high_risk_txns FROM vw_high_risk_txns;

-- 4f. Test the triggers inside a transaction, then ROLLBACK so nothing is kept
START TRANSACTION;

  -- large txn: should create 1 audit row + 1 TRIGGER_LARGE_AMOUNT alert
  INSERT INTO transactions (sender_id, sender_account_id, receiver_id, amount, txn_time, city)
  VALUES (4, 4, 5, 75000, '2026-10-01 10:00:00', 'Chennai');
  SET @new_id = LAST_INSERT_ID();

  SELECT * FROM txn_audit_log WHERE txn_id = @new_id;
  SELECT alert_id, txn_id, rule_name, severity FROM fraud_alerts WHERE txn_id = @new_id;

  -- status change: should add a STATUS_SUCCESS_TO_FAILED audit row
  UPDATE transactions SET status = 'FAILED' WHERE txn_id = @new_id;
  SELECT * FROM txn_audit_log WHERE txn_id = @new_id ORDER BY log_id;

ROLLBACK;

-- after ROLLBACK the test txn, its alert and its audit rows are gone
SELECT COUNT(*) AS leftover_test_rows FROM transactions WHERE txn_id = @new_id;   -- expect 0

-- 4g. Self-payment blocker: this statement is SUPPOSED to fail with
--     "Sender and receiver cannot be the same user". Run it on its own to see the error.
-- INSERT INTO transactions (sender_id, sender_account_id, receiver_id, amount, txn_time, city)
-- VALUES (4, 4, 4, 100, '2026-10-01 10:00:00', 'Chennai');