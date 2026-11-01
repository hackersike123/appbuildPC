const sqlModels = require('../sql-models');
const { send } = require('../http-utils');
const { money, hasMarketProductPrice, compatibility } = require('../build-service');

module.exports = async function handleMiscRoutes(context) {
  const { req, res, method, url, parts, body, user, id } = context;
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
};
