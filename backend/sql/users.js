const { sql, getPool } = require('./connection');

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

module.exports = { listAreas, findUserByEmail, findUserById, createUser, updateUser, updateUserPassword };
