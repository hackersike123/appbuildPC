require('dotenv').config();

const fs = require('node:fs');
const path = require('node:path');
const sql = require('mssql');

const filePath = process.argv[2] || process.env.PCBUILD_DB_FILE || path.join(__dirname, 'data.json');
const required = ['MSSQL_SERVER', 'MSSQL_PORT', 'MSSQL_DATABASE', 'MSSQL_USER', 'MSSQL_PASSWORD'];
if (required.some((name) => !process.env[name])) {
  throw new Error('Missing MSSQL_* configuration. Set it in backend/.env first.');
}

function mergeById(existing, incoming) {
  const result = Array.isArray(existing) ? [...existing] : [];
  const ids = new Set(result.map((item) => item?.id).filter(Boolean));
  for (const item of Array.isArray(incoming) ? incoming : []) {
    if (!item?.id || !ids.has(item.id)) {
      result.push(item);
      if (item?.id) ids.add(item.id);
    }
  }
  return result;
}

function mergeState(current, imported) {
  const result = { ...current };
  for (const key of [
    'users', 'areas', 'products', 'builds', 'alerts', 'conversations',
    'scans', 'notifications', 'supportRequests', 'passwordResetTokens'
  ]) {
    result[key] = mergeById(current[key], imported[key]);
  }
  result.market = { ...(current.market || {}) };
  for (const [areaId, prices] of Object.entries(imported.market || {})) {
    result.market[areaId] = { ...(result.market[areaId] || {}), ...prices };
  }
  return result;
}

async function main() {
  const imported = JSON.parse(fs.readFileSync(filePath, 'utf8'));
  const pool = await sql.connect({
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
  });
  await pool.request().query(`
    IF OBJECT_ID(N'dbo.pcbuild_app_state', N'U') IS NULL
    CREATE TABLE dbo.pcbuild_app_state (
      state_id INT NOT NULL CONSTRAINT PK_pcbuild_app_state PRIMARY KEY,
      payload NVARCHAR(MAX) NOT NULL,
      updated_at DATETIME2(3) NOT NULL CONSTRAINT DF_pcbuild_app_state_updated_at DEFAULT SYSUTCDATETIME()
    )
  `);
  const stateResult = await pool.request().input('stateId', sql.Int, 1)
    .query('SELECT payload FROM dbo.pcbuild_app_state WHERE state_id = @stateId');
  const current = stateResult.recordset.length
    ? JSON.parse(stateResult.recordset[0].payload)
    : {};
  const merged = mergeState(current, imported);
  await pool.request()
    .input('stateId', sql.Int, 1)
    .input('payload', sql.NVarChar(sql.MAX), JSON.stringify(merged))
    .query(`
      MERGE dbo.pcbuild_app_state WITH (HOLDLOCK) AS target
      USING (SELECT @stateId AS state_id, @payload AS payload) AS source
      ON target.state_id = source.state_id
      WHEN MATCHED THEN UPDATE SET payload = source.payload, updated_at = SYSUTCDATETIME()
      WHEN NOT MATCHED THEN INSERT (state_id, payload) VALUES (source.state_id, source.payload);
    `);
  console.log(JSON.stringify({
    source: filePath,
    imported: {
      users: (imported.users || []).length,
      builds: (imported.builds || []).length,
      products: (imported.products || []).length
    },
    sqlAfterMerge: {
      users: (merged.users || []).length,
      builds: (merged.builds || []).length,
      products: (merged.products || []).length,
      conversations: (merged.conversations || []).length,
      notifications: (merged.notifications || []).length
    }
  }));
  await pool.close();
}

main().catch((error) => {
  console.error(error.message);
  process.exitCode = 1;
});
