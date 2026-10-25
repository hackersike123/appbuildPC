// backend/sql-models.js
// Data-access layer for the PCBUILD app using relational tables.

const sql = require('mssql');
const crypto = require('node:crypto');

// Shared connection pool (initialized lazily)
let poolPromise = null;
const PC_AI_EXAMPLES = [
  {
    id: 'scope-pc-only',
    topic: 'scope',
    userPrompt: 'Bạn có thể giúp tôi chọn quà sinh nhật không?',
    assistantResponse: 'Tôi chuyên hỗ trợ cấu hình, linh kiện, nguồn và tương thích PC. Nếu bạn đang chọn linh kiện máy tính, cho tôi biết mục đích và ngân sách nhé.'
  },
  {
    id: 'psu-manufacturer-floor',
    topic: 'power-supply',
    userPrompt: 'Tại sao nguồn 450W có thể chưa đủ dù tổng TDP linh kiện chỉ khoảng 300W?',
    assistantResponse: 'TDP không phải mức tiêu thụ đỉnh của toàn hệ thống. Hãy đối chiếu mức nguồn hệ thống tối thiểu do hãng GPU khuyến nghị trong SQL, cộng dự phòng cho tải biến thiên, rồi so với công suất PSU thực chọn. Nếu SQL thiếu thông số hãng, phải nêu đây chỉ là ước tính.'
  },
  {
    id: 'psu-report-format',
    topic: 'power-supply',
    userPrompt: 'Hãy giải thích kết quả nguồn trong báo cáo tương thích.',
    assistantResponse: 'Nêu riêng tải CPU/GPU ước tính, PSU đang chọn, mức tối thiểu theo hãng GPU nếu có, khoảng dư hoặc thiếu theo watt, và nguồn dữ liệu. Không gọi tải ước tính là công suất PSU khuyến nghị.'
  },
  {
    id: 'compatibility-partial',
    topic: 'compatibility',
    userPrompt: 'Tôi mới chọn CPU và mainboard, còn thiếu các linh kiện khác. Có kiểm tra được không?',
    assistantResponse: 'Có thể kiểm tra các cặp đã chọn, như socket CPU/mainboard. Những tiêu chí cần linh kiện còn thiếu sẽ ghi chưa kiểm tra; không kết luận toàn bộ cấu hình tương thích.'
  },
  {
    id: 'compatibility-evidence',
    topic: 'compatibility',
    userPrompt: 'CPU này có chắc chắn tương thích với mainboard này không?',
    assistantResponse: 'So sánh socket của hai mã sản phẩm trong SQL. Nếu thiếu mã hoặc thiếu socket, nói rõ chưa đủ dữ liệu; không suy đoán chỉ từ tên sản phẩm.'
  },
  {
    id: 'sql-price-only',
    topic: 'catalog-price',
    userPrompt: 'Giá linh kiện này hôm nay bao nhiêu?',
    assistantResponse: 'Chỉ nêu giá SQL hiện tại theo khu vực và thời điểm API trả về. Nếu không có bản ghi giá hoặc lịch sử, nói rõ chưa có dữ liệu thay vì tự ước lượng.'
  },
  {
    id: 'scan-exact-catalog',
    topic: 'product-scan',
    userPrompt: 'Ảnh hộp GPU mờ, bạn có thể đoán model gần giống không?',
    assistantResponse: 'Không tự gán model khi ảnh chưa đủ rõ. Chỉ xác nhận sản phẩm khi khớp một mã trong catalog SQL; nếu chưa chắc, lưu kết quả chưa nhận diện và hỏi người dùng xác nhận.'
  },
  {
    id: 'build-budget',
    topic: 'pc-build',
    userPrompt: 'Tạo PC chơi game trong ngân sách tôi đưa.',
    assistantResponse: 'Chọn mã linh kiện và giá từ SQL, giữ ngân sách, kiểm tra socket, RAM, PSU, chiều dài GPU và form factor. Nếu thiếu dữ liệu hoặc không ghép được cấu hình hợp lệ, nêu giới hạn thay vì bịa linh kiện.'
  }
];

