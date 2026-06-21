const express = require('express');
const http = require('http');
const WebSocket = require('ws');
const cors = require('cors');
const bcrypt = require('bcryptjs');
const jwt = require('jsonwebtoken');
const multer = require('multer');
const xlsx = require('xlsx');
require('dotenv').config();

const db = require('./db');

const upload = multer({ storage: multer.memoryStorage() });

const app = express();
const server = http.createServer(app);
const wss = new WebSocket.Server({ server });

const PORT = process.env.PORT || 3000;
const JWT_SECRET = process.env.JWT_SECRET || 'hotel_pos_super_secret_key_123';

app.use(cors());
app.use(express.json({ limit: '50mb' }));
app.use(express.urlencoded({ limit: '50mb', extended: true }));

// WebSocket Clients Map
const clients = new Set();

wss.on('connection', (ws) => {
    clients.add(ws);
    console.log(`New WebSocket client connected. Total clients: ${clients.size}`);
    
    ws.on('close', () => {
        clients.delete(ws);
        console.log(`WebSocket client disconnected. Total clients: ${clients.size}`);
    });
    
    ws.on('message', (message) => {
        try {
            const data = JSON.parse(message);
            console.log('Received WebSocket message:', data);
            // Broadcast messages to other clients (e.g. order-update, card-machine-feedback)
            broadcast(data, ws);
        } catch (err) {
            console.error('Error parsing WebSocket message:', err);
        }
    });
});

function broadcast(data, excludeWs = null) {
    const messageStr = JSON.stringify(data);
    clients.forEach((client) => {
        if (client !== excludeWs && client.readyState === WebSocket.OPEN) {
            client.send(messageStr);
        }
    });
}

// Authentication Middleware
function authenticateToken(req, res, next) {
    const authHeader = req.headers['authorization'];
    const token = authHeader && authHeader.split(' ')[1];
    
    if (!token) return res.status(401).json({ error: 'Access token required' });
    
    jwt.verify(token, JWT_SECRET, (err, user) => {
        if (err) return res.status(403).json({ error: 'Invalid or expired token' });
        req.user = user;
        next();
    });
}

// Audit Log Helper
async function logAudit(actionType, tableName, recordId, details, userId) {
    try {
        await db.query(
            'INSERT INTO audit_logs (action_type, table_name, record_id, details, user_id) VALUES (?, ?, ?, ?, ?)',
            [actionType, tableName, recordId, details, userId]
        );
        // Broadcast audit update
        broadcast({ type: 'audit_logged', data: { actionType, details, userId, timestamp: new Date() } });
    } catch (err) {
        console.error('Audit logging failed:', err);
    }
}

// ----------------------------------------------------
// AUTHENTICATION ENDPOINTS
// ----------------------------------------------------

app.get('/api/diagnostic', async (req, res) => {
    try {
        const tables = await db.query("SHOW TABLES");
        const users = await db.query("SELECT * FROM users");
        
        const testCompare = {};
        for (const u of users) {
            testCompare[u.username] = {
                matches_123456: bcrypt.compareSync('123456', u.password_hash),
                matches_1234: bcrypt.compareSync('1234', u.password_hash),
                hash: u.password_hash
            };
        }
        
        res.json({
            status: "connected",
            tables: tables.map(t => Object.values(t)[0]),
            users: users.map(u => ({ id: u.id, name: u.name, username: u.username, role: u.role, status: u.status })),
            testCompare
        });
    } catch (err) {
        res.status(500).json({ error: err.message });
    }
});

app.post('/api/auth/login', async (req, res) => {
    const { username, password } = req.body;
    try {
        const users = await db.query('SELECT * FROM users WHERE username = ?', [username]);
        if (users.length === 0) {
            return res.status(400).json({ error: 'User not found' });
        }
        
        const user = users[0];
        if (user.status !== 'active') {
            return res.status(403).json({ error: 'User account is inactive' });
        }
        
        const validPassword = await bcrypt.compare(password, user.password_hash);
        if (!validPassword) {
            return res.status(400).json({ error: 'Invalid password' });
        }
        
        const token = jwt.sign({ id: user.id, username: user.username, role: user.role }, JWT_SECRET, { expiresIn: '24h' });
        
        await logAudit('login', 'users', user.id, `User ${username} logged in.`, user.id);
        
        res.json({
            token,
            user: { id: user.id, name: user.name, username: user.username, role: user.role, image_base64: user.image_base64 }
        });
    } catch (err) {
        res.status(500).json({ error: err.message });
    }
});

// ----------------------------------------------------
// PRODUCT & CATEGORY ENDPOINTS (Happy Hour integration)
// ----------------------------------------------------

app.get('/api/categories', async (req, res) => {
    try {
        const categories = await db.query('SELECT * FROM categories WHERE status = "active"');
        res.json(categories);
    } catch (err) {
        res.status(500).json({ error: err.message });
    }
});

app.get('/api/products', async (req, res) => {
    const showAll = req.query.all === 'true';
    try {
        // Fetch products along with active happy hour pricing
        const products = await db.query(`
            SELECT p.*, h.promo_price, h.start_time, h.end_time, h.days_of_week
            FROM products p
            LEFT JOIN happy_hour_pricing h ON p.id = h.product_id AND h.status = 'active'
            ${showAll ? '' : "WHERE p.status = 'active'"}
        `);
        
        // Map products and calculate if happy hour is currently active
        const currentTime = new Date();
        const currentDay = currentTime.getDay(); // 0=Sunday, 1=Monday...
        const currentDayFormatted = currentDay === 0 ? 7 : currentDay; // map 0 to 7 (Sun)
        const timeString = currentTime.toTimeString().split(' ')[0]; // "HH:MM:SS"
        
        const productsWithPricing = products.map(p => {
            let activePrice = Number(p.price);
            let isHappyHour = false;
            
            if (p.promo_price) {
                const days = p.days_of_week.split(',').map(Number);
                if (days.includes(currentDayFormatted)) {
                    if (timeString >= p.start_time && timeString <= p.end_time) {
                        activePrice = Number(p.promo_price);
                        isHappyHour = true;
                    }
                }
            }
            
            return {
                id: p.id,
                name: p.name,
                sinhala_name: p.sinhala_name,
                description: p.description,
                category_id: p.category_id,
                price: Number(p.price),
                cost: Number(p.cost),
                active_price: activePrice,
                is_happy_hour: isHappyHour,
                barcode: p.barcode,
                stock_qty: p.stock_qty,
                min_stock_level: p.min_stock_level,
                is_short_eat: !!p.is_short_eat,
                image_base64: p.image_base64,
                status: p.status,
                item_type: p.item_type || 'Veg',
                tax: p.tax !== null ? Number(p.tax) : 0.00,
                is_featured: !!p.is_featured,
                caution: p.caution
            };
        });
        
        res.json(productsWithPricing);
    } catch (err) {
        res.status(500).json({ error: err.message });
    }
});

