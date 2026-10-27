# UPI-Guard | UPI Transaction Fraud Detection & Analytics

**A SQL-powered fraud detection and transaction analytics project built with MySQL 8.0+.**

<p align="center">
  <strong>Database Engineering · Fraud Detection · Risk Scoring · Query Optimization</strong>
</p>

---

## Overview

UPI-Guard is a relational database project that simulates a Unified Payments Interface (UPI) transaction environment and applies SQL-based rules to identify potentially suspicious payment activity.

The project demonstrates how database design, transaction analysis, fraud-rule evaluation, risk scoring, and query optimization can work together in a payment-monitoring workflow. It uses synthetic transaction data to explore fraud patterns and generate alerts for further investigation.

The goal is to demonstrate practical SQL and database engineering skills through an end-to-end, reproducible project.

## Key Features

- **Relational database design:** Structured tables, primary keys, foreign keys, and data integrity constraints.
- **Transaction data generation:** Synthetic payment records for testing analytical queries and fraud scenarios.
- **Rule-based fraud detection:** Identification of suspicious transaction velocity, unusual amounts, impossible travel, new-device high-value activity, potential mule accounts, and nighttime transaction spikes.
- **Risk scoring and alert classification:** Rule-based risk scores and severity levels to prioritize suspicious transactions.
- **Advanced SQL analytics:** Common Table Expressions (CTEs), window functions, joins, aggregations, and date-based analysis.
- **Reusable database objects:** Views and stored procedures for reporting and fraud-alert generation.
- **Audit logging:** Triggers to record selected transaction events and status changes.
- **Performance optimization:** Composite indexes, `EXPLAIN ANALYZE`, execution-plan comparisons, and a monthly partitioning experiment.

## Technology Stack

| Technology | Purpose |
|---|---|
| MySQL 8.0+ | Database engine and SQL processing |
| MySQL Workbench | Database development, querying, and visualization |
| SQL | Data manipulation, fraud rules, analytics, and automation |
| Git & GitHub | Version control and project documentation |

## System Architecture

```text
Synthetic Transaction Data
            |
            v
   MySQL Relational Database
            |
            v
 Data Validation & Preparation
            |
            v
    Fraud Detection Rules
            |
            v
    Risk Scoring & Alerts
            |
            v
 Transaction Analytics & Reports
            |
            v
 Indexing & Performance Evaluation
```

## Database Design

The database is organized around eight core tables.

| Table | Responsibility |
|---|---|
| `users` | User profiles, KYC status, and risk scores |
| `bank_accounts` | Bank accounts associated with users |
| `devices` | Devices registered or observed for users |
| `merchants` | Merchant profiles and categories |
| `transactions` | Payment transaction records |
| `fraud_alerts` | Suspicious transactions and associated alerts |
| `txn_audit_log` | Selected transaction events and status changes |
| `fraud_ground_truth` | Known synthetic fraud labels for evaluation |

**ER diagram:** Add your exported MySQL Workbench diagram to `screenshots/upi_guard_er_diagram.png` and display it here:

```markdown
![UPI-Guard ER Diagram](screenshots/upi_guard_er_diagram.png)
```

## Fraud Detection Scenarios

UPI-Guard explores six synthetic fraud patterns using SQL-based detection rules.

| Fraud pattern | Detection objective |
|---|---|
| Velocity burst | Identify unusually frequent transactions within a short time window |
| Amount anomaly | Flag transactions with unusually high amounts |
| Impossible travel | Identify transactions associated with suspicious location changes |
| New device + high value | Flag high-value activity from a newly observed device |
| Potential mule activity | Investigate accounts receiving transactions from multiple senders |
| Nighttime spike | Identify unusual transaction activity during nighttime hours |

These rules are designed for learning and experimentation. A flagged transaction is a candidate for investigation, not proof of fraud.

## SQL Concepts Demonstrated

### Database Development
- `CREATE DATABASE` and `CREATE TABLE`
- Primary keys, foreign keys, and `CHECK` constraints
- `INSERT`, `UPDATE`, and `DELETE`
- Joins, filtering, sorting, and aggregation
- Views and stored procedures
- Triggers and audit logging

### Fraud Analytics
- CTEs and recursive CTEs
- Window functions such as `LAG()` and rolling-window calculations
- Conditional expressions using `CASE`
- Date and time calculations
- Rule-based risk scoring
- Evaluation against synthetic ground-truth labels

### Performance Engineering
- Composite indexes such as `(sender_id, txn_time)`
- Query-plan inspection using `EXPLAIN ANALYZE`
- Correlated-subquery versus window-function comparisons
- Receiver-, merchant-, and timestamp-based index experiments
- Monthly range partitioning on a separate experimental table

## Project Structure