function getPool() {
  if (!poolPromise) {
    const cfg = {
      server: process.env.MSSQL_SERVER,
      port: Number(process.env.MSSQL_PORT),
      user: process.env.MSSQL_USER,
      password: process.env.MSSQL_PASSWORD,
      database: process.env.MSSQL_DATABASE,
      options: {
        encrypt: String(process.env.MSSQL_ENCRYPT).toLowerCase() === 'true',
        trustServerCertificate: String(process.env.MSSQL_TRUST_SERVER_CERTIFICATE).toLowerCase() === 'true'
      },
      connectionTimeout: Number(process.env.MSSQL_CONNECTION_TIMEOUT || 10000),
      requestTimeout: Number(process.env.MSSQL_REQUEST_TIMEOUT || 10000)
    };
    poolPromise = sql.connect(cfg);
  }
  return poolPromise;
}

async function ensureFeatureSchema() {
  const pool = await getPool();
  await pool.request().query(`
    IF COL_LENGTH(N'dbo.scans', N'analysis') IS NULL
      ALTER TABLE dbo.scans ADD analysis NVARCHAR(MAX) NULL;
    IF COL_LENGTH(N'dbo.scans', N'imageMimeType') IS NULL
      ALTER TABLE dbo.scans ADD imageMimeType NVARCHAR(32) NULL;
    IF COL_LENGTH(N'dbo.scans', N'imageData') IS NULL
      ALTER TABLE dbo.scans ADD imageData NVARCHAR(MAX) NULL;
    IF COL_LENGTH(N'dbo.notifications', N'sourceKey') IS NULL
      ALTER TABLE dbo.notifications ADD sourceKey NVARCHAR(128) NULL;
    IF COL_LENGTH(N'dbo.products', N'recommendedPsuW') IS NULL
      ALTER TABLE dbo.products ADD recommendedPsuW INT NULL;
    IF COL_LENGTH(N'dbo.products', N'recommendedPsuSource') IS NULL
      ALTER TABLE dbo.products ADD recommendedPsuSource NVARCHAR(500) NULL;
    IF OBJECT_ID(N'dbo.market_history', N'U') IS NULL
    BEGIN
      CREATE TABLE dbo.market_history (
        areaId NVARCHAR(16) NOT NULL,
        productId NVARCHAR(32) NOT NULL,
        snapshotDate DATE NOT NULL,
        price BIGINT NOT NULL,
        updatedAt DATETIME2(3) NOT NULL CONSTRAINT DF_market_history_updatedAt DEFAULT SYSUTCDATETIME(),
        CONSTRAINT PK_market_history PRIMARY KEY (areaId, productId, snapshotDate)
      );
    END;
  `);
  await pool.request().query(`
    IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = N'UX_notifications_sourceKey' AND object_id = OBJECT_ID(N'dbo.notifications'))
      CREATE UNIQUE INDEX UX_notifications_sourceKey ON dbo.notifications(userId, sourceKey) WHERE sourceKey IS NOT NULL;
    IF OBJECT_ID(N'dbo.ai_pc_examples', N'U') IS NULL
    BEGIN
      CREATE TABLE dbo.ai_pc_examples (
        id NVARCHAR(64) NOT NULL CONSTRAINT PK_ai_pc_examples PRIMARY KEY,
        topic NVARCHAR(64) NOT NULL,
        userPrompt NVARCHAR(1000) NOT NULL,
        assistantResponse NVARCHAR(2000) NOT NULL,
        enabled BIT NOT NULL CONSTRAINT DF_ai_pc_examples_enabled DEFAULT 1,
        createdAt DATETIME2(3) NOT NULL CONSTRAINT DF_ai_pc_examples_createdAt DEFAULT SYSUTCDATETIME()
      );
    END;
  `);
  for (const example of PC_AI_EXAMPLES) {
    await pool.request()
      .input('id', sql.NVarChar(64), example.id)
      .input('topic', sql.NVarChar(64), example.topic)
      .input('userPrompt', sql.NVarChar(1000), example.userPrompt)
      .input('assistantResponse', sql.NVarChar(2000), example.assistantResponse)
      .query(`IF NOT EXISTS (SELECT 1 FROM dbo.ai_pc_examples WHERE id = @id)
              INSERT INTO dbo.ai_pc_examples (id, topic, userPrompt, assistantResponse)
              VALUES (@id, @topic, @userPrompt, @assistantResponse);`);
  }
  await pool.request().query(`
    UPDATE dbo.products SET recommendedPsuW = 550,
      recommendedPsuSource = N'https://www.asus.com/uk/motherboards-components/graphics-cards/dual/dual-rtx4060-o8g/techspec/'
    WHERE id = N'gpu-4060';
    UPDATE dbo.products SET recommendedPsuW = 450,
      recommendedPsuSource = N'https://www.gigabyte.com/id/Graphics-Card/GV-N4060WF2OC-8GD/sp'
    WHERE id = N'gpu-4060-gigabyte';
    UPDATE dbo.products SET recommendedPsuW = 550,
      recommendedPsuSource = N'https://storage-asset.msi.com/datasheet/vga/global/GeForce-RTX-4060-VENTUS-2X-BLACK-8G-OC.pdf'
    WHERE id = N'gpu-4060-msi';
    UPDATE dbo.products SET recommendedPsuW = 600,
      recommendedPsuSource = N'https://www.zotac.com/download/mediadrivers/External/GraphicsCard/3060/Brochure/ZT-A30600E-10M-brochure.pdf'
    WHERE id = N'gpu-3060-zotac' AND recommendedPsuW IS NULL;
    UPDATE dbo.products SET recommendedPsuW = 550,
      recommendedPsuSource = N'https://www.msi.com/Graphics-Card/GeForce-RTX-3060-GAMING-X-TRIO-12G/Specification'
    WHERE id = N'gpu-3060-msi' AND recommendedPsuW IS NULL;
  `);
}

