const crypto = require('node:crypto');
const nodemailer = require('nodemailer');
const sqlModels = require('./sql-models');
const { send } = require('./http-utils');
const JWT_SECRET = process.env.JWT_SECRET || 'pcbuild-local-development-secret-change-me';
const JWT_EXPIRES_IN = Number(process.env.JWT_EXPIRES_IN || 3600);
const API_ISSUER = 'pcbuild-local-api';
const API_AUDIENCE = 'pcbuild-local-app';
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

module.exports = { base64Url, createAccessToken, verifyAccessToken, auth, requireAuth, publicUser, resetTokenHash, getMailTransport, resetUrlFor, sendPasswordResetEmail, JWT_EXPIRES_IN };
