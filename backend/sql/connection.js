// backend/sql-models.js
// Data-access layer for the PCBUILD app using relational tables.

const sql = require('mssql');

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

module.exports = { sql, getPool, ensureFeatureSchema };