```text
upi-guard/
├── README.md
├── 01_schema.sql
├── 02_seed_manual.sql
├── 03_data_generation.sql
├── 04_plant_fraud.sql
├── 05_fraud_rules.sql
├── 06_analytics.sql
├── 07_views_procs_triggers.sql
├── 08_indexing_performance.sql
└── screenshots/
    ├── upi_guard_er_diagram.png
    ├── fraud_alerts.png
    ├── analytics_results.png
    ├── query_plan_before.png
    ├── query_plan_after.png
    └── partition_pruning.png
```

*The screenshots folder is a suggested structure. Add each image after capturing it in MySQL Workbench.*

## Getting Started

### Prerequisites

- MySQL Server 8.0 or later
- MySQL Workbench
- A GitHub account (optional, for version control)

### Installation and Setup

**1. Clone the repository**

```bash
git clone https://github.com/YOUR_USERNAME/upi-guard.git
cd upi-guard
```

Replace `YOUR_USERNAME` with your GitHub username.

**2. Connect to MySQL**

Open MySQL Workbench and connect to your local MySQL server.

**3. Execute the SQL files in order**

Run the scripts in the following sequence:

| Order | File | Purpose |
|---|---|---|
| 1 | `01_schema.sql` | Create the database and tables |
| 2 | `02_seed_manual.sql` | Insert initial seed data |
| 3 | `03_data_generation.sql` | Generate additional synthetic data |
| 4 | `04_plant_fraud.sql` | Insert controlled fraud scenarios and labels |
| 5 | `05_fraud_rules.sql` | Define fraud detection rules |
| 6 | `06_analytics.sql` | Run analytical queries and evaluation |
| 7 | `07_views_procs_triggers.sql` | Create views, procedures, and triggers |
| 8 | `08_indexing_performance.sql` | Evaluate query performance and indexes |

**Important:** Run these scripts against a test database. Check the contents before execution because setup scripts may recreate objects or insert large volumes of data. Some scripts depend on data generated by earlier steps.

### Verify the Database

After setup, you can inspect the main tables:

```sql
USE upi_guard;

SHOW TABLES;

SELECT COUNT(*) AS total_transactions
FROM transactions;

SELECT *
FROM fraud_alerts
ORDER BY created_at DESC
LIMIT 10;
```

## Performance Evaluation

The project investigates how index selection and query design affect transaction-analysis performance.

The primary comparison uses a correlated subquery before and after creating a composite index on `(sender_id, txn_time)`, followed by a window-function alternative.

Record actual results in the following table:

| Version | Index | Query approach | Average time (s) |
|---|---|---|---|
| A | Baseline | Correlated subquery | To be measured |
| B | `(sender_id, txn_time)` | Correlated subquery | To be measured |
| C | `(sender_id, txn_time)` | Window function | To be measured |

Run each test three times and record the average. Use `EXPLAIN ANALYZE` on supported MySQL versions and capture execution plans before and after optimization.

The partitioning experiment uses a separate copy of the transactions table so the original dataset remains available.

## Fraud Detection Evaluation

The project includes synthetic ground-truth labels to support evaluation of the rule-based detection approach.

Once the detection results are available, report precision and recall using actual measured values.

| Metric | Meaning | Result |
|---|---|---|
| Precision | Fraction of flagged transactions that are labeled as fraud | To be measured |
| Recall | Fraction of labeled fraud transactions detected by the rules | To be measured |
| Transactions analyzed | Number of transaction records evaluated | To be measured |
| Alerts generated | Number of fraud alerts produced | To be measured |

Do not enter assumed performance or detection figures. Results depend on the generated dataset, rule definitions, and evaluation methodology.

## Key Learning Outcomes

- Designing a normalized relational database for a payment use case.
- Writing maintainable SQL for analytical workloads.
- Translating fraud scenarios into rule-based queries.
- Using window functions and time-based calculations.
- Automating database tasks with stored procedures and triggers.
- Interpreting query execution plans and testing indexes.
- Documenting a database project for reproducibility and technical review.

## Future Improvements

- Build a dashboard for transaction trends, fraud alerts, and risk distribution.
- Add configurable fraud thresholds and rule weights.
- Evaluate precision, recall, and false-positive rates across different scenarios.
- Compare rule-based detection with machine-learning models.
- Explore incremental processing and streaming fraud detection.
- Evaluate archiving, monthly partitioning, and pre-aggregated summary tables for larger datasets.

## Limitations

UPI-Guard is an educational project built around synthetic data. Its detection rules are illustrative and are not validated for real financial transactions. The project does not connect to live UPI payment networks, bank systems, or production fraud-monitoring infrastructure.

## Author

AISHWARYA B C 


## License

Choose a license before distributing the project. For example, the MIT License permits reuse subject to its terms; add a `LICENSE` file if you choose it.

---

*UPI-Guard demonstrates the application of SQL, relational database design, fraud analytics, and query optimization to a simulated digital payments environment.*