// USERS --------------------------------------------------------------

// -----------------------------------------------------------------
// ADDITIONAL FUNCTIONS
// -----------------------------------------------------------------
async function listAreas() {
  const pool = await getPool();
  const result = await pool.request().query('SELECT id, name FROM dbo.areas ORDER BY name');
  return result.recordset;
}

async function findUserByEmail(email) {
  const pool = await getPool();
  const result = await pool.request()
    .input('email', sql.NVarChar, email)
    .query('SELECT * FROM dbo.users WHERE LOWER(email) = LOWER(@email)');
  return result.recordset[0];
}

async function findUserById(id) {
  const pool = await getPool();
  const result = await pool.request()
    .input('id', sql.NVarChar, id)
    .query('SELECT * FROM dbo.users WHERE id = @id');
  return result.recordset[0];
}

async function createUser(user) {
  const pool = await getPool();
  await pool.request()
    .input('id', sql.NVarChar, user.id)
    .input('name', sql.NVarChar, user.name)
    .input('email', sql.NVarChar, user.email)
    .input('areaId', sql.NVarChar, user.areaId)
    .input('passwordHash', sql.NVarChar, user.passwordHash)
    .input('preferences', sql.NVarChar, JSON.stringify(user.preferences || {}))
    .query(`INSERT INTO dbo.users (id, name, email, areaId, passwordHash, preferences)
            VALUES (@id, @name, @email, @areaId, @passwordHash, @preferences);`);
  return user;
}

async function updateUser(userId, fields) {
  const pool = await getPool();
  const setClauses = [];
  const request = pool.request().input('id', sql.NVarChar, userId);
  if (fields.name !== undefined) {
    setClauses.push('name = @name');
    request.input('name', sql.NVarChar, fields.name);
  }
  if (fields.areaId !== undefined) {
    setClauses.push('areaId = @areaId');
    request.input('areaId', sql.NVarChar, fields.areaId);
  }
  if (fields.preferences !== undefined) {
    setClauses.push('preferences = @preferences');
    request.input('preferences', sql.NVarChar, JSON.stringify(fields.preferences));
  }
  if (fields.passwordHash !== undefined) {
    setClauses.push('passwordHash = @passwordHash');
    request.input('passwordHash', sql.NVarChar, fields.passwordHash);
  }
  if (setClauses.length === 0) return findUserById(userId);
  await request.query(`UPDATE dbo.users SET ${setClauses.join(', ')} WHERE id = @id`);
  return findUserById(userId);
}

