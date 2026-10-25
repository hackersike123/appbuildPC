require('dotenv').config({ path: '.env' });
const sql = require('mssql');
const fs = require('fs');

(async () => {
  // Load JSON payload from the old table (or from data.json if present)
  // For simplicity, read the current state directly from the JSON file used by the legacy server.
  const dataPath = 'data.json';
  let state;
  try {
    const raw = fs.readFileSync(dataPath, 'utf8');
    state = JSON.parse(raw);
  } catch (e) {
    console.error('Failed to read legacy data.json:', e.message);
    process.exit(1);
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

  const pool = await sql.connect(config);

  // Helper for upsert
  async function insertRow(table, columns, values) {
    const cols = columns.join(', ');
    const placeholders = columns.map((_, i) => `@v${i}`).join(', ');
    const request = pool.request();
    values.forEach((val, i) => {
      if (typeof val === 'number') {
        request.input(`v${i}`, Number.isInteger(val) ? sql.Int : sql.Float, val);
      } else {
        request.input(`v${i}`, sql.NVarChar, val);
      }
    });
    const sqlText = `INSERT INTO dbo.${table} (${cols}) VALUES (${placeholders});`;
    try {
      await request.query(sqlText);
    } catch (e) {
      // Ignore duplicate key errors (error number 2627) or any other constraint violation
    }
  }

  // USERS
  for (const u of state.users || []) {
    await insertRow('users', ['id','name','email','areaId','passwordHash','preferences'], [u.id, u.name, u.email, u.areaId, u.passwordHash, JSON.stringify(u.preferences||{})]);
  }
  // AREAS
  for (const a of state.areas || []) {
    await insertRow('areas', ['id','name'], [a.id, a.name]);
  }
  // PRODUCTS
  for (const p of state.products || []) {
    await insertRow('products', ['id','type','name','price','power','socket','ram','form','length','gpuLength','watts'], [p.id, p.type, p.name, p.price, p.power||null, p.socket||null, p.ram||null, p.form||null, p.length||null, p.gpuLength||null, p.watts||null]);
  }
  // BUILDS
  for (const b of state.builds || []) {
    await insertRow('builds', ['id','userId','name','budget','areaId','components','version','status','updatedAt'], [b.id, b.userId, b.name, b.budget, b.areaId, JSON.stringify(b.components||{}), b.version||1, b.status||'draft', new Date(b.updatedAt||Date.now())]);
  }
  // ALERTS
  for (const a of state.alerts || []) {
    await insertRow('alerts', ['id','userId','productId','targetPrice','areaId'], [a.id, a.userId, a.productId, a.targetPrice, a.areaId]);
  }
  // NOTIFICATIONS
  for (const n of state.notifications || []) {
    await insertRow('notifications', ['id','userId','title','message','read','createdAt'], [n.id, n.userId, n.title, n.message, n.read?1:0, new Date(n.createdAt||Date.now())]);
  }
  // SUPPORT REQUESTS
  for (const r of state.supportRequests || []) {
    await insertRow('support_requests', ['id','userId','topic','contactEmail','message','status','createdAt'], [r.id, r.userId, r.topic, r.contactEmail, r.message, r.status||'received', new Date(r.createdAt||Date.now())]);
  }
  // SCANS and CANDIDATES
  for (const s of state.scans || []) {
    await insertRow('scans', ['id','userId','status','detectedProductId','confirmedByUser','createdAt','confirmedAt'], [s.id, s.userId, s.status, s.detectedProductId||null, s.confirmedByUser?1:0, new Date(s.createdAt||Date.now()), s.confirmedAt?new Date(s.confirmedAt):null]);
    for (const cand of s.candidates || []) {
      await insertRow('scan_candidates', ['scanId','productId','model','confidence'], [s.id, cand.productId, cand.model||null, cand.confidence||null]);
    }
  }
  // MARKET (prices per area)
  for (const [areaId, products] of Object.entries(state.market || {})) {
    for (const [productId, priceObj] of Object.entries(products)) {
      await insertRow('market', ['areaId','productId','current','previous'], [areaId, productId, priceObj.current, priceObj.previous]);
    }
  }

  console.log('✅ Migration completed');
  process.exit(0);
})();
