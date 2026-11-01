const { sql, getPool } = require('./connection');

async function createConversation(conv) {
  const pool = await getPool();
  await pool.request()
    .input('id', sql.NVarChar, conv.id)
    .input('userId', sql.NVarChar, conv.userId)
    .query('INSERT INTO dbo.conversations (id, userId) VALUES (@id, @userId);');
  return conv;
}

async function getConversationById(conversationId, userId) {
  const pool = await getPool();
  const result = await pool.request()
    .input('id', sql.NVarChar, conversationId)
    .input('userId', sql.NVarChar, userId)
    .query('SELECT id, userId FROM dbo.conversations WHERE id = @id AND userId = @userId');
  return result.recordset[0];
}

async function deleteConversation(conversationId, userId) {
  const pool = await getPool();
  const result = await pool.request()
    .input('id', sql.NVarChar, conversationId)
    .input('userId', sql.NVarChar, userId)
    .query('DELETE FROM dbo.conversations WHERE id = @id AND userId = @userId');
  return (result.rowsAffected?.[0] ?? 0) > 0;
}

async function addMessage(message) {
  const pool = await getPool();
  await pool.request()
    .input('conversationId', sql.NVarChar, message.conversationId)
    .input('role', sql.NVarChar, message.role)
    .input('content', sql.NVarChar, message.content)
    .query('INSERT INTO dbo.messages (conversationId, role, content, createdAt) VALUES (@conversationId, @role, @content, SYSUTCDATETIME());');
}

async function listMessages(conversationId) {
  const pool = await getPool();
  const result = await pool.request()
    .input('cid', sql.NVarChar, conversationId)
    .query('SELECT role, content, createdAt FROM dbo.messages WHERE conversationId = @cid ORDER BY createdAt');
  return result.recordset;
}

async function createScan(scan) {
  const pool = await getPool();
  await pool.request()
    .input('id', sql.NVarChar, scan.id)
    .input('userId', sql.NVarChar, scan.userId)
    .input('status', sql.NVarChar, scan.status)
    .input('detectedProductId', sql.NVarChar, scan.detectedProductId)
    .input('confirmedByUser', sql.Bit, Boolean(scan.confirmedByUser))
    .input('confirmedAt', sql.DateTime2, scan.confirmedAt || null)
    .input('analysis', sql.NVarChar(sql.MAX), scan.analysis || null)
    .input('imageMimeType', sql.NVarChar(32), scan.imageMimeType || null)
    .input('imageData', sql.NVarChar(sql.MAX), scan.imageData || null)
    .query(`INSERT INTO dbo.scans
              (id, userId, status, detectedProductId, confirmedByUser, confirmedAt, analysis, imageMimeType, imageData)
            VALUES
              (@id, @userId, @status, @detectedProductId, @confirmedByUser, @confirmedAt, @analysis, @imageMimeType, @imageData);`);
  for (const candidate of scan.candidates || []) {
    await pool.request()
      .input('scanId', sql.NVarChar, scan.id)
      .input('productId', sql.NVarChar, candidate.productId)
      .input('model', sql.NVarChar(200), candidate.model || null)
      .input('confidence', sql.Float, candidate.confidence)
      .query(`INSERT INTO dbo.scan_candidates (scanId, productId, model, confidence)
              VALUES (@scanId, @productId, @model, @confidence);`);
  }
  return scan;
}

async function getScanById(scanId, userId) {
  const pool = await getPool();
  const result = await pool.request()
    .input('id', sql.NVarChar, scanId)
    .input('userId', sql.NVarChar, userId)
    .query('SELECT * FROM dbo.scans WHERE id = @id AND userId = @userId');
  const scan = result.recordset[0];
  if (!scan) return null;
  const candidates = await pool.request()
    .input('scanId', sql.NVarChar, scanId)
    .query('SELECT productId, model, confidence FROM dbo.scan_candidates WHERE scanId = @scanId');
  return { ...scan, candidates: candidates.recordset };
}

async function deleteScan(scanId, userId) {
  const pool = await getPool();
  const result = await pool.request()
    .input('id', sql.NVarChar, scanId)
    .input('userId', sql.NVarChar, userId)
    .query('DELETE FROM dbo.scans WHERE id = @id AND userId = @userId');
  return (result.rowsAffected?.[0] ?? 0) > 0;
}

async function listScansByUser(userId, limit = 50) {
  const pool = await getPool();
  const result = await pool.request()
    .input('userId', sql.NVarChar, userId)
    .input('limit', sql.Int, Math.min(100, Math.max(1, Number(limit) || 50)))
    .query(`SELECT TOP (@limit) s.id, s.userId, s.status, s.detectedProductId,
                   s.confirmedByUser, s.createdAt, s.confirmedAt, s.analysis,
                   CASE WHEN s.imageData IS NULL THEN 0 ELSE 1 END AS hasImage,
                   p.name AS productName, p.type AS productType
            FROM dbo.scans s
            LEFT JOIN dbo.products p ON p.id = s.detectedProductId
            WHERE s.userId = @userId
            ORDER BY s.createdAt DESC`);
  return result.recordset;
}

async function confirmScan(scanId, userId, productId) {
  const pool = await getPool();
  const result = await pool.request()
    .input('scanId', sql.NVarChar, scanId)
    .input('userId', sql.NVarChar, userId)
    .input('productId', sql.NVarChar, productId)
    .query(`UPDATE dbo.scans
            SET detectedProductId = @productId, confirmedByUser = 1,
                status = 'confirmed', confirmedAt = SYSUTCDATETIME()
            WHERE id = @scanId AND userId = @userId`);
  return (result.rowsAffected?.[0] ?? 0) > 0;
}

async function insertSupportRequest(requestData) {
  const pool = await getPool();
  await pool.request()
    .input('id', sql.NVarChar, requestData.id)
    .input('userId', sql.NVarChar, requestData.userId)
    .input('topic', sql.NVarChar(100), requestData.topic)
    .input('contactEmail', sql.NVarChar(255), requestData.contactEmail)
    .input('message', sql.NVarChar(sql.MAX), requestData.message)
    .input('status', sql.NVarChar(32), requestData.status || 'received')
    .query(`INSERT INTO dbo.support_requests (id, userId, topic, contactEmail, message, status)
            VALUES (@id, @userId, @topic, @contactEmail, @message, @status);`);
  return requestData;
}

// MARKET ---------------------------------------------------------------

async function listAiPcExamples(limit = 8) {
  const pool = await getPool();
  const result = await pool.request()
    .input('limit', sql.Int, Math.min(12, Math.max(1, Number(limit) || 8)))
    .query(`SELECT TOP (@limit) topic, userPrompt, assistantResponse
            FROM dbo.ai_pc_examples
            WHERE enabled = 1
            ORDER BY topic, id`);
  return result.recordset;
}

module.exports = { createConversation, getConversationById, deleteConversation, addMessage, listMessages, createScan, getScanById, deleteScan, listScansByUser, confirmScan, insertSupportRequest, listAiPcExamples };
