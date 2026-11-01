const sqlModels = require('../sql-models');
const crypto = require('node:crypto');
const { send } = require('../http-utils');
const { auth, publicUser } = require('../auth');

module.exports = async function handleAccountRoutes(context) {
  const { req, res, method, url, parts, body, user, id } = context;
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
};
