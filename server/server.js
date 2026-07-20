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

// Low Stock Notification Helper
async function checkLowStockNotification(productId) {
    try {
        const products = await db.query("SELECT * FROM products WHERE id = ?", [productId]);
        if (products.length === 0) return;
        const product = products[0];
        
        if (product.track_stock && product.stock_qty <= product.min_stock_level) {
            // Check if we already have an unread low stock notification for this product
            const existing = await db.query(
                "SELECT id FROM notifications WHERE type = 'low_stock' AND is_read = 0 AND message LIKE ?",
                [`%Product ${product.name} is low on stock%`]
            );
            if (existing.length === 0) {
                const title = "Low Stock Alert";
                const message = `Product ${product.name} is low on stock (${product.stock_qty} left)`;
                await db.query(
                    "INSERT INTO notifications (title, message, type) VALUES (?, ?, 'low_stock')",
                    [title, message]
                );
                broadcast({
                    type: 'new_notification',
                    data: {
                        title,
                        message,
                        type: 'low_stock',
                        created_at: new Date()
                    }
                });
            }
        }
    } catch (err) {
        console.error('Error checking low stock notification:', err);
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

// Create Product Category
app.post('/api/categories', authenticateToken, async (req, res) => {
    if (req.user.role !== 'admin' && req.user.role !== 'owner') {
        return res.status(403).json({ error: 'Unauthorized' });
    }
    const { name, image_base64 } = req.body;
    if (!name || name.trim() === '') {
        return res.status(400).json({ error: 'Category name is required' });
    }
    try {
        const result = await db.query(
            'INSERT INTO categories (name, image_base64, status) VALUES (?, ?, "active")',
            [name.trim(), image_base64 || null]
        );
        const newId = result.insertId;
        const [category] = await db.query('SELECT * FROM categories WHERE id = ?', [newId]);
        broadcast({ type: 'database_synchronized' });
        res.json(category);
    } catch (err) {
        res.status(500).json({ error: err.message });
    }
});

app.get('/api/products', async (req, res) => {
    const showAll = req.query.all === 'true';
    try {
        // Fetch products
        const products = await db.query(`
            SELECT p.*
            FROM products p
            ${showAll ? '' : "WHERE p.status = 'active'"}
        `);
        
        // Fetch all active happy hours
        const activeHappyHours = await db.query("SELECT * FROM happy_hour_pricing WHERE status = 'active'");
        
        // Map products and calculate if happy hour is currently active
        const currentTime = new Date();
        const currentDay = currentTime.getDay(); // 0=Sunday, 1=Monday...
        const currentDayFormatted = currentDay === 0 ? 7 : currentDay; // map 0 to 7 (Sun)
        const timeString = currentTime.toTimeString().split(' ')[0]; // "HH:MM:SS"
        
        const productsWithPricing = products.map(p => {
            let activePrice = Number(p.price);
            let isHappyHour = false;
            
            // Check if product is eligible for happy hour
            const isEligible = p.is_happy_hour_eligible === undefined || p.is_happy_hour_eligible === null ? true : !!p.is_happy_hour_eligible;
            
            if (isEligible) {
                // Find matching happy hour
                // 1. Look for product-specific happy hour
                let hhp = activeHappyHours.find(h => h.product_id === p.id);
                // 2. If not found, look for category-specific happy hour
                if (!hhp && p.category_id) {
                    hhp = activeHappyHours.find(h => h.category_id === p.category_id && (!h.product_id || h.product_id === 0 || h.product_id === '0'));
                }

                if (hhp && hhp.start_time && hhp.end_time && hhp.days_of_week) {
                    const days = hhp.days_of_week.split(',').map(Number);
                    if (days.includes(currentDayFormatted)) {
                        if (timeString >= hhp.start_time && timeString <= hhp.end_time) {
                            if (hhp.product_id && hhp.product_id !== 0 && hhp.product_id !== '0') {
                                activePrice = Number(hhp.promo_price);
                            } else {
                                // Category-level: hhp.promo_price acts as percentage discount
                                const discountPct = Number(hhp.promo_price);
                                activePrice = Number(p.price) * (1 - (discountPct / 100.0));
                                activePrice = Number(activePrice.toFixed(2));
                            }
                            isHappyHour = true;
                        }
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
                caution: p.caution,
                has_sizes: !!p.has_sizes,
                has_extras: !!p.has_extras,
                has_addons: !!p.has_addons,
                track_stock: p.track_stock === undefined || p.track_stock === null ? true : !!p.track_stock,
                is_happy_hour_eligible: p.is_happy_hour_eligible === undefined || p.is_happy_hour_eligible === null ? true : !!p.is_happy_hour_eligible,
                is_kot_item: !!p.is_kot_item,
                sizes: p.sizes ? JSON.parse(p.sizes) : [],
                extras: p.extras ? JSON.parse(p.extras) : [],
                addons: p.addons ? JSON.parse(p.addons) : [],
                ingredients: p.ingredients ? JSON.parse(p.ingredients) : []
            };
        });
        
        res.json(productsWithPricing);
    } catch (err) {
        res.status(500).json({ error: err.message });
    }
});

// Stock Adjustments / Entering (requires senior level)
app.get('/api/products/stock-logs', authenticateToken, async (req, res) => {
    try {
        const logs = await db.query(`
            SELECT sl.*, p.name as product_name, u.name as recorder_name 
            FROM stock_logs sl 
            JOIN products p ON sl.product_id = p.id 
            JOIN users u ON sl.user_id = u.id 
            ORDER BY sl.timestamp DESC 
            LIMIT 50
        `);
        res.json(logs);
    } catch (err) {
        res.status(500).json({ error: err.message });
    }
});

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
        await checkLowStockNotification(id);
        
        // Broadcast stock update
        broadcast({ type: 'stock_updated', data: { productId: id, stock_qty: product.stock_qty } });
        
        res.json(product);
    } catch (err) {
        res.status(500).json({ error: err.message });
    }
});

// ----------------------------------------------------
// INGREDIENTS STOCK ENDPOINTS
// ----------------------------------------------------
app.get('/api/ingredients', authenticateToken, async (req, res) => {
    try {
        const ingredients = await db.query('SELECT * FROM ingredients ORDER BY name ASC');
        res.json(ingredients);
    } catch (err) {
        res.status(500).json({ error: err.message });
    }
});

app.get('/api/ingredients/logs', authenticateToken, async (req, res) => {
    try {
        const logs = await db.query(`
            SELECT isl.*, i.name as ingredient_name, u.name as recorder_name 
            FROM ingredient_stock_logs isl 
            JOIN ingredients i ON isl.ingredient_id = i.id 
            JOIN users u ON isl.user_id = u.id 
            ORDER BY isl.timestamp DESC 
            LIMIT 50
        `);
        res.json(logs);
    } catch (err) {
        res.status(500).json({ error: err.message });
    }
});

app.post('/api/ingredients', authenticateToken, async (req, res) => {
    const { name, unit, min_stock_level } = req.body;
    if (req.user.role !== 'admin' && req.user.role !== 'owner') {
        return res.status(403).json({ error: 'Unauthorized. Only admins or owners can add ingredients.' });
    }
    if (!name || !unit) {
        return res.status(400).json({ error: 'Name and unit are required.' });
    }
    try {
        const result = await db.query(
            'INSERT INTO ingredients (name, stock_qty, unit, min_stock_level) VALUES (?, 0.00, ?, ?)',
            [name, unit, min_stock_level || 0.00]
        );
        await logAudit('edit_stock', 'ingredients', result.insertId, `Ingredient ${name} created manually.`, req.user.id);
        const [newIng] = await db.query('SELECT * FROM ingredients WHERE id = ?', [result.insertId]);
        res.json(newIng);
    } catch (err) {
        res.status(500).json({ error: err.message });
    }
});

app.put('/api/ingredients/:id', authenticateToken, async (req, res) => {
    const { id } = req.params;
    const { name, unit, min_stock_level } = req.body;
    if (req.user.role !== 'admin' && req.user.role !== 'owner') {
        return res.status(403).json({ error: 'Unauthorized. Only admins or owners can edit ingredients.' });
    }
    if (!name || !unit) {
        return res.status(400).json({ error: 'Name and unit are required.' });
    }
    try {
        await db.query(
            'UPDATE ingredients SET name = ?, unit = ?, min_stock_level = ? WHERE id = ?',
            [name, unit, min_stock_level || 0.00, id]
        );
        await logAudit('edit_stock', 'ingredients', id, `Ingredient ${name} details updated.`, req.user.id);
        const [updated] = await db.query('SELECT * FROM ingredients WHERE id = ?', [id]);
        
        // Broadcast WebSocket update
        if (req.app.get('wss')) {
            const wsMsg = JSON.stringify({ type: 'ingredient_stock_updated', data: { ingredientId: id } });
            req.app.get('wss').clients.forEach(client => {
                if (client.readyState === 1) {
                    client.send(wsMsg);
                }
            });
        }
        
        res.json(updated);
    } catch (err) {
        res.status(500).json({ error: err.message });
    }
});

app.delete('/api/ingredients/:id', authenticateToken, async (req, res) => {
    const { id } = req.params;
    if (req.user.role !== 'admin' && req.user.role !== 'owner') {
        return res.status(403).json({ error: 'Unauthorized. Only admins or owners can delete ingredients.' });
    }
    try {
        const [ing] = await db.query('SELECT name FROM ingredients WHERE id = ?', [id]);
        if (!ing) {
            return res.status(404).json({ error: 'Ingredient not found.' });
        }
        
        await db.query('DELETE FROM ingredients WHERE id = ?', [id]);
        await logAudit('edit_stock', 'ingredients', id, `Ingredient ${ing.name} deleted.`, req.user.id);
        
        // Broadcast WebSocket update
        if (req.app.get('wss')) {
            const wsMsg = JSON.stringify({ type: 'ingredient_stock_updated', data: { ingredientId: id } });
            req.app.get('wss').clients.forEach(client => {
                if (client.readyState === 1) {
                    client.send(wsMsg);
                }
            });
        }
        
        res.json({ message: 'Ingredient deleted successfully.' });
    } catch (err) {
        res.status(500).json({ error: err.message });
    }
});

app.post('/api/ingredients/:id/stock', authenticateToken, async (req, res) => {
    const { id } = req.params;
    const { change_qty, type, reason } = req.body; // type: 'purchase', 'adjustment', 'wastage'
    
    if (req.user.role !== 'admin' && req.user.role !== 'owner') {
        return res.status(403).json({ error: 'Unauthorized. Only admins or owners can adjust stock.' });
    }
    
    try {
        // Update ingredient stock
        await db.query('UPDATE ingredients SET stock_qty = stock_qty + ? WHERE id = ?', [change_qty, id]);
        
        // Insert ingredient stock log
        await db.query(
            'INSERT INTO ingredient_stock_logs (ingredient_id, change_qty, type, reason, user_id) VALUES (?, ?, ?, ?, ?)',
            [id, change_qty, type, reason, req.user.id]
        );
        
        // Log audit trail
        await logAudit('edit_stock', 'ingredients', id, `Ingredient stock adjusted by ${change_qty} units (Type: ${type}). Reason: ${reason || 'N/A'}`, req.user.id);
        
        // Broadcast stock update
        broadcast({ type: 'ingredient_stock_updated', data: { ingredientId: id } });
        
        // Fetch updated ingredient
        const [updated] = await db.query('SELECT * FROM ingredients WHERE id = ?', [id]);
        res.json(updated);
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
        item_type, tax, is_featured, caution,
        has_sizes, has_extras, has_addons, track_stock,
        sizes, extras, addons, is_happy_hour_eligible, ingredients, is_kot_item
    } = req.body;
    
    try {
        const result = await db.query(`
            INSERT INTO products (
                name, sinhala_name, description, category_id, price, cost, barcode,
                stock_qty, min_stock_level, is_short_eat, status, image_base64,
                item_type, tax, is_featured, caution,
                has_sizes, has_extras, has_addons, track_stock,
                sizes, extras, addons, is_happy_hour_eligible, ingredients, is_kot_item
            ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
        `, [
            name, sinhala_name || null, description || null, category_id, price, cost || 0.00, barcode || null,
            stock_qty || 0, min_stock_level || 10, is_short_eat ? 1 : 0, status || 'active', image_base64 || null,
            item_type || 'Veg', tax || 0.00, is_featured ? 1 : 0, caution || null,
            has_sizes ? 1 : 0, has_extras ? 1 : 0, has_addons ? 1 : 0, track_stock !== undefined ? (track_stock ? 1 : 0) : 1,
            sizes ? JSON.stringify(sizes) : null,
            extras ? JSON.stringify(extras) : null,
            addons ? JSON.stringify(addons) : null,
            is_happy_hour_eligible !== undefined ? (is_happy_hour_eligible ? 1 : 0) : 1,
            ingredients ? JSON.stringify(ingredients) : null,
            is_kot_item ? 1 : 0
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
        item_type, tax, is_featured, caution,
        has_sizes, has_extras, has_addons, track_stock,
        sizes, extras, addons, is_happy_hour_eligible, ingredients, is_kot_item
    } = req.body;
    
    try {
        await db.query(`
            UPDATE products SET
                name = ?, sinhala_name = ?, description = ?, category_id = ?, price = ?, cost = ?, barcode = ?,
                stock_qty = ?, min_stock_level = ?, is_short_eat = ?, status = ?, image_base64 = ?,
                item_type = ?, tax = ?, is_featured = ?, caution = ?,
                has_sizes = ?, has_extras = ?, has_addons = ?, track_stock = ?,
                sizes = ?, extras = ?, addons = ?, is_happy_hour_eligible = ?, ingredients = ?, is_kot_item = ?
            WHERE id = ?
        `, [
            name, sinhala_name || null, description || null, category_id, price, cost || 0.00, barcode || null,
            stock_qty || 0, min_stock_level || 10, is_short_eat ? 1 : 0, status || 'active', image_base64 || null,
            item_type || 'Veg', tax || 0.00, is_featured ? 1 : 0, caution || null,
            has_sizes ? 1 : 0, has_extras ? 1 : 0, has_addons ? 1 : 0, track_stock !== undefined ? (track_stock ? 1 : 0) : 1,
            sizes ? JSON.stringify(sizes) : null,
            extras ? JSON.stringify(extras) : null,
            addons ? JSON.stringify(addons) : null,
            is_happy_hour_eligible !== undefined ? (is_happy_hour_eligible ? 1 : 0) : 1,
            ingredients ? JSON.stringify(ingredients) : null,
            is_kot_item ? 1 : 0,
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
    const { product_id, promo_price, start_time, end_time, days_of_week, name, category_id, image_base64 } = req.body;
    try {
        if (category_id && !product_id) {
            // Deactivate previous active category promos for this category
            await db.query('UPDATE happy_hour_pricing SET status = "inactive" WHERE category_id = ? AND product_id IS NULL', [category_id]);
        } else if (product_id) {
            // Deactivate previous active product promos for this product
            await db.query('UPDATE happy_hour_pricing SET status = "inactive" WHERE product_id = ?', [product_id]);
        }
        
        const result = await db.query(
            'INSERT INTO happy_hour_pricing (product_id, promo_price, start_time, end_time, days_of_week, name, category_id, image_base64) VALUES (?, ?, ?, ?, ?, ?, ?, ?)',
            [product_id || null, promo_price, start_time, end_time, days_of_week, name || null, category_id || null, image_base64 || null]
        );
        
        await logAudit('change_price', 'products', product_id || 0, `Happy hour pricing configured for ${name || 'Product'}`, req.user.id);
        broadcast({ type: 'happy_hour_updated' });
        
        res.json({ success: true, insertId: result.insertId });
    } catch (err) {
        res.status(500).json({ error: err.message });
    }
});

app.put('/api/happyhour/:id', authenticateToken, async (req, res) => {
    if (req.user.role !== 'admin' && req.user.role !== 'owner') {
        return res.status(403).json({ error: 'Unauthorized' });
    }
    const { id } = req.params;
    const { product_id, promo_price, start_time, end_time, days_of_week, name, category_id, image_base64, status } = req.body;
    try {
        await db.query(`
            UPDATE happy_hour_pricing
            SET product_id = ?, promo_price = ?, start_time = ?, end_time = ?, days_of_week = ?, name = ?, category_id = ?, image_base64 = ?, status = ?
            WHERE id = ?
        `, [
            product_id || null, promo_price, start_time, end_time, days_of_week, name || null, category_id || null, image_base64 || null, status || 'active', id
        ]);
        
        await logAudit('change_price', 'products', product_id || 0, `Happy hour pricing updated.`, req.user.id);
        broadcast({ type: 'happy_hour_updated' });
        
        res.json({ success: true });
    } catch (err) {
        res.status(500).json({ error: err.message });
    }
});

app.get('/api/happyhour', authenticateToken, async (req, res) => {
    try {
        const promos = await db.query(`
            SELECT hhp.*, p.name as product_name, p.price as original_price, c.name as category_name
            FROM happy_hour_pricing hhp
            LEFT JOIN products p ON hhp.product_id = p.id
            LEFT JOIN categories c ON hhp.category_id = c.id
            WHERE hhp.status = "active"
            ORDER BY hhp.id DESC
        `);
        res.json(promos);
    } catch (err) {
        res.status(500).json({ error: err.message });
    }
});

app.delete('/api/happyhour/:id', authenticateToken, async (req, res) => {
    if (req.user.role !== 'admin' && req.user.role !== 'owner') {
        return res.status(403).json({ error: 'Unauthorized' });
    }
    const { id } = req.params;
    try {
        await db.query('UPDATE happy_hour_pricing SET status = "inactive" WHERE id = ?', [id]);
        broadcast({ type: 'happy_hour_updated' });
        res.json({ success: true, message: 'Happy hour pricing deactivated successfully.' });
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
        const [customer] = await db.query('SELECT * FROM customers WHERE id = ?', [customer_id]);
        if (!customer) return res.status(404).json({ error: 'Customer not found' });

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
        
        // If paid via Cash, record to cash drawer logs under active shift
        if (payment_method === 'cash') {
            const openShifts = await db.query('SELECT * FROM shifts WHERE status = "open" LIMIT 1');
            if (openShifts.length > 0) {
                const shiftId = openShifts[0].id;
                await db.query(
                    'INSERT INTO cash_drawer_logs (shift_id, type, amount, reason) VALUES (?, "cash_in", ?, ?)',
                    [shiftId, amount, `Credit Settlement: ${customer.name}`]
                );
            }
        }

        const [updatedCustomer] = await db.query('SELECT * FROM customers WHERE id = ?', [customer_id]);
        
        await logAudit('modify_bill', 'customers', customer_id, `Settled LKR ${amount} credit balance via ${payment_method.toUpperCase()}`, req.user.id);
        
        // Broadcast updates
        broadcast({ type: 'customer_updated', data: updatedCustomer });
        broadcast({ type: 'shift_updated' });
        
        res.json({ success: true, customer: updatedCustomer });
    } catch (err) {
        res.status(500).json({ error: err.message });
    }
});

app.put('/api/credit/settle/:id', authenticateToken, async (req, res) => {
    const { id } = req.params;
    const { amount, payment_method } = req.body;
    try {
        const settlements = await db.query('SELECT * FROM credit_settlements WHERE id = ?', [id]);
        if (settlements.length === 0) return res.status(404).json({ error: 'Credit settlement not found' });
        const settlement = settlements[0];
        
        const [customer] = await db.query('SELECT * FROM customers WHERE id = ?', [settlement.customer_id]);
        if (!customer) return res.status(404).json({ error: 'Customer not found' });

        const oldAmount = Number(settlement.amount);
        const newAmount = Number(amount);
        const oldPaymentMethod = settlement.payment_method.toLowerCase();
        const newPaymentMethod = payment_method.toLowerCase();

        const diff = newAmount - oldAmount;

        // 1. Update credit settlement entry
        await db.query(
            'UPDATE credit_settlements SET amount = ?, payment_method = ? WHERE id = ?',
            [newAmount, newPaymentMethod, id]
        );

        // 2. Adjust customer outstanding balance
        await db.query(
            'UPDATE customers SET outstanding_balance = outstanding_balance - ? WHERE id = ?',
            [diff, settlement.customer_id]
        );

        // 3. Adjust cash drawer logs
        const reasonStr = `Credit Settlement: ${customer.name}`;
        if (oldPaymentMethod === 'cash') {
            // Find old drawer log
            const logs = await db.query(
                'SELECT * FROM cash_drawer_logs WHERE type = "cash_in" AND amount = ? AND reason = ? ORDER BY timestamp DESC LIMIT 1',
                [oldAmount, reasonStr]
            );
            if (logs.length > 0) {
                const logId = logs[0].id;
                if (newPaymentMethod === 'cash') {
                    await db.query('UPDATE cash_drawer_logs SET amount = ? WHERE id = ?', [newAmount, logId]);
                } else {
                    await db.query('DELETE FROM cash_drawer_logs WHERE id = ?', [logId]);
                }
            }
        } else if (newPaymentMethod === 'cash') {
            // Insert new cash log if changed from card/qr to cash
            const openShifts = await db.query('SELECT * FROM shifts WHERE status = "open" LIMIT 1');
            if (openShifts.length > 0) {
                await db.query(
                    'INSERT INTO cash_drawer_logs (shift_id, type, amount, reason) VALUES (?, "cash_in", ?, ?)',
                    [openShifts[0].id, newAmount, reasonStr]
                );
            }
        }

        const [updatedCustomer] = await db.query('SELECT * FROM customers WHERE id = ?', [settlement.customer_id]);

        await logAudit('modify_bill', 'customers', settlement.customer_id, `Edited credit settlement (ID: ${id}) from LKR ${oldAmount} to LKR ${newAmount} (${newPaymentMethod.toUpperCase()})`, req.user.id);

        broadcast({ type: 'customer_updated', data: updatedCustomer });
        broadcast({ type: 'shift_updated' });

        res.json({ success: true, customer: updatedCustomer });
    } catch (err) {
        res.status(500).json({ error: err.message });
    }
});

app.delete('/api/credit/settle/:id', authenticateToken, async (req, res) => {
    const { id } = req.params;
    try {
        const settlements = await db.query('SELECT * FROM credit_settlements WHERE id = ?', [id]);
        if (settlements.length === 0) return res.status(404).json({ error: 'Credit settlement not found' });
        const settlement = settlements[0];
        
        const [customer] = await db.query('SELECT * FROM customers WHERE id = ?', [settlement.customer_id]);
        if (!customer) return res.status(404).json({ error: 'Customer not found' });

        const oldAmount = Number(settlement.amount);
        const oldPaymentMethod = settlement.payment_method.toLowerCase();

        // 1. Delete credit settlement entry
        await db.query('DELETE FROM credit_settlements WHERE id = ?', [id]);

        // 2. Restore customer outstanding balance
        await db.query(
            'UPDATE customers SET outstanding_balance = outstanding_balance + ? WHERE id = ?',
            [oldAmount, settlement.customer_id]
        );

        // 3. Remove cash drawer log if it was cash
        if (oldPaymentMethod === 'cash') {
            const reasonStr = `Credit Settlement: ${customer.name}`;
            const logs = await db.query(
                'SELECT * FROM cash_drawer_logs WHERE type = "cash_in" AND amount = ? AND reason = ? ORDER BY timestamp DESC LIMIT 1',
                [oldAmount, reasonStr]
            );
            if (logs.length > 0) {
                await db.query('DELETE FROM cash_drawer_logs WHERE id = ?', [logs[0].id]);
            }
        }

        const [updatedCustomer] = await db.query('SELECT * FROM customers WHERE id = ?', [settlement.customer_id]);

        await logAudit('modify_bill', 'customers', settlement.customer_id, `Voided/Deleted credit settlement (ID: ${id}) of LKR ${oldAmount}`, req.user.id);

        broadcast({ type: 'customer_updated', data: updatedCustomer });
        broadcast({ type: 'shift_updated' });

        res.json({ success: true, customer: updatedCustomer });
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
        
        const actionType = type === 'cash_in' ? 'cash_in' : 'cash_out';
        const label = type === 'cash_in' ? 'Cash In' : 'Cash Out';
        await logAudit(actionType, 'cash_drawer_logs', shift_id, `Drawer ${label} adjustment: LKR ${amount} - Reason: ${reason}`, req.user.id);
        
        res.json({ success: true });
    } catch (err) {
        res.status(500).json({ error: err.message });
    }
});

app.get('/api/shifts/:id/drawer-logs', authenticateToken, async (req, res) => {
    const { id } = req.params;
    try {
        const logs = await db.query('SELECT * FROM cash_drawer_logs WHERE shift_id = ? ORDER BY timestamp DESC', [id]);
        res.json(logs);
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
// PROMOTIONS & OFFERS ENDPOINTS
// ----------------------------------------------------

app.get('/api/offers', authenticateToken, async (req, res) => {
    try {
        const offers = await db.query('SELECT * FROM offers ORDER BY created_at DESC');
        res.json(offers);
    } catch (err) {
        res.status(500).json({ error: err.message });
    }
});

app.post('/api/offers', authenticateToken, async (req, res) => {
    const { name, discount_percentage, start_date, end_date, image_base64, status } = req.body;
    try {
        const result = await db.query(
            'INSERT INTO offers (name, discount_percentage, start_date, end_date, image_base64, status) VALUES (?, ?, ?, ?, ?, ?)',
            [name, discount_percentage, start_date, end_date, image_base64 || null, status || 'active']
        );
        const newId = result.insertId;
        const [offer] = await db.query('SELECT * FROM offers WHERE id = ?', [newId]);
        
        await logAudit('modify_bill', 'offers', newId, `Offer ${name} created.`, req.user.id);
        broadcast({ type: 'offer_created', data: offer });

        res.json(offer);
    } catch (err) {
        res.status(500).json({ error: err.message });
    }
});

app.put('/api/offers/:id', authenticateToken, async (req, res) => {
    const { id } = req.params;
    const { name, discount_percentage, start_date, end_date, image_base64, status } = req.body;
    try {
        let updateFields = [];
        let params = [];
        
        if (name !== undefined) { updateFields.push('name = ?'); params.push(name); }
        if (discount_percentage !== undefined) { updateFields.push('discount_percentage = ?'); params.push(discount_percentage); }
        if (start_date !== undefined) { updateFields.push('start_date = ?'); params.push(start_date); }
        if (end_date !== undefined) { updateFields.push('end_date = ?'); params.push(end_date); }
        if (image_base64 !== undefined) { updateFields.push('image_base64 = ?'); params.push(image_base64); }
        if (status !== undefined) { updateFields.push('status = ?'); params.push(status); }

        if (updateFields.length === 0) {
            return res.status(400).json({ error: 'No fields provided to update.' });
        }

        params.push(id);
        await db.query(`UPDATE offers SET ${updateFields.join(', ')} WHERE id = ?`, params);
        const [offer] = await db.query('SELECT * FROM offers WHERE id = ?', [id]);
        
        await logAudit('modify_bill', 'offers', id, `Offer ${offer.name} updated.`, req.user.id);
        broadcast({ type: 'offer_updated', data: offer });

        res.json(offer);
    } catch (err) {
        res.status(500).json({ error: err.message });
    }
});

app.delete('/api/offers/:id', authenticateToken, async (req, res) => {
    const { id } = req.params;
    try {
        const offers = await db.query('SELECT name FROM offers WHERE id = ?', [id]);
        if (offers.length === 0) return res.status(404).json({ error: 'Offer not found' });
        const offer = offers[0];

        await db.query('DELETE FROM offers WHERE id = ?', [id]);
        await logAudit('modify_bill', 'offers', id, `Offer ${offer.name} deleted.`, req.user.id);
        broadcast({ type: 'offer_deleted', data: { id } });

        res.json({ success: true, message: 'Offer deleted successfully.' });
    } catch (err) {
        res.status(500).json({ error: err.message });
    }
});

// ----------------------------------------------------
// SYSTEM USER CRUD ENDPOINTS
// ----------------------------------------------------

app.get('/api/users', authenticateToken, async (req, res) => {
    const { role } = req.query;
    try {
        let sql = 'SELECT id, name, username, email, phone, role, status, branch, image_base64, category_id, created_at FROM users';
        let params = [];
        if (role) {
            if (role === 'admin_owner') {
                sql += ' WHERE role IN ("admin", "owner")';
            } else {
                sql += ' WHERE role = ?';
                params.push(role);
            }
        }
        sql += ' ORDER BY created_at DESC';
        const users = await db.query(sql, params);
        res.json(users);
    } catch (err) {
        res.status(500).json({ error: err.message });
    }
});

app.post('/api/users', authenticateToken, async (req, res) => {
    if (req.user.role !== 'admin' && req.user.role !== 'owner') {
        return res.status(403).json({ error: 'Unauthorized' });
    }
    const { name, username, password, role, status, email, phone, branch, image_base64, category_id } = req.body;
    if (!username || !password || !role) {
        return res.status(400).json({ error: 'Username, password, and role are required' });
    }
    try {
        const passHash = await bcrypt.hash(password, 10);
        const result = await db.query(
            'INSERT INTO users (name, username, password_hash, role, status, email, phone, branch, image_base64, category_id) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)',
            [name, username, passHash, role, status || 'active', email || null, phone || null, branch || 'current', image_base64 || null, category_id || null]
        );
        const newId = result.insertId;
        const [newUser] = await db.query('SELECT id, name, username, email, phone, role, status, branch, image_base64, category_id FROM users WHERE id = ?', [newId]);
        
        await logAudit('modify_bill', 'users', newId, `User ${username} created.`, req.user.id);
        broadcast({ type: 'user_created', data: newUser });
        res.json(newUser);
    } catch (err) {
        res.status(500).json({ error: err.message });
    }
});

app.put('/api/users/:id', authenticateToken, async (req, res) => {
    const { id } = req.params;
    if (req.user.role !== 'admin' && req.user.role !== 'owner' && req.user.id !== Number(id)) {
        return res.status(403).json({ error: 'Unauthorized' });
    }
    const { name, username, role, status, email, phone, branch, image_base64, category_id } = req.body;
    try {
        let updateFields = [];
        let params = [];
        
        if (name !== undefined) { updateFields.push('name = ?'); params.push(name); }
        if (username !== undefined) { updateFields.push('username = ?'); params.push(username); }
        if (role !== undefined) { updateFields.push('role = ?'); params.push(role); }
        if (status !== undefined) { updateFields.push('status = ?'); params.push(status); }
        if (email !== undefined) { updateFields.push('email = ?'); params.push(email); }
        if (phone !== undefined) { updateFields.push('phone = ?'); params.push(phone); }
        if (branch !== undefined) { updateFields.push('branch = ?'); params.push(branch); }
        if (image_base64 !== undefined) { updateFields.push('image_base64 = ?'); params.push(image_base64); }
        if (category_id !== undefined) { updateFields.push('category_id = ?'); params.push(category_id); }
 
        if (updateFields.length === 0) {
            return res.status(400).json({ error: 'No fields provided to update' });
        }
 
        params.push(id);
        await db.query(`UPDATE users SET ${updateFields.join(', ')} WHERE id = ?`, params);
        const [user] = await db.query('SELECT id, name, username, email, phone, role, status, branch, image_base64, category_id FROM users WHERE id = ?', [id]);
        
        await logAudit('modify_bill', 'users', id, `User ${user.username} updated.`, req.user.id);
        broadcast({ type: 'user_updated', data: user });
        res.json(user);
    } catch (err) {
        res.status(500).json({ error: err.message });
    }
});

app.put('/api/users/:id/password', authenticateToken, async (req, res) => {
    const { id } = req.params;
    if (req.user.role !== 'admin' && req.user.role !== 'owner' && req.user.id !== Number(id)) {
        return res.status(403).json({ error: 'Unauthorized' });
    }
    const { password } = req.body;
    if (!password) return res.status(400).json({ error: 'Password required' });
    try {
        const passHash = await bcrypt.hash(password, 10);
        await db.query('UPDATE users SET password_hash = ? WHERE id = ?', [passHash, id]);
        const [user] = await db.query('SELECT username FROM users WHERE id = ?', [id]);
        await logAudit('modify_bill', 'users', id, `Password reset for user ${user.username}.`, req.user.id);
        res.json({ success: true, message: 'Password updated successfully' });
    } catch (err) {
        res.status(500).json({ error: err.message });
    }
});

app.delete('/api/users/:id', authenticateToken, async (req, res) => {
    if (req.user.role !== 'admin' && req.user.role !== 'owner') {
        return res.status(403).json({ error: 'Unauthorized' });
    }
    const { id } = req.params;
    try {
        const [user] = await db.query('SELECT username FROM users WHERE id = ?', [id]);
        if (!user) return res.status(404).json({ error: 'User not found' });
        await db.query('UPDATE users SET status = "inactive" WHERE id = ?', [id]);
        await logAudit('modify_bill', 'users', id, `User ${user.username} deactivated.`, req.user.id);
        broadcast({ type: 'user_deactivated', data: { id } });
        res.json({ success: true, message: 'User deactivated successfully' });
    } catch (err) {
        res.status(500).json({ error: err.message });
    }
});

app.get('/api/users/:id/prepared-items', authenticateToken, async (req, res) => {
    const { id } = req.params;
    try {
        const users = await db.query('SELECT role, category_id FROM users WHERE id = ?', [id]);
        if (users.length === 0) return res.status(404).json({ error: 'User not found' });
        const user = users[0];
        
        if (user.role !== 'kitchen' || !user.category_id) {
            return res.json([]);
        }

        // 1. Fetch sales order items matching this category (only for products that DO NOT track stock, i.e., made-to-order)
        const salesItems = await db.query(`
            SELECT 
                oi.id,
                o.order_number,
                oi.quantity,
                o.created_at,
                p.name AS product_name,
                p.sinhala_name AS product_sinhala_name,
                p.ingredients,
                oi.notes,
                'sale' AS source_type
            FROM order_items oi
            JOIN orders o ON oi.order_id = o.id
            JOIN products p ON oi.product_id = p.id
            WHERE p.category_id = ? AND o.status != 'cancelled' AND p.track_stock = 0
        `, [user.category_id]);

        // 2. Fetch stock additions for products in this category (only for products that DO track stock, i.e., prepared in advance)
        const stockAdditions = await db.query(`
            SELECT 
                sl.id,
                CONCAT('STOCK_ADD-', sl.id) AS order_number,
                sl.change_qty AS quantity,
                sl.timestamp AS created_at,
                p.name AS product_name,
                p.sinhala_name AS product_sinhala_name,
                p.ingredients,
                sl.reason AS notes,
                'stock_addition' AS source_type
            FROM stock_logs sl
            JOIN products p ON sl.product_id = p.id
            WHERE p.category_id = ? AND sl.change_qty > 0 AND sl.type IN ('adjustment', 'purchase') AND p.track_stock = 1
        `, [user.category_id]);

        // Combine and parse ingredients
        const combined = [...salesItems, ...stockAdditions].map(item => {
            let parsedIngredients = [];
            if (item.ingredients) {
                try {
                    parsedIngredients = typeof item.ingredients === 'string' 
                        ? JSON.parse(item.ingredients) 
                        : item.ingredients;
                } catch (_) {}
            }
            return {
                id: item.id,
                order_number: item.order_number,
                quantity: Number(item.quantity),
                created_at: item.created_at,
                product_name: item.product_name,
                product_sinhala_name: item.product_sinhala_name,
                notes: item.notes,
                source_type: item.source_type,
                ingredients: parsedIngredients
            };
        });

        // Sort by date DESC
        combined.sort((a, b) => new Date(b.created_at) - new Date(a.created_at));

        res.json(combined);
    } catch (err) {
        res.status(500).json({ error: err.message });
    }
});

// ----------------------------------------------------
// CUSTOMER CRUD ENDPOINTS
// ----------------------------------------------------

app.get('/api/customers', authenticateToken, async (req, res) => {
    try {
        const customers = await db.query('SELECT * FROM customers ORDER BY created_at DESC');
        res.json(customers);
    } catch (err) {
        res.status(500).json({ error: err.message });
    }
});

app.post('/api/customers', authenticateToken, async (req, res) => {
    const { name, phone, email, birthday, credit_limit, outstanding_balance, image_base64 } = req.body;
    if (!name || !phone) {
        return res.status(400).json({ error: 'Customer Name and Phone number are required' });
    }
    try {
        const result = await db.query(
            'INSERT INTO customers (name, phone, email, birthday, credit_limit, outstanding_balance, image_base64) VALUES (?, ?, ?, ?, ?, ?, ?)',
            [name, phone, email || null, birthday || null, credit_limit || 0.00, outstanding_balance || 0.00, image_base64 || null]
        );
        const newId = result.insertId;
        const [customer] = await db.query('SELECT * FROM customers WHERE id = ?', [newId]);
        
        await logAudit('modify_bill', 'customers', newId, `Customer ${name} added.`, req.user.id);
        broadcast({ type: 'customer_created', data: customer });
        res.json(customer);
    } catch (err) {
        res.status(500).json({ error: err.message });
    }
});

app.put('/api/customers/:id', authenticateToken, async (req, res) => {
    const { id } = req.params;
    const { name, phone, email, birthday, credit_limit, outstanding_balance, image_base64 } = req.body;
    try {
        let updateFields = [];
        let params = [];
        
        if (name !== undefined) { updateFields.push('name = ?'); params.push(name); }
        if (phone !== undefined) { updateFields.push('phone = ?'); params.push(phone); }
        if (email !== undefined) { updateFields.push('email = ?'); params.push(email); }
        if (birthday !== undefined) { updateFields.push('birthday = ?'); params.push(birthday); }
        if (credit_limit !== undefined) { updateFields.push('credit_limit = ?'); params.push(credit_limit); }
        if (outstanding_balance !== undefined) { updateFields.push('outstanding_balance = ?'); params.push(outstanding_balance); }
        if (image_base64 !== undefined) { updateFields.push('image_base64 = ?'); params.push(image_base64); }

        if (updateFields.length === 0) {
            return res.status(400).json({ error: 'No fields provided to update' });
        }

        params.push(id);
        await db.query(`UPDATE customers SET ${updateFields.join(', ')} WHERE id = ?`, params);
        const [customer] = await db.query('SELECT * FROM customers WHERE id = ?', [id]);
        
        await logAudit('modify_bill', 'customers', id, `Customer ${customer.name} updated.`, req.user.id);
        broadcast({ type: 'customer_updated', data: customer });
        res.json(customer);
    } catch (err) {
        res.status(500).json({ error: err.message });
    }
});

app.delete('/api/customers/:id', authenticateToken, async (req, res) => {
    if (req.user.role !== 'admin' && req.user.role !== 'owner') {
        return res.status(403).json({ error: 'Unauthorized' });
    }
    const { id } = req.params;
    try {
        const [customer] = await db.query('SELECT name FROM customers WHERE id = ?', [id]);
        if (!customer) return res.status(404).json({ error: 'Customer not found' });
        await db.query('DELETE FROM customers WHERE id = ?', [id]);
        await logAudit('modify_bill', 'customers', id, `Customer ${customer.name} deleted.`, req.user.id);
        broadcast({ type: 'customer_deleted', data: { id } });
        res.json({ success: true, message: 'Customer deleted successfully' });
    } catch (err) {
        res.status(500).json({ error: err.message });
    }
});

app.get('/api/customers/:id/ledger', authenticateToken, async (req, res) => {
    const { id } = req.params;
    try {
        const [customer] = await db.query('SELECT outstanding_balance, created_at FROM customers WHERE id = ?', [id]);
        if (!customer) return res.status(404).json({ error: 'Customer not found' });

        const currentOutstanding = Number(customer.outstanding_balance);

        // Fetch all credit purchases (orders)
        const purchases = await db.query(`
            SELECT id, order_number AS description, total AS debit, 0.00 AS credit, created_at AS date, 'purchase' AS type
            FROM orders
            WHERE customer_id = ? AND payment_method = 'credit'
        `, [id]);

        // Fetch all credit settlements
        const payments = await db.query(`
            SELECT id, CONCAT('Settle Payment: ', UPPER(payment_method)) AS description, 0.00 AS debit, amount AS credit, date_paid AS date, 'payment' AS type
            FROM credit_settlements
            WHERE customer_id = ?
        `, [id]);

        // Back-calculate initial outstanding balance
        let totalDebit = 0;
        let totalCredit = 0;
        purchases.forEach(p => totalDebit += Number(p.debit));
        payments.forEach(p => totalCredit += Number(p.credit));

        const initialBalance = currentOutstanding - totalDebit + totalCredit;

        const combined = [...purchases, ...payments];
        combined.sort((a, b) => new Date(a.date).getTime() - new Date(b.date).getTime());

        const ledger = [];
        if (initialBalance !== 0) {
            ledger.push({
                id: 0,
                description: 'Starting Outstanding Balance',
                debit: initialBalance > 0 ? initialBalance : 0.00,
                credit: initialBalance < 0 ? -initialBalance : 0.00,
                date: customer.created_at,
                type: 'starting',
                running_balance: initialBalance
            });
        }

        let balance = initialBalance;
        combined.forEach(item => {
            balance += (Number(item.debit) - Number(item.credit));
            ledger.push({
                id: item.id,
                description: item.description,
                debit: Number(item.debit),
                credit: Number(item.credit),
                date: item.date,
                type: item.type,
                running_balance: balance
            });
        });

        res.json(ledger);
    } catch (err) {
        res.status(500).json({ error: err.message });
    }
});

// ----------------------------------------------------
// SUPPLIER CRUD & PAYMENT ENDPOINTS
// ----------------------------------------------------

app.get('/api/suppliers', authenticateToken, async (req, res) => {
    try {
        const suppliers = await db.query('SELECT * FROM suppliers ORDER BY created_at DESC');
        res.json(suppliers);
    } catch (err) {
        res.status(500).json({ error: err.message });
    }
});

app.post('/api/suppliers', authenticateToken, async (req, res) => {
    const { name, outstanding_balance, delivery_cycle } = req.body;
    if (!name) {
        return res.status(400).json({ error: 'Supplier Name is required' });
    }
    try {
        const result = await db.query(
            'INSERT INTO suppliers (name, outstanding_balance, delivery_cycle) VALUES (?, ?, ?)',
            [name, outstanding_balance || 0.00, delivery_cycle || 'Weekly']
        );
        const newId = result.insertId;
        const [supplier] = await db.query('SELECT * FROM suppliers WHERE id = ?', [newId]);
        
        await logAudit('modify_bill', 'suppliers', newId, `Supplier ${name} added.`, req.user.id);
        broadcast({ type: 'supplier_created', data: supplier });
        res.json(supplier);
    } catch (err) {
        res.status(500).json({ error: err.message });
    }
});

app.put('/api/suppliers/:id', authenticateToken, async (req, res) => {
    const { id } = req.params;
    const { name, outstanding_balance, delivery_cycle } = req.body;
    try {
        let updateFields = [];
        let params = [];
        
        if (name !== undefined) { updateFields.push('name = ?'); params.push(name); }
        if (outstanding_balance !== undefined) { updateFields.push('outstanding_balance = ?'); params.push(outstanding_balance); }
        if (delivery_cycle !== undefined) { updateFields.push('delivery_cycle = ?'); params.push(delivery_cycle); }

        if (updateFields.length === 0) {
            return res.status(400).json({ error: 'No fields provided to update' });
        }

        params.push(id);
        await db.query(`UPDATE suppliers SET ${updateFields.join(', ')} WHERE id = ?`, params);
        const [supplier] = await db.query('SELECT * FROM suppliers WHERE id = ?', [id]);
        
        await logAudit('modify_bill', 'suppliers', id, `Supplier ${supplier.name} updated.`, req.user.id);
        broadcast({ type: 'supplier_updated', data: supplier });
        res.json(supplier);
    } catch (err) {
        res.status(500).json({ error: err.message });
    }
});

app.delete('/api/suppliers/:id', authenticateToken, async (req, res) => {
    if (req.user.role !== 'admin' && req.user.role !== 'owner') {
        return res.status(403).json({ error: 'Unauthorized' });
    }
    const { id } = req.params;
    try {
        const [supplier] = await db.query('SELECT name FROM suppliers WHERE id = ?', [id]);
        if (!supplier) return res.status(404).json({ error: 'Supplier not found' });
        await db.query('DELETE FROM suppliers WHERE id = ?', [id]);
        await logAudit('modify_bill', 'suppliers', id, `Supplier ${supplier.name} deleted.`, req.user.id);
        broadcast({ type: 'supplier_deleted', data: { id } });
        res.json({ success: true, message: 'Supplier deleted successfully' });
    } catch (err) {
        res.status(500).json({ error: err.message });
    }
});

app.post('/api/suppliers/:id/pay', authenticateToken, async (req, res) => {
    const { id } = req.params;
    const { amount, payment_source, remarks } = req.body;
    try {
        const suppliers = await db.query('SELECT * FROM suppliers WHERE id = ?', [id]);
        if (suppliers.length === 0) return res.status(404).json({ error: 'Supplier not found' });
        const supplier = suppliers[0];

        await db.query(
            'UPDATE suppliers SET outstanding_balance = outstanding_balance - ? WHERE id = ?',
            [amount, id]
        );

        // Record to supplier_payments
        await db.query(
            'INSERT INTO supplier_payments (supplier_id, amount, payment_source, remarks, payment_date) VALUES (?, ?, ?, ?, CURRENT_DATE())',
            [id, amount, payment_source, remarks || null]
        );

        if (payment_source === 'drawer') {
            const openShifts = await db.query('SELECT * FROM shifts WHERE status = "open" LIMIT 1');
            if (openShifts.length === 0) {
                return res.status(400).json({ error: 'No active shift found. Please open a shift first.' });
            }
            const shiftId = openShifts[0].id;
            await db.query(
                'INSERT INTO cash_drawer_logs (shift_id, type, amount, reason) VALUES (?, "cash_out", ?, ?)',
                [shiftId, amount, `Supplier Payment: ${supplier.name} (${remarks || 'No remarks'})`]
            );
        }

        await logAudit('modify_bill', 'suppliers', id, `Paid LKR ${amount} to Supplier ${supplier.name} via ${payment_source}`, req.user.id);
        
        const [updatedSupplier] = await db.query('SELECT * FROM suppliers WHERE id = ?', [id]);
        broadcast({ type: 'supplier_updated', data: updatedSupplier });
        
        res.json({ success: true, supplier: updatedSupplier });
    } catch (err) {
        res.status(500).json({ error: err.message });
    }
});

app.get('/api/suppliers/:id/deliveries', authenticateToken, async (req, res) => {
    const { id } = req.params;
    try {
        const deliveries = await db.query('SELECT * FROM supplier_deliveries WHERE supplier_id = ? ORDER BY delivery_date DESC, id DESC', [id]);
        res.json(deliveries);
    } catch (err) {
        res.status(500).json({ error: err.message });
    }
});

app.post('/api/suppliers/:id/deliveries', authenticateToken, async (req, res) => {
    const { id } = req.params;
    const { item_name, quantity, unit, total_amount, delivery_date } = req.body;
    if (!item_name || !quantity || !total_amount || !delivery_date) {
        return res.status(400).json({ error: 'Item Name, Quantity, Total Amount and Delivery Date are required' });
    }
    try {
        const suppliers = await db.query('SELECT * FROM suppliers WHERE id = ?', [id]);
        if (suppliers.length === 0) return res.status(404).json({ error: 'Supplier not found' });
        const supplier = suppliers[0];

        const result = await db.query(
            'INSERT INTO supplier_deliveries (supplier_id, item_name, quantity, unit, total_amount, delivery_date) VALUES (?, ?, ?, ?, ?, ?)',
            [id, item_name, quantity, unit || 'kg', total_amount, delivery_date]
        );

        await db.query(
            'UPDATE suppliers SET outstanding_balance = outstanding_balance + ? WHERE id = ?',
            [total_amount, id]
        );

        await logAudit('modify_bill', 'suppliers', id, `Logged delivery: ${item_name} (${quantity} ${unit || 'kg'}) worth LKR ${total_amount} from Supplier ${supplier.name}`, req.user.id);
        
        const [updatedSupplier] = await db.query('SELECT * FROM suppliers WHERE id = ?', [id]);
        broadcast({ type: 'supplier_updated', data: updatedSupplier });
        
        res.json({ success: true, deliveryId: result.insertId, supplier: updatedSupplier });
    } catch (err) {
        res.status(500).json({ error: err.message });
    }
});

app.get('/api/suppliers/:id/payments', authenticateToken, async (req, res) => {
    const { id } = req.params;
    try {
        const payments = await db.query('SELECT * FROM supplier_payments WHERE supplier_id = ? ORDER BY payment_date DESC, id DESC', [id]);
        res.json(payments);
    } catch (err) {
        res.status(500).json({ error: err.message });
    }
});

app.get('/api/suppliers/:id/ledger', authenticateToken, async (req, res) => {
    const { id } = req.params;
    try {
        const deliveries = await db.query(`
            SELECT id, item_name AS description, quantity, unit, total_amount AS debit, 0.00 AS credit, delivery_date AS date, 'delivery' AS type, created_at
            FROM supplier_deliveries
            WHERE supplier_id = ?
        `, [id]);

        const payments = await db.query(`
            SELECT id, CONCAT('Payment: ', payment_source, IF(remarks IS NULL OR remarks = '', '', CONCAT(' - ', remarks))) AS description, 0.00 AS quantity, '' AS unit, 0.00 AS debit, amount AS credit, payment_date AS date, 'payment' AS type, created_at
            FROM supplier_payments
            WHERE supplier_id = ?
        `, [id]);

        const combined = [...deliveries, ...payments];
        combined.sort((a, b) => {
            const dateCompare = new Date(a.date).getTime() - new Date(b.date).getTime();
            if (dateCompare !== 0) return dateCompare;
            return new Date(a.created_at).getTime() - new Date(b.created_at).getTime();
        });

        res.json(combined);
    } catch (err) {
        res.status(500).json({ error: err.message });
    }
});

// ----------------------------------------------------
// USER & CUSTOMER ADDRESS ENDPOINTS
// ----------------------------------------------------

app.get('/api/users/:id/addresses', authenticateToken, async (req, res) => {
    const { id } = req.params;
    try {
        const addresses = await db.query('SELECT * FROM user_addresses WHERE user_id = ? ORDER BY id DESC', [id]);
        res.json(addresses);
    } catch (err) {
        res.status(500).json({ error: err.message });
    }
});

app.post('/api/users/:id/addresses', authenticateToken, async (req, res) => {
    const { id } = req.params;
    const { label, address_line, latitude, longitude } = req.body;
    if (!label || !address_line) {
        return res.status(400).json({ error: 'Label and address are required' });
    }
    try {
        const result = await db.query(
            'INSERT INTO user_addresses (user_id, label, address_line, latitude, longitude) VALUES (?, ?, ?, ?, ?)',
            [id, label, address_line, latitude || null, longitude || null]
        );
        const [newAddr] = await db.query('SELECT * FROM user_addresses WHERE id = ?', [result.insertId]);
        res.json(newAddr);
    } catch (err) {
        res.status(500).json({ error: err.message });
    }
});

app.get('/api/customers/:id/addresses', authenticateToken, async (req, res) => {
    const { id } = req.params;
    try {
        const addresses = await db.query('SELECT * FROM user_addresses WHERE customer_id = ? ORDER BY id DESC', [id]);
        res.json(addresses);
    } catch (err) {
        res.status(500).json({ error: err.message });
    }
});

app.post('/api/customers/:id/addresses', authenticateToken, async (req, res) => {
    const { id } = req.params;
    const { label, address_line, latitude, longitude } = req.body;
    if (!label || !address_line) {
        return res.status(400).json({ error: 'Label and address are required' });
    }
    try {
        const result = await db.query(
            'INSERT INTO user_addresses (customer_id, label, address_line, latitude, longitude) VALUES (?, ?, ?, ?, ?)',
            [id, label, address_line, latitude || null, longitude || null]
        );
        const [newAddr] = await db.query('SELECT * FROM user_addresses WHERE id = ?', [result.insertId]);
        res.json(newAddr);
    } catch (err) {
        res.status(500).json({ error: err.message });
    }
});

app.delete('/api/addresses/:id', authenticateToken, async (req, res) => {
    const { id } = req.params;
    try {
        await db.query('DELETE FROM user_addresses WHERE id = ?', [id]);
        res.json({ success: true, message: 'Address deleted successfully' });
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

app.get('/api/orders/by-number/:orderNumber', authenticateToken, async (req, res) => {
    const { orderNumber } = req.params;
    try {
        const orders = await db.query('SELECT * FROM orders WHERE order_number = ? LIMIT 1', [orderNumber]);
        if (orders.length === 0) return res.status(404).json({ error: 'Order not found' });
        const order = orders[0];
        const items = await db.query(`
            SELECT oi.*, p.name as product_name, p.sinhala_name as product_sinhala_name, p.is_short_eat
            FROM order_items oi
            JOIN products p ON oi.product_id = p.id
            WHERE oi.order_id = ?
        `, [order.id]);
        order.items = items;
        res.json(order);
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
        kot_printed, ack_printed, card_tx_reference, received_amount, change_amount,
        advance_payment, balance_amount, pre_order_id
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
        
        let existingOrderId = null;
        let orderNumber = null;
        
        if (order_type === 'dine_in' && table_id) {
            const [existingOrderRows] = await conn.query(
                'SELECT id, order_number FROM orders WHERE table_id = ? AND payment_status = "unpaid" AND status != "cancelled" LIMIT 1',
                [table_id]
            );
            if (existingOrderRows.length > 0) {
                existingOrderId = existingOrderRows[0].id;
                orderNumber = existingOrderRows[0].order_number;
            }
        }

        if (!existingOrderId) {
            if (pre_order_id) {
                const [poRows] = await conn.query('SELECT pre_order_number FROM pre_orders WHERE id = ?', [pre_order_id]);
                if (poRows.length > 0) {
                    orderNumber = poRows[0].pre_order_number;
                }
            }
            if (!orderNumber) {
                // Generate unique order number (e.g. ORD-20260617-1004)
                const localDate = new Date();
                const year = localDate.getFullYear();
                const month = String(localDate.getMonth() + 1).padStart(2, '0');
                const day = String(localDate.getDate()).padStart(2, '0');
                const dateStr = `${year}${month}${day}`;
                const queryDate = `${year}-${month}-${day}`;
         
                const [countResult] = await conn.query('SELECT COUNT(*) as count FROM orders WHERE DATE(created_at) = ?', [queryDate]);
                const nextNum = (countResult[0].count + 1).toString().padStart(4, '0');
                orderNumber = `ORD-${dateStr}-${nextNum}`;
            }
        }
        
        const barcode = orderNumber; // Barcode maps to order number
        
        let newOrderId = existingOrderId;
        
        if (!existingOrderId) {
            // Insert new order
            const [orderResult] = await conn.query(`
                INSERT INTO orders (
                    order_number, table_id, order_type, delivery_platform, customer_id, steward_name,
                    status, payment_status, payment_method, subtotal, discount, total, cashier_id,
                    shift_id, kot_printed, ack_printed, card_tx_reference, barcode, received_amount, change_amount,
                    advance_payment, balance_amount, pre_order_id
                ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            `, [
                orderNumber, table_id || null, order_type, delivery_platform || null, customer_id || null,
                steward_name || null, status || 'pending', payment_status || 'unpaid', payment_method || null,
                subtotal, discount, total, req.user.id, activeShiftId, kot_printed || false,
                ack_printed || false, card_tx_reference || null, barcode, received_amount || 0.00, change_amount || 0.00,
                advance_payment || 0.00, balance_amount || 0.00, pre_order_id || null
            ]);
            newOrderId = orderResult.insertId;
        } else {
            // Restore product stock from previous items of this order
            const [oldStockLogs] = await conn.query(
                'SELECT product_id, change_qty FROM stock_logs WHERE reason = ?',
                [`Sale Order: ${orderNumber}`]
            );
            for (const log of oldStockLogs) {
                const restoreQty = Math.abs(log.change_qty);
                await conn.query('UPDATE products SET stock_qty = stock_qty + ? WHERE id = ?', [restoreQty, log.product_id]);
                await conn.query(
                    'INSERT INTO stock_logs (product_id, change_qty, type, reason, user_id) VALUES (?, ?, "adjustment", ?, ?)',
                    [log.product_id, restoreQty, `Order Updated (Restore): ${orderNumber}`, req.user.id]
                );
            }
            await conn.query('DELETE FROM stock_logs WHERE reason = ?', [`Sale Order: ${orderNumber}`]);

            // Restore ingredient stock from previous items/extras of this order
            const [oldIngLogs] = await conn.query(
                'SELECT ingredient_id, change_qty FROM ingredient_stock_logs WHERE reason LIKE ?',
                [`%in Order: ${orderNumber}`]
            );
            for (const log of oldIngLogs) {
                const restoreQty = Math.abs(log.change_qty);
                await conn.query('UPDATE ingredients SET stock_qty = stock_qty + ? WHERE id = ?', [restoreQty, log.ingredient_id]);
                await conn.query(
                    'INSERT INTO ingredient_stock_logs (ingredient_id, change_qty, type, reason, user_id) VALUES (?, ?, "adjustment", ?, ?)',
                    [log.ingredient_id, restoreQty, `Restore Updated Order: ${orderNumber}`, req.user.id]
                );
            }
            await conn.query('DELETE FROM ingredient_stock_logs WHERE reason LIKE ?', [`%in Order: ${orderNumber}`]);

            // Delete old items
            await conn.query('DELETE FROM order_items WHERE order_id = ?', [existingOrderId]);
            
            // Update existing order details
            await conn.query(`
                UPDATE orders SET 
                    subtotal = ?, discount = ?, total = ?, steward_name = ?, customer_id = ?,
                    kot_printed = ?, ack_printed = ?, received_amount = ?, change_amount = ?,
                    advance_payment = ?, balance_amount = ?
                WHERE id = ?
            `, [
                subtotal, discount, total, steward_name || null, customer_id || null,
                kot_printed || false, ack_printed || false, 
                received_amount || 0.00, change_amount || 0.00, 
                advance_payment || 0.00, balance_amount || 0.00,
                existingOrderId
            ]);
        }
        
        // Insert order items & reduce stock counts
        for (const item of items) {
            await conn.query(`
                INSERT INTO order_items (order_id, product_id, quantity, price, notes, status)
                VALUES (?, ?, ?, ?, ?, ?)
            `, [newOrderId, item.product_id, item.quantity, item.price, item.notes || null, item.status || 'pending']);
            
            // Stock Reduction (only if track_stock is enabled)
            const [prodRows] = await conn.query('SELECT track_stock, ingredients FROM products WHERE id = ?', [item.product_id]);
            const trackStock = prodRows[0] ? prodRows[0].track_stock : 1;
            if (trackStock) {
                await conn.query('UPDATE products SET stock_qty = stock_qty - ? WHERE id = ?', [item.quantity, item.product_id]);
                
                // Insert Stock Log
                await conn.query(
                    'INSERT INTO stock_logs (product_id, change_qty, type, reason, user_id) VALUES (?, ?, "sale", ?, ?)',
                    [item.product_id, -item.quantity, `Sale Order: ${orderNumber}`, req.user.id]
                );
            }

            // Deduct recipe/raw ingredients if product has any
            if (prodRows[0] && prodRows[0].ingredients) {
                try {
                    const recipe = typeof prodRows[0].ingredients === 'string'
                        ? JSON.parse(prodRows[0].ingredients)
                        : prodRows[0].ingredients;
                    if (Array.isArray(recipe)) {
                        // Extract selected size from item.notes (e.g., "Size: Large | Extras: ...")
                        let selectedSize = null;
                        if (item.notes && item.notes.includes('Size: ')) {
                            const match = item.notes.match(/Size:\s*([^|]+)/);
                            if (match && match[1]) {
                                selectedSize = match[1].trim();
                            }
                        }

                        for (const ing of recipe) {
                            if (ing.ingredient_id && ing.qty) {
                                // If the recipe ingredient specifies a size, it must match the selected size
                                // If it doesn't specify a size, it applies to all sizes
                                if (ing.size && ing.size !== selectedSize) {
                                    continue; // Skip deduction if size does not match
                                }

                                const totalDeduct = ing.qty * item.quantity;
                                // Deduct raw ingredient stock
                                await conn.query('UPDATE ingredients SET stock_qty = stock_qty - ? WHERE id = ?', [totalDeduct, ing.ingredient_id]);
                                // Insert raw ingredient stock log
                                const sizeSuffix = selectedSize ? ` (${selectedSize})` : '';
                                await conn.query(`
                                    INSERT INTO ingredient_stock_logs (ingredient_id, change_qty, type, reason, user_id)
                                    VALUES (?, ?, 'sale', ?, ?)
                                `, [ing.ingredient_id, -totalDeduct, `Product '${item.product_name || 'Product'}'${sizeSuffix} in Order: ${orderNumber}`, req.user.id]);
                            }
                        }
                    }
                } catch (e) {
                    console.error('Error deducting recipe ingredients:', e);
                }
            }

            // Extra Stock Reduction (Countable raw materials like Egg, Chicken, Cheese, etc.)
            if (item.extras && Array.isArray(item.extras)) {
                for (const extra of item.extras) {
                    if (extra.ingredient_id && extra.qty) {
                        const totalDeduct = extra.qty * item.quantity;
                        // Deduct raw ingredient stock
                        await conn.query('UPDATE ingredients SET stock_qty = stock_qty - ? WHERE id = ?', [totalDeduct, extra.ingredient_id]);
                        // Insert raw ingredient stock log
                        await conn.query(`
                            INSERT INTO ingredient_stock_logs (ingredient_id, change_qty, type, reason, user_id)
                            VALUES (?, ?, 'sale', ?, ?)
                        `, [extra.ingredient_id, -totalDeduct, `Extra '${extra.name}' in Order: ${orderNumber}`, req.user.id]);
                    }
                }
            }
        }
        
        // Update Table Status if Dine-in
        if (order_type === 'dine_in' && table_id) {
            const tableStatus = (payment_status === 'paid' || status === 'delivered') ? 'empty' : (ack_printed ? 'billing' : 'seated');
            const currentOrderIdParam = (payment_status === 'paid' || status === 'delivered') ? null : newOrderId;
            const stewardParam = (payment_status === 'paid' || status === 'delivered') ? null : steward_name;
            await conn.query(
                'UPDATE dining_tables SET status = ?, current_order_id = ?, steward_name = ? WHERE id = ?',
                [tableStatus, currentOrderIdParam, stewardParam, table_id]
            );
        }
        
        // Add to Credit Person outstanding balance if credit payment method
        if (payment_method === 'credit' && customer_id) {
            const outstandingInc = balance_amount !== undefined ? parseFloat(balance_amount) : total;
            await conn.query(
                'UPDATE customers SET outstanding_balance = outstanding_balance + ? WHERE id = ?',
                [outstandingInc, customer_id]
            );
            await logAudit('modify_bill', 'customers', customer_id, `Added outstanding balance LKR ${outstandingInc} via Credit Order: ${orderNumber}`, req.user.id);
        }
        
        await conn.commit();

        // Check low stock notifications for all ordered items
        for (const item of items) {
            checkLowStockNotification(item.product_id).catch(err => console.error("Error checking low stock after order:", err));
        }
        
        if (existingOrderId) {
            await logAudit('modify_bill', 'orders', existingOrderId, `Order ${orderNumber} updated (Dine-in items appended). Total updated to: LKR ${total}`, req.user.id);
        } else {
            await logAudit('place_order', 'orders', newOrderId, `Order ${orderNumber} placed (${order_type.toUpperCase()}). Payment Status: ${payment_status.toUpperCase()}. Total: LKR ${total}`, req.user.id);
        }
        
        // Broadcast WebSocket notifications
        if (existingOrderId) {
            broadcast({ type: 'order_updated', data: { id: existingOrderId, order_number: orderNumber, status: status || 'pending', order_type } });
        } else {
            broadcast({ type: 'order_created', data: { id: newOrderId, order_number: orderNumber, status: status || 'pending', order_type } });
        }
        
        if (order_type === 'dine_in' && table_id) {
            const [tbl] = await db.query('SELECT * FROM dining_tables WHERE id = ?', [table_id]);
            broadcast({ type: 'table_status_changed', data: tbl[0] || tbl });
        }
        
        // Trigger voice message synthesis trigger for KDS
        if (kot_printed) {
            let tableName = null;
            if (order_type === 'dine_in' && table_id) {
                const [tblRows] = await db.query('SELECT table_number FROM dining_tables WHERE id = ?', [table_id]);
                if (tblRows[0]) {
                    tableName = tblRows[0].table_number;
                }
            }
            broadcast({ 
                type: 'kot_trigger_voice', 
                data: { 
                    orderNumber, 
                    items,
                    orderType: order_type,
                    tableName: tableName,
                    stewardName: steward_name || null
                } 
            });
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
    const { status, payment_status, payment_method, ack_printed, kot_printed, card_tx_reference, table_id, customer_id } = req.body;
    try {
        let updateFields = [];
        let params = [];
        
        if (status) { updateFields.push('status = ?'); params.push(status); }
        if (payment_status) { updateFields.push('payment_status = ?'); params.push(payment_status); }
        if (payment_method) { updateFields.push('payment_method = ?'); params.push(payment_method); }
        if (ack_printed !== undefined) { updateFields.push('ack_printed = ?'); params.push(ack_printed); }
        if (kot_printed !== undefined) { updateFields.push('kot_printed = ?'); params.push(kot_printed); }
        if (card_tx_reference) { updateFields.push('card_tx_reference = ?'); params.push(card_tx_reference); }
        if (customer_id) { updateFields.push('customer_id = ?'); params.push(customer_id); }
        
        if (updateFields.length === 0) {
            return res.status(400).json({ error: 'No fields provided to update.' });
        }
        
        params.push(id);
        await db.query(`UPDATE orders SET ${updateFields.join(', ')} WHERE id = ?`, params);
        
        const [updatedOrderRows] = await db.query('SELECT * FROM orders WHERE id = ?', [id]);
        const updatedOrder = updatedOrderRows[0];
        
        // If Dine-in Table, sync table state
        if (updatedOrder && updatedOrder.table_id) {
            const tableStatus = updatedOrder.payment_status === 'paid' ? 'empty' : (updatedOrder.ack_printed ? 'billing' : 'seated');
            const orderParam = updatedOrder.payment_status === 'paid' ? null : updatedOrder.id;
            const stewardParam = updatedOrder.payment_status === 'paid' ? null : updatedOrder.steward_name;
            await db.query(
                'UPDATE dining_tables SET status = ?, current_order_id = ?, steward_name = ? WHERE id = ?',
                [tableStatus, orderParam, stewardParam, updatedOrder.table_id]
            );
            const [tblRows] = await db.query('SELECT * FROM dining_tables WHERE id = ?', [updatedOrder.table_id]);
            broadcast({ type: 'table_status_changed', data: tblRows[0] });
        }

        // If payment method is updated to credit, update the customer's outstanding balance
        if (payment_method === 'credit' && updatedOrder) {
            const finalCustomerId = customer_id || updatedOrder.customer_id;
            if (finalCustomerId) {
                await db.query(
                    'UPDATE customers SET outstanding_balance = outstanding_balance + ? WHERE id = ?',
                    [updatedOrder.total, finalCustomerId]
                );
                await logAudit('modify_bill', 'customers', finalCustomerId, `Added outstanding balance LKR ${updatedOrder.total} via Credit Order Update: ${updatedOrder.order_number}`, req.user.id);
                // Also broadcast shift_updated / customer_updated so clients sync
                broadcast({ type: 'customer_updated', data: { id: finalCustomerId } });
                broadcast({ type: 'shift_updated' });
            }
        }

        // Log payment or status changes
        if (payment_status === 'paid' && updatedOrder) {
            await logAudit('pay_order', 'orders', id, `Order ${updatedOrder.order_number} marked as PAID via ${updatedOrder.payment_method || 'N/A'}. Total: LKR ${updatedOrder.total}`, req.user.id);
        } else if (status && status !== 'cancelled' && updatedOrder) {
            await logAudit('modify_bill', 'orders', id, `Order ${updatedOrder.order_number} status updated to ${status.toUpperCase()}.`, req.user.id);
        }
        
        if (status === 'cancelled' && updatedOrder) {
            // Restore inventory if cancelled
            const items = await db.query('SELECT * FROM order_items WHERE order_id = ?', [id]);
            for (const item of items) {
                const [prodRows] = await db.query('SELECT track_stock FROM products WHERE id = ?', [item.product_id]);
                const trackStock = prodRows[0] ? prodRows[0].track_stock : 1;
                if (trackStock) {
                    await db.query('UPDATE products SET stock_qty = stock_qty + ? WHERE id = ?', [item.quantity, item.product_id]);
                    await db.query(
                        'INSERT INTO stock_logs (product_id, change_qty, type, reason, user_id) VALUES (?, ?, "adjustment", ?, ?)',
                        [item.product_id, item.quantity, `Order Cancelled: ${updatedOrder.order_number}`, req.user.id]
                    );
                }
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
                            
                            // Adjust online stocks if track_stock is enabled
                            const [prodRows] = await conn.query('SELECT track_stock FROM products WHERE id = ?', [item.product_id]);
                            const trackStock = prodRows[0] ? prodRows[0].track_stock : 1;
                            if (trackStock) {
                                await conn.query('UPDATE products SET stock_qty = stock_qty - ? WHERE id = ?', [item.quantity, item.product_id]);
                            }
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

        // Check low stock notifications for synced items
        if (offline_orders && offline_orders.length > 0) {
            for (const o of offline_orders) {
                if (o.items && o.items.length > 0) {
                    for (const item of o.items) {
                        checkLowStockNotification(item.product_id).catch(err => console.error("Error checking low stock after sync:", err));
                    }
                }
            }
        }
        
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
        const { start_date, end_date } = req.query;
        
        let start = start_date;
        let end = end_date;
        if (!start || !end) {
            const now = new Date();
            const year = now.getFullYear();
            const month = String(now.getMonth() + 1).padStart(2, '0');
            start = `${year}-${month}-01`;
            const lastDay = new Date(year, now.getMonth() + 1, 0).getDate();
            end = `${year}-${month}-${String(lastDay).padStart(2, '0')}`;
        }

        const [{ total_sales }] = await db.query('SELECT COALESCE(SUM(total), 0) as total_sales FROM orders WHERE payment_status = "paid" AND DATE(created_at) BETWEEN ? AND ?', [start, end]);
        const [{ total_orders }] = await db.query('SELECT COUNT(*) as total_orders FROM orders WHERE DATE(created_at) BETWEEN ? AND ?', [start, end]);
        const [{ total_customers }] = await db.query('SELECT COUNT(*) as total_customers FROM customers');
        const [{ total_menu_items }] = await db.query('SELECT COUNT(*) as total_menu_items FROM products WHERE status = "active"');
        
        // Status counts
        const orderStatuses = await db.query('SELECT status, COUNT(*) as count FROM orders WHERE DATE(created_at) BETWEEN ? AND ? GROUP BY status', [start, end]);
        
        // Top selling products
        const topSelling = await db.query(`
            SELECT p.name, SUM(oi.quantity) as qty, SUM(oi.quantity * oi.price) as revenue
            FROM order_items oi
            JOIN products p ON oi.product_id = p.id
            JOIN orders o ON oi.order_id = o.id
            WHERE o.payment_status = "paid" AND DATE(o.created_at) BETWEEN ? AND ?
            GROUP BY p.id
            ORDER BY qty DESC
            LIMIT 5
        `, [start, end]);
        
        // Hourly Sales (dashboard graph)
        const hourlySales = await db.query(`
            SELECT HOUR(created_at) as hour, SUM(total) as sales
            FROM orders
            WHERE payment_status = "paid" AND DATE(created_at) BETWEEN ? AND ?
            GROUP BY HOUR(created_at)
            ORDER BY hour
        `, [start, end]);
        
        // Payment method breakdown
        const payments = await db.query(`
            SELECT payment_method, SUM(total) as amount, COUNT(*) as count
            FROM orders
            WHERE payment_status = "paid" AND DATE(created_at) BETWEEN ? AND ?
            GROUP BY payment_method
        `, [start, end]);
        
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

        // Top Customers (who ordered the most)
        const topCustomers = await db.query(`
            SELECT COALESCE(c.name, 'Walking Customer') as name, COUNT(o.id) as orders_count
            FROM orders o
            LEFT JOIN customers c ON o.customer_id = c.id
            WHERE DATE(o.created_at) BETWEEN ? AND ?
            GROUP BY o.customer_id, c.name
            ORDER BY orders_count DESC
            LIMIT 5
        `, [start, end]);

        // Customer Stats (hourly unique customer count / check-ins)
        const customerStats = await db.query(`
            SELECT HOUR(created_at) as hour, COUNT(DISTINCT COALESCE(customer_id, 0)) as count
            FROM orders
            WHERE DATE(created_at) BETWEEN ? AND ?
            GROUP BY HOUR(created_at)
            ORDER BY hour
        `, [start, end]);

        const hourlyMap = {};
        for (let h = 6; h <= 23; h++) {
            const label = `${String(h).padStart(2, '0')}:00`;
            hourlyMap[label] = 0;
        }
        customerStats.forEach(row => {
            const h = row.hour;
            if (h >= 6 && h <= 23) {
                const label = `${String(h).padStart(2, '0')}:00`;
                hourlyMap[label] = Number(row.count);
            }
        });
        const formattedCustomerStats = Object.keys(hourlyMap).map(hour => ({
            hour,
            count: hourlyMap[hour]
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
            payment_methods: formattedPayments,
            top_customers: topCustomers.map(tc => ({
                name: tc.name,
                orders_count: Number(tc.orders_count)
            })),
            customer_stats: formattedCustomerStats
        });
    } catch (err) {
        res.status(500).json({ error: err.message });
    }
});

// End of Day Summary API
app.get('/api/reports/eod', authenticateToken, async (req, res) => {
    const { date } = req.query;
    const localDateStr = new Date().toLocaleDateString('en-CA'); // Outputs YYYY-MM-DD in local time
    const filterDate = date || localDateStr;
    try {
        const sales = await db.query(`
            SELECT payment_method, COALESCE(SUM(total), 0) as total, COUNT(*) as count
            FROM orders
            WHERE payment_status = "paid" AND DATE(created_at) = ?
            GROUP BY payment_method
        `, [filterDate]);
        
        const expenses = await db.query(`
            SELECT category, COALESCE(SUM(amount), 0) as total
            FROM expenses
            WHERE expense_date = ?
            GROUP BY category
        `, [filterDate]);
        
        const creditSettlementsResult = await db.query(`
            SELECT COALESCE(SUM(amount), 0) as credit_settlements
            FROM credit_settlements
            WHERE DATE(date_paid) = ?
        `, [filterDate]);
        const credit_settlements = creditSettlementsResult[0] ? creditSettlementsResult[0].credit_settlements : 0.00;
        
        const defaultSales = {
            cash: { payment_method: 'cash', total: 0.00, count: 0 },
            card: { payment_method: 'card', total: 0.00, count: 0 },
            qr: { payment_method: 'qr', total: 0.00, count: 0 },
            credit: { payment_method: 'credit', total: 0.00, count: 0 }
        };
        
        sales.forEach(item => {
            if (item.payment_method) {
                const method = item.payment_method.toLowerCase();
                if (defaultSales[method]) {
                    defaultSales[method].total = Number(item.total);
                    defaultSales[method].count = Number(item.count);
                }
            }
        });
        
        const formattedSales = Object.values(defaultSales);

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
    const { date } = req.query;
    try {
        let sql = `
            SELECT al.*, u.username, u.role
            FROM audit_logs al
            JOIN users u ON al.user_id = u.id
        `;
        const params = [];
        if (date) {
            sql += ` WHERE DATE(al.timestamp) = ?`;
            params.push(date);
        }
        sql += ` ORDER BY al.timestamp DESC`;
        if (!date) {
            sql += ` LIMIT 100`;
        }
        const logs = await db.query(sql, params);
        res.json(logs);
    } catch (err) {
        res.status(500).json({ error: err.message });
    }
});

// ----------------------------------------------------
// ROLES & PERMISSIONS ENDPOINTS
// ----------------------------------------------------

// List all roles with member count
app.get('/api/roles', authenticateToken, async (req, res) => {
    try {
        const roles = await db.query(`
            SELECT r.id, r.name, r.created_at,
                   COUNT(u.id) AS member_count
            FROM roles r
            LEFT JOIN users u ON LOWER(u.role) = LOWER(r.name)
            GROUP BY r.id, r.name, r.created_at
            ORDER BY r.name
        `);
        res.json(roles);
    } catch (err) {
        res.status(500).json({ error: err.message });
    }
});

// Create a new role
app.post('/api/roles', authenticateToken, async (req, res) => {
    try {
        const { name } = req.body;
        if (!name) return res.status(400).json({ error: 'Role name is required' });
        const result = await db.query('INSERT INTO roles (name) VALUES (?)', [name]);
        res.json({ id: result.insertId, name });
    } catch (err) {
        if (err.code === 'ER_DUP_ENTRY') return res.status(409).json({ error: 'Role already exists' });
        res.status(500).json({ error: err.message });
    }
});

// Update a role name
app.put('/api/roles/:id', authenticateToken, async (req, res) => {
    try {
        const { name } = req.body;
        await db.query('UPDATE roles SET name = ? WHERE id = ?', [name, req.params.id]);
        res.json({ success: true });
    } catch (err) {
        res.status(500).json({ error: err.message });
    }
});

// Delete a role
app.delete('/api/roles/:id', authenticateToken, async (req, res) => {
    try {
        await db.query('DELETE FROM roles WHERE id = ?', [req.params.id]);
        res.json({ success: true });
    } catch (err) {
        res.status(500).json({ error: err.message });
    }
});

// Get permissions for a role
app.get('/api/roles/:id/permissions', authenticateToken, async (req, res) => {
    try {
        const perms = await db.query(
            'SELECT * FROM role_permissions WHERE role_id = ?',
            [req.params.id]
        );
        res.json(perms);
    } catch (err) {
        res.status(500).json({ error: err.message });
    }
});

// Save permissions for a role (bulk upsert)
app.put('/api/roles/:id/permissions', authenticateToken, async (req, res) => {
    try {
        const roleId = req.params.id;
        const { permissions } = req.body; // array of { page, can_view, can_create, can_update, can_delete }
        if (!Array.isArray(permissions)) return res.status(400).json({ error: 'permissions must be an array' });

        // Upsert each page permission
        for (const p of permissions) {
            await db.query(`
                INSERT INTO role_permissions (role_id, page, can_view, can_create, can_update, can_delete)
                VALUES (?, ?, ?, ?, ?, ?)
                ON DUPLICATE KEY UPDATE
                    can_view = VALUES(can_view),
                    can_create = VALUES(can_create),
                    can_update = VALUES(can_update),
                    can_delete = VALUES(can_delete)
            `, [roleId, p.page, p.can_view ? 1 : 0, p.can_create ? 1 : 0, p.can_update ? 1 : 0, p.can_delete ? 1 : 0]);
        }
        res.json({ success: true });
    } catch (err) {
        res.status(500).json({ error: err.message });
    }
});

// ----------------------------------------------------
// PRE-ORDERS ENDPOINTS
// ----------------------------------------------------

app.get('/api/pre-orders', authenticateToken, async (req, res) => {
    try {
        const preorders = await db.query('SELECT * FROM pre_orders ORDER BY received_date ASC');
        for (let po of preorders) {
            const items = await db.query(`
                SELECT poi.*, p.name as product_name, p.sinhala_name as product_sinhala_name
                FROM pre_order_items poi
                JOIN products p ON poi.product_id = p.id
                WHERE poi.pre_order_id = ?
            `, [po.id]);
            po.items = items;
        }
        res.json(preorders);
    } catch (err) {
        res.status(500).json({ error: err.message });
    }
});

app.post('/api/pre-orders', authenticateToken, async (req, res) => {
    const { customer_id, customer_name, customer_phone, received_date, subtotal, discount, total, items, advance_payment, balance_amount } = req.body;
    if (!customer_name || !customer_phone || !received_date || !items || items.length === 0) {
        return res.status(400).json({ error: 'Missing required pre-order details' });
    }
    
    const dbPool = await db.getPool();
    const conn = await dbPool.getConnection();
    try {
        await conn.beginTransaction();
        
        // Generate pre-order number (PRE-20260713-0001)
        const localDate = new Date();
        const year = localDate.getFullYear();
        const month = String(localDate.getMonth() + 1).padStart(2, '0');
        const day = String(localDate.getDate()).padStart(2, '0');
        const dateStr = `${year}${month}${day}`;
        const queryDate = `${year}-${month}-${day}`;
 
        const [countResult] = await conn.query('SELECT COUNT(*) as count FROM pre_orders WHERE DATE(created_at) = ?', [queryDate]);
        const nextNum = (countResult[0].count + 1).toString().padStart(4, '0');
        const preOrderNumber = `PRE-${dateStr}-${nextNum}`;
        
        const [result] = await conn.query(`
            INSERT INTO pre_orders (pre_order_number, customer_id, customer_name, customer_phone, received_date, subtotal, discount, total, advance_payment, balance_amount)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
        `, [preOrderNumber, customer_id || null, customer_name, customer_phone, received_date, subtotal, discount, total, advance_payment || 0.00, balance_amount || 0.00]);
        
        const preOrderId = result.insertId;
        
        for (const item of items) {
            await conn.query(`
                INSERT INTO pre_order_items (pre_order_id, product_id, quantity, price, notes)
                VALUES (?, ?, ?, ?, ?)
            `, [preOrderId, item.product_id, item.quantity, item.price, item.notes || null]);
        }
        
        await conn.commit();
        
        broadcast({ type: 'pre_order_created', data: { id: preOrderId, pre_order_number: preOrderNumber } });
        res.json({ success: true, id: preOrderId, pre_order_number: preOrderNumber });
    } catch (err) {
        await conn.rollback();
        res.status(500).json({ error: err.message });
    } finally {
        conn.release();
    }
});

app.put('/api/pre-orders/:id', authenticateToken, async (req, res) => {
    const { id } = req.params;
    const { customer_id, customer_name, customer_phone, received_date, subtotal, discount, total, items, status, advance_payment, balance_amount } = req.body;
    
    const dbPool = await db.getPool();
    const conn = await dbPool.getConnection();
    try {
        await conn.beginTransaction();
        
        let updateFields = [];
        let params = [];
        if (customer_id !== undefined) { updateFields.push('customer_id = ?'); params.push(customer_id); }
        if (customer_name !== undefined) { updateFields.push('customer_name = ?'); params.push(customer_name); }
        if (customer_phone !== undefined) { updateFields.push('customer_phone = ?'); params.push(customer_phone); }
        if (received_date !== undefined) { updateFields.push('received_date = ?'); params.push(received_date); }
        if (subtotal !== undefined) { updateFields.push('subtotal = ?'); params.push(subtotal); }
        if (discount !== undefined) { updateFields.push('discount = ?'); params.push(discount); }
        if (total !== undefined) { updateFields.push('total = ?'); params.push(total); }
        if (status !== undefined) { updateFields.push('status = ?'); params.push(status); }
        if (advance_payment !== undefined) { updateFields.push('advance_payment = ?'); params.push(advance_payment); }
        if (balance_amount !== undefined) { updateFields.push('balance_amount = ?'); params.push(balance_amount); }
        
        if (updateFields.length > 0) {
            params.push(id);
            await conn.query(`UPDATE pre_orders SET ${updateFields.join(', ')} WHERE id = ?`, params);
        }
        
        if (items && Array.isArray(items)) {
            await conn.query('DELETE FROM pre_order_items WHERE pre_order_id = ?', [id]);
            for (const item of items) {
                await conn.query(`
                    INSERT INTO pre_order_items (pre_order_id, product_id, quantity, price, notes)
                    VALUES (?, ?, ?, ?, ?)
                `, [id, item.product_id, item.quantity, item.price, item.notes || null]);
            }
        }
        
        await conn.commit();
        broadcast({ type: 'pre_order_updated', data: { id } });
        res.json({ success: true });
    } catch (err) {
        await conn.rollback();
        res.status(500).json({ error: err.message });
    } finally {
        conn.release();
    }
});

app.delete('/api/pre-orders/:id', authenticateToken, async (req, res) => {
    const { id } = req.params;
    try {
        await db.query('DELETE FROM pre_orders WHERE id = ?', [id]);
        broadcast({ type: 'pre_order_deleted', data: { id } });
        res.json({ success: true });
    } catch (err) {
        res.status(500).json({ error: err.message });
    }
});

// ----------------------------------------------------
// NOTIFICATIONS ENDPOINTS
// ----------------------------------------------------

app.get('/api/notifications', authenticateToken, async (req, res) => {
    try {
        const rows = await db.query('SELECT * FROM notifications ORDER BY created_at DESC LIMIT 100');
        res.json(rows);
    } catch (err) {
        res.status(500).json({ error: err.message });
    }
});

app.put('/api/notifications/read', authenticateToken, async (req, res) => {
    try {
        await db.query('UPDATE notifications SET is_read = 1');
        broadcast({ type: 'notifications_read_all' });
        res.json({ success: true });
    } catch (err) {
        res.status(500).json({ error: err.message });
    }
});

app.put('/api/notifications/:id/read', authenticateToken, async (req, res) => {
    const { id } = req.params;
    try {
        await db.query('UPDATE notifications SET is_read = 1 WHERE id = ?', [id]);
        broadcast({ type: 'notification_read', data: { id } });
        res.json({ success: true });
    } catch (err) {
        res.status(500).json({ error: err.message });
    }
});

// Background task to check for near pre-orders (30 mins before received date)
setInterval(async () => {
    try {
        const now = new Date();
        const thirtyMinsLater = new Date(now.getTime() + 30 * 60000);
        
        // Find pending pre-orders due soon
        const pending = await db.query(
            "SELECT * FROM pre_orders WHERE status = 'pending' AND is_notified = 0 AND received_date <= ?",
            [thirtyMinsLater]
        );
        
        for (const po of pending) {
            await db.query("UPDATE pre_orders SET is_notified = 1 WHERE id = ?", [po.id]);
            
            const title = "Pre-Order Alert";
            const dueTime = new Date(po.received_date).toLocaleTimeString([], { hour: '2-digit', minute: '2-digit' });
            const message = `Pre-Order ${po.pre_order_number} is due soon at ${dueTime} for ${po.customer_name}`;
            
            await db.query(
                "INSERT INTO notifications (title, message, type) VALUES (?, ?, 'pre_order_alert')",
                [title, message]
            );
            
            broadcast({
                type: 'new_notification',
                data: {
                    title,
                    message,
                    type: 'pre_order_alert',
                    created_at: new Date()
                }
            });
        }
    } catch (err) {
        console.error("Error checking pre-order alerts in background:", err);
    }
}, 60000); // Check every 1 minute

// ----------------------------------------------------
// ADMIN APP ENDPOINTS — Orders, Notifications & Reports
// ----------------------------------------------------

// GET per-user activity report — role-aware:
//   cashier/admin/owner/waiter → orders processed/served (matched by cashier_id OR steward_name)
//   kitchen                     → items prepared (filtered by user.category_id for sales & stock additions)
app.get('/api/admin/users-report', authenticateToken, async (req, res) => {
    const { from, to } = req.query;
    const fromDate = from || null;
    const toDate   = to   || null;
    try {
        const users = await db.query("SELECT id, name, username, role, category_id FROM users ORDER BY role, name");

        const result = [];
        for (const user of users) {
            const userData = {
                id: user.id,
                name: user.name,
                username: user.username,
                role: user.role,
                category_id: user.category_id,
                total_orders: 0,
                paid_orders: 0,
                total_revenue: 0,
                items_prepared: [],   // [{name, qty}] for kitchen users
                orders_list: []       // brief order list for cashiers/waiters
            };

            if (user.role === 'kitchen') {
                // Kitchen: filter items prepared for THIS chef's assigned category_id
                if (!user.category_id) {
                    userData.items_prepared = [];
                    userData.total_orders = 0;
                } else {
                    const paramsSales = [user.category_id];
                    let dateWhereSales = '';
                    if (fromDate) { dateWhereSales += ' AND DATE(o.created_at) >= ?'; paramsSales.push(fromDate); }
                    if (toDate)   { dateWhereSales += ' AND DATE(o.created_at) <= ?'; paramsSales.push(toDate); }

                    const salesItems = await db.query(`
                        SELECT p.name AS item_name,
                               SUM(oi.quantity) AS total_qty
                        FROM order_items oi
                        JOIN orders o ON o.id = oi.order_id
                        JOIN products p ON p.id = oi.product_id
                        WHERE p.category_id = ? AND o.status != 'cancelled' AND p.track_stock = 0
                        ${dateWhereSales}
                        GROUP BY p.id, p.name
                    `, paramsSales);

                    const paramsStock = [user.category_id];
                    let dateWhereStock = '';
                    if (fromDate) { dateWhereStock += ' AND DATE(sl.timestamp) >= ?'; paramsStock.push(fromDate); }
                    if (toDate)   { dateWhereStock += ' AND DATE(sl.timestamp) <= ?'; paramsStock.push(toDate); }

                    const stockItems = await db.query(`
                        SELECT p.name AS item_name,
                               SUM(sl.change_qty) AS total_qty
                        FROM stock_logs sl
                        JOIN products p ON p.id = sl.product_id
                        WHERE p.category_id = ? AND sl.change_qty > 0 AND sl.type IN ('adjustment', 'purchase') AND p.track_stock = 1
                        ${dateWhereStock}
                        GROUP BY p.id, p.name
                    `, paramsStock);

                    const itemMap = {};
                    for (const item of [...salesItems, ...stockItems]) {
                        const name = item.item_name;
                        const qty = parseInt(item.total_qty) || 0;
                        itemMap[name] = (itemMap[name] || 0) + qty;
                    }

                    const itemsPrepared = Object.keys(itemMap).map(name => ({
                        name: name,
                        qty: itemMap[name]
                    })).sort((a, b) => b.qty - a.qty);

                    userData.items_prepared = itemsPrepared;
                    userData.total_orders = itemsPrepared.reduce((sum, i) => sum + i.qty, 0);
                }
            } else {
                // Cashier / Admin / Owner / Waiter / Delivery: orders matched by cashier_id OR steward_name
                const params = [user.id, user.name];
                let dateWhere = '';
                if (fromDate) { dateWhere += ' AND DATE(o.created_at) >= ?'; params.push(fromDate); }
                if (toDate)   { dateWhere += ' AND DATE(o.created_at) <= ?'; params.push(toDate); }

                const orders = await db.query(`
                    SELECT o.id, o.order_number, o.total, o.payment_status,
                           o.payment_method, o.order_type, o.status, o.created_at,
                           COUNT(oi.id) AS item_types,
                           COALESCE(SUM(oi.quantity), 0) AS items_qty
                    FROM orders o
                    LEFT JOIN order_items oi ON oi.order_id = o.id
                    WHERE (o.cashier_id = ? OR LOWER(o.steward_name) = LOWER(?))
                    ${dateWhere}
                    GROUP BY o.id
                    ORDER BY o.created_at DESC
                `, params);

                userData.total_orders  = orders.length;
                userData.paid_orders   = orders.filter(o => o.payment_status === 'paid').length;
                userData.total_revenue = orders
                    .filter(o => o.payment_status === 'paid')
                    .reduce((s, o) => s + parseFloat(o.total || 0), 0);
                userData.orders_list = orders.map(o => ({
                    order_number: o.order_number,
                    total: parseFloat(o.total || 0),
                    payment_status: o.payment_status,
                    payment_method: o.payment_method,
                    order_type: o.order_type,
                    status: o.status,
                    created_at: o.created_at,
                    items_qty: parseInt(o.items_qty) || 0
                }));
            }

            result.push(userData);
        }

        res.json(result);
    } catch (err) {
        res.status(500).json({ error: err.message });
    }
});

// GET all users (for admin app)
app.get('/api/admin/users', authenticateToken, async (req, res) => {
    try {
        const users = await db.query(
            "SELECT id, name, username, role, email, phone, status FROM users ORDER BY name ASC"
        );
        res.json(users);
    } catch (err) {
        res.status(500).json({ error: err.message });
    }
});

// GET today's orders with items (for admin mobile app dashboard & live POS)
app.get('/api/orders/today', authenticateToken, async (req, res) => {
    try {
        const orders = await db.query(`
            SELECT o.*,
                   dt.table_number,
                   u.name as cashier_name
            FROM orders o
            LEFT JOIN dining_tables dt ON o.table_id = dt.id
            LEFT JOIN users u ON o.cashier_id = u.id
            WHERE DATE(o.created_at) = CURDATE()
            ORDER BY o.id DESC
        `);

        for (const order of orders) {
            const items = await db.query(`
                SELECT oi.*, p.name as product_name, p.sinhala_name as product_sinhala_name
                FROM order_items oi
                LEFT JOIN products p ON oi.product_id = p.id
                WHERE oi.order_id = ?
            `, [order.id]);
            order.items = items;
        }

        res.json(orders);
    } catch (err) {
        res.status(500).json({ error: err.message });
    }
});

// GET orders for a date range (for admin reports)
app.get('/api/orders/range', authenticateToken, async (req, res) => {
    const { from, to } = req.query;
    if (!from || !to) {
        return res.status(400).json({ error: 'from and to dates are required (YYYY-MM-DD)' });
    }
    try {
        const orders = await db.query(`
            SELECT o.*,
                   dt.table_number,
                   u.name as cashier_name
            FROM orders o
            LEFT JOIN dining_tables dt ON o.table_id = dt.id
            LEFT JOIN users u ON o.cashier_id = u.id
            WHERE DATE(o.created_at) >= ? AND DATE(o.created_at) <= ?
            ORDER BY o.id DESC
        `, [from, to]);

        for (const order of orders) {
            const items = await db.query(`
                SELECT oi.*, p.name as product_name
                FROM order_items oi
                LEFT JOIN products p ON oi.product_id = p.id
                WHERE oi.order_id = ?
            `, [order.id]);
            order.items = items;
        }

        res.json(orders);
    } catch (err) {
        res.status(500).json({ error: err.message });
    }
});

// GET transaction summary for dashboard detail view (date range)
app.get('/api/admin/transactions', authenticateToken, async (req, res) => {
    const { from, to } = req.query;
    const today = new Date().toISOString().slice(0, 10);
    const fromDate = from || today;
    const toDate   = to   || today;
    try {
        // All paid orders in range
        const orders = await db.query(`
            SELECT o.id, o.order_number, o.total, o.payment_method, o.payment_status,
                   o.order_type, o.created_at, o.cashier_id,
                   u.name as cashier_name,
                   dt.table_number
            FROM orders o
            LEFT JOIN users u ON o.cashier_id = u.id
            LEFT JOIN dining_tables dt ON o.table_id = dt.id
            WHERE DATE(o.created_at) >= ? AND DATE(o.created_at) <= ?
              AND o.payment_status = 'paid'
            ORDER BY o.created_at DESC
        `, [fromDate, toDate]);

        // Summary stats
        const cashIn   = orders.reduce((s, o) => s + parseFloat(o.total || 0), 0);
        const byCash   = orders.filter(o => o.payment_method === 'cash'  ).reduce((s, o) => s + parseFloat(o.total || 0), 0);
        const byCard   = orders.filter(o => o.payment_method === 'card'  ).reduce((s, o) => s + parseFloat(o.total || 0), 0);
        const byCredit = orders.filter(o => o.payment_method === 'credit').reduce((s, o) => s + parseFloat(o.total || 0), 0);

        res.json({
            from: fromDate,
            to: toDate,
            total_revenue: cashIn,
            by_cash:   byCash,
            by_card:   byCard,
            by_credit: byCredit,
            count: orders.length,
            transactions: orders
        });
    } catch (err) {
        res.status(500).json({ error: err.message });
    }
});

// GET all notifications (most recent 50)
app.get('/api/notifications', authenticateToken, async (req, res) => {
    try {
        const notifications = await db.query(
            'SELECT * FROM notifications ORDER BY created_at DESC LIMIT 50'
        );
        res.json(notifications);
    } catch (err) {
        res.status(500).json({ error: err.message });
    }
});

// PUT mark single notification as read
app.put('/api/notifications/:id/read', authenticateToken, async (req, res) => {
    const { id } = req.params;
    try {
        await db.query('UPDATE notifications SET is_read = 1 WHERE id = ?', [id]);
        res.json({ success: true });
    } catch (err) {
        res.status(500).json({ error: err.message });
    }
});

// PUT mark all notifications as read
app.put('/api/notifications/read-all', authenticateToken, async (req, res) => {
    try {
        await db.query('UPDATE notifications SET is_read = 1 WHERE is_read = 0');
        res.json({ success: true });
    } catch (err) {
        res.status(500).json({ error: err.message });
    }
});

// Start Server and Init Database
server.listen(PORT, async () => {
    console.log(`Hotel POS Server is running on port ${PORT}`);
    await db.initializeDatabase();
});
