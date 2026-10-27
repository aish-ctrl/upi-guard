USE upi_guard;

INSERT INTO users (name, city, kyc_status, signup_date) VALUES
('Aarav Sharma','Mumbai','VERIFIED','2025-01-10'),
('Priya Nair','Bengaluru','VERIFIED','2025-01-15'),
('Rohan Mehta','Delhi','VERIFIED','2025-02-01'),
('Sneha Iyer','Chennai','VERIFIED','2025-02-11'),
('Vikram Singh','Jaipur','PENDING','2025-03-03'),
('Ananya Das','Kolkata','VERIFIED','2025-03-09'),
('Karan Patel','Ahmedabad','VERIFIED','2025-03-20'),
('Neha Reddy','Hyderabad','VERIFIED','2025-04-02'),
('Arjun Gupta','Pune','VERIFIED','2025-04-18'),
('Divya Menon','Kochi','VERIFIED','2025-05-05'),
('Rahul Verma','Lucknow','REJECTED','2025-05-21'),
('Pooja Joshi','Mumbai','VERIFIED','2025-06-01'),
('Sanjay Kumar','Patna','PENDING','2025-06-14'),
('Meera Pillai','Bengaluru','VERIFIED','2025-07-02'),
('Amit Shah','Surat','VERIFIED','2025-07-19'),
('Kavya Rao','Mysuru','VERIFIED','2025-08-08'),
('Nikhil Bose','Kolkata','VERIFIED','2025-08-25'),
('Ishita Kapoor','Delhi','VERIFIED','2025-09-12'),
('Manoj Tiwari','Varanasi','PENDING','2025-09-30'),
('Tanvi Desai','Pune','VERIFIED','2025-10-10');

INSERT INTO bank_accounts (user_id, bank_name, account_type) VALUES
(1,'SBI','SAVINGS'),(2,'HDFC','SAVINGS'),(3,'ICICI','SAVINGS'),(4,'Axis','SAVINGS'),
(5,'SBI','SAVINGS'),(6,'PNB','SAVINGS'),(7,'HDFC','CURRENT'),(8,'ICICI','SAVINGS'),
(9,'Kotak','SAVINGS'),(10,'Canara','SAVINGS'),(11,'SBI','SAVINGS'),(12,'HDFC','SAVINGS'),
(13,'PNB','SAVINGS'),(14,'Axis','SAVINGS'),(15,'ICICI','CURRENT'),(16,'Kotak','SAVINGS'),
(17,'SBI','SAVINGS'),(18,'HDFC','SAVINGS'),(19,'Canara','SAVINGS'),(20,'Axis','SAVINGS');

INSERT INTO devices (user_id, device_type, first_seen) VALUES
(1,'ANDROID','2025-01-10 10:00:00'),(2,'IOS','2025-01-15 11:00:00'),
(3,'ANDROID','2025-02-01 09:30:00'),(4,'ANDROID','2025-02-11 14:00:00'),
(5,'WEB','2025-03-03 16:00:00'),(6,'IOS','2025-03-09 12:00:00'),
(7,'ANDROID','2025-03-20 18:00:00'),(8,'ANDROID','2025-04-02 08:00:00'),
(9,'IOS','2025-04-18 19:00:00'),(10,'ANDROID','2025-05-05 20:00:00'),
(1,'ANDROID','2026-03-01 02:00:00'),   -- new device for user 1 (device_id 11)
(3,'WEB','2026-03-02 01:30:00');       -- new device for user 3 (device_id 12)

INSERT INTO merchants (name, category, city, onboarded_date) VALUES
('Big Bazaar Mart','Grocery','Mumbai','2024-01-01'),
('Spice Route Cafe','Food','Bengaluru','2024-02-10'),
('QuickCab','Transport','Delhi','2024-03-05'),
('TechZone Electronics','Electronics','Chennai','2024-04-12'),
('StyleHub','Fashion','Hyderabad','2024-05-20'),
('MediCare Pharmacy','Health','Pune','2024-06-15'),
('CineMax','Entertainment','Mumbai','2024-07-01'),
('FuelUp Station','Fuel','Jaipur','2024-08-09'),
('BookNest','Books','Kolkata','2024-09-18'),
('GreenGrocer','Grocery','Kochi','2024-10-30');

