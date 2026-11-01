const { sql, getPool } = require('./connection');

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

module.exports = { listProducts, getProductById };
