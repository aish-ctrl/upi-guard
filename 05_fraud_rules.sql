-- =====================================================================
-- 05_fraud_rules.sql  (UPI-Guard, MySQL 8.0 / Workbench)
-- Run AFTER 04_plant_fraud.sql.
-- Part 1: the 6 rules as standalone queries (run one at a time to see results)
-- Part 2: vw_txn_risk = all rules combined into one risk score per transaction
-- Part 3: precision / recall against fraud_ground_truth
-- =====================================================================
USE upi_guard;

-- =====================================================================
-- PART 1: THE SIX RULES (each is a normal SELECT, run and screenshot them)
-- =====================================================================

-- Rule 1: VELOCITY. 5+ txns by one sender within +/-10 minutes (rolling window)
SELECT txn_id, sender_id, txn_time, cnt_window
FROM (
  SELECT txn_id, sender_id, txn_time,
         COUNT(*) OVER (PARTITION BY sender_id ORDER BY txn_time
                        RANGE BETWEEN INTERVAL 10 MINUTE PRECEDING
                                  AND INTERVAL 10 MINUTE FOLLOWING) AS cnt_window
  FROM transactions
) x
WHERE cnt_window >= 5
ORDER BY sender_id, txn_time
LIMIT 100;

-- Rule 2: AMOUNT ANOMALY. >= 10,000 and more than 5x the sender's OTHER txns
-- (the average excludes the txn itself, otherwise one huge txn hides in its own average)
SELECT txn_id, sender_id, amount, ROUND(other_avg, 2) AS usual_avg
FROM (
  SELECT txn_id, sender_id, amount,
         (SUM(amount) OVER (PARTITION BY sender_id) - amount)
           / NULLIF(COUNT(*) OVER (PARTITION BY sender_id) - 1, 0) AS other_avg
  FROM transactions
) x
WHERE amount >= 10000 AND (other_avg IS NULL OR amount > 5 * other_avg)
ORDER BY amount DESC
LIMIT 100;

-- Rule 3: IMPOSSIBLE TRAVEL. city changes within 30 minutes of the previous txn
SELECT txn_id, sender_id, prev_city, city, prev_time, txn_time,
       TIMESTAMPDIFF(MINUTE, prev_time, txn_time) AS minutes_apart
FROM (
  SELECT txn_id, sender_id, city, txn_time,
         LAG(city)     OVER (PARTITION BY sender_id ORDER BY txn_time, txn_id) AS prev_city,
         LAG(txn_time) OVER (PARTITION BY sender_id ORDER BY txn_time, txn_id) AS prev_time
  FROM transactions
) x
WHERE prev_city IS NOT NULL AND city <> prev_city
  AND TIMESTAMPDIFF(MINUTE, prev_time, txn_time) <= 30
ORDER BY txn_time
LIMIT 100;

-- Rule 4: NEW DEVICE + LARGE AMOUNT. device first seen <= 24h before an amount >= 20,000
SELECT t.txn_id, t.sender_id, t.amount, d.first_seen, t.txn_time
FROM transactions t
JOIN devices d ON d.device_id = t.device_id
WHERE t.amount >= 20000
  AND t.txn_time >= d.first_seen
  AND t.txn_time <= d.first_seen + INTERVAL 24 HOUR
ORDER BY t.txn_time
LIMIT 100;

-- Rule 5: MULE ACCOUNT. one receiver paid by 10+ different senders in a single day
SELECT receiver_id, DATE(txn_time) AS day, COUNT(DISTINCT sender_id) AS distinct_senders,
       COUNT(*) AS txns, SUM(amount) AS total_received
FROM transactions
WHERE receiver_id IS NOT NULL
GROUP BY receiver_id, DATE(txn_time)
HAVING COUNT(DISTINCT sender_id) >= 10
ORDER BY distinct_senders DESC;

-- Rule 6: NIGHT-TIME SPIKE. between 1 and 4 AM with amount >= 10,000
SELECT txn_id, sender_id, amount, txn_time
FROM transactions
WHERE HOUR(txn_time) BETWEEN 1 AND 3 AND amount >= 10000
ORDER BY txn_time
LIMIT 100;

