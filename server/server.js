const express = require('express');
const http = require('http');
const WebSocket = require('ws');
const cors = require('cors');
const bcrypt = require('bcryptjs');
const jwt = require('jsonwebtoken');
const multer = require('multer');
const xlsx = require('xlsx');
require('dotenv').config();

const promClient = require('prom-client');

// Collect default Node.js metrics (CPU, memory, event loop lag, GC, etc.)
promClient.collectDefaultMetrics({ prefix: 'pos_' });

// --- HTTP Metrics ---
const httpRequestDuration = new promClient.Histogram({
  name: 'pos_http_request_duration_seconds',
  help: 'Duration of HTTP requests in seconds',
  labelNames: ['method', 'route', 'status_code'],
  buckets: [0.01, 0.05, 0.1, 0.3, 0.5, 1, 2, 5]
});

const httpRequestsTotal = new promClient.Counter({
  name: 'pos_http_requests_total',
  help: 'Total number of HTTP requests',
  labelNames: ['method', 'route', 'status_code']
});

// --- WebSocket Metrics ---
const wsActiveConnections = new promClient.Gauge({
  name: 'pos_websocket_active_connections',
  help: 'Number of active WebSocket connections'
});

const wsMessagesTotal = new promClient.Counter({
  name: 'pos_websocket_messages_total',
  help: 'Total WebSocket messages received',
  labelNames: ['direction']  // 'inbound' or 'broadcast'
});

// --- Business Metrics ---
const ordersCreatedTotal = new promClient.Counter({
  name: 'pos_orders_created_total',
  help: 'Total number of orders created'
});

const loginAttemptsTotal = new promClient.Counter({
  name: 'pos_login_attempts_total',
  help: 'Total login attempts',
  labelNames: ['result']  // 'success' or 'failure'
});

const dbQueryDuration = new promClient.Histogram({
  name: 'pos_db_query_duration_seconds',
  help: 'Duration of database queries',
  labelNames: ['operation'],
  buckets: [0.001, 0.005, 0.01, 0.05, 0.1, 0.5, 1, 5]
});

const db = require('./db');

const path = require('path');
const upload = multer({ storage: multer.memoryStorage() });

const app = express();
const server = http.createServer(app);
const wss = new WebSocket.Server({ server });

const PORT = process.env.PORT || 3000;
const JWT_SECRET = process.env.JWT_SECRET || 'hotel_pos_super_secret_key_123';

app.use(cors());
app.use(express.json({ limit: '50mb' }));
app.use(express.urlencoded({ limit: '50mb', extended: true }));

// Prometheus HTTP metrics middleware
app.use((req, res, next) => {
  const end = httpRequestDuration.startTimer();
  res.on('finish', () => {
    const route = req.route ? req.route.path : req.path;
    const labels = {
      method: req.method,
      route: route,
      status_code: res.statusCode
    };
    end(labels);
    httpRequestsTotal.inc(labels);
  });
  next();
});

app.use('/order', express.static(path.join(__dirname, 'public/customer_order')));
app.use(express.static(path.join(__dirname, 'public')));

// WebSocket Clients Map
const clients = new Set();