// Stock Adjustments / Entering (requires senior level)
app.post('/api/products/:id/stock', authenticateToken, async (req, res) => {
    const { id } = req.params;
    const { change_qty, type, reason } = req.body; // type: 'purchase', 'adjustment', 'wastage'
    
    if (req.user.role !== 'admin' && req.user.role !== 'owner') {
        return res.status(403).json({ error: 'Unauthorized. Only admins or owners can adjust stock.' });
    }
    
    try {
        // Update product stock
        await db.query('UPDATE products SET stock_qty = stock_qty + ? WHERE id = ?', [change_qty, id]);
        // Insert stock log
        await db.query(
            'INSERT INTO stock_logs (product_id, change_qty, type, reason, user_id) VALUES (?, ?, ?, ?, ?)',
            [id, change_qty, type, reason, req.user.id]
        );
        // Log activity
        await logAudit('edit_stock', 'products', id, `Stock adjusted by ${change_qty} units (Type: ${type}). Reason: ${reason || 'N/A'}`, req.user.id);
        
        // Fetch updated product
        const [product] = await db.query('SELECT * FROM products WHERE id = ?', [id]);
        
        // Send alert if low stock
        if (product.stock_qty <= product.min_stock_level) {
            broadcast({ type: 'low_stock_alert', data: { productId: product.id, name: product.name, stock: product.stock_qty } });
        }
        
        // Broadcast stock update
        broadcast({ type: 'stock_updated', data: { productId: id, stock_qty: product.stock_qty } });
        
        res.json(product);
    } catch (err) {
        res.status(500).json({ error: err.message });
    }
});

// Manual Product CRUD - Create Product
app.post('/api/products', authenticateToken, async (req, res) => {
    if (req.user.role !== 'admin' && req.user.role !== 'owner') {
        return res.status(403).json({ error: 'Unauthorized' });
    }
    const {
        name, sinhala_name, description, category_id, price, cost, barcode,
        stock_qty, min_stock_level, is_short_eat, status, image_base64,
        item_type, tax, is_featured, caution
    } = req.body;
    
    try {
        const result = await db.query(`
            INSERT INTO products (
                name, sinhala_name, description, category_id, price, cost, barcode,
                stock_qty, min_stock_level, is_short_eat, status, image_base64,
                item_type, tax, is_featured, caution
            ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
        `, [
            name, sinhala_name || null, description || null, category_id, price, cost || 0.00, barcode || null,
            stock_qty || 0, min_stock_level || 10, is_short_eat ? 1 : 0, status || 'active', image_base64 || null,
            item_type || 'Veg', tax || 0.00, is_featured ? 1 : 0, caution || null
        ]);
        
        const newId = result.insertId;
        const [product] = await db.query('SELECT * FROM products WHERE id = ?', [newId]);
        
        await logAudit('edit_stock', 'products', newId, `Product ${name} created manually.`, req.user.id);
        broadcast({ type: 'database_synchronized' });
        
        res.json(product);
    } catch (err) {
        res.status(500).json({ error: err.message });
    }
});

// Manual Product CRUD - Update Product
app.put('/api/products/:id', authenticateToken, async (req, res) => {
    if (req.user.role !== 'admin' && req.user.role !== 'owner') {
        return res.status(403).json({ error: 'Unauthorized' });
    }
    const { id } = req.params;
    const {
        name, sinhala_name, description, category_id, price, cost, barcode,
        stock_qty, min_stock_level, is_short_eat, status, image_base64,
        item_type, tax, is_featured, caution
    } = req.body;
    
    try {
        await db.query(`
            UPDATE products SET
                name = ?, sinhala_name = ?, description = ?, category_id = ?, price = ?, cost = ?, barcode = ?,
                stock_qty = ?, min_stock_level = ?, is_short_eat = ?, status = ?, image_base64 = ?,
                item_type = ?, tax = ?, is_featured = ?, caution = ?
            WHERE id = ?
        `, [
            name, sinhala_name || null, description || null, category_id, price, cost || 0.00, barcode || null,
            stock_qty || 0, min_stock_level || 10, is_short_eat ? 1 : 0, status || 'active', image_base64 || null,
            item_type || 'Veg', tax || 0.00, is_featured ? 1 : 0, caution || null,
            id
        ]);
        
        const [product] = await db.query('SELECT * FROM products WHERE id = ?', [id]);
        
        await logAudit('edit_stock', 'products', id, `Product ${name} updated manually.`, req.user.id);
        broadcast({ type: 'database_synchronized' });
        
        res.json(product);
    } catch (err) {
        res.status(500).json({ error: err.message });
    }
});

// Manual Product CRUD - Delete Product (Hard delete if unused, soft delete to 'inactive' if has order/stock references)
app.delete('/api/products/:id', authenticateToken, async (req, res) => {
    if (req.user.role !== 'admin' && req.user.role !== 'owner') {
        return res.status(403).json({ error: 'Unauthorized' });
    }
    const { id } = req.params;
    try {
        const products = await db.query('SELECT name FROM products WHERE id = ?', [id]);
        if (products.length === 0) return res.status(404).json({ error: 'Product not found' });
        const product = products[0];
        
        const refs = await db.query('SELECT COUNT(*) as count FROM order_items WHERE product_id = ?', [id]);
        const stockLogsRefs = await db.query('SELECT COUNT(*) as count FROM stock_logs WHERE product_id = ?', [id]);
        
        if (refs[0].count > 0 || stockLogsRefs[0].count > 0) {
            await db.query('UPDATE products SET status = "inactive" WHERE id = ?', [id]);
            await logAudit('edit_stock', 'products', id, `Product ${product.name} marked as inactive due to existing history.`, req.user.id);
            broadcast({ type: 'database_synchronized' });
            res.json({ success: true, message: 'Product has order/stock history. Marked as inactive.', softDeleted: true });
        } else {
            await db.query('DELETE FROM products WHERE id = ?', [id]);
            await logAudit('edit_stock', 'products', id, `Product ${product.name} permanently deleted.`, req.user.id);
            broadcast({ type: 'database_synchronized' });
            res.json({ success: true, message: 'Product deleted permanently.', softDeleted: false });
        }
    } catch (err) {
        res.status(500).json({ error: err.message });
    }
});