-- =====================================================================
-- PART 2: COMBINED RISK SCORE VIEW
-- points: velocity 40, amount40, travel 45, new device 45, mule 40, night 20
-- flag a transaction when risk_score >= 40
-- =====================================================================
CREATE OR REPLACE VIEW vw_txn_risk AS
WITH base AS (
  SELECT t.txn_id, t.sender_id, t.receiver_id, t.amount, t.txn_time, t.city, t.device_id,
    COUNT(*) OVER (PARTITION BY t.sender_id ORDER BY t.txn_time
                   RANGE BETWEEN INTERVAL 10 MINUTE PRECEDING
                             AND INTERVAL 10 MINUTE FOLLOWING)             AS cnt_window,
    (SUM(t.amount) OVER (PARTITION BY t.sender_id) - t.amount)
      / NULLIF(COUNT(*) OVER (PARTITION BY t.sender_id) - 1, 0)            AS other_avg,
    LAG(t.city)     OVER (PARTITION BY t.sender_id ORDER BY t.txn_time, t.txn_id) AS prev_city,
    LAG(t.txn_time) OVER (PARTITION BY t.sender_id ORDER BY t.txn_time, t.txn_id) AS prev_time
  FROM transactions t
),
mule AS (
  SELECT receiver_id, DATE(txn_time) AS d
  FROM transactions
  WHERE receiver_id IS NOT NULL
  GROUP BY receiver_id, DATE(txn_time)
  HAVING COUNT(DISTINCT sender_id) >= 10
),
flags AS (
  SELECT b.txn_id, b.sender_id, b.receiver_id, b.amount, b.txn_time,
    (b.cnt_window >= 5)                                                  AS f_velocity,
    (b.amount >= 10000 AND (b.other_avg IS NULL OR b.amount > 5 * b.other_avg)) AS f_amount,
    (b.prev_city IS NOT NULL AND b.city <> b.prev_city
       AND TIMESTAMPDIFF(MINUTE, b.prev_time, b.txn_time) <= 30)        AS f_travel,
    (d.device_id IS NOT NULL AND b.amount >= 20000
       AND b.txn_time >= d.first_seen
       AND b.txn_time <= d.first_seen + INTERVAL 24 HOUR)               AS f_newdev,
    (m.receiver_id IS NOT NULL)                                          AS f_mule,
    (HOUR(b.txn_time) BETWEEN 1 AND 3 AND b.amount >= 10000)             AS f_night
  FROM base b
  LEFT JOIN devices d ON d.device_id = b.device_id
  LEFT JOIN mule m    ON m.receiver_id = b.receiver_id AND m.d = DATE(b.txn_time)
)
SELECT txn_id, sender_id, receiver_id, amount, txn_time,
       f_velocity, f_amount, f_travel, f_newdev, f_mule, f_night,
       ( 40*f_velocity + 40*f_amount + 45*f_travel
       + 45*f_newdev   + 40*f_mule   + 20*f_night ) AS risk_score
FROM flags;

-- look at the riskiest transactions
SELECT * FROM vw_txn_risk ORDER BY risk_score DESC, txn_time LIMIT 20;

-- how many txns land in each score band
SELECT CASE WHEN risk_score = 0  THEN '0 clean'
            WHEN risk_score < 40 THEN '1-39 low'
            WHEN risk_score < 60 THEN '40-59 medium'
            WHEN risk_score < 80 THEN '60-79 high'
            ELSE '80+ critical' END AS band,
       COUNT(*) AS txns
FROM vw_txn_risk GROUP BY band ORDER BY MIN(risk_score);

-- =====================================================================
-- PART 3: PRECISION AND RECALL (your resume numbers)
-- precision = flagged txns that really are fraud / all flagged txns
-- recall    = planted fraud that was flagged / all planted fraud
-- =====================================================================
WITH scored AS (
  SELECT r.txn_id, r.risk_score, (g.txn_id IS NOT NULL) AS is_fraud
  FROM vw_txn_risk r
  LEFT JOIN fraud_ground_truth g ON g.txn_id = r.txn_id
),
th AS (SELECT 20 AS t UNION ALL SELECT 30 UNION ALL SELECT 40
       UNION ALL SELECT 50 UNION ALL SELECT 60 UNION ALL SELECT 80)
SELECT th.t AS threshold,
       SUM(s.risk_score >= th.t)                                  AS flagged,
       SUM(s.risk_score >= th.t AND s.is_fraud)                   AS true_positives,
       SUM(s.risk_score >= th.t AND NOT s.is_fraud)               AS false_positives,
       ROUND(100 * SUM(s.risk_score >= th.t AND s.is_fraud)
                 / NULLIF(SUM(s.risk_score >= th.t), 0), 1)       AS precision_pct,
       ROUND(100 * SUM(s.risk_score >= th.t AND s.is_fraud)
                 / (SELECT COUNT(*) FROM fraud_ground_truth), 1)  AS recall_pct
FROM th CROSS JOIN scored s
GROUP BY th.t
ORDER BY th.t;

-- recall for each planted pattern at the chosen threshold (40)
SELECT g.pattern,
       COUNT(*)                                   AS planted,
       SUM(r.risk_score >= 40)                    AS caught,
       ROUND(100 * SUM(r.risk_score >= 40) / COUNT(*), 1) AS recall_pct
FROM fraud_ground_truth g
JOIN vw_txn_risk r ON r.txn_id = g.txn_id
GROUP BY g.pattern
ORDER BY g.pattern;

-- the false positives (should be zero or very few)
SELECT r.*
FROM vw_txn_risk r
LEFT JOIN fraud_ground_truth g ON g.txn_id = r.txn_id
WHERE r.risk_score >= 40 AND g.txn_id IS NULL
LIMIT 50;