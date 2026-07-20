const mysql = require('mysql2/promise');
const fs = require('fs');
const path = require('path');
require('dotenv').config();

const dbConfig = {
    host: process.env.DB_HOST || 'localhost',
    user: process.env.DB_USER || 'root',
    password: process.env.DB_PASSWORD || '1234',
    database: process.env.DB_NAME || 'hotel_pos',
    multipleStatements: true // Allow running multi-line SQL scripts during init
};

let pool;

async function getPool() {
    if (!pool) {
        // First, check if database exists, create if not
        try {
            const tempConnection = await mysql.createConnection({
                host: dbConfig.host,
                user: dbConfig.user,
                password: dbConfig.password,
                multipleStatements: true
            });
            await tempConnection.query(`CREATE DATABASE IF NOT EXISTS \`${dbConfig.database}\`;`);
            await tempConnection.end();
        } catch (error) {
            console.error('Error verifying database existence:', error.message);
        }

        pool = mysql.createPool(dbConfig);
    }
    return pool;
}

// Helper to run query with params
async function query(sql, params) {
    const dbPool = await getPool();
    const [results] = await dbPool.execute(sql, params);
    return results;
}

// Helper for multi-statement queries (like sql scripts)
async function multiQuery(sql) {
    const dbPool = await getPool();
    const connection = await dbPool.getConnection();
    try {
        const [results] = await connection.query(sql);
        return results;
    } finally {
        connection.release();
    }
}

