require('dotenv').config({path:'./backend/.env'});
const sql = require('mssql');
(async() => {
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
  try {
    await sql.connect(cfg);
    const cmds = [];
    const addTable = (name, ddl) => {
      cmds.push(`IF OBJECT_ID(N'dbo.${name}', N'U') IS NULL BEGIN ${ddl} END;`);
    };
    addTable('users', `CREATE TABLE dbo.users (
      id NVARCHAR(64) NOT NULL PRIMARY KEY,
      name NVARCHAR(100) NOT NULL,
      email NVARCHAR(255) NOT NULL UNIQUE,
      areaId NVARCHAR(16) NOT NULL,
      passwordHash NVARCHAR(64) NOT NULL,
      preferences NVARCHAR(MAX) NULL
    );`);
    addTable('areas', `CREATE TABLE dbo.areas (
      id NVARCHAR(16) NOT NULL PRIMARY KEY,
      name NVARCHAR(100) NOT NULL
    );`);
    addTable('products', `CREATE TABLE dbo.products (
      id NVARCHAR(32) NOT NULL PRIMARY KEY,
      type NVARCHAR(32) NOT NULL,
      name NVARCHAR(200) NOT NULL,
      price BIGINT NOT NULL,
      power INT NULL,
      socket NVARCHAR(16) NULL,
      ram NVARCHAR(16) NULL,
      form NVARCHAR(16) NULL,
      length INT NULL,
      gpuLength INT NULL,
      watts INT NULL,
      recommendedPsuW INT NULL,
      recommendedPsuSource NVARCHAR(500) NULL
    );`);
    addTable('builds', `CREATE TABLE dbo.builds (
      id NVARCHAR(64) NOT NULL PRIMARY KEY,
      userId NVARCHAR(64) NOT NULL REFERENCES dbo.users(id) ON DELETE CASCADE,
      name NVARCHAR(200) NOT NULL,
      budget BIGINT NOT NULL,
      areaId NVARCHAR(16) NOT NULL,
      components NVARCHAR(MAX) NULL,
      version INT NOT NULL DEFAULT 1,
      status NVARCHAR(32) NOT NULL DEFAULT 'draft',
      updatedAt DATETIME2(3) NOT NULL DEFAULT SYSUTCDATETIME()
    );`);
    addTable('alerts', `CREATE TABLE dbo.alerts (
      id NVARCHAR(64) NOT NULL PRIMARY KEY,
      userId NVARCHAR(64) NOT NULL REFERENCES dbo.users(id) ON DELETE CASCADE,
      productId NVARCHAR(32) NOT NULL REFERENCES dbo.products(id),
      targetPrice BIGINT NOT NULL,
      areaId NVARCHAR(16) NOT NULL
    );`);
    addTable('conversations', `CREATE TABLE dbo.conversations (
      id NVARCHAR(64) NOT NULL PRIMARY KEY,
      userId NVARCHAR(64) NOT NULL REFERENCES dbo.users(id) ON DELETE CASCADE
    );`);
    addTable('messages', `CREATE TABLE dbo.messages (
      conversationId NVARCHAR(64) NOT NULL REFERENCES dbo.conversations(id) ON DELETE CASCADE,
      role NVARCHAR(16) NOT NULL,
      content NVARCHAR(MAX) NOT NULL,
      createdAt DATETIME2(3) NOT NULL DEFAULT SYSUTCDATETIME(),
      PRIMARY KEY (conversationId, createdAt)
    );`);
    addTable('scans', `CREATE TABLE dbo.scans (
      id NVARCHAR(64) NOT NULL PRIMARY KEY,
      userId NVARCHAR(64) NOT NULL REFERENCES dbo.users(id) ON DELETE CASCADE,
      status NVARCHAR(32) NOT NULL,
      detectedProductId NVARCHAR(32) NULL REFERENCES dbo.products(id),
      confirmedByUser BIT NOT NULL,
      createdAt DATETIME2(3) NOT NULL DEFAULT SYSUTCDATETIME(),
      confirmedAt DATETIME2(3) NULL,
      analysis NVARCHAR(MAX) NULL,
      imageMimeType NVARCHAR(32) NULL,
      imageData NVARCHAR(MAX) NULL
    );`);
    addTable('scan_candidates', `CREATE TABLE dbo.scan_candidates (
      scanId NVARCHAR(64) NOT NULL REFERENCES dbo.scans(id) ON DELETE CASCADE,
      productId NVARCHAR(32) NOT NULL REFERENCES dbo.products(id),
      model NVARCHAR(200) NULL,
      confidence FLOAT NULL,
      PRIMARY KEY (scanId, productId)
    );`);
    addTable('notifications', `CREATE TABLE dbo.notifications (
      id NVARCHAR(64) NOT NULL PRIMARY KEY,
      userId NVARCHAR(64) NOT NULL REFERENCES dbo.users(id) ON DELETE CASCADE,
      title NVARCHAR(200) NOT NULL,
      message NVARCHAR(MAX) NOT NULL,
      read BIT NOT NULL DEFAULT 0,
      createdAt DATETIME2(3) NOT NULL DEFAULT SYSUTCDATETIME(),
      sourceKey NVARCHAR(128) NULL
    );`);
    addTable('support_requests', `CREATE TABLE dbo.support_requests (
      id NVARCHAR(64) NOT NULL PRIMARY KEY,
      userId NVARCHAR(64) NOT NULL REFERENCES dbo.users(id) ON DELETE CASCADE,
      topic NVARCHAR(100) NOT NULL,
      contactEmail NVARCHAR(255) NOT NULL,
      message NVARCHAR(MAX) NOT NULL,
      status NVARCHAR(32) NOT NULL DEFAULT 'received',
      createdAt DATETIME2(3) NOT NULL DEFAULT SYSUTCDATETIME()
    );`);
    addTable('password_reset_tokens', `CREATE TABLE dbo.password_reset_tokens (
      tokenHash NVARCHAR(64) NOT NULL PRIMARY KEY,
      userId NVARCHAR(64) NOT NULL REFERENCES dbo.users(id) ON DELETE CASCADE,
      expiresAt BIGINT NOT NULL,
      usedAt BIGINT NULL
    );`);
    addTable('market', `CREATE TABLE dbo.market (
      areaId NVARCHAR(16) NOT NULL,
      productId NVARCHAR(32) NOT NULL,
      current_price BIGINT NOT NULL,
      previous_price BIGINT NOT NULL,
      PRIMARY KEY (areaId, productId)
    );`);
    addTable('market_history', `CREATE TABLE dbo.market_history (
      areaId NVARCHAR(16) NOT NULL,
      productId NVARCHAR(32) NOT NULL,
      snapshotDate DATE NOT NULL,
      price BIGINT NOT NULL,
      updatedAt DATETIME2(3) NOT NULL DEFAULT SYSUTCDATETIME(),
      PRIMARY KEY (areaId, productId, snapshotDate)
    );`);
    addTable('ai_pc_examples', `CREATE TABLE dbo.ai_pc_examples (
      id NVARCHAR(64) NOT NULL PRIMARY KEY,
      topic NVARCHAR(64) NOT NULL,
      userPrompt NVARCHAR(1000) NOT NULL,
      assistantResponse NVARCHAR(2000) NOT NULL,
      enabled BIT NOT NULL DEFAULT 1,
      createdAt DATETIME2(3) NOT NULL DEFAULT SYSUTCDATETIME()
    );`);
    const batch = cmds.join('\n');
    await sql.query(batch);
    await sql.query(`
      IF COL_LENGTH(N'dbo.scans', N'analysis') IS NULL ALTER TABLE dbo.scans ADD analysis NVARCHAR(MAX) NULL;
      IF COL_LENGTH(N'dbo.scans', N'imageMimeType') IS NULL ALTER TABLE dbo.scans ADD imageMimeType NVARCHAR(32) NULL;
      IF COL_LENGTH(N'dbo.scans', N'imageData') IS NULL ALTER TABLE dbo.scans ADD imageData NVARCHAR(MAX) NULL;
      IF COL_LENGTH(N'dbo.notifications', N'sourceKey') IS NULL ALTER TABLE dbo.notifications ADD sourceKey NVARCHAR(128) NULL;
      IF COL_LENGTH(N'dbo.products', N'recommendedPsuW') IS NULL ALTER TABLE dbo.products ADD recommendedPsuW INT NULL;
      IF COL_LENGTH(N'dbo.products', N'recommendedPsuSource') IS NULL ALTER TABLE dbo.products ADD recommendedPsuSource NVARCHAR(500) NULL;
      IF OBJECT_ID(N'dbo.ai_pc_examples', N'U') IS NULL
        CREATE TABLE dbo.ai_pc_examples (id NVARCHAR(64) NOT NULL PRIMARY KEY, topic NVARCHAR(64) NOT NULL, userPrompt NVARCHAR(1000) NOT NULL, assistantResponse NVARCHAR(2000) NOT NULL, enabled BIT NOT NULL DEFAULT 1, createdAt DATETIME2(3) NOT NULL DEFAULT SYSUTCDATETIME());
    `);
    await sql.query(`
      IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = N'UX_notifications_sourceKey' AND object_id = OBJECT_ID(N'dbo.notifications'))
        CREATE UNIQUE INDEX UX_notifications_sourceKey ON dbo.notifications(userId, sourceKey) WHERE sourceKey IS NOT NULL;
    `);
    console.log('✅ All tables ensured/created');
    await sql.close();
  } catch (e) {
    console.error('❌ Schema error', e.message);
    process.exit(1);
  }
})();
