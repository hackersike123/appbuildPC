const connection = require('./sql/connection');
const users = require('./sql/users');
const products = require('./sql/products');
const builds = require('./sql/builds');
const alerts = require('./sql/alerts');
const activity = require('./sql/activity');
const market = require('./sql/market');

module.exports = {
  ...users,
  ...products,
  ensureFeatureSchema: connection.ensureFeatureSchema,
  ...builds,
  ...alerts,
  ...activity,
  ...market,
};