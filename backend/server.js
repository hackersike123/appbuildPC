const http = require('node:http');
const crypto = require('node:crypto');
const fs = require('node:fs');
const path = require('node:path');

const PORT = Number(process.env.PORT || 3000);
const DB_FILE = process.env.PCBUILD_DB_FILE || path.join(__dirname, 'data.json');
const tokens = new Map();
const money = (value) => Math.round(Number(value) || 0);
const id = (prefix) => `${prefix}_${crypto.randomBytes(8).toString('hex')}`;

const seed = {
  users: [],
  areas: [
    { id: 'hcm', name: 'TP. Hồ Chí Minh' },
    { id: 'hanoi', name: 'Hà Nội' },
    { id: 'danang', name: 'Đà Nẵng' }
  ],
  products: [
    { id: 'cpu-7600', type: 'CPU', name: 'AMD Ryzen 5 7600', price: 4890000, power: 65, socket: 'AM5' },
    { id: 'mb-b650m', type: 'MAINBOARD', name: 'MSI B650M Gaming Plus', price: 3690000, socket: 'AM5', ram: 'DDR5', form: 'mATX' },
    { id: 'gpu-4060', type: 'GPU', name: 'ASUS Dual GeForce RTX 4060 OC 8GB', price: 8690000, power: 115, length: 227 },
    { id: 'ram-32-ddr5', type: 'RAM', name: 'Kingston Fury 32GB DDR5', price: 2150000, ram: 'DDR5' },
    { id: 'ssd-sn770', type: 'SSD', name: 'WD Black SN770 1TB', price: 1890000 },
    { id: 'psu-650', type: 'PSU', name: 'Corsair RM650e 650W', price: 1790000, watts: 650 },
    { id: 'case-air-100', type: 'CASE', name: 'Montech Air 100', price: 1190000, form: 'mATX', gpuLength: 330 },
    { id: 'cooler-ak400', type: 'TẢN NHIỆT', name: 'DeepCool AK400', price: 790000, socket: 'AM5' }
  ],
  builds: [], alerts: [], conversations: [], scans: [], notifications: [], market: {}
};

