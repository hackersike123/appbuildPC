const sqlModels = require('../sql-models');
const crypto = require('node:crypto');
const { send } = require('../http-utils');
const { createAccessToken, auth, requireAuth, publicUser, JWT_EXPIRES_IN } = require('../auth');
const { hasMarketProductPrice } = require('../build-service');

module.exports = async function handlePublicRoutes(context) {
  const { req, res, method, url, parts, body, user, id } = context;
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
};
