require('dotenv').config({path:'./backend/.env'});
const sql = require('mssql');
const fs = require('fs');
(async() => {
  const cfg = {
    server: process.env.MSSQL_SERVER,
    port: Number(process.env.MSSQL_PORT),
    user: process.env.MSSQL_USER,
    password: process.env.MSSQL_PASSWORD,
    database: process.env.MSSQL_DATABASE,
    options: { encrypt: String(process.env.MSSQL_ENCRYPT).toLowerCase() === 'true', trustServerCertificate: String(process.env.MSSQL_TRUST_SERVER_CERTIFICATE).toLowerCase() === 'true' },
    connectionTimeout: 10000,
    requestTimeout: 10000
  };
  await sql.connect(cfg);
  const raw = fs.readFileSync('backend/data.json', 'utf8');
  const state = JSON.parse(raw);
  const exec = async (query, params) => {
    const request = new sql.Request();
    for (const [k, v] of Object.entries(params)) {
      if (v instanceof Date) {
        request.input(k, sql.DateTime2, v);
      } else if (typeof v === 'number') {
        request.input(k, sql.BigInt, v);
      } else if (typeof v === 'boolean') {
        request.input(k, sql.Bit, v ? 1 : 0);
      } else {
        request.input(k, sql.NVarChar, v);
      }
    }
    await request.query(query);
  };
  const safeExec = async (query, params) => {
    try {
      await exec(query, params);
    } catch (e) {
      // Ignore duplicate key errors (2627) and continue
      if (e.originalError && e.originalError.info && e.originalError.info.number === 2627) {
        console.warn('Duplicate key ignored');
      } else {
        console.error('Error executing query:', e.message);
        throw e;
      }
    }
  };
  // USERS
  for (const u of state.users || []) {
    await safeExec(`INSERT INTO dbo.users (id, name, email, areaId, passwordHash, preferences) VALUES (@id, @name, @email, @areaId, @passwordHash, @preferences);`, {
      id: u.id,
      name: u.name,
      email: u.email,
      areaId: u.areaId,
      passwordHash: u.passwordHash,
      preferences: u.preferences ? JSON.stringify(u.preferences) : null
    });
  }
  // AREAS
  for (const a of state.areas || []) {
    await safeExec(`INSERT INTO dbo.areas (id, name) VALUES (@id, @name);`, {id: a.id, name: a.name});
  }
  // PRODUCTS
  for (const p of state.products || []) {
    await safeExec(`INSERT INTO dbo.products (id, type, name, price, power, socket, ram, form, length, gpuLength, watts) VALUES (@id, @type, @name, @price, @power, @socket, @ram, @form, @length, @gpuLength, @watts);`, {
      id: p.id,
      type: p.type,
      name: p.name,
      price: p.price,
      power: p.power ?? null,
      socket: p.socket ?? null,
      ram: p.ram ?? null,
      form: p.form ?? null,
      length: p.length ?? null,
      gpuLength: p.gpuLength ?? null,
      watts: p.watts ?? null
    });
  }
  // BUILDS
  for (const b of state.builds || []) {
    await safeExec(`INSERT INTO dbo.builds (id, userId, name, budget, areaId, components, version, status, updatedAt) VALUES (@id, @userId, @name, @budget, @areaId, @components, @version, @status, @updatedAt);`, {
      id: b.id,
      userId: b.userId,
      name: b.name,
      budget: b.budget,
      areaId: b.areaId,
      components: b.components ? JSON.stringify(b.components) : null,
      version: b.version ?? 1,
      status: b.status ?? 'draft',
      updatedAt: b.updatedAt ? new Date(b.updatedAt) : new Date()
    });
  }
  // ALERTS
  for (const a of state.alerts || []) {
    await safeExec(`INSERT INTO dbo.alerts (id, userId, productId, targetPrice, areaId) VALUES (@id, @userId, @productId, @targetPrice, @areaId);`, {
      id: a.id,
      userId: a.userId,
      productId: a.productId,
      targetPrice: a.targetPrice,
      areaId: a.areaId
    });
  }
  // CONVERSATIONS & MESSAGES
  for (const c of state.conversations || []) {
    await safeExec(`INSERT INTO dbo.conversations (id, userId) VALUES (@id, @userId);`, {id: c.id, userId: c.userId});
    if (Array.isArray(c.messages)) {
      for (const m of c.messages) {
        await safeExec(`INSERT INTO dbo.messages (conversationId, role, content, createdAt) VALUES (@convId, @role, @content, @createdAt);`, {
          convId: c.id,
          role: m.role,
          content: m.content,
          createdAt: m.createdAt ? new Date(m.createdAt) : new Date()
        });
      }
    }
  }
  // SCANS & CANDIDATES
  for (const s of state.scans || []) {
    await safeExec(`INSERT INTO dbo.scans (id, userId, status, detectedProductId, confirmedByUser, createdAt, confirmedAt) VALUES (@id, @userId, @status, @detectedProductId, @confirmedByUser, @createdAt, @confirmedAt);`, {
      id: s.id,
      userId: s.userId,
      status: s.status,
      detectedProductId: s.detectedProductId ?? null,
      confirmedByUser: s.confirmedByUser ? 1 : 0,
      createdAt: s.createdAt ? new Date(s.createdAt) : new Date(),
      confirmedAt: s.confirmedAt ? new Date(s.confirmedAt) : null
    });
    if (Array.isArray(s.candidates)) {
      for (const c of s.candidates) {
        await safeExec(`INSERT INTO dbo.scan_candidates (scanId, productId, model, confidence) VALUES (@scanId, @productId, @model, @confidence);`, {
          scanId: s.id,
          productId: c.productId,
          model: c.model ?? null,
          confidence: c.confidence ?? null
        });
      }
    }
  }
  // NOTIFICATIONS
  for (const n of state.notifications || []) {
    await safeExec(`INSERT INTO dbo.notifications (id, userId, title, message, is_read, createdAt) VALUES (@id, @userId, @title, @message, @is_read, @createdAt);`, {
      id: n.id,
      userId: n.userId,
      title: n.title,
      message: n.message,
      is_read: n.read ? 1 : 0,
      createdAt: n.createdAt ? new Date(n.createdAt) : new Date()
    });
  }
  // SUPPORT REQUESTS
  for (const r of state.supportRequests || []) {
    await safeExec(`INSERT INTO dbo.support_requests (id, userId, topic, contactEmail, message, status, createdAt) VALUES (@id, @userId, @topic, @contactEmail, @message, @status, @createdAt);`, {
      id: r.id,
      userId: r.userId,
      topic: r.topic,
      contactEmail: r.contactEmail,
      message: r.message,
      status: r.status ?? 'received',
      createdAt: r.createdAt ? new Date(r.createdAt) : new Date()
    });
  }
  // PASSWORD RESET TOKENS
  for (const t of state.passwordResetTokens || []) {
    await safeExec(`INSERT INTO dbo.password_reset_tokens (tokenHash, userId, expiresAt, usedAt) VALUES (@tokenHash, @userId, @expiresAt, @usedAt);`, {
      tokenHash: t.tokenHash,
      userId: t.userId,
      expiresAt: t.expiresAt,
      usedAt: t.usedAt ?? null
    });
  }
  // MARKET
  for (const [areaId, prods] of Object.entries(state.market || {})) {
    for (const [productId, priceObj] of Object.entries(prods)) {
      await safeExec(`INSERT INTO dbo.market (areaId, productId, [current_price], [previous_price]) VALUES (@areaId, @productId, @current, @previous);`, {
        areaId,
        productId,
        current: priceObj.current,
        previous: priceObj.previous
      });
    }
  }
  console.log('✅ Migration completed');
  await sql.close();
})();
