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
