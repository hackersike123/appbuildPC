require('dotenv').config();

const http = require('node:http');
const crypto = require('node:crypto');
const fs = require('node:fs');
const path = require('node:path');
const nodemailer = require('nodemailer');
const { createSqlStoreFromEnv } = require('./sql-store');

const PORT = Number(process.env.PORT || 3000);
const DB_FILE = process.env.PCBUILD_DB_FILE || path.join(__dirname, 'data.json');
const JWT_SECRET = process.env.JWT_SECRET || 'pcbuild-local-development-secret-change-me';
const JWT_EXPIRES_IN = Number(process.env.JWT_EXPIRES_IN || 3600);
const API_ISSUER = 'pcbuild-local-api';
const API_AUDIENCE = 'pcbuild-local-app';
const sqlStore = createSqlStoreFromEnv();
const money = (value) => Math.round(Number(value) || 0);
const id = (prefix) => `${prefix}_${crypto.randomBytes(8).toString('hex')}`;
function base64Url(value) {
  return Buffer.from(value).toString('base64').replace(/\+/g, '-').replace(/\//g, '_').replace(/=+$/, '');
}
function createAccessToken(user) {
  const now = Math.floor(Date.now() / 1000);
  const payload = { sub: user.id, email: user.email, iss: API_ISSUER, aud: API_AUDIENCE, iat: now, exp: now + JWT_EXPIRES_IN };
  const header = base64Url(JSON.stringify({ alg: 'HS256', typ: 'JWT' }));
  const body = base64Url(JSON.stringify(payload));
  const input = `${header}.${body}`;
  const signature = crypto.createHmac('sha256', JWT_SECRET).update(input).digest();
  return `${input}.${base64Url(signature)}`;
}
function verifyAccessToken(token) {
  const parts = String(token || '').split('.');
  if (parts.length !== 3) return null;
  const input = `${parts[0]}.${parts[1]}`;
  const expected = crypto.createHmac('sha256', JWT_SECRET).update(input).digest();
  const received = Buffer.from(parts[2].replace(/-/g, '+').replace(/_/g, '/'), 'base64');
  if (received.length !== expected.length || !crypto.timingSafeEqual(received, expected)) return null;
  try {
    const payload = JSON.parse(Buffer.from(parts[1], 'base64url').toString('utf8'));
    if (payload.iss !== API_ISSUER || payload.aud !== API_AUDIENCE || Number(payload.exp) <= Math.floor(Date.now() / 1000)) return null;
    return payload;
  } catch {
    return null;
  }
}

const seed = {
  users: [],
  areas: [
    { id: 'hcm', name: 'TP. Hồ Chí Minh' },
    { id: 'hanoi', name: 'Hà Nội' },
    { id: 'danang', name: 'Đà Nẵng' }
  ],
  products: [
    { id: 'cpu-7600', type: 'CPU', name: 'AMD Ryzen 5 7600', price: 4890000, power: 65, socket: 'AM5' },
    { id: 'cpu-7800x3d', type: 'CPU', name: 'AMD Ryzen 7 7800X3D', price: 8990000, power: 120, socket: 'AM5' },
    { id: 'mb-b650m', type: 'MAINBOARD', name: 'MSI B650M Gaming Plus', price: 3690000, socket: 'AM5', ram: 'DDR5', form: 'mATX' },
    { id: 'mb-b650-aorus', type: 'MAINBOARD', name: 'Gigabyte B650 AORUS Elite AX', price: 5290000, socket: 'AM5', ram: 'DDR5', form: 'ATX' },
    { id: 'gpu-4060', type: 'GPU', name: 'ASUS Dual GeForce RTX 4060 OC 8GB', price: 8690000, power: 115, length: 227 },
    { id: 'gpu-4060-gigabyte', type: 'GPU', name: 'Gigabyte RTX 4060 Windforce OC 8GB', price: 7250000, power: 115, length: 201 },
    { id: 'gpu-4060-msi', type: 'GPU', name: 'MSI RTX 4060 Ventus 2X Black 8G OC', price: 8490000, power: 115, length: 199 },
    { id: 'gpu-3060-zotac', type: 'GPU', name: 'Zotac Gaming RTX 3060 Twin Edge 12GB', price: 5900000, power: 170, length: 224 },
    { id: 'ram-32-ddr5', type: 'RAM', name: 'Kingston Fury 32GB DDR5', price: 2150000, ram: 'DDR5' },
    { id: 'ram-16-ddr5', type: 'RAM', name: 'Corsair Vengeance 16GB DDR5', price: 1190000, ram: 'DDR5' },
    { id: 'ssd-sn770', type: 'SSD', name: 'WD Black SN770 1TB', price: 1890000 },
    { id: 'ssd-nv2', type: 'SSD', name: 'Kingston NV2 1TB', price: 1590000 },
    { id: 'psu-650', type: 'PSU', name: 'Corsair RM650e 650W', price: 1790000, watts: 650 },
    { id: 'psu-750', type: 'PSU', name: 'Cooler Master MWE Gold 750W', price: 2290000, watts: 750 },
    { id: 'case-air-100', type: 'CASE', name: 'Montech Air 100', price: 1190000, form: 'mATX', gpuLength: 330 },
    { id: 'case-h5-flow', type: 'CASE', name: 'NZXT H5 Flow', price: 2190000, form: 'ATX', gpuLength: 365 },
    { id: 'cooler-ak400', type: 'TẢN NHIỆT', name: 'DeepCool AK400', price: 790000, socket: 'AM5' }
  ],
  builds: [], alerts: [], conversations: [], scans: [], notifications: [], supportRequests: [], market: {}
};

function loadDb() {
  try { return JSON.parse(fs.readFileSync(DB_FILE, 'utf8')); } catch { return structuredClone(seed); }
}
function normalizeDb(value) {
  const result = value || structuredClone(seed);
  result.users ??= [];
  result.areas ??= structuredClone(seed.areas);
  result.products ??= [];
  result.builds ??= [];
  result.alerts ??= [];
  result.conversations ??= [];
  result.scans ??= [];
  result.notifications ??= [];
  result.supportRequests ??= [];
  result.market ??= {};
  result.passwordResetTokens ??= [];
  for (const item of seed.products) {
    if (!result.products.some((existing) => existing.id === item.id)) result.products.push(item);
  }
  for (const area of result.areas) {
    result.market[area.id] ??= {};
    for (const item of result.products) {
      result.market[area.id][item.id] ??= {
        current: Math.round(item.price * ({ hcm: 1, hanoi: 1.024, danang: 1.011 }[area.id] || 1)),
        previous: Math.round(item.price * ({ hcm: 0.982, hanoi: 1.006, danang: 0.997 }[area.id] || 0.982))
      };
    }
  }
  return result;
}
let db = normalizeDb(loadDb());
const persistenceReady = sqlStore
  ? sqlStore.initialize(normalizeDb(seed)).then((loaded) => {
      db = normalizeDb(loaded);
      console.log(`SQL Server persistence enabled: ${process.env.MSSQL_SERVER}:${process.env.MSSQL_PORT}/${process.env.MSSQL_DATABASE}`);
    })
  : Promise.resolve();
let persistenceError;
const saveDb = () => {
  if (!sqlStore) {
    fs.writeFileSync(DB_FILE, JSON.stringify(db, null, 2));
    return Promise.resolve();
  }
  return sqlStore.queueSave(db).catch((error) => {
    persistenceError = error;
    throw error;
  });
};
function send(res, status, body) {
  res.writeHead(status, {
    'content-type': 'application/json; charset=utf-8',
    'access-control-allow-origin': '*',
    'access-control-allow-methods': 'GET,POST,PUT,DELETE,OPTIONS',
    'access-control-allow-headers': 'content-type,authorization,ngrok-skip-browser-warning'
  });
  res.end(JSON.stringify(body));
}
function sendHtml(res, status, html) {
  res.writeHead(status, {
    'content-type': 'text/html; charset=utf-8',
    'access-control-allow-origin': '*',
  });
  res.end(html);
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
  const header = String(req.headers.authorization || '');
  if (!header.startsWith('Bearer ')) return null;
  const claims = verifyAccessToken(header.slice(7));
  return claims ? db.users.find((user) => user.id === claims.sub) : null;
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
const RESET_TOKEN_TTL_MS = 15 * 60 * 1000;
const resetTokenHash = (token) =>
  crypto.createHash('sha256').update(token).digest('hex');
let mailTransport;
function getMailTransport() {
  if (mailTransport) return mailTransport;
  if (!process.env.SMTP_USER || !process.env.SMTP_PASS) {
    throw new Error('SMTP_USER và SMTP_PASS chưa được cấu hình.');
  }
  mailTransport = nodemailer.createTransport({
    host: process.env.SMTP_HOST || 'smtp.gmail.com',
    port: Number(process.env.SMTP_PORT || 465),
    secure: String(process.env.SMTP_SECURE || 'true') === 'true',
    auth: { user: process.env.SMTP_USER, pass: process.env.SMTP_PASS },
  });
  return mailTransport;
}
function resetUrlFor(token) {
  const baseUrl = String(process.env.APP_BASE_URL || '').replace(/\/+$/, '');
  if (!baseUrl) throw new Error('APP_BASE_URL chưa được cấu hình.');
  return `${baseUrl}/reset-password?token=${encodeURIComponent(token)}`;
}
async function sendPasswordResetEmail(user, token) {
  const resetUrl = resetUrlFor(token);
  await getMailTransport().sendMail({
    from: `"PCBUILD LOCAL" <${process.env.SMTP_USER}>`,
    to: user.email,
    subject: 'Khôi phục mật khẩu PCBUILD LOCAL',
    text: `Xin chào ${user.name},\n\nMở liên kết sau trong 15 phút để đặt lại mật khẩu:\n${resetUrl}\n\nNếu bạn không yêu cầu, hãy bỏ qua email này.`,
    html: `<h2>Khôi phục mật khẩu</h2><p>Xin chào ${user.name},</p><p>Liên kết đặt lại mật khẩu có hiệu lực trong 15 phút:</p><p><a href="${resetUrl}">Đặt lại mật khẩu</a></p><p>Nếu bạn không yêu cầu, hãy bỏ qua email này.</p>`,
  });
}
function product(idValue) { return db.products.find((item) => item.id === idValue); }
function decodePathPart(value) {
  try { return decodeURIComponent(value); } catch { return value; }
}
const componentTypes = ['CPU', 'MAINBOARD', 'GPU', 'RAM', 'SSD', 'PSU', 'CASE', 'TẢN NHIỆT'];
function buildView(build) {
  const components = Object.fromEntries(
    componentTypes.map((type) => [type, product(build.components[type]) || null])
  );
  const selected = Object.values(components).filter(Boolean);
  const total = selected.reduce((sum, item) => sum + item.price, 0);
  const power = selected.reduce((sum, item) => sum + Number(item.power || 0), 0);
  const recommendedPsu = Math.max(450, Math.ceil((power + 150) / 50) * 50);
  return {
    ...build,
    version: Number(build.version || 1),
    syncState: 'synced',
    components,
    totalPrice: total,
    completion: Math.round(selected.length / componentTypes.length * 100),
    estimatedPower: power,
    recommendedPsu,
    powerDetails: selected.map((item) => ({ id: item.id, name: item.name, watts: Number(item.power || 0) }))
  };
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
  const estimatedPower = items.reduce((sum, item) => sum + Number(item?.power || 0), 0);
  const recommendedPsu = Math.max(450, Math.ceil((estimatedPower + 150) / 50) * 50);
  const recommendations = [];
  if (gpu && (!psu || psu.watts < recommendedPsu)) {
    recommendations.push(...db.products.filter((item) => item.type === 'PSU' && item.watts >= recommendedPsu).slice(0, 3));
  }
  if (cpu && board && cpu.socket !== board.socket) {
    recommendations.push(...db.products.filter((item) => item.type === 'MAINBOARD' && item.socket === cpu.socket).slice(0, 3));
  }
  const criteria = [
    {
      code: 'SOCKET',
      severity: 'error',
      status: cpu && board ? (cpu.socket === board.socket ? 'pass' : 'error') : 'unchecked',
      comparedFields: ['CPU.socket', 'MAINBOARD.socket'],
      assumptions: [],
      remediation: 'Chọn mainboard cùng socket với CPU.'
    },
    {
      code: 'RAM',
      severity: 'error',
      status: board && ram ? (board.ram === ram.ram ? 'pass' : 'error') : 'unchecked',
      comparedFields: ['MAINBOARD.ram', 'RAM.ram'],
      assumptions: [],
      remediation: 'Chọn RAM đúng chuẩn mà mainboard hỗ trợ.'
    },
    {
      code: 'PSU',
      severity: 'warning',
      status: psu ? (psu.watts >= recommendedPsu ? 'pass' : 'warning') : 'unchecked',
      comparedFields: ['PSU.watts', 'estimatedPower'],
      assumptions: ['Công suất là ước tính từ catalog linh kiện.'],
      remediation: `Nên dùng PSU tối thiểu ${recommendedPsu}W.`
    },
    {
      code: 'CASE_SIZE',
      severity: 'error',
      status: gpu && box ? (gpu.length <= box.gpuLength ? 'pass' : 'error') : 'unchecked',
      comparedFields: ['GPU.length', 'CASE.gpuLength'],
      assumptions: [],
      remediation: 'Chọn case có khoảng trống GPU phù hợp.'
    }
  ];
  return {
    status: issues.some((item) => item.severity === 'error') ? 'incompatible' : issues.length ? 'warning' : 'compatible',
    score: Math.max(0, 100 - issues.length * 20),
    issues,
    estimatedPower,
    recommendedPsu,
    recommendations,
    criteria,
    checkedAt: new Date().toISOString(),
    rulesVersion: 'catalog-v1'
  };
}

async function route(req, res) {
  await persistenceReady;
  if (persistenceError) throw persistenceError;
  const url = new URL(req.url, `http://${req.headers.host || 'localhost'}`);
  const parts = url.pathname.split('/').filter(Boolean);
  const method = req.method;
  if (method === 'OPTIONS') return send(res, 204, {});
  if (method === 'GET' && url.pathname === '/health') return send(res, 200, { ok: true, service: 'pcbuild-local-api' });
  if (method === 'GET' && url.pathname === '/openapi.json') {
    return send(res, 200, JSON.parse(fs.readFileSync(path.join(__dirname, 'openapi.json'), 'utf8')));
  }
  if (method === 'GET' && url.pathname === '/docs') {
    res.writeHead(200, { 'content-type': 'text/html; charset=utf-8', 'access-control-allow-origin': '*' });
    return res.end(`<!doctype html><html><head><title>PCBUILD LOCAL API</title><link rel="stylesheet" href="https://unpkg.com/swagger-ui-dist@5/swagger-ui.css"></head><body><div id="swagger-ui"></div><script src="https://unpkg.com/swagger-ui-dist@5/swagger-ui-bundle.js"></script><script>SwaggerUIBundle({url:'/openapi.json',dom_id:'#swagger-ui'});</script></body></html>`);
  }
  if (method === 'GET' && url.pathname === '/reset-password') {
    const token = JSON.stringify(url.searchParams.get('token') || '');
    return sendHtml(res, 200, `<!doctype html>
<html lang="vi"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<title>Đặt lại mật khẩu - PCBUILD LOCAL</title>
<style>body{font-family:Arial,sans-serif;background:#070a0f;color:#fff;display:grid;place-items:center;min-height:100vh;margin:0}
main{width:min(390px,calc(100% - 40px));background:#101820;padding:28px;border-radius:16px;box-sizing:border-box}
h1{font-size:22px;text-align:center}.mint{color:#63e6be}label{display:block;margin-top:16px;color:#a8b4c0}
input{width:100%;box-sizing:border-box;padding:13px;margin-top:7px;border:1px solid #33404d;border-radius:10px;background:#0c121a;color:#fff}
button{width:100%;margin-top:22px;padding:14px;border:0;border-radius:10px;background:#63e6be;color:#07100e;font-weight:bold;cursor:pointer}
#message{margin-top:16px;line-height:1.4}</style></head>
<body><main><h1 class="mint">ĐẶT LẠI MẬT KHẨU</h1>
<label>Mật khẩu mới<input id="password" type="password" minlength="8"></label>
<label>Nhập lại mật khẩu<input id="confirmation" type="password" minlength="8"></label>
<button id="submit">CẬP NHẬT MẬT KHẨU</button><div id="message"></div>
<script>
const token=${token}; const message=document.getElementById('message');
document.getElementById('submit').onclick=async()=>{const password=document.getElementById('password').value;
const confirmation=document.getElementById('confirmation').value;
if(password.length<8||password!==confirmation){message.textContent='Mật khẩu phải có ít nhất 8 ký tự và hai ô phải giống nhau.';return;}
const response=await fetch('/api/v1/auth/reset-password',{method:'POST',headers:{'content-type':'application/json'},body:JSON.stringify({token,password})});
const data=await response.json(); message.textContent=data.message||'Đã xảy ra lỗi.';
if(response.ok) document.getElementById('submit').disabled=true;};
</script></main></body></html>`);
  }

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
    const user = {
      id: id('user'),
      name,
      email,
      areaId: body.areaId || 'hcm',
      preferences: {
        pricePreference: true,
        priceNotifications: true
      },
      passwordHash: crypto.createHash('sha256').update(password).digest('hex')
    };
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
    return send(res, 200, { accessToken: createAccessToken(user), tokenType: 'Bearer', expiresIn: JWT_EXPIRES_IN, user: publicUser(user) });
  }
  if (method === 'POST' && parts.join('/') === 'api/v1/auth/forgot-password') {
    const email = String(body.email || '').trim().toLowerCase();
    if (!email || !email.includes('@')) return send(res, 422, { error: 'INVALID_EMAIL', message: 'Email không hợp lệ.' });
    const user = db.users.find((item) => item.email.toLowerCase() === email);
    if (!user) return send(res, 202, { accepted: true, message: 'Nếu email tồn tại, hướng dẫn khôi phục đã được gửi.' });
    const token = crypto.randomBytes(32).toString('base64url');
    db.passwordResetTokens = db.passwordResetTokens.filter(
      (item) => item.userId !== user.id && item.expiresAt > Date.now()
    );
    db.passwordResetTokens.push({
      tokenHash: resetTokenHash(token),
      userId: user.id,
      expiresAt: Date.now() + RESET_TOKEN_TTL_MS,
      usedAt: null,
    });
    saveDb();
    try {
      await sendPasswordResetEmail(user, token);
    } catch (error) {
      db.passwordResetTokens = db.passwordResetTokens.filter(
        (item) => item.tokenHash !== resetTokenHash(token)
      );
      saveDb();
      return send(res, 503, { error: 'SMTP_UNAVAILABLE', message: `Không thể gửi email khôi phục: ${error.message}` });
    }
    return send(res, 202, { accepted: true, message: 'Nếu email tồn tại, hướng dẫn khôi phục đã được gửi.' });
  }
  if (method === 'POST' && parts.join('/') === 'api/v1/auth/reset-password') {
    const token = String(body.token || '');
    const password = String(body.password || '');
    if (!token || password.length < 8) {
      return send(res, 422, { error: 'INVALID_RESET_REQUEST', message: 'Token hợp lệ và mật khẩu mới tối thiểu 8 ký tự là bắt buộc.' });
    }
    const record = db.passwordResetTokens.find(
      (item) => item.tokenHash === resetTokenHash(token) && !item.usedAt
    );
    if (!record || record.expiresAt <= Date.now()) {
      return send(res, 400, { error: 'RESET_TOKEN_INVALID', message: 'Liên kết khôi phục không hợp lệ hoặc đã hết hạn.' });
    }
    const user = db.users.find((item) => item.id === record.userId);
    if (!user) return send(res, 400, { error: 'RESET_TOKEN_INVALID', message: 'Liên kết khôi phục không hợp lệ hoặc đã hết hạn.' });
    user.passwordHash = crypto.createHash('sha256').update(password).digest('hex');
    record.usedAt = Date.now();
    db.passwordResetTokens = db.passwordResetTokens.filter((item) => item !== record);
    saveDb();
    return send(res, 200, { ok: true, message: 'Đã cập nhật mật khẩu. Bạn có thể đăng nhập lại.' });
  }
  if (method === 'GET' && parts.join('/') === 'api/v1/areas') return send(res, 200, db.areas);
  if (method === 'POST' && parts.join('/') === 'api/v1/location/resolve') {
    const coordinates = {
      lat: Number(body.lat),
      lng: Number(body.lng)
    };
    const knownAreas = [
      { id: 'hcm', lat: 10.8231, lng: 106.6297 },
      { id: 'hanoi', lat: 21.0278, lng: 105.8342 },
      { id: 'danang', lat: 16.0544, lng: 108.2022 }
    ];
    const hasCoordinates = Number.isFinite(coordinates.lat) && Number.isFinite(coordinates.lng);
    const nearest = hasCoordinates
      ? knownAreas.reduce((best, candidate) => {
          const distance = Math.hypot(
            candidate.lat - coordinates.lat,
            candidate.lng - coordinates.lng
          );
          return distance < best.distance ? { candidate, distance } : best;
        }, { candidate: knownAreas[0], distance: Number.POSITIVE_INFINITY }).candidate
      : null;
    const area = db.areas.find((item) => item.id === body.areaId)
      || db.areas.find((item) => item.id === nearest?.id)
      || db.areas[0];
    return send(res, 200, {
      area,
      source: hasCoordinates ? 'gps' : body.areaId ? 'manual' : 'unresolved',
      coordinates: hasCoordinates ? coordinates : null
    });
  }
  if (method === 'GET' && parts.join('/') === 'api/v1/market/summary') {
    const areaId = url.searchParams.get('areaId') || 'hcm';
    const area = db.areas.find((item) => item.id === areaId) || db.areas[0];
    return send(res, 200, {
      area,
      updatedAt: new Date().toISOString(),
      source: 'backend-market-catalog',
      items: db.products.map((item) => {
        const productId = item.id;
        const prices = db.market[area.id][productId];
        const trend = Number((((prices.current - prices.previous) / prices.previous) * 100).toFixed(2));
        return { productId, name: item.name, price: prices.current, previousPrice: prices.previous, trend };
      })
    });
  }
  if (method === 'GET' && parts.join('/') === 'api/v1/products') {
    const type = url.searchParams.get('type');
    const query = (url.searchParams.get('q') || '').trim().toLowerCase();
    const maxPrice = Number(url.searchParams.get('maxPrice') || 0);
    return send(res, 200, db.products.filter((item) =>
      (!type || item.type === type) &&
      (!query || `${item.name} ${item.id}`.toLowerCase().includes(query)) &&
      (!maxPrice || item.price <= maxPrice)
    ));
  }
  if (method === 'GET' && parts.join('/') === 'api/v1/compare') {
    const ids = [...new Set((url.searchParams.get('productIds') || '').split(',').map((value) => value.trim()).filter(Boolean))];
    if (ids.length < 2 || ids.length > 3) return send(res, 422, { error: 'INVALID_COMPARE_COUNT', message: 'Cần so sánh từ 2 đến 3 sản phẩm.' });
    const products = ids.map((productId) => product(productId)).filter(Boolean);
    if (products.length !== ids.length) return send(res, 404, { error: 'PRODUCT_NOT_FOUND' });
    return send(res, 200, {
      products,
      fields: ['name', 'type', 'price', 'power', 'socket', 'ram', 'form', 'length', 'watts'],
      updatedAt: new Date().toISOString(),
      source: 'backend-market-catalog'
    });
  }
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
  if (method === 'POST' && parts.join('/') === 'api/v1/auth/change-password') {
    const currentPassword = String(body.currentPassword || '');
    const newPassword = String(body.newPassword || '');
    if (newPassword.length < 8) {
      return send(res, 422, { error: 'INVALID_PASSWORD', message: 'Mật khẩu mới phải có ít nhất 8 ký tự.' });
    }
    const currentHash = crypto.createHash('sha256').update(currentPassword).digest('hex');
    if (user.passwordHash !== currentHash) {
      return send(res, 401, { error: 'INVALID_CURRENT_PASSWORD', message: 'Mật khẩu hiện tại không đúng.' });
    }
    user.passwordHash = crypto.createHash('sha256').update(newPassword).digest('hex');
    saveDb();
    return send(res, 200, { ok: true, message: 'Đã đổi mật khẩu.' });
  }
  if (method === 'PUT' && parts.join('/') === 'api/v1/auth/me') {
    const name = body.name === undefined ? user.name : String(body.name).trim();
    const areaId = body.areaId === undefined ? user.areaId : String(body.areaId);
    if (name.length < 2) return send(res, 422, { error: 'INVALID_NAME', message: 'Tên người dùng tối thiểu 2 ký tự.' });
    if (!db.areas.some((area) => area.id === areaId)) return send(res, 422, { error: 'INVALID_AREA', message: 'Khu vực không hợp lệ.' });
    user.name = name;
    user.areaId = areaId;
    if (body.avatarUrl !== undefined) user.avatarUrl = String(body.avatarUrl).slice(0, 500);
    if (body.preferences && typeof body.preferences === 'object') {
      user.preferences = {
        ...(user.preferences || {}),
        ...(body.preferences.pricePreference === undefined
          ? {}
          : { pricePreference: Boolean(body.preferences.pricePreference) }),
        ...(body.preferences.priceNotifications === undefined
          ? {}
          : { priceNotifications: Boolean(body.preferences.priceNotifications) })
      };
    }
    saveDb();
    return send(res, 200, publicUser(user));
  }
  if (method === 'GET' && parts.join('/') === 'api/v1/auth/me') return send(res, 200, publicUser(user));
  if (method === 'GET' && parts.join('/') === 'api/v1/notifications') {
    return send(res, 200, db.notifications.filter((item) => item.userId === user.id).sort((a, b) => b.createdAt.localeCompare(a.createdAt)));
  }
  if (method === 'POST' && parts.join('/') === 'api/v1/notifications/read') {
    db.notifications.filter((item) => item.userId === user.id).forEach((item) => { item.read = true; });
    saveDb(); return send(res, 200, { ok: true });
  }
  if (method === 'POST' && parts.join('/') === 'api/v1/builds') {
    const build = { id: id('build'), userId: user.id, name: body.name || 'Build mới', budget: money(body.budget), areaId: body.areaId || user.areaId, components: {}, version: 1, status: 'draft', updatedAt: new Date().toISOString() };
    db.builds.push(build); saveDb(); return send(res, 201, buildView(build));
  }
  if (method === 'GET' && parts.join('/') === 'api/v1/builds') return send(res, 200, db.builds.filter((item) => item.userId === user.id).sort((a, b) => String(b.updatedAt || '').localeCompare(String(a.updatedAt || ''))).map(buildView));
  if (parts[0] === 'api' && parts[1] === 'v1' && parts[2] === 'builds' && parts[3]) {
    const build = db.builds.find((item) => item.id === parts[3] && item.userId === user.id);
    if (!build) return send(res, 404, { error: 'BUILD_NOT_FOUND' });
    if (method === 'GET') return send(res, 200, buildView(build));
    if (method === 'DELETE') { db.builds = db.builds.filter((item) => item !== build); saveDb(); return send(res, 204, {}); }
    if (method === 'PUT' && parts.length === 4) {
      if (body.expectedVersion !== undefined && Number(body.expectedVersion) !== Number(build.version || 1)) {
        return send(res, 409, { error: 'BUILD_VERSION_CONFLICT', message: 'Cấu hình đã thay đổi ở nơi khác.', latest: buildView(build) });
      }
      if (body.name !== undefined) {
        const name = String(body.name).trim();
        if (name.length < 2) return send(res, 422, { error: 'INVALID_BUILD_NAME', message: 'Tên cấu hình phải có ít nhất 2 ký tự.' });
        build.name = name;
      }
      if (body.budget !== undefined) build.budget = money(body.budget);
      if (body.areaId !== undefined) build.areaId = String(body.areaId);
      build.version = Number(build.version || 1) + 1;
      build.updatedAt = new Date().toISOString();
      saveDb();
      return send(res, 200, buildView(build));
    }
    if (method === 'PUT' && parts[4] === 'components' && parts[5]) {
      if (body.expectedVersion !== undefined && Number(body.expectedVersion) !== Number(build.version || 1)) {
        return send(res, 409, { error: 'BUILD_VERSION_CONFLICT', message: 'Cấu hình đã thay đổi ở nơi khác.', latest: buildView(build) });
      }
      const componentType = decodePathPart(parts[5]);
      if (body.productId === null || body.productId === undefined || body.productId === '') {
        delete build.components[componentType];
        build.version = Number(build.version || 1) + 1;
        build.updatedAt = new Date().toISOString();
        saveDb();
        return send(res, 200, buildView(build));
      }
      if (!product(body.productId) || product(body.productId).type !== componentType) {
        return send(res, 422, { error: 'INVALID_COMPONENT', message: `Sản phẩm không thuộc loại ${componentType}.` });
      }
      build.components[componentType] = body.productId;
      build.version = Number(build.version || 1) + 1;
      build.updatedAt = new Date().toISOString();
      saveDb();
      return send(res, 200, buildView(build));
    }
    if (method === 'POST' && parts[4] === 'duplicate') {
      const name = String(body.name || `${build.name} (bản sao)`).trim();
      if (name.length < 2 || name.length > 60) return send(res, 422, { error: 'INVALID_BUILD_NAME' });
      const copy = {
        ...build,
        id: id('build'),
        name,
        version: 1,
        updatedAt: new Date().toISOString()
      };
      db.builds.push(copy); saveDb(); return send(res, 201, buildView(copy));
    }
    if (method === 'POST' && parts[4] === 'check') return send(res, 200, compatibility(build.components));
  }
  if (method === 'POST' && parts.join('/') === 'api/v1/compatibility/check') return send(res, 200, compatibility(body.components || {}));
  if (method === 'POST' && parts.join('/') === 'api/v1/scans') {
    const candidateIds = Array.isArray(body.candidateProductIds) ? body.candidateProductIds : [];
    const candidates = candidateIds.map((candidateId) => product(candidateId)).filter(Boolean).map((item) => ({
      productId: item.id,
      model: item.name,
      confidence: Number(body.confidenceByProduct?.[item.id] || body.confidence || 0) || null
    }));
    const detectedProductId = product(body.confirmedProductId)?.id || null;
    const scan = {
      id: id('scan'),
      userId: user.id,
      status: detectedProductId ? 'confirmed' : (candidates.length ? 'awaiting_confirmation' : 'pending_analysis'),
      detectedProductId,
      candidates,
      confirmedByUser: Boolean(detectedProductId),
      createdAt: new Date().toISOString()
    };
    db.scans.push(scan); saveDb(); return send(res, 201, { ...scan, product: product(scan.detectedProductId) });
  }
  if (method === 'POST' && parts[0] === 'api' && parts[1] === 'v1' && parts[2] === 'scans' && parts[4] === 'confirm') {
    const scan = db.scans.find((item) => item.id === parts[3] && item.userId === user.id);
    const selected = product(body.productId);
    if (!scan) return send(res, 404, { error: 'SCAN_NOT_FOUND' });
    if (!selected || !scan.candidates.some((candidate) => candidate.productId === selected.id)) {
      return send(res, 422, { error: 'INVALID_SCAN_CANDIDATE', message: 'Sản phẩm xác nhận phải nằm trong danh sách nhận diện.' });
    }
    scan.detectedProductId = selected.id;
    scan.confirmedByUser = true;
    scan.status = 'confirmed';
    scan.confirmedAt = new Date().toISOString();
    saveDb();
    return send(res, 200, { ...scan, product: selected });
  }
  if (method === 'POST' && parts.join('/') === 'api/v1/conversations') {
    const conversation = { id: id('conversation'), userId: user.id, messages: [] }; db.conversations.push(conversation); saveDb(); return send(res, 201, conversation);
  }
  if (method === 'POST' && parts.join('/') === 'api/v1/ai/chat') {
    const lmStudioUrl = String(process.env.LM_STUDIO_URL || '').replace(/\/$/, '');
    const model = String(process.env.LM_STUDIO_MODEL || 'qwen3-vl-8b-instruct');
    if (!lmStudioUrl) {
      return send(res, 503, { error: 'AI_PROVIDER_REQUIRED', message: 'Hãy cấu hình LM_STUDIO_URL cho máy chủ.' });
    }
    const messages = Array.isArray(body.messages) ? body.messages : [];
    if (messages.length === 0) return send(res, 422, { error: 'INVALID_MESSAGES' });
    try {
      const headers = { 'content-type': 'application/json' };
      if (process.env.LM_STUDIO_API_KEY) headers.authorization = `Bearer ${process.env.LM_STUDIO_API_KEY}`;
      const response = await fetch(`${lmStudioUrl}/chat/completions`, {
        method: 'POST',
        headers,
        body: JSON.stringify({
          model,
          messages: messages.slice(-12),
          temperature: 0.4,
          stream: false
        })
      });
      const responseText = await response.text();
      let responseBody;
      try {
        responseBody = responseText ? JSON.parse(responseText) : null;
      } catch {
        responseBody = { error: { message: responseText || 'Phản hồi trống từ LM Studio.' } };
      }
      if (!response.ok) {
        return send(res, 502, {
          error: 'AI_PROVIDER_ERROR',
          message: responseBody?.error?.message || `LM Studio trả về HTTP ${response.status}.`
        });
      }
      return send(res, 200, responseBody);
    } catch (error) {
      return send(res, 502, { error: 'AI_PROVIDER_UNREACHABLE', message: error.message });
    }
  }
  if (method === 'POST' && parts[0] === 'api' && parts[1] === 'v1' && parts[2] === 'conversations' && parts[4] === 'messages') {
    const conversation = db.conversations.find((item) => item.id === parts[3] && item.userId === user.id);
    if (!conversation) return send(res, 404, { error: 'CONVERSATION_NOT_FOUND' });
    const message = String(body.message || '').trim();
    if (!message) return send(res, 422, { error: 'INVALID_MESSAGE', message: 'Nội dung tư vấn không được để trống.' });
    conversation.messages.push({ role: 'user', content: message, createdAt: new Date().toISOString() });
    saveDb();
    return send(res, 503, {
      error: 'AI_PROVIDER_REQUIRED',
      message: 'Hãy cấu hình LM Studio để nhận câu trả lời tư vấn.'
    });
  }
  if (method === 'POST' && parts.join('/') === 'api/v1/price-alerts') {
    const alert = { id: id('alert'), userId: user.id, productId: body.productId, targetPrice: money(body.targetPrice), areaId: body.areaId || user.areaId }; db.alerts.push(alert); saveDb(); return send(res, 201, alert);
  }
  if (method === 'GET' && parts.join('/') === 'api/v1/price-alerts') return send(res, 200, db.alerts.filter((item) => item.userId === user.id));
  if (method === 'GET' && parts.join('/') === 'api/v1/faq') {
    const query = String(url.searchParams.get('q') || '').trim().toLowerCase();
    const faq = [
      { id: 'faq-location', topic: 'location', question: 'Làm sao đổi khu vực?', answer: 'Mở Tài khoản > Khu vực và xác nhận vị trí mới.' },
      { id: 'faq-build', topic: 'build', question: 'Cấu hình được lưu ở đâu?', answer: 'Cấu hình được lưu theo tài khoản sau khi máy chủ xác nhận.' },
      { id: 'faq-compatibility', topic: 'compatibility', question: 'Tại sao linh kiện chưa kiểm tra được?', answer: 'Thiếu thông số catalog sẽ được đánh dấu chưa đủ dữ liệu, không tự coi là tương thích.' }
    ];
    return send(res, 200, faq.filter((item) => !query || `${item.topic} ${item.question} ${item.answer}`.toLowerCase().includes(query)));
  }
  if (method === 'POST' && parts.join('/') === 'api/v1/support-requests') {
    const message = String(body.message || '').trim();
    const email = String(body.contactEmail || user.email || '').trim();
    if (!email.includes('@')) return send(res, 422, { error: 'INVALID_EMAIL' });
    if (message.length < 10 || message.length > 2000) return send(res, 422, { error: 'INVALID_MESSAGE', message: 'Nội dung hỗ trợ phải từ 10 đến 2.000 ký tự.' });
    const request = { id: id('support'), userId: user.id, topic: String(body.topic || 'general'), contactEmail: email, message, status: 'received', createdAt: new Date().toISOString() };
    db.supportRequests.push(request); saveDb();
    return send(res, 201, request);
  }
  return send(res, 404, { error: 'NOT_FOUND' });
}

const server = http.createServer((req, res) => route(req, res).catch((error) => send(res, 500, { error: 'INTERNAL_ERROR', message: error.message })));
if (require.main === module) server.listen(PORT, '0.0.0.0', () => console.log(`PCBUILD API listening on port ${PORT}`));
module.exports = { server, db, route };
