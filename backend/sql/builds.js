const { sql, getPool } = require('./connection');

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

module.exports = { normalizeBuild, listBuildsByUser, getBuildById, insertBuild, updateBuild, deleteBuild };