function loadDb() {
  try { return JSON.parse(fs.readFileSync(DB_FILE, 'utf8')); } catch { return structuredClone(seed); }
}
let db = loadDb();
db.notifications ??= [];
db.market ??= {};
for (const area of db.areas) {
  db.market[area.id] ??= {};
  for (const item of db.products) {
    db.market[area.id][item.id] ??= {
      current: Math.round(item.price * ({ hcm: 1, hanoi: 1.024, danang: 1.011 }[area.id] || 1)),
      previous: Math.round(item.price * ({ hcm: 0.982, hanoi: 1.006, danang: 0.997 }[area.id] || 0.982))
    };
  }
}
function saveDb() { fs.writeFileSync(DB_FILE, JSON.stringify(db, null, 2)); }
function send(res, status, body) {
  res.writeHead(status, {
    'content-type': 'application/json; charset=utf-8',
    'access-control-allow-origin': '*',
    'access-control-allow-methods': 'GET,POST,PUT,DELETE,OPTIONS',
    'access-control-allow-headers': 'content-type,authorization'
  });
  res.end(JSON.stringify(body));
}
function readBody(req) {
  return new Promise((resolve, reject) => {
    let raw = '';
    req.on('data', (chunk) => { raw += chunk; if (raw.length > 1_000_000) reject(new Error('Payload too large')); });
    req.on('end', () => { try { resolve(raw ? JSON.parse(raw) : {}); } catch { reject(new Error('Invalid JSON')); } });
    req.on('error', reject);
  });
}
function auth(req) {
  const token = (req.headers.authorization || '').replace('Bearer ', '');
  const userId = tokens.get(token);
  return db.users.find((user) => user.id === userId);
}
function requireAuth(req, res) {
  const user = auth(req);
  if (!user) send(res, 401, { error: 'UNAUTHORIZED', message: 'Bearer token is required.' });
  return user;
}
function publicUser(user) {
  const { passwordHash, ...safe } = user;
  return safe;
}
function product(idValue) { return db.products.find((item) => item.id === idValue); }
function buildView(build) {
  const components = Object.fromEntries(Object.entries(build.components).map(([type, productId]) => [type, product(productId)]));
  const total = Object.values(components).filter(Boolean).reduce((sum, item) => sum + item.price, 0);
  return { ...build, components, totalPrice: total, completion: Math.round(Object.values(components).filter(Boolean).length / 8 * 100) };
}
function compatibility(components) {
  const items = Object.values(components).map(product);
  const issues = [];
  const cpu = items.find((item) => item?.type === 'CPU');
  const board = items.find((item) => item?.type === 'MAINBOARD');
  const ram = items.find((item) => item?.type === 'RAM');
  const psu = items.find((item) => item?.type === 'PSU');
  const gpu = items.find((item) => item?.type === 'GPU');
  const box = items.find((item) => item?.type === 'CASE');
  if (cpu && board && cpu.socket !== board.socket) issues.push({ code: 'SOCKET', severity: 'error', message: 'CPU và mainboard khác socket.' });
  if (board && ram && board.ram !== ram.ram) issues.push({ code: 'RAM', severity: 'error', message: 'Mainboard không hỗ trợ loại RAM này.' });
  if (psu && gpu && psu.watts < gpu.power + 400) issues.push({ code: 'PSU', severity: 'warning', message: 'Nguồn có thể không đủ công suất khuyến nghị.' });
  if (gpu && box && gpu.length > box.gpuLength) issues.push({ code: 'CASE_SIZE', severity: 'error', message: 'GPU dài hơn khoảng trống của case.' });
  return { status: issues.some((item) => item.severity === 'error') ? 'incompatible' : issues.length ? 'warning' : 'compatible', score: Math.max(0, 100 - issues.length * 20), issues };
}

