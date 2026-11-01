const crypto = require('node:crypto');
const { readBody, send } = require('../http-utils');
const { requireAuth } = require('../auth');
const handleSystemRoutes = require('./system');
const handlePublicRoutes = require('./public');
const handleAccountRoutes = require('./account');
const handleBuildRoutes = require('./builds');
const handleScanRoutes = require('./scans');
const handleAiRoutes = require('./ai');
const handleMiscRoutes = require('./misc');

const privateRoutes = [
  handleAccountRoutes,
  handleBuildRoutes,
  handleScanRoutes,
  handleAiRoutes,
  handleMiscRoutes,
];

const id = (prefix) => prefix + '_' + crypto.randomBytes(8).toString('hex');

async function route(req, res) {
  const url = new URL(req.url, 'http://' + (req.headers.host || 'localhost'));
  const parts = url.pathname.split('/').filter(Boolean);
  const method = req.method;
  const context = { req, res, url, parts, method, id };

  await handleSystemRoutes(context);
  if (res.writableEnded) return;

  let body;
  try {
    if (method !== 'GET' && method !== 'DELETE') body = await readBody(req);
  } catch (error) {
    return send(res, 400, { error: 'BAD_REQUEST', message: error.message });
  }
  context.body = body;

  await handlePublicRoutes(context);
  if (res.writableEnded) return;

  context.user = await requireAuth(req, res);
  if (!context.user) return;

  for (const handleRoute of privateRoutes) {
    await handleRoute(context);
    if (res.writableEnded) return;
  }
  return send(res, 404, { error: 'NOT_FOUND' });
}

module.exports = route;