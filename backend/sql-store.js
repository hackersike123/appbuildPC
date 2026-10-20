const sql = require('mssql');

function createSqlStoreFromEnv() {
  if (process.env.PCBUILD_USE_SQL === 'false') return null;
  const required = [
    'MSSQL_SERVER',
    'MSSQL_PORT',
    'MSSQL_DATABASE',
    'MSSQL_USER',
    'MSSQL_PASSWORD'
  ];
  if (required.some((name) => !process.env[name])) {
    if (String(process.env.MSSQL_REQUIRED).toLowerCase() === 'true') {
      throw new Error('MSSQL_REQUIRED=true but one or more MSSQL_* variables are missing.');
    }
    return null;
  }

  const config = {
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

  let poolPromise;
  let pendingSave = Promise.resolve();

  async function pool() {
    poolPromise ??= sql.connect(config);
    return poolPromise;
  }

  async function initialize(seed) {
    const connection = await pool();
    await connection.request().query(`
      IF OBJECT_ID(N'dbo.pcbuild_app_state', N'U') IS NULL
      BEGIN
        CREATE TABLE dbo.pcbuild_app_state (
          state_id INT NOT NULL CONSTRAINT PK_pcbuild_app_state PRIMARY KEY,
          payload NVARCHAR(MAX) NOT NULL,
          updated_at DATETIME2(3) NOT NULL CONSTRAINT DF_pcbuild_app_state_updated_at DEFAULT SYSUTCDATETIME()
        );
      END
    `);
    const result = await connection.request()
      .input('stateId', sql.Int, 1)
      .query('SELECT payload FROM dbo.pcbuild_app_state WHERE state_id = @stateId');
    if (result.recordset.length === 0) {
      await save(seed);
      return structuredClone(seed);
    }
    return JSON.parse(result.recordset[0].payload);
  }

  async function save(state) {
    const connection = await pool();
    await connection.request()
      .input('stateId', sql.Int, 1)
      .input('payload', sql.NVarChar(sql.MAX), JSON.stringify(state))
      .query(`
        MERGE dbo.pcbuild_app_state WITH (HOLDLOCK) AS target
        USING (SELECT @stateId AS state_id, @payload AS payload) AS source
        ON target.state_id = source.state_id
        WHEN MATCHED THEN
          UPDATE SET payload = source.payload, updated_at = SYSUTCDATETIME()
        WHEN NOT MATCHED THEN
          INSERT (state_id, payload) VALUES (source.state_id, source.payload);
      `);
  }

  function queueSave(state) {
    pendingSave = pendingSave.then(() => save(state));
    pendingSave = pendingSave.catch((error) => {
      console.error(`SQL Server persistence failed: ${error.message}`);
      throw error;
    });
    return pendingSave;
  }

  return {
    initialize,
    queueSave,
    flush: () => pendingSave,
    close: async () => {
      await pendingSave;
      if (poolPromise) (await poolPromise).close();
    }
  };
}

module.exports = { createSqlStoreFromEnv };