async function updateUserPassword(userId, passwordHash) {
  const pool = await getPool();
  await pool.request()
    .input('id', sql.NVarChar, userId)
    .input('passwordHash', sql.NVarChar(64), passwordHash)
    .query('UPDATE dbo.users SET passwordHash = @passwordHash WHERE id = @id');
  return findUserById(userId);
}

// PRODUCTS ------------------------------------------------------------
async function listProducts(filter = {}) {
  const pool = await getPool();
  const areaId = String(filter.areaId || 'hcm');
  let sqlText = `SELECT p.id, p.type, p.name,
      COALESCE(m.current_price, p.price) AS price,
      CASE WHEN COALESCE(m.current_price, 0) > 0 THEN N'market'
           WHEN COALESCE(p.price, 0) > 0 THEN N'catalog_estimate'
           ELSE N'missing' END AS priceSource,
      p.power, p.socket, p.ram, p.form, p.length, p.gpuLength, p.watts,
      p.recommendedPsuW, p.recommendedPsuSource
    FROM dbo.products p
    LEFT JOIN dbo.market m ON m.productId = p.id AND m.areaId = @areaId`;
  const conditions = [];
  const request = pool.request().input('areaId', sql.NVarChar, areaId);
  if (filter.type) { conditions.push('p.type = @type'); request.input('type', sql.NVarChar, filter.type); }
  if (filter.q) {
    const query = filter.q.toLowerCase();
    conditions.push('LOWER(p.name) LIKE @q');
    request.input('q', sql.NVarChar, `%${query}%`);
    if (/^\d+$/.test(query)) {
      conditions.push('LOWER(p.name) NOT LIKE @digitsFollowedByMoreDigits');
      request.input('digitsFollowedByMoreDigits', sql.NVarChar, `%${query}[0-9]%`);
    }
  }
  if (filter.maxPrice) { conditions.push('COALESCE(m.current_price, p.price) > 0 AND COALESCE(m.current_price, p.price) <= @maxPrice'); request.input('maxPrice', sql.BigInt, Number(filter.maxPrice)); }
  if (conditions.length) sqlText += ' WHERE ' + conditions.join(' AND ');
  sqlText += filter.maxPrice
    ? ' ORDER BY COALESCE(m.current_price, p.price), p.name'
    : ' ORDER BY CASE WHEN COALESCE(m.current_price, 0) > 0 THEN 0 ELSE 1 END, CASE WHEN COALESCE(m.current_price, 0) > 0 THEN m.current_price END ASC, CASE WHEN COALESCE(m.current_price, 0) <= 0 THEN p.price END DESC, p.name';
  const result = await request.query(sqlText);
  return result.recordset;
}

// BUILDS --------------------------------------------------------------
function normalizeBuild(build) {
  if (!build) return build;
  let components = build.components;
  if (typeof components === 'string') {
    try {
      components = JSON.parse(components);
    } catch {
      components = {};
    }
  }
  return {
    ...build,
    components: components && typeof components === 'object' && !Array.isArray(components)
      ? components
      : {}
  };
}

async function listBuildsByUser(userId) {
  const pool = await getPool();
  const result = await pool.request()
    .input('uid', sql.NVarChar, userId)
    .query('SELECT * FROM dbo.builds WHERE userId = @uid ORDER BY updatedAt DESC');
  return result.recordset.map(normalizeBuild);
}

async function getBuildById(buildId, userId) {
  const pool = await getPool();
  const result = await pool.request()
    .input('id', sql.NVarChar, buildId)
    .input('userId', sql.NVarChar, userId)
    .query('SELECT * FROM dbo.builds WHERE id = @id AND userId = @userId');
  return normalizeBuild(result.recordset[0]);
}

