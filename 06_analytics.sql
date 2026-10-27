-- =====================================================================
-- 06_analytics.sql  (UPI-Guard, MySQL 8.0 / Workbench)
-- Business-side analytics. Run AFTER 05_fraud_rules.sql (needs vw_txn_risk
-- only for query 13). Run each query on its own (click inside it, press
-- Cmd+Enter / Ctrl+Enter) and screenshot the result grids for your README.
-- =====================================================================
USE upi_guard;

-- ---------------------------------------------------------------------
-- 1. Headline KPIs
-- ---------------------------------------------------------------------
SELECT COUNT(*)                                        AS total_txns,
       SUM(status = 'SUCCESS')                         AS successful,
       ROUND(100 * SUM(status = 'SUCCESS') / COUNT(*), 2) AS success_rate_pct,
       ROUND(SUM(CASE WHEN status = 'SUCCESS' THEN amount END), 2) AS total_value,
       ROUND(AVG(CASE WHEN status = 'SUCCESS' THEN amount END), 2) AS avg_ticket,
       COUNT(DISTINCT sender_id)                       AS active_senders
FROM transactions;

-- ---------------------------------------------------------------------
-- 2. Daily volume and value (first 60 days shown)
-- ---------------------------------------------------------------------
SELECT DATE(txn_time) AS day,
       COUNT(*)       AS txns,
       ROUND(SUM(amount), 2) AS value
FROM transactions
WHERE status = 'SUCCESS'
GROUP BY DATE(txn_time)
ORDER BY day
LIMIT 60;

-- ---------------------------------------------------------------------
-- 3. Weekly volume and value
-- ---------------------------------------------------------------------
SELECT YEARWEEK(txn_time, 1) AS year_week,
       MIN(DATE(txn_time))   AS week_start_seen,
       COUNT(*)              AS txns,
       ROUND(SUM(amount), 2) AS value
FROM transactions
WHERE status = 'SUCCESS'
GROUP BY YEARWEEK(txn_time, 1)
ORDER BY year_week;

-- ---------------------------------------------------------------------
-- 4. Monthly volume + month-over-month growth (LAG)
-- ---------------------------------------------------------------------
WITH monthly AS (
  SELECT DATE_FORMAT(txn_time, '%Y-%m') AS ym,
         COUNT(*)              AS txns,
         ROUND(SUM(amount), 2) AS val
  FROM transactions
  WHERE status = 'SUCCESS'
  GROUP BY DATE_FORMAT(txn_time, '%Y-%m')
)
SELECT ym, txns, val,
       LAG(val) OVER (ORDER BY ym) AS prev_month_val,
       ROUND(100 * (val - LAG(val) OVER (ORDER BY ym))
                 / LAG(val) OVER (ORDER BY ym), 2) AS mom_growth_pct
FROM monthly
ORDER BY ym;

-- ---------------------------------------------------------------------
-- 5. Running total of daily value (window SUM)
-- ---------------------------------------------------------------------
SELECT day, val,
       ROUND(SUM(val) OVER (ORDER BY day), 2) AS running_total
FROM (
  SELECT DATE(txn_time) AS day, SUM(amount) AS val
  FROM transactions
  WHERE status = 'SUCCESS'
  GROUP BY DATE(txn_time)
) d
ORDER BY day
LIMIT 60;

-- ---------------------------------------------------------------------
-- 6. Top 10 merchants per category (DENSE_RANK)
-- ---------------------------------------------------------------------
SELECT category, name AS merchant, revenue, txns, rnk
FROM (
  SELECT m.category, m.name,
         ROUND(SUM(t.amount), 2) AS revenue,
         COUNT(*)                AS txns,
         DENSE_RANK() OVER (PARTITION BY m.category ORDER BY SUM(t.amount) DESC) AS rnk
  FROM transactions t
  JOIN merchants m ON m.merchant_id = t.merchant_id
  WHERE t.status = 'SUCCESS'
  GROUP BY m.category, m.merchant_id, m.name
) x
WHERE rnk <= 10
ORDER BY category, rnk;

-- ---------------------------------------------------------------------
-- 7. Revenue by merchant category
-- ---------------------------------------------------------------------
SELECT m.category,
       COUNT(*)                AS txns,
       ROUND(SUM(t.amount), 2) AS revenue,
       ROUND(AVG(t.amount), 2) AS avg_ticket,
       ROUND(100 * SUM(t.amount) / SUM(SUM(t.amount)) OVER (), 1) AS share_pct
FROM transactions t
JOIN merchants m ON m.merchant_id = t.merchant_id
WHERE t.status = 'SUCCESS'
GROUP BY m.category
ORDER BY revenue DESC;

-- ---------------------------------------------------------------------
-- 8. Success vs failure rate per bank
-- ---------------------------------------------------------------------
SELECT ba.bank_name,
       COUNT(*) AS total,
       ROUND(100 * SUM(t.status = 'SUCCESS') / COUNT(*), 2) AS success_pct,
       ROUND(100 * SUM(t.status = 'FAILED')  / COUNT(*), 2) AS failure_pct,
       ROUND(100 * SUM(t.status = 'PENDING') / COUNT(*), 2) AS pending_pct
