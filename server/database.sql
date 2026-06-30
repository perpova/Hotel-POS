-- Restaurant POS System Database Schema
-- Optimized for LAN-first Local + VPS Sync

CREATE DATABASE IF NOT EXISTS hotel_pos;
USE hotel_pos;

-- 1. Multiple User Levels (Admin, Cashier, Owner, Kitchen, Delivery)
CREATE TABLE IF NOT EXISTS users (
    id INT AUTO_INCREMENT PRIMARY KEY,
    name VARCHAR(100) NOT NULL,
    username VARCHAR(50) UNIQUE NOT NULL,
    password_hash VARCHAR(255) NOT NULL,
    role ENUM('admin', 'cashier', 'owner', 'kitchen', 'delivery') NOT NULL,
    status ENUM('active', 'inactive') DEFAULT 'active',
    image_base64 LONGTEXT NULL,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- 2. Product Categories
CREATE TABLE IF NOT EXISTS categories (
    id INT AUTO_INCREMENT PRIMARY KEY,
    name VARCHAR(100) NOT NULL,
    parent_id INT NULL,
    status ENUM('active', 'inactive') DEFAULT 'active',
    image_base64 LONGTEXT NULL,
    FOREIGN KEY (parent_id) REFERENCES categories(id) ON DELETE SET NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- 3. Product Catalog with Sinhala support & Stock levels
CREATE TABLE IF NOT EXISTS products (
    id INT AUTO_INCREMENT PRIMARY KEY,
    name VARCHAR(255) NOT NULL,
    sinhala_name VARCHAR(255) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci DEFAULT NULL,
    description TEXT,
    category_id INT NOT NULL,
    price DECIMAL(10,2) NOT NULL,
    cost DECIMAL(10,2) NOT NULL,
    barcode VARCHAR(100) UNIQUE DEFAULT NULL,
    stock_qty INT DEFAULT 0,
    min_stock_level INT DEFAULT 10,
    is_short_eat BOOLEAN DEFAULT FALSE,
    image_base64 LONGTEXT NULL,
    status ENUM('active', 'inactive') DEFAULT 'active',
    item_type VARCHAR(50) DEFAULT 'Veg',
    tax DECIMAL(10,2) DEFAULT 0.00,
    is_featured BOOLEAN DEFAULT FALSE,
    caution TEXT,
    has_sizes BOOLEAN DEFAULT FALSE,
    has_extras BOOLEAN DEFAULT FALSE,
    has_addons BOOLEAN DEFAULT FALSE,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (category_id) REFERENCES categories(id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- 4. Happy Hour Pricing (Promotions & Time-based pricing)
CREATE TABLE IF NOT EXISTS happy_hour_pricing (
    id INT AUTO_INCREMENT PRIMARY KEY,
    product_id INT NOT NULL,
    promo_price DECIMAL(10,2) NOT NULL,
    start_time TIME NOT NULL,
    end_time TIME NOT NULL,
    days_of_week VARCHAR(50) DEFAULT '1,2,3,4,5,6,7', -- Comma-separated days (1=Mon, 7=Sun)
    status ENUM('active', 'inactive') DEFAULT 'active',
    FOREIGN KEY (product_id) REFERENCES products(id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- 5. Table Management
CREATE TABLE IF NOT EXISTS dining_tables (
    id INT AUTO_INCREMENT PRIMARY KEY,
    table_number VARCHAR(10) NOT NULL UNIQUE,
    capacity INT DEFAULT 4,
    status ENUM('empty', 'seated', 'billing') DEFAULT 'empty',
    current_order_id INT NULL,
    steward_name VARCHAR(100) DEFAULT NULL,
    active_status VARCHAR(50) DEFAULT 'active'
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- 6. Customer Database (Birthdays, Credit limits)
CREATE TABLE IF NOT EXISTS customers (
    id INT AUTO_INCREMENT PRIMARY KEY,
    name VARCHAR(100) NOT NULL,
    phone VARCHAR(20) UNIQUE NOT NULL,
    birthday DATE DEFAULT NULL,
    favorite_items VARCHAR(255) DEFAULT NULL,
    credit_limit DECIMAL(10,2) DEFAULT 0.00,
    outstanding_balance DECIMAL(10,2) DEFAULT 0.00,
    image_base64 LONGTEXT NULL,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- 7. Shifts & Cash Drawer Reconciliation
CREATE TABLE IF NOT EXISTS shifts (
    id INT AUTO_INCREMENT PRIMARY KEY,
    user_id INT NOT NULL,
    start_time TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    end_time TIMESTAMP NULL DEFAULT NULL,
    opening_balance DECIMAL(10,2) NOT NULL,
    closing_balance DECIMAL(10,2) DEFAULT 0.00,
    actual_closing_balance DECIMAL(10,2) DEFAULT 0.00,
    status ENUM('open', 'closed') DEFAULT 'open',
    FOREIGN KEY (user_id) REFERENCES users(id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- 8. Cash Drawer Control (Track drawer ins/outs)
CREATE TABLE IF NOT EXISTS cash_drawer_logs (
    id INT AUTO_INCREMENT PRIMARY KEY,
    shift_id INT NOT NULL,
    type ENUM('cash_in', 'cash_out') NOT NULL,
    amount DECIMAL(10,2) NOT NULL,
    reason VARCHAR(255) NOT NULL,
    timestamp TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (shift_id) REFERENCES shifts(id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- 9. Orders (Supports Dine-In, Takeaway, Delivery, and Credit settlements)
CREATE TABLE IF NOT EXISTS orders (
    id INT AUTO_INCREMENT PRIMARY KEY,
    order_number VARCHAR(50) UNIQUE NOT NULL,
    table_id INT DEFAULT NULL,
    order_type ENUM('dine_in', 'takeaway', 'delivery') NOT NULL,
    delivery_platform ENUM('uber_eats', 'pickme', 'phone', 'direct') DEFAULT NULL,
    customer_id INT DEFAULT NULL,
    steward_name VARCHAR(100) DEFAULT NULL,
    status ENUM('pending', 'preparing', 'prepared', 'out_for_delivery', 'delivered', 'cancelled', 'returned', 'rejected') DEFAULT 'pending',
    payment_status ENUM('unpaid', 'paid') DEFAULT 'unpaid',
    payment_method ENUM('cash', 'credit', 'card', 'qr') DEFAULT NULL,
    subtotal DECIMAL(10,2) NOT NULL,
    discount DECIMAL(10,2) DEFAULT 0.00,
    total DECIMAL(10,2) NOT NULL,
    cashier_id INT NOT NULL,
    shift_id INT NOT NULL,
    kot_printed BOOLEAN DEFAULT FALSE,
    ack_printed BOOLEAN DEFAULT FALSE,
    card_tx_reference VARCHAR(100) DEFAULT NULL,
    barcode VARCHAR(100) UNIQUE DEFAULT NULL,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    sync_status ENUM('synced', 'pending') DEFAULT 'synced',
    FOREIGN KEY (table_id) REFERENCES dining_tables(id),
    FOREIGN KEY (customer_id) REFERENCES customers(id),
    FOREIGN KEY (cashier_id) REFERENCES users(id),
    FOREIGN KEY (shift_id) REFERENCES shifts(id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- 10. Order Items
CREATE TABLE IF NOT EXISTS order_items (
    id INT AUTO_INCREMENT PRIMARY KEY,
    order_id INT NOT NULL,
    product_id INT NOT NULL,
    quantity INT NOT NULL,
    price DECIMAL(10,2) NOT NULL, -- price sold at (inc happy hour)
    notes VARCHAR(255) DEFAULT NULL, -- order notes like "no chili"
    status ENUM('pending', 'preparing', 'completed') DEFAULT 'pending',
    FOREIGN KEY (order_id) REFERENCES orders(id) ON DELETE CASCADE,
    FOREIGN KEY (product_id) REFERENCES products(id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- 11. Credit settlements (Nearby shop owners & weekly settle)
CREATE TABLE IF NOT EXISTS credit_settlements (
    id INT AUTO_INCREMENT PRIMARY KEY,
    customer_id INT NOT NULL,
    amount DECIMAL(10,2) NOT NULL,
    payment_method ENUM('cash', 'card', 'qr') NOT NULL,
    date_paid TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    recorded_by INT NOT NULL,
    FOREIGN KEY (customer_id) REFERENCES customers(id),
    FOREIGN KEY (recorded_by) REFERENCES users(id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- 12. Stock Entering & Logs (Wastage, Adjustments)
CREATE TABLE IF NOT EXISTS stock_logs (
    id INT AUTO_INCREMENT PRIMARY KEY,
    product_id INT NOT NULL,
    change_qty INT NOT NULL,
    type ENUM('purchase', 'adjustment', 'wastage', 'sale') NOT NULL,
    reason VARCHAR(255) DEFAULT NULL,
    user_id INT NOT NULL,
    timestamp TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (product_id) REFERENCES products(id),
    FOREIGN KEY (user_id) REFERENCES users(id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- 13. Expenses Entering Screen & Expenses Report
CREATE TABLE IF NOT EXISTS expenses (
    id INT AUTO_INCREMENT PRIMARY KEY,
    title VARCHAR(255) NOT NULL,
    amount DECIMAL(10,2) NOT NULL,
    category ENUM('ingredients', 'salary', 'utility', 'rent', 'other') NOT NULL,
    payment_source ENUM('drawer', 'bank') NOT NULL,
    recorded_by INT NOT NULL,
    expense_date DATE NOT NULL,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (recorded_by) REFERENCES users(id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- 14. Audit Trail & Reprint Log (Reprinted, Cancelled, Modified Bills)
CREATE TABLE IF NOT EXISTS audit_logs (
    id INT AUTO_INCREMENT PRIMARY KEY,
    action_type ENUM('login', 'logout', 'delete_bill', 'change_price', 'edit_stock', 'reprint_bill', 'modify_bill') NOT NULL,
    table_name VARCHAR(50) DEFAULT NULL,
    record_id INT DEFAULT NULL,
    details TEXT NOT NULL,
    user_id INT NOT NULL,
    timestamp TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (user_id) REFERENCES users(id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;


-- Seed Data

-- Insert default admin, owner, cashier, kitchen, delivery
-- Default password for all: 123456 (using raw passwords for local testing/demo, or bcrypt hash)
-- For demonstration/testing we will seed active users:
INSERT INTO users (name, username, password_hash, role) VALUES
('System Administrator', 'admin', '$2a$10$KYVVXoS7ntUm8jLTGL7HgOe4Ff/NPByXj0z9wcMS/UwY2ZVglw7Y6', 'admin'),
('Cashier Perera', 'cashier', '$2a$10$KYVVXoS7ntUm8jLTGL7HgOe4Ff/NPByXj0z9wcMS/UwY2ZVglw7Y6', 'cashier'),
('Hotel Owner', 'owner', '$2a$10$KYVVXoS7ntUm8jLTGL7HgOe4Ff/NPByXj0z9wcMS/UwY2ZVglw7Y6', 'owner'),
('Head Kottu Chef', 'chef1', '$2a$10$KYVVXoS7ntUm8jLTGL7HgOe4Ff/NPByXj0z9wcMS/UwY2ZVglw7Y6', 'kitchen'),
('Delivery Rider', 'delivery1', '$2a$10$KYVVXoS7ntUm8jLTGL7HgOe4Ff/NPByXj0z9wcMS/UwY2ZVglw7Y6', 'delivery');

-- Categories
INSERT INTO categories (name) VALUES
('Rice Dishes'),
('Kottu Dishes'),
('Short Eats'),
('Drinks'),
('Desserts');

-- Products with Sinhala Names
INSERT INTO products (name, sinhala_name, description, category_id, price, cost, barcode, stock_qty, min_stock_level, is_short_eat) VALUES
('Chicken Fried Rice', 'තෙම්පරාදු කුකුල් මස් බත්', 'Savory fried rice with tender chicken chunks and fresh vegetables.', 1, 950.00, 500.00, '9780000000010', 100, 15, FALSE),
('Egg Fried Rice', 'තෙම්පරාදු බිත්තර බත්', 'Fragrant fried rice loaded with scrambled eggs and spring onions.', 1, 800.00, 400.00, '9780000000027', 150, 10, FALSE),
('Chicken Kottu Roti', 'කුකුල් මස් කොත්තු රොටි', 'Shredded flatbread stir-fried with chicken, eggs, and rich gravy.', 2, 1100.00, 600.00, '9780000000034', 80, 20, FALSE),
('Cheese Kottu Roti', 'චීස් කොත්තු රොටි', 'Creamy kottu roti infused with processed cheese and milk.', 2, 1300.00, 750.00, '9780000000041', 50, 10, FALSE),
('Fish Bun', 'මාළු පාන්', 'Spiced fish filling baked inside a triangular soft bun.', 3, 120.00, 60.00, '9780000000058', 60, 25, TRUE),
('Egg Roti', 'බිත්තර රොටි', 'Flatbread cooked with a whole egg inside.', 3, 150.00, 80.00, '9780000000065', 40, 15, TRUE),
('Coca-Cola 500ml', 'කොකා කෝලා', 'Refreshing soft drink.', 4, 250.00, 200.00, '9780000000072', 200, 30, FALSE),
('Fresh Ginger Tea', 'ඉඟුරු තේ', 'A warm cup of traditional ginger black tea.', 4, 100.00, 30.00, '9780000000089', 500, 50, FALSE);

-- Dining Tables
INSERT INTO dining_tables (table_number, capacity) VALUES
('Table 1', 4),
('Table 2', 4),
('Table 3', 2),
('Table 4', 6),
('Table 5', 8),
('Table 6', 4);

-- Customers
INSERT INTO customers (name, phone, birthday, credit_limit, outstanding_balance) VALUES
('Walking Customer', '0000000000', NULL, 0.00, 0.00),
('Sahan Bandara', '0771234567', '1995-08-12', 50000.00, 2500.00),
('Uncle Sunil (Shop Owner)', '0719876543', '1968-04-20', 100000.00, 12000.00);
