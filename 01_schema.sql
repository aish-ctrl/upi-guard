DROP DATABASE IF EXISTS upi_guard;
CREATE DATABASE upi_guard CHARACTER SET utf8mb4;
USE upi_guard;

CREATE TABLE users (
  user_id      INT AUTO_INCREMENT PRIMARY KEY,
  name         VARCHAR(80)  NOT NULL,
  city         VARCHAR(40)  NOT NULL,
  kyc_status   ENUM('VERIFIED','PENDING','REJECTED') NOT NULL DEFAULT 'PENDING',
  signup_date  DATE NOT NULL,
  risk_score   DECIMAL(5,2) NOT NULL DEFAULT 0,
  CONSTRAINT chk_risk CHECK (risk_score BETWEEN 0 AND 100)
);

CREATE TABLE bank_accounts (
  account_id   INT AUTO_INCREMENT PRIMARY KEY,
  user_id      INT NOT NULL,
  bank_name    VARCHAR(40) NOT NULL,
  account_type ENUM('SAVINGS','CURRENT') NOT NULL DEFAULT 'SAVINGS',
  CONSTRAINT fk_acc_user FOREIGN KEY (user_id) REFERENCES users(user_id)
);

CREATE TABLE devices (
  device_id    INT AUTO_INCREMENT PRIMARY KEY,
  user_id      INT NOT NULL,
  device_type  ENUM('ANDROID','IOS','WEB') NOT NULL,
  first_seen   DATETIME NOT NULL,
  CONSTRAINT fk_dev_user FOREIGN KEY (user_id) REFERENCES users(user_id)
);

CREATE TABLE merchants (
  merchant_id    INT AUTO_INCREMENT PRIMARY KEY,
  name           VARCHAR(80) NOT NULL,
  category       VARCHAR(40) NOT NULL,
  city           VARCHAR(40) NOT NULL,
  onboarded_date DATE NOT NULL
);

CREATE TABLE transactions (
  txn_id            BIGINT AUTO_INCREMENT PRIMARY KEY,
  sender_id         INT NOT NULL,
  sender_account_id INT NULL,
  receiver_id       INT NULL,
  merchant_id       INT NULL,
  amount            DECIMAL(12,2) NOT NULL,
  txn_time          DATETIME NOT NULL,
  status            ENUM('SUCCESS','FAILED','PENDING') NOT NULL DEFAULT 'SUCCESS',
  device_id         INT NULL,
  city              VARCHAR(40) NOT NULL,
  CONSTRAINT chk_amount CHECK (amount > 0),
  CONSTRAINT chk_target CHECK (receiver_id IS NOT NULL OR merchant_id IS NOT NULL),
  CONSTRAINT fk_t_sender   FOREIGN KEY (sender_id)         REFERENCES users(user_id),
  CONSTRAINT fk_t_receiver FOREIGN KEY (receiver_id)       REFERENCES users(user_id),
  CONSTRAINT fk_t_merchant FOREIGN KEY (merchant_id)       REFERENCES merchants(merchant_id),
  CONSTRAINT fk_t_device   FOREIGN KEY (device_id)         REFERENCES devices(device_id),
  CONSTRAINT fk_t_account  FOREIGN KEY (sender_account_id) REFERENCES bank_accounts(account_id)
);

CREATE TABLE fraud_alerts (
  alert_id   INT AUTO_INCREMENT PRIMARY KEY,
  txn_id     BIGINT NOT NULL,
  rule_name  VARCHAR(200) NOT NULL,
  risk_score INT NOT NULL,
  severity   ENUM('LOW','MEDIUM','HIGH','CRITICAL') NOT NULL,
  created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  CONSTRAINT fk_alert_txn FOREIGN KEY (txn_id) REFERENCES transactions(txn_id)
);

CREATE TABLE txn_audit_log (
  log_id    INT AUTO_INCREMENT PRIMARY KEY,
  txn_id    BIGINT NOT NULL,
  action    VARCHAR(60) NOT NULL,
  logged_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP
);

-- Ground truth for measuring precision/recall later (the 8th table)
CREATE TABLE fraud_ground_truth (
  txn_id  BIGINT PRIMARY KEY,
  pattern VARCHAR(40) NOT NULL
);