// Excel Product Import - Synchronizes DB with Excel data
app.post('/api/products/import', authenticateToken, upload.single('file'), async (req, res) => {
    if (req.user.role !== 'admin' && req.user.role !== 'owner') {
        return res.status(403).json({ error: 'Unauthorized' });
    }
    if (!req.file) {
        return res.status(400).json({ error: 'No file uploaded' });
    }
    
    const dbPool = await db.getPool();
    const conn = await dbPool.getConnection();
    
    try {
        await conn.beginTransaction();
        
        // Parse Excel file
        const workbook = xlsx.read(req.file.buffer, { type: 'buffer' });
        const sheetName = workbook.SheetNames[0];
        const worksheet = workbook.Sheets[sheetName];
        const rows = xlsx.utils.sheet_to_json(worksheet);
        
        // Match items by Name. Fetch all categories first.
        const [categories] = await conn.query('SELECT * FROM categories');
        const categoryMap = {}; // name.toLowerCase() -> id
        categories.forEach(c => {
            categoryMap[c.name.toLowerCase()] = c.id;
        });
        
        // Fetch existing products
        const [existingProducts] = await conn.query('SELECT * FROM products');
        const existingProductsMap = {}; // name.toLowerCase() -> product
        existingProducts.forEach(p => {
            existingProductsMap[p.name.toLowerCase()] = p;
        });
        
        const importedNames = new Set();
        
        for (const row of rows) {
            const name = row['Name'] || row['name'];
            if (!name) continue;
            
            const categoryName = row['Category'] || row['category'];
            const price = Number(row['Price'] || row['price'] || 0);
            const itemType = row['Item Type'] || row['item_type'] || 'Veg';
            const tax = Number(row['Tax'] || row['tax'] || 0);
            const statusStr = row['Status'] || row['status'] || 'Active';
            const featuredStr = row['Featured'] || row['featured'] || 'No';
            const caution = row['Caution'] || row['caution'] || null;
            const description = row['Description'] || row['description'] || null;
            
            const status = statusStr.toLowerCase() === 'inactive' ? 'inactive' : 'active';
            const isFeatured = (featuredStr.toLowerCase() === 'yes' || featuredStr.toLowerCase() === 'true') ? 1 : 0;
            
            importedNames.add(name.toLowerCase());
            
            // Resolve category ID (Create new category automatically if not found)
            let categoryId = null;
            if (categoryName) {
                const catKey = categoryName.trim().toLowerCase();
                if (categoryMap[catKey]) {
                    categoryId = categoryMap[catKey];
                } else {
                    const [catResult] = await conn.query('INSERT INTO categories (name) VALUES (?)', [categoryName.trim()]);
                    categoryId = catResult.insertId;
                    categoryMap[catKey] = categoryId;
                }
            } else {
                if (categories.length > 0) {
                    categoryId = categories[0].id;
                } else {
                    const [catResult] = await conn.query('INSERT INTO categories (name) VALUES ("General")');
                    categoryId = catResult.insertId;
                    categoryMap['general'] = categoryId;
                }
            }
            
            if (existingProductsMap[name.toLowerCase()]) {
                const existing = existingProductsMap[name.toLowerCase()];
                await conn.query(`
                    UPDATE products SET
                        category_id = ?, price = ?, item_type = ?, tax = ?,
                        status = ?, is_featured = ?, caution = ?, description = ?
                    WHERE id = ?
                `, [categoryId, price, itemType, tax, status, isFeatured, caution, description, existing.id]);
            } else {
                await conn.query(`
                    INSERT INTO products (
                        name, category_id, price, cost, stock_qty, min_stock_level,
                        is_short_eat, status, item_type, tax, is_featured, caution, description
                    ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                `, [
                    name, categoryId, price, price * 0.6, 0, 10,
                    0, status, itemType, tax, isFeatured, caution, description
                ]);
            }
        }
        
        // Deletion stage: Products in DB but NOT in the excel import
        for (const existing of existingProducts) {
            if (!importedNames.has(existing.name.toLowerCase())) {
                const [refs] = await conn.query('SELECT COUNT(*) as count FROM order_items WHERE product_id = ?', [existing.id]);
                const [stockLogsRefs] = await conn.query('SELECT COUNT(*) as count FROM stock_logs WHERE product_id = ?', [existing.id]);
                
                if (refs[0].count > 0 || stockLogsRefs[0].count > 0) {
                    await conn.query('UPDATE products SET status = "inactive" WHERE id = ?', [existing.id]);
                } else {
                    await conn.query('DELETE FROM products WHERE id = ?', [existing.id]);
                }
            }
        }
        
        await conn.commit();
        await logAudit('edit_stock', 'products', null, `Imported products Excel sheet containing ${rows.length} rows.`, req.user.id);
        broadcast({ type: 'database_synchronized' });
        
        res.json({ success: true, message: `Successfully synchronized ${rows.length} products.` });
    } catch (err) {
        await conn.rollback();
        res.status(500).json({ error: err.message });
    } finally {
        conn.release();
    }
});