async function insertBuild(build) {
  const pool = await getPool();
  await pool.request()
    .input('id', sql.NVarChar, build.id)
    .input('userId', sql.NVarChar, build.userId)
    .input('name', sql.NVarChar, build.name)
    .input('budget', sql.BigInt, build.budget)
    .input('areaId', sql.NVarChar, build.areaId)
    .input('components', sql.NVarChar, JSON.stringify(build.components || {}))
    .input('version', sql.Int, build.version ?? 1)
    .input('status', sql.NVarChar, build.status ?? 'draft')
    .query(`INSERT INTO dbo.builds (id, userId, name, budget, areaId, components, version, status, updatedAt)
            VALUES (@id, @userId, @name, @budget, @areaId, @components, @version, @status, SYSUTCDATETIME());`);
  return normalizeBuild(build);
}

async function updateBuild(buildId, userId, fields) {
  const pool = await getPool();
  const setClauses = [];
  const request = pool.request();
  request.input('id', sql.NVarChar, buildId);
  request.input('userId', sql.NVarChar, userId);
  if (fields.name) { setClauses.push('name = @name'); request.input('name', sql.NVarChar, fields.name); }
  if (fields.budget !== undefined) { setClauses.push('budget = @budget'); request.input('budget', sql.BigInt, fields.budget); }
  if (fields.areaId) { setClauses.push('areaId = @areaId'); request.input('areaId', sql.NVarChar, fields.areaId); }
  if (fields.components !== undefined) { setClauses.push('components = @components'); request.input('components', sql.NVarChar, JSON.stringify(fields.components)); }
  // version bump and timestamp
  setClauses.push('version = version + 1');
  setClauses.push('updatedAt = SYSUTCDATETIME()');
  let whereClause = 'id = @id AND userId = @userId';
  if (fields.expectedVersion !== undefined) {
    whereClause += ' AND version = @expectedVersion';
    request.input('expectedVersion', sql.Int, Number(fields.expectedVersion));
  }
  const result = await request.query(`UPDATE dbo.builds SET ${setClauses.join(', ')} WHERE ${whereClause}`);
  if (result.rowsAffected?.[0] === 0) return null;
  return getBuildById(buildId, userId);
}

async function deleteBuild(buildId, userId) {
  const pool = await getPool();
  const result = await pool.request()
    .input('id', sql.NVarChar, buildId)
    .input('userId', sql.NVarChar, userId)
    .query('DELETE FROM dbo.builds WHERE id = @id AND userId = @userId');
  return (result.rowsAffected?.[0] ?? 0) > 0;
}

// ALERTS --------------------------------------------------------------
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
async function marketSummary(areaId) {
  const pool = await getPool();
  const result = await pool.request()
    .input('area', sql.NVarChar, areaId)
    .query('SELECT productId, current_price AS price, previous_price AS previous FROM dbo.market WHERE areaId = @area');
  return result.recordset;
}

async function recordMarketSnapshots(areaId, items) {
  const pool = await getPool();
  for (const item of items) {
    const price = Number(item.price);
    if (!item.productId || !Number.isFinite(price) || price <= 0) continue;
    await pool.request()
      .input('areaId', sql.NVarChar, areaId)
      .input('productId', sql.NVarChar, item.productId)
      .input('price', sql.BigInt, Math.round(price))
      .query(`MERGE dbo.market_history WITH (HOLDLOCK) AS target
              USING (SELECT @areaId AS areaId, @productId AS productId,
                            CAST(SYSUTCDATETIME() AS DATE) AS snapshotDate, @price AS price) AS source
              ON target.areaId = source.areaId
                 AND target.productId = source.productId
                 AND target.snapshotDate = source.snapshotDate
              WHEN MATCHED AND target.price <> source.price THEN
                UPDATE SET price = source.price, updatedAt = SYSUTCDATETIME()
              WHEN NOT MATCHED THEN
                INSERT (areaId, productId, snapshotDate, price)
                VALUES (source.areaId, source.productId, source.snapshotDate, source.price);`);
  }
}