// Automatically initialize database tables using database.sql
async function initializeDatabase() {
    try {
        const dbPool = await getPool();
        // Check if users table exists
        const [tables] = await dbPool.query("SHOW TABLES LIKE 'users'");
        let needInit = false;
        
        if (tables.length === 0) {
            needInit = true;
        } else {
            // Check if users table is empty
            const [rows] = await dbPool.query("SELECT COUNT(*) as count FROM users");
            if (rows[0].count === 0) {
                needInit = true;
            }
        }

        if (needInit) {
            console.log('Database tables not found or empty. Initializing database schema from database.sql...');
            const sqlPath = path.join(__dirname, 'database.sql');
            if (fs.existsSync(sqlPath)) {
                const sqlContent = fs.readFileSync(sqlPath, 'utf8');
                await multiQuery(sqlContent);
                console.log('Database tables created and seeded successfully.');
            } else {
                console.warn('database.sql file not found. Skipping auto-initialization.');
            }
        } else {
            console.log('Database already initialized. Active connections ready.');
            // Ensure columns exist (self-healing migration)
            try {
                await dbPool.query("ALTER TABLE users ADD COLUMN image_base64 LONGTEXT NULL");
                console.log("Migration: Added image_base64 to users table.");
            } catch (_) {}
            try {
                await dbPool.query("ALTER TABLE users ADD COLUMN category_id INT NULL, ADD CONSTRAINT fk_users_category FOREIGN KEY (category_id) REFERENCES categories(id) ON DELETE SET NULL");
                console.log("Migration: Added category_id to users table.");
            } catch (_) {}
            try {
                await dbPool.query("ALTER TABLE products ADD COLUMN image_base64 LONGTEXT NULL");
                console.log("Migration: Added image_base64 to products table.");
            } catch (_) {}
            try {
                await dbPool.query("ALTER TABLE products ADD COLUMN item_type VARCHAR(50) DEFAULT 'Veg'");
                console.log("Migration: Added item_type to products table.");
            } catch (_) {}
            try {
                await dbPool.query("ALTER TABLE products ADD COLUMN tax DECIMAL(10,2) DEFAULT 0.00");
                console.log("Migration: Added tax to products table.");
            } catch (_) {}
            try {
                await dbPool.query("ALTER TABLE products ADD COLUMN is_featured BOOLEAN DEFAULT FALSE");
                console.log("Migration: Added is_featured to products table.");
            } catch (_) {}
            try {
                await dbPool.query("ALTER TABLE products ADD COLUMN caution TEXT NULL");
                console.log("Migration: Added caution to products table.");
            } catch (_) {}
            try {
                await dbPool.query("ALTER TABLE products ADD COLUMN has_sizes BOOLEAN DEFAULT FALSE");
                console.log("Migration: Added has_sizes to products table.");
            } catch (_) {}
            try {
                await dbPool.query("ALTER TABLE products ADD COLUMN has_extras BOOLEAN DEFAULT FALSE");
                console.log("Migration: Added has_extras to products table.");
            } catch (_) {}
            try {
                await dbPool.query("ALTER TABLE products ADD COLUMN has_addons BOOLEAN DEFAULT FALSE");
                console.log("Migration: Added has_addons to products table.");
            } catch (_) {}
            try {
                await dbPool.query("ALTER TABLE products ADD COLUMN sizes TEXT NULL");
                console.log("Migration: Added sizes to products table.");
            } catch (_) {}
            try {
                await dbPool.query("ALTER TABLE products ADD COLUMN extras TEXT NULL");
                console.log("Migration: Added extras to products table.");
            } catch (_) {}
            try {
                await dbPool.query("ALTER TABLE products ADD COLUMN addons TEXT NULL");
                console.log("Migration: Added addons to products table.");
            } catch (_) {}
            try {
                await dbPool.query("ALTER TABLE products ADD COLUMN track_stock BOOLEAN DEFAULT TRUE");
                console.log("Migration: Added track_stock to products table.");
            } catch (_) {}
            try {
                await dbPool.query("ALTER TABLE products ADD COLUMN is_happy_hour_eligible BOOLEAN DEFAULT TRUE");
                console.log("Migration: Added is_happy_hour_eligible to products table.");
            } catch (_) {}
            try {
                await dbPool.query("ALTER TABLE products ADD COLUMN is_kot_item BOOLEAN DEFAULT FALSE");
                console.log("Migration: Added is_kot_item to products table.");
            } catch (_) {}
            try {
                await dbPool.query("ALTER TABLE customers ADD COLUMN image_base64 LONGTEXT NULL");
                console.log("Migration: Added image_base64 to customers table.");
            } catch (_) {}
            try {
                await dbPool.query("ALTER TABLE dining_tables ADD COLUMN active_status VARCHAR(50) DEFAULT 'active'");
                console.log("Migration: Added active_status to dining_tables table.");
            } catch (_) {}
            try {
                await dbPool.query("ALTER TABLE categories ADD COLUMN image_base64 LONGTEXT NULL");
                console.log("Migration: Added image_base64 to categories table.");
            } catch (_) {}
            
            try {
                await dbPool.query("ALTER TABLE happy_hour_pricing ADD COLUMN name VARCHAR(255) NULL");
                console.log("Migration: Added name to happy_hour_pricing table.");
            } catch (_) {}
            try {
                await dbPool.query("ALTER TABLE happy_hour_pricing ADD COLUMN category_id INT NULL");
                console.log("Migration: Added category_id to happy_hour_pricing table.");
            } catch (_) {}
            try {
                await dbPool.query("SET FOREIGN_KEY_CHECKS = 0");
                await dbPool.query("ALTER TABLE happy_hour_pricing MODIFY product_id INT NULL");
                await dbPool.query("UPDATE happy_hour_pricing SET product_id = NULL WHERE product_id = 0");
                await dbPool.query("SET FOREIGN_KEY_CHECKS = 1");
                console.log("Migration: Allowed NULL product_id in happy_hour_pricing table and cleaned up 0s.");
            } catch (err) {
                console.error("Migration: Allowed NULL product_id failed:", err.message);
                try { await dbPool.query("SET FOREIGN_KEY_CHECKS = 1"); } catch (_) {}
            }
            try {
                await dbPool.query("ALTER TABLE happy_hour_pricing ADD COLUMN image_base64 LONGTEXT NULL");
                console.log("Migration: Added image_base64 to happy_hour_pricing table.");
            } catch (_) {}
            try {
                await dbPool.query("ALTER TABLE happy_hour_pricing ADD CONSTRAINT fk_hhp_category FOREIGN KEY (category_id) REFERENCES categories(id) ON DELETE SET NULL");
                console.log("Migration: Added fk_hhp_category constraint to happy_hour_pricing table.");
            } catch (_) {}
            
            try {
                await dbPool.query(`
                    CREATE TABLE IF NOT EXISTS offers (
                        id INT AUTO_INCREMENT PRIMARY KEY,
                        name VARCHAR(255) NOT NULL,
                        discount_percentage DECIMAL(5,2) NOT NULL,
                        start_date DATE NOT NULL,
                        end_date DATE NOT NULL,
                        image_base64 LONGTEXT NULL,
                        status ENUM('active', 'inactive') DEFAULT 'active',
                        created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
                    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
                `);
                console.log("Migration: Created offers table if not exists.");
            } catch (err) {
                console.error("Migration: Creating offers table failed:", err.message);
            }

            // Migration: Add email and phone to users table
            try {
                await dbPool.query("ALTER TABLE users ADD COLUMN email VARCHAR(100) NULL");
                console.log("Migration: Added email to users table.");
            } catch (_) {}
            try {
                await dbPool.query("ALTER TABLE users ADD COLUMN phone VARCHAR(20) NULL");
                console.log("Migration: Added phone to users table.");
            } catch (_) {}
            try {
                await dbPool.query("ALTER TABLE users MODIFY COLUMN role VARCHAR(100) NOT NULL DEFAULT 'cashier'");
                console.log("Migration: Modified users.role column to VARCHAR(100).");
            } catch (_) {}
            try {
                await dbPool.query("ALTER TABLE audit_logs MODIFY COLUMN action_type ENUM('login', 'logout', 'delete_bill', 'change_price', 'edit_stock', 'reprint_bill', 'modify_bill', 'place_order', 'pay_order', 'cash_in', 'cash_out') NOT NULL");
                console.log("Migration: Expanded action_type ENUM in audit_logs table.");
            } catch (_) {}

            // Migration: Add email to customers table
            try {
                await dbPool.query("ALTER TABLE customers ADD COLUMN email VARCHAR(100) NULL");
                console.log("Migration: Added email to customers table.");
            } catch (_) {}

            // Migration: Add branch column to users table
            try {
                await dbPool.query("ALTER TABLE users ADD COLUMN branch VARCHAR(50) DEFAULT 'current' NULL");
                console.log("Migration: Added branch to users table.");
            } catch (_) {}

            // Migration: Create user_addresses table
            try {
                await dbPool.query(`
                    CREATE TABLE IF NOT EXISTS user_addresses (
                        id INT AUTO_INCREMENT PRIMARY KEY,
                        user_id INT NULL,
                        customer_id INT NULL,
                        label VARCHAR(50) NOT NULL,
                        address_line VARCHAR(255) NOT NULL,
                        latitude DECIMAL(10, 8) NULL,
                        longitude DECIMAL(11, 8) NULL,
                        created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
                        FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE,
                        FOREIGN KEY (customer_id) REFERENCES customers(id) ON DELETE CASCADE
                    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
                `);
                console.log("Migration: Created user_addresses table.");
            } catch (err) {
                console.error("Migration: Creating user_addresses table failed:", err.message);
            }

            // Migration: Create ingredients & ingredient_stock_logs tables
            try {
                await dbPool.query(`
                    CREATE TABLE IF NOT EXISTS ingredients (
                        id INT AUTO_INCREMENT PRIMARY KEY,
                        name VARCHAR(100) UNIQUE NOT NULL,
                        stock_qty DECIMAL(10, 2) DEFAULT 0.00,
                        unit VARCHAR(50) DEFAULT 'kg' NOT NULL
                    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
                `);
                
                await dbPool.query(`
                    CREATE TABLE IF NOT EXISTS ingredient_stock_logs (
                        id INT AUTO_INCREMENT PRIMARY KEY,
                        ingredient_id INT NOT NULL,
                        change_qty DECIMAL(10, 2) NOT NULL,
                        type VARCHAR(50) NOT NULL,
                        reason TEXT NULL,
                        user_id INT NOT NULL,
                        timestamp TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
                        FOREIGN KEY (ingredient_id) REFERENCES ingredients(id) ON DELETE CASCADE
                    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
                `);

                // Seed ingredients
                const ingredients = [
                    ['Rice', 0.0, 'kg'],
                    ['Egg', 0.0, 'units'],
                    ['Chicken', 0.0, 'kg'],
                    ['Oil', 0.0, 'liters'],
                    ['Flour', 0.0, 'kg']
                ];
                for (const ing of ingredients) {
                    await dbPool.query('INSERT IGNORE INTO ingredients (name, stock_qty, unit) VALUES (?, ?, ?)', ing);
                }
                console.log("Migration: Created and seeded ingredients successfully.");
            } catch (err) {
                console.error("Migration: Creating ingredients table failed:", err.message);
            }

            // Migration: Add min_stock_level to ingredients table
            try {
                await dbPool.query("ALTER TABLE ingredients ADD COLUMN min_stock_level DECIMAL(10, 2) DEFAULT 0.00");
                console.log("Migration: Added min_stock_level column to ingredients table.");
            } catch (_) {}

            // Migration: Add ingredients column to products table
            try {
                await dbPool.query("ALTER TABLE products ADD COLUMN ingredients TEXT NULL");
                console.log("Migration: Added ingredients to products table.");
            } catch (_) {}

            // Seed base64 image placeholders for default products & users
            try {
                const redImg = 'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==';
                const yellowImg = 'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8P8PADwADgAGAAXyvHk8AAAAASUVORK5CYII=';
                const greenImg = 'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNk+M9QDwADhgGAWjR9awAAAABJRU5ErkJggg==';
                const blueImg = 'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNkYPhfDwAEtAH5af1hHgAAAABJRU5ErkJggg==';
                const orangeImg = 'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==';
                
                await dbPool.query("UPDATE products SET image_base64 = ? WHERE name LIKE '%Rice%' AND image_base64 IS NULL", [yellowImg]);
                await dbPool.query("UPDATE products SET image_base64 = ? WHERE name LIKE '%Kottu%' AND image_base64 IS NULL", [orangeImg]);
                await dbPool.query("UPDATE products SET image_base64 = ? WHERE name LIKE '%Bun%' AND image_base64 IS NULL", [redImg]);
                await dbPool.query("UPDATE products SET image_base64 = ? WHERE name LIKE '%Roti%' AND image_base64 IS NULL", [yellowImg]);
                await dbPool.query("UPDATE products SET image_base64 = ? WHERE name LIKE '%Cola%' AND image_base64 IS NULL", [redImg]);
                await dbPool.query("UPDATE products SET image_base64 = ? WHERE name LIKE '%Tea%' AND image_base64 IS NULL", [greenImg]);
                
                await dbPool.query("UPDATE users SET image_base64 = ? WHERE username = 'admin' AND image_base64 IS NULL", [blueImg]);
                await dbPool.query("UPDATE users SET image_base64 = ? WHERE username = 'cashier' AND image_base64 IS NULL", [greenImg]);
                await dbPool.query("UPDATE users SET image_base64 = ? WHERE username = 'owner' AND image_base64 IS NULL", [redImg]);
                
                console.log("Migration: Seeded base64 images successfully.");
            } catch (err) {
                console.error("Migration: Seeding base64 images failed:", err.message);
            }

            // ── Roles & Permissions ──────────────────────────────────────────
            try {
                await dbPool.query(`
                    CREATE TABLE IF NOT EXISTS roles (
                        id INT AUTO_INCREMENT PRIMARY KEY,
                        name VARCHAR(100) NOT NULL UNIQUE,
                        created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
                    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
                `);
                await dbPool.query(`
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
                `);
                const defaultRoles = ['Admin', 'Cashier', 'Waiter', 'Chef', 'Delivery Boy', 'Short Eats Cabin'];
                for (const r of defaultRoles) {
                    await dbPool.query('INSERT IGNORE INTO roles (name) VALUES (?)', [r]);
                }
                console.log("Migration: Created roles & role_permissions tables.");
            } catch (err) {
                console.error("Migration: Creating roles tables failed:", err.message);
            }

            // Migration: Create suppliers table
            try {
                await dbPool.query(`
                    CREATE TABLE IF NOT EXISTS suppliers (
                        id INT AUTO_INCREMENT PRIMARY KEY,
                        name VARCHAR(255) NOT NULL,
                        outstanding_balance DECIMAL(10,2) DEFAULT 0.00,
                        delivery_cycle VARCHAR(255) DEFAULT 'Weekly',
                        created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
                    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
                `);
                
                // Seed if empty
                const [rows] = await dbPool.query("SELECT COUNT(*) as count FROM suppliers");
                if (rows[0].count === 0) {
                    const defaultSuppliers = [
                        ['Aliya Flour Suppliers', 45000.00, 'Weekly (Monday)'],
                        ['Coca-Cola Beverages', 18500.00, 'Weekly (Thursday)'],
                        ['Keells Meat Providers', 120000.00, 'Daily'],
                        ['Prima Flour Co.', 0.00, 'Bi-weekly']
                    ];
                    for (const s of defaultSuppliers) {
                        await dbPool.query('INSERT INTO suppliers (name, outstanding_balance, delivery_cycle) VALUES (?, ?, ?)', s);
                    }
                }
                console.log("Migration: Created and seeded suppliers table.");
            } catch (err) {
                console.error("Migration: Creating suppliers table failed:", err.message);
            }

            // Migration: Create supplier_deliveries table
            try {
                await dbPool.query(`
                    CREATE TABLE IF NOT EXISTS supplier_deliveries (
                        id INT AUTO_INCREMENT PRIMARY KEY,
                        supplier_id INT NOT NULL,
                        item_name VARCHAR(255) NOT NULL,
                        quantity DECIMAL(10,2) NOT NULL,
                        unit VARCHAR(50) DEFAULT 'kg',
                        total_amount DECIMAL(10,2) NOT NULL DEFAULT 0.00,
                        delivery_date DATE NOT NULL,
                        created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
                        FOREIGN KEY (supplier_id) REFERENCES suppliers(id) ON DELETE CASCADE
                    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
                `);
                console.log("Migration: Created supplier_deliveries table.");
            } catch (err) {
                console.error("Migration: Creating supplier_deliveries table failed:", err.message);
            }

            // Migration: Create supplier_payments table
            try {
                await dbPool.query(`
                    CREATE TABLE IF NOT EXISTS supplier_payments (
                        id INT AUTO_INCREMENT PRIMARY KEY,
                        supplier_id INT NOT NULL,
                        amount DECIMAL(10,2) NOT NULL,
                        payment_source ENUM('drawer', 'bank') NOT NULL DEFAULT 'drawer',
                        remarks VARCHAR(255) NULL,
                        payment_date DATE NOT NULL,
                        created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
                        FOREIGN KEY (supplier_id) REFERENCES suppliers(id) ON DELETE CASCADE
                    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
                `);
                console.log("Migration: Created supplier_payments table.");
            } catch (err) {
                console.error("Migration: Creating supplier_payments table failed:", err.message);
            }

            // Migration: Add received_amount and change_amount to orders table
            try {
                await dbPool.query("ALTER TABLE orders ADD COLUMN received_amount DECIMAL(10,2) DEFAULT 0.00");
                console.log("Migration: Added received_amount to orders table.");
            } catch (_) {}
            try {
                await dbPool.query("ALTER TABLE orders ADD COLUMN change_amount DECIMAL(10,2) DEFAULT 0.00");
                console.log("Migration: Added change_amount to orders table.");
            } catch (_) {}

            // Migration: Create pre_orders, pre_order_items, and notifications tables
            try {
                await dbPool.query(`
                    CREATE TABLE IF NOT EXISTS pre_orders (
                        id INT AUTO_INCREMENT PRIMARY KEY,
                        pre_order_number VARCHAR(50) UNIQUE NOT NULL,
                        customer_id INT DEFAULT NULL,
                        customer_name VARCHAR(100) NOT NULL,
                        customer_phone VARCHAR(20) NOT NULL,
                        received_date DATETIME NOT NULL,
                        status ENUM('pending', 'converted', 'cancelled') DEFAULT 'pending',
                        subtotal DECIMAL(10,2) NOT NULL,
                        discount DECIMAL(10,2) DEFAULT 0.00,
                        total DECIMAL(10,2) NOT NULL,
                        is_notified BOOLEAN DEFAULT FALSE,
                        created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
                        updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
                        FOREIGN KEY (customer_id) REFERENCES customers(id) ON DELETE SET NULL
                    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
                `);
                console.log("Migration: Created pre_orders table successfully.");
            } catch (err) {
                console.error("Migration: Creating pre_orders table failed:", err.message);
            }

            try {
                await dbPool.query(`
                    CREATE TABLE IF NOT EXISTS pre_order_items (
                        id INT AUTO_INCREMENT PRIMARY KEY,
                        pre_order_id INT NOT NULL,
                        product_id INT NOT NULL,
                        quantity INT NOT NULL,
                        price DECIMAL(10,2) NOT NULL,
                        notes VARCHAR(255) DEFAULT NULL,
                        FOREIGN KEY (pre_order_id) REFERENCES pre_orders(id) ON DELETE CASCADE,
                        FOREIGN KEY (product_id) REFERENCES products(id) ON DELETE CASCADE
                    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
                `);
                console.log("Migration: Created pre_order_items table successfully.");
            } catch (err) {
                console.error("Migration: Creating pre_order_items table failed:", err.message);
            }

            try {
                await dbPool.query(`
                    CREATE TABLE IF NOT EXISTS notifications (
                        id INT AUTO_INCREMENT PRIMARY KEY,
                        title VARCHAR(255) NOT NULL,
                        message TEXT NOT NULL,
                        type VARCHAR(50) DEFAULT 'general',
                        is_read BOOLEAN DEFAULT FALSE,
                        created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
                    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
                `);
                console.log("Migration: Created notifications table successfully.");
            } catch (err) {
                console.error("Migration: Creating notifications table failed:", err.message);
            }

            // Migration: Add advance_payment and balance_amount to pre_orders
            try {
                await dbPool.query("ALTER TABLE pre_orders ADD COLUMN advance_payment DECIMAL(10,2) DEFAULT 0.00");
                console.log("Migration: Added advance_payment to pre_orders table.");
            } catch (_) {}
            try {
                await dbPool.query("ALTER TABLE pre_orders ADD COLUMN balance_amount DECIMAL(10,2) DEFAULT 0.00");
                console.log("Migration: Added balance_amount to pre_orders table.");
            } catch (_) {}

            // Migration: Add advance_payment and balance_amount to orders
            try {
                await dbPool.query("ALTER TABLE orders ADD COLUMN advance_payment DECIMAL(10,2) DEFAULT 0.00");
                console.log("Migration: Added advance_payment to orders table.");
            } catch (_) {}
            try {
                await dbPool.query("ALTER TABLE orders ADD COLUMN balance_amount DECIMAL(10,2) DEFAULT 0.00");
                console.log("Migration: Added balance_amount to orders table.");
            } catch (_) {}
            try {
                await dbPool.query("ALTER TABLE orders ADD COLUMN pre_order_id INT NULL");
                console.log("Migration: Added pre_order_id to orders table.");
            } catch (_) {}
            try {
                await dbPool.query("ALTER TABLE orders ADD CONSTRAINT fk_orders_pre_order FOREIGN KEY (pre_order_id) REFERENCES pre_orders(id) ON DELETE SET NULL");
                console.log("Migration: Added fk_orders_pre_order constraint.");
            } catch (_) {}
        }
    } catch (error) {
        console.error('Database initialization failed:', error.message);
    }
}

module.exports = {
    getPool,
    query,
    multiQuery,
    initializeDatabase
};
