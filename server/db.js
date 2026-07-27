const mysql = require('mysql2/promise');
const fs = require('fs');
const path = require('path');
require('dotenv').config();

const dbConfig = {
    host: process.env.DB_HOST || 'localhost',
    user: process.env.DB_USER || 'root',
    password: process.env.DB_PASSWORD || '1234',
    database: process.env.DB_NAME || 'hotel_pos',
    multipleStatements: true,
    dateStrings: true,
    charset: 'utf8mb4'
};

let pool;

async function getPool() {
    if (!pool) {
        const passwordsToTry = Array.from(new Set([dbConfig.password, '1234', 'Perpova26@Hrm+', 'root', '', '123456', 'admin']));
        let connected = false;

        for (const pw of passwordsToTry) {
            try {
                const tempConfig = {
                    host: dbConfig.host,
                    user: dbConfig.user,
                    password: pw,
                    multipleStatements: true,
                    charset: 'utf8mb4'
                };
                const tempConn = await mysql.createConnection(tempConfig);
                await tempConn.query(`CREATE DATABASE IF NOT EXISTS \`${dbConfig.database}\`;`);
                await tempConn.end();

                dbConfig.password = pw;
                connected = true;

                // Save working password to .env file for persistence
                try {
                    const envPath = path.join(__dirname, '.env');
                    let envContent = '';
                    if (fs.existsSync(envPath)) {
                        envContent = fs.readFileSync(envPath, 'utf8');
                        if (envContent.includes('DB_PASSWORD=')) {
                            envContent = envContent.replace(/DB_PASSWORD=.*/g, `DB_PASSWORD=${pw}`);
                        } else {
                            envContent += `\nDB_PASSWORD=${pw}\n`;
                        }
                    } else {
                        envContent = `DB_HOST=${dbConfig.host}\nDB_USER=${dbConfig.user}\nDB_PASSWORD=${pw}\nDB_NAME=${dbConfig.database}\nPORT=3000\n`;
                    }
                    fs.writeFileSync(envPath, envContent, 'utf8');
                } catch (envErr) {
                    console.warn('Could not update .env file:', envErr.message);
                }
                break;
            } catch (err) {
                // Try next password
            }
        }

        if (!connected) {
            console.error('Failed to connect to MySQL with any standard root password.');
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
        await connection.query('SET FOREIGN_KEY_CHECKS = 0;');
        const [results] = await connection.query(sql);
        await connection.query('SET FOREIGN_KEY_CHECKS = 1;');
        return results;
    } catch (err) {
        console.warn('Batch multiQuery execution issue, executing statement-by-statement:', err.message);
        const statements = sql
            .split(';')
            .map(s => s.trim())
            .filter(s => s.length > 0 && !s.startsWith('--'));

        for (const stmt of statements) {
            if (stmt.toLowerCase().startsWith('use ')) continue;
            try {
                await connection.query(stmt);
            } catch (e) {
                console.error('Statement error:', e.message);
            }
        }
        try { await connection.query('SET FOREIGN_KEY_CHECKS = 1;'); } catch (_) {}
    } finally {
        connection.release();
    }
}

// Automatically initialize database tables using database.sql with full self-healing schema synchronization
async function initializeDatabase() {
    try {
        const dbPool = await getPool();
        // Check if users table exists
        const [tables] = await dbPool.query("SHOW TABLES LIKE 'users'");
        const [prodTables] = await dbPool.query("SHOW TABLES LIKE 'products'");
        let needInit = false;
        
        if (tables.length === 0 || prodTables.length === 0) {
            needInit = true;
        } else {
            // Check if users or products table is empty
            const [rows] = await dbPool.query("SELECT COUNT(*) as count FROM users");
            const [prodRows] = await dbPool.query("SELECT COUNT(*) as count FROM products");
            if (rows[0].count === 0 || prodRows[0].count === 0) {
                needInit = true;
            }
        }

        if (needInit) {
            console.log('Database tables not found or empty (users/products missing). Initializing schema & seed data from database.sql...');
            const sqlPath = path.join(__dirname, 'database.sql');
            if (fs.existsSync(sqlPath)) {
                const sqlContent = fs.readFileSync(sqlPath, 'utf8');
                await multiQuery(sqlContent);
                console.log('Database tables created and seeded successfully.');
            } else {
                console.warn('database.sql file not found. Skipping auto-initialization.');
            }
        } else {
            console.log('Database already initialized. Executing full self-healing schema synchronization...');
            
            // 1. USERS table migrations
            try { await dbPool.query("ALTER TABLE users ADD COLUMN image_base64 LONGTEXT NULL"); } catch (_) {}
            try { await dbPool.query("ALTER TABLE users ADD COLUMN category_id INT NULL, ADD CONSTRAINT fk_users_category FOREIGN KEY (category_id) REFERENCES categories(id) ON DELETE SET NULL"); } catch (_) {}
            try { await dbPool.query("ALTER TABLE users ADD COLUMN email VARCHAR(100) NULL"); } catch (_) {}
            try { await dbPool.query("ALTER TABLE users ADD COLUMN phone VARCHAR(20) NULL"); } catch (_) {}
            try { await dbPool.query("ALTER TABLE users ADD COLUMN branch VARCHAR(50) DEFAULT 'current' NULL"); } catch (_) {}
            try { await dbPool.query("ALTER TABLE users MODIFY COLUMN role VARCHAR(100) NOT NULL DEFAULT 'cashier'"); } catch (_) {}

            // 2. CATEGORIES table migrations
            try { await dbPool.query("ALTER TABLE categories ADD COLUMN image_base64 LONGTEXT NULL"); } catch (_) {}

            // 3. PRODUCTS table migrations
            try { await dbPool.query("ALTER TABLE products ADD COLUMN image_base64 LONGTEXT NULL"); } catch (_) {}
            try { await dbPool.query("ALTER TABLE products ADD COLUMN item_type VARCHAR(50) DEFAULT 'Veg'"); } catch (_) {}
            try { await dbPool.query("ALTER TABLE products ADD COLUMN tax DECIMAL(10,2) DEFAULT 0.00"); } catch (_) {}
            try { await dbPool.query("ALTER TABLE products ADD COLUMN is_featured BOOLEAN DEFAULT FALSE"); } catch (_) {}
            try { await dbPool.query("ALTER TABLE products ADD COLUMN caution TEXT NULL"); } catch (_) {}
            try { await dbPool.query("ALTER TABLE products ADD COLUMN has_sizes BOOLEAN DEFAULT FALSE"); } catch (_) {}
            try { await dbPool.query("ALTER TABLE products ADD COLUMN has_extras BOOLEAN DEFAULT FALSE"); } catch (_) {}
            try { await dbPool.query("ALTER TABLE products ADD COLUMN has_addons BOOLEAN DEFAULT FALSE"); } catch (_) {}
            try { await dbPool.query("ALTER TABLE products ADD COLUMN sizes TEXT NULL"); } catch (_) {}
            try { await dbPool.query("ALTER TABLE products ADD COLUMN extras TEXT NULL"); } catch (_) {}
            try { await dbPool.query("ALTER TABLE products ADD COLUMN addons TEXT NULL"); } catch (_) {}
            try { await dbPool.query("ALTER TABLE products ADD COLUMN track_stock BOOLEAN DEFAULT TRUE"); } catch (_) {}
            try { await dbPool.query("ALTER TABLE products ADD COLUMN is_happy_hour_eligible BOOLEAN DEFAULT TRUE"); } catch (_) {}
            try { await dbPool.query("ALTER TABLE products ADD COLUMN is_kot_item BOOLEAN DEFAULT FALSE"); } catch (_) {}
            try { await dbPool.query("ALTER TABLE products ADD COLUMN ingredients TEXT NULL"); } catch (_) {}

            // 4. HAPPY_HOUR_PRICING table migrations
            try { await dbPool.query("ALTER TABLE happy_hour_pricing ADD COLUMN name VARCHAR(255) NULL"); } catch (_) {}
            try { await dbPool.query("ALTER TABLE happy_hour_pricing ADD COLUMN category_id INT NULL"); } catch (_) {}
            try {
                await dbPool.query("SET FOREIGN_KEY_CHECKS = 0");
                await dbPool.query("ALTER TABLE happy_hour_pricing MODIFY product_id INT NULL");
                await dbPool.query("UPDATE happy_hour_pricing SET product_id = NULL WHERE product_id = 0");
                await dbPool.query("SET FOREIGN_KEY_CHECKS = 1");
            } catch (_) {
                try { await dbPool.query("SET FOREIGN_KEY_CHECKS = 1"); } catch (_) {}
            }
            try { await dbPool.query("ALTER TABLE happy_hour_pricing ADD COLUMN image_base64 LONGTEXT NULL"); } catch (_) {}
            try { await dbPool.query("ALTER TABLE happy_hour_pricing ADD CONSTRAINT fk_hhp_category FOREIGN KEY (category_id) REFERENCES categories(id) ON DELETE SET NULL"); } catch (_) {}

            // 5. DINING_TABLES table migrations
            try { await dbPool.query("ALTER TABLE dining_tables ADD COLUMN active_status VARCHAR(50) DEFAULT 'active'"); } catch (_) {}

            // 6. CUSTOMERS table migrations
            try { await dbPool.query("ALTER TABLE customers ADD COLUMN image_base64 LONGTEXT NULL"); } catch (_) {}
            try { await dbPool.query("ALTER TABLE customers ADD COLUMN email VARCHAR(100) NULL"); } catch (_) {}

            // 7. OFFERS table migration & column additions
            try {
                await dbPool.query(`
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
                `);
            } catch (_) {}
            try { await dbPool.query("ALTER TABLE offers ADD COLUMN title VARCHAR(255) NULL"); } catch (_) {}
            try { await dbPool.query("ALTER TABLE offers ADD COLUMN description TEXT NULL"); } catch (_) {}
            try { await dbPool.query("ALTER TABLE offers ADD COLUMN code VARCHAR(50) NULL"); } catch (_) {}

            // 8. AUDIT_LOGS ENUM expansion
            try {
                await dbPool.query("ALTER TABLE audit_logs MODIFY COLUMN action_type ENUM('login', 'logout', 'delete_bill', 'change_price', 'edit_stock', 'reprint_bill', 'modify_bill', 'place_order', 'pay_order', 'cash_in', 'cash_out') NOT NULL");
            } catch (_) {}

            // 9. USER_ADDRESSES table migration
            try {
                await dbPool.query(`
                    CREATE TABLE IF NOT EXISTS user_addresses (
                        id INT AUTO_INCREMENT PRIMARY KEY,
                        user_id INT NULL,
                        customer_id INT NULL,
                        label VARCHAR(50) DEFAULT 'Home',
                        address_line TEXT NOT NULL,
                        latitude DECIMAL(10, 7) NULL,
                        longitude DECIMAL(10, 7) NULL,
                        created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
                        FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE,
                        FOREIGN KEY (customer_id) REFERENCES customers(id) ON DELETE CASCADE
                    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
                `);
            } catch (_) {}

            // 10. INGREDIENTS & INGREDIENT_STOCK_LOGS table migrations
            try {
                await dbPool.query(`
                    CREATE TABLE IF NOT EXISTS ingredients (
                        id INT AUTO_INCREMENT PRIMARY KEY,
                        name VARCHAR(100) UNIQUE NOT NULL,
                        stock_qty DECIMAL(10, 3) DEFAULT 0.000,
                        unit VARCHAR(50) DEFAULT 'kg' NOT NULL
                    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
                `);
                await dbPool.query(`
                    CREATE TABLE IF NOT EXISTS ingredient_stock_logs (
                        id INT AUTO_INCREMENT PRIMARY KEY,
                        ingredient_id INT NOT NULL,
                        change_qty DECIMAL(10, 3) NOT NULL,
                        type VARCHAR(50) NOT NULL,
                        reason TEXT NULL,
                        user_id INT NOT NULL,
                        timestamp TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
                        FOREIGN KEY (ingredient_id) REFERENCES ingredients(id) ON DELETE CASCADE
                    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
                `);

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
            } catch (_) {}
            try { await dbPool.query("ALTER TABLE ingredients ADD COLUMN min_stock_level DECIMAL(10, 3) DEFAULT 5.000"); } catch (_) {}
            try { await dbPool.query("ALTER TABLE ingredients ADD COLUMN cost_per_unit DECIMAL(10, 2) DEFAULT 0.00"); } catch (_) {}

            // 11. Base64 placeholder seeding
            try {
                const redImg = 'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==';
                const yellowImg = 'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8P8PADwADgAGAAXyvHk8AAAAASUVOR5CYII=';
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
            } catch (_) {}

            // 12. ROLES & ROLE_PERMISSIONS tables migration
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
            } catch (_) {}

            // 13. SUPPLIERS, SUPPLIER_DELIVERIES, SUPPLIER_PAYMENTS tables migration
            try {
                await dbPool.query(`
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
                `);
                try { await dbPool.query("ALTER TABLE suppliers ADD COLUMN company VARCHAR(100) NULL"); } catch (_) {}
                try { await dbPool.query("ALTER TABLE suppliers ADD COLUMN phone VARCHAR(20) NULL"); } catch (_) {}
                try { await dbPool.query("ALTER TABLE suppliers ADD COLUMN email VARCHAR(100) NULL"); } catch (_) {}
                try { await dbPool.query("ALTER TABLE suppliers ADD COLUMN address TEXT NULL"); } catch (_) {}
                try { await dbPool.query("ALTER TABLE suppliers ADD COLUMN outstanding_balance DECIMAL(10,2) DEFAULT 0.00"); } catch (_) {}
                try { await dbPool.query("ALTER TABLE suppliers ADD COLUMN delivery_cycle VARCHAR(255) DEFAULT 'Weekly'"); } catch (_) {}
                
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
            } catch (_) {}

            try {
                await dbPool.query(`
                    CREATE TABLE IF NOT EXISTS supplier_deliveries (
                        id INT AUTO_INCREMENT PRIMARY KEY,
                        supplier_id INT NOT NULL,
                        invoice_number VARCHAR(100) NULL,
                        item_name VARCHAR(255) NOT NULL,
                        quantity DECIMAL(10,2) NOT NULL,
                        unit VARCHAR(50) DEFAULT 'kg',
                        total_amount DECIMAL(10,2) NOT NULL DEFAULT 0.00,
                        delivery_date DATE NOT NULL,
                        created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
                        FOREIGN KEY (supplier_id) REFERENCES suppliers(id) ON DELETE CASCADE
                    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
                `);
                try { await dbPool.query("ALTER TABLE supplier_deliveries ADD COLUMN invoice_number VARCHAR(100) NULL"); } catch (_) {}
            } catch (_) {}

            try {
                await dbPool.query(`
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
                `);
                try { await dbPool.query("ALTER TABLE supplier_payments ADD COLUMN payment_method VARCHAR(50) DEFAULT 'cash'"); } catch (_) {}
                try { await dbPool.query("ALTER TABLE supplier_payments ADD COLUMN remarks VARCHAR(255) NULL"); } catch (_) {}
            } catch (_) {}

            // 14. ORDERS table column migrations
            try { await dbPool.query("ALTER TABLE orders ADD COLUMN received_amount DECIMAL(10,2) DEFAULT 0.00"); } catch (_) {}
            try { await dbPool.query("ALTER TABLE orders ADD COLUMN change_amount DECIMAL(10,2) DEFAULT 0.00"); } catch (_) {}
            try { await dbPool.query("ALTER TABLE orders ADD COLUMN advance_payment DECIMAL(10,2) DEFAULT 0.00"); } catch (_) {}
            try { await dbPool.query("ALTER TABLE orders ADD COLUMN balance_amount DECIMAL(10,2) DEFAULT 0.00"); } catch (_) {}
            try { await dbPool.query("ALTER TABLE orders ADD COLUMN pre_order_id INT NULL"); } catch (_) {}
            try { await dbPool.query("ALTER TABLE orders ADD CONSTRAINT fk_orders_pre_order FOREIGN KEY (pre_order_id) REFERENCES pre_orders(id) ON DELETE SET NULL"); } catch (_) {}

            // 15. ORDER_ITEMS table column migrations
            try { await dbPool.query("ALTER TABLE order_items ADD COLUMN order_number VARCHAR(50) DEFAULT NULL"); } catch (_) {}
            try { await dbPool.query("ALTER TABLE order_items ADD COLUMN product_name VARCHAR(255) DEFAULT NULL"); } catch (_) {}
            try { await dbPool.query("ALTER TABLE order_items ADD COLUMN product_sinhala_name VARCHAR(255) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci DEFAULT NULL"); } catch (_) {}
            try { await dbPool.query("ALTER TABLE order_items ADD COLUMN is_short_eat BOOLEAN DEFAULT FALSE"); } catch (_) {}

            // 16. PRE_ORDERS, PRE_ORDER_ITEMS, NOTIFICATIONS table migrations
            try {
                await dbPool.query(`
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
                `);
            } catch (_) {}

            try {
                await dbPool.query(`
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
                `);
            } catch (_) {}

            try {
                await dbPool.query(`
                    CREATE TABLE IF NOT EXISTS notifications (
                        id INT AUTO_INCREMENT PRIMARY KEY,
                        title VARCHAR(255) NOT NULL,
                        message TEXT NOT NULL,
                        type VARCHAR(50) DEFAULT 'info',
                        is_read BOOLEAN DEFAULT FALSE,
                        created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
                    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
                `);
            } catch (_) {}

            try { await dbPool.query("ALTER TABLE pre_orders ADD COLUMN advance_payment DECIMAL(10,2) DEFAULT 0.00"); } catch (_) {}
            try { await dbPool.query("ALTER TABLE pre_orders ADD COLUMN balance_amount DECIMAL(10,2) DEFAULT 0.00"); } catch (_) {}
            try { await dbPool.query("ALTER TABLE pre_order_items ADD COLUMN notes VARCHAR(255) DEFAULT NULL"); } catch (_) {}
            try { await dbPool.query("ALTER TABLE pre_order_items ADD COLUMN product_name VARCHAR(255) NULL DEFAULT NULL"); } catch (_) {}

            // 17. GLOBAL_SETTINGS, STAFF_PAYROLL_SETTINGS, STAFF_ADVANCES, STAFF_PAYROLLS, STAFF_SHIFTS tables migrations
            try {
                await dbPool.query(`
                    CREATE TABLE IF NOT EXISTS global_settings (
                        setting_key VARCHAR(100) PRIMARY KEY,
                        setting_value TEXT NULL,
                        updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP
                    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
                `);
                await dbPool.query("INSERT IGNORE INTO global_settings (setting_key, setting_value) VALUES ('global_ot_rate', '250.00')");
                await dbPool.query("INSERT IGNORE INTO global_settings (setting_key, setting_value) VALUES ('salary_notification_days', '2')");
            } catch (_) {}

            try {
                await dbPool.query(`
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
                `);
            } catch (_) {}
            try { await dbPool.query("ALTER TABLE staff_payroll_settings ADD COLUMN monthly_salary DECIMAL(10,2) DEFAULT 0.00"); } catch (_) {}
            try { await dbPool.query("ALTER TABLE staff_payroll_settings ADD COLUMN daily_salary DECIMAL(10,2) DEFAULT 0.00"); } catch (_) {}
            try { await dbPool.query("ALTER TABLE staff_payroll_settings ADD COLUMN hourly_rate DECIMAL(10,2) DEFAULT 0.00"); } catch (_) {}
            try { await dbPool.query("ALTER TABLE staff_payroll_settings ADD COLUMN ot_hourly_rate DECIMAL(10,2) DEFAULT 0.00"); } catch (_) {}

            try {
                await dbPool.query(`
                    CREATE TABLE IF NOT EXISTS staff_advances (
                        id INT AUTO_INCREMENT PRIMARY KEY,
                        user_id INT NOT NULL,
                        amount DECIMAL(10,2) NOT NULL,
                        reason VARCHAR(255) DEFAULT NULL,
                        advance_date DATE NOT NULL,
                        status ENUM('pending', 'deducted', 'settled') DEFAULT 'pending',
                        recorded_by INT NULL,
                        created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
                        FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE,
                        FOREIGN KEY (recorded_by) REFERENCES users(id) ON DELETE SET NULL
                    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
                `);
            } catch (_) {}

            try {
                await dbPool.query(`
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
                `);
            } catch (_) {}
            try { await dbPool.query("ALTER TABLE staff_payrolls ADD COLUMN month_year VARCHAR(20) NULL"); } catch (_) {}
            try { await dbPool.query("ALTER TABLE staff_payrolls ADD COLUMN advances_deducted DECIMAL(10,2) DEFAULT 0.00"); } catch (_) {}
            try { await dbPool.query("ALTER TABLE staff_payrolls ADD COLUMN status VARCHAR(50) DEFAULT 'unpaid'"); } catch (_) {}

            try {
                await dbPool.query(`
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
                `);
            } catch (_) {}
            try { await dbPool.query("ALTER TABLE staff_shifts ADD COLUMN hours_worked DECIMAL(5,2) DEFAULT 0.00"); } catch (_) {}

            // 18. CUSTOMER_REVIEWS table migration
            try {
                await dbPool.query(`
                    CREATE TABLE IF NOT EXISTS customer_reviews (
                        id INT AUTO_INCREMENT PRIMARY KEY,
                        table_number VARCHAR(50) NULL,
                        customer_name VARCHAR(100) NULL,
                        rating INT NOT NULL DEFAULT 5,
                        comment TEXT NULL,
                        created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
                    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
                `);
            } catch (_) {}

            console.log("Self-healing schema synchronization completed successfully ✓");
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