async function priceHistory(productId, areaId, period = 'day') {
  const pool = await getPool();
  const request = pool.request()
    .input('productId', sql.NVarChar, productId)
    .input('areaId', sql.NVarChar, areaId);
  if (period === 'month') {
    return (await request.query(`SELECT DATEFROMPARTS(YEAR(snapshotDate), MONTH(snapshotDate), 1) AS date,
                                        CAST(AVG(CAST(price AS DECIMAL(19, 2))) AS BIGINT) AS price
                                 FROM dbo.market_history
                                 WHERE productId = @productId AND areaId = @areaId
                                   AND snapshotDate >= DATEADD(MONTH, -12, CAST(SYSUTCDATETIME() AS DATE))
                                 GROUP BY YEAR(snapshotDate), MONTH(snapshotDate)
                                 ORDER BY date`)).recordset;
  }
  if (period === 'year') {
    return (await request.query(`SELECT DATEFROMPARTS(YEAR(snapshotDate), 1, 1) AS date,
                                        CAST(AVG(CAST(price AS DECIMAL(19, 2))) AS BIGINT) AS price
                                 FROM dbo.market_history
                                 WHERE productId = @productId AND areaId = @areaId
                                   AND snapshotDate >= DATEADD(YEAR, -5, CAST(SYSUTCDATETIME() AS DATE))
                                 GROUP BY YEAR(snapshotDate)
                                 ORDER BY date`)).recordset;
  }
  return (await request.query(`SELECT snapshotDate AS date, price
                               FROM dbo.market_history
                               WHERE productId = @productId AND areaId = @areaId
                                 AND snapshotDate >= DATEADD(DAY, -30, CAST(SYSUTCDATETIME() AS DATE))
                               ORDER BY snapshotDate`)).recordset;
}

// Additional helpers
async function getProductById(id, areaId = 'hcm') {
  const pool = await getPool();
  const result = await pool.request()
    .input('id', sql.NVarChar, id)
    .input('areaId', sql.NVarChar, areaId)
    .query(`SELECT p.id, p.type, p.name, COALESCE(m.current_price, p.price) AS price,
                   CASE WHEN COALESCE(m.current_price, 0) > 0 THEN N'market'
                        WHEN COALESCE(p.price, 0) > 0 THEN N'catalog_estimate'
                        ELSE N'missing' END AS priceSource,
                   p.power, p.socket, p.ram, p.form, p.length, p.gpuLength, p.watts,
                   p.recommendedPsuW, p.recommendedPsuSource
            FROM dbo.products p
            LEFT JOIN dbo.market m ON m.productId = p.id AND m.areaId = @areaId
            WHERE p.id = @id`);
  return result.recordset[0];
}

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

async function getMarketPrice(productId, areaId) {
  const pool = await getPool();
  const result = await pool.request()
    .input('productId', sql.NVarChar, productId)
    .input('areaId', sql.NVarChar, areaId)
    .query('SELECT current_price AS price, previous_price AS previous FROM dbo.market WHERE productId = @productId AND areaId = @areaId');
  return result.recordset[0];
}

// List notifications for a user
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

module.exports = {


  listAreas,

  findUserByEmail,
  findUserById,
  createUser,
  updateUser,
  updateUserPassword,
  listProducts,
  ensureFeatureSchema,
  listBuildsByUser,
  getBuildById,
  insertBuild,
  updateBuild,
  deleteBuild,
  createAlert,
  listAlertsByUser,
  updateAlert,
  deleteAlert,
  notifyPriceMovements,
  triggerPriceAlerts,
  createConversation,
  getConversationById,
  deleteConversation,
  addMessage,
  listMessages,
  createScan,
  getScanById,
  deleteScan,
  listScansByUser,
  confirmScan,
  marketSummary,
  recordMarketSnapshots,
  priceHistory,
  insertSupportRequest,


  getProductById,
  listAiPcExamples,
  getMarketPrice,

  listNotificationsByUser,
  markNotificationsRead,
};