// Excel Product Export - Downloads all products in Excel
app.get('/api/products/export', authenticateToken, async (req, res) => {
    try {
        const products = await db.query(`
            SELECT p.*, c.name as category_name
            FROM products p
            LEFT JOIN categories c ON p.category_id = c.id
        `);
        
        const data = products.map(p => ({
            'Name': p.name,
            'Category': p.category_name || '',
            'Price': Number(p.price),
            'Item Type': p.item_type || 'Veg',
            'Tax': Number(p.tax || 0),
            'Status': p.status === 'active' ? 'Active' : 'Inactive',
            'Featured': p.is_featured ? 'Yes' : 'No',
            'Caution': p.caution || '',
            'Description': p.description || ''
        }));
        
        const worksheet = xlsx.utils.json_to_sheet(data);
        const workbook = xlsx.utils.book_new();
        xlsx.utils.book_append_sheet(workbook, worksheet, 'Products');
        
        const buffer = xlsx.write(workbook, { type: 'buffer', bookType: 'xlsx' });
        
        res.setHeader('Content-Disposition', 'attachment; filename=products_export.xlsx');
        res.setHeader('Content-Type', 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet');
        res.send(buffer);
    } catch (err) {
        res.status(500).json({ error: err.message });
    }
});

// Happy Hour management
app.post('/api/happyhour', authenticateToken, async (req, res) => {
    if (req.user.role !== 'admin' && req.user.role !== 'owner') {
        return res.status(403).json({ error: 'Unauthorized' });
    }
    const { product_id, promo_price, start_time, end_time, days_of_week } = req.body;
    try {
        // Deactivate previous active promos for this product
        await db.query('UPDATE happy_hour_pricing SET status = "inactive" WHERE product_id = ?', [product_id]);
        
        const result = await db.query(
            'INSERT INTO happy_hour_pricing (product_id, promo_price, start_time, end_time, days_of_week) VALUES (?, ?, ?, ?, ?)',
            [product_id, promo_price, start_time, end_time, days_of_week]
        );
        
        await logAudit('change_price', 'products', product_id, `Happy hour pricing configured to LKR ${promo_price}`, req.user.id);
        broadcast({ type: 'happy_hour_updated' });
        
        res.json({ success: true, insertId: result.insertId });
    } catch (err) {
        res.status(500).json({ error: err.message });
    }
});

// ----------------------------------------------------
// TABLE MANAGEMENT ENDPOINTS
// ----------------------------------------------------

app.get('/api/tables', async (req, res) => {
    try {
        const diningTables = await db.query('SELECT * FROM dining_tables');
        res.json(diningTables);
    } catch (err) {
        res.status(500).json({ error: err.message });
    }
});

app.put('/api/tables/:id/status', authenticateToken, async (req, res) => {
    const { id } = req.params;
    const { status, steward_name, current_order_id } = req.body; // status: 'empty', 'seated', 'billing'
    try {
        await db.query(
            'UPDATE dining_tables SET status = ?, steward_name = ?, current_order_id = ? WHERE id = ?',
            [status, steward_name || null, current_order_id || null, id]
        );
        
        const [updatedTable] = await db.query('SELECT * FROM dining_tables WHERE id = ?', [id]);
        
        // Broadcast table status update to all terminals
        broadcast({ type: 'table_status_changed', data: updatedTable });
        
        res.json(updatedTable);
    } catch (err) {
        res.status(500).json({ error: err.message });
    }
});

// Create Dining Table
app.post('/api/tables', authenticateToken, async (req, res) => {
    if (req.user.role !== 'admin' && req.user.role !== 'owner') {
        return res.status(403).json({ error: 'Unauthorized' });
    }
    const { table_number, capacity, active_status } = req.body;
    try {
        const result = await db.query(
            'INSERT INTO dining_tables (table_number, capacity, active_status) VALUES (?, ?, ?)',
            [table_number, capacity, active_status || 'active']
        );
        const newId = result.insertId;
        const [table] = await db.query('SELECT * FROM dining_tables WHERE id = ?', [newId]);
        
        await logAudit('modify_bill', 'dining_tables', newId, `Table ${table_number} created manually.`, req.user.id);
        broadcast({ type: 'table_status_changed', data: table });
        
        res.json(table);
    } catch (err) {
        res.status(500).json({ error: err.message });
    }
});

// Update Dining Table
app.put('/api/tables/:id', authenticateToken, async (req, res) => {
    if (req.user.role !== 'admin' && req.user.role !== 'owner') {
        return res.status(403).json({ error: 'Unauthorized' });
    }
    const { id } = req.params;
    const { table_number, capacity, active_status } = req.body;
    try {
        await db.query(
            'UPDATE dining_tables SET table_number = ?, capacity = ?, active_status = ? WHERE id = ?',
            [table_number, capacity, active_status || 'active', id]
        );
        const [table] = await db.query('SELECT * FROM dining_tables WHERE id = ?', [id]);
        
        await logAudit('modify_bill', 'dining_tables', id, `Table ${table_number} updated manually.`, req.user.id);
        broadcast({ type: 'table_status_changed', data: table });
        
        res.json(table);
    } catch (err) {
        res.status(500).json({ error: err.message });
    }
});

// Delete Dining Table (hard delete if unused, soft delete to inactive if referenced in orders)
app.delete('/api/tables/:id', authenticateToken, async (req, res) => {
    if (req.user.role !== 'admin' && req.user.role !== 'owner') {
        return res.status(403).json({ error: 'Unauthorized' });
    }
    const { id } = req.params;
    try {
        const tables = await db.query('SELECT table_number FROM dining_tables WHERE id = ?', [id]);
        if (tables.length === 0) return res.status(404).json({ error: 'Table not found' });
        const table = tables[0];
        
        const refs = await db.query('SELECT COUNT(*) as count FROM orders WHERE table_id = ?', [id]);
        
        if (refs[0].count > 0) {
            await db.query('UPDATE dining_tables SET active_status = "inactive" WHERE id = ?', [id]);
            await logAudit('modify_bill', 'dining_tables', id, `Table ${table.table_number} marked as inactive due to order history.`, req.user.id);
            // Broadcast so all terminals reload
            broadcast({ type: 'table_status_changed', data: { id, active_status: 'inactive' } });
            res.json({ success: true, message: 'Table has order history. Marked as inactive.', softDeleted: true });
        } else {
            await db.query('DELETE FROM dining_tables WHERE id = ?', [id]);
            await logAudit('modify_bill', 'dining_tables', id, `Table ${table.table_number} permanently deleted.`, req.user.id);
            // Broadcast so all terminals reload
            broadcast({ type: 'table_status_changed', data: { id, deleted: true } });
            res.json({ success: true, message: 'Table deleted permanently.', softDeleted: false });
        }
    } catch (err) {
        res.status(500).json({ error: err.message });
    }
});

// ----------------------------------------------------
// CUSTOMER & CREDIT MANAGEMENT ENDPOINTS
// ----------------------------------------------------

app.get('/api/customers', async (req, res) => {
    try {
        const customers = await db.query('SELECT * FROM customers');
        res.json(customers);
    } catch (err) {
        res.status(500).json({ error: err.message });
    }
});

app.post('/api/customers', authenticateToken, async (req, res) => {
    const { name, phone, birthday, favorite_items, credit_limit, image_base64 } = req.body;
    try {
        const result = await db.query(
            'INSERT INTO customers (name, phone, birthday, favorite_items, credit_limit, image_base64) VALUES (?, ?, ?, ?, ?, ?)',
            [name, phone, birthday || null, favorite_items || null, credit_limit || 0.00, image_base64 || null]
        );
        const newCustId = result.insertId;
        const [newCustomer] = await db.query('SELECT * FROM customers WHERE id = ?', [newCustId]);
        res.json(newCustomer);
    } catch (err) {
        res.status(500).json({ error: err.message });
    }
});

// Settle outstanding balances (weekly billing settlement)
app.post('/api/credit/settle', authenticateToken, async (req, res) => {
    const { customer_id, amount, payment_method } = req.body;
    try {
        // Deduct from outstanding balance
        await db.query(
            'UPDATE customers SET outstanding_balance = outstanding_balance - ? WHERE id = ?',
            [amount, customer_id]
        );
        // Insert credit settlement log
        await db.query(
            'INSERT INTO credit_settlements (customer_id, amount, payment_method, recorded_by) VALUES (?, ?, ?, ?)',
            [customer_id, amount, payment_method, req.user.id]
        );
        
        const [customer] = await db.query('SELECT * FROM customers WHERE id = ?', [customer_id]);
        
        await logAudit('modify_bill', 'customers', customer_id, `Settled LKR ${amount} credit balance via ${payment_method}`, req.user.id);
        
        res.json({ success: true, customer });
    } catch (err) {
        res.status(500).json({ error: err.message });
    }
});

// ----------------------------------------------------
// SHIFT & CASH DRAWER CONTROL
// ----------------------------------------------------

app.get('/api/shifts/current', authenticateToken, async (req, res) => {
    try {
        const currentShift = await db.query(
            'SELECT * FROM shifts WHERE status = "open" ORDER BY start_time DESC LIMIT 1'
        );
        res.json(currentShift[0] || null);
    } catch (err) {
        res.status(500).json({ error: err.message });
    }
});

app.post('/api/shifts/open', authenticateToken, async (req, res) => {
    const { opening_balance } = req.body;
    try {
        // Close any accidentally left open shifts
        await db.query('UPDATE shifts SET status = "closed", end_time = CURRENT_TIMESTAMP WHERE status = "open"');
        
        const result = await db.query(
            'INSERT INTO shifts (user_id, opening_balance) VALUES (?, ?)',
            [req.user.id, opening_balance]
        );
        
        const newShiftId = result.insertId;
        const [shift] = await db.query('SELECT * FROM shifts WHERE id = ?', [newShiftId]);
        
        await logAudit('modify_bill', 'shifts', newShiftId, `New shift opened with cash balance LKR ${opening_balance}`, req.user.id);
        
        res.json(shift);
    } catch (err) {
        res.status(500).json({ error: err.message });
    }
});

app.post('/api/shifts/close', authenticateToken, async (req, res) => {
    const { shift_id, closing_balance, actual_closing_balance } = req.body;
    try {
        await db.query(
            'UPDATE shifts SET end_time = CURRENT_TIMESTAMP, closing_balance = ?, actual_closing_balance = ?, status = "closed" WHERE id = ?',
            [closing_balance, actual_closing_balance, shift_id]
        );
        
        const [shift] = await db.query('SELECT * FROM shifts WHERE id = ?', [shift_id]);
        
        await logAudit('modify_bill', 'shifts', shift_id, `Shift closed. Expected: ${closing_balance}, Actual: ${actual_closing_balance}. Reconciliation variance: ${actual_closing_balance - closing_balance}`, req.user.id);
        
        res.json(shift);
    } catch (err) {
        res.status(500).json({ error: err.message });
    }
});

app.post('/api/shifts/drawer-log', authenticateToken, async (req, res) => {
    const { shift_id, type, amount, reason } = req.body; // type: 'cash_in', 'cash_out'
    try {
        await db.query(
            'INSERT INTO cash_drawer_logs (shift_id, type, amount, reason) VALUES (?, ?, ?, ?)',
            [shift_id, type, amount, reason]
        );
        res.json({ success: true });
    } catch (err) {
        res.status(500).json({ error: err.message });
    }
});

// ----------------------------------------------------
// EXPENSE ENDPOINTS
// ----------------------------------------------------

app.get('/api/expenses', authenticateToken, async (req, res) => {
    try {
        const expenses = await db.query('SELECT e.*, u.name as recorder_name FROM expenses e JOIN users u ON e.recorded_by = u.id ORDER BY expense_date DESC');
        res.json(expenses);
    } catch (err) {
        res.status(500).json({ error: err.message });
    }
});

app.post('/api/expenses', authenticateToken, async (req, res) => {
    const { title, amount, category, payment_source, expense_date } = req.body;
    try {
        const result = await db.query(
            'INSERT INTO expenses (title, amount, category, payment_source, recorded_by, expense_date) VALUES (?, ?, ?, ?, ?, ?)',
            [title, amount, category, payment_source, req.user.id, expense_date]
        );
        
        // If paid from drawer, add cash_out log to the active shift
        if (payment_source === 'drawer') {
            const openShifts = await db.query('SELECT * FROM shifts WHERE status = "open" LIMIT 1');
            if (openShifts.length > 0) {
                await db.query(
                    'INSERT INTO cash_drawer_logs (shift_id, type, amount, reason) VALUES (?, "cash_out", ?, ?)',
                    [openShifts[0].id, amount, `Expense: ${title}`]
                );
            }
        }
        
        res.json({ success: true, insertId: result.insertId });
    } catch (err) {
        res.status(500).json({ error: err.message });
    }
});

// ----------------------------------------------------
// BILLING PROCESS & ORDER ENDPOINTS
// ----------------------------------------------------

app.get('/api/orders', authenticateToken, async (req, res) => {
    try {
        const orders = await db.query('SELECT * FROM orders ORDER BY created_at DESC');
        res.json(orders);
    } catch (err) {
        res.status(500).json({ error: err.message });
    }
});

app.get('/api/orders/:id/items', authenticateToken, async (req, res) => {
    const { id } = req.params;
    try {
        const items = await db.query(`
            SELECT oi.*, p.name as product_name, p.sinhala_name as product_sinhala_name, p.is_short_eat
            FROM order_items oi
            JOIN products p ON oi.product_id = p.id
            WHERE oi.order_id = ?
        `, [id]);
        res.json(items);
    } catch (err) {
        res.status(500).json({ error: err.message });
    }
});

// Create Order (Dine-in / Takeaway / Delivery)
app.post('/api/orders', authenticateToken, async (req, res) => {
    const {
        table_id, order_type, delivery_platform, customer_id, steward_name,
        payment_method, subtotal, discount, total, items, status, payment_status,
        kot_printed, ack_printed, card_tx_reference
    } = req.body;
    
    // Obtain active shift
    const shifts = await db.query('SELECT * FROM shifts WHERE status = "open" LIMIT 1');
    if (shifts.length === 0) {
        return res.status(400).json({ error: 'No active shift found. Please open a shift first.' });
    }
    const activeShiftId = shifts[0].id;
    
    const dbPool = await db.getPool();
    const conn = await dbPool.getConnection();
    
    try {
        await conn.beginTransaction();
        
        // Generate unique order number (e.g. ORD-20260617-1004)
        const dateStr = new Date().toISOString().slice(0, 10).replace(/-/g, '');
        const [countResult] = await conn.query('SELECT COUNT(*) as count FROM orders WHERE DATE(created_at) = CURDATE()');
        const nextNum = (countResult[0].count + 1).toString().padStart(4, '0');
        const orderNumber = `ORD-${dateStr}-${nextNum}`;
        const barcode = orderNumber; // Barcode maps to order number
        
        // Insert order
        const [orderResult] = await conn.query(`
            INSERT INTO orders (
                order_number, table_id, order_type, delivery_platform, customer_id, steward_name,
                status, payment_status, payment_method, subtotal, discount, total, cashier_id,
                shift_id, kot_printed, ack_printed, card_tx_reference, barcode
            ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
        `, [
            orderNumber, table_id || null, order_type, delivery_platform || null, customer_id || null,
            steward_name || null, status || 'pending', payment_status || 'unpaid', payment_method || null,
            subtotal, discount, total, req.user.id, activeShiftId, kot_printed || false,
            ack_printed || false, card_tx_reference || null, barcode
        ]);
        
        const newOrderId = orderResult.insertId;
        
        // Insert order items & reduce stock counts
        for (const item of items) {
            await conn.query(`
                INSERT INTO order_items (order_id, product_id, quantity, price, notes, status)
                VALUES (?, ?, ?, ?, ?, ?)
            `, [newOrderId, item.product_id, item.quantity, item.price, item.notes || null, item.status || 'pending']);
            
            // Stock Reduction
            await conn.query('UPDATE products SET stock_qty = stock_qty - ? WHERE id = ?', [item.quantity, item.product_id]);
            
            // Insert Stock Log
            await conn.query(
                'INSERT INTO stock_logs (product_id, change_qty, type, reason, user_id) VALUES (?, ?, "sale", ?, ?)',
                [item.product_id, -item.quantity, `Sale Order: ${orderNumber}`, req.user.id]
            );
        }
        
        // Update Table Status if Dine-in
        if (order_type === 'dine_in' && table_id) {
            const tableStatus = payment_status === 'paid' ? 'empty' : (ack_printed ? 'billing' : 'seated');
            const currentOrderIdParam = payment_status === 'paid' ? null : newOrderId;
            const stewardParam = payment_status === 'paid' ? null : steward_name;
            await conn.query(
                'UPDATE dining_tables SET status = ?, current_order_id = ?, steward_name = ? WHERE id = ?',
                [tableStatus, currentOrderIdParam, stewardParam, table_id]
            );
        }
        
        // Add to Credit Person outstanding balance if credit payment method
        if (payment_method === 'credit' && customer_id) {
            await conn.query(
                'UPDATE customers SET outstanding_balance = outstanding_balance + ? WHERE id = ?',
                [total, customer_id]
            );
            await logAudit('modify_bill', 'customers', customer_id, `Added outstanding balance LKR ${total} via Credit Order: ${orderNumber}`, req.user.id);
        }
        
        await conn.commit();
        
        // Broadcast WebSocket notifications
        broadcast({ type: 'order_created', data: { id: newOrderId, order_number: orderNumber, status: status || 'pending', order_type } });
        if (order_type === 'dine_in' && table_id) {
            const [tbl] = await db.query('SELECT * FROM dining_tables WHERE id = ?', [table_id]);
            broadcast({ type: 'table_status_changed', data: tbl });
        }
        
        // Trigger voice message synthesis trigger for KDS
        if (kot_printed) {
            broadcast({ type: 'kot_trigger_voice', data: { orderNumber, items } });
        }
        
        res.json({ success: true, orderId: newOrderId, order_number: orderNumber });
    } catch (err) {
        await conn.rollback();
        res.status(500).json({ error: err.message });
    } finally {
        conn.release();
    }
});

// Update Order (Status, print checks, card reference)
app.put('/api/orders/:id', authenticateToken, async (req, res) => {
    const { id } = req.params;
    const { status, payment_status, payment_method, ack_printed, kot_printed, card_tx_reference, table_id } = req.body;
    try {
        let updateFields = [];
        let params = [];
        
        if (status) { updateFields.push('status = ?'); params.push(status); }
        if (payment_status) { updateFields.push('payment_status = ?'); params.push(payment_status); }
        if (payment_method) { updateFields.push('payment_method = ?'); params.push(payment_method); }
        if (ack_printed !== undefined) { updateFields.push('ack_printed = ?'); params.push(ack_printed); }
        if (kot_printed !== undefined) { updateFields.push('kot_printed = ?'); params.push(kot_printed); }
        if (card_tx_reference) { updateFields.push('card_tx_reference = ?'); params.push(card_tx_reference); }
        
        if (updateFields.length === 0) {
            return res.status(400).json({ error: 'No fields provided to update.' });
        }
        
        params.push(id);
        await db.query(`UPDATE orders SET ${updateFields.join(', ')} WHERE id = ?`, params);
        
        const [updatedOrder] = await db.query('SELECT * FROM orders WHERE id = ?', [id]);
        
        // If Dine-in Table, sync table state
        if (updatedOrder.table_id) {
            const tableStatus = updatedOrder.payment_status === 'paid' ? 'empty' : (updatedOrder.ack_printed ? 'billing' : 'seated');
            const orderParam = updatedOrder.payment_status === 'paid' ? null : updatedOrder.id;
            const stewardParam = updatedOrder.payment_status === 'paid' ? null : updatedOrder.steward_name;
            await db.query(
                'UPDATE dining_tables SET status = ?, current_order_id = ?, steward_name = ? WHERE id = ?',
                [tableStatus, orderParam, stewardParam, updatedOrder.table_id]
            );
            const [tbl] = await db.query('SELECT * FROM dining_tables WHERE id = ?', [updatedOrder.table_id]);
            broadcast({ type: 'table_status_changed', data: tbl });
        }
        
        if (status === 'cancelled') {
            // Restore inventory if cancelled
            const items = await db.query('SELECT * FROM order_items WHERE order_id = ?', [id]);
            for (const item of items) {
                await db.query('UPDATE products SET stock_qty = stock_qty + ? WHERE id = ?', [item.quantity, item.product_id]);
                await db.query(
                    'INSERT INTO stock_logs (product_id, change_qty, type, reason, user_id) VALUES (?, ?, "adjustment", ?, ?)',
                    [item.product_id, item.quantity, `Order Cancelled: ${updatedOrder.order_number}`, req.user.id]
                );
            }
            await logAudit('delete_bill', 'orders', id, `Order ${updatedOrder.order_number} was CANCELLED. Inventory restored.`, req.user.id);
        }
        
        broadcast({ type: 'order_updated', data: updatedOrder });
        
        res.json({ success: true, order: updatedOrder });
    } catch (err) {
        res.status(500).json({ error: err.message });
    }
});

// Barcode scanner lookup (Flowchart: scan acknowledgement bill barcode)
app.get('/api/orders/barcode/:barcode', authenticateToken, async (req, res) => {
    const { barcode } = req.params;
    try {
        const orders = await db.query('SELECT * FROM orders WHERE barcode = ?', [barcode]);
        if (orders.length === 0) {
            return res.status(404).json({ error: 'Order not found with this barcode/ticket number.' });
        }
        res.json(orders[0]);
    } catch (err) {
        res.status(500).json({ error: err.message });
    }
});

// 2-Way Card Machine integration simulator webhook/endpoint
app.post('/api/card-terminal/charge', authenticateToken, async (req, res) => {
    const { amount, order_number } = req.body;
    console.log(`Sending charge request to Card Machine: LKR ${amount} for order ${order_number}`);
    
    // Broadcast status to cashier terminal (loading state)
    broadcast({ type: 'card_machine_status', data: { state: 'processing', order_number, amount } });
    
    // Simulate card machine network lag and processing
    setTimeout(() => {
        const approved = Math.random() > 0.05; // 95% success rate
        const approvalCode = approved ? Math.floor(100000 + Math.random() * 900000).toString() : null;
        
        const responseData = {
            success: approved,
            order_number,
            amount,
            approval_code: approvalCode,
            error_msg: approved ? null : 'Transaction Declined by Host Server'
        };
        
        console.log(`Card Machine transaction response:`, responseData);
        // Broadcast success/fail back to terminal
        broadcast({ type: 'card_machine_feedback', data: responseData });
    }, 4000); // 4 seconds simulated delay
    
    res.json({ success: true, message: 'Transaction initiated on terminal' });
});

// LankaQR Generation
app.get('/api/lankaqr/generate', async (req, res) => {
    const { amount, order_number } = req.query;
    // Mock LankaQR Compliant string (EMVCo standard compliant formatted code)
    // LankaQR Compliant EMV payload format details:
    // Payload indicator, Merchant Category Code, Currency (LKR=144), Amount, Country Code (LK), Merchant Name, LankaQR identifier, etc.
    const lankaQRPayload = `00020101021226500013lk.lankaqr.pay011112345678901020499995204581253031445407${amount}5802LK5911HotelPOS-LK6007Colombo62230111${order_number}6304D1B9`;
    res.json({
        payload: lankaQRPayload,
        merchant_name: 'Hotel POS (PVT) Ltd',
        lkr_amount: amount,
        order_number: order_number
    });
});

// ----------------------------------------------------
// SYNCHRONIZATION ENDPOINT (LAN-first offline sync)
// ----------------------------------------------------
// Frontend calls this to upload offline orders and download latest server catalog

app.post('/api/sync', authenticateToken, async (req, res) => {
    const { offline_orders, offline_shifts, offline_expenses, offline_stock_logs, offline_audit_logs } = req.body;
    
    console.log(`Synchronization requested. Uploading offline changes: 
        Orders: ${offline_orders?.length || 0}, 
        Shifts: ${offline_shifts?.length || 0}, 
        Expenses: ${offline_expenses?.length || 0}`);
        
    const dbPool = await db.getPool();
    const conn = await dbPool.getConnection();
    
    try {
        await conn.beginTransaction();
        
        // Sync Shifts first
        if (offline_shifts && offline_shifts.length > 0) {
            for (const s of offline_shifts) {
                // Check if shift already exists
                const [existing] = await conn.query('SELECT id FROM shifts WHERE id = ?', [s.id]);
                if (existing.length === 0) {
                    await conn.query(
                        'INSERT INTO shifts (id, user_id, start_time, end_time, opening_balance, closing_balance, actual_closing_balance, status) VALUES (?, ?, ?, ?, ?, ?, ?, ?)',
                        [s.id, s.user_id, s.start_time, s.end_time, s.opening_balance, s.closing_balance, s.actual_closing_balance, s.status]
                    );
                } else {
                    await conn.query(
                        'UPDATE shifts SET end_time = ?, closing_balance = ?, actual_closing_balance = ?, status = ? WHERE id = ?',
                        [s.end_time, s.closing_balance, s.actual_closing_balance, s.status, s.id]
                    );
                }
            }
        }
        
        // Sync Orders and Order Items
        if (offline_orders && offline_orders.length > 0) {
            for (const o of offline_orders) {
                const [existing] = await conn.query('SELECT id FROM orders WHERE order_number = ?', [o.order_number]);
                if (existing.length === 0) {
                    // Sync the order
                    await conn.query(`
                        INSERT INTO orders (
                            order_number, table_id, order_type, delivery_platform, customer_id, steward_name,
                            status, payment_status, payment_method, subtotal, discount, total, cashier_id,
                            shift_id, kot_printed, ack_printed, card_tx_reference, barcode, created_at, sync_status
                        ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, 'synced')
                    `, [
                        o.order_number, o.table_id || null, o.order_type, o.delivery_platform || null, o.customer_id || null,
                        o.steward_name || null, o.status, o.payment_status, o.payment_method || null,
                        o.subtotal, o.discount, o.total, o.cashier_id, o.shift_id, o.kot_printed || false,
                        o.ack_printed || false, o.card_tx_reference || null, o.barcode, o.created_at
                    ]);
                    
                    // Sync items
                    if (o.items && o.items.length > 0) {
                        for (const item of o.items) {
                            await conn.query(`
                                INSERT INTO order_items (order_id, product_id, quantity, price, notes, status)
                                VALUES ((SELECT id FROM orders WHERE order_number = ?), ?, ?, ?, ?, ?)
                            `, [o.order_number, item.product_id, item.quantity, item.price, item.notes || null, item.status || 'pending']);
                            
                            // Adjust online stocks
                            await conn.query('UPDATE products SET stock_qty = stock_qty - ? WHERE id = ?', [item.quantity, item.product_id]);
                        }
                    }
                }
            }
        }
        
        // Sync Expenses
        if (offline_expenses && offline_expenses.length > 0) {
            for (const e of offline_expenses) {
                const [existing] = await conn.query('SELECT id FROM expenses WHERE id = ?', [e.id]);
                if (existing.length === 0) {
                    await conn.query(
                        'INSERT INTO expenses (id, title, amount, category, payment_source, recorded_by, expense_date, created_at) VALUES (?, ?, ?, ?, ?, ?, ?, ?)',
                        [e.id, e.title, e.amount, e.category, e.payment_source, e.recorded_by, e.expense_date, e.created_at]
                    );
                }
            }
        }
        
        // Sync Stock Logs
        if (offline_stock_logs && offline_stock_logs.length > 0) {
            for (const sl of offline_stock_logs) {
                await conn.query(
                    'INSERT INTO stock_logs (product_id, change_qty, type, reason, user_id, timestamp) VALUES (?, ?, ?, ?, ?, ?)',
                    [sl.product_id, sl.change_qty, sl.type, sl.reason, sl.user_id, sl.timestamp]
                );
            }
        }
        
        // Sync Audit Logs
        if (offline_audit_logs && offline_audit_logs.length > 0) {
            for (const al of offline_audit_logs) {
                await conn.query(
                    'INSERT INTO audit_logs (action_type, table_name, record_id, details, user_id, timestamp) VALUES (?, ?, ?, ?, ?, ?)',
                    [al.action_type, al.table_name, al.record_id, al.details, al.user_id, al.timestamp]
                );
            }
        }
        
        await conn.commit();
        console.log('Sync processing completed successfully.');
        
        // Pull latest states to return to client
        const categories = await db.query('SELECT * FROM categories WHERE status = "active"');
        const products = await db.query('SELECT * FROM products WHERE status = "active"');
        const diningTables = await db.query('SELECT * FROM dining_tables');
        const customers = await db.query('SELECT * FROM customers');
        
        res.json({
            success: true,
            categories,
            products,
            diningTables,
            customers
        });
        
        broadcast({ type: 'database_synchronized' });
    } catch (err) {
        await conn.rollback();
        console.error('Sync failed, transaction rolled back:', err);
        res.status(500).json({ error: err.message });
    } finally {
        conn.release();
    }
});

// ----------------------------------------------------
// REPORTS & DASHBOARD ENDPOINTS
// ----------------------------------------------------

app.get('/api/reports/dashboard', authenticateToken, async (req, res) => {
    try {
        const [{ total_sales }] = await db.query('SELECT COALESCE(SUM(total), 0) as total_sales FROM orders WHERE payment_status = "paid" AND DATE(created_at) = CURDATE()');
        const [{ total_orders }] = await db.query('SELECT COUNT(*) as total_orders FROM orders WHERE DATE(created_at) = CURDATE()');
        const [{ total_customers }] = await db.query('SELECT COUNT(*) as total_customers FROM customers');
        const [{ total_menu_items }] = await db.query('SELECT COUNT(*) as total_menu_items FROM products WHERE status = "active"');
        
        // Status counts
        const orderStatuses = await db.query('SELECT status, COUNT(*) as count FROM orders WHERE DATE(created_at) = CURDATE() GROUP BY status');
        
        // Top selling products
        const topSelling = await db.query(`
            SELECT p.name, SUM(oi.quantity) as qty, SUM(oi.quantity * oi.price) as revenue
            FROM order_items oi
            JOIN products p ON oi.product_id = p.id
            JOIN orders o ON oi.order_id = o.id
            WHERE o.payment_status = "paid" AND DATE(o.created_at) = CURDATE()
            GROUP BY p.id
            ORDER BY qty DESC
            LIMIT 5
        `);
        
        // Hourly Sales (dashboard graph)
        const hourlySales = await db.query(`
            SELECT HOUR(created_at) as hour, SUM(total) as sales
            FROM orders
            WHERE payment_status = "paid" AND DATE(created_at) = CURDATE()
            GROUP BY HOUR(created_at)
            ORDER BY hour
        `);
        
        // Payment method breakdown
        const payments = await db.query(`
            SELECT payment_method, SUM(total) as amount, COUNT(*) as count
            FROM orders
            WHERE payment_status = "paid" AND DATE(created_at) = CURDATE()
            GROUP BY payment_method
        `);
        
        const formattedTopSelling = topSelling.map(item => ({
            name: item.name,
            qty: Number(item.qty),
            revenue: Number(item.revenue)
        }));
        
        const formattedHourlySales = hourlySales.map(item => ({
            hour: Number(item.hour),
            sales: Number(item.sales)
        }));
        
        const formattedPayments = payments.map(item => ({
            payment_method: item.payment_method,
            amount: Number(item.amount),
            count: Number(item.count)
        }));
        
        res.json({
            summary: { 
                total_sales: Number(total_sales), 
                total_orders: Number(total_orders), 
                total_customers: Number(total_customers), 
                total_menu_items: Number(total_menu_items) 
            },
            statuses: orderStatuses.map(s => ({ status: s.status, count: Number(s.count) })),
            top_selling: formattedTopSelling,
            hourly_sales: formattedHourlySales,
            payment_methods: formattedPayments
        });
    } catch (err) {
        res.status(500).json({ error: err.message });
    }
});

// End of Day Summary API
app.get('/api/reports/eod', authenticateToken, async (req, res) => {
    try {
        const [sales] = await db.query(`
            SELECT payment_method, COALESCE(SUM(total), 0) as total, COUNT(*) as count
            FROM orders
            WHERE payment_status = "paid" AND DATE(created_at) = CURDATE()
            GROUP BY payment_method
        `);
        
        const [expenses] = await db.query(`
            SELECT category, COALESCE(SUM(amount), 0) as total
            FROM expenses
            WHERE expense_date = CURDATE()
            GROUP BY category
        `);
        
        const [{ credit_settlements }] = await db.query(`
            SELECT COALESCE(SUM(amount), 0) as credit_settlements
            FROM credit_settlements
            WHERE DATE(date_paid) = CURDATE()
        `);
        
        const formattedSales = sales.map(item => ({
            payment_method: item.payment_method,
            total: Number(item.total),
            count: Number(item.count)
        }));

        const formattedExpenses = expenses.map(item => ({
            category: item.category,
            total: Number(item.total)
        }));

        res.json({
            sales: formattedSales,
            expenses: formattedExpenses,
            credit_settlements: Number(credit_settlements)
        });
    } catch (err) {
        res.status(500).json({ error: err.message });
    }
});

// Historical Reports (monthly & yearly summaries, unaffected by weekly order deletion)
app.get('/api/reports/historical', authenticateToken, async (req, res) => {
    const { period } = req.query; // 'monthly' or 'yearly'
    try {
        let sql = '';
        if (period === 'yearly') {
            sql = `
                SELECT YEAR(created_at) as period, SUM(total) as revenue, COUNT(*) as total_orders
                FROM orders
                WHERE payment_status = "paid"
                GROUP BY YEAR(created_at)
                ORDER BY period DESC
            `;
        } else {
            sql = `
                SELECT DATE_FORMAT(created_at, '%Y-%m') as period, SUM(total) as revenue, COUNT(*) as total_orders
                FROM orders
                WHERE payment_status = "paid"
                GROUP BY DATE_FORMAT(created_at, '%Y-%m')
                ORDER BY period DESC
                LIMIT 12
            `;
        }
        const reports = await db.query(sql);
        const formattedReports = reports.map(item => ({
            period: item.period.toString(),
            revenue: Number(item.revenue),
            total_orders: Number(item.total_orders)
        }));
        res.json(formattedReports);
    } catch (err) {
        res.status(500).json({ error: err.message });
    }
});

// User Activity Logs API
app.get('/api/reports/logs', authenticateToken, async (req, res) => {
    try {
        const logs = await db.query(`
            SELECT al.*, u.username, u.role
            FROM audit_logs al
            JOIN users u ON al.user_id = u.id
            ORDER BY al.timestamp DESC
            LIMIT 100
        `);
        res.json(logs);
    } catch (err) {
        res.status(500).json({ error: err.message });
    }
});

// Start Server and Init Database
server.listen(PORT, async () => {
    console.log(`Hotel POS Server is running on port ${PORT}`);
    await db.initializeDatabase();
});