async function route(req, res) {
  const url = new URL(req.url, `http://${req.headers.host || 'localhost'}`);
  const parts = url.pathname.split('/').filter(Boolean);
  const method = req.method;
  if (method === 'OPTIONS') return send(res, 204, {});
  if (method === 'GET' && url.pathname === '/health') return send(res, 200, { ok: true, service: 'pcbuild-local-api' });

  let body;
  try { if (method !== 'GET' && method !== 'DELETE') body = await readBody(req); } catch (error) { return send(res, 400, { error: 'BAD_REQUEST', message: error.message }); }

  if (method === 'POST' && parts.join('/') === 'api/v1/auth/register') {
    const email = String(body.email || '').trim().toLowerCase();
    const name = String(body.name || '').trim();
    const password = String(body.password || '');
    if (!email || !email.includes('@') || name.length < 2 || password.length < 8) {
      return send(res, 422, { error: 'INVALID_ACCOUNT', message: 'Vui lòng nhập họ tên, email hợp lệ và mật khẩu tối thiểu 8 ký tự.' });
    }
    if (db.users.some((user) => user.email.toLowerCase() === email)) {
      return send(res, 409, { error: 'EMAIL_EXISTS', message: 'Email này đã được đăng ký.' });
    }
    const user = { id: id('user'), name, email, areaId: body.areaId || 'hcm', passwordHash: crypto.createHash('sha256').update(password).digest('hex') };
    db.users.push(user);
    db.notifications.push({
      id: id('notification'), userId: user.id,
      title: 'Chào mừng bạn đến PCBUILD LOCAL',
      message: 'Tài khoản đã sẵn sàng. Hãy bắt đầu tạo cấu hình PC đầu tiên.',
      read: false, createdAt: new Date().toISOString()
    });
    saveDb(); return send(res, 201, { user: publicUser(user) });
  }
  if (method === 'POST' && parts.join('/') === 'api/v1/auth/login') {
    const email = String(body.email || '').trim().toLowerCase();
    const hash = crypto.createHash('sha256').update(body.password || '').digest('hex');
    const user = db.users.find((item) => item.email.toLowerCase() === email && item.passwordHash === hash);
    if (!user) return send(res, 401, { error: 'INVALID_CREDENTIALS', message: 'Email hoặc mật khẩu không đúng. Nếu chưa có tài khoản, hãy đăng ký trước.' });
    const token = crypto.randomBytes(32).toString('hex'); tokens.set(token, user.id); return send(res, 200, { accessToken: token, user: publicUser(user) });
  }
  if (method === 'POST' && parts.join('/') === 'api/v1/auth/forgot-password') {
    if (!String(body.email || '').includes('@')) return send(res, 422, { error: 'INVALID_EMAIL', message: 'Email không hợp lệ.' });
    return send(res, 202, { accepted: true, message: 'Nếu email tồn tại, hướng dẫn khôi phục đã được gửi.' });
  }
  if (method === 'GET' && parts.join('/') === 'api/v1/areas') return send(res, 200, db.areas);
  if (method === 'POST' && parts.join('/') === 'api/v1/location/resolve') {
    const area = db.areas.find((item) => item.id === body.areaId) || db.areas[0];
    return send(res, 200, {
      area,
      source: body.areaId ? 'manual' : 'gps-demo',
      coordinates: { lat: Number(body.lat) || 10.8231, lng: Number(body.lng) || 106.6297 }
    });
  }
  if (method === 'GET' && parts.join('/') === 'api/v1/market/summary') {
    const areaId = url.searchParams.get('areaId') || 'hcm';
    const area = db.areas.find((item) => item.id === areaId) || db.areas[0];
    return send(res, 200, {
      area,
      updatedAt: new Date().toISOString(),
      source: 'backend-market-catalog',
      items: ['gpu-4060', 'cpu-7600', 'ram-32-ddr5'].map((productId) => {
        const item = product(productId);
        const prices = db.market[area.id][productId];
        const trend = Number((((prices.current - prices.previous) / prices.previous) * 100).toFixed(2));
        return { productId, name: item.name, price: prices.current, previousPrice: prices.previous, trend };
      })
    });
  }
  if (method === 'GET' && parts.join('/') === 'api/v1/products') return send(res, 200, db.products.filter((item) => !url.searchParams.get('type') || item.type === url.searchParams.get('type')));
  if (method === 'GET' && parts[0] === 'api' && parts[1] === 'v1' && parts[2] === 'products' && parts[3]) {
    const item = product(parts[3]); return item ? send(res, 200, item) : send(res, 404, { error: 'PRODUCT_NOT_FOUND' });
  }
  if (method === 'GET' && parts[0] === 'api' && parts[1] === 'v1' && parts[2] === 'prices') {
    const item = product(url.searchParams.get('productId')); if (!item) return send(res, 404, { error: 'PRODUCT_NOT_FOUND' });
    const areaId = url.searchParams.get('areaId') || 'hcm';
    const prices = db.market[areaId]?.[item.id] || { current: item.price, previous: item.price };
    const changePercent = Number((((prices.current - prices.previous) / prices.previous) * 100).toFixed(2));
    return send(res, 200, {
      productId: item.id, areaId, price: prices.current, previousPrice: prices.previous,
      changePercent, updatedAt: new Date().toISOString(),
      history: [{ date: new Date().toISOString().slice(0, 10), price: prices.current }]
    });
  }

  const user = requireAuth(req, res); if (!user) return;
  if (method === 'GET' && parts.join('/') === 'api/v1/auth/me') return send(res, 200, publicUser(user));
  if (method === 'GET' && parts.join('/') === 'api/v1/notifications') {
    return send(res, 200, db.notifications.filter((item) => item.userId === user.id).sort((a, b) => b.createdAt.localeCompare(a.createdAt)));
  }
  if (method === 'POST' && parts.join('/') === 'api/v1/notifications/read') {
    db.notifications.filter((item) => item.userId === user.id).forEach((item) => { item.read = true; });
    saveDb(); return send(res, 200, { ok: true });
  }
  if (method === 'POST' && parts.join('/') === 'api/v1/builds') {
    const build = { id: id('build'), userId: user.id, name: body.name || 'Build mới', budget: money(body.budget), areaId: body.areaId || user.areaId, components: {} };
    db.builds.push(build); saveDb(); return send(res, 201, buildView(build));
  }
  if (method === 'GET' && parts.join('/') === 'api/v1/builds') return send(res, 200, db.builds.filter((item) => item.userId === user.id).map(buildView));
  if (parts[0] === 'api' && parts[1] === 'v1' && parts[2] === 'builds' && parts[3]) {
    const build = db.builds.find((item) => item.id === parts[3] && item.userId === user.id);
    if (!build) return send(res, 404, { error: 'BUILD_NOT_FOUND' });
    if (method === 'GET') return send(res, 200, buildView(build));
    if (method === 'DELETE') { db.builds = db.builds.filter((item) => item !== build); saveDb(); return send(res, 204, {}); }
    if (method === 'PUT' && parts[4] === 'components' && parts[5]) {
      if (!product(body.productId) || product(body.productId).type !== parts[5]) return send(res, 422, { error: 'INVALID_COMPONENT' });
      build.components[parts[5]] = body.productId; saveDb(); return send(res, 200, buildView(build));
    }
    if (method === 'POST' && parts[4] === 'check') return send(res, 200, compatibility(build.components));
  }
  if (method === 'POST' && parts.join('/') === 'api/v1/compatibility/check') return send(res, 200, compatibility(body.components || {}));
  if (method === 'POST' && parts.join('/') === 'api/v1/scans') {
    const scan = { id: id('scan'), userId: user.id, status: 'completed', detectedProductId: 'gpu-4060', confidence: 0.96, createdAt: new Date().toISOString() };
    db.scans.push(scan); saveDb(); return send(res, 201, { ...scan, product: product(scan.detectedProductId) });
  }
  if (method === 'POST' && parts.join('/') === 'api/v1/conversations') {
    const conversation = { id: id('conversation'), userId: user.id, messages: [] }; db.conversations.push(conversation); saveDb(); return send(res, 201, conversation);
  }
  if (method === 'POST' && parts[0] === 'api' && parts[1] === 'v1' && parts[2] === 'conversations' && parts[4] === 'messages') {
    const conversation = db.conversations.find((item) => item.id === parts[3] && item.userId === user.id);
    if (!conversation) return send(res, 404, { error: 'CONVERSATION_NOT_FOUND' });
    const answer = `BuildMate: ${body.message || 'Hãy nhập câu hỏi.'} — đây là tư vấn demo dựa trên catalog hiện tại.`;
    conversation.messages.push({ role: 'user', content: body.message, createdAt: new Date().toISOString() }, { role: 'assistant', content: answer, createdAt: new Date().toISOString() });
    saveDb(); return send(res, 200, { answer, messages: conversation.messages });
  }
  if (method === 'POST' && parts.join('/') === 'api/v1/price-alerts') {
    const alert = { id: id('alert'), userId: user.id, productId: body.productId, targetPrice: money(body.targetPrice), areaId: body.areaId || user.areaId }; db.alerts.push(alert); saveDb(); return send(res, 201, alert);
  }
  if (method === 'GET' && parts.join('/') === 'api/v1/price-alerts') return send(res, 200, db.alerts.filter((item) => item.userId === user.id));
  return send(res, 404, { error: 'NOT_FOUND' });
}

const server = http.createServer((req, res) => route(req, res).catch((error) => send(res, 500, { error: 'INTERNAL_ERROR', message: error.message })));
if (require.main === module) server.listen(PORT, '0.0.0.0', () => console.log(`PCBUILD API listening on port ${PORT}`));
module.exports = { server, db, route };
