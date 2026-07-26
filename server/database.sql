-- Restaurant POS System Database Schema
-- Optimized for LAN-first Local + VPS Sync (Includes all Admin, Staff & POS System Tables)

CREATE DATABASE IF NOT EXISTS hotel_pos;
USE hotel_pos;

-- 1. Multiple User Levels (Admin, Cashier, Owner, Kitchen, Delivery)
CREATE TABLE IF NOT EXISTS users (
    id INT AUTO_INCREMENT PRIMARY KEY,
    name VARCHAR(100) NOT NULL,
    username VARCHAR(50) UNIQUE NOT NULL,
    password_hash VARCHAR(255) NOT NULL,
    role VARCHAR(100) NOT NULL DEFAULT 'cashier',
    status ENUM('active', 'inactive') DEFAULT 'active',
    image_base64 LONGTEXT NULL,
    email VARCHAR(100) NULL,
    phone VARCHAR(20) NULL,
    branch VARCHAR(50) DEFAULT 'current' NULL,
    category_id INT NULL,
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
    sizes TEXT NULL,
    extras TEXT NULL,
    addons TEXT NULL,
    track_stock BOOLEAN DEFAULT TRUE,
    is_happy_hour_eligible BOOLEAN DEFAULT TRUE,
    ingredients TEXT NULL,
    is_kot_item BOOLEAN DEFAULT FALSE,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (category_id) REFERENCES categories(id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- 4. Happy Hour Pricing (Promotions & Time-based pricing)
CREATE TABLE IF NOT EXISTS happy_hour_pricing (
    id INT AUTO_INCREMENT PRIMARY KEY,
    product_id INT NULL,
    category_id INT NULL,
    name VARCHAR(255) NULL,
    promo_price DECIMAL(10,2) NOT NULL,
    start_time TIME NOT NULL,
    end_time TIME NOT NULL,
    days_of_week VARCHAR(50) DEFAULT '1,2,3,4,5,6,7', -- Comma-separated days (1=Mon, 7=Sun)
    status ENUM('active', 'inactive') DEFAULT 'active',
    image_base64 LONGTEXT NULL,
    FOREIGN KEY (product_id) REFERENCES products(id) ON DELETE CASCADE,
    FOREIGN KEY (category_id) REFERENCES categories(id) ON DELETE SET NULL
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
    email VARCHAR(100) NULL,
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

-- 9. Pre Orders
CREATE TABLE IF NOT EXISTS pre_orders (
    id INT AUTO_INCREMENT PRIMARY KEY,
    pre_order_number VARCHAR(50) UNIQUE NOT NULL,
    customer_id INT DEFAULT NULL,
    customer_name VARCHAR(100) NOT NULL,
    customer_phone VARCHAR(20) NOT NULL,
    received_date DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    status ENUM('pending', 'converted', 'cancelled') DEFAULT 'pending',
    subtotal DECIMAL(10,2) NOT NULL DEFAULT 0.00,
    discount DECIMAL(10,2) DEFAULT 0.00,
    total DECIMAL(10,2) NOT NULL DEFAULT 0.00,
    advance_payment DECIMAL(10,2) DEFAULT 0.00,
    balance_amount DECIMAL(10,2) DEFAULT 0.00,
    is_notified BOOLEAN DEFAULT FALSE,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    FOREIGN KEY (customer_id) REFERENCES customers(id) ON DELETE SET NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- 10. Orders (Supports Dine-In, Takeaway, Delivery, Pre-orders and Credit settlements)
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
    received_amount DECIMAL(10,2) DEFAULT 0.00,
    change_amount DECIMAL(10,2) DEFAULT 0.00,
    advance_payment DECIMAL(10,2) DEFAULT 0.00,
    balance_amount DECIMAL(10,2) DEFAULT 0.00,
    pre_order_id INT NULL,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    sync_status ENUM('synced', 'pending') DEFAULT 'synced',
    FOREIGN KEY (table_id) REFERENCES dining_tables(id),
    FOREIGN KEY (customer_id) REFERENCES customers(id),
    FOREIGN KEY (cashier_id) REFERENCES users(id),
    FOREIGN KEY (shift_id) REFERENCES shifts(id),
    FOREIGN KEY (pre_order_id) REFERENCES pre_orders(id) ON DELETE SET NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- 11. Order Items
CREATE TABLE IF NOT EXISTS order_items (
    id INT AUTO_INCREMENT PRIMARY KEY,
    order_id INT NOT NULL,
    order_number VARCHAR(50) DEFAULT NULL,
    product_id INT NOT NULL,
    product_name VARCHAR(255) DEFAULT NULL,
    product_sinhala_name VARCHAR(255) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci DEFAULT NULL,
    quantity INT NOT NULL,
    price DECIMAL(10,2) NOT NULL, -- price sold at (inc happy hour)
    notes VARCHAR(255) DEFAULT NULL, -- order notes like "no chili"
    status ENUM('pending', 'preparing', 'completed') DEFAULT 'pending',
    is_short_eat BOOLEAN DEFAULT FALSE,
    FOREIGN KEY (order_id) REFERENCES orders(id) ON DELETE CASCADE,
    FOREIGN KEY (product_id) REFERENCES products(id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- 12. Credit settlements (Nearby shop owners & weekly settle)
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

-- 13. Stock Entering & Logs (Wastage, Adjustments)
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

-- 14. Expenses Entering Screen & Expenses Report
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

-- 15. Audit Trail & Reprint Log (Reprinted, Cancelled, Modified Bills)
CREATE TABLE IF NOT EXISTS audit_logs (
    id INT AUTO_INCREMENT PRIMARY KEY,
    action_type ENUM('login', 'logout', 'delete_bill', 'change_price', 'edit_stock', 'reprint_bill', 'modify_bill', 'place_order', 'pay_order', 'cash_in', 'cash_out') NOT NULL,
    table_name VARCHAR(50) DEFAULT NULL,
    record_id INT DEFAULT NULL,
    details TEXT NOT NULL,
    user_id INT NOT NULL,
    timestamp TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (user_id) REFERENCES users(id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- 16. Ingredients
CREATE TABLE IF NOT EXISTS ingredients (
    id INT AUTO_INCREMENT PRIMARY KEY,
    name VARCHAR(100) NOT NULL UNIQUE,
    unit VARCHAR(50) NOT NULL DEFAULT 'kg',
    stock_qty DECIMAL(10,3) NOT NULL DEFAULT 0.000,
    min_stock_level DECIMAL(10,3) NOT NULL DEFAULT 5.000,
    cost_per_unit DECIMAL(10,2) NOT NULL DEFAULT 0.00,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- 17. Ingredient Stock Logs
CREATE TABLE IF NOT EXISTS ingredient_stock_logs (
    id INT AUTO_INCREMENT PRIMARY KEY,
    ingredient_id INT NOT NULL,
    change_qty DECIMAL(10,3) NOT NULL,
    type VARCHAR(50) NOT NULL,
    reason VARCHAR(255) NULL,
    user_id INT NOT NULL,
    timestamp TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (ingredient_id) REFERENCES ingredients(id) ON DELETE CASCADE,
    FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- 18. System Notifications
CREATE TABLE IF NOT EXISTS notifications (
    id INT AUTO_INCREMENT PRIMARY KEY,
    title VARCHAR(255) NOT NULL,
    message TEXT NOT NULL,
    type VARCHAR(50) DEFAULT 'info',
    is_read BOOLEAN DEFAULT FALSE,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- 19. Promotional Offers
CREATE TABLE IF NOT EXISTS offers (
    id INT AUTO_INCREMENT PRIMARY KEY,
    title VARCHAR(255) NULL,
    name VARCHAR(255) NULL,
    description TEXT NULL,
    discount_percentage DECIMAL(5,2) NOT NULL,
    code VARCHAR(50) NULL,
    start_date DATE NULL,
    end_date DATE NULL,
    image_base64 LONGTEXT NULL,
    status ENUM('active', 'inactive') DEFAULT 'active',
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- 19. Pre Orders
CREATE TABLE IF NOT EXISTS pre_orders (
    id INT AUTO_INCREMENT PRIMARY KEY,
    pre_order_number VARCHAR(50) UNIQUE NOT NULL,
    customer_id INT DEFAULT NULL,
    customer_name VARCHAR(100) NOT NULL,
    customer_phone VARCHAR(20) NOT NULL,
    received_date DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    status ENUM('pending', 'converted', 'cancelled') DEFAULT 'pending',
    subtotal DECIMAL(10,2) NOT NULL DEFAULT 0.00,
    discount DECIMAL(10,2) DEFAULT 0.00,
    total DECIMAL(10,2) NOT NULL DEFAULT 0.00,
    advance_payment DECIMAL(10,2) DEFAULT 0.00,
    balance_amount DECIMAL(10,2) DEFAULT 0.00,
    is_notified BOOLEAN DEFAULT FALSE,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    FOREIGN KEY (customer_id) REFERENCES customers(id) ON DELETE SET NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- 20. Pre Order Items
CREATE TABLE IF NOT EXISTS pre_order_items (
    id INT AUTO_INCREMENT PRIMARY KEY,
    pre_order_id INT NOT NULL,
    product_id INT NOT NULL,
    product_name VARCHAR(255) NULL DEFAULT NULL,
    quantity INT NOT NULL,
    price DECIMAL(10,2) NOT NULL,
    notes VARCHAR(255) DEFAULT NULL,
    FOREIGN KEY (pre_order_id) REFERENCES pre_orders(id) ON DELETE CASCADE,
    FOREIGN KEY (product_id) REFERENCES products(id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- 21. Global Settings
CREATE TABLE IF NOT EXISTS global_settings (
    setting_key VARCHAR(100) PRIMARY KEY,
    setting_value TEXT NULL,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- 22. Roles & Permissions
CREATE TABLE IF NOT EXISTS roles (
    id INT AUTO_INCREMENT PRIMARY KEY,
    name VARCHAR(100) NOT NULL UNIQUE,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE IF NOT EXISTS role_permissions (
    id INT AUTO_INCREMENT PRIMARY KEY,
    role_id INT NOT NULL,
    page VARCHAR(100) NOT NULL,
    can_view TINYINT(1) DEFAULT 0,
    can_create TINYINT(1) DEFAULT 0,
    can_update TINYINT(1) DEFAULT 0,
    can_delete TINYINT(1) DEFAULT 0,
    FOREIGN KEY (role_id) REFERENCES roles(id) ON DELETE CASCADE,
    UNIQUE KEY uq_role_page (role_id, page)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- 23. Staff Payroll & Advances
CREATE TABLE IF NOT EXISTS staff_advances (
    id INT AUTO_INCREMENT PRIMARY KEY,
    user_id INT NOT NULL,
    amount DECIMAL(10,2) NOT NULL,
    reason VARCHAR(255) NULL,
    advance_date DATE NOT NULL,
    status ENUM('pending', 'deducted', 'settled') DEFAULT 'pending',
    recorded_by INT NULL,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE,
    FOREIGN KEY (recorded_by) REFERENCES users(id) ON DELETE SET NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE IF NOT EXISTS staff_payroll_settings (
    id INT AUTO_INCREMENT PRIMARY KEY,
    user_id INT NOT NULL UNIQUE,
    basic_salary DECIMAL(10,2) DEFAULT 0.00,
    salary_type ENUM('daily', 'weekly', 'monthly') DEFAULT 'monthly',
    ot_rate_per_hour DECIMAL(10,2) NULL,
    allowances DECIMAL(10,2) DEFAULT 0.00,
    salary_due_day INT DEFAULT 28,
    monthly_salary DECIMAL(10,2) DEFAULT 0.00,
    daily_salary DECIMAL(10,2) DEFAULT 0.00,
    hourly_rate DECIMAL(10,2) DEFAULT 0.00,
    ot_hourly_rate DECIMAL(10,2) DEFAULT 0.00,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE IF NOT EXISTS staff_payrolls (
    id INT AUTO_INCREMENT PRIMARY KEY,
    user_id INT NOT NULL,
    month_year VARCHAR(20) NULL,
    period_start DATE NULL,
    period_end DATE NULL,
    basic_salary DECIMAL(10,2) DEFAULT 0.00,
    working_hours DECIMAL(10,2) DEFAULT 0.00,
    ot_hours DECIMAL(10,2) DEFAULT 0.00,
    ot_rate DECIMAL(10,2) DEFAULT 0.00,
    ot_amount DECIMAL(10,2) DEFAULT 0.00,
    tip_amount DECIMAL(10,2) DEFAULT 0.00,
    bonuses_others DECIMAL(10,2) DEFAULT 0.00,
    allowances DECIMAL(10,2) DEFAULT 0.00,
    advance_deduction DECIMAL(10,2) DEFAULT 0.00,
    advances_deducted DECIMAL(10,2) DEFAULT 0.00,
    net_salary DECIMAL(10,2) NOT NULL DEFAULT 0.00,
    payment_method ENUM('cash', 'bank', 'drawer') DEFAULT 'cash',
    payment_status ENUM('draft', 'paid', 'unpaid') DEFAULT 'paid',
    status VARCHAR(50) DEFAULT 'unpaid',
    paid_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    created_by INT NULL,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE,
    FOREIGN KEY (created_by) REFERENCES users(id) ON DELETE SET NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE IF NOT EXISTS staff_shifts (
    id INT AUTO_INCREMENT PRIMARY KEY,
    user_id INT NOT NULL,
    clock_in DATETIME DEFAULT CURRENT_TIMESTAMP,
    clock_out DATETIME DEFAULT NULL,
    duration_minutes INT DEFAULT 0,
    hours_worked DECIMAL(5,2) DEFAULT 0.00,
    status ENUM('active', 'completed') DEFAULT 'active',
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- 24. Suppliers & Supplier Deliveries
CREATE TABLE IF NOT EXISTS suppliers (
    id INT AUTO_INCREMENT PRIMARY KEY,
    name VARCHAR(255) NOT NULL,
    company VARCHAR(100) NULL,
    phone VARCHAR(20) NULL,
    email VARCHAR(100) NULL,
    address TEXT NULL,
    outstanding_balance DECIMAL(10,2) DEFAULT 0.00,
    delivery_cycle VARCHAR(255) DEFAULT 'Weekly',
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE IF NOT EXISTS supplier_deliveries (
    id INT AUTO_INCREMENT PRIMARY KEY,
    supplier_id INT NOT NULL,
    invoice_number VARCHAR(100) NULL,
    item_name VARCHAR(255) NULL,
    quantity DECIMAL(10,2) NOT NULL DEFAULT 0.00,
    unit VARCHAR(50) DEFAULT 'kg',
    total_amount DECIMAL(10,2) NOT NULL DEFAULT 0.00,
    delivery_date DATE NOT NULL,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (supplier_id) REFERENCES suppliers(id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE IF NOT EXISTS supplier_payments (
    id INT AUTO_INCREMENT PRIMARY KEY,
    supplier_id INT NOT NULL,
    amount DECIMAL(10,2) NOT NULL,
    payment_method VARCHAR(50) DEFAULT 'cash',
    payment_source ENUM('drawer', 'bank') NOT NULL DEFAULT 'drawer',
    remarks VARCHAR(255) NULL,
    payment_date DATE NOT NULL,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (supplier_id) REFERENCES suppliers(id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- 25. User Addresses
CREATE TABLE IF NOT EXISTS user_addresses (
    id INT AUTO_INCREMENT PRIMARY KEY,
    user_id INT NULL,
    customer_id INT NULL,
    label VARCHAR(50) DEFAULT 'Home',
    address_line TEXT NOT NULL,
    latitude DECIMAL(10,7) NULL,
    longitude DECIMAL(10,7) NULL,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE,
    FOREIGN KEY (customer_id) REFERENCES customers(id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;


-- Seed Data

-- Insert default admin, owner, cashier, kitchen, delivery
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
