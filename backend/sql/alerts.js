const crypto = require('node:crypto');
const { sql, getPool } = require('./connection');
const { findUserById } = require('./users');
const { getProductById } = require('./products');

async function createAlert(alert) {
  const pool = await getPool();
  await pool.request()
    .input('id', sql.NVarChar, alert.id)
    .input('userId', sql.NVarChar, alert.userId)
    .input('productId', sql.NVarChar, alert.productId)
    .input('targetPrice', sql.BigInt, alert.targetPrice)
    .input('areaId', sql.NVarChar, alert.areaId)
    .query(`INSERT INTO dbo.alerts (id, userId, productId, targetPrice, areaId)
            VALUES (@id, @userId, @productId, @targetPrice, @areaId);`);
  return alert;
}

async function listAlertsByUser(userId) {
  const pool = await getPool();
  const result = await pool.request()
    .input('userId', sql.NVarChar, userId)
    .query(`SELECT a.*, p.name AS productName, p.type AS productType,
                   COALESCE(m.current_price, p.price) AS currentPrice
            FROM dbo.alerts a
            JOIN dbo.products p ON p.id = a.productId
            LEFT JOIN dbo.market m ON m.productId = a.productId AND m.areaId = a.areaId
            WHERE a.userId = @userId
            ORDER BY a.id`);
  return result.recordset;
}

async function updateAlert(alertId, userId, fields) {
  const pool = await getPool();
  const result = await pool.request()
    .input('id', sql.NVarChar, alertId)
    .input('userId', sql.NVarChar, userId)
    .input('productId', sql.NVarChar, fields.productId)
    .input('targetPrice', sql.BigInt, fields.targetPrice)
    .input('areaId', sql.NVarChar, fields.areaId)
    .query(`UPDATE dbo.alerts SET productId = @productId, targetPrice = @targetPrice, areaId = @areaId
            WHERE id = @id AND userId = @userId;
            SELECT * FROM dbo.alerts WHERE id = @id AND userId = @userId;`);
  return result.recordset[0] || null;
}

async function deleteAlert(alertId, userId) {
  const pool = await getPool();
  const result = await pool.request()
    .input('id', sql.NVarChar, alertId)
    .input('userId', sql.NVarChar, userId)
    .query('DELETE FROM dbo.alerts WHERE id = @id AND userId = @userId');
  return (result.rowsAffected?.[0] ?? 0) > 0;
}

async function insertNotification(userId, title, message, sourceKey) {
  const pool = await getPool();
  await pool.request()
    .input('id', sql.NVarChar, crypto.randomUUID())
    .input('userId', sql.NVarChar, userId)
    .input('title', sql.NVarChar, title.slice(0, 200))
    .input('message', sql.NVarChar(sql.MAX), message)
    .input('sourceKey', sql.NVarChar(128), sourceKey)
    .query(`IF NOT EXISTS (SELECT 1 FROM dbo.notifications WHERE userId = @userId AND sourceKey = @sourceKey)
            INSERT INTO dbo.notifications (id, userId, title, message, sourceKey)
            VALUES (@id, @userId, @title, @message, @sourceKey);`);
}

async function notifyPriceMovements(userId, areaId, items) {
  const user = await findUserById(userId);
  let preferences = user?.preferences || {};
  if (typeof preferences === 'string') {
    try { preferences = JSON.parse(preferences); } catch { preferences = {}; }
  }
  if (preferences.priceNotifications === false) return;
  const day = new Date().toISOString().slice(0, 10);
  for (const item of items) {
    if (Math.abs(Number(item.trend) || 0) < 3) continue;
    const direction = Number(item.trend) < 0 ? 'giảm' : 'tăng';
    const message = `${item.name}: giá ${direction} ${Math.abs(Number(item.trend)).toFixed(2)}%, hiện ${Number(item.price).toLocaleString('vi-VN')}đ tại ${areaId}.`;
    await insertNotification(userId, 'Biến động giá linh kiện', message, `movement:${areaId}:${item.productId}:${day}`);
  }
}

async function triggerPriceAlerts(userId, areaId, items) {
  const alerts = await listAlertsByUser(userId);
  const pricesById = new Map(items.map((item) => [item.productId, Number(item.price)]));
  for (const alert of alerts) {
    const price = pricesById.get(alert.productId);
    if (alert.areaId !== areaId || !Number.isFinite(price) || price > Number(alert.targetPrice)) continue;
    const item = await getProductById(alert.productId, areaId);
    await insertNotification(
      userId,
      'Đã đạt mức giá mục tiêu',
      `${item?.name || alert.productId} hiện có giá ${price.toLocaleString('vi-VN')}đ, thấp hơn hoặc bằng mức bạn đặt.`,
      `alert:${alert.id}`
    );
    await deleteAlert(alert.id, userId);
  }
}

// CONVERSATIONS & MESSAGES --------------------------------------------

async function listNotificationsByUser(userId) {
  const pool = await getPool();
  const result = await pool.request().input('userId', sql.NVarChar, userId).query('SELECT * FROM dbo.notifications WHERE userId = @userId');
  return result.recordset;
}

// Mark all notifications as read for a user
async function markNotificationsRead(userId) {
  const pool = await getPool();
  await pool.request().input('userId', sql.NVarChar, userId).query('UPDATE dbo.notifications SET read = 1 WHERE userId = @userId');
}

module.exports = { createAlert, listAlertsByUser, updateAlert, deleteAlert, insertNotification, notifyPriceMovements, triggerPriceAlerts, listNotificationsByUser, markNotificationsRead };
