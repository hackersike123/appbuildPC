const { sql, getPool } = require('./connection');

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

async function getMarketPrice(productId, areaId) {
  const pool = await getPool();
  const result = await pool.request()
    .input('productId', sql.NVarChar, productId)
    .input('areaId', sql.NVarChar, areaId)
    .query('SELECT current_price AS price, previous_price AS previous FROM dbo.market WHERE productId = @productId AND areaId = @areaId');
  return result.recordset[0];
}

// List notifications for a user

module.exports = { marketSummary, recordMarketSnapshots, priceHistory, getMarketPrice };