-- 10 normal transactions
INSERT INTO transactions (sender_id, sender_account_id, merchant_id, receiver_id, amount, txn_time, status, device_id, city) VALUES
(1,1,1,NULL,450.00,'2026-03-01 10:15:00','SUCCESS',1,'Mumbai'),
(1,1,2,NULL,320.00,'2026-03-01 13:05:00','SUCCESS',1,'Mumbai'),
(2,2,2,NULL,280.00,'2026-03-01 09:40:00','SUCCESS',2,'Bengaluru'),
(3,3,3,NULL,150.00,'2026-03-01 08:20:00','SUCCESS',3,'Delhi'),
(4,4,4,NULL,2200.00,'2026-03-02 17:30:00','SUCCESS',4,'Chennai'),
(5,5,NULL,6,500.00,'2026-03-02 12:00:00','SUCCESS',5,'Jaipur'),
(6,6,5,NULL,1800.00,'2026-03-02 19:45:00','FAILED',6,'Kolkata'),
(7,7,6,NULL,640.00,'2026-03-03 11:10:00','SUCCESS',7,'Ahmedabad'),
(8,8,7,NULL,500.00,'2026-03-03 20:00:00','SUCCESS',8,'Hyderabad'),
(9,9,8,NULL,1500.00,'2026-03-03 15:25:00','SUCCESS',9,'Pune');

-- 9 planted fraud transactions: velocity burst (user 2, 6 txns in 5 min) + big amount + impossible travel
INSERT INTO transactions (sender_id, sender_account_id, merchant_id, receiver_id, amount, txn_time, status, device_id, city) VALUES
(2,2,NULL,12,99.00,'2026-03-05 14:00:00','SUCCESS',2,'Bengaluru'),
(2,2,NULL,12,99.00,'2026-03-05 14:01:00','SUCCESS',2,'Bengaluru'),
(2,2,NULL,12,99.00,'2026-03-05 14:02:00','SUCCESS',2,'Bengaluru'),
(2,2,NULL,12,99.00,'2026-03-05 14:03:00','SUCCESS',2,'Bengaluru'),
(2,2,NULL,12,99.00,'2026-03-05 14:04:00','SUCCESS',2,'Bengaluru'),
(2,2,NULL,12,99.00,'2026-03-05 14:05:00','SUCCESS',2,'Bengaluru'),
(3,3,NULL,13,95000.00,'2026-03-06 02:10:00','SUCCESS',12,'Delhi'),   -- new device + huge + night
(1,1,NULL,14,1200.00,'2026-03-06 12:20:00','SUCCESS',1,'Delhi');     -- Delhi txn 5 min after the Mumbai one below
INSERT INTO transactions (sender_id, sender_account_id, merchant_id, receiver_id, amount, txn_time, status, device_id, city) VALUES
(1,1,NULL,15,800.00,'2026-03-06 12:15:00','SUCCESS',1,'Mumbai');

-- Record the planted ones in ground truth
INSERT INTO fraud_ground_truth (txn_id, pattern)
SELECT txn_id, 'velocity' FROM transactions WHERE sender_id=2 AND txn_time BETWEEN '2026-03-05 14:00:00' AND '2026-03-05 14:05:00';
INSERT INTO fraud_ground_truth (txn_id, pattern)
SELECT txn_id, 'new_device_large' FROM transactions WHERE amount=95000.00;
INSERT INTO fraud_ground_truth (txn_id, pattern)
SELECT txn_id, 'impossible_travel' FROM transactions WHERE sender_id=1 AND city='Delhi' AND txn_time='2026-03-06 12:20:00';

-- CHECK: expect users 20, accounts 20, devices 12, merchants 10, transactions 19, ground truth 8
SELECT (SELECT COUNT(*) FROM users)              AS users,
       (SELECT COUNT(*) FROM bank_accounts)      AS accounts,
       (SELECT COUNT(*) FROM devices)            AS devices,
       (SELECT COUNT(*) FROM merchants)          AS merchants,
       (SELECT COUNT(*) FROM transactions)       AS txns,
       (SELECT COUNT(*) FROM fraud_ground_truth) AS ground_truth;