FROM transactions t
JOIN bank_accounts ba ON ba.account_id = t.sender_account_id
GROUP BY ba.bank_name
ORDER BY success_pct DESC;

-- ---------------------------------------------------------------------
-- 9. Customer segments by spend (NTILE quartiles)
--    segment 1 = top 25% spenders ... segment 4 = bottom 25%
-- ---------------------------------------------------------------------
WITH spend AS (
  SELECT sender_id, SUM(amount) AS total_spend, COUNT(*) AS txns
  FROM transactions
  WHERE status = 'SUCCESS'
  GROUP BY sender_id
),
seg AS (
  SELECT sender_id, total_spend, txns,
         NTILE(4) OVER (ORDER BY total_spend DESC) AS segment
  FROM spend
)
SELECT segment,
       COUNT(*)                     AS customers,
       ROUND(MIN(total_spend), 2)   AS min_spend,
       ROUND(MAX(total_spend), 2)   AS max_spend,
       ROUND(AVG(total_spend), 2)   AS avg_spend,
       ROUND(SUM(total_spend), 2)   AS segment_value
FROM seg
GROUP BY segment
ORDER BY segment;

-- ---------------------------------------------------------------------
-- 10. Retention: of users whose first txn happened in a month, how many
--     transacted again the following month (cohort retention)
-- ---------------------------------------------------------------------
WITH first_month AS (
  SELECT sender_id, DATE_FORMAT(MIN(txn_time), '%Y-%m') AS cohort
  FROM transactions
  GROUP BY sender_id
),
activity AS (
  SELECT DISTINCT sender_id, DATE_FORMAT(txn_time, '%Y-%m') AS ym
  FROM transactions
)
SELECT f.cohort,
       COUNT(DISTINCT f.sender_id) AS cohort_users,
       COUNT(DISTINCT a.sender_id) AS back_next_month,
       ROUND(100 * COUNT(DISTINCT a.sender_id) / COUNT(DISTINCT f.sender_id), 1) AS retention_pct
FROM first_month f
LEFT JOIN activity a
       ON a.sender_id = f.sender_id
      AND a.ym = DATE_FORMAT(STR_TO_DATE(CONCAT(f.cohort, '-01'), '%Y-%m-%d') + INTERVAL 1 MONTH, '%Y-%m')
WHERE f.cohort < (SELECT DATE_FORMAT(MAX(txn_time), '%Y-%m') FROM transactions)  -- last month has no "next month" yet
GROUP BY f.cohort
ORDER BY f.cohort;

-- ---------------------------------------------------------------------
-- 11. Peak-hour heatmap data (day of week x hour of day)
--     paste into Excel / Power BI as a heatmap
-- ---------------------------------------------------------------------
SELECT DAYNAME(txn_time)   AS day_name,
       HOUR(txn_time)      AS hour_of_day,
       COUNT(*)            AS txns
FROM transactions
GROUP BY DAYOFWEEK(txn_time), DAYNAME(txn_time), HOUR(txn_time)
ORDER BY DAYOFWEEK(txn_time), HOUR(txn_time);

-- busiest 5 hours overall
SELECT HOUR(txn_time) AS hour_of_day, COUNT(*) AS txns,
       ROUND(AVG(amount), 2) AS avg_amount
FROM transactions
GROUP BY HOUR(txn_time)
ORDER BY txns DESC
LIMIT 5;

-- ---------------------------------------------------------------------
-- 12. Transactions by city and by device type
-- ---------------------------------------------------------------------
SELECT city, COUNT(*) AS txns, ROUND(SUM(amount), 2) AS value
FROM transactions
GROUP BY city
ORDER BY txns DESC;

SELECT d.device_type, COUNT(*) AS txns, ROUND(AVG(t.amount), 2) AS avg_amount,
       ROUND(100 * SUM(t.status = 'FAILED') / COUNT(*), 2) AS failure_pct
FROM transactions t
JOIN devices d ON d.device_id = t.device_id
GROUP BY d.device_type
ORDER BY txns DESC;

-- ---------------------------------------------------------------------
-- 13. Fraud overview (uses the risk view from file 5)
-- ---------------------------------------------------------------------
SELECT DATE_FORMAT(txn_time, '%Y-%m') AS ym,
       COUNT(*)                        AS txns,
       SUM(risk_score >= 40)           AS flagged,
       ROUND(100 * SUM(risk_score >= 40) / COUNT(*), 2) AS flagged_pct,
       ROUND(SUM(CASE WHEN risk_score >= 40 THEN amount END), 2) AS flagged_value
FROM vw_txn_risk
GROUP BY DATE_FORMAT(txn_time, '%Y-%m')
ORDER BY ym;