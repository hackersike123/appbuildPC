require('dotenv').config();

const http = require('node:http');
const crypto = require('node:crypto');
const fs = require('node:fs');
const path = require('node:path');
const nodemailer = require('nodemailer');
// Removed JSON persistence; using relational tables via sql-models
const sqlModels = require('./sql-models');

async function ensureSqlSchema() {
  await sqlModels.ensureFeatureSchema();
}


const PORT = Number(process.env.PORT || 3000);
const JWT_SECRET = process.env.JWT_SECRET;
if (!JWT_SECRET) {
  throw new Error('JWT_SECRET must be set in backend/.env');
}
const JWT_EXPIRES_IN = Number(process.env.JWT_EXPIRES_IN || 3600);
const API_ISSUER = 'pcbuild-local-api';
const API_AUDIENCE = 'pcbuild-local-app';
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
    let rejected = false;
    req.on('data', (chunk) => {
      if (rejected) return;
      raw += chunk;
      if (raw.length > 12_000_000) {
        rejected = true;
        const error = new Error('Payload too large');
        error.statusCode = 413;
        reject(error);
      }
    });
    req.on('end', () => {
      if (rejected) return;
      try { resolve(raw ? JSON.parse(raw) : {}); }
      catch {
        const error = new Error('Invalid JSON');
        error.statusCode = 400;
        reject(error);
      }
    });
    req.on('error', reject);
  });
}
async function auth(req) {
  const header = String(req.headers.authorization || '');
  if (!header.startsWith('Bearer ')) return null;
  const claims = verifyAccessToken(header.slice(7));
  if (!claims) return null;
  // Load user from DB
  return await sqlModels.findUserById(claims.sub);
}
async function requireAuth(req, res) {
  const user = await auth(req);
  if (!user) {
    send(res, 401, { error: 'UNAUTHORIZED', message: 'Bearer token is required.' });
    return null;
  }
  return user;
}
function publicUser(user) {
  const { passwordHash, ...safe } = user;
  if (typeof safe.preferences === 'string') {
    try {
      safe.preferences = JSON.parse(safe.preferences);
    } catch {
      safe.preferences = {};
    }
  }
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
function completionText(completion) {
  const content = completion?.choices?.[0]?.message?.content;
  if (typeof content === 'string') return content.trim();
  if (Array.isArray(content)) {
    return content.map((part) => typeof part === 'string' ? part : String(part?.text || '')).join('\n').trim();
  }
  return '';
}

async function requestOpenAICompatibleChat({ url, model, messages, requestOptions = {}, provider, apiKey }) {
  const endpoint = String(url || '').replace(/\/$/, '');
  if (!endpoint) {
    const error = new Error(`${provider} chưa được cấu hình.`);
    error.statusCode = 503;
    throw error;
  }
  const headers = { 'content-type': 'application/json' };
  if (endpoint.includes('ngrok')) headers['ngrok-skip-browser-warning'] = 'true';
  if (apiKey) headers.authorization = `Bearer ${apiKey}`;
  const controller = new AbortController();
  const timeoutMs = Math.max(1000, Number(requestOptions.timeoutMs || process.env.AI_PROVIDER_TIMEOUT_MS || 300000));
  const timeout = setTimeout(() => controller.abort(), timeoutMs);
  try {
    const response = await fetch(`${endpoint}/chat/completions`, {
      method: 'POST',
      headers,
      signal: controller.signal,
      body: JSON.stringify({
        model,
        messages: messages.slice(-12),
        temperature: Number(requestOptions.temperature ?? process.env.LOCAL_AI_TEMPERATURE ?? 0.4),
        top_p: Number(requestOptions.topP ?? process.env.LOCAL_AI_TOP_P ?? 0.8),
        max_tokens: Number(requestOptions.maxTokens ?? process.env.LOCAL_AI_MAX_TOKENS ?? 512),
        stream: false
      })
    });
    const responseText = await response.text();
    let responseBody;
    try {
      responseBody = responseText ? JSON.parse(responseText) : null;
    } catch {
      responseBody = { error: { message: responseText || 'Phản hồi trống.' } };
    }
    if (!response.ok) {
      const error = new Error(responseBody?.error?.message || `${provider} trả về HTTP ${response.status}.`);
      error.statusCode = 502;
      throw error;
    }
    if (!completionText(responseBody)) {
      const error = new Error(`${provider} không trả về câu trả lời hợp lệ.`);
      error.statusCode = 502;
      throw error;
    }
    return responseBody;
  } catch (error) {
    if (controller.signal.aborted) {
      error.message = `${provider} quá thời gian chờ (${timeoutMs} ms).`;
      error.statusCode = 504;
    }
    throw error;
  } finally {
    clearTimeout(timeout);
  }
}

function answerNeedsExpertFallback(completion) {
  const answer = completionText(completion);
  return !answer || /__PCBUILD_NEED_EXPERT__|không thể trả lời|chưa thể trả lời|chưa đủ căn cứ|chưa đủ dữ liệu|chưa đủ thông tin|không đủ thông tin|không chắc chắn|chưa thể xác nhận|không thể xác định|tôi không biết|I don't know|I cannot answer|unable to answer|not enough information|not sure/i.test(answer);
}

function pcChatNeedsExpertReview(messages, completion) {
  if (answerNeedsExpertFallback(completion)) return true;
  const latestQuestion = [...messages].reverse().find((item) => item?.role === 'user')?.content;
  const question = String(latestQuestion || '').toLowerCase();
  const answer = completionText(completion).toLowerCase();
  if (/modular.{0,35}(psu|nguồn|power supply)|(psu|nguồn).{0,35}modular|dây.{0,35}(modular|nguồn)/i.test(question)) {
    return !/pinout|sơ đồ chân|đúng model|đúng sku|nhà sản xuất xác nhận/i.test(answer);
  }
  if (/mùi khét|cháy|tia lửa|tách điện|smoke|burning smell|melted connector/i.test(question)) {
    return !/(rút điện|ngắt điện|ngắt nguồn)/i.test(answer)
      || /(bật lại|tiếp tục sử dụng|mở psu)/i.test(answer);
  }
  if (/bios|flash.*firmware/i.test(question)) {
    return !/(revision|model mainboard|mã mainboard|manual|tài liệu|trang hỗ trợ|nhà sản xuất)/i.test(answer);
  }
  if (/ddr5|memory training|train ram|đèn dram/i.test(question)) {
    return !/(chờ|đợi).{0,60}(training|manual|đèn|post)|training.{0,80}(chờ|đợi)/i.test(answer)
      || /(xả ram|15.?30 phút)/i.test(answer);
  }
  return false;
}

function addLmStudioExpertInstructions(messages, task) {
  const instructions = [
    'Bạn là trợ lý AI chính thức của PCBUILD, chạy trên LM Studio. Hãy tự xử lý toàn bộ yêu cầu bằng tiếng Việt, chuyên nghiệp, chính xác và dựa trên ngữ cảnh được cung cấp.',
    'Chỉ hỗ trợ PC và linh kiện PC. Kiến thức kỹ thuật tổng quát có thể giải thích, nhưng mọi mã/tên SKU, giá, lịch sử giá, cấu hình tài khoản, thông số riêng của sản phẩm và dữ liệu tương thích phải khớp SQL trong system prompt. Thiếu SQL thì nói rõ chưa xác nhận; tuyệt đối không đoán hoặc tự tạo dữ liệu.',
    task === 'scan'
      ? 'Với ảnh, phân biệt loại linh kiện, đọc chữ và tìm ứng viên gần nhất trong catalog SQL. Chỉ đánh dấu recognized=true khi model/SKU in trên sản phẩm khớp rõ ràng và duy nhất. Nếu chưa chắc, recognized=false, productId=null nhưng vẫn trả tối đa 5 candidateProductIds có trong catalog, xếp theo mức giống hình/chữ; tuyệt đối không bịa ID.'
      : task === 'build'
        ? 'Chọn cấu hình chỉ từ product ID trong catalog SQL được cung cấp. Giữ nguyên linh kiện ghim, đúng ngân sách, đủ nhóm được yêu cầu và không khẳng định tương thích nếu dữ liệu SQL thiếu.'
        : 'Nếu câu hỏi cần dữ liệu SQL chưa có, nêu đúng giới hạn thay vì tự điền một con số.'
  ].join('\n');
  const cloned = messages.map((message) => ({ ...message }));
  const systemIndex = cloned.findIndex((message) => message.role === 'system');
  if (systemIndex >= 0) {
    cloned[systemIndex].content = `${cloned[systemIndex].content || ''}\n\n${instructions}`;
  } else {
    cloned.unshift({ role: 'system', content: instructions });
  }
  return cloned;
}

function removeHandoffMarker(completion) {
  const message = completion?.choices?.[0]?.message;
  if (typeof message?.content === 'string') {
    message.content = message.content.replaceAll('__PCBUILD_NEED_EXPERT__', '').trim()
      || 'Tôi chưa đủ căn cứ để trả lời chính xác từ dữ liệu hiện có.';
  }
  return completion;
}

async function requestProjectLmStudio(messages, {
  task = 'chat',
  requestOptions = {},
} = {}) {
  const lmStudioUrl = String(process.env.LM_STUDIO_URL || '').replace(/\/$/, '');
  const lmStudioModel = String((task === 'scan'
    ? process.env.LM_STUDIO_VISION_MODEL || process.env.LM_STUDIO_MODEL
    : process.env.LM_STUDIO_MODEL) || 'qwen3-vl-8b-instruct');
  const lmStudioRequestOptions = {
    ...requestOptions,
    timeoutMs: Number(requestOptions.timeoutMs || process.env.LM_STUDIO_TIMEOUT_MS || 240000)
  };
  if (!lmStudioUrl) {
    const error = new Error('LM_STUDIO_URL chưa được cấu hình.');
    error.statusCode = 503;
    throw error;
  }
  return requestOpenAICompatibleChat({
    url: lmStudioUrl,
    model: lmStudioModel,
    messages: addLmStudioExpertInstructions(messages, task),
    requestOptions: lmStudioRequestOptions,
    provider: 'LM Studio',
    apiKey: process.env.LM_STUDIO_API_KEY
  });
}

function appendSystemContext(messages, context) {
  const cloned = messages.map((message) => ({ ...message }));
  const systemIndex = cloned.findIndex((message) => message.role === 'system');
  if (systemIndex >= 0) {
    cloned[systemIndex].content = `${cloned[systemIndex].content || ''}\n\n${context}`;
  } else {
    cloned.unshift({ role: 'system', content: context });
  }
  return cloned;
}

function scanCompletionMatchesCatalog(completion, catalog) {
  let proposed;
  try {
    proposed = parseModelJson(completionText(completion));
  } catch {
    return false;
  }
  const confidence = Math.max(0, Math.min(1, Number(proposed?.confidence) || 0));
  const summary = String(proposed?.summary || '');
  const uncertain = /chưa đủ rõ|không đủ rõ|không chắc|chưa thể xác nhận|chưa xác định|chưa phân biệt|nhiều khả năng|nhiều bản ghi|nhiều sản phẩm|bản ghi cụ thể|có thể là|phân biệt|mơ hồ|không đọc được|không xác định được|uncertain|ambiguous|not sure|cannot confirm/i.test(summary);
  if (proposed?.recognized !== true || confidence < 0.9 || uncertain) return false;
  const productId = String(proposed.productId || '');
  const productName = String(proposed.name || '').trim().toLowerCase();
  return catalog.some((item) => item.id === productId || (productName && item.name.toLowerCase() === productName));
}

function hasVisibleSkuEvidence(product, vision) {
  if (!product) return false;
  const visibleText = String(vision?.visibleText || '').toLowerCase();
  const name = String(product.name || '').toLowerCase();
  if (!visibleText || !name) return false;
  if (product.type === 'GPU') {
    const model = name.match(/\b(?:rtx|gtx)\D{0,4}(\d{3,4})\b/i);
    if (model && !new RegExp(`\\b${model[1]}\\b`).test(visibleText)) return false;
    if (/\bti\b/i.test(name) && !/\bti\b/i.test(visibleText)) return false;
    if (/\bsuper\b/i.test(name) && !/\bsuper\b/i.test(visibleText)) return false;
    return Boolean(model);
  }
  const modelTokens = name.match(/\b[a-z]{0,5}\d{3,}[a-z0-9-]*\b/gi) || [];
  return modelTokens.some((token) => visibleText.includes(token.toLowerCase()));
}

function addLmStudioInitialVisionInstructions(messages) {
  return appendSystemContext(messages, [
    'Bạn là bộ nhận diện hình ảnh PC của PCBUILD. Phân loại linh kiện; đọc nguyên văn mọi chữ/model/SKU rõ; nhận diện hãng, họ sản phẩm và mô tả đặc điểm nhìn thấy để lượt sau so với catalog SQL.',
    'Không khẳng định model cụ thể nếu không nhìn thấy bằng chứng. Nếu ảnh chỉ thấy hãng hoặc dòng chung, vẫn ghi brand/modelFamily/visualDescription để tạo danh sách gợi ý gần giống, nhưng giảm confidence và nêu giới hạn.',
    'Chỉ trả JSON đúng schema: {"componentType":string|null,"visibleText":string,"brand":string|null,"modelFamily":string|null,"visualDescription":string,"confidence":number,"summary":string}. componentType chỉ dùng CPU, MAINBOARD, GPU, RAM, SSD, PSU, CASE, TẢN NHIỆT hoặc null. Không thêm markdown hay văn bản ngoài JSON.'
  ].join('\n'));
}

function catalogForVisionCandidate(candidate, catalog) {
  const value = String(candidate?.componentType || '').trim().toUpperCase();
  const aliases = {
    'CPU COOLER': 'TẢN NHIỆT',
    COOLER: 'TẢN NHIỆT',
    'GRAPHICS CARD': 'GPU',
    'VIDEO CARD': 'GPU',
    VGA: 'GPU',
    MOTHERBOARD: 'MAINBOARD',
    MEMORY: 'RAM',
    'POWER SUPPLY': 'PSU',
    'POWER SUPPLY UNIT': 'PSU',
    'PC CASE': 'CASE',
    CHASSIS: 'CASE',
    STORAGE: 'SSD',
    HDD: 'SSD',
  };
  const type = aliases[value] || value;
  const focused = catalog.filter((item) => item.type === type);
  const source = focused.length ? focused : catalog;
  const visibleText = [candidate?.brand, candidate?.visibleText].filter(Boolean).join(' ').toLowerCase();
  const visualHints = [candidate?.modelFamily, candidate?.visualDescription].filter(Boolean).join(' ').toLowerCase();
  const tokens = visibleText.split(/[^a-z0-9]+/i).filter((token) => token.length >= 3);
  const hintTokens = visualHints.split(/[^a-z0-9]+/i).filter((token) => token.length >= 3);
  return source.map((item) => {
    const name = String(item.name || '').toLowerCase();
    const id = String(item.id || '').toLowerCase();
    let score = 0;
    if (name && visibleText.includes(name)) score += 100;
    if (id && visibleText.includes(id)) score += 100;
    for (const token of tokens) {
      if (name.includes(token) || id.includes(token)) score += 10;
    }
    for (const token of hintTokens) {
      if (name.includes(token) || id.includes(token)) score += 2;
    }
    if (/\b(?:geforce|rtx|gtx)\b/i.test(visibleText)) {
      score += /\b(?:geforce|rtx|gtx)\b/i.test(name) ? 40 : -40;
    }
    if (/\b(?:radeon|rx)\b/i.test(visibleText)) {
      score += /\b(?:radeon|rx)\b/i.test(name) ? 40 : -40;
    }
    return { ...item, _visionMatchScore: score };
  }).sort((a, b) => b._visionMatchScore - a._visionMatchScore
      || Number(b.priceSource === 'market') - Number(a.priceSource === 'market')
      || Number(a.price) - Number(b.price))
    .filter((item) => item._visionMatchScore > 0)
    .slice(0, 80);
}

function parseVisionStageOne(completion) {
  const raw = completionText(completion);
  try {
    return parseModelJson(raw);
  } catch {
    return { componentType: null, visibleText: raw.slice(0, 1000), confidence: 0, summary: 'Lượt OCR vision đầu không trả JSON hợp lệ.' };
  }
}

async function requestVisionWithLmStudio(messages, catalog, requestOptions = {}) {
  const lmStudioUrl = String(process.env.LM_STUDIO_URL || '').replace(/\/$/, '');
  const lmStudioModel = String(process.env.LM_STUDIO_VISION_MODEL || process.env.LM_STUDIO_MODEL || 'qwen3-vl-8b-instruct');
  if (!lmStudioUrl) {
    const error = new Error('LM_STUDIO_URL chưa được cấu hình.');
    error.statusCode = 503;
    throw error;
  }
  const firstVisionCompletion = await requestOpenAICompatibleChat({
    url: lmStudioUrl,
    model: lmStudioModel,
    messages: addLmStudioInitialVisionInstructions(messages),
    requestOptions: { ...requestOptions, temperature: 0.1 },
    provider: 'LM Studio vision OCR',
    apiKey: process.env.LM_STUDIO_API_KEY
  });
  const firstVision = parseVisionStageOne(firstVisionCompletion);
  const candidateCatalog = catalogForVisionCandidate(firstVision, catalog)
    .map(({ id, type, name, price, priceSource }) => ({ id, type, name, price, priceSource }));
  const finalMessages = [
    {
      role: 'system',
      content: [
        'Bạn là AI vision chuyên dụng của PCBUILD. Dùng ảnh gốc, chữ in, hình dáng và catalog SQL bên dưới để nhận diện hoặc đưa ra các ứng viên gần giống.',
        `Kết quả OCR sơ bộ: ${JSON.stringify(firstVision).slice(0, 1800)}`,
        `Các ứng viên catalog SQL: ${JSON.stringify(candidateCatalog)}`,
        'Nếu model/SKU đọc được và khớp duy nhất tên trong catalog, trả recognized=true, productId đúng và candidateProductIds gồm sản phẩm đó.',
        'Nếu không đọc rõ SKU, không được khẳng định chính xác. Hãy chọn tối đa 5 productId gần giống nhất từ danh sách catalog dựa trên chữ nhìn thấy, hãng, dòng sản phẩm và hình dáng; trả recognized=false, productId=null. Nếu ảnh chỉ cho biết hãng/loại chung, nói rõ đây là gợi ý gần đúng để người dùng xác nhận.',
        'Không tạo SKU, giá, hay thông số. Trả duy nhất JSON: {"recognized":boolean,"productId":string|null,"candidateProductIds":string[],"componentType":string|null,"confidence":number,"summary":string}.'
      ].join('\n')
    },
    ...messages.filter((message) => message.role === 'user')
  ];
  const completion = await requestOpenAICompatibleChat({
    url: lmStudioUrl,
    model: lmStudioModel,
    messages: addLmStudioExpertInstructions(finalMessages, 'scan'),
    requestOptions: { ...requestOptions, temperature: 0.1 },
    provider: 'LM Studio final vision review',
    apiKey: process.env.LM_STUDIO_API_KEY
  });
  return { completion, firstVision, candidateCatalog };
}

function catalogPromptSelection(catalog, messages = [], activeBuild = null, limit = 32) {
  const userText = messages
    .filter((message) => message?.role === 'user')
    .slice(-3)
    .map((message) => String(message.content || ''))
    .join(' ')
    .toLowerCase();
  const tokens = userText.split(/[^a-z0-9]+/i).filter((token) => token.length >= 3);
  const typeTerms = new Map([
    ['GPU', ['gpu', 'rtx', 'geforce', 'radeon', 'arc', 'vga']],
    ['CPU', ['cpu', 'ryzen', 'intel', 'xeon', 'processor']],
    ['MAINBOARD', ['mainboard', 'motherboard', 'bo mach', 'b650', 'x670', 'am5', 'lga']],
    ['RAM', ['ram', 'ddr4', 'ddr5', 'memory']],
    ['SSD', ['ssd', 'nvme', 'm.2']],
    ['PSU', ['psu', 'nguon', 'nguồn', 'watt']],
    ['CASE', ['case', 'vo may', 'vỏ máy']],
    ['TẢN NHIỆT', ['tan nhiet', 'tản nhiệt', 'cooler', 'aio']]
  ]);
  const requestedTypes = new Set();
  for (const [type, terms] of typeTerms) {
    if (terms.some((term) => userText.includes(term))) requestedTypes.add(type);
  }
  const ranked = catalog.map((item) => {
    const name = String(item.name || '').toLowerCase();
    const id = String(item.id || '').toLowerCase();
    let score = requestedTypes.has(item.type) ? 4 : 0;
    if (name && userText.includes(name)) score += 100;
    if (id && userText.includes(id)) score += 100;
    for (const token of tokens) {
      if (name.includes(token) || id.includes(token)) score += 8;
    }
    if (hasMarketProductPrice(item)) score += 1;
    return { item, score };
  }).sort((a, b) => b.score - a.score || Number(a.item.price) - Number(b.item.price));

  const selected = new Map();
  const add = (item) => {
    if (item?.id && selected.size < limit) selected.set(item.id, item);
  };
  if (activeBuild?.components) {
    for (const productId of Object.values(activeBuild.components)) {
      add(catalog.find((item) => item.id === productId));
    }
  }
  const typesToSeed = requestedTypes.size ? requestedTypes : new Set([...typeTerms.keys()]);
  for (const type of typesToSeed) {
    for (const { item } of ranked.filter(({ item }) => item.type === type).slice(0, 3)) add(item);
  }
  for (const { item } of ranked) {
    if (selected.size >= limit) break;
    add(item);
  }
  return [...selected.values()];
}

function pcKnowledgePrompt(catalog, areaId, examples = [], activeBuild = null, messages = []) {
  const facts = catalogPromptSelection(catalog, messages, activeBuild).map(({ id: productId, type, name, price, priceSource, power, watts, socket, ram, form, length, gpuLength, recommendedPsuW, recommendedPsuSource }) => ({
    id: productId, type, name, price: Number(price), priceSource, power, watts, socket, ram, form, length, gpuLength, recommendedPsuW, recommendedPsuSource
  }));
  const examplesText = examples.map((item) => `Chủ đề: ${item.topic}\nNgười dùng: ${item.userPrompt}\nCách trả lời: ${item.assistantResponse}`).join('\n\n');
  const buildParts = activeBuild
    ? Object.entries(activeBuild.components || {}).map(([type, productId]) => catalog.find((item) => item.id === productId && item.type === type)).filter(Boolean)
    : [];
  const buildPower = activeBuild ? powerAssessment(buildParts) : null;
  const buildText = activeBuild
    ? `Build SQL gần nhất và số điện đã tính sẵn (không tự tính lại): ${JSON.stringify({ name: activeBuild.name, budget: activeBuild.budget, components: buildParts.map((item) => ({ type: item.type, name: item.name, powerTdpW: Number(item.power || 0), psuCapacityW: Number(item.watts || 0), gpuManufacturerPsuW: item.recommendedPsuW || null })), power: buildPower, totalPrice: buildParts.reduce((sum, item) => sum + Number(item.price || 0), 0) })}`
    : 'Tài khoản chưa có build SQL hiện tại.';
  return [
    'Bạn là PCBuild Coach, trợ lý CHỈ phục vụ cấu hình, linh kiện, nguồn, tương thích, nâng cấp, khắc phục lỗi PC và nhận diện sản phẩm PC.',
    'Luôn trả lời bằng tiếng Việt, ngắn gọn, nêu kết luận trước rồi mới nêu lý do. Nếu câu hỏi ngoài PC, từ chối lịch sự và hướng người dùng về PC.',
    'SQL là nguồn duy nhất cho tên/mã sản phẩm, giá khu vực, mức PSU hãng khuyến nghị và cấu hình tài khoản. Không bịa giá, lịch sử giá, thông số hay linh kiện.',
    'Khi đánh giá PSU, chỉ chép số từ powerAssessment: estimatedLoadW là tải; recommendedPsuW là mức đề nghị hệ thống; selectedPsuW là PSU đã chọn; marginW là chênh so với recommendedPsuW; marginFromLoadW là chênh so với tải; marginVsManufacturerW là chênh so với mức hãng. Dấu dương là dư, dấu âm là thiếu. Nếu manufacturerMinimumW hoặc marginVsManufacturerW null thì SQL không có mức hãng: không được ghi một con số dưới nhãn “PSU hãng khuyến nghị” và không được nêu số dư/thiếu theo hãng. Không lấy recommendedPsuW hay marginW thay cho dữ liệu hãng. Không tự tính lại, đổi định nghĩa, thêm phần trăm hoặc nhận xét ngoài dữ liệu.',
    'Khi đánh giá tương thích: chỉ kết luận những cặp có đủ thông số SQL; linh kiện hoặc thông số còn thiếu phải ghi “chưa kiểm tra/chưa đủ dữ liệu”, tuyệt đối không gọi là đạt.',
    'Khi quét ảnh: chỉ xác nhận model khi khớp catalog SQL; nếu ảnh mờ hoặc chưa chắc, nói rõ và không tự tạo mã sản phẩm.',
    'Nếu không thể đưa câu trả lời PC hữu ích, có căn cứ từ ngữ cảnh, hãy trả chính xác __PCBUILD_NEED_EXPERT__ để lượt chuyên gia dự phòng kiểm tra; không dùng dấu này chỉ vì SQL thiếu giá hoặc thông số mà cần được giữ ở trạng thái chưa xác nhận.',
    `Ví dụ hướng dẫn đã duyệt từ SQL:\n${examplesText || 'Không có ví dụ bổ sung.'}`,
    buildText,
    `Khu vực tài khoản: ${areaId}. Catalog SQL rút gọn theo câu hỏi: ${JSON.stringify(facts)}`
  ].join('\n\n');
}

function psuRatedWatts(item) {
  const explicit = Number(item?.watts);
  if (Number.isFinite(explicit) && explicit > 0) return explicit;
  const match = String(item?.name || '').match(/\b(\d{3,4})\s*W\b/i);
  return match ? Number(match[1]) : 0;
}

function normalizeFormFactor(value) {
  const normalized = String(value || '').toLowerCase().replace(/[^a-z0-9]+/g, ' ').trim();
  if (/e ?atx|extended atx/.test(normalized)) return 'eatx';
  if (/micro ?atx|\bmatx\b/.test(normalized)) return 'matx';
  if (/mini ?itx|\bitx\b/.test(normalized)) return 'itx';
  if (/\batx\b/.test(normalized)) return 'atx';
  return normalized;
}

function caseSupportsBoardForm(caseForm, boardForm) {
  const box = normalizeFormFactor(caseForm);
  const board = normalizeFormFactor(boardForm);
  const supportedBoards = {
    eatx: ['eatx', 'atx', 'matx', 'itx'],
    atx: ['atx', 'matx', 'itx'],
    matx: ['matx', 'itx'],
    itx: ['itx']
  };
  return Boolean(box && board && supportedBoards[box]?.includes(board));
}

function powerAssessment(items) {
  const selected = items.filter(Boolean);
  const estimatedLoadW = selected.filter((item) => item.type !== 'PSU')
    .reduce((sum, item) => sum + Math.max(0, Number(item.power || 0)), 0);
  const gpus = selected.filter((item) => item.type === 'GPU');
  const manufacturerMinimumW = gpus.reduce((maximum, gpu) => Math.max(maximum, Number(gpu.recommendedPsuW || 0)), 0);
  const calculatedMinimumW = selected.length ? Math.ceil((estimatedLoadW * 1.3 + 100) / 50) * 50 : 0;
  const recommendedPsuW = selected.length ? Math.max(450, calculatedMinimumW, manufacturerMinimumW) : 0;
  const selectedPsu = selected.filter((item) => item.type === 'PSU').sort((a, b) => psuRatedWatts(a) - psuRatedWatts(b))[0] || null;
  const selectedPsuW = selectedPsu ? psuRatedWatts(selectedPsu) || null : null;
  const sourceEntry = gpus.find((gpu) => gpu.recommendedPsuW && gpu.recommendedPsuSource);
  return {
    estimatedLoadW,
    calculatedMinimumW,
    manufacturerMinimumW: manufacturerMinimumW || null,
    manufacturerGpuNames: gpus.filter((gpu) => gpu.recommendedPsuW).map((gpu) => gpu.name),
    manufacturerSources: [...new Set(gpus.map((gpu) => gpu.recommendedPsuSource).filter(Boolean))],
    recommendedPsuW,
    selectedPsuW,
    selectedPsuName: selectedPsu?.name || null,
    marginW: selectedPsuW == null ? null : selectedPsuW - recommendedPsuW,
    marginFromLoadW: selectedPsuW == null ? null : selectedPsuW - estimatedLoadW,
    marginVsManufacturerW: selectedPsuW == null || !manufacturerMinimumW ? null : selectedPsuW - manufacturerMinimumW,
    sourceEntry: sourceEntry ? { gpuName: sourceEntry.name, url: sourceEntry.recommendedPsuSource } : null,
    method: !selected.length
      ? 'Chưa chọn linh kiện; chưa tính công suất.'
      : manufacturerMinimumW
      ? 'max(mức PSU tối thiểu trong SQL của GPU, tải CPU/GPU × 1,3 + 100W dự phòng, 450W)'
      : 'max(tải CPU/GPU × 1,3 + 100W dự phòng, 450W)'
  };
}

function formatBuildPowerSummary(build, catalog) {
  const components = Object.entries(build.components || {})
    .map(([type, productId]) => catalog.find((item) => item.id === productId && item.type === type))
    .filter(Boolean);
  const power = powerAssessment(components);
  const formatMargin = (margin) => margin == null
    ? 'chưa đủ dữ liệu để tính'
    : margin >= 0 ? `dư ${margin} W` : `thiếu ${Math.abs(margin)} W`;
  const selected = power.selectedPsuW == null
    ? 'Chưa chọn PSU trong build SQL.'
    : `PSU đang chọn: ${power.selectedPsuName} (${power.selectedPsuW} W).`;
  const manufacturer = power.manufacturerMinimumW == null
    ? 'Mức PSU hãng khuyến nghị: SQL chưa có dữ liệu cho GPU trong build.'
    : `Mức PSU hãng khuyến nghị: ${power.manufacturerMinimumW} W${power.manufacturerGpuNames.length ? ` (${power.manufacturerGpuNames.join(', ')})` : ''}.`;
  const manufacturerMargin = power.marginVsManufacturerW == null
    ? 'Dư/thiếu so với mức hãng: chưa đủ dữ liệu để tính.'
    : `Dư/thiếu so với mức hãng: ${formatMargin(power.marginVsManufacturerW)}.`;
  return [
    `Theo build “${build.name}” trong SQL:`,
    `Tải CPU/GPU ước tính: ${power.estimatedLoadW} W.`,
    manufacturer,
    `Mức PSU hệ thống đề nghị: ${power.recommendedPsuW} W.`,
    selected,
    `Dư/thiếu so với mức hệ thống đề nghị: ${formatMargin(power.marginW)}.`,
    manufacturerMargin,
    `Chênh so với tải ước tính: ${formatMargin(power.marginFromLoadW)}; đây không phải mức PSU hãng khuyến nghị.`
  ].join('\n');
}

function isPowerQuestion(messages) {
  const lastUserMessage = [...messages].reverse().find((message) => message?.role === 'user');
  const content = Array.isArray(lastUserMessage?.content)
    ? lastUserMessage.content.map((part) => part?.text || '').join(' ')
    : String(lastUserMessage?.content || '');
  return /psu|nguồn|nguon|watt|công suất|cong suat/i.test(content);
}

function selectSqlBuild(catalog, budget, purpose, areaId, pinnedComponents = {}) {
  const byType = (type) => catalog.filter((item) => item.type === type && hasUsableProductPrice(item)).sort((a, b) => Number(a.price) - Number(b.price));
  const pick = (type, predicate = () => true) => {
    const pinnedId = pinnedComponents[type];
    return pinnedId
      ? catalog.find((item) => item.id === String(pinnedId) && item.type === type && hasUsableProductPrice(item) && predicate(item))
      : byType(type).find(predicate);
  };
  const cpu = pick('CPU');
  if (!cpu) return null;
  const board = pick('MAINBOARD', (item) => item.socket === cpu.socket);
  if (!board) return null;
  const ram = pick('RAM', (item) => !board.ram || item.ram === board.ram);
  const gpu = pick('GPU');
  const box = pick('CASE', (item) => !gpu || !gpu.length || !item.gpuLength || gpu.length <= item.gpuLength);
  const ssd = pick('SSD');
  const cooler = pick('TẢN NHIỆT', (item) => !item.socket || item.socket === cpu.socket);
  if (!ram || !gpu || !box || !ssd || !cooler) return null;
  const power = powerAssessment([cpu, gpu]);
  const psu = pick('PSU', (item) => Number(item.watts || 0) >= power.recommendedPsuW);
  if (!psu) return null;
  const chosen = { CPU: cpu, MAINBOARD: board, GPU: gpu, RAM: ram, SSD: ssd, PSU: psu, CASE: box, 'TẢN NHIỆT': cooler };
  const total = Object.values(chosen).reduce((sum, item) => sum + Number(item.price || 0), 0);
  if (total > budget) return null;
  const report = compatibility(Object.fromEntries(Object.entries(chosen).map(([type, item]) => [type, item.id])), catalog);
  if (report.status === 'incompatible') return null;
  return {
    name: `PC ${purpose} theo catalog SQL`,
    budget,
    areaId,
    components: Object.fromEntries(Object.entries(chosen).map(([type, item]) => [type, item.id])),
    totalPrice: total,
    priceEstimate: Object.values(chosen).some((item) => item.priceSource !== 'market'),
    source: 'sql'
  };
}

function parseModelJson(text) {
  const cleaned = String(text || '').replace(/^```(?:json)?\s*/i, '').replace(/\s*```$/, '').trim();
  return JSON.parse(cleaned);
}

function decodePathPart(value) {
  try { return decodeURIComponent(value); } catch { return value; }
}
const componentTypes = ['CPU', 'MAINBOARD', 'GPU', 'RAM', 'SSD', 'PSU', 'CASE', 'TẢN NHIỆT'];
function hasUsableProductPrice(item) {
  const price = Number(item?.price);
  return Number.isFinite(price) && price > 0;
}
function hasMarketProductPrice(item) {
  return hasUsableProductPrice(item) && item?.priceSource === 'market';
}
async function buildView(build) {
  const catalog = await sqlModels.listProducts({ areaId: build.areaId });
  const catalogById = new Map(catalog.map((item) => [item.id, item]));
  const components = Object.fromEntries(
    componentTypes.map((type) => [type, catalogById.get(build.components[type]) || null])
  );
  const selected = Object.values(components).filter(Boolean);
  const priced = selected.filter(hasUsableProductPrice);
  const total = priced.reduce((sum, item) => sum + Number(item.price), 0);
  const power = powerAssessment(selected);
  return {
    ...build,
    version: Number(build.version || 1),
    syncState: 'synced',
    components,
    totalPrice: total,
    priceComplete: selected.every(hasUsableProductPrice),
    missingPriceCount: selected.length - priced.length,
    priceEstimate: priced.some((item) => item.priceSource !== 'market'),
    completion: Math.round(selected.length / componentTypes.length * 100),
    estimatedPower: power.estimatedLoadW,
    recommendedPsu: power.recommendedPsuW,
    powerAssessment: power,
    powerDetails: selected.map((item) => ({ id: item.id, name: item.name, watts: Number(item.power || 0), type: item.type }))
  };
}
function compatibility(components, catalog = []) {
  const catalogById = new Map(catalog.map((item) => [item.id, item]));
  const items = Object.entries(components || {}).map(([type, productId]) => {
    const item = catalogById.get(String(productId));
    return item?.type === type ? item : null;
  }).filter(Boolean);
  const selectedIds = new Set(items.map((item) => item.id));
  const issues = [];
  const cpu = items.find((item) => item?.type === 'CPU');
  const board = items.find((item) => item?.type === 'MAINBOARD');
  const ram = items.find((item) => item?.type === 'RAM');
  const psu = items.find((item) => item?.type === 'PSU');
  const gpu = items.find((item) => item?.type === 'GPU');
  const box = items.find((item) => item?.type === 'CASE');
  const cooler = items.find((item) => item?.type === 'TẢN NHIỆT');
  const power = powerAssessment(items);
  const powerBasis = power.manufacturerMinimumW && power.recommendedPsuW === power.manufacturerMinimumW
    ? `mức PSU hãng khuyến nghị ${power.manufacturerMinimumW}W`
    : `mức hệ thống đề nghị ${power.recommendedPsuW}W${power.manufacturerMinimumW ? ` (mức hãng là ${power.manufacturerMinimumW}W)` : ''}`;
  const caseFitsBoard = caseSupportsBoardForm(box?.form, board?.form);
  const validCpuBoardSocket = Boolean(cpu?.socket && board?.socket);
  const validBoardRam = Boolean(board?.ram && ram?.ram);
  const validGpuLength = Number.isFinite(Number(gpu?.length)) && Number.isFinite(Number(box?.gpuLength));
  const validCaseForm = Boolean(board?.form && box?.form);
  if (validCpuBoardSocket && cpu.socket !== board.socket) issues.push({ code: 'SOCKET', severity: 'error', message: `Socket không khớp: ${cpu.name} dùng ${cpu.socket}, còn ${board.name} là ${board.socket}.` });
  if (validBoardRam && board.ram !== ram.ram) issues.push({ code: 'RAM', severity: 'error', message: `Chuẩn RAM không khớp: mainboard hỗ trợ ${board.ram}, còn RAM đang chọn là ${ram.ram}.` });
  if (psu && power.selectedPsuW == null) {
    issues.push({ code: 'PSU', severity: 'warning', message: `Catalog chưa có công suất xác nhận cho ${psu.name}; cần kiểm tra nhãn PSU trước khi kết luận có đủ ${power.recommendedPsuW}W.` });
  } else if (psu && power.selectedPsuW < power.recommendedPsuW) {
    const shortfall = power.recommendedPsuW - Number(power.selectedPsuW || 0);
    const gpuName = power.manufacturerGpuNames.join(', ');
    issues.push({ code: 'PSU', severity: 'warning', message: `Nguồn ${psu.name} (${power.selectedPsuW || 'chưa xác định'}W) thiếu ${shortfall}W so với ${powerBasis}${gpuName && power.recommendedPsuW === power.manufacturerMinimumW ? ` cho ${gpuName}` : ''}.` });
  }
  if (validGpuLength && Number(gpu.length) > Number(box.gpuLength)) issues.push({ code: 'CASE_SIZE', severity: 'error', message: `GPU dài ${gpu.length}mm, vượt khoảng trống ${box.gpuLength}mm của case.` });
  if (cpu?.socket && cooler?.socket && cpu.socket !== cooler.socket) issues.push({ code: 'COOLER_SOCKET', severity: 'error', message: `Tản nhiệt hỗ trợ ${cooler.socket}, không khớp socket ${cpu.socket} của CPU.` });
  if (validCaseForm && !caseFitsBoard) issues.push({ code: 'CASE_FORM', severity: 'error', message: `Mainboard ${board.form} không vừa case ${box.form}.` });
  const recommendations = [];
  const recommendationIds = new Set();
  const addRecommendations = (type, predicate, reason) => {
    catalog
      .filter((item) => item.type === type && hasUsableProductPrice(item) && !selectedIds.has(item.id) && !recommendationIds.has(item.id) && predicate(item))
      .sort((a, b) => Number(a.price || 0) - Number(b.price || 0))
      .slice(0, 3)
      .forEach((item) => {
        recommendationIds.add(item.id);
        recommendations.push({ ...item, recommendationReason: reason });
      });
  };
  if (gpu && (!psu || power.selectedPsuW == null || power.selectedPsuW < power.recommendedPsuW)) {
    addRecommendations('PSU', (item) => psuRatedWatts(item) >= power.recommendedPsuW,
      `Công suất từ ${power.recommendedPsuW}W để đạt mức đề nghị cho cấu hình.`);
  }
  if (cpu && board && cpu.socket !== board.socket) {
    addRecommendations('MAINBOARD', (item) => item.socket === cpu.socket,
      `Socket ${cpu.socket} tương thích với CPU đang chọn.`);
  }
  if (board && ram && board.ram && ram.ram && board.ram !== ram.ram) {
    addRecommendations('RAM', (item) => item.ram === board.ram,
      `Chuẩn ${board.ram} được mainboard hỗ trợ.`);
  }
  if (cpu && cooler && cpu.socket && cooler.socket && cpu.socket !== cooler.socket) {
    addRecommendations('TẢN NHIỆT', (item) => !item.socket || item.socket === cpu.socket,
      `Hỗ trợ socket ${cpu.socket} của CPU.`);
  }
  if (board && box && validCaseForm && !caseFitsBoard) {
    addRecommendations('CASE', (item) => caseSupportsBoardForm(item.form, board.form),
      `Hỗ trợ mainboard form factor ${board.form}.`);
  }
  if (gpu && box && validGpuLength && Number(gpu.length) > Number(box.gpuLength)) {
    addRecommendations('CASE', (item) => Number(item.gpuLength || 0) >= Number(gpu.length),
      `Khoảng trống GPU ít nhất ${gpu.length}mm.`);
  }
  const psuDetail = psu
    ? power.selectedPsuW == null
      ? `Chưa xác minh được công suất của ${psu.name} trong SQL; cần kiểm tra nhãn nguồn.`
      : power.selectedPsuW >= power.recommendedPsuW
      ? `Nguồn đang chọn ${psu.name}, đạt ${powerBasis} (dư ${power.marginW}W so với mức đề nghị hệ thống).`
      : `Nguồn đang chọn ${psu.name}, thiếu ${Math.abs(power.marginW)}W so với ${powerBasis}.`
    : `Chưa chọn PSU. Nên dùng nguồn tối thiểu ${power.recommendedPsuW}W.`;
  const criteria = [
    {
      code: 'SOCKET',
      severity: 'error',
      status: validCpuBoardSocket ? (cpu.socket === board.socket ? 'pass' : 'error') : 'unchecked',
      comparedFields: ['CPU.socket', 'MAINBOARD.socket'],
      assumptions: [],
      detail: validCpuBoardSocket ? `CPU ${cpu.socket}; mainboard ${board.socket}.` : 'Chọn CPU và mainboard có socket trong catalog để kiểm tra.',
      remediation: 'Chọn mainboard cùng socket với CPU.'
    },
    {
      code: 'RAM',
      severity: 'error',
      status: validBoardRam ? (board.ram === ram.ram ? 'pass' : 'error') : 'unchecked',
      comparedFields: ['MAINBOARD.ram', 'RAM.ram'],
      assumptions: [],
      detail: validBoardRam ? `Mainboard ${board.ram}; RAM ${ram.ram}.` : !ram || !board ? 'Chọn cả mainboard và RAM để kiểm tra chuẩn bộ nhớ.' : `Đã chọn mainboard và RAM, nhưng SQL chưa có chuẩn bộ nhớ cho ${!board.ram ? board.name : ram.name}.`,
      remediation: 'Chọn RAM đúng chuẩn mà mainboard hỗ trợ.'
    },
    {
      code: 'PSU',
      severity: 'warning',
      status: psu ? (power.selectedPsuW != null && power.selectedPsuW >= power.recommendedPsuW ? 'pass' : 'warning') : 'unchecked',
      comparedFields: ['PSU.watts', 'GPU.recommendedPsuW', 'estimatedLoadW'],
      assumptions: ['Tải CPU/GPU lấy từ catalog; mức PSU của GPU lấy theo nhà sản xuất khi SQL có dữ liệu.'],
      detail: `${psuDetail} Tải CPU/GPU ước tính ${power.estimatedLoadW}W; cách tính: ${power.method}.`,
      source: power.sourceEntry,
      remediation: `Chọn PSU từ ${power.recommendedPsuW}W trở lên; đối chiếu nhãn công suất và dây cấp nguồn của GPU.`
    },
    {
      code: 'CASE_SIZE',
      severity: 'error',
      status: validGpuLength ? (Number(gpu.length) <= Number(box.gpuLength) ? 'pass' : 'error') : 'unchecked',
      comparedFields: ['GPU.length', 'CASE.gpuLength'],
      assumptions: [],
      detail: validGpuLength ? `GPU ${gpu.length}mm; case hỗ trợ tối đa ${box.gpuLength}mm.` : 'Chưa đủ dữ liệu chiều dài GPU hoặc khoảng trống case trong SQL.',
      remediation: 'Chọn case có khoảng trống GPU phù hợp.'
    },
    {
      code: 'COOLER_SOCKET',
      severity: 'error',
      status: cpu && cooler && cooler.socket ? (cpu.socket === cooler.socket ? 'pass' : 'error') : 'unchecked',
      comparedFields: ['CPU.socket', 'TẢN NHIỆT.socket'],
      assumptions: cooler && !cooler.socket ? ['SQL chưa có socket hỗ trợ của tản nhiệt.'] : [],
      detail: cpu && cooler?.socket ? `CPU ${cpu.socket}; tản nhiệt hỗ trợ ${cooler.socket}.` : !cpu || !cooler ? 'Chọn cả CPU và tản nhiệt để kiểm tra socket.' : `Đã chọn tản nhiệt ${cooler.name}, nhưng SQL chưa có socket hỗ trợ để đối chiếu.`,
      remediation: 'Chọn tản nhiệt hỗ trợ socket của CPU.'
    },
    {
      code: 'CASE_FORM',
      severity: 'error',
      status: validCaseForm ? (caseFitsBoard ? 'pass' : 'error') : 'unchecked',
      comparedFields: ['MAINBOARD.form', 'CASE.form'],
      assumptions: [],
      detail: validCaseForm ? `Mainboard ${board.form}; case ${box.form}.` : 'Chưa đủ dữ liệu form factor của mainboard hoặc case.',
      remediation: 'Chọn case hỗ trợ kích thước mainboard.'
    }
  ];
  const checkedCriteria = criteria.filter((item) => item.status !== 'unchecked');
  const hasUnchecked = criteria.some((item) => item.status === 'unchecked');
  const status = issues.some((item) => item.severity === 'error')
    ? 'incompatible'
    : issues.length
      ? 'warning'
      : hasUnchecked || !checkedCriteria.length ? 'partial' : 'compatible';
  return {
    status,
    selectedCount: selectedIds.size,
    score: checkedCriteria.length
      ? Math.max(0, Math.round(((checkedCriteria.length - issues.length) / checkedCriteria.length) * 100))
      : null,
    issues,
    estimatedPower: power.estimatedLoadW,
    recommendedPsu: power.recommendedPsuW,
    powerAssessment: power,
    recommendations,
    criteria,
    checkedAt: new Date().toISOString(),
    rulesVersion: 'catalog-v1'
  };
}

async function route(req, res) {
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
    // Check for existing email
    const existing = await sqlModels.findUserByEmail(email);
    if (existing) {
      return send(res, 409, { error: 'EMAIL_EXISTS', message: 'Email này đã được đăng ký.' });
    }
    const user = {
      id: id('user'),
      name,
      email,
      areaId: body.areaId || 'hcm',
      preferences: { pricePreference: true, priceNotifications: true },
      passwordHash: crypto.createHash('sha256').update(password).digest('hex')
    };
    await sqlModels.createUser(user);
    // Welcome notification
    await sqlModels.createAlert({
      id: id('alert'),
      userId: user.id,
      productId: '', // none
      targetPrice: 0,
      areaId: user.areaId
    }).catch(()=>{}); // ignore if not needed
    return send(res, 201, { user: publicUser(user) });


  }
  if (method === 'POST' && parts.join('/') === 'api/v1/auth/login') {
    const email = String(body.email || '').trim().toLowerCase();
    const hash = crypto.createHash('sha256').update(body.password || '').digest('hex');
    const user = await sqlModels.findUserByEmail(email);
    if (!user || user.passwordHash !== hash) return send(res, 401, { error: 'INVALID_CREDENTIALS', message: 'Email hoặc mật khẩu không đúng. Nếu chưa có tài khoản, hãy đăng ký trước.' });
    return send(res, 200, { accessToken: createAccessToken(user), tokenType: 'Bearer', expiresIn: JWT_EXPIRES_IN, user: publicUser(user) });
  }
  if (method === 'POST' && parts.join('/') === 'api/v1/auth/forgot-password') {
    const email = String(body.email || '').trim().toLowerCase();
    if (!email || !email.includes('@')) return send(res, 422, { error: 'INVALID_EMAIL', message: 'Email không hợp lệ.' });
    // In a real implementation we would create a password reset token in the DB and email it.
    // For now we simply acknowledge the request to avoid exposing user existence.
    return send(res, 202, { accepted: true, message: 'Nếu email tồn tại, hướng dẫn khôi phục đã được gửi.' });
  }

  if (method === 'POST' && parts.join('/') === 'api/v1/auth/reset-password') {
    const token = String(body.token || '');
    const password = String(body.password || '');
    // Password reset not implemented in relational version; respond with generic success.
    return send(res, 200, { ok: true, message: 'Password reset endpoint is not implemented in this version.' });
  }
  if (method === 'GET' && parts.join('/') === 'api/v1/areas') { const areas = await sqlModels.listAreas(); return send(res, 200, areas); }
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
    const areas = await sqlModels.listAreas();
          const area = areas.find((item) => item.id === body.areaId)
            || areas.find((item) => item.id === nearest?.id)
            || areas[0];
    return send(res, 200, {
      area,
      source: hasCoordinates ? 'gps' : body.areaId ? 'manual' : 'unresolved',
      coordinates: hasCoordinates ? coordinates : null
    });
  }
  if (method === 'GET' && parts.join('/') === 'api/v1/market/summary') {
    const areaId = url.searchParams.get('areaId') || 'hcm';
        const area = (await sqlModels.listAreas()).find(a => a.id === areaId) || (await sqlModels.listAreas())[0];
        const marketRows = await sqlModels.marketSummary(area.id);
        const productsAll = await sqlModels.listProducts({ areaId: area.id });
        const marketProducts = productsAll.filter(hasMarketProductPrice);
        const items = marketProducts.map(item => {
          const priceInfo = marketRows.find(m => m.productId === item.id) || { price: item.price, previous: item.price };
          const previousPrice = Number(priceInfo.previous) || Number(item.price) || 1;
          const trend = Number((((Number(priceInfo.price) - previousPrice) / previousPrice) * 100).toFixed(2));
          return { productId: item.id, name: item.name, price: priceInfo.price, previousPrice: priceInfo.previous, trend };
        });
        await sqlModels.recordMarketSnapshots(area.id, items);
        const viewer = await auth(req);
        if (viewer) {
          await sqlModels.notifyPriceMovements(viewer.id, area.id, items);
          await sqlModels.triggerPriceAlerts(viewer.id, area.id, items);
        }
        return send(res, 200, { area, updatedAt: new Date().toISOString(), source: 'backend-market-catalog', items });
  }
  if (method === 'GET' && parts.join('/') === 'api/v1/products') { const type = url.searchParams.get('type'); const q = (url.searchParams.get('q') || '').trim().toLowerCase(); const maxPrice = Number(url.searchParams.get('maxPrice') || 0); const areaId = url.searchParams.get('areaId') || 'hcm'; const filters = { type, q, maxPrice, areaId }; const products = await sqlModels.listProducts(filters); return send(res, 200, products); }
  if (method === 'GET' && parts.join('/') === 'api/v1/compare') {
    const ids = [...new Set((url.searchParams.get('productIds') || '').split(',').map((value) => value.trim()).filter(Boolean))];
    if (ids.length < 2 || ids.length > 3) return send(res, 422, { error: 'INVALID_COMPARE_COUNT', message: 'Cần so sánh từ 2 đến 3 sản phẩm.' });
    const areaId = url.searchParams.get('areaId') || 'hcm';
    const products = (await Promise.all(ids.map(id => sqlModels.getProductById(id, areaId)))).filter(Boolean);
    if (products.length !== ids.length) return send(res, 404, { error: 'PRODUCT_NOT_FOUND' });
    return send(res, 200, {
      products,
      fields: ['name', 'type', 'price', 'priceSource', 'power', 'socket', 'ram', 'form', 'length', 'watts'],
      updatedAt: new Date().toISOString(),
      source: 'backend-market-catalog'
    });
  }
  if (method === 'GET' && parts[0] === 'api' && parts[1] === 'v1' && parts[2] === 'products' && parts[3]) { const item = await sqlModels.getProductById(parts[3]); return item ? send(res, 200, item) : send(res, 404, { error: 'PRODUCT_NOT_FOUND' }); }
  if (method === 'GET' && parts[0] === 'api' && parts[1] === 'v1' && parts[2] === 'prices') {
    const productId = url.searchParams.get('productId');
    const areaId = url.searchParams.get('areaId') || 'hcm';
    const period = ['day', 'month', 'year'].includes(url.searchParams.get('period')) ? url.searchParams.get('period') : 'day';
    const item = await sqlModels.getProductById(productId, areaId);
    if (!item) return send(res, 404, { error: 'PRODUCT_NOT_FOUND' });
    const marketRows = await sqlModels.marketSummary(areaId);
    const priceInfo = marketRows.find((row) => row.productId === item.id) || { price: item.price, previous: item.price };
    const changePercent = Number((((priceInfo.price - priceInfo.previous) / priceInfo.previous) * 100).toFixed(2));
    const hasMarketPrice = hasMarketProductPrice(item);
    if (hasMarketPrice) await sqlModels.recordMarketSnapshots(areaId, [{ productId, price: priceInfo.price }]);
    const history = hasMarketPrice ? await sqlModels.priceHistory(productId, areaId, period) : [];
    return send(res, 200, {
      productId,
      areaId,
      period,
      price: priceInfo.price,
      previousPrice: hasMarketPrice ? priceInfo.previous : null,
      changePercent: hasMarketPrice ? changePercent : null,
      priceSource: item.priceSource,
      updatedAt: new Date().toISOString(),
      history
    });
  }

  // Debug endpoint to inspect authenticated user
  if (method === 'GET' && parts.join('/') === 'api/v1/debug/me') {
    const dbgUser = await requireAuth(req, res);
    if (!dbgUser) return send(res, 401, { error: 'UNAUTHORIZED', message: 'Bearer token required.' });
    return send(res, 200, publicUser(dbgUser));
  }

  const user = await requireAuth(req, res); if (!user) return;
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
    await sqlModels.updateUserPassword(
      user.id,
      crypto.createHash('sha256').update(newPassword).digest('hex')
    );
    return send(res, 200, { ok: true, message: 'Đã đổi mật khẩu.' });
  }
  if (method === 'PUT' && parts.join('/') === 'api/v1/auth/me') {
    const name = body.name === undefined ? user.name : String(body.name).trim();
    const areaId = body.areaId === undefined ? user.areaId : String(body.areaId);
    if (name.length < 2) return send(res, 422, { error: 'INVALID_NAME', message: 'Tên người dùng tối thiểu 2 ký tự.' });
    const areas = await sqlModels.listAreas();
    if (!areas.some((area) => area.id === areaId)) return send(res, 422, { error: 'INVALID_AREA', message: 'Khu vực không hợp lệ.' });
    const fields = { name, areaId };
    if (body.preferences && typeof body.preferences === 'object') {
      let currentPreferences = user.preferences || {};
      if (typeof currentPreferences === 'string') {
        try {
          currentPreferences = JSON.parse(currentPreferences);
        } catch {
          currentPreferences = {};
        }
      }
      fields.preferences = {
        ...currentPreferences,
        ...(body.preferences.pricePreference === undefined
          ? {}
          : { pricePreference: Boolean(body.preferences.pricePreference) }),
        ...(body.preferences.priceNotifications === undefined
          ? {}
          : { priceNotifications: Boolean(body.preferences.priceNotifications) })
      };
    }
    const updatedUser = await sqlModels.updateUser(user.id, fields);
    return send(res, 200, publicUser(updatedUser));
  }
  if (method === 'GET' && parts.join('/') === 'api/v1/auth/me') {
    return send(res, 200, publicUser(user));
  }
  if (method === 'GET' && parts.join('/') === 'api/v1/notifications') {
    const notifications = await sqlModels.listNotificationsByUser(user.id);
    return send(res, 200, notifications.sort((a, b) => b.createdAt.localeCompare(a.createdAt)));
  }
  if (method === 'POST' && parts.join('/') === 'api/v1/notifications/read') {
    await sqlModels.markNotificationsRead(user.id);
    return send(res, 200, { ok: true });
  }
  if (method === 'POST' && parts.join('/') === 'api/v1/builds') {
    const { randomUUID } = require('crypto');
    const name = String(body.name || 'Build mới').trim();
    const budget = money(body.budget ?? 20000000);
    const areaId = String(body.areaId || user.areaId || '').trim();
    if (name.length < 2 || name.length > 60) {
      return send(res, 422, { error: 'INVALID_BUILD_NAME', message: 'Tên cấu hình phải từ 2 đến 60 ký tự.' });
    }
    const areas = await sqlModels.listAreas();
    if (budget <= 0 || !areas.some((area) => area.id === areaId)) {
      return send(res, 422, { error: 'INVALID_BUILD', message: 'Ngân sách và khu vực hợp lệ là bắt buộc.' });
    }
    const build = await sqlModels.insertBuild({
      id: randomUUID(),
      userId: user.id,
      name,
      budget,
      areaId,
      components: {},
      version: 1,
      status: 'draft',
      updatedAt: new Date().toISOString()
    });
    return send(res, 201, await buildView(build));
  }
  if (method === 'GET' && parts.join('/') === 'api/v1/builds') {
    const builds = await sqlModels.listBuildsByUser(user.id);
    return send(res, 200, await Promise.all(builds.map(buildView)));
  }
  if (parts[0] === 'api' && parts[1] === 'v1' && parts[2] === 'builds' && parts[3]) {
    const build = await sqlModels.getBuildById(parts[3], user.id);
    if (!build) return send(res, 404, { error: 'BUILD_NOT_FOUND' });
    if (method === 'GET') return send(res, 200, await buildView(build));
    if (method === 'DELETE') {
      const deleted = await sqlModels.deleteBuild(build.id, user.id);
      return deleted
        ? send(res, 204, {})
        : send(res, 404, { error: 'BUILD_NOT_FOUND' });
    }
    if (method === 'PUT' && parts.length === 4) {
      if (body.expectedVersion !== undefined && Number(body.expectedVersion) !== Number(build.version || 1)) {
        return send(res, 409, { error: 'BUILD_VERSION_CONFLICT', message: 'Cấu hình đã thay đổi ở nơi khác.', latest: await buildView(build) });
      }
      const fields = { expectedVersion: body.expectedVersion };
      if (body.name !== undefined) {
        const name = String(body.name).trim();
        if (name.length < 2) return send(res, 422, { error: 'INVALID_BUILD_NAME', message: 'Tên cấu hình phải có ít nhất 2 ký tự.' });
        if (name.length > 60) return send(res, 422, { error: 'INVALID_BUILD_NAME', message: 'Tên cấu hình không được dài quá 60 ký tự.' });
        fields.name = name;
      }
      if (body.budget !== undefined) {
        fields.budget = money(body.budget);
        if (fields.budget <= 0) return send(res, 422, { error: 'INVALID_BUILD_BUDGET' });
      }
      if (body.areaId !== undefined) {
        fields.areaId = String(body.areaId);
        const areas = await sqlModels.listAreas();
        if (!areas.some((area) => area.id === fields.areaId)) {
          return send(res, 422, { error: 'INVALID_AREA' });
        }
      }
      const updated = await sqlModels.updateBuild(build.id, user.id, fields);
      if (!updated) {
        const latest = await sqlModels.getBuildById(build.id, user.id);
        return send(res, 409, {
          error: 'BUILD_VERSION_CONFLICT',
          message: 'Cấu hình đã thay đổi ở nơi khác.',
          latest: latest ? await buildView(latest) : null
        });
      }
      return send(res, 200, await buildView(updated));
    }
    if (method === 'PUT' && parts[4] === 'components' && parts[5]) {
      if (body.expectedVersion !== undefined && Number(body.expectedVersion) !== Number(build.version || 1)) {
        return send(res, 409, { error: 'BUILD_VERSION_CONFLICT', message: 'Cấu hình đã thay đổi ở nơi khác.', latest: await buildView(build) });
      }
      const componentType = decodePathPart(parts[5]);
      if (!componentTypes.includes(componentType)) {
        return send(res, 422, { error: 'INVALID_COMPONENT_TYPE', message: 'Loại linh kiện không hợp lệ.' });
      }
      const components = { ...build.components };
      if (body.productId === null || body.productId === undefined || body.productId === '') {
        delete components[componentType];
      } else {
        const item = await sqlModels.getProductById(body.productId, build.areaId);
        if (!item || item.type !== componentType) {
          return send(res, 422, { error: 'INVALID_COMPONENT', message: `Sản phẩm không thuộc loại ${componentType}.` });
        }
        if (!hasUsableProductPrice(item)) {
          return send(res, 422, { error: 'PRICE_UNAVAILABLE', message: 'Sản phẩm chưa có giá SQL nên chưa thể thêm vào cấu hình.' });
        }
        components[componentType] = item.id;
      }
      const updated = await sqlModels.updateBuild(build.id, user.id, {
        components,
        expectedVersion: body.expectedVersion
      });
      if (!updated) {
        const latest = await sqlModels.getBuildById(build.id, user.id);
        return send(res, 409, {
          error: 'BUILD_VERSION_CONFLICT',
          message: 'Cấu hình đã thay đổi ở nơi khác.',
          latest: latest ? await buildView(latest) : null
        });
      }
      return send(res, 200, await buildView(updated));
    }
    if (method === 'POST' && parts[4] === 'duplicate') {
      const name = String(body.name || `${build.name} (bản sao)`).trim();
      if (name.length < 2 || name.length > 60) return send(res, 422, { error: 'INVALID_BUILD_NAME' });
      const copy = {
        id: require('crypto').randomUUID(),
        userId: user.id,
        name,
        budget: build.budget,
        areaId: build.areaId,
        components: { ...build.components },
        version: 1,
        status: build.status || 'draft',
        updatedAt: new Date().toISOString()
      };
      const duplicate = await sqlModels.insertBuild(copy);
      return send(res, 201, await buildView(duplicate));
    }
    if (method === 'POST' && parts[4] === 'check') {
      const catalog = await sqlModels.listProducts({ areaId: build.areaId });
      const report = compatibility(build.components, catalog);
      if (report.selectedCount < 2) return send(res, 422, { error: 'INSUFFICIENT_COMPONENTS', message: 'Cần ít nhất hai linh kiện để kiểm tra tương thích.', selectedCount: report.selectedCount });
      return send(res, 200, report);
    }
  }
  if (method === 'POST' && parts.join('/') === 'api/v1/compatibility/check') {
    const areaId = String(body.areaId || user.areaId || 'hcm');
    const catalog = await sqlModels.listProducts({ areaId });
    const report = compatibility(body.components || {}, catalog);
    if (report.selectedCount < 2) return send(res, 422, { error: 'INSUFFICIENT_COMPONENTS', message: 'Cần ít nhất hai linh kiện để kiểm tra tương thích.', selectedCount: report.selectedCount });
    return send(res, 200, report);
  }
  if (method === 'GET' && parts.join('/') === 'api/v1/scans') {
    const scans = await sqlModels.listScansByUser(user.id);
    return send(res, 200, scans);
  }
  if (method === 'GET' && parts[0] === 'api' && parts[1] === 'v1' && parts[2] === 'scans' && parts[3] && parts.length === 4) {
    const scan = await sqlModels.getScanById(parts[3], user.id);
    return scan ? send(res, 200, scan) : send(res, 404, { error: 'SCAN_NOT_FOUND' });
  }
  if (method === 'DELETE' && parts[0] === 'api' && parts[1] === 'v1' && parts[2] === 'scans' && parts[3] && parts.length === 4) {
    const deleted = await sqlModels.deleteScan(parts[3], user.id);
    return deleted ? send(res, 204, {}) : send(res, 404, { error: 'SCAN_NOT_FOUND' });
  }
  if (method === 'POST' && parts.join('/') === 'api/v1/ai/scan') {
    const imageData = String(body.imageBase64 || '').replace(/^data:[^,]+,/, '');
    const imageMimeType = String(body.imageMimeType || 'image/jpeg').toLowerCase();
    if (!imageData || imageData.length > 6_000_000 || !['image/jpeg', 'image/png', 'image/webp'].includes(imageMimeType)) {
      return send(res, 422, { error: 'INVALID_SCAN_IMAGE', message: 'Ảnh không hợp lệ hoặc vượt quá dung lượng cho phép.' });
    }
    try {
      const catalog = await sqlModels.listProducts({ areaId: user.areaId });
      const system = [
        'Đây là lượt nhận diện ảnh của LM Studio. Phân loại linh kiện và đọc nguyên văn chữ/model/SKU; đồng thời mô tả hãng, họ sản phẩm và đặc điểm nhìn thấy để tìm ứng viên SQL gần giống.',
        'Chỉ nhận một trong tám nhóm linh kiện: CPU, MAINBOARD, GPU, RAM, SSD, PSU, CASE, TẢN NHIỆT.',
        'Không khẳng định model nếu không có bằng chứng. Trả duy nhất JSON: {"componentType":string|null,"visibleText":string,"brand":string|null,"modelFamily":string|null,"visualDescription":string,"confidence":number,"summary":string}.'
      ].join('\n');
      const scanMessages = [
        { role: 'system', content: system },
        { role: 'user', content: [
          { type: 'text', text: 'Phân tích ảnh và đọc nguyên văn nhãn/model/SKU nhìn thấy được.' },
          { type: 'image_url', image_url: { url: `data:${imageMimeType};base64,${imageData}` } }
        ] }
      ];
      const vision = await requestVisionWithLmStudio(
        scanMessages,
        catalog,
        { temperature: 0.1, topP: 0.5, maxTokens: 300, timeoutMs: 240000 }
      );
      const completion = vision.completion;
      const modelText = completionText(completion);
      let recognition;
      try {
        recognition = parseModelJson(modelText);
      } catch {
        recognition = { recognized: false, productId: null, componentType: null, confidence: 0, summary: String(modelText || 'AI chưa nhận diện được sản phẩm.') };
      }
      const confidence = Math.max(0, Math.min(1, Number(recognition.confidence) || 0));
      const rawAnalysis = String(recognition.summary || modelText || 'AI chưa nhận diện được sản phẩm.');
      const analysisSignalsUncertainty = /chưa đủ rõ|không đủ rõ|không chắc|chưa thể xác nhận|chưa xác định|chưa phân biệt|nhiều khả năng|nhiều bản ghi|nhiều sản phẩm|bản ghi cụ thể|có thể là|phân biệt|mơ hồ|không đọc được|không xác định được|uncertain|ambiguous|not sure|cannot confirm/i.test(rawAnalysis);
      const canConfirmFromModel = recognition.recognized === true && confidence >= 0.9 && !analysisSignalsUncertainty;
      let selectedProduct = canConfirmFromModel
        ? catalog.find((item) => item.id === String(recognition.productId || '')) || null
        : null;
      if (canConfirmFromModel && !selectedProduct && recognition.name) {
        const normalizedName = String(recognition.name).trim().toLowerCase();
        selectedProduct = catalog.find((item) => item.name.toLowerCase() === normalizedName) || null;
      }
      const exactMatchNeedsConfirmation = Boolean(
        selectedProduct && !hasVisibleSkuEvidence(selectedProduct, vision.firstVision)
      );
      if (exactMatchNeedsConfirmation) selectedProduct = null;
      const rawExpectedType = String(recognition.componentType || vision.firstVision.componentType || '').toUpperCase();
      const expectedType = ({
        'GRAPHICS CARD': 'GPU',
        'VIDEO CARD': 'GPU',
        VGA: 'GPU',
        MOTHERBOARD: 'MAINBOARD',
        MEMORY: 'RAM',
        COOLER: 'TẢN NHIỆT',
        'CPU COOLER': 'TẢN NHIỆT',
        'POWER SUPPLY': 'PSU',
        'POWER SUPPLY UNIT': 'PSU',
        STORAGE: 'SSD',
        HDD: 'SSD',
        CHASSIS: 'CASE',
        'PC CASE': 'CASE'
      })[rawExpectedType] || rawExpectedType;
      const modelCandidateIds = Array.isArray(recognition.candidateProductIds)
        ? recognition.candidateProductIds.map((value) => String(value))
        : [];
      if (recognition.productId && !selectedProduct) modelCandidateIds.unshift(String(recognition.productId));
      const candidateById = new Map(catalog.map((item) => [item.id, item]));
      const candidateProducts = [];
      const addCandidate = (candidateId) => {
        const candidate = candidateById.get(candidateId);
        if (candidate && (!expectedType || candidate.type === expectedType) && !candidateProducts.some((item) => item.id === candidate.id)) {
          candidateProducts.push(candidate);
        }
      };
      for (const candidate of (vision.candidateCatalog || []).slice(0, 2)) {
        addCandidate(candidate.id);
      }
      for (const candidateId of modelCandidateIds) {
        addCandidate(candidateId);
        if (candidateProducts.length >= 5) break;
      }
      if (selectedProduct) {
        candidateProducts.splice(0, candidateProducts.length, selectedProduct);
      } else {
        for (const candidate of vision.candidateCatalog || []) {
          addCandidate(candidate.id);
          if (candidateProducts.length >= 5) break;
        }
      }
      const candidates = candidateProducts.map((item, index) => ({
        productId: item.id,
        model: item.name,
        confidence: selectedProduct ? confidence : Math.max(0.15, Math.min(0.89, confidence || (0.65 - index * 0.08)))
      }));
      const unverifiedProduct = exactMatchNeedsConfirmation
        ? candidateById.get(String(recognition.productId || ''))
        : null;
      const analysis = selectedProduct
        ? rawAnalysis
        : candidateProducts.length
          ? exactMatchNeedsConfirmation && unverifiedProduct
            ? `Ảnh cho thấy ${expectedType || 'một linh kiện PC'}. AI nghiêng về mẫu ${unverifiedProduct.name}, nhưng model/SKU không nhìn thấy rõ trong ảnh nên chưa xác nhận. Đây là gợi ý trong SQL; hãy chọn mẫu phù hợp để tạo build tương tự.`
            : `${rawAnalysis}\n\nChưa xác nhận chính xác SKU. Đây là các ứng viên gần giống trong SQL; chọn đúng mẫu để tạo build tương tự.`
          : `${rawAnalysis}\n\nChưa tìm thấy ứng viên phù hợp trong catalog SQL. Hãy chụp rõ nhãn/model sản phẩm.`;
      const scan = {
        id: id('scan'),
        userId: user.id,
        status: selectedProduct ? 'recognized' : candidateProducts.length ? 'awaiting_confirmation' : 'unrecognized',
        detectedProductId: selectedProduct?.id || null,
        confirmedByUser: false,
        candidates,
        analysis: analysis.slice(0, 8000),
        imageMimeType,
        imageData,
        createdAt: new Date().toISOString()
      };
      await sqlModels.createScan(scan);
      return send(res, 201, {
        ...scan,
        product: selectedProduct,
        candidateProducts: candidateProducts.map((item, index) => ({
          ...item,
          confidence: candidates[index]?.confidence ?? confidence
        }))
      });
    } catch (error) {
      return send(res, error.statusCode || 502, { error: 'AI_SCAN_FAILED', message: error.message });
    }
  }
  if (method === 'POST' && parts.join('/') === 'api/v1/scans') {
    const candidateIds = Array.isArray(body.candidateProductIds) ? body.candidateProductIds : [];
    const catalog = await sqlModels.listProducts({ areaId: user.areaId });
    const catalogById = new Map(catalog.map((item) => [item.id, item]));
    const candidates = candidateIds.map((candidateId) => catalogById.get(candidateId)).filter(Boolean).map((item) => ({
      productId: item.id,
      model: item.name,
      confidence: Number(body.confidenceByProduct?.[item.id] || body.confidence || 0) || null
    }));
    const detectedProductId = catalogById.get(String(body.confirmedProductId || ''))?.id || null;
    const scan = {
      id: id('scan'),
      userId: user.id,
      status: detectedProductId ? 'confirmed' : (candidates.length ? 'awaiting_confirmation' : 'pending_analysis'),
      detectedProductId,
      candidates,
      confirmedByUser: Boolean(detectedProductId),
      createdAt: new Date().toISOString()
    };
    await sqlModels.createScan(scan);
    return send(res, 201, { ...scan, product: catalogById.get(scan.detectedProductId) || null });
  }
  if (method === 'POST' && parts[0] === 'api' && parts[1] === 'v1' && parts[2] === 'scans' && parts[4] === 'confirm') {
    const scan = await sqlModels.getScanById(parts[3], user.id);
    const catalog = await sqlModels.listProducts({ areaId: user.areaId });
    const selected = catalog.find((item) => item.id === String(body.productId || ''));
    if (!scan) return send(res, 404, { error: 'SCAN_NOT_FOUND' });
    if (!selected || !scan.candidates.some((candidate) => candidate.productId === selected.id)) {
      return send(res, 422, { error: 'INVALID_SCAN_CANDIDATE', message: 'Sản phẩm xác nhận phải nằm trong danh sách nhận diện.' });
    }
    await sqlModels.confirmScan(scan.id, user.id, selected.id);
    const confirmed = await sqlModels.getScanById(scan.id, user.id);
    return send(res, 200, { ...confirmed, product: selected });
  }
  if (method === 'POST' && parts.join('/') === 'api/v1/conversations') {
    const conversation = { id: id('conversation'), userId: user.id };
    await sqlModels.createConversation(conversation);
    const initialMessage = String(body.initialMessage || '').trim();
    if (initialMessage) {
      await sqlModels.addMessage({
        conversationId: conversation.id,
        role: 'assistant',
        content: initialMessage
      });
    }
    return send(res, 201, {
      ...conversation,
      messages: initialMessage ? [{ role: 'assistant', content: initialMessage }] : []
    });
  }
  if (method === 'DELETE' && parts.length === 4 && parts[0] === 'api' && parts[1] === 'v1' && parts[2] === 'conversations') {
    const deleted = await sqlModels.deleteConversation(parts[3], user.id);
    return deleted
      ? send(res, 204, {})
      : send(res, 404, { error: 'CONVERSATION_NOT_FOUND' });
  }
  if (method === 'POST' && parts.join('/') === 'api/v1/ai/chat') {
    const messages = Array.isArray(body.messages) ? body.messages : [];
    if (messages.length === 0) return send(res, 422, { error: 'INVALID_MESSAGES' });
    try {
      const catalog = await sqlModels.listProducts({ areaId: user.areaId });
      const conversation = messages
        .filter((message) => ['user', 'assistant'].includes(message?.role))
        .slice(-10)
        .map(({ role, content }) => ({ role, content }));
      const [examples, builds] = await Promise.all([
        sqlModels.listAiPcExamples(),
        sqlModels.listBuildsByUser(user.id)
      ]);
      const completion = await requestProjectLmStudio([
        { role: 'system', content: pcKnowledgePrompt(catalog, user.areaId, examples, builds[0], conversation) },
        ...conversation
      ], {
        task: 'chat',
        shouldFallback: (candidate) => pcChatNeedsExpertReview(conversation, candidate)
      });
      if (builds[0] && isPowerQuestion(conversation) && completion?.choices?.[0]?.message) {
        completion.choices[0].message.content = formatBuildPowerSummary(builds[0], catalog);
        completion.choices[0].finish_reason = 'stop';
      }
      return send(res, 200, completion);
    } catch (error) {
      return send(res, error.statusCode || 502, {
        error: 'AI_PROVIDER_UNREACHABLE',
        message: error.message
      });
    }
  }
  if (method === 'POST' && parts.join('/') === 'api/v1/ai/generate-build') {
    const budget = Number(body.budget);
    const purpose = String(body.purpose || '').trim();
    const areaId = String(body.areaId || user.areaId || '').trim();
    const areas = await sqlModels.listAreas();
    if (!Number.isFinite(budget) || budget <= 0 || !purpose || !areas.some((area) => area.id === areaId)) {
      return send(res, 422, {
        error: 'INVALID_BUILD_REQUEST',
        message: 'Ngân sách, mục đích và khu vực hợp lệ là bắt buộc.'
      });
    }

    const catalog = await sqlModels.listProducts({ areaId });
    const pricedCatalog = catalog.filter(hasUsableProductPrice);
    const marketCatalog = pricedCatalog.filter(hasMarketProductPrice);
    const pinnedComponents = body.pinnedComponents && typeof body.pinnedComponents === 'object'
      ? body.pinnedComponents
      : {};
    for (const [type, productId] of Object.entries(pinnedComponents)) {
      if (!componentTypes.includes(type) || !catalog.some((item) => item.id === String(productId) && item.type === type)) {
        return send(res, 422, { error: 'INVALID_PINNED_COMPONENT', message: 'Linh kiện được ghim không có trong catalog SQL.' });
      }
      if (!hasUsableProductPrice(catalog.find((item) => item.id === String(productId) && item.type === type))) {
        return send(res, 422, { error: 'PRICE_UNAVAILABLE', message: 'Linh kiện được ghim chưa có giá SQL.' });
      }
    }
    const missingPriceTypes = componentTypes.filter((type) => !pricedCatalog.some((item) => item.type === type));
    if (missingPriceTypes.length) {
      return send(res, 422, {
        error: 'PRICED_CATALOG_INCOMPLETE',
        message: 'Chưa đủ linh kiện có giá SQL để tạo cấu hình.',
        missingTypes: missingPriceTypes
      });
    }
    const sqlBuild = selectSqlBuild(marketCatalog, budget, purpose, areaId, pinnedComponents)
      || selectSqlBuild(pricedCatalog, budget, purpose, areaId, pinnedComponents);
    if (sqlBuild) {
      const catalogById = new Map(catalog.map((item) => [item.id, item]));
      const componentDetails = Object.fromEntries(Object.entries(sqlBuild.components)
        .map(([type, productId]) => [type, catalogById.get(productId) || null]));
      return send(res, 200, { ...sqlBuild, componentDetails });
    }
    const fallbackCatalogById = new Map();
    for (const type of componentTypes) {
      const candidates = pricedCatalog
        .filter((item) => item.type === type)
        .sort((a, b) => Number(a.priceSource !== 'market') - Number(b.priceSource !== 'market') || Number(a.price) - Number(b.price))
        .slice(0, 8);
      for (const item of candidates) fallbackCatalogById.set(item.id, item);
      const pinnedId = pinnedComponents[type];
      const pinned = pinnedId && pricedCatalog.find((item) => item.id === String(pinnedId));
      if (pinned) fallbackCatalogById.set(pinned.id, pinned);
    }
    const fallbackCatalog = [...fallbackCatalogById.values()];
    const prompt = [
      'Bạn là trợ lý xây dựng cấu hình PC. Đây là phương án dự phòng vì catalog SQL chưa tạo được cấu hình phù hợp.',
      `Ngân sách: ${budget} VND. Mục đích: ${purpose}. Khu vực: ${areaId}.`,
      'Chỉ chọn sản phẩm có giá dương từ catalog SQL. Ưu tiên giá thị trường (priceSource=market); giá catalog_estimate chỉ dùng khi không có phương án thị trường phù hợp và phải nêu là ước tính. Phải đủ 8 nhóm linh kiện và tổng không vượt ngân sách. Nếu không thể đáp ứng, trả JSON {"error":"NO_VALID_BUILD"}.',
      `Bắt buộc giữ nguyên các linh kiện này: ${JSON.stringify(pinnedComponents)}.`,
      'Trả về đúng JSON, không markdown, với các trường name, budget, areaId, components và optionalNotes. Giá trị component là product ID, không bịa sản phẩm.',
      `Catalog mẫu có giá (tối đa 8 sản phẩm mỗi nhóm): ${JSON.stringify(fallbackCatalog)}`
    ].join('\n');

    try {
      const response = await requestProjectLmStudio([
        { role: 'system', content: 'Bạn là chuyên gia build PC của PCBUILD, phải chọn chính xác từ catalog SQL và chỉ trả JSON theo yêu cầu.' },
        { role: 'user', content: prompt }
      ], {
        task: 'build',
        requestOptions: { timeoutMs: Number(process.env.LM_STUDIO_TIMEOUT_MS || 240000), temperature: 0.1, maxTokens: 1800 }
      });
      const text = completionText(response);
      if (!text) throw new Error('LM Studio không trả về cấu hình.');
      const generated = parseModelJson(text);
      if (generated?.error === 'NO_VALID_BUILD') {
        return send(res, 422, { error: 'NO_VALID_BUILD', message: 'Catalog SQL chưa có cấu hình tương thích trong ngân sách này.' });
      }
      if (!generated || typeof generated !== 'object' || !generated.components || typeof generated.components !== 'object') {
        throw new Error('LM Studio trả về cấu hình không đúng định dạng.');
      }
      const components = {};
      for (const [type, productId] of Object.entries(generated.components)) {
        const item = fallbackCatalog.find((candidate) => candidate.id === String(productId));
        if (item && item.type === type) components[type] = item.id;
      }
      if (Object.keys(components).length !== componentTypes.length) {
        throw new Error('LM Studio không chọn đủ tám linh kiện hợp lệ trong catalog SQL.');
      }
      for (const [type, productId] of Object.entries(pinnedComponents)) {
        if (components[type] !== String(productId)) throw new Error(`Cấu hình không giữ lại linh kiện ${type} đã ghim.`);
      }
      const totalPrice = Object.values(components).reduce((sum, productId) => sum + Number(fallbackCatalog.find((item) => item.id === productId)?.price || 0), 0);
      const report = compatibility(components, fallbackCatalog);
      if (totalPrice > budget || report.status === 'incompatible') {
        throw new Error('Cấu hình dự phòng vượt ngân sách hoặc không tương thích theo dữ liệu SQL.');
      }
      return send(res, 200, {
        name: String(generated.name || `PC ${purpose}`),
        budget,
        areaId,
        components,
        componentDetails: Object.fromEntries(Object.entries(components)
          .map(([type, productId]) => [type, fallbackCatalog.find((item) => item.id === productId) || null])),
        totalPrice,
        priceEstimate: Object.values(components).some((productId) => fallbackCatalog.find((item) => item.id === productId)?.priceSource !== 'market'),
        optionalNotes: String(generated.optionalNotes || ''),
        source: 'lm_studio_fallback'
      });
    } catch (error) {
      return send(res, 502, { error: 'AI_BUILD_GENERATION_FAILED', message: error.message });
    }
  }
  if (method === 'POST' && parts[0] === 'api' && parts[1] === 'v1' && parts[2] === 'conversations' && parts[4] === 'messages') {
    const conversation = await sqlModels.getConversationById(parts[3], user.id);
    if (!conversation) return send(res, 404, { error: 'CONVERSATION_NOT_FOUND' });
    const message = String(body.message || '').trim();
    if (!message) return send(res, 422, { error: 'INVALID_MESSAGE', message: 'Nội dung tư vấn không được để trống.' });
    await sqlModels.addMessage({
      conversationId: conversation.id,
      role: 'user',
      content: message
    });
    try {
      const history = await sqlModels.listMessages(conversation.id);
      const [catalog, examples, builds] = await Promise.all([
        sqlModels.listProducts({ areaId: user.areaId }),
        sqlModels.listAiPcExamples(),
        sqlModels.listBuildsByUser(user.id)
      ]);
      const completion = await requestProjectLmStudio([
        {
          role: 'system',
          content: pcKnowledgePrompt(catalog, user.areaId, examples, builds[0], history)
        },
        ...history.slice(-10).map(({ role, content }) => ({ role, content }))
      ], {
        task: 'chat',
        shouldFallback: (candidate) => pcChatNeedsExpertReview(history, candidate)
      });
      const answer = completion?.choices?.[0]?.message?.content;
      if (typeof answer !== 'string' || !answer.trim()) {
        return send(res, 502, { error: 'AI_INVALID_RESPONSE', message: 'LM Studio không trả về nội dung hợp lệ.' });
      }
      await sqlModels.addMessage({
        conversationId: conversation.id,
        role: 'assistant',
        content: answer
      });
      return send(res, 200, completion);
    } catch (error) {
      return send(res, error.statusCode || 502, {
        error: 'AI_PROVIDER_UNREACHABLE',
        message: error.message
      });
    }
  }
  if (method === 'POST' && parts.join('/') === 'api/v1/price-alerts') {
    const productId = String(body.productId || '');
    const targetPrice = money(body.targetPrice);
    const areaId = String(body.areaId || user.areaId || '');
    const [item, areas] = await Promise.all([
      sqlModels.getProductById(productId, areaId),
      sqlModels.listAreas()
    ]);
    if (!item || targetPrice <= 0 || !areas.some((area) => area.id === areaId)) {
      return send(res, 422, { error: 'INVALID_PRICE_ALERT', message: 'Sản phẩm, giá mục tiêu và khu vực hợp lệ là bắt buộc.' });
    }
    if (!hasMarketProductPrice(item)) return send(res, 422, { error: 'PRICE_UNAVAILABLE', message: 'Chưa có giá thị trường SQL để theo dõi sản phẩm này.' });
    const alert = {
      id: id('alert'),
      userId: user.id,
      productId,
      targetPrice,
      areaId
    };
    await sqlModels.createAlert(alert);
    return send(res, 201, alert);
  }
  if (method === 'GET' && parts.join('/') === 'api/v1/price-alerts') {
    return send(res, 200, await sqlModels.listAlertsByUser(user.id));
  }
  if (parts[0] === 'api' && parts[1] === 'v1' && parts[2] === 'price-alerts' && parts[3]) {
    if (method === 'DELETE') {
      const deleted = await sqlModels.deleteAlert(parts[3], user.id);
      return deleted ? send(res, 204, {}) : send(res, 404, { error: 'PRICE_ALERT_NOT_FOUND' });
    }
    if (method === 'PUT') {
      const productId = String(body.productId || '');
      const targetPrice = money(body.targetPrice);
      const areaId = String(body.areaId || user.areaId || '');
      const item = await sqlModels.getProductById(productId, areaId);
      const areas = await sqlModels.listAreas();
      if (!item || targetPrice <= 0 || !areas.some((area) => area.id === areaId)) {
        return send(res, 422, { error: 'INVALID_PRICE_ALERT', message: 'Sản phẩm, giá mục tiêu và khu vực hợp lệ là bắt buộc.' });
      }
      if (!hasMarketProductPrice(item)) return send(res, 422, { error: 'PRICE_UNAVAILABLE', message: 'Chưa có giá thị trường SQL để theo dõi sản phẩm này.' });
      const updated = await sqlModels.updateAlert(parts[3], user.id, { productId, targetPrice, areaId });
      return updated ? send(res, 200, updated) : send(res, 404, { error: 'PRICE_ALERT_NOT_FOUND' });
    }
  }
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
    const request = {
      id: id('support'),
      userId: user.id,
      topic: String(body.topic || 'general').slice(0, 100),
      contactEmail: email,
      message,
      status: 'received',
      createdAt: new Date().toISOString()
    };
    await sqlModels.insertSupportRequest(request);
    return send(res, 201, request);
  }
  return send(res, 404, { error: 'NOT_FOUND' });
}

const server = http.createServer((req, res) => route(req, res).catch((error) => send(res, error.statusCode || 500, { error: error.statusCode === 413 ? 'PAYLOAD_TOO_LARGE' : error.statusCode === 400 ? 'INVALID_JSON' : 'INTERNAL_ERROR', message: error.message })));
if (require.main === module) {
  ensureSqlSchema()
    .catch((error) => console.error(`Failed to load API reference data: ${error.message}`))
    .finally(() => server.listen(PORT, '0.0.0.0', () => console.log(`PCBUILD API listening on port ${PORT}`)));
}
module.exports = {
  server,
  route,
  compatibility,
  powerAssessment,
  pcChatNeedsExpertReview,
  scanCompletionMatchesCatalog,
  hasVisibleSkuEvidence,
  hasUsableProductPrice,
  catalogPromptSelection,
  catalogForVisionCandidate,
  selectSqlBuild,
};