wss.on('connection', (ws) => {
    clients.add(ws);
    wsActiveConnections.set(clients.size);
    console.log(`New WebSocket client connected. Total clients: ${clients.size}`);
    
    ws.on('close', () => {
        clients.delete(ws);
        wsActiveConnections.set(clients.size);
        console.log(`WebSocket client disconnected. Total clients: ${clients.size}`);
    });
    
    ws.on('message', (message) => {
        wsMessagesTotal.inc({ direction: 'inbound' });
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
            wsMessagesTotal.inc({ direction: 'broadcast' });
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

// Migration Helper for Staff Meal Columns
async function ensureStaffMealColumnsExist() {
    try {
        await db.query("ALTER TABLE orders ADD COLUMN staff_user_id INT NULL").catch(() => {});
        await db.query("ALTER TABLE orders MODIFY COLUMN order_type VARCHAR(50) NOT NULL").catch(() => {});
    } catch (err) {
        console.error('Staff meal DB migration notice:', err.message);
    }
}
ensureStaffMealColumnsExist();

// Migration Helper for POS Stock Sessions
async function ensurePosStockSessionTablesExist() {
    try {
        await db.query(`
            CREATE TABLE IF NOT EXISTS pos_stock_sessions (
                id INT AUTO_INCREMENT PRIMARY KEY,
                user_id INT NOT NULL,
                session_date DATE NOT NULL,
                login_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
                logout_at DATETIME NULL,
                status ENUM('active','closed') DEFAULT 'active',
                FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE
            ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4
        `).catch(() => {});
        await db.query(`
            CREATE TABLE IF NOT EXISTS pos_stock_session_entries (
                id INT AUTO_INCREMENT PRIMARY KEY,
                session_id INT NOT NULL,
                product_id INT NOT NULL,
                added_qty INT NOT NULL DEFAULT 0,
                added_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
                FOREIGN KEY (session_id) REFERENCES pos_stock_sessions(id) ON DELETE CASCADE,
                FOREIGN KEY (product_id) REFERENCES products(id) ON DELETE CASCADE
            ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4
        `).catch(() => {});
        // Add manual remaining snapshot column (for physical count at session close)
        await db.query("ALTER TABLE pos_stock_sessions ADD COLUMN remaining_snapshot TEXT NULL").catch(() => {});
        console.log('POS Stock Session tables ensured.');
    } catch (err) {
        console.error('POS Stock Session DB migration notice:', err.message);
    }
}
ensurePosStockSessionTablesExist();


// ----------------------------------------------------
// POS STOCK SESSION ENDPOINTS
// ----------------------------------------------------

// POST /api/pos-stock/session/open — Open a new session for current user
app.post('/api/pos-stock/session/open', authenticateToken, async (req, res) => {
    try {
        const userId = req.user.id;
        const sessionDate = new Date().toISOString().slice(0, 10);

        // Check for already active session for this user today
        const existing = await db.query(
            `SELECT id FROM pos_stock_sessions WHERE user_id = ? AND session_date = ? AND status = 'active' LIMIT 1`,
            [userId, sessionDate]
        );
        if (existing.length > 0) {
            return res.json({ session_id: existing[0].id, already_open: true });
        }

        const result = await db.query(
            `INSERT INTO pos_stock_sessions (user_id, session_date, login_at, status) VALUES (?, ?, NOW(), 'active')`,
            [userId, sessionDate]
        );
        broadcast({ type: 'pos_stock_session_opened', data: { sessionId: result.insertId, userId } });
        res.json({ session_id: result.insertId, already_open: false });
    } catch (err) {
        res.status(500).json({ error: err.message });
    }
});

// POST /api/pos-stock/session/close — Close the current user's active session
app.post('/api/pos-stock/session/close', authenticateToken, async (req, res) => {
    try {
        const userId = req.user.id;
        const sessionDate = new Date().toISOString().slice(0, 10);

        const sessions = await db.query(
            `SELECT id FROM pos_stock_sessions WHERE user_id = ? AND session_date = ? AND status = 'active' ORDER BY login_at DESC LIMIT 1`,
            [userId, sessionDate]
        );
        if (sessions.length === 0) {
            return res.json({ success: false, message: 'No active session found.' });
        }
        const sessionId = sessions[0].id;
        await db.query(
            `UPDATE pos_stock_sessions SET logout_at = NOW(), status = 'closed' WHERE id = ?`,
            [sessionId]
        );
        broadcast({ type: 'pos_stock_session_closed', data: { sessionId, userId } });
        res.json({ success: true, session_id: sessionId });
    } catch (err) {
        res.status(500).json({ error: err.message });
    }
});

// POST /api/pos-stock/session/add — Add qty for a product into active session
app.post('/api/pos-stock/session/add', authenticateToken, async (req, res) => {
    try {
        const userId = req.user.id;
        const { product_id, qty } = req.body;
        if (!product_id || !qty || qty <= 0) {
            return res.status(400).json({ error: 'product_id and qty (>0) are required.' });
        }
        const sessionDate = new Date().toISOString().slice(0, 10);

        // Find or create active session
        let sessions = await db.query(
            `SELECT id FROM pos_stock_sessions WHERE user_id = ? AND session_date = ? AND status = 'active' ORDER BY login_at DESC LIMIT 1`,
            [userId, sessionDate]
        );
        let sessionId;
        if (sessions.length === 0) {
            const result = await db.query(
                `INSERT INTO pos_stock_sessions (user_id, session_date, login_at, status) VALUES (?, ?, NOW(), 'active')`,
                [userId, sessionDate]
            );
            sessionId = result.insertId;
        } else {
            sessionId = sessions[0].id;
        }

        // Insert entry
        await db.query(
            `INSERT INTO pos_stock_session_entries (session_id, product_id, added_qty, added_at) VALUES (?, ?, ?, NOW())`,
            [sessionId, product_id, qty]
        );

        broadcast({ type: 'pos_stock_session_updated', data: { sessionId, userId, productId: product_id } });
        res.json({ success: true, session_id: sessionId });
    } catch (err) {
        res.status(500).json({ error: err.message });
    }
});

// GET /api/pos-stock/session/current — Get current user's active session with full item data
app.get('/api/pos-stock/session/current', authenticateToken, async (req, res) => {
    try {
        const userId = req.user.id;
        const sessionDate = new Date().toISOString().slice(0, 10);

        const sessions = await db.query(
            `SELECT * FROM pos_stock_sessions WHERE user_id = ? AND session_date = ? AND status = 'active' ORDER BY login_at DESC LIMIT 1`,
            [userId, sessionDate]
        );

        if (sessions.length === 0) {
            return res.json({ session: null, items: [] });
        }

        const session = sessions[0];
        const sessionId = session.id;

        // Get all entries for this session grouped by product
        const entries = await db.query(`
            SELECT psse.product_id, p.name as product_name, p.sinhala_name,
                   psse.added_qty, psse.added_at, psse.id as entry_id
            FROM pos_stock_session_entries psse
            JOIN products p ON psse.product_id = p.id
            WHERE psse.session_id = ?
            ORDER BY psse.product_id, psse.added_at ASC
        `, [sessionId]);

        // Get POS sales since session start for each product
        const salesData = await db.query(`
            SELECT oi.product_id, SUM(oi.quantity) as sold_qty
            FROM order_items oi
            JOIN orders o ON oi.order_id = o.id
            WHERE o.created_at >= ? AND o.payment_status = 'paid'
            GROUP BY oi.product_id
        `, [session.login_at]);

        const salesMap = {};
        salesData.forEach(s => { salesMap[s.product_id] = Number(s.sold_qty); });

        // Group entries by product
        const productMap = {};
        entries.forEach(e => {
            if (!productMap[e.product_id]) {
                productMap[e.product_id] = {
                    product_id: e.product_id,
                    product_name: e.product_name,
                    sinhala_name: e.sinhala_name,
                    additions: [],
                    total_added: 0,
                };
            }
            productMap[e.product_id].additions.push({ qty: e.added_qty, at: e.added_at, entry_id: e.entry_id });
            productMap[e.product_id].total_added += Number(e.added_qty);
        });

        const items = Object.values(productMap).map(item => ({
            ...item,
            sold_qty: salesMap[item.product_id] || 0,
            remaining: item.total_added - (salesMap[item.product_id] || 0),
            count_string: item.additions.map(a => a.qty).join('+'),
        }));

        res.json({ session, items });
    } catch (err) {
        res.status(500).json({ error: err.message });
    }
});

// GET /api/pos-stock/sessions — Admin only: get all sessions (with optional date/user filter)
app.get('/api/pos-stock/sessions', authenticateToken, async (req, res) => {
    const userRole = (req.user && req.user.role ? req.user.role : '').toLowerCase();
    const isAdmin = userRole === 'admin' || userRole === 'owner';

    try {
        const { date, user_id } = req.query;
        const targetDate = date || new Date().toISOString().slice(0, 10);

        let query = `
            SELECT pss.*, u.name as user_name, u.username, u.role as user_role
            FROM pos_stock_sessions pss
            JOIN users u ON pss.user_id = u.id
            WHERE pss.session_date = ?
        `;
        const params = [targetDate];

        if (!isAdmin) {
            // Non-admins only see their own sessions
            query += ' AND pss.user_id = ?';
            params.push(req.user.id);
        } else if (user_id) {
            query += ' AND pss.user_id = ?';
            params.push(user_id);
        }

        query += ' ORDER BY pss.login_at DESC';
        const sessions = await db.query(query, params);

        // For each session, get its items + sales
        const result = await Promise.all(sessions.map(async (session) => {
            const entries = await db.query(`
                SELECT psse.product_id, p.name as product_name, p.sinhala_name,
                       psse.added_qty, psse.added_at
                FROM pos_stock_session_entries psse
                JOIN products p ON psse.product_id = p.id
                WHERE psse.session_id = ?
                ORDER BY psse.product_id, psse.added_at ASC
            `, [session.id]);

            // POS sales during session time range
            const endTime = session.logout_at || new Date().toISOString().replace('T', ' ').slice(0, 19);
            const salesData = await db.query(`
                SELECT oi.product_id, SUM(oi.quantity) as sold_qty
                FROM order_items oi
                JOIN orders o ON oi.order_id = o.id
                WHERE o.created_at >= ? AND o.created_at <= ? AND o.payment_status = 'paid'
                GROUP BY oi.product_id
            `, [session.login_at, endTime]);

            const salesMap = {};
            salesData.forEach(s => { salesMap[s.product_id] = Number(s.sold_qty); });

            const productMap = {};
            entries.forEach(e => {
                if (!productMap[e.product_id]) {
                    productMap[e.product_id] = {
                        product_id: e.product_id,
                        product_name: e.product_name,
                        sinhala_name: e.sinhala_name,
                        additions: [],
                        total_added: 0,
                    };
                }
                productMap[e.product_id].additions.push({ qty: e.added_qty, at: e.added_at });
                productMap[e.product_id].total_added += Number(e.added_qty);
            });

            const items = Object.values(productMap).map(item => ({
                ...item,
                sold_qty: salesMap[item.product_id] || 0,
                remaining: item.total_added - (salesMap[item.product_id] || 0),
                count_string: item.additions.map(a => a.qty).join('+'),
            }));

            return { ...session, items };
        }));

        res.json(result);
    } catch (err) {
        res.status(500).json({ error: err.message });
    }
});

// GET /api/pos-stock/session/:id — Get specific session detail
app.get('/api/pos-stock/session/:id', authenticateToken, async (req, res) => {
    try {
        const { id } = req.params;
        const userRole = (req.user && req.user.role ? req.user.role : '').toLowerCase();
        const isAdmin = userRole === 'admin' || userRole === 'owner';

        const sessions = await db.query(`
            SELECT pss.*, u.name as user_name, u.username
            FROM pos_stock_sessions pss JOIN users u ON pss.user_id = u.id
            WHERE pss.id = ?
        `, [id]);

        if (sessions.length === 0) return res.status(404).json({ error: 'Session not found.' });
        const session = sessions[0];

        // Only allow own session unless admin
        if (!isAdmin && session.user_id !== req.user.id) {
            return res.status(403).json({ error: 'Unauthorized.' });
        }

        const entries = await db.query(`
            SELECT psse.product_id, p.name as product_name, p.sinhala_name,
                   psse.added_qty, psse.added_at
            FROM pos_stock_session_entries psse
            JOIN products p ON psse.product_id = p.id
            WHERE psse.session_id = ?
            ORDER BY psse.product_id, psse.added_at ASC
        `, [id]);

        const endTime = session.logout_at || new Date().toISOString().replace('T', ' ').slice(0, 19);
        const salesData = await db.query(`
            SELECT oi.product_id, SUM(oi.quantity) as sold_qty
            FROM order_items oi
            JOIN orders o ON oi.order_id = o.id
            WHERE o.created_at >= ? AND o.created_at <= ? AND o.payment_status = 'paid'
            GROUP BY oi.product_id
        `, [session.login_at, endTime]);

        const salesMap = {};
        salesData.forEach(s => { salesMap[s.product_id] = Number(s.sold_qty); });

        const productMap = {};
        entries.forEach(e => {
            if (!productMap[e.product_id]) {
                productMap[e.product_id] = {
                    product_id: e.product_id,
                    product_name: e.product_name,
                    sinhala_name: e.sinhala_name,
                    additions: [],
                    total_added: 0,
                };
            }
            productMap[e.product_id].additions.push({ qty: e.added_qty, at: e.added_at });
            productMap[e.product_id].total_added += Number(e.added_qty);
        });

        const items = Object.values(productMap).map(item => ({
            ...item,
            sold_qty: salesMap[item.product_id] || 0,
            remaining: item.total_added - (salesMap[item.product_id] || 0),
            count_string: item.additions.map(a => a.qty).join('+'),
        }));

        res.json({ session, items });
    } catch (err) {
        res.status(500).json({ error: err.message });
    }
});

// POST /api/pos-stock/session/:id/snapshot — Save physical count at session close
app.post('/api/pos-stock/session/:id/snapshot', authenticateToken, async (req, res) => {
    try {
        const { id } = req.params;
        const { manual_remaining } = req.body; // { "product_id": actual_count }

        const sessions = await db.query('SELECT * FROM pos_stock_sessions WHERE id = ?', [id]);
        if (sessions.length === 0) return res.status(404).json({ error: 'Session not found' });
        const session = sessions[0];

        const userRole = (req.user && req.user.role ? req.user.role : '').toLowerCase();
        const isAdmin = userRole === 'admin' || userRole === 'owner';
        if (!isAdmin && session.user_id !== req.user.id) return res.status(403).json({ error: 'Unauthorized' });

        await db.query(
            "UPDATE pos_stock_sessions SET remaining_snapshot = ?, logout_at = NOW(), status = 'closed' WHERE id = ?",
            [JSON.stringify(manual_remaining || {}), id]
        );

        broadcast({ type: 'pos_stock_session_closed', data: { sessionId: id, userId: session.user_id } });
        res.json({ success: true });
    } catch (err) {
        res.status(500).json({ error: err.message });
    }
});


// ----------------------------------------------------
// AUTHENTICATION ENDPOINTS
// ----------------------------------------------------

// ----------------------------------------------------
// VPS LIVE LOG RECORDING & INSPECTION API
// ----------------------------------------------------
const recentServerLogs = [];
function addServerLog(level, message) {
    const timestamp = new Date().toISOString();
    recentServerLogs.unshift({ timestamp, level, message });
    if (recentServerLogs.length > 300) recentServerLogs.pop();
}

const originalConsoleLog = console.log;
const originalConsoleError = console.error;
console.log = function(...args) {
    originalConsoleLog.apply(console, args);
    addServerLog('INFO', args.map(a => (typeof a === 'object' ? JSON.stringify(a) : a)).join(' '));
};
console.error = function(...args) {
    originalConsoleError.apply(console, args);
    addServerLog('ERROR', args.map(a => (typeof a === 'object' ? JSON.stringify(a) : a)).join(' '));
};

// GET /api/logs — View live VPS server logs directly in browser or app
app.get('/api/logs', (req, res) => {
    res.json({
        success: true,
        server_time: new Date().toISOString(),
        total_logs: recentServerLogs.length,
        logs: recentServerLogs
    });
});

// Prometheus metrics endpoint
app.get('/metrics', async (req, res) => {
  try {
    res.set('Content-Type', promClient.register.contentType);
    res.end(await promClient.register.metrics());
  } catch (err) {
    res.status(500).end(err.message);
  }
});

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
            loginAttemptsTotal.inc({ result: 'failure' });
            return res.status(400).json({ error: 'User not found' });
        }
        
        const user = users[0];
        if (user.status !== 'active') {
            loginAttemptsTotal.inc({ result: 'failure' });
            return res.status(403).json({ error: 'User account is inactive' });
        }
        
        const validPassword = await bcrypt.compare(password, user.password_hash);
        if (!validPassword) {
            loginAttemptsTotal.inc({ result: 'failure' });
            return res.status(400).json({ error: 'Invalid password' });
        }
        
        const token = jwt.sign({ id: user.id, username: user.username, role: user.role }, JWT_SECRET, { expiresIn: '24h' });
        
        await logAudit('login', 'users', user.id, `User ${username} logged in.`, user.id);
        
        loginAttemptsTotal.inc({ result: 'success' });
        res.json({
            token,
            user: { id: user.id, name: user.name, username: user.username, role: user.role, image_base64: user.image_base64 }
        });
    } catch (err) {
        loginAttemptsTotal.inc({ result: 'failure' });
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
    const userRole = (req.user && req.user.role ? req.user.role : '').toLowerCase();
    if (userRole !== 'admin' && userRole !== 'owner' && userRole !== 'system administrator' && userRole !== 'manager' && userRole !== 'cashier') {
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
        broadcast({ type: 'category_created', data: { categoryId: newId, category } });
        broadcast({ type: 'database_synchronized' });
        triggerRemoteMirror({ categories: [category] });
        res.json(category);
    } catch (err) {
        res.status(500).json({ error: err.message });
    }
});

// Update Product Category
app.put('/api/categories/:id', authenticateToken, async (req, res) => {
    const userRole = (req.user && req.user.role ? req.user.role : '').toLowerCase();
    if (userRole !== 'admin' && userRole !== 'owner' && userRole !== 'system administrator' && userRole !== 'manager' && userRole !== 'cashier') {
        return res.status(403).json({ error: 'Unauthorized' });
    }
    const { id } = req.params;
    const { name, image_base64 } = req.body;
    if (!name || name.trim() === '') {
        return res.status(400).json({ error: 'Category name is required' });
    }
    try {
        const [existingCat] = await db.query('SELECT image_base64 FROM categories WHERE id = ?', [id]);
        const finalImageBase64 = (image_base64 !== undefined && image_base64 !== null) ? image_base64 : (existingCat ? existingCat.image_base64 : null);

        await db.query(
            'UPDATE categories SET name = ?, image_base64 = ? WHERE id = ?',
            [name.trim(), finalImageBase64, id]
        );
        const [category] = await db.query('SELECT * FROM categories WHERE id = ?', [id]);
        broadcast({ type: 'category_updated', data: { categoryId: id, category } });
        broadcast({ type: 'database_synchronized' });
        triggerRemoteMirror({ categories: [category] });
        res.json(category);
    } catch (err) {
        res.status(500).json({ error: err.message });
    }
});

// Delete Product Category
app.delete('/api/categories/:id', authenticateToken, async (req, res) => {
    const userRole = (req.user && req.user.role ? req.user.role : '').toLowerCase();
    if (userRole !== 'admin' && userRole !== 'owner' && userRole !== 'system administrator') {
        return res.status(403).json({ error: 'Unauthorized' });
    }
    const { id } = req.params;
    try {
        await db.query('UPDATE categories SET status = "inactive" WHERE id = ?', [id]);
        broadcast({ type: 'category_deleted', data: { categoryId: id } });
        broadcast({ type: 'database_synchronized' });
        res.json({ success: true, message: 'Category marked as inactive' });
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
    const userRole = (req.user && req.user.role ? req.user.role : '').toLowerCase();
    if (userRole !== 'admin' && userRole !== 'owner' && userRole !== 'system administrator' && userRole !== 'manager' && userRole !== 'cashier') {
        return res.status(403).json({ error: 'Unauthorized role: ' + (req.user ? req.user.role : 'none') });
    }
    const {
        name, sinhala_name, description, category_id, price, cost, barcode,
        stock_qty, min_stock_level, is_short_eat, status, image_base64,
        item_type, tax, is_featured, caution,
        has_sizes, has_extras, has_addons, track_stock,
        sizes, extras, addons, is_happy_hour_eligible, ingredients, is_kot_item
    } = req.body;
    
    try {
        let validCatId = category_id;
        if (!validCatId || validCatId === 0 || validCatId === '0') {
            const [firstCat] = await db.query("SELECT id FROM categories LIMIT 1");
            validCatId = firstCat ? firstCat.id : null;
        }

        const sizesStr = typeof sizes === 'string' ? sizes : (sizes ? JSON.stringify(sizes) : null);
        const extrasStr = typeof extras === 'string' ? extras : (extras ? JSON.stringify(extras) : null);
        const addonsStr = typeof addons === 'string' ? addons : (addons ? JSON.stringify(addons) : null);
        const ingredientsStr = typeof ingredients === 'string' ? ingredients : (ingredients ? JSON.stringify(ingredients) : null);

        const result = await db.query(`
            INSERT INTO products (
                name, sinhala_name, description, category_id, price, cost, barcode,
                stock_qty, min_stock_level, is_short_eat, status, image_base64,
                item_type, tax, is_featured, caution,
                has_sizes, has_extras, has_addons, track_stock,
                sizes, extras, addons, is_happy_hour_eligible, ingredients, is_kot_item
            ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
        `, [
            name, sinhala_name || null, description || null, validCatId, price || 0.00, cost || 0.00, barcode || null,
            stock_qty || 0, min_stock_level || 10, is_short_eat ? 1 : 0, status || 'active', image_base64 || null,
            item_type || 'Veg', tax || 0.00, is_featured ? 1 : 0, caution || null,
            has_sizes ? 1 : 0, has_extras ? 1 : 0, has_addons ? 1 : 0, track_stock !== undefined ? (track_stock ? 1 : 0) : 1,
            sizesStr, extrasStr, addonsStr,
            is_happy_hour_eligible !== undefined ? (is_happy_hour_eligible ? 1 : 0) : 1,
            ingredientsStr, is_kot_item ? 1 : 0
        ]);
        
        const newId = result.insertId;
        const [product] = await db.query('SELECT * FROM products WHERE id = ?', [newId]);
        
        await logAudit('edit_stock', 'products', newId, `Product ${name} created manually.`, req.user.id);
        broadcast({ type: 'database_synchronized' });
        
        triggerRemoteMirror({ products: [product] });
        res.json(product);
    } catch (err) {
        console.error('Error creating product:', err.message);
        res.status(500).json({ error: err.message });
    }
});

// Manual Product CRUD - Update Product
app.put('/api/products/:id', authenticateToken, async (req, res) => {
    const userRole = (req.user && req.user.role ? req.user.role : '').toLowerCase();
    if (userRole !== 'admin' && userRole !== 'owner' && userRole !== 'system administrator' && userRole !== 'manager' && userRole !== 'cashier') {
        return res.status(403).json({ error: 'Unauthorized role: ' + (req.user ? req.user.role : 'none') });
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
        let validCatId = category_id;
        if (!validCatId || validCatId === 0 || validCatId === '0') {
            const [firstCat] = await db.query("SELECT id FROM categories LIMIT 1");
            validCatId = firstCat ? firstCat.id : null;
        }

        const [existingProd] = await db.query('SELECT image_base64 FROM products WHERE id = ?', [id]);
        const finalImageBase64 = (image_base64 !== undefined && image_base64 !== null) ? image_base64 : (existingProd ? existingProd.image_base64 : null);

        const sizesStr = typeof sizes === 'string' ? sizes : (sizes ? JSON.stringify(sizes) : null);
        const extrasStr = typeof extras === 'string' ? extras : (extras ? JSON.stringify(extras) : null);
        const addonsStr = typeof addons === 'string' ? addons : (addons ? JSON.stringify(addons) : null);
        const ingredientsStr = typeof ingredients === 'string' ? ingredients : (ingredients ? JSON.stringify(ingredients) : null);

        await db.query(`
            UPDATE products SET
                name = ?, sinhala_name = ?, description = ?, category_id = ?, price = ?, cost = ?, barcode = ?,
                stock_qty = ?, min_stock_level = ?, is_short_eat = ?, status = ?, image_base64 = ?,
                item_type = ?, tax = ?, is_featured = ?, caution = ?,
                has_sizes = ?, has_extras = ?, has_addons = ?, track_stock = ?,
                sizes = ?, extras = ?, addons = ?, is_happy_hour_eligible = ?, ingredients = ?, is_kot_item = ?
            WHERE id = ?
        `, [
            name, sinhala_name || null, description || null, validCatId, price || 0.00, cost || 0.00, barcode || null,
            stock_qty || 0, min_stock_level || 10, is_short_eat ? 1 : 0, status || 'active', finalImageBase64,
            item_type || 'Veg', tax || 0.00, is_featured ? 1 : 0, caution || null,
            has_sizes ? 1 : 0, has_extras ? 1 : 0, has_addons ? 1 : 0, track_stock !== undefined ? (track_stock ? 1 : 0) : 1,
            sizesStr, extrasStr, addonsStr,
            is_happy_hour_eligible !== undefined ? (is_happy_hour_eligible ? 1 : 0) : 1,
            ingredientsStr, is_kot_item ? 1 : 0,
            id
        ]);
        
        const [product] = await db.query('SELECT * FROM products WHERE id = ?', [id]);
        
        await logAudit('edit_stock', 'products', id, `Product ${name} updated manually.`, req.user.id);
        broadcast({ type: 'product_updated', data: { productId: id, product } });
        broadcast({ type: 'database_synchronized' });
        
        triggerRemoteMirror({ products: [product] });
        res.json(product);
    } catch (err) {
        console.error('Error updating product:', err.message);
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
        if (status === 'empty') {
            await db.query('UPDATE orders SET status = "cancelled" WHERE table_id = ? AND payment_status = "unpaid"', [id]);
        }
        await db.query(
            'UPDATE dining_tables SET status = ?, steward_name = ?, current_order_id = ? WHERE id = ?',
            [status, steward_name || null, current_order_id || null, id]
        );
        
        const [updatedTable] = await db.query('SELECT * FROM dining_tables WHERE id = ?', [id]);
        
        // Broadcast table status update and order cancellation to all terminals
        broadcast({ type: 'table_status_changed', data: updatedTable });
        broadcast({ type: 'order_updated', data: { table_id: id, status: 'cancelled' } });
        
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
                sql += ' WHERE LOWER(role) IN ("admin", "owner", "administrator", "hotel owner")';
            } else if (role === 'delivery') {
                sql += ' WHERE LOWER(role) IN ("delivery", "delivery boy", "delivery rider")';
            } else if (role === 'cashier') {
                sql += ' WHERE LOWER(role) IN ("cashier", "employee")';
            } else if (role === 'waiter') {
                sql += ' WHERE LOWER(role) IN ("waiter", "steward", "steward / waiter")';
            } else if (role === 'kitchen') {
                sql += ' WHERE LOWER(role) IN ("kitchen", "chef", "chef / kitchen")';
            } else {
                sql += ' WHERE LOWER(role) = LOWER(?)';
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
        const orders = await db.query(`
            SELECT o.*, su.name as staff_name
            FROM orders o
            LEFT JOIN users su ON o.staff_user_id = su.id
            ORDER BY o.created_at DESC
        `);
        res.json(orders);
    } catch (err) {
        res.status(500).json({ error: err.message });
    }
});

app.get('/api/orders/by-number/:orderNumber', authenticateToken, async (req, res) => {
    const { orderNumber } = req.params;
    try {
        let orders = await db.query('SELECT * FROM orders WHERE order_number = ? LIMIT 1', [orderNumber]);
        if (orders.length === 0) {
            orders = await db.query('SELECT * FROM orders WHERE order_number = ? OR order_number = ? OR order_number LIKE ? LIMIT 1', [
                `O-${orderNumber}`,
                `ORD-${orderNumber}`,
                `%${orderNumber}`
            ]);
        }
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

// Create Order (Dine-in / Takeaway / Delivery / Staff Meal)
app.post('/api/orders', authenticateToken, async (req, res) => {
    const {
        table_id, order_type, delivery_platform, customer_id, steward_name, staff_user_id,
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
                // Generate unique order number (e.g. O-260730-0004)
                const localDate = new Date();
                const fullYear = localDate.getFullYear();
                const shortYear = String(fullYear).slice(-2);
                const month = String(localDate.getMonth() + 1).padStart(2, '0');
                const day = String(localDate.getDate()).padStart(2, '0');
                const dateStr = `${shortYear}${month}${day}`;
                const queryDate = `${fullYear}-${month}-${day}`;
         
                const [countResult] = await conn.query('SELECT COUNT(*) as count FROM orders WHERE DATE(created_at) = ?', [queryDate]);
                const nextNum = (countResult[0].count + 1).toString().padStart(4, '0');
                orderNumber = `O-${dateStr}-${nextNum}`;
            }
        }
        
        const barcode = orderNumber; // Barcode maps to order number
        
        let newOrderId = existingOrderId;
        
        if (!existingOrderId) {
            // Insert new order
            const [orderResult] = await conn.query(`
                INSERT INTO orders (
                    order_number, table_id, order_type, delivery_platform, customer_id, steward_name, staff_user_id,
                    status, payment_status, payment_method, subtotal, discount, total, cashier_id,
                    shift_id, kot_printed, ack_printed, card_tx_reference, barcode, received_amount, change_amount,
                    advance_payment, balance_amount, pre_order_id
                ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            `, [
                orderNumber, table_id || null, order_type, delivery_platform || null, customer_id || null,
                steward_name || null, staff_user_id || null, status || 'pending', payment_status || 'unpaid', payment_method || null,
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
            if (item.product_id) {
                const [pRows] = await conn.query('SELECT id FROM products WHERE id = ?', [item.product_id]);
                if (pRows.length === 0) {
                    await conn.query(`
                        INSERT INTO products (id, name, sinhala_name, category_id, price, cost, barcode, status)
                        VALUES (?, ?, ?, 1, ?, 0.00, ?, 'active')
                        ON DUPLICATE KEY UPDATE name = VALUES(name)
                    `, [
                        item.product_id,
                        item.product_name || item.name || `Product #${item.product_id}`,
                        item.product_sinhala_name || item.sinhala_name || null,
                        item.price || 0.00,
                        `AUTOGEN_${item.product_id}`
                    ]);
                }
            }

            await conn.query(`
                INSERT INTO order_items (
                    order_id, order_number, product_id, product_name, product_sinhala_name,
                    quantity, price, notes, status, is_short_eat
                ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            `, [
                newOrderId, orderNumber, item.product_id,
                item.product_name || item.name || null, item.product_sinhala_name || item.sinhala_name || null,
                item.quantity, item.price, item.notes || null, item.status || 'pending',
                item.is_short_eat ? 1 : 0
            ]);
            
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
        
        ordersCreatedTotal.inc();
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
// POS CASHIER SHIFTS & DRAWER RECONCILIATION
// ----------------------------------------------------

app.get('/api/shifts/current', authenticateToken, async (req, res) => {
    try {
        const shifts = await db.query(
            "SELECT * FROM shifts WHERE status = 'open' ORDER BY id DESC LIMIT 1"
        );
        if (shifts.length === 0) return res.status(200).send(null);
        res.json(shifts[0]);
    } catch (err) {
        res.status(500).json({ error: err.message });
    }
});

app.post('/api/shifts/open', authenticateToken, async (req, res) => {
    try {
        const { opening_balance } = req.body;
        const userId = req.user.id;

        // Check if shift is already open
        const existing = await db.query(
            "SELECT * FROM shifts WHERE status = 'open' ORDER BY id DESC LIMIT 1"
        );

        let activeShift = null;
        if (existing.length > 0) {
            activeShift = existing[0];
        } else {
            const result = await db.query(
                "INSERT INTO shifts (user_id, start_time, opening_balance, status) VALUES (?, NOW(), ?, 'open')",
                [userId, opening_balance || 0.00]
            );
            const [newShift] = await db.query("SELECT * FROM shifts WHERE id = ?", [result.insertId]);
            activeShift = newShift;
        }

        // Auto clock-in user to staff_shifts if not already clocked in
        const activeStaffShift = await db.query(
            "SELECT * FROM staff_shifts WHERE user_id = ? AND status = 'active'",
            [userId]
        );
        if (activeStaffShift.length === 0) {
            await db.query(
                "INSERT INTO staff_shifts (user_id, clock_in, status) VALUES (?, NOW(), 'active')",
                [userId]
            );
        }

        broadcast({ type: 'shift_updated', data: activeShift });
        broadcast({ type: 'staff_attendance_updated' });

        res.json(activeShift);
    } catch (err) {
        res.status(500).json({ error: err.message });
    }
});

app.post('/api/shifts/close', authenticateToken, async (req, res) => {
    try {
        const { shift_id, closing_balance, actual_closing_balance } = req.body;
        const userId = req.user.id;

        await db.query(
            "UPDATE shifts SET end_time = NOW(), closing_balance = ?, actual_closing_balance = ?, status = 'closed' WHERE id = ?",
            [closing_balance || 0.00, actual_closing_balance || 0.00, shift_id]
        );

        // Auto clock-out user in staff_shifts if clocked in
        const activeStaffShift = await db.query(
            "SELECT * FROM staff_shifts WHERE user_id = ? AND status = 'active' ORDER BY id DESC LIMIT 1",
            [userId]
        );
        if (activeStaffShift.length > 0) {
            const shift = activeStaffShift[0];
            const clockInTime = new Date(shift.clock_in);
            const now = new Date();
            const durationMinutes = Math.max(1, Math.round((now.getTime() - clockInTime.getTime()) / 60000));

            await db.query(
                "UPDATE staff_shifts SET clock_out = NOW(), duration_minutes = ?, status = 'completed' WHERE id = ?",
                [durationMinutes, shift.id]
            );
        }

        const [closedShift] = await db.query("SELECT * FROM shifts WHERE id = ?", [shift_id]);

        broadcast({ type: 'shift_updated', data: closedShift });
        broadcast({ type: 'staff_attendance_updated' });

        res.json(closedShift);
    } catch (err) {
        res.status(500).json({ error: err.message });
    }
});

app.post('/api/shifts/drawer-log', authenticateToken, async (req, res) => {
    try {
        const { shift_id, type, amount, reason } = req.body;
        const result = await db.query(
            "INSERT INTO cash_drawer_logs (shift_id, type, amount, reason) VALUES (?, ?, ?, ?)",
            [shift_id, type, amount, reason || '']
        );
        broadcast({ type: 'shift_updated' });
        res.json({ success: true, id: result.insertId });
    } catch (err) {
        res.status(500).json({ error: err.message });
    }
});

app.get('/api/shifts/:shiftId/drawer-logs', authenticateToken, async (req, res) => {
    try {
        const { shiftId } = req.params;
        const logs = await db.query("SELECT * FROM cash_drawer_logs WHERE shift_id = ? ORDER BY timestamp DESC", [shiftId]);
        res.json(logs);
    } catch (err) {
        res.status(500).json({ error: err.message });
    }
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
    
    const syncedOrders = [];
    const syncedShifts = [];
    const syncedExpenses = [];
    const syncedStockLogs = [];
    const syncedAuditLogs = [];

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
                        [s.id, s.user_id, formatMySqlDateTime(s.start_time), formatMySqlDateTime(s.end_time), s.opening_balance, s.closing_balance, s.actual_closing_balance, s.status]
                    );
                } else {
                    await conn.query(
                        'UPDATE shifts SET end_time = ?, closing_balance = ?, actual_closing_balance = ?, status = ? WHERE id = ?',
                        [formatMySqlDateTime(s.end_time), s.closing_balance, s.actual_closing_balance, s.status, s.id]
                    );
                }
                syncedShifts.push(s.id);
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
                            shift_id, kot_printed, ack_printed, card_tx_reference, barcode, created_at, sync_status,
                            received_amount, change_amount
                        ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, 'synced', ?, ?)
                    `, [
                        o.order_number, o.table_id || null, o.order_type || 'takeaway', o.delivery_platform || null, o.customer_id || null,
                        o.steward_name || null, o.status || 'pending', o.payment_status || 'unpaid', o.payment_method || null,
                        o.subtotal || 0, o.discount || 0, o.total || 0, o.cashier_id || 1, o.shift_id || 1, o.kot_printed || false,
                        o.ack_printed || false, o.card_tx_reference || null, o.barcode || o.order_number, formatMySqlDateTime(o.created_at),
                        o.received_amount || 0, o.change_amount || 0
                    ]);
                    
                    // Sync items
                    if (o.items && o.items.length > 0) {
                        for (const item of o.items) {
                            if (item.product_id) {
                                const [pRows] = await conn.query('SELECT id FROM products WHERE id = ?', [item.product_id]);
                                if (pRows.length === 0) {
                                    await conn.query(`
                                        INSERT INTO products (id, name, sinhala_name, category_id, price, cost, barcode, status)
                                        VALUES (?, ?, ?, 1, ?, 0.00, ?, 'active')
                                        ON DUPLICATE KEY UPDATE name = VALUES(name)
                                    `, [
                                        item.product_id,
                                        item.product_name || item.name || `Product #${item.product_id}`,
                                        item.product_sinhala_name || item.sinhala_name || null,
                                        item.price || 0.00,
                                        `AUTOGEN_${item.product_id}`
                                    ]);
                                }
                            }
                            await conn.query(`
                                INSERT INTO order_items (
                                    order_id, order_number, product_id, product_name, product_sinhala_name,
                                    quantity, price, notes, status, is_short_eat
                                ) VALUES ((SELECT id FROM orders WHERE order_number = ?), ?, ?, ?, ?, ?, ?, ?, ?, ?)
                            `, [
                                o.order_number, o.order_number, item.product_id,
                                item.product_name || item.name || null, item.product_sinhala_name || item.sinhala_name || null,
                                item.quantity || 1, item.price || 0, item.notes || null, item.status || 'pending',
                                item.is_short_eat ? 1 : 0
                            ]);
                            
                            // Adjust online stocks if track_stock is enabled
                            const [prodRows] = await conn.query('SELECT track_stock FROM products WHERE id = ?', [item.product_id]);
                            const trackStock = prodRows[0] ? prodRows[0].track_stock : 1;
                            if (trackStock) {
                                await conn.query('UPDATE products SET stock_qty = stock_qty - ? WHERE id = ?', [item.quantity || 1, item.product_id]);
                            }
                        }
                    }
                }
                syncedOrders.push(o.order_number);
            }
        }
        
        // Sync Expenses
        if (offline_expenses && offline_expenses.length > 0) {
            for (const e of offline_expenses) {
                const [existing] = await conn.query('SELECT id FROM expenses WHERE id = ?', [e.id]);
                if (existing.length === 0) {
                    await conn.query(
                        'INSERT INTO expenses (id, title, amount, category, payment_source, recorded_by, expense_date, created_at) VALUES (?, ?, ?, ?, ?, ?, ?, ?)',
                        [e.id, e.title, e.amount, e.category, e.payment_source, e.recorded_by, formatMySqlDate(e.expense_date), formatMySqlDateTime(e.created_at)]
                    );
                }
                syncedExpenses.push(e.id);
            }
        }
        
        // Sync Stock Logs
        if (offline_stock_logs && offline_stock_logs.length > 0) {
            for (const sl of offline_stock_logs) {
                await conn.query(
                    'INSERT INTO stock_logs (product_id, change_qty, type, reason, user_id, timestamp) VALUES (?, ?, ?, ?, ?, ?)',
                    [sl.product_id, sl.change_qty, sl.type, sl.reason, sl.user_id, formatMySqlDateTime(sl.timestamp)]
                );
                syncedStockLogs.push(sl.id);
            }
        }
        
        // Sync Audit Logs
        if (offline_audit_logs && offline_audit_logs.length > 0) {
            for (const al of offline_audit_logs) {
                await conn.query(
                    'INSERT INTO audit_logs (action_type, table_name, record_id, details, user_id, timestamp) VALUES (?, ?, ?, ?, ?, ?)',
                    [al.action_type, al.table_name, al.record_id, al.details, al.user_id, formatMySqlDateTime(al.timestamp)]
                );
                syncedAuditLogs.push(al.id);
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
            synced: true,
            synced_orders: syncedOrders,
            synced_shifts: syncedShifts,
            synced_expenses: syncedExpenses,
            synced_stock_logs: syncedStockLogs,
            synced_audit_logs: syncedAuditLogs,
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
// USER MANAGEMENT ENDPOINTS
// ----------------------------------------------------

// List all users
app.get('/api/users', authenticateToken, async (req, res) => {
    try {
        const { role } = req.query;
        let sql = 'SELECT id, name, username, role, status, email, phone, branch, category_id, image_base64, created_at FROM users';
        const params = [];
        if (role) {
            if (role === 'admin_owner') {
                sql += ' WHERE LOWER(role) IN ("admin", "owner")';
            } else if (role === 'kitchen' || role === 'chef') {
                sql += ' WHERE LOWER(role) IN ("kitchen", "chef")';
            } else {
                sql += ' WHERE LOWER(role) = LOWER(?)';
                params.push(role);
            }
        }
        sql += ' ORDER BY name ASC';
        const users = await db.query(sql, params);
        res.json(users);
    } catch (err) {
        res.status(500).json({ error: err.message });
    }
});

// Admin Users Route Alias
app.get('/api/admin/users', authenticateToken, async (req, res) => {
    try {
        const users = await db.query('SELECT id, name, username, role, status, email, phone, branch, category_id, image_base64, created_at FROM users ORDER BY id DESC');
        res.json(users);
    } catch (err) {
        res.status(500).json({ error: err.message });
    }
});

// Create a new user
app.post('/api/users', authenticateToken, async (req, res) => {
    let { name, username, password, role, status, email, phone, branch, category_id, image_base64 } = req.body;
    if (!name || !username || !password) {
        return res.status(400).json({ error: 'Name, username, and password are required' });
    }
    try {
        // Normalize chef/kitchen role to 'kitchen'
        if (role && (role.toLowerCase() === 'chef' || role.toLowerCase() === 'kitchen')) {
            role = 'kitchen';
        }

        // Check username uniqueness
        const existing = await db.query('SELECT id FROM users WHERE username = ?', [username.trim()]);
        if (existing.length > 0) {
            return res.status(400).json({ error: 'Username already exists' });
        }

        const password_hash = await bcrypt.hash(password, 10);
        const result = await db.query(`
            INSERT INTO users (name, username, password_hash, role, status, email, phone, branch, category_id, image_base64)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
        `, [
            name.trim(),
            username.trim(),
            password_hash,
            role || 'cashier',
            status || 'active',
            email || null,
            phone || null,
            branch || 'current',
            category_id !== undefined ? category_id : null,
            image_base64 || null
        ]);

        const newUserId = result.insertId;
        const [newUser] = await db.query(
            'SELECT id, name, username, role, status, email, phone, branch, category_id, image_base64, created_at FROM users WHERE id = ?',
            [newUserId]
        );

        await logAudit('login', 'users', newUserId, `User ${username} created by Admin.`, req.user.id);
        broadcast({ type: 'database_synchronized' });

        res.json(newUser);
    } catch (err) {
        res.status(500).json({ error: err.message });
    }
});

// Update user details
app.put('/api/users/:id', authenticateToken, async (req, res) => {
    const { id } = req.params;
    let { name, username, role, status, email, phone, branch, category_id, image_base64 } = req.body;
    try {
        const users = await db.query('SELECT * FROM users WHERE id = ?', [id]);
        if (users.length === 0) {
            return res.status(404).json({ error: 'User not found' });
        }

        // Normalize chef/kitchen role to 'kitchen'
        if (role && (role.toLowerCase() === 'chef' || role.toLowerCase() === 'kitchen')) {
            role = 'kitchen';
        }

        if (username) {
            const existing = await db.query('SELECT id FROM users WHERE username = ? AND id != ?', [username.trim(), id]);
            if (existing.length > 0) {
                return res.status(400).json({ error: 'Username is taken by another user' });
            }
        }

        await db.query(`
            UPDATE users SET
                name = COALESCE(?, name),
                username = COALESCE(?, username),
                role = COALESCE(?, role),
                status = COALESCE(?, status),
                email = ?,
                phone = ?,
                branch = COALESCE(?, branch),
                category_id = ?,
                image_base64 = COALESCE(?, image_base64)
            WHERE id = ?
        `, [
            name ? name.trim() : null,
            username ? username.trim() : null,
            role || null,
            status || null,
            email !== undefined ? email : users[0].email,
            phone !== undefined ? phone : users[0].phone,
            branch || null,
            category_id !== undefined ? category_id : users[0].category_id,
            image_base64 !== undefined ? image_base64 : users[0].image_base64,
            id
        ]);

        const [updatedUser] = await db.query(
            'SELECT id, name, username, role, status, email, phone, branch, category_id, image_base64, created_at FROM users WHERE id = ?',
            [id]
        );

        await logAudit('login', 'users', id, `User ${updatedUser.username} updated by Admin.`, req.user.id);
        broadcast({ type: 'database_synchronized' });

        res.json(updatedUser);
    } catch (err) {
        res.status(500).json({ error: err.message });
    }
});

// Reset user password
app.put('/api/users/:id/password', authenticateToken, async (req, res) => {
    const { id } = req.params;
    const { password } = req.body;
    if (!password) {
        return res.status(400).json({ error: 'Password is required' });
    }
    try {
        const password_hash = await bcrypt.hash(password, 10);
        await db.query('UPDATE users SET password_hash = ? WHERE id = ?', [password_hash, id]);

        await logAudit('login', 'users', id, `Password reset for user ID ${id} by Admin.`, req.user.id);
        res.json({ success: true, message: 'Password updated successfully' });
    } catch (err) {
        res.status(500).json({ error: err.message });
    }
});

// Deactivate / Delete user
app.delete('/api/users/:id', authenticateToken, async (req, res) => {
    const { id } = req.params;
    try {
        const users = await db.query('SELECT name, username FROM users WHERE id = ?', [id]);
        if (users.length === 0) {
            return res.status(404).json({ error: 'User not found' });
        }
        await db.query('UPDATE users SET status = "inactive" WHERE id = ?', [id]);

        await logAudit('login', 'users', id, `User ${users[0].username} deactivated by Admin.`, req.user.id);
        broadcast({ type: 'database_synchronized' });

        res.json({ success: true, message: 'User deactivated successfully' });
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
        const defaultRoles = ['Admin', 'Cashier', 'Waiter', 'Chef', 'Delivery Boy', 'Short Eats Cabin'];
        for (const r of defaultRoles) {
            await db.query('INSERT IGNORE INTO roles (name) VALUES (?)', [r]);
        }
        const roles = await db.query(`
            SELECT r.id, r.name, r.created_at,
                   COUNT(u.id) AS member_count
            FROM roles r
            LEFT JOIN users u ON (
                LOWER(u.role) = LOWER(r.name)
                OR (LOWER(r.name) IN ('chef', 'kitchen') AND LOWER(u.role) IN ('chef', 'kitchen'))
                OR (LOWER(r.name) IN ('delivery', 'delivery boy') AND LOWER(u.role) IN ('delivery', 'delivery boy'))
                OR (LOWER(r.name) IN ('admin', 'administrator') AND LOWER(u.role) IN ('admin', 'administrator'))
                OR (LOWER(r.name) IN ('waiter', 'waiters', 'steward') AND LOWER(u.role) IN ('waiter', 'waiters', 'steward'))
                OR (LOWER(r.name) IN ('cashier', 'employee') AND LOWER(u.role) IN ('cashier', 'employee'))
                OR (LOWER(r.name) IN ('owner', 'hotel owner') AND LOWER(u.role) IN ('owner', 'hotel owner'))
            )
            GROUP BY r.id, r.name, r.created_at
            ORDER BY r.name
        `);
        res.json(roles);
    } catch (err) {
        res.json([
            { id: 1, name: 'Admin', member_count: 1 },
            { id: 2, name: 'Cashier', member_count: 1 },
            { id: 3, name: 'Waiter', member_count: 0 },
            { id: 4, name: 'Chef', member_count: 0 },
            { id: 5, name: 'Delivery Boy', member_count: 0 }
        ]);
    }
});

// Create a new role
app.post('/api/roles', authenticateToken, async (req, res) => {
    try {
        const { name } = req.body;
        if (!name) return res.status(400).json({ error: 'Role name is required' });
        const result = await db.query('INSERT INTO roles (name) VALUES (?)', [name]);
        broadcast({ type: 'database_synchronized' });
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
        broadcast({ type: 'database_synchronized' });
        res.json({ success: true });
    } catch (err) {
        res.status(500).json({ error: err.message });
    }
});

// Delete a role
app.delete('/api/roles/:id', authenticateToken, async (req, res) => {
    try {
        await db.query('DELETE FROM roles WHERE id = ?', [req.params.id]);
        broadcast({ type: 'database_synchronized' });
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
        broadcast({ type: 'database_synchronized' });
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
        const preorders = await db.query('SELECT * FROM pre_orders ORDER BY id DESC');
        for (let po of preorders) {
            const items = await db.query(`
                SELECT poi.*, p.name as product_name, p.sinhala_name as product_sinhala_name
                FROM pre_order_items poi
                LEFT JOIN products p ON poi.product_id = p.id
                WHERE poi.pre_order_id = ?
            `, [po.id]);
            po.items = items;
        }
        res.json(preorders);
    } catch (err) {
        res.json([]);
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
        
        // Generate pre-order number (P-260730-0001)
        const localDate = new Date();
        const fullYear = localDate.getFullYear();
        const shortYear = String(fullYear).slice(-2);
        const month = String(localDate.getMonth() + 1).padStart(2, '0');
        const day = String(localDate.getDate()).padStart(2, '0');
        const dateStr = `${shortYear}${month}${day}`;
        const queryDate = `${fullYear}-${month}-${day}`;
 
        const [countResult] = await conn.query('SELECT COUNT(*) as count FROM pre_orders WHERE DATE(created_at) = ?', [queryDate]);
        const nextNum = (countResult[0].count + 1).toString().padStart(4, '0');
        const preOrderNumber = `P-${dateStr}-${nextNum}`;
        
        const [result] = await conn.query(`
            INSERT INTO pre_orders (pre_order_number, customer_id, customer_name, customer_phone, received_date, subtotal, discount, total, advance_payment, balance_amount)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
        `, [preOrderNumber, customer_id || null, customer_name, customer_phone, received_date, subtotal, discount, total, advance_payment || 0.00, balance_amount || 0.00]);
        
        const preOrderId = result.insertId;
        
        for (const item of items) {
            await conn.query(`
                INSERT INTO pre_order_items (pre_order_id, product_id, product_name, quantity, price, notes)
                VALUES (?, ?, ?, ?, ?, ?)
            `, [preOrderId, item.product_id, item.product_name || null, item.quantity, item.price, item.notes || null]);
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
                    INSERT INTO pre_order_items (pre_order_id, product_id, product_name, quantity, price, notes)
                    VALUES (?, ?, ?, ?, ?, ?)
                `, [id, item.product_id, item.product_name || null, item.quantity, item.price, item.notes || null]);
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

// ----------------------------------------------------
// STAFF SHIFT & ATTENDANCE ENDPOINTS (Clock In / Clock Out)
// ----------------------------------------------------

// GET current staff shift status & history
app.get('/api/staff/shift-status', authenticateToken, async (req, res) => {
    const userId = req.user.id;
    try {
        const activeShifts = await db.query(
            "SELECT * FROM staff_shifts WHERE user_id = ? AND status = 'active' ORDER BY id DESC LIMIT 1",
            [userId]
        );
        const history = await db.query(
            "SELECT * FROM staff_shifts WHERE user_id = ? ORDER BY clock_in DESC LIMIT 20",
            [userId]
        );

        res.json({
            active_shift: activeShifts.length > 0 ? activeShifts[0] : null,
            is_clocked_in: activeShifts.length > 0,
            history: history
        });
    } catch (err) {
        res.status(500).json({ error: err.message });
    }
});

// POST Clock In
app.post('/api/staff/clock-in', authenticateToken, async (req, res) => {
    const userId = req.user.id;
    try {
        const active = await db.query(
            "SELECT * FROM staff_shifts WHERE user_id = ? AND status = 'active'",
            [userId]
        );
        if (active.length > 0) {
            return res.status(400).json({
                error: 'Already clocked in',
                active_shift: active[0]
            });
        }

        const result = await db.query(
            "INSERT INTO staff_shifts (user_id, clock_in, status) VALUES (?, NOW(), 'active')",
            [userId]
        );
        const [newShift] = await db.query(
            "SELECT * FROM staff_shifts WHERE id = ?",
            [result.insertId]
        );

        broadcast({
            type: 'staff_clock_in',
            data: { user_id: userId, user_name: req.user.name, shift: newShift }
        });

        res.json({ success: true, message: 'Clocked in successfully', shift: newShift });
    } catch (err) {
        res.status(500).json({ error: err.message });
    }
});

// POST Clock Out
app.post('/api/staff/clock-out', authenticateToken, async (req, res) => {
    const userId = req.user.id;
    try {
        const active = await db.query(
            "SELECT * FROM staff_shifts WHERE user_id = ? AND status = 'active' ORDER BY id DESC LIMIT 1",
            [userId]
        );
        if (active.length === 0) {
            return res.status(400).json({ error: 'No active shift found to clock out' });
        }

        const shift = active[0];
        const clockInTime = new Date(shift.clock_in);
        const now = new Date();
        const durationMinutes = Math.max(1, Math.round((now.getTime() - clockInTime.getTime()) / 60000));

        await db.query(
            "UPDATE staff_shifts SET clock_out = NOW(), duration_minutes = ?, status = 'completed' WHERE id = ?",
            [durationMinutes, shift.id]
        );

        const [completedShift] = await db.query(
            "SELECT * FROM staff_shifts WHERE id = ?",
            [shift.id]
        );

        broadcast({
            type: 'staff_clock_out',
            data: { user_id: userId, user_name: req.user.name, shift: completedShift }
        });

        res.json({
            success: true,
            message: 'Clocked out successfully',
            shift: completedShift,
            duration_minutes: durationMinutes
        });
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

// GET single order details by ID or order_number / pre_order_number
app.get('/api/orders/:id', authenticateToken, async (req, res) => {
    const { id } = req.params;
    try {
        // First check in orders table
        let orders = await db.query(`
            SELECT o.*,
                   dt.table_number,
                   u.name as cashier_name,
                   c.name as customer_name,
                   c.phone as customer_phone
            FROM orders o
            LEFT JOIN dining_tables dt ON o.table_id = dt.id
            LEFT JOIN users u ON o.cashier_id = u.id
            LEFT JOIN customers c ON o.customer_id = c.id
            WHERE o.id = ? OR o.order_number = ?
            LIMIT 1
        `, [id, id]);

        if (orders.length > 0) {
            const order = orders[0];
            const items = await db.query(`
                SELECT oi.*, oi.price as unit_price, (oi.quantity * oi.price) as subtotal,
                       p.name as product_name, p.sinhala_name as product_sinhala_name, p.is_short_eat
                FROM order_items oi
                LEFT JOIN products p ON oi.product_id = p.id
                WHERE oi.order_id = ?
            `, [order.id]);
            order.items = items;
            return res.json(order);
        }

        // If not found in orders, check pre_orders table
        let preorders = await db.query(`
            SELECT po.*,
                   po.pre_order_number as order_number,
                   'takeaway' as order_type,
                   'completed' as status,
                   IF(po.balance_amount <= 0, 'paid', 'unpaid') as payment_status,
                   'cash' as payment_method,
                   c.name as customer_name_from_db,
                   c.phone as customer_phone_from_db
            FROM pre_orders po
            LEFT JOIN customers c ON po.customer_id = c.id
            WHERE po.id = ? OR po.pre_order_number = ?
            LIMIT 1
        `, [id, id]);

        if (preorders.length > 0) {
            const po = preorders[0];
            if (!po.customer_name && po.customer_name_from_db) {
                po.customer_name = po.customer_name_from_db;
            }
            if (!po.customer_phone && po.customer_phone_from_db) {
                po.customer_phone = po.customer_phone_from_db;
            }
            const items = await db.query(`
                SELECT poi.*, poi.price as unit_price, (poi.quantity * poi.price) as subtotal,
                       p.name as product_name, p.sinhala_name as product_sinhala_name
                FROM pre_order_items poi
                LEFT JOIN products p ON poi.product_id = p.id
                WHERE poi.pre_order_id = ?
            `, [po.id]);
            po.items = items;
            return res.json(po);
        }

        return res.status(404).json({ error: 'Order not found' });
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
        // All paid orders in range (excluding staff_meal)
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
              AND o.order_type != 'staff_meal'
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

// GET Staff Meal Report
app.get('/api/reports/staff-meals', authenticateToken, async (req, res) => {
    try {
        const { from, to, staff_id } = req.query;
        let query = `
            SELECT o.*,
                   dt.table_number,
                   u.name as cashier_name,
                   su.name as staff_name,
                   su.role as staff_role
            FROM orders o
            LEFT JOIN dining_tables dt ON o.table_id = dt.id
            LEFT JOIN users u ON o.cashier_id = u.id
            LEFT JOIN users su ON o.staff_user_id = su.id
            WHERE o.order_type = 'staff_meal'
        `;
        let params = [];

        if (from && to) {
            query += ` AND DATE(o.created_at) >= ? AND DATE(o.created_at) <= ?`;
            params.push(from, to);
        }
        if (staff_id && staff_id !== 'all') {
            query += ` AND o.staff_user_id = ?`;
            params.push(staff_id);
        }

        query += ` ORDER BY o.id DESC`;

        const orders = await db.query(query, params);

        for (const order of orders) {
            const items = await db.query(`
                SELECT oi.*, p.name as product_name, p.sinhala_name as product_sinhala_name, p.price as regular_price, p.cost as item_cost
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

// ----------------------------------------------------
// STAFF ATTENDANCE & PAYROLL / SALARY ENDPOINTS
// ----------------------------------------------------

async function ensurePayrollTablesExist() {
    try {
        await db.query(`
            CREATE TABLE IF NOT EXISTS staff_shifts (
                id INT AUTO_INCREMENT PRIMARY KEY,
                user_id INT NOT NULL,
                clock_in DATETIME NOT NULL,
                clock_out DATETIME DEFAULT NULL,
                duration_minutes INT DEFAULT 0,
                status ENUM('active', 'completed') DEFAULT 'active',
                created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
                FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE
            ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4
        `);

        await db.query(`
            CREATE TABLE IF NOT EXISTS global_settings (
                setting_key VARCHAR(100) PRIMARY KEY,
                setting_value TEXT NULL,
                updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP
            ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4
        `);
        await db.query("INSERT IGNORE INTO global_settings (setting_key, setting_value) VALUES ('global_ot_rate', '250.00')");
        await db.query("INSERT IGNORE INTO global_settings (setting_key, setting_value) VALUES ('salary_notification_days', '2')");

        await db.query(`
            CREATE TABLE IF NOT EXISTS staff_payroll_settings (
                id INT AUTO_INCREMENT PRIMARY KEY,
                user_id INT NOT NULL UNIQUE,
                basic_salary DECIMAL(10,2) DEFAULT 0.00,
                salary_type ENUM('daily', 'weekly', 'monthly') DEFAULT 'monthly',
                ot_rate_per_hour DECIMAL(10,2) NULL,
                allowances DECIMAL(10,2) DEFAULT 0.00,
                salary_due_day INT DEFAULT 28,
                created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
                updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
                FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE
            ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4
        `);

        await db.query(`
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
            ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4
        `);

        await db.query(`
            CREATE TABLE IF NOT EXISTS staff_payrolls (
                id INT AUTO_INCREMENT PRIMARY KEY,
                user_id INT NOT NULL,
                period_start DATE NOT NULL,
                period_end DATE NOT NULL,
                basic_salary DECIMAL(10,2) DEFAULT 0.00,
                working_hours DECIMAL(10,2) DEFAULT 0.00,
                ot_hours DECIMAL(10,2) DEFAULT 0.00,
                ot_rate DECIMAL(10,2) DEFAULT 0.00,
                ot_amount DECIMAL(10,2) DEFAULT 0.00,
                tip_amount DECIMAL(10,2) DEFAULT 0.00,
                bonuses_others DECIMAL(10,2) DEFAULT 0.00,
                allowances DECIMAL(10,2) DEFAULT 0.00,
                advance_deduction DECIMAL(10,2) DEFAULT 0.00,
                net_salary DECIMAL(10,2) NOT NULL,
                payment_method ENUM('cash', 'bank', 'drawer') DEFAULT 'cash',
                payment_status ENUM('draft', 'paid') DEFAULT 'paid',
                paid_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
                created_by INT NULL,
                created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
                FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE,
                FOREIGN KEY (created_by) REFERENCES users(id) ON DELETE SET NULL
            ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4
        `);

        // Self-healing missing column migrations for pre-existing tables
        try { await db.query("ALTER TABLE staff_payroll_settings ADD COLUMN user_id INT NULL"); } catch (_) {}
        try { await db.query("ALTER TABLE staff_payroll_settings ADD COLUMN basic_salary DECIMAL(10,2) DEFAULT 0.00"); } catch (_) {}
        try { await db.query("ALTER TABLE staff_payroll_settings ADD COLUMN salary_type ENUM('daily', 'weekly', 'monthly') DEFAULT 'monthly'"); } catch (_) {}
        try { await db.query("ALTER TABLE staff_payroll_settings ADD COLUMN daily_rate DECIMAL(10,2) DEFAULT 0.00"); } catch (_) {}
        try { await db.query("ALTER TABLE staff_payroll_settings ADD COLUMN ot_rate_per_hour DECIMAL(10,2) NULL"); } catch (_) {}
        try { await db.query("ALTER TABLE staff_payroll_settings ADD COLUMN allowances DECIMAL(10,2) DEFAULT 0.00"); } catch (_) {}
        try { await db.query("ALTER TABLE staff_payroll_settings ADD COLUMN salary_due_day INT DEFAULT 28"); } catch (_) {}
        try { await db.query("ALTER TABLE staff_payroll_settings ADD COLUMN allow_ot TINYINT(1) DEFAULT 1"); } catch (_) {}

        // Remove duplicate setting entries per user_id if any exist
        try {
            await db.query(`
                DELETE t1 FROM staff_payroll_settings t1
                INNER JOIN staff_payroll_settings t2 
                WHERE t1.id < t2.id AND t1.user_id = t2.user_id
            `);
        } catch (_) {}

        try { await db.query("ALTER TABLE staff_advances ADD COLUMN user_id INT NULL"); } catch (_) {}
        try { await db.query("ALTER TABLE staff_advances ADD COLUMN amount DECIMAL(10,2) DEFAULT 0.00"); } catch (_) {}
        try { await db.query("ALTER TABLE staff_advances ADD COLUMN amount_deducted DECIMAL(10,2) DEFAULT 0.00"); } catch (_) {}
        try { await db.query("ALTER TABLE staff_advances ADD COLUMN remaining_balance DECIMAL(10,2) NULL"); } catch (_) {}
        try { await db.query("ALTER TABLE staff_advances ADD COLUMN reason VARCHAR(255) DEFAULT NULL"); } catch (_) {}
        try { await db.query("ALTER TABLE staff_advances ADD COLUMN advance_date DATE NULL DEFAULT NULL"); } catch (_) {}
        try { await db.query("ALTER TABLE staff_advances MODIFY COLUMN advance_date DATE NULL DEFAULT NULL"); } catch (_) {}
        try { await db.query("ALTER TABLE staff_advances ADD COLUMN date_given DATE NULL DEFAULT NULL"); } catch (_) {}
        try { await db.query("ALTER TABLE staff_advances MODIFY COLUMN date_given DATE NULL DEFAULT NULL"); } catch (_) {}
        try { await db.query("ALTER TABLE staff_advances ADD COLUMN status ENUM('pending', 'partially_deducted', 'deducted', 'settled') DEFAULT 'pending'"); } catch (_) {}
        try { await db.query("ALTER TABLE staff_advances MODIFY COLUMN status ENUM('pending', 'partially_deducted', 'deducted', 'settled') DEFAULT 'pending'"); } catch (_) {}
        try { await db.query("ALTER TABLE staff_advances ADD COLUMN recorded_by INT NULL"); } catch (_) {}

        try { await db.query("ALTER TABLE staff_payrolls ADD COLUMN user_id INT NULL"); } catch (_) {}
        try { await db.query("ALTER TABLE staff_payrolls ADD COLUMN period_start DATE NULL"); } catch (_) {}
        try { await db.query("ALTER TABLE staff_payrolls ADD COLUMN period_end DATE NULL"); } catch (_) {}
        try { await db.query("ALTER TABLE staff_payrolls ADD COLUMN basic_salary DECIMAL(10,2) DEFAULT 0.00"); } catch (_) {}
        try { await db.query("ALTER TABLE staff_payrolls ADD COLUMN working_hours DECIMAL(10,2) DEFAULT 0.00"); } catch (_) {}
        try { await db.query("ALTER TABLE staff_payrolls ADD COLUMN ot_hours DECIMAL(10,2) DEFAULT 0.00"); } catch (_) {}
        try { await db.query("ALTER TABLE staff_payrolls ADD COLUMN ot_rate DECIMAL(10,2) DEFAULT 0.00"); } catch (_) {}
        try { await db.query("ALTER TABLE staff_payrolls ADD COLUMN ot_amount DECIMAL(10,2) DEFAULT 0.00"); } catch (_) {}
        try { await db.query("ALTER TABLE staff_payrolls ADD COLUMN tip_amount DECIMAL(10,2) DEFAULT 0.00"); } catch (_) {}
        try { await db.query("ALTER TABLE staff_payrolls ADD COLUMN allowances DECIMAL(10,2) DEFAULT 0.00"); } catch (_) {}
        try { await db.query("ALTER TABLE staff_payrolls ADD COLUMN advance_deduction DECIMAL(10,2) DEFAULT 0.00"); } catch (_) {}
        try { await db.query("ALTER TABLE staff_payrolls ADD COLUMN remaining_advance_balance DECIMAL(10,2) DEFAULT 0.00"); } catch (_) {}
        try { await db.query("ALTER TABLE staff_payrolls ADD COLUMN net_salary DECIMAL(10,2) DEFAULT 0.00"); } catch (_) {}
        try { await db.query("ALTER TABLE staff_payrolls ADD COLUMN payment_method ENUM('cash', 'bank', 'drawer') DEFAULT 'cash'"); } catch (_) {}
        try { await db.query("ALTER TABLE staff_payrolls ADD COLUMN created_by INT NULL"); } catch (_) {}

        try { await db.query("ALTER TABLE staff_shifts ADD COLUMN user_id INT NULL"); } catch (_) {}
        try { await db.query("ALTER TABLE staff_shifts ADD COLUMN clock_in DATETIME NULL"); } catch (_) {}
        try { await db.query("ALTER TABLE staff_shifts ADD COLUMN clock_out DATETIME DEFAULT NULL"); } catch (_) {}
        try { await db.query("ALTER TABLE staff_shifts ADD COLUMN duration_minutes INT DEFAULT 0"); } catch (_) {}
        try { await db.query("ALTER TABLE staff_shifts ADD COLUMN status ENUM('active', 'completed') DEFAULT 'active'"); } catch (_) {}

        try { await db.query("INSERT IGNORE INTO global_settings (setting_key, setting_value) VALUES ('global_ot_start_time', '17:00')"); } catch (_) {}
    } catch (e) {
        console.error('ensurePayrollTablesExist error:', e.message);
    }
}

// GET Staff Attendance Summary & Work Hours Analytics
// Helper to calculate Overtime (OT) minutes based on normal daily working hours exceeding threshold (default 8 hours / 480 mins per day)
function calculateOvertimeMinutesForUserShifts(shiftsList, standardDailyHours = 8.0, activeLiveMins = 0) {
    const thresholdMins = Math.round((parseFloat(standardDailyHours) || 8.0) * 60);
    let totalOtMins = 0;

    const dayMap = {};
    for (const sh of shiftsList) {
        if (!sh.clock_in) continue;
        const cin = new Date(sh.clock_in);
        const cout = sh.clock_out ? new Date(sh.clock_out) : new Date();
        const dateStr = cin.toISOString().slice(0, 10);

        if (!dayMap[dateStr]) {
            dayMap[dateStr] = 0;
        }

        const durMins = Math.max(0, Math.round((cout.getTime() - cin.getTime()) / 60000));
        dayMap[dateStr] += durMins;
    }

    const todayStr = new Date().toISOString().slice(0, 10);
    if (activeLiveMins > 0) {
        dayMap[todayStr] = (dayMap[todayStr] || 0) + activeLiveMins;
    }

    for (const dayMins of Object.values(dayMap)) {
        if (dayMins > thresholdMins) {
            totalOtMins += (dayMins - thresholdMins);
        }
    }

    return totalOtMins;
}

// GET Staff Attendance Summary & Work Hours Analytics
app.get('/api/staff/attendance/summary', authenticateToken, async (req, res) => {
    try {
        await ensurePayrollTablesExist();
        const { user_id, from, to } = req.query;
        let userFilter = '';
        let params = [];
        if (user_id) {
            userFilter = ' WHERE u.id = ?';
            params.push(user_id);
        }

        const otSettingRows = await db.query("SELECT setting_value FROM global_settings WHERE setting_key = 'global_ot_start_time'");
        const otThresholdHours = parseFloat(otSettingRows[0]?.setting_value) || 8.0;

        const users = await db.query(`
            SELECT u.id, u.name, u.username, u.role, u.status, u.image_base64
            FROM users u
            ${userFilter}
            ORDER BY u.name ASC
        `, params);

        const summaryList = [];

        for (const user of users) {
            // Check active shift from staff_shifts OR active open shift in POS shifts table
            const activeStaffShifts = await db.query(
                "SELECT * FROM staff_shifts WHERE user_id = ? AND status = 'active' ORDER BY id DESC LIMIT 1",
                [user.id]
            );

            const activePosShifts = await db.query(
                "SELECT * FROM shifts WHERE user_id = ? AND status = 'open' ORDER BY id DESC LIMIT 1",
                [user.id]
            );

            const isClockedIn = activeStaffShifts.length > 0 || activePosShifts.length > 0;
            const activeShiftObj = activeStaffShifts.length > 0
                ? activeStaffShifts[0]
                : (activePosShifts.length > 0 ? { clock_in: activePosShifts[0].start_time, status: 'active' } : null);

            let rangeCond = '';
            let rangeParams = [user.id];
            if (from) { rangeCond += ' AND DATE(clock_in) >= ?'; rangeParams.push(from); }
            if (to)   { rangeCond += ' AND DATE(clock_in) <= ?'; rangeParams.push(to); }

            const shifts = await db.query(
                `SELECT * FROM staff_shifts WHERE user_id = ? ${rangeCond} ORDER BY clock_in DESC`,
                rangeParams
            );

            const todayShifts = await db.query(
                `SELECT SUM(duration_minutes) as total_mins FROM staff_shifts WHERE user_id = ? AND DATE(clock_in) = CURDATE()`,
                [user.id]
            );
            const dailyMins = parseFloat(todayShifts[0]?.total_mins || 0);

            const weekShifts = await db.query(
                `SELECT SUM(duration_minutes) as total_mins FROM staff_shifts WHERE user_id = ? AND YEARWEEK(clock_in, 1) = YEARWEEK(CURDATE(), 1)`,
                [user.id]
            );
            const weeklyMins = parseFloat(weekShifts[0]?.total_mins || 0);

            const monthShifts = await db.query(
                `SELECT SUM(duration_minutes) as total_mins FROM staff_shifts WHERE user_id = ? AND YEAR(clock_in) = YEAR(CURDATE()) AND MONTH(clock_in) = MONTH(CURDATE())`,
                [user.id]
            );
            const monthlyMins = parseFloat(monthShifts[0]?.total_mins || 0);

            const yearShifts = await db.query(
                `SELECT SUM(duration_minutes) as total_mins FROM staff_shifts WHERE user_id = ? AND YEAR(clock_in) = YEAR(CURDATE())`,
                [user.id]
            );
            const yearlyMins = parseFloat(yearShifts[0]?.total_mins || 0);

            const totalRangeMins = shifts.reduce((s, sh) => s + (sh.duration_minutes || 0), 0);

            let activeLiveMins = 0;
            if (activeShiftObj && activeShiftObj.clock_in) {
                const diff = (new Date().getTime() - new Date(activeShiftObj.clock_in).getTime()) / 60000;
                activeLiveMins = Math.max(0, Math.floor(diff));
            }

            const distinctDays = await db.query(
                `SELECT COUNT(DISTINCT DATE(clock_in)) as day_count FROM staff_shifts WHERE user_id = ?`,
                [user.id]
            );
            const totalDaysWorked = Math.max(1, parseInt(distinctDays[0]?.day_count || 1));
            const avgDailyHours = (yearlyMins / 60) / Math.max(1, Math.min(365, totalDaysWorked));

            // Check if OT is allowed for user
            const pSettings = await db.query("SELECT allow_ot FROM staff_payroll_settings WHERE user_id = ?", [user.id]);
            const allowOt = pSettings[0] ? (parseInt(pSettings[0].allow_ot) !== 0) : true;

            const totalOtMins = allowOt ? calculateOvertimeMinutesForUserShifts(shifts, otThresholdHours, activeLiveMins) : 0;

            summaryList.push({
                user_id: user.id,
                name: user.name,
                username: user.username,
                role: user.role,
                image_base64: user.image_base64,
                is_clocked_in: isClockedIn,
                active_shift: activeShiftObj,
                daily_hours: (dailyMins + activeLiveMins) / 60,
                weekly_hours: weeklyMins / 60,
                monthly_hours: monthlyMins / 60,
                yearly_hours: yearlyMins / 60,
                average_daily_hours: avgDailyHours,
                range_total_hours: totalRangeMins / 60,
                ot_hours: totalOtMins / 60,
                shifts: shifts
            });
        }

        res.json(summaryList);
    } catch (err) {
        res.status(500).json({ error: err.message });
    }
});

// POST Manual Clock In / Clock Out adjustment
app.post('/api/staff/attendance/manual', authenticateToken, async (req, res) => {
    try {
        const { user_id, clock_in, clock_out } = req.body;
        if (!user_id || !clock_in) {
            return res.status(400).json({ error: 'user_id and clock_in are required' });
        }

        let duration_minutes = 0;
        let status = 'active';

        if (clock_out) {
            const cin = new Date(clock_in);
            const cout = new Date(clock_out);
            duration_minutes = Math.max(1, Math.round((cout.getTime() - cin.getTime()) / 60000));
            status = 'completed';
        }

        const result = await db.query(`
            INSERT INTO staff_shifts (user_id, clock_in, clock_out, duration_minutes, status)
            VALUES (?, ?, ?, ?, ?)
        `, [user_id, clock_in, clock_out || null, duration_minutes, status]);

        broadcast({ type: 'staff_attendance_updated' });
        res.json({ success: true, id: result.insertId });
    } catch (err) {
        res.status(500).json({ error: err.message });
    }
});

// GET Payroll Settings & Global OT Rate
app.get('/api/staff/payroll/settings', authenticateToken, async (req, res) => {
    try {
        await ensurePayrollTablesExist();
        const globalSettingsRows = await db.query('SELECT * FROM global_settings');
        const settingsMap = {};
        for (const r of globalSettingsRows) {
            settingsMap[r.setting_key] = r.setting_value;
        }

        const staffSettings = await db.query(`
            SELECT u.id as user_id, u.name, u.username, u.role,
                   COALESCE(sps.basic_salary, 0.00) as basic_salary,
                   COALESCE(sps.salary_type, 'monthly') as salary_type,
                   COALESCE(sps.daily_rate, 0.00) as daily_rate,
                   sps.ot_rate_per_hour,
                   COALESCE(sps.allowances, 0.00) as allowances,
                   COALESCE(sps.salary_due_day, 28) as salary_due_day,
                   COALESCE(sps.allow_ot, 1) as allow_ot
            FROM users u
            LEFT JOIN (
                SELECT user_id,
                       MAX(basic_salary) as basic_salary,
                       MAX(salary_type) as salary_type,
                       MAX(daily_rate) as daily_rate,
                       MAX(ot_rate_per_hour) as ot_rate_per_hour,
                       MAX(allowances) as allowances,
                       MAX(salary_due_day) as salary_due_day,
                       MAX(allow_ot) as allow_ot
                FROM staff_payroll_settings
                GROUP BY user_id
            ) sps ON sps.user_id = u.id
            WHERE u.status = 'active'
            ORDER BY u.name ASC
        `);

        res.json({
            global_ot_rate: parseFloat(settingsMap['global_ot_rate'] || '250.00'),
            global_ot_start_time: settingsMap['global_ot_start_time'] || '17:00',
            salary_notification_days: parseInt(settingsMap['salary_notification_days'] || '2'),
            staff_settings: staffSettings.map(s => ({
                user_id: s.user_id,
                name: s.name,
                username: s.username,
                role: s.role,
                basic_salary: parseFloat(s.basic_salary || 0.00),
                salary_type: s.salary_type || 'monthly',
                daily_rate: parseFloat(s.daily_rate || 0.00),
                ot_rate_per_hour: s.ot_rate_per_hour !== null && s.ot_rate_per_hour !== undefined ? parseFloat(s.ot_rate_per_hour) : null,
                allowances: parseFloat(s.allowances || 0.00),
                salary_due_day: parseInt(s.salary_due_day || 28),
                allow_ot: parseInt(s.allow_ot ?? 1) === 1
            }))
        });
    } catch (err) {
        console.error('Payroll Settings API Error:', err.message);
        res.status(500).json({ error: err.message });
    }
});

// PUT Payroll Settings & Global OT Rate
app.put('/api/staff/payroll/settings', authenticateToken, async (req, res) => {
    try {
        const { global_ot_rate, global_ot_start_time, salary_notification_days, user_settings } = req.body;

        if (global_ot_rate !== undefined) {
            await db.query(`
                INSERT INTO global_settings (setting_key, setting_value)
                VALUES ('global_ot_rate', ?)
                ON DUPLICATE KEY UPDATE setting_value = VALUES(setting_value)
            `, [global_ot_rate.toString()]);
        }

        if (global_ot_start_time !== undefined) {
            await db.query(`
                INSERT INTO global_settings (setting_key, setting_value)
                VALUES ('global_ot_start_time', ?)
                ON DUPLICATE KEY UPDATE setting_value = VALUES(setting_value)
            `, [global_ot_start_time.toString()]);
        }

        if (salary_notification_days !== undefined) {
            await db.query(`
                INSERT INTO global_settings (setting_key, setting_value)
                VALUES ('salary_notification_days', ?)
                ON DUPLICATE KEY UPDATE setting_value = VALUES(setting_value)
            `, [salary_notification_days.toString()]);
        }

        if (Array.isArray(user_settings)) {
            for (const s of user_settings) {
                await db.query(`
                    INSERT INTO staff_payroll_settings (user_id, basic_salary, salary_type, daily_rate, ot_rate_per_hour, allowances, salary_due_day, allow_ot)
                    VALUES (?, ?, ?, ?, ?, ?, ?, ?)
                    ON DUPLICATE KEY UPDATE
                        basic_salary = VALUES(basic_salary),
                        salary_type = VALUES(salary_type),
                        daily_rate = VALUES(daily_rate),
                        ot_rate_per_hour = VALUES(ot_rate_per_hour),
                        allowances = VALUES(allowances),
                        salary_due_day = VALUES(salary_due_day),
                        allow_ot = VALUES(allow_ot)
                `, [
                    s.user_id,
                    s.basic_salary || 0.00,
                    s.salary_type || 'monthly',
                    s.daily_rate || 0.00,
                    s.ot_rate_per_hour !== undefined && s.ot_rate_per_hour !== null ? s.ot_rate_per_hour : null,
                    s.allowances || 0.00,
                    s.salary_due_day || 28,
                    s.allow_ot === false || s.allow_ot === 0 ? 0 : 1
                ]);
            }
        }

        broadcast({ type: 'payroll_settings_updated' });
        res.json({ success: true });
    } catch (err) {
        res.status(500).json({ error: err.message });
    }
});

// GET Staff Advances
app.get('/api/staff/advances', authenticateToken, async (req, res) => {
    try {
        await ensurePayrollTablesExist();
        const { user_id, status } = req.query;
        let whereClauses = [];
        let params = [];

        if (user_id) {
            whereClauses.push('sa.user_id = ?');
            params.push(user_id);
        }
        if (status) {
            whereClauses.push('sa.status = ?');
            params.push(status);
        }

        const whereSql = whereClauses.length > 0 ? `WHERE ${whereClauses.join(' AND ')}` : '';

        const advances = await db.query(`
            SELECT sa.*, u.name as user_name, rec.name as recorded_by_name
            FROM staff_advances sa
            JOIN users u ON sa.user_id = u.id
            LEFT JOIN users rec ON sa.recorded_by = rec.id
            ${whereSql}
            ORDER BY sa.advance_date DESC, sa.id DESC
        `, params);

        res.json(advances);
    } catch (err) {
        console.error('Staff Advances API Error:', err.message);
        res.status(500).json({ error: err.message });
    }
});

// POST Grant Staff Advance
app.post('/api/staff/advances', authenticateToken, async (req, res) => {
    try {
        await ensurePayrollTablesExist();
        const { user_id, amount, reason, advance_date } = req.body;
        if (!user_id || !amount) {
            return res.status(400).json({ error: 'user_id and amount are required' });
        }

        const dateStr = advance_date || new Date().toISOString().slice(0, 10);

        const result = await db.query(`
            INSERT INTO staff_advances (user_id, amount, reason, advance_date, status, recorded_by)
            VALUES (?, ?, ?, ?, 'pending', ?)
        `, [user_id, amount, reason || 'Staff Cash Advance', dateStr, req.user.id]);

        broadcast({ type: 'staff_advance_created' });
        res.json({ success: true, id: result.insertId });
    } catch (err) {
        res.status(500).json({ error: err.message });
    }
});

// GET Calculate Salary Breakdown for Staff Member & Period
app.get('/api/staff/payroll/calculate', authenticateToken, async (req, res) => {
    try {
        await ensurePayrollTablesExist();
        const { user_id, period_start, period_end } = req.query;
        if (!user_id) {
            return res.status(400).json({ error: 'user_id is required' });
        }

        const today = new Date().toISOString().slice(0, 10);
        const startDate = period_start || new Date(new Date().getFullYear(), new Date().getMonth(), 1).toISOString().slice(0, 10);
        const endDate = period_end || today;

        const users = await db.query("SELECT id, name, username, role FROM users WHERE id = ?", [user_id]);
        if (users.length === 0) return res.status(404).json({ error: 'User not found' });
        const user = users[0];

        const globalOtRows = await db.query("SELECT setting_value FROM global_settings WHERE setting_key = 'global_ot_rate'");
        const globalOtRate = parseFloat(globalOtRows[0]?.setting_value || '250.00');

        const staffSettingRows = await db.query("SELECT * FROM staff_payroll_settings WHERE user_id = ?", [user_id]);
        const staffSetting = staffSettingRows[0] || {};

        const salaryType = staffSetting.salary_type || 'monthly';
        const dailyRate = parseFloat(staffSetting.daily_rate || 0.00);
        const allowOt = parseInt(staffSetting.allow_ot ?? 1) !== 0;

        const applicableOtRate = staffSetting.ot_rate_per_hour !== null && staffSetting.ot_rate_per_hour !== undefined
            ? parseFloat(staffSetting.ot_rate_per_hour)
            : globalOtRate;
        const allowances = parseFloat(staffSetting.allowances || 0.00);

        const shifts = await db.query(`
            SELECT * FROM staff_shifts
            WHERE user_id = ? AND DATE(clock_in) >= ? AND DATE(clock_in) <= ?
            ORDER BY clock_in DESC
        `, [user_id, startDate, endDate]);

        const distinctDaysResult = await db.query(`
            SELECT COUNT(DISTINCT DATE(clock_in)) as days_worked
            FROM staff_shifts
            WHERE user_id = ? AND DATE(clock_in) >= ? AND DATE(clock_in) <= ?
        `, [user_id, startDate, endDate]);
        const daysWorked = parseInt(distinctDaysResult[0]?.days_worked || 0);

        let basicSalary = parseFloat(staffSetting.basic_salary || 0.00);
        if (salaryType === 'daily') {
            basicSalary = daysWorked * dailyRate;
        }

        const otTimeRows = await db.query("SELECT setting_value FROM global_settings WHERE setting_key = 'global_ot_start_time'");
        const otThresholdHours = parseFloat(otTimeRows[0]?.setting_value) || 8.0;

        let activeLiveMins = 0;
        let totalMins = 0;
        for (const sh of shifts) {
            if (sh.status === 'completed') {
                totalMins += (sh.duration_minutes || 0);
            } else if (sh.status === 'active' && sh.clock_in) {
                const diff = Math.max(0, Math.floor((new Date().getTime() - new Date(sh.clock_in).getTime()) / 60000));
                activeLiveMins += diff;
                totalMins += diff;
            }
        }

        const workingHours = totalMins / 60;
        const otMins = allowOt ? calculateOvertimeMinutesForUserShifts(shifts, otThresholdHours, activeLiveMins) : 0;
        const otHours = otMins / 60;
        const otAmount = otHours * applicableOtRate;

        // No auto 5% tip calculation
        const tipAmount = 0.00;

        const advanceRows = await db.query(`
            SELECT id, amount, COALESCE(amount_deducted, 0.00) as amount_deducted
            FROM staff_advances
            WHERE user_id = ? AND status IN ('pending', 'partially_deducted')
            ORDER BY id ASC
        `, [user_id]);

        let totalOutstandingAdvance = 0.00;
        for (const adv of advanceRows) {
            const amt = parseFloat(adv.amount || 0.00);
            const ded = parseFloat(adv.amount_deducted || 0.00);
            totalOutstandingAdvance += Math.max(0, amt - ded);
        }

        const bonusesOthers = 0.00;
        const grossSalary = basicSalary + otAmount + tipAmount + allowances + bonusesOthers;
        const advanceDeduction = Math.min(grossSalary, totalOutstandingAdvance);
        const remainingAdvanceBalance = Math.max(0.00, totalOutstandingAdvance - advanceDeduction);
        const netSalary = Math.max(0.00, grossSalary - advanceDeduction);

        res.json({
            user_id: user.id,
            name: user.name,
            role: user.role,
            period_start: startDate,
            period_end: endDate,
            salary_type: salaryType,
            basic_salary: basicSalary,
            working_hours: workingHours,
            ot_hours: otHours,
            ot_rate: applicableOtRate,
            ot_amount: otAmount,
            tip_amount: tipAmount,
            allowances: allowances,
            bonuses_others: bonusesOthers,
            gross_salary: grossSalary,
            advance_deduction: advanceDeduction,
            remaining_advance_balance: remainingAdvanceBalance,
            net_salary: netSalary
        });
    } catch (err) {
        console.error('Calculate Salary API Error:', err.message);
        res.status(500).json({ error: err.message });
    }
});

// POST Finalize & Process Salary Payout
app.post('/api/staff/payroll/pay', authenticateToken, async (req, res) => {
    try {
        const {
            user_id, period_start, period_end, basic_salary, working_hours,
            ot_hours, ot_rate, ot_amount, tip_amount, bonuses_others,
            allowances, advance_deduction, remaining_advance_balance, net_salary, payment_method
        } = req.body;

        if (!user_id || net_salary === undefined) {
            return res.status(400).json({ error: 'user_id and net_salary are required' });
        }

        const users = await db.query("SELECT name FROM users WHERE id = ?", [user_id]);
        const userName = users[0]?.name || 'Staff';

        const result = await db.query(`
            INSERT INTO staff_payrolls (
                user_id, period_start, period_end, basic_salary, working_hours,
                ot_hours, ot_rate, ot_amount, tip_amount, bonuses_others,
                allowances, advance_deduction, remaining_advance_balance, net_salary, payment_method,
                payment_status, paid_at, created_by
            ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, 'paid', NOW(), ?)
        `, [
            user_id, period_start, period_end, basic_salary || 0.00, working_hours || 0.00,
            ot_hours || 0.00, ot_rate || 0.00, ot_amount || 0.00, tip_amount || 0.00, bonuses_others || 0.00,
            allowances || 0.00, advance_deduction || 0.00, remaining_advance_balance || 0.00, net_salary, payment_method || 'cash', req.user.id
        ]);

        let toDeduct = parseFloat(advance_deduction || 0.00);
        if (toDeduct > 0) {
            const pendingAdvances = await db.query(`
                SELECT id, amount, COALESCE(amount_deducted, 0.00) as amount_deducted
                FROM staff_advances
                WHERE user_id = ? AND status IN ('pending', 'partially_deducted')
                ORDER BY id ASC
            `, [user_id]);

            for (const adv of pendingAdvances) {
                if (toDeduct <= 0) break;
                const totalAmt = parseFloat(adv.amount || 0.00);
                const alreadyDed = parseFloat(adv.amount_deducted || 0.00);
                const openBal = Math.max(0, totalAmt - alreadyDed);

                const deductHere = Math.min(toDeduct, openBal);
                const newDedTotal = alreadyDed + deductHere;
                const newRemBal = Math.max(0, totalAmt - newDedTotal);
                const newStatus = newRemBal <= 0.01 ? 'settled' : 'partially_deducted';

                await db.query(`
                    UPDATE staff_advances
                    SET amount_deducted = ?, remaining_balance = ?, status = ?
                    WHERE id = ?
                `, [newDedTotal, newRemBal, newStatus, adv.id]);

                toDeduct -= deductHere;
            }
        }

        const pSource = payment_method === 'drawer' ? 'drawer' : 'bank';
        await db.query(`
            INSERT INTO expenses (title, amount, category, payment_source, recorded_by, expense_date)
            VALUES (?, ?, 'salary', ?, ?, CURDATE())
        `, [`Staff Salary - ${userName}`, net_salary, pSource, req.user.id]);

        broadcast({ type: 'staff_payroll_processed', data: { user_id, net_salary } });

        res.json({ success: true, id: result.insertId, message: 'Salary payment processed successfully' });
    } catch (err) {
        res.status(500).json({ error: err.message });
    }
});

// GET Salary History (Payslips)
app.get('/api/staff/payroll/history', authenticateToken, async (req, res) => {
    try {
        const { user_id } = req.query;
        let whereSql = '';
        let params = [];
        if (user_id) {
            whereSql = 'WHERE sp.user_id = ?';
            params.push(user_id);
        }

        const history = await db.query(`
            SELECT sp.*, u.name as user_name, u.role as user_role, creator.name as created_by_name
            FROM staff_payrolls sp
            JOIN users u ON sp.user_id = u.id
            LEFT JOIN users creator ON sp.created_by = creator.id
            ${whereSql}
            ORDER BY sp.paid_at DESC, sp.id DESC
        `, params);

        res.json(history);
    } catch (err) {
        res.status(500).json({ error: err.message });
    }
});

// Background Salary Due Date Notification Interval (Runs every 1 hour)
setInterval(async () => {
    try {
        const globalSettingsRows = await db.query("SELECT setting_value FROM global_settings WHERE setting_key = 'salary_notification_days'");
        const noticeDays = parseInt(globalSettingsRows[0]?.setting_value || '2');

        const today = new Date();
        const currentDayOfMonth = today.getDate();
        const currentYear = today.getFullYear();
        const currentMonth = today.getMonth() + 1;

        const staffSettings = await db.query(`
            SELECT sps.*, u.name
            FROM staff_payroll_settings sps
            JOIN users u ON sps.user_id = u.id
            WHERE u.status = 'active'
        `);

        for (const staff of staffSettings) {
            const dueDay = staff.salary_due_day || 28;
            let daysUntil = dueDay - currentDayOfMonth;
            if (daysUntil < 0) {
                const daysInMonth = new Date(currentYear, currentMonth, 0).getDate();
                daysUntil = (daysInMonth - currentDayOfMonth) + dueDay;
            }

            if (daysUntil >= 0 && daysUntil <= noticeDays) {
                const title = "Staff Salary Payment Due";
                const message = `Salary payment for ${staff.name} is due in ${daysUntil === 0 ? 'TODAY' : daysUntil + ' day(s)'}!`;

                const existing = await db.query(`
                    SELECT id FROM notifications
                    WHERE type = 'salary_due_alert' AND message LIKE ? AND DATE(created_at) = CURDATE()
                `, [`%${staff.name}%`]);

                if (existing.length === 0) {
                    await db.query(
                        "INSERT INTO notifications (title, message, type) VALUES (?, ?, 'salary_due_alert')",
                        [title, message]
                    );

                    broadcast({
                        type: 'new_notification',
                        data: { title, message, type: 'salary_due_alert', created_at: new Date() }
                    });
                }
            }
        }
    } catch (err) {
        console.error("Error checking staff salary due notifications:", err.message);
    }
}, 3600000);

// Order Purging Endpoint — automatically deletes orders & order_items from Local MySQL DB after sync to Remote MySQL DB
app.post('/api/orders/purge-synced', async (req, res) => {
    const { order_numbers } = req.body;
    if (!order_numbers || !Array.isArray(order_numbers) || order_numbers.length === 0) {
        return res.json({ success: true, count: 0 });
    }
    try {
        const placeholders = order_numbers.map(() => '?').join(',');
        await db.query(`DELETE FROM order_items WHERE order_number IN (${placeholders})`, order_numbers);
        const result = await db.query(`DELETE FROM orders WHERE order_number IN (${placeholders})`, order_numbers);
        console.log(`[OrderPurge] Successfully purged ${result.affectedRows || order_numbers.length} synced orders from Local MySQL DB.`);
        res.json({ success: true, count: result.affectedRows || order_numbers.length });
    } catch (err) {
        console.error('Error purging synced orders from local DB:', err.message);
        res.status(500).json({ error: err.message });
    }
});

function formatMySqlDate(dateVal) {
    if (!dateVal) return null;
    if (typeof dateVal === 'string') {
        if (dateVal.includes('T')) {
            return dateVal.split('T')[0];
        }
        return dateVal.substring(0, 10);
    }
    try {
        const d = new Date(dateVal);
        if (isNaN(d.getTime())) return null;
        return d.toISOString().split('T')[0];
    } catch (_) {
        return null;
    }
}

function formatMySqlDateTime(dateVal) {
    if (!dateVal) {
        const d = new Date();
        const pad = (n) => String(n).padStart(2, '0');
        return `${d.getFullYear()}-${pad(d.getMonth() + 1)}-${pad(d.getDate())} ${pad(d.getHours())}:${pad(d.getMinutes())}:${pad(d.getSeconds())}`;
    }
    
    try {
        const d = new Date(dateVal);
        if (!isNaN(d.getTime())) {
            const pad = (n) => String(n).padStart(2, '0');
            return `${d.getFullYear()}-${pad(d.getMonth() + 1)}-${pad(d.getDate())} ${pad(d.getHours())}:${pad(d.getMinutes())}:${pad(d.getSeconds())}`;
        }
    } catch (_) {}

    if (typeof dateVal === 'string') {
        let s = dateVal.replace('T', ' ').replace('Z', '');
        if (s.includes('.')) s = s.split('.')[0];
        if (/^\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}$/.test(s)) return s;
    }

    const now = new Date();
    const pad = (n) => String(n).padStart(2, '0');
    return `${now.getFullYear()}-${pad(now.getMonth() + 1)}-${pad(now.getDate())} ${pad(now.getHours())}:${pad(now.getMinutes())}:${pad(now.getSeconds())}`;
}

// Helper function to upsert catalog & system tables into local database
async function processCatalogMirror(body) {
    const {
        categories, products, diningTables, customers, users,
        ingredients, happyHours, offers, roles, rolePermissions,
        suppliers, globalSettings, preOrders, preOrderItems,
        expenses, shifts, cashDrawerLogs, creditSettlements,
        stockLogs, ingredientStockLogs, staffAdvances, staffPayrollSettings,
        staffPayrolls, staffShifts, supplierDeliveries, supplierPayments,
        userAddresses, orders, orderItems
    } = body || {};

    if (categories && Array.isArray(categories)) {
        for (const c of categories) {
            try {
                await db.query(`
                    INSERT INTO categories (id, name, parent_id, status, image_base64)
                    VALUES (?, ?, ?, ?, ?)
                    ON DUPLICATE KEY UPDATE
                        name = VALUES(name),
                        parent_id = VALUES(parent_id),
                        status = VALUES(status),
                        image_base64 = COALESCE(VALUES(image_base64), categories.image_base64)
                `, [c.id, c.name, c.parentId || c.parent_id || null, c.status || 'active', c.imageBase64 || c.image_base64 || null]);
            } catch (cErr) {
                console.error('Error mirroring category:', cErr.message);
            }
        }
    }

    if (products && Array.isArray(products)) {
        const [firstCatRow] = await db.query("SELECT id FROM categories LIMIT 1");
        const fallbackCatId = firstCatRow ? firstCatRow.id : null;

        for (const p of products) {
            try {
                let catId = p.categoryId || p.category_id;
                if (!catId || catId === 0 || catId === '0') {
                    catId = fallbackCatId;
                }

                await db.query(`
                    INSERT INTO products (id, name, sinhala_name, description, category_id, price, cost, barcode, stock_qty, min_stock_level, is_short_eat, image_base64, status, item_type, tax, is_featured, caution, has_sizes, has_extras, has_addons, track_stock, is_happy_hour_eligible, ingredients, is_kot_item)
                    VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                    ON DUPLICATE KEY UPDATE
                        name = VALUES(name),
                        sinhala_name = VALUES(sinhala_name),
                        description = VALUES(description),
                        category_id = VALUES(category_id),
                        price = VALUES(price),
                        cost = VALUES(cost),
                        barcode = VALUES(barcode),
                        stock_qty = VALUES(stock_qty),
                        min_stock_level = VALUES(min_stock_level),
                        is_short_eat = VALUES(is_short_eat),
                        image_base64 = COALESCE(VALUES(image_base64), products.image_base64),
                        status = VALUES(status),
                        item_type = VALUES(item_type),
                        tax = VALUES(tax),
                        is_featured = VALUES(is_featured),
                        caution = VALUES(caution),
                        has_sizes = VALUES(has_sizes),
                        has_extras = VALUES(has_extras),
                        has_addons = VALUES(has_addons),
                        track_stock = VALUES(track_stock),
                        is_happy_hour_eligible = VALUES(is_happy_hour_eligible),
                        ingredients = VALUES(ingredients),
                        is_kot_item = VALUES(is_kot_item)
                `, [
                    p.id || null, p.name, p.sinhalaName || p.sinhala_name || null, p.description || null, catId, p.price, p.cost || 0.00, p.barcode || null, p.stockQty ?? p.stock_qty ?? 0, p.minStockLevel ?? p.min_stock_level ?? 10, (p.isShortEat || p.is_short_eat) ? 1 : 0, p.imageBase64 || p.image_base64 || null, p.status || 'active', p.itemType || p.item_type || 'Veg', p.tax || 0.00, (p.isFeatured || p.is_featured) ? 1 : 0, p.caution || null, (p.hasSizes || p.has_sizes) ? 1 : 0, (p.hasExtras || p.has_extras) ? 1 : 0, (p.hasAddons || p.has_addons) ? 1 : 0, (p.trackStock ?? p.track_stock ?? 1) ? 1 : 0, (p.isHappyHourEligible ?? p.is_happy_hour_eligible ?? 1) ? 1 : 0, p.ingredients ? (typeof p.ingredients === 'string' ? p.ingredients : JSON.stringify(p.ingredients)) : null, (p.isKotItem || p.is_kot_item) ? 1 : 0
                ]);
            } catch (pErr) {
                console.error('Error mirroring product:', pErr.message);
            }
        }
    }

    if (diningTables && Array.isArray(diningTables)) {
        for (const t of diningTables) {
            try {
                await db.query(`
                    INSERT INTO dining_tables (id, table_number, capacity, status, current_order_id, steward_name, active_status)
                    VALUES (?, ?, ?, ?, ?, ?, ?)
                    ON DUPLICATE KEY UPDATE
                        table_number = VALUES(table_number),
                        capacity = VALUES(capacity),
                        status = VALUES(status),
                        current_order_id = VALUES(current_order_id),
                        steward_name = VALUES(steward_name),
                        active_status = VALUES(active_status)
                `, [t.id, t.tableNumber || t.table_number, t.capacity || 4, t.status || 'empty', t.currentOrderId || t.current_order_id || null, t.stewardName || t.steward_name || null, t.activeStatus || t.active_status || 'active']);
            } catch (tErr) {
                console.error('Error mirroring dining table:', tErr.message);
            }
        }
    }

    if (customers && Array.isArray(customers)) {
        for (const c of customers) {
            try {
                const birthdayVal = formatMySqlDate(c.birthday);
                await db.query(`
                    INSERT INTO customers (id, name, phone, birthday, favorite_items, credit_limit, outstanding_balance, image_base64)
                    VALUES (?, ?, ?, ?, ?, ?, ?, ?)
                    ON DUPLICATE KEY UPDATE
                        name = VALUES(name),
                        phone = VALUES(phone),
                        birthday = VALUES(birthday),
                        favorite_items = VALUES(favorite_items),
                        credit_limit = VALUES(credit_limit),
                        outstanding_balance = VALUES(outstanding_balance),
                        image_base64 = VALUES(image_base64)
                `, [c.id, c.name, c.phone, birthdayVal, c.favoriteItems || c.favorite_items || null, c.creditLimit ?? c.credit_limit ?? 0.00, c.outstandingBalance ?? c.outstanding_balance ?? 0.00, c.imageBase64 || c.image_base64 || null]);
            } catch (custErr) {
                console.error('Error mirroring customer:', custErr.message);
            }
        }
    }

    if (users && Array.isArray(users)) {
        for (const u of users) {
            try {
                await db.query(`
                    INSERT INTO users (id, name, username, password_hash, role, status, image_base64, email, phone, branch, category_id)
                    VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                    ON DUPLICATE KEY UPDATE
                        name = VALUES(name),
                        username = VALUES(username),
                        role = VALUES(role),
                        status = VALUES(status),
                        image_base64 = VALUES(image_base64),
                        email = VALUES(email),
                        phone = VALUES(phone),
                        branch = VALUES(branch),
                        category_id = VALUES(category_id)
                `, [u.id, u.name, u.username, u.passwordHash || u.password_hash || '$2a$10$KYVVXoS7ntUm8jLTGL7HgOe4Ff/NPByXj0z9wcMS/UwY2ZVglw7Y6', u.role, u.status || 'active', u.imageBase64 || u.image_base64 || null, u.email || null, u.phone || null, u.branch || 'current', u.category_id || u.categoryId || null]);
            } catch (uErr) {
                console.error('Error mirroring user:', uErr.message);
            }
        }
    }

    if (ingredients && Array.isArray(ingredients)) {
        for (const i of ingredients) {
            try {
                await db.query(`
                    INSERT INTO ingredients (id, name, stock_qty, unit, min_stock_level, cost_per_unit)
                    VALUES (?, ?, ?, ?, ?, ?)
                    ON DUPLICATE KEY UPDATE
                        name = VALUES(name),
                        stock_qty = VALUES(stock_qty),
                        unit = VALUES(unit),
                        min_stock_level = VALUES(min_stock_level),
                        cost_per_unit = VALUES(cost_per_unit)
                `, [i.id, i.name, i.stock_qty ?? i.stockQty ?? 0.0, i.unit || 'kg', i.min_stock_level ?? i.minStockLevel ?? 0.0, i.cost_per_unit ?? i.costPerUnit ?? 0.0]);
            } catch (iErr) {
                console.error('Error mirroring ingredient:', iErr.message);
            }
        }
    }

    if (happyHours && Array.isArray(happyHours)) {
        for (const h of happyHours) {
            try {
                await db.query(`
                    INSERT INTO happy_hour_pricing (id, product_id, promo_price, start_time, end_time, days_of_week, name, category_id, status, image_base64)
                    VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                    ON DUPLICATE KEY UPDATE
                        promo_price = VALUES(promo_price),
                        start_time = VALUES(start_time),
                        end_time = VALUES(end_time),
                        days_of_week = VALUES(days_of_week),
                        name = VALUES(name),
                        category_id = VALUES(category_id),
                        status = VALUES(status),
                        image_base64 = VALUES(image_base64)
                `, [h.id, h.product_id || null, h.promo_price, h.start_time, h.end_time, h.days_of_week, h.name || null, h.category_id || null, h.status || 'active', h.image_base64 || h.imageBase64 || null]);
            } catch (hErr) {
                console.error('Error mirroring happy hour:', hErr.message);
            }
        }
    }

    if (offers && Array.isArray(offers)) {
        for (const o of offers) {
            try {
                await db.query(`
                    INSERT INTO offers (id, title, name, description, discount_percentage, code, start_date, end_date, image_base64, status)
                    VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                    ON DUPLICATE KEY UPDATE
                        title = VALUES(title),
                        name = VALUES(name),
                        description = VALUES(description),
                        discount_percentage = VALUES(discount_percentage),
                        code = VALUES(code),
                        start_date = VALUES(start_date),
                        end_date = VALUES(end_date),
                        image_base64 = VALUES(image_base64),
                        status = VALUES(status)
                `, [o.id, o.title || null, o.name || null, o.description || null, o.discount_percentage ?? o.discountPercentage ?? 0.00, o.code || null, formatMySqlDate(o.start_date ?? o.startDate), formatMySqlDate(o.end_date ?? o.endDate), o.image_base64 || null, o.status || 'active']);
            } catch (oErr) {
                console.error('Error mirroring offer:', oErr.message);
            }
        }
    }

    if (roles && Array.isArray(roles)) {
        for (const r of roles) {
            try {
                await db.query(`
                    INSERT INTO roles (id, name) VALUES (?, ?)
                    ON DUPLICATE KEY UPDATE name = VALUES(name)
                `, [r.id, r.name]);
            } catch (rErr) {
                console.error('Error mirroring role:', rErr.message);
            }
        }
    }

    if (rolePermissions && Array.isArray(rolePermissions)) {
        for (const rp of rolePermissions) {
            try {
                await db.query(`
                    INSERT INTO role_permissions (id, role_id, page, can_view, can_create, can_update, can_delete)
                    VALUES (?, ?, ?, ?, ?, ?, ?)
                    ON DUPLICATE KEY UPDATE
                        can_view = VALUES(can_view),
                        can_create = VALUES(can_create),
                        can_update = VALUES(can_update),
                        can_delete = VALUES(can_delete)
                `, [rp.id, rp.role_id || rp.roleId, rp.page, rp.can_view ? 1 : 0, rp.can_create ? 1 : 0, rp.can_update ? 1 : 0, rp.can_delete ? 1 : 0]);
            } catch (rpErr) {
                console.error('Error mirroring role permission:', rpErr.message);
            }
        }
    }

    if (suppliers && Array.isArray(suppliers)) {
        for (const s of suppliers) {
            try {
                await db.query(`
                    INSERT INTO suppliers (id, name, company, phone, email, address, outstanding_balance, delivery_cycle)
                    VALUES (?, ?, ?, ?, ?, ?, ?, ?)
                    ON DUPLICATE KEY UPDATE
                        name = VALUES(name),
                        company = VALUES(company),
                        phone = VALUES(phone),
                        email = VALUES(email),
                        address = VALUES(address),
                        outstanding_balance = VALUES(outstanding_balance),
                        delivery_cycle = VALUES(delivery_cycle)
                `, [s.id, s.name, s.company || null, s.phone || null, s.email || null, s.address || null, s.outstanding_balance ?? s.outstandingBalance ?? 0.00, s.delivery_cycle || s.deliveryCycle || 'Weekly']);
            } catch (sErr) {
                console.error('Error mirroring supplier:', sErr.message);
            }
        }
    }

    if (globalSettings && Array.isArray(globalSettings)) {
        for (const gs of globalSettings) {
            try {
                await db.query(`
                    INSERT INTO global_settings (setting_key, setting_value)
                    VALUES (?, ?)
                    ON DUPLICATE KEY UPDATE setting_value = VALUES(setting_value)
                `, [gs.setting_key || gs.settingKey, gs.setting_value || gs.settingValue]);
            } catch (gsErr) {
                console.error('Error mirroring global setting:', gsErr.message);
            }
        }
    }

    if (preOrders && Array.isArray(preOrders)) {
        for (const po of preOrders) {
            try {
                await db.query(`
                    INSERT INTO pre_orders (id, pre_order_number, customer_id, customer_name, customer_phone, received_date, status, subtotal, discount, total, advance_payment, balance_amount, is_notified)
                    VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                    ON DUPLICATE KEY UPDATE
                        customer_id = VALUES(customer_id),
                        customer_name = VALUES(customer_name),
                        customer_phone = VALUES(customer_phone),
                        received_date = VALUES(received_date),
                        status = VALUES(status),
                        subtotal = VALUES(subtotal),
                        discount = VALUES(discount),
                        total = VALUES(total),
                        advance_payment = VALUES(advance_payment),
                        balance_amount = VALUES(balance_amount),
                        is_notified = VALUES(is_notified)
                `, [po.id, po.pre_order_number || po.preOrderNumber, po.customer_id || po.customerId || null, po.customer_name || po.customerName, po.customer_phone || po.customerPhone, formatMySqlDateTime(po.received_date || po.receivedDate), po.status || 'pending', po.subtotal || 0, po.discount || 0, po.total || 0, po.advance_payment || po.advancePayment || 0, po.balance_amount || po.balanceAmount || 0, po.is_notified || po.isNotified ? 1 : 0]);
            } catch (poErr) {
                console.error('Error mirroring pre order:', poErr.message);
            }
        }
    }

    if (preOrderItems && Array.isArray(preOrderItems)) {
        for (const poi of preOrderItems) {
            try {
                await db.query(`
                    INSERT INTO pre_order_items (id, pre_order_id, product_id, product_name, quantity, price, notes)
                    VALUES (?, ?, ?, ?, ?, ?, ?)
                    ON DUPLICATE KEY UPDATE
                        product_name = VALUES(product_name),
                        quantity = VALUES(quantity),
                        price = VALUES(price),
                        notes = VALUES(notes)
                `, [poi.id, poi.pre_order_id || poi.preOrderId, poi.product_id || poi.productId, poi.product_name || poi.productName || null, poi.quantity || 1, poi.price || 0, poi.notes || null]);
            } catch (poiErr) {
                console.error('Error mirroring pre order item:', poiErr.message);
            }
        }
    }

    if (expenses && Array.isArray(expenses)) {
        for (const e of expenses) {
            try {
                await db.query(`
                    INSERT INTO expenses (id, title, amount, category, payment_source, recorded_by, expense_date)
                    VALUES (?, ?, ?, ?, ?, ?, ?)
                    ON DUPLICATE KEY UPDATE
                        title = VALUES(title),
                        amount = VALUES(amount),
                        category = VALUES(category),
                        payment_source = VALUES(payment_source),
                        recorded_by = VALUES(recorded_by),
                        expense_date = VALUES(expense_date)
                `, [e.id, e.title, e.amount, e.category, e.payment_source || e.paymentSource, e.recorded_by || e.recordedBy || 1, formatMySqlDate(e.expense_date || e.expenseDate)]);
            } catch (eErr) {
                console.error('Error mirroring expense:', eErr.message);
            }
        }
    }

    if (shifts && Array.isArray(shifts)) {
        for (const s of shifts) {
            try {
                await db.query(`
                    INSERT INTO shifts (id, user_id, start_time, end_time, opening_balance, closing_balance, actual_closing_balance, status)
                    VALUES (?, ?, ?, ?, ?, ?, ?, ?)
                    ON DUPLICATE KEY UPDATE
                        end_time = VALUES(end_time),
                        closing_balance = VALUES(closing_balance),
                        actual_closing_balance = VALUES(actual_closing_balance),
                        status = VALUES(status)
                `, [s.id, s.user_id || s.userId || 1, formatMySqlDateTime(s.start_time || s.startTime), formatMySqlDateTime(s.end_time || s.endTime), s.opening_balance || s.openingBalance || 0, s.closing_balance || s.closingBalance || 0, s.actual_closing_balance || s.actualClosingBalance || 0, s.status || 'open']);
            } catch (sErr) {
                console.error('Error mirroring shift:', sErr.message);
            }
        }
    }

    if (cashDrawerLogs && Array.isArray(cashDrawerLogs)) {
        for (const cdl of cashDrawerLogs) {
            try {
                await db.query(`
                    INSERT INTO cash_drawer_logs (id, shift_id, type, amount, reason)
                    VALUES (?, ?, ?, ?, ?)
                    ON DUPLICATE KEY UPDATE
                        shift_id = VALUES(shift_id),
                        type = VALUES(type),
                        amount = VALUES(amount),
                        reason = VALUES(reason)
                `, [cdl.id, cdl.shift_id || cdl.shiftId, cdl.type, cdl.amount, cdl.reason]);
            } catch (cdlErr) {
                console.error('Error mirroring cash drawer log:', cdlErr.message);
            }
        }
    }

    if (creditSettlements && Array.isArray(creditSettlements)) {
        for (const cs of creditSettlements) {
            try {
                await db.query(`
                    INSERT INTO credit_settlements (id, customer_id, amount, payment_method, date_paid, recorded_by)
                    VALUES (?, ?, ?, ?, ?, ?)
                    ON DUPLICATE KEY UPDATE
                        amount = VALUES(amount),
                        payment_method = VALUES(payment_method),
                        date_paid = VALUES(date_paid),
                        recorded_by = VALUES(recorded_by)
                `, [cs.id, cs.customer_id || cs.customerId, cs.amount, cs.payment_method || cs.paymentMethod, formatMySqlDateTime(cs.date_paid || cs.datePaid), cs.recorded_by || cs.recordedBy || 1]);
            } catch (csErr) {
                console.error('Error mirroring credit settlement:', csErr.message);
            }
        }
    }

    if (stockLogs && Array.isArray(stockLogs)) {
        for (const sl of stockLogs) {
            try {
                await db.query(`
                    INSERT INTO stock_logs (id, product_id, change_qty, type, reason, user_id)
                    VALUES (?, ?, ?, ?, ?, ?)
                    ON DUPLICATE KEY UPDATE
                        change_qty = VALUES(change_qty),
                        type = VALUES(type),
                        reason = VALUES(reason)
                `, [sl.id, sl.product_id || sl.productId, sl.change_qty || sl.changeQty, sl.type, sl.reason || null, sl.user_id || sl.userId || 1]);
            } catch (slErr) {
                console.error('Error mirroring stock log:', slErr.message);
            }
        }
    }

    if (ingredientStockLogs && Array.isArray(ingredientStockLogs)) {
        for (const isl of ingredientStockLogs) {
            try {
                await db.query(`
                    INSERT INTO ingredient_stock_logs (id, ingredient_id, change_qty, type, reason, user_id)
                    VALUES (?, ?, ?, ?, ?, ?)
                    ON DUPLICATE KEY UPDATE
                        change_qty = VALUES(change_qty),
                        type = VALUES(type),
                        reason = VALUES(reason)
                `, [isl.id, isl.ingredient_id || isl.ingredientId, isl.change_qty || isl.changeQty, isl.type, isl.reason || null, isl.user_id || isl.userId || 1]);
            } catch (islErr) {
                console.error('Error mirroring ingredient stock log:', islErr.message);
            }
        }
    }

    if (staffAdvances && Array.isArray(staffAdvances)) {
        for (const sa of staffAdvances) {
            try {
                await db.query(`
                    INSERT INTO staff_advances (id, user_id, amount, reason, advance_date, status, recorded_by)
                    VALUES (?, ?, ?, ?, ?, ?, ?)
                    ON DUPLICATE KEY UPDATE
                        amount = VALUES(amount),
                        reason = VALUES(reason),
                        advance_date = VALUES(advance_date),
                        status = VALUES(status)
                `, [sa.id, sa.user_id || sa.userId, sa.amount, sa.reason || null, formatMySqlDate(sa.advance_date || sa.advanceDate), sa.status || 'pending', sa.recorded_by || sa.recordedBy || null]);
            } catch (saErr) {
                console.error('Error mirroring staff advance:', saErr.message);
            }
        }
    }

    if (staffPayrollSettings && Array.isArray(staffPayrollSettings)) {
        for (const sps of staffPayrollSettings) {
            try {
                await db.query(`
                    INSERT INTO staff_payroll_settings (id, user_id, basic_salary, salary_type, ot_rate_per_hour, allowances, salary_due_day, monthly_salary, daily_salary, hourly_rate, ot_hourly_rate)
                    VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                    ON DUPLICATE KEY UPDATE
                        basic_salary = VALUES(basic_salary),
                        salary_type = VALUES(salary_type),
                        ot_rate_per_hour = VALUES(ot_rate_per_hour),
                        allowances = VALUES(allowances),
                        salary_due_day = VALUES(salary_due_day),
                        monthly_salary = VALUES(monthly_salary),
                        daily_salary = VALUES(daily_salary),
                        hourly_rate = VALUES(hourly_rate),
                        ot_hourly_rate = VALUES(ot_hourly_rate)
                `, [sps.id, sps.user_id || sps.userId, sps.basic_salary || sps.basicSalary || 0, sps.salary_type || sps.salaryType || 'monthly', sps.ot_rate_per_hour || sps.otRatePerHour || null, sps.allowances || 0, sps.salary_due_day || sps.salaryDueDay || 28, sps.monthly_salary || sps.monthlySalary || 0, sps.daily_salary || sps.dailySalary || 0, sps.hourly_rate || sps.hourlyRate || 0, sps.ot_hourly_rate || sps.otHourlyRate || 0]);
            } catch (spsErr) {
                console.error('Error mirroring staff payroll settings:', spsErr.message);
            }
        }
    }

    if (staffPayrolls && Array.isArray(staffPayrolls)) {
        for (const sp of staffPayrolls) {
            try {
                await db.query(`
                    INSERT INTO staff_payrolls (id, user_id, month_year, period_start, period_end, basic_salary, working_hours, ot_hours, ot_rate, ot_amount, tip_amount, bonuses_others, allowances, advance_deduction, advances_deducted, net_salary, payment_method, payment_status, status, paid_at, created_by)
                    VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                    ON DUPLICATE KEY UPDATE
                        net_salary = VALUES(net_salary),
                        payment_method = VALUES(payment_method),
                        payment_status = VALUES(payment_status),
                        status = VALUES(status)
                `, [sp.id, sp.user_id || sp.userId, sp.month_year || sp.monthYear || null, formatMySqlDate(sp.period_start || sp.periodStart), formatMySqlDate(sp.period_end || sp.periodEnd), sp.basic_salary || sp.basicSalary || 0, sp.working_hours || sp.workingHours || 0, sp.ot_hours || sp.otHours || 0, sp.ot_rate || sp.otRate || 0, sp.ot_amount || sp.otAmount || 0, sp.tip_amount || sp.tipAmount || 0, sp.bonuses_others || sp.bonusesOthers || 0, sp.allowances || 0, sp.advance_deduction || sp.advanceDeduction || 0, sp.advances_deducted || sp.advancesDeducted || 0, sp.net_salary || sp.netSalary || 0, sp.payment_method || sp.paymentMethod || 'cash', sp.payment_status || sp.paymentStatus || 'paid', sp.status || 'unpaid', formatMySqlDateTime(sp.paid_at || sp.paidAt), sp.created_by || sp.createdBy || null]);
            } catch (spErr) {
                console.error('Error mirroring staff payroll:', spErr.message);
            }
        }
    }

    if (staffShifts && Array.isArray(staffShifts)) {
        for (const ss of staffShifts) {
            try {
                await db.query(`
                    INSERT INTO staff_shifts (id, user_id, clock_in, clock_out, duration_minutes, hours_worked, status)
                    VALUES (?, ?, ?, ?, ?, ?, ?)
                    ON DUPLICATE KEY UPDATE
                        clock_out = VALUES(clock_out),
                        duration_minutes = VALUES(duration_minutes),
                        hours_worked = VALUES(hours_worked),
                        status = VALUES(status)
                `, [ss.id, ss.user_id || ss.userId, formatMySqlDateTime(ss.clock_in || ss.clockIn), formatMySqlDateTime(ss.clock_out || ss.clockOut), ss.duration_minutes || ss.durationMinutes || 0, ss.hours_worked || ss.hoursWorked || 0, ss.status || 'active']);
            } catch (ssErr) {
                console.error('Error mirroring staff shift:', ssErr.message);
            }
        }
    }

    if (supplierDeliveries && Array.isArray(supplierDeliveries)) {
        for (const sd of supplierDeliveries) {
            try {
                await db.query(`
                    INSERT INTO supplier_deliveries (id, supplier_id, invoice_number, item_name, quantity, unit, total_amount, delivery_date)
                    VALUES (?, ?, ?, ?, ?, ?, ?, ?)
                    ON DUPLICATE KEY UPDATE
                        invoice_number = VALUES(invoice_number),
                        item_name = VALUES(item_name),
                        quantity = VALUES(quantity),
                        unit = VALUES(unit),
                        total_amount = VALUES(total_amount),
                        delivery_date = VALUES(delivery_date)
                `, [sd.id, sd.supplier_id || sd.supplierId, sd.invoice_number || sd.invoiceNumber || null, sd.item_name || sd.itemName || null, sd.quantity || 0, sd.unit || 'kg', sd.total_amount || sd.totalAmount || 0, formatMySqlDate(sd.delivery_date || sd.deliveryDate)]);
            } catch (sdErr) {
                console.error('Error mirroring supplier delivery:', sdErr.message);
            }
        }
    }

    if (supplierPayments && Array.isArray(supplierPayments)) {
        for (const sp of supplierPayments) {
            try {
                await db.query(`
                    INSERT INTO supplier_payments (id, supplier_id, amount, payment_method, payment_source, remarks, payment_date)
                    VALUES (?, ?, ?, ?, ?, ?, ?)
                    ON DUPLICATE KEY UPDATE
                        amount = VALUES(amount),
                        payment_method = VALUES(payment_method),
                        payment_source = VALUES(payment_source),
                        remarks = VALUES(remarks),
                        payment_date = VALUES(payment_date)
                `, [sp.id, sp.supplier_id || sp.supplierId, sp.amount, sp.payment_method || sp.paymentMethod || 'cash', sp.payment_source || sp.paymentSource || 'drawer', sp.remarks || null, formatMySqlDate(sp.payment_date || sp.paymentDate)]);
            } catch (spErr) {
                console.error('Error mirroring supplier payment:', spErr.message);
            }
        }
    }

    if (userAddresses && Array.isArray(userAddresses)) {
        for (const ua of userAddresses) {
            try {
                await db.query(`
                    INSERT INTO user_addresses (id, user_id, customer_id, label, address_line, latitude, longitude)
                    VALUES (?, ?, ?, ?, ?, ?, ?)
                    ON DUPLICATE KEY UPDATE
                        label = VALUES(label),
                        address_line = VALUES(address_line),
                        latitude = VALUES(latitude),
                        longitude = VALUES(longitude)
                `, [ua.id, ua.user_id || ua.userId || null, ua.customer_id || ua.customerId || null, ua.label || 'Home', ua.address_line || ua.addressLine, ua.latitude || null, ua.longitude || null]);
            } catch (uaErr) {
                console.error('Error mirroring user address:', uaErr.message);
            }
        }
    }

    if (orders && Array.isArray(orders)) {
        for (const o of orders) {
            try {
                await db.query(`
                    INSERT INTO orders (id, order_number, table_id, order_type, delivery_platform, customer_id, steward_name, status, payment_status, payment_method, subtotal, discount, total, cashier_id, shift_id, kot_printed, ack_printed, card_tx_reference, barcode, received_amount, change_amount, created_at, sync_status)
                    VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, 'synced')
                    ON DUPLICATE KEY UPDATE
                        status = VALUES(status),
                        payment_status = VALUES(payment_status),
                        payment_method = VALUES(payment_method),
                        subtotal = VALUES(subtotal),
                        discount = VALUES(discount),
                        total = VALUES(total),
                        received_amount = VALUES(received_amount),
                        change_amount = VALUES(change_amount)
                `, [o.id, o.order_number || o.orderNumber, o.table_id || o.tableId || null, o.order_type || o.orderType || 'takeaway', o.delivery_platform || o.deliveryPlatform || null, o.customer_id || o.customerId || null, o.steward_name || o.stewardName || null, o.status || 'pending', o.payment_status || o.paymentStatus || 'unpaid', o.payment_method || o.paymentMethod || null, o.subtotal || 0, o.discount || 0, o.total || 0, o.cashier_id || o.cashierId || 1, o.shift_id || o.shiftId || 1, o.kot_printed || o.kotPrinted ? 1 : 0, o.ack_printed || o.ackPrinted ? 1 : 0, o.card_tx_reference || o.cardTxReference || null, o.barcode || o.order_number, o.received_amount || o.receivedAmount || 0, o.change_amount || o.changeAmount || 0, formatMySqlDateTime(o.created_at || o.createdAt)]);

                const items = o.items || o.order_items;
                if (items && Array.isArray(items)) {
                    for (const item of items) {
                        await db.query(`
                            INSERT INTO order_items (id, order_id, order_number, product_id, product_name, product_sinhala_name, quantity, price, notes, status, is_short_eat)
                            VALUES (?, (SELECT id FROM orders WHERE order_number = ?), ?, ?, ?, ?, ?, ?, ?, ?, ?)
                            ON DUPLICATE KEY UPDATE
                                quantity = VALUES(quantity),
                                price = VALUES(price),
                                status = VALUES(status)
                        `, [item.id || null, o.order_number || o.orderNumber, o.order_number || o.orderNumber, item.product_id || item.productId, item.product_name || item.productName || null, item.product_sinhala_name || item.productSinhalaName || null, item.quantity || 1, item.price || 0, item.notes || null, item.status || 'pending', item.is_short_eat || item.isShortEat ? 1 : 0]);
                    }
                }
            } catch (oErr) {
                console.error('Error mirroring order:', oErr.message);
            }
        }
    }
}

// Bulk catalog mirror endpoint to sync central server catalog to local MySQL database
app.post('/api/sync/mirror-catalog', async (req, res) => {
    try {
        await processCatalogMirror(req.body);
        res.json({ success: true, message: 'All persistent tables mirrored to Local MySQL database successfully' });
    } catch (err) {
        console.error('Error mirroring catalog to local MySQL:', err.message);
        res.status(500).json({ error: err.message });
    }
});

// Full data export endpoint for server-to-server bidirectional synchronization
app.get('/api/sync/export-all-data', async (req, res) => {
    try {
        const categories = await db.query('SELECT * FROM categories');
        const products = await db.query('SELECT * FROM products');
        const diningTables = await db.query('SELECT * FROM dining_tables');
        const customers = await db.query('SELECT * FROM customers');
        const users = await db.query('SELECT id, name, username, password_hash, role, status, image_base64, email, phone, branch, category_id FROM users');
        const ingredients = await db.query('SELECT * FROM ingredients');
        const happyHours = await db.query('SELECT * FROM happy_hour_pricing');
        const offers = await db.query('SELECT * FROM offers');
        const roles = await db.query('SELECT * FROM roles');
        const rolePermissions = await db.query('SELECT * FROM role_permissions');
        const suppliers = await db.query('SELECT * FROM suppliers');
        const globalSettings = await db.query('SELECT * FROM global_settings');
        const preOrders = await db.query('SELECT * FROM pre_orders');
        const preOrderItems = await db.query('SELECT * FROM pre_order_items');
        const expenses = await db.query('SELECT * FROM expenses');
        const shifts = await db.query('SELECT * FROM shifts');
        const cashDrawerLogs = await db.query('SELECT * FROM cash_drawer_logs');
        const creditSettlements = await db.query('SELECT * FROM credit_settlements');
        const stockLogs = await db.query('SELECT * FROM stock_logs');
        const ingredientStockLogs = await db.query('SELECT * FROM ingredient_stock_logs');
        const staffAdvances = await db.query('SELECT * FROM staff_advances');
        const staffPayrollSettings = await db.query('SELECT * FROM staff_payroll_settings');
        const staffPayrolls = await db.query('SELECT * FROM staff_payrolls');
        const staffShifts = await db.query('SELECT * FROM staff_shifts');
        const supplierDeliveries = await db.query('SELECT * FROM supplier_deliveries');
        const supplierPayments = await db.query('SELECT * FROM supplier_payments');
        const userAddresses = await db.query('SELECT * FROM user_addresses');
        const orders = await db.query('SELECT * FROM orders');
        const orderItems = await db.query('SELECT * FROM order_items');

        res.json({
            categories, products, diningTables, customers, users, ingredients,
            happyHours, offers, roles, rolePermissions, suppliers, globalSettings,
            preOrders, preOrderItems, expenses, shifts, cashDrawerLogs, creditSettlements,
            stockLogs, ingredientStockLogs, staffAdvances, staffPayrollSettings, staffPayrolls,
            staffShifts, supplierDeliveries, supplierPayments, userAddresses, orders, orderItems
        });
    } catch (err) {
        res.status(500).json({ error: err.message });
    }
});

// ----------------------------------------------------
// MASTER DATA SNAPSHOT (All persistent MySQL tables)
// ----------------------------------------------------
app.get('/api/master-data', authenticateToken, async (req, res) => {
    try {
        const categories = await db.query("SELECT * FROM categories WHERE status = 'active'");
        const products = await db.query("SELECT * FROM products");
        const activeHappyHours = await db.query("SELECT * FROM happy_hour_pricing WHERE status = 'active'");

        const currentTime = new Date();
        const currentDay = currentTime.getDay();
        const currentDayFormatted = currentDay === 0 ? 7 : currentDay;
        const timeString = currentTime.toTimeString().split(' ')[0];

        const productsWithPricing = products.map(p => {
            let activePrice = Number(p.price);
            let isHappyHour = false;
            const isEligible = p.is_happy_hour_eligible === undefined || p.is_happy_hour_eligible === null ? true : !!p.is_happy_hour_eligible;
            if (isEligible) {
                let hhp = activeHappyHours.find(h => h.product_id === p.id);
                if (!hhp && p.category_id) {
                    hhp = activeHappyHours.find(h => h.category_id === p.category_id && (!h.product_id || h.product_id === 0 || h.product_id === '0'));
                }
                if (hhp && hhp.start_time && hhp.end_time && hhp.days_of_week) {
                    const days = hhp.days_of_week.split(',').map(Number);
                    if (days.includes(currentDayFormatted) && timeString >= hhp.start_time && timeString <= hhp.end_time) {
                        if (hhp.product_id && hhp.product_id !== 0 && hhp.product_id !== '0') {
                            activePrice = Number(hhp.promo_price);
                        } else {
                            const discountPct = Number(hhp.promo_price);
                            activePrice = Number((Number(p.price) * (1 - discountPct / 100.0)).toFixed(2));
                        }
                        isHappyHour = true;
                    }
                }
            }
            return {
                id: p.id, name: p.name, sinhala_name: p.sinhala_name, description: p.description,
                category_id: p.category_id, price: Number(p.price), cost: Number(p.cost),
                active_price: activePrice, is_happy_hour: isHappyHour, barcode: p.barcode,
                stock_qty: p.stock_qty, min_stock_level: p.min_stock_level,
                is_short_eat: !!p.is_short_eat, image_base64: p.image_base64,
                status: p.status, item_type: p.item_type || 'Veg',
                tax: p.tax !== null ? Number(p.tax) : 0.00, is_featured: !!p.is_featured,
                caution: p.caution, has_sizes: !!p.has_sizes, has_extras: !!p.has_extras,
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

        const users = await db.query("SELECT id, name, username, role, email, phone, status, image_base64, category_id FROM users WHERE status = 'active'");
        const diningTables = await db.query("SELECT * FROM dining_tables");
        const shifts = await db.query("SELECT * FROM shifts ORDER BY start_time DESC LIMIT 10");
        const customers = await db.query("SELECT * FROM customers");
        const ingredients = await db.query("SELECT * FROM ingredients");
        const happyHours = await db.query("SELECT * FROM happy_hour_pricing");
        const offers = await db.query("SELECT * FROM offers");
        const roles = await db.query("SELECT * FROM roles");
        const rolePermissions = await db.query("SELECT * FROM role_permissions");
        const preOrders = await db.query("SELECT * FROM pre_orders ORDER BY created_at DESC LIMIT 50");
        const suppliers = await db.query("SELECT * FROM suppliers");
        const globalSettings = await db.query("SELECT * FROM global_settings");

        res.json({
            categories,
            products: productsWithPricing,
            users,
            dining_tables: diningTables,
            shifts,
            customers,
            ingredients,
            happy_hours: happyHours,
            offers,
            roles,
            role_permissions: rolePermissions,
            pre_orders: preOrders,
            suppliers,
            global_settings: globalSettings
        });
    } catch (err) {
        console.error('Error fetching master data:', err.message);
        res.status(500).json({ error: err.message });
    }
});



// ----------------------------------------------------
// AUTOMATIC MYSQL DB-TO-DB BACKGROUND SYNC & PURGE
// ----------------------------------------------------
const https = require('https');
const httpModule = require('http');
const { URL } = require('url');

function makeSyncRequest(urlStr, method, data, token) {
    return new Promise((resolve, reject) => {
        try {
            const parsedUrl = new URL(urlStr);
            const isHttps = parsedUrl.protocol === 'https:';
            const lib = isHttps ? https : httpModule;
            const payload = data ? JSON.stringify(data) : null;
            const options = {
                hostname: parsedUrl.hostname,
                port: parsedUrl.port || (isHttps ? 443 : 80),
                path: parsedUrl.pathname + parsedUrl.search,
                method: method,
                headers: {
                    'Content-Type': 'application/json',
                    ...(token ? { 'Authorization': `Bearer ${token}` } : {})
                },
                timeout: 60000
            };
            if (payload) {
                options.headers['Content-Length'] = Buffer.byteLength(payload);
            }
            const req = lib.request(options, (res) => {
                let body = '';
                res.setEncoding('utf8');
                res.on('data', chunk => body += chunk);
                res.on('end', () => {
                    if (res.statusCode >= 200 && res.statusCode < 300) {
                        try { resolve(JSON.parse(body)); } catch (_) { resolve(body); }
                    } else {
                        reject(new Error(`HTTP ${res.statusCode}: ${body}`));
                    }
                });
            });
            req.on('error', err => reject(err));
            req.on('timeout', () => { req.destroy(); reject(new Error('Request timed out')); });
            if (payload) req.write(payload);
            req.end();
        } catch (e) {
            reject(e);
        }
    });
}

async function triggerRemoteMirror(payload) {
    if (process.env.IS_REMOTE_SERVER === 'true') return;
    try {
        const remoteUrl = process.env.REMOTE_SERVER_URL || 'https://pos0001.perpova.dev';
        const systemToken = jwt.sign({ id: 1, username: 'system_autosync', role: 'admin' }, JWT_SECRET, { expiresIn: '1h' });
        await makeSyncRequest(`${remoteUrl}/api/sync/mirror-catalog`, 'POST', payload, systemToken);
    } catch (e) {
        console.error('[InstantSync] Remote mirror failed:', e.message);
    }
}

async function performDbToDbSync() {
    const remoteUrl = process.env.REMOTE_SERVER_URL || 'https://pos0001.perpova.dev';
    if (process.env.IS_REMOTE_SERVER === 'true') {
        return { success: true, synced_orders_count: 0, message: 'Running as remote server — no DB sync required' };
    }

    // Generate valid system admin token for authenticated server-to-server endpoints
    const systemToken = jwt.sign({ id: 1, username: 'system_autosync', role: 'admin' }, JWT_SECRET, { expiresIn: '1h' });

    let syncedOrdersCount = 0;
    // 1. Sync pending local MySQL Workbench orders to Remote Server DB
    const localOrders = await db.query('SELECT * FROM orders');
    if (localOrders.length > 0) {
        const ordersWithItems = [];
        for (const order of localOrders) {
            const items = await db.query('SELECT * FROM order_items WHERE order_id = ? OR order_number = ?', [order.id, order.order_number]);
            ordersWithItems.push({
                ...order,
                items
            });
        }

        try {
            const syncResult = await makeSyncRequest(`${remoteUrl}/api/sync`, 'POST', { offline_orders: ordersWithItems }, systemToken);
            if (syncResult && syncResult.synced_orders && Array.isArray(syncResult.synced_orders) && syncResult.synced_orders.length > 0) {
                syncedOrdersCount = syncResult.synced_orders.length;
                const placeholders = syncResult.synced_orders.map(() => '?').join(',');
                await db.query(`DELETE FROM order_items WHERE order_number IN (${placeholders})`, syncResult.synced_orders);
                await db.query(`DELETE FROM orders WHERE order_number IN (${placeholders})`, syncResult.synced_orders);
                console.log(`[AutoSync] Successfully pushed ${syncedOrdersCount} local orders to Remote Server & purged from Local MySQL Workbench DB ✓`);
                broadcast({ type: 'database_synchronized', source: 'db_to_db_sync' });
            }
        } catch (orderSyncErr) {
            console.error('[AutoSync] Order sync error to remote server:', orderSyncErr.message);
        }
    }

    // 2. PUSH: Sync local system tables to Remote Server DB
    try {
        const localProducts = await db.query('SELECT * FROM products');
        const localCategories = await db.query('SELECT * FROM categories');
        const localCustomers = await db.query('SELECT * FROM customers');
        const localUsers = await db.query("SELECT id, name, username, role, email, phone, status, image_base64, category_id FROM users");
        const localIngredients = await db.query('SELECT * FROM ingredients');
        const localHappyHours = await db.query('SELECT * FROM happy_hour_pricing');
        const localOffers = await db.query('SELECT * FROM offers');
        const localDiningTables = await db.query('SELECT * FROM dining_tables');
        const localRoles = await db.query('SELECT * FROM roles');
        const localRolePermissions = await db.query('SELECT * FROM role_permissions');
        const localSuppliers = await db.query('SELECT * FROM suppliers');
        const localGlobalSettings = await db.query('SELECT * FROM global_settings');
        const localPreOrders = await db.query('SELECT * FROM pre_orders');
        const localPreOrderItems = await db.query('SELECT * FROM pre_order_items');
        const localExpenses = await db.query('SELECT * FROM expenses');
        const localShifts = await db.query('SELECT * FROM shifts');
        const localCashDrawerLogs = await db.query('SELECT * FROM cash_drawer_logs');
        const localCreditSettlements = await db.query('SELECT * FROM credit_settlements');
        const localStockLogs = await db.query('SELECT * FROM stock_logs');
        const localIngredientStockLogs = await db.query('SELECT * FROM ingredient_stock_logs');
        const localStaffAdvances = await db.query('SELECT * FROM staff_advances');
        const localStaffPayrollSettings = await db.query('SELECT * FROM staff_payroll_settings');
        const localStaffPayrolls = await db.query('SELECT * FROM staff_payrolls');
        const localStaffShifts = await db.query('SELECT * FROM staff_shifts');
        const localSupplierDeliveries = await db.query('SELECT * FROM supplier_deliveries');
        const localSupplierPayments = await db.query('SELECT * FROM supplier_payments');
        const localUserAddresses = await db.query('SELECT * FROM user_addresses');

        await makeSyncRequest(`${remoteUrl}/api/sync/mirror-catalog`, 'POST', {
            categories: localCategories,
            products: localProducts,
            customers: localCustomers,
            users: localUsers,
            ingredients: localIngredients,
            happyHours: localHappyHours,
            offers: localOffers,
            diningTables: localDiningTables,
            roles: localRoles,
            rolePermissions: localRolePermissions,
            suppliers: localSuppliers,
            globalSettings: localGlobalSettings,
            preOrders: localPreOrders,
            preOrderItems: localPreOrderItems,
            expenses: localExpenses,
            shifts: localShifts,
            cashDrawerLogs: localCashDrawerLogs,
            creditSettlements: localCreditSettlements,
            stockLogs: localStockLogs,
            ingredientStockLogs: localIngredientStockLogs,
            staffAdvances: localStaffAdvances,
            staffPayrollSettings: localStaffPayrollSettings,
            staffPayrolls: localStaffPayrolls,
            staffShifts: localStaffShifts,
            supplierDeliveries: localSupplierDeliveries,
            supplierPayments: localSupplierPayments,
            userAddresses: localUserAddresses
        }, systemToken);
    } catch (pushErr) {
        console.error('[AutoSync] Catalog push error:', pushErr.message);
    }

    // 3. PULL: Sync Remote Server DB data into Localhost MySQL Workbench DB
    try {
        const remoteDump = await makeSyncRequest(`${remoteUrl}/api/sync/export-all-data`, 'GET', null, systemToken);
        if (remoteDump && typeof remoteDump === 'object') {
            await processCatalogMirror(remoteDump);
            console.log('[AutoSync] Successfully pulled and synchronized Remote Server DB into Localhost MySQL Workbench DB ✓');
        }
    } catch (pullErr) {
        console.error('[AutoSync] Remote pull error:', pullErr.message);
    }

    broadcast({ type: 'database_synchronized', source: 'db_to_db_sync' });

    return {
        success: true,
        synced_orders_count: syncedOrdersCount,
        message: 'Localhost MySQL Workbench database is fully synchronized bidirectionally with Remote Server DB.'
    };
}

// GET Local MySQL DB Sync Status
app.get('/api/sync/status', async (req, res) => {
    try {
        const orderRows = await db.query('SELECT COUNT(*) as cnt FROM orders');
        const localOrdersCount = orderRows[0]?.cnt || 0;
        const remoteUrl = process.env.REMOTE_SERVER_URL || 'https://pos0001.perpova.dev';

        res.json({
            local_orders_count: localOrdersCount,
            remote_url: remoteUrl,
            is_remote_server: process.env.IS_REMOTE_SERVER === 'true'
        });
    } catch (err) {
        res.status(500).json({ error: err.message });
    }
});

// POST Trigger Manual Local DB to Remote Server DB Sync
app.post('/api/sync/trigger-db-to-db', async (req, res) => {
    try {
        const result = await performDbToDbSync();
        res.json(result);
    } catch (err) {
        res.status(500).json({ error: err.message });
    }
});

// ----------------------------------------------------
// DINING TABLES ENDPOINTS
// ----------------------------------------------------

// GET /api/tables - Fetch all dining tables
app.get('/api/tables', async (req, res) => {
    try {
        const tables = await db.query('SELECT * FROM dining_tables ORDER BY id ASC');
        res.json(tables);
    } catch (err) {
        res.status(500).json({ error: err.message });
    }
});

// POST /api/tables - Create new table
app.post('/api/tables', async (req, res) => {
    const { table_number, capacity } = req.body;
    if (!table_number) {
        return res.status(400).json({ error: 'Table number is required' });
    }
    try {
        const result = await db.query(
            'INSERT INTO dining_tables (table_number, capacity, status, active_status) VALUES (?, ?, "empty", "active")',
            [table_number.trim(), capacity || 4]
        );
        const [newTable] = await db.query('SELECT * FROM dining_tables WHERE id = ?', [result.insertId]);
        broadcast({ type: 'table_created', data: newTable });
        broadcast({ type: 'database_synchronized' });
        res.json(newTable);
    } catch (err) {
        res.status(500).json({ error: err.message });
    }
});

// PUT /api/tables/:id - Update table status or details
app.put('/api/tables/:id', async (req, res) => {
    const { id } = req.params;
    const { table_number, capacity, status, steward_name, active_status } = req.body;
    try {
        const [existing] = await db.query('SELECT * FROM dining_tables WHERE id = ?', [id]);
        if (!existing) return res.status(404).json({ error: 'Table not found' });

        const updatedNumber = table_number !== undefined ? table_number : existing.table_number;
        const updatedCapacity = capacity !== undefined ? capacity : existing.capacity;
        const updatedStatus = status !== undefined ? status : existing.status;
        const updatedSteward = steward_name !== undefined ? steward_name : existing.steward_name;
        const updatedActive = active_status !== undefined ? active_status : existing.active_status;

        await db.query(
            'UPDATE dining_tables SET table_number = ?, capacity = ?, status = ?, steward_name = ?, active_status = ? WHERE id = ?',
            [updatedNumber, updatedCapacity, updatedStatus, updatedSteward, updatedActive, id]
        );
        const [table] = await db.query('SELECT * FROM dining_tables WHERE id = ?', [id]);
        broadcast({ type: 'table_status_changed', data: { tableId: id, status: updatedStatus, table } });
        broadcast({ type: 'database_synchronized' });
        res.json(table);
    } catch (err) {
        res.status(500).json({ error: err.message });
    }
});

// DELETE /api/tables/:id - Soft delete table
app.delete('/api/tables/:id', async (req, res) => {
    const { id } = req.params;
    try {
        await db.query("UPDATE dining_tables SET active_status = 'inactive' WHERE id = ?", [id]);
        broadcast({ type: 'table_deleted', data: { id } });
        broadcast({ type: 'database_synchronized' });
        res.json({ success: true, message: 'Table marked as inactive' });
    } catch (err) {
        res.status(500).json({ error: err.message });
    }
});

// POST /api/tables/ping-seated - Mark table seated when QR code is scanned
app.post('/api/tables/ping-seated', async (req, res) => {
    const { table_number } = req.body;
    if (!table_number) return res.status(400).json({ error: 'table_number is required' });
    try {
        let [table] = await db.query('SELECT * FROM dining_tables WHERE table_number = ?', [table_number]);
        if (!table) {
            const insRes = await db.query('INSERT INTO dining_tables (table_number, capacity, status) VALUES (?, 4, "seated")', [table_number]);
            [table] = await db.query('SELECT * FROM dining_tables WHERE id = ?', [insRes.insertId]);
        } else {
            await db.query('UPDATE dining_tables SET status = "seated" WHERE id = ?', [table.id]);
        }
        broadcast({ type: 'table_status_changed', data: { tableId: table.id, status: 'seated' } });
        broadcast({ type: 'database_synchronized' });
        res.json({ success: true, table });
    } catch (err) {
        res.status(500).json({ error: err.message });
    }
});

// POST /api/customer-orders - Place a dine-in order from QR Code Web App
app.post('/api/customer-orders', async (req, res) => {
    const { table_number, customer_name, items, notes } = req.body;

    if (!table_number) {
        return res.status(400).json({ error: 'Table number is required' });
    }
    if (!items || !Array.isArray(items) || items.length === 0) {
        return res.status(400).json({ error: 'Order must contain at least one item' });
    }

    try {
        // 1. Find table by table_number or create if not exists
        let [table] = await db.query('SELECT * FROM dining_tables WHERE table_number = ?', [table_number]);
        if (!table) {
            const insRes = await db.query('INSERT INTO dining_tables (table_number, capacity, status) VALUES (?, 4, "seated")', [table_number]);
            [table] = await db.query('SELECT * FROM dining_tables WHERE id = ?', [insRes.insertId]);
        }

        // 2. Fetch products to compute accurate pricing
        const productIds = items.map(i => Number(i.product_id)).filter(id => !isNaN(id) && id > 0);
        let productsList = [];
        if (productIds.length > 0) {
            const placeholders = productIds.map(() => '?').join(',');
            productsList = await db.query(`SELECT * FROM products WHERE id IN (${placeholders})`, productIds);
        }
        const productMap = {};
        productsList.forEach(p => { productMap[p.id] = p; });

        let subtotal = 0;
        const processedItems = [];

        for (const item of items) {
            const p = productMap[item.product_id];
            if (!p) continue;
            const price = Number(p.price);
            const qty = Number(item.quantity || 1);
            const itemTotal = price * qty;
            subtotal += itemTotal;
            processedItems.push({
                product_id: p.id,
                product_name: p.name,
                product_sinhala_name: p.sinhala_name || null,
                quantity: qty,
                price: price,
                notes: item.notes || null,
                is_short_eat: !!p.is_short_eat,
                status: 'pending'
            });
        }

        if (processedItems.length === 0) {
            return res.status(400).json({ error: 'None of the submitted products were found in catalog' });
        }

        // 3. Find open shift or default shift 1
        const openShifts = await db.query("SELECT id FROM shifts WHERE status = 'open' ORDER BY id DESC LIMIT 1");
        const shiftId = openShifts.length > 0 ? openShifts[0].id : 1;

        // 4. Find cashier user id (or user 1 default)
        const cashiers = await db.query("SELECT id FROM users WHERE role = 'cashier' OR role = 'admin' LIMIT 1");
        const cashierId = cashiers.length > 0 ? cashiers[0].id : 1;

        // 5. Generate Order Number
        const orderNumber = `ORD-QR-${Date.now().toString().slice(-6)}`;
        const total = subtotal;

        // 6. Insert Order
        const orderResult = await db.query(`
            INSERT INTO orders (
                order_number, table_id, order_type, customer_id, steward_name,
                status, payment_status, subtotal, discount, total,
                cashier_id, shift_id, sync_status
            ) VALUES (?, ?, 'dine_in', NULL, ?, 'pending', 'unpaid', ?, 0.00, ?, ?, ?, 'synced')
        `, [
            orderNumber, table.id, customer_name || `QR Customer (${table_number})`,
            subtotal, total, cashierId, shiftId
        ]);

        const orderId = orderResult.insertId;

        // 7. Insert Order Items
        for (const item of processedItems) {
            await db.query(`
                INSERT INTO order_items (
                    order_id, order_number, product_id, product_name, product_sinhala_name,
                    quantity, price, notes, status, is_short_eat
                ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            `, [
                orderId, orderNumber, item.product_id, item.product_name, item.product_sinhala_name,
                item.quantity, item.price, item.notes, item.status, item.is_short_eat ? 1 : 0
            ]);
        }

        // 8. Update Table status to 'seated'
        await db.query('UPDATE dining_tables SET status = "seated", current_order_id = ? WHERE id = ?', [orderId, table.id]);

        // 9. Broadcast real-time WebSocket notifications to POS app, Kitchen (KDS), and Admin App
        const broadcastOrderData = {
            id: orderId,
            orderNumber,
            tableId: table.id,
            orderType: 'dine_in',
            tableName: table_number,
            status: 'pending',
            paymentStatus: 'unpaid',
            subtotal,
            total,
            items: processedItems,
            createdAt: new Date()
        };

        broadcast({ type: 'order_created', data: broadcastOrderData });
        broadcast({ type: 'table_status_changed', data: { tableId: table.id, status: 'seated' } });
        broadcast({ type: 'kot_trigger_voice', data: { orderId, orderType: 'dine_in', tableName: table_number, items: processedItems } });
        broadcast({ type: 'new_notification', data: { title: 'New QR Table Order', message: `Customer placed order for ${table_number} (${orderNumber})`, type: 'order' } });
        broadcast({ type: 'database_synchronized' });

        res.json({
            success: true,
            order_id: orderId,
            order_number: orderNumber,
            table_number,
            total,
            message: 'Order sent successfully to Kitchen & POS!'
        });
    } catch (err) {
        console.error('Error creating customer QR order:', err);
        res.status(500).json({ error: err.message });
    }
});

// ----------------------------------------------------
// CUSTOMER REVIEWS & RATINGS ENDPOINTS
// ----------------------------------------------------

// POST /api/customer-reviews - Submit feedback/rating from customer web app
app.post('/api/customer-reviews', async (req, res) => {
    const { table_number, customer_name, rating, comment } = req.body;
    try {
        const result = await db.query(
            'INSERT INTO customer_reviews (table_number, customer_name, rating, comment) VALUES (?, ?, ?, ?)',
            [table_number || 'General', customer_name || 'Anonymous Customer', rating || 5, comment || '']
        );
        const [review] = await db.query('SELECT * FROM customer_reviews WHERE id = ?', [result.insertId]);
        broadcast({ type: 'new_customer_review', data: review });
        res.json({ success: true, review });
    } catch (err) {
        res.status(500).json({ error: err.message });
    }
});

// GET /api/customer-reviews - Fetch all customer reviews
app.get('/api/customer-reviews', async (req, res) => {
    try {
        const reviews = await db.query('SELECT * FROM customer_reviews ORDER BY created_at DESC LIMIT 100');
        res.json(reviews);
    } catch (err) {
        res.status(500).json({ error: err.message });
    }
});

// Start Server and Init Database
server.listen(PORT, async () => {
    console.log(`Hotel POS Server is running on port ${PORT}`);
    await db.initializeDatabase();
});
