const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');

const testDbFile = path.join(os.tmpdir(), `pcbuild-local-api-test-${process.pid}.json`);
process.env.PCBUILD_DB_FILE = testDbFile;
const { server, db } = require('./server');

test('register, login, build and compatibility flow', async () => {
  db.users.length = 0;
  db.builds.length = 0;
  await new Promise((resolve) => server.listen(0, resolve));
  const base = `http://localhost:${server.address().port}`;
  const request = (path, options) => fetch(`${base}${path}`, {
    headers: { 'content-type': 'application/json', ...(options?.headers || {}) },
    ...options,
    body: options?.body && JSON.stringify(options.body)
  });

  const register = await request('/api/v1/auth/register', {
    method: 'POST', body: { name: 'Test User', email: 'test@example.com', password: 'password123' }
  });
  assert.equal(register.status, 201);
  const duplicate = await request('/api/v1/auth/register', {
    method: 'POST', body: { name: 'Another User', email: ' TEST@EXAMPLE.COM ', password: 'password123' }
  });
  assert.equal(duplicate.status, 409);
  const invalidRegister = await request('/api/v1/auth/register', {
    method: 'POST', body: { name: 'A', email: 'invalid', password: 'short' }
  });
  assert.equal(invalidRegister.status, 422);
  const login = await request('/api/v1/auth/login', {
    method: 'POST', body: { email: ' TEST@EXAMPLE.COM ', password: 'password123' }
  });
  assert.equal(login.status, 200);
  const { accessToken } = await login.json();
  assert.equal(accessToken.split('.').length, 3);
  const headers = { Authorization: `Bearer ${accessToken}` };
  const invalidAuth = await request('/api/v1/auth/me', {
    method: 'GET', headers: { Authorization: 'Bearer invalid.jwt.token' }
  });
  assert.equal(invalidAuth.status, 401);
  const me = await request('/api/v1/auth/me', { method: 'GET', headers });
  assert.equal(me.status, 200);
  const notifications = await request('/api/v1/notifications', { method: 'GET', headers });
  assert.equal(notifications.status, 200);
  assert.equal((await notifications.json()).length, 1);
  const readNotifications = await request('/api/v1/notifications/read', { method: 'POST', headers, body: {} });
  assert.equal(readNotifications.status, 200);
  const forgot = await request('/api/v1/auth/forgot-password', {
    method: 'POST', body: { email: 'unknown@example.com' }
  });
  assert.equal(forgot.status, 202);
  const resetPage = await request('/reset-password?token=test-reset-token', {
    method: 'GET'
  });
  assert.equal(resetPage.status, 200);
  assert.match(await resetPage.text(), /ĐẶT LẠI MẬT KHẨU/);
  const resetToken = 'test-reset-token';
  db.passwordResetTokens.push({
    tokenHash: require('node:crypto').createHash('sha256').update(resetToken).digest('hex'),
    userId: db.users[0].id,
    expiresAt: Date.now() + 60_000,
    usedAt: null
  });
  const reset = await request('/api/v1/auth/reset-password', {
    method: 'POST', body: { token: resetToken, password: 'newpassword123' }
  });
  assert.equal(reset.status, 200);
  const relogin = await request('/api/v1/auth/login', {
    method: 'POST', body: { email: 'test@example.com', password: 'newpassword123' }
  });
  assert.equal(relogin.status, 200);
  const reusedReset = await request('/api/v1/auth/reset-password', {
    method: 'POST', body: { token: resetToken, password: 'anotherpass123' }
  });
  assert.equal(reusedReset.status, 400);
  const build = await request('/api/v1/builds', {
    method: 'POST', headers, body: { name: 'Test build' }
  });
  assert.equal(build.status, 201);
  const buildBody = await build.json();
  const fetchedBuild = await request(`/api/v1/builds/${buildBody.id}`, { method: 'GET', headers });
  assert.equal(fetchedBuild.status, 200);
  const component = await request(`/api/v1/builds/${buildBody.id}/components/CPU`, {
    method: 'PUT', headers, body: { productId: 'cpu-7600' }
  });
  assert.equal(component.status, 200);
  const cooler = await request(`/api/v1/builds/${buildBody.id}/components/${encodeURIComponent('TẢN NHIỆT')}`, {
    method: 'PUT', headers, body: { productId: 'cooler-ak400' }
  });
  assert.equal(cooler.status, 200);
  assert.equal(cooler.headers.get('content-type').includes('application/json'), true);
  const coolerBody = await cooler.json();
  assert.equal(coolerBody.components['TẢN NHIỆT'].id, 'cooler-ak400');
  const removedCpu = await request(`/api/v1/builds/${buildBody.id}/components/CPU`, {
    method: 'PUT', headers, body: { productId: null }
  });
  assert.equal(removedCpu.status, 200);
  const afterComponentRemoval = await removedCpu.json();
  assert.equal(afterComponentRemoval.components.CPU, null);
  assert.equal(afterComponentRemoval.components['TẢN NHIỆT'].id, 'cooler-ak400');
  const renamed = await request(`/api/v1/builds/${buildBody.id}`, {
    method: 'PUT', headers, body: { name: 'Updated build', budget: 25000000 }
  });
  assert.equal(renamed.status, 200);
  assert.equal((await renamed.json()).name, 'Updated build');
  const listedBuilds = await request('/api/v1/builds', { method: 'GET', headers });
  assert.equal((await listedBuilds.json()).length, 1);
  const products = await request('/api/v1/products?type=GPU', { method: 'GET' });
  assert.ok((await products.json()).length >= 4);
  const compatibility = await request('/api/v1/compatibility/check', {
    method: 'POST', headers, body: { components: { CPU: 'cpu-7600', MAINBOARD: 'mb-b650m' } }
  });
  assert.equal(compatibility.status, 200);
  assert.equal((await compatibility.json()).status, 'compatible');
  const areas = await request('/api/v1/areas', { method: 'GET' });
  assert.equal(areas.status, 200);
  assert.ok((await areas.json()).length >= 3);
  const location = await request('/api/v1/location/resolve', {
    method: 'POST', body: { areaId: 'hanoi' }
  });
  assert.equal((await location.json()).area.id, 'hanoi');
  const market = await request('/api/v1/market/summary?areaId=hcm', { method: 'GET' });
  const hcmMarket = await market.json();
  assert.equal(hcmMarket.items.length, 3);
  const hanoiMarket = await request('/api/v1/market/summary?areaId=hanoi', { method: 'GET' });
  assert.notEqual((await hanoiMarket.json()).items[0].price, hcmMarket.items[0].price);
  const deleted = await request(`/api/v1/builds/${buildBody.id}`, { method: 'DELETE', headers });
  assert.equal(deleted.status, 204);
  const missing = await request(`/api/v1/builds/${buildBody.id}`, { method: 'GET', headers });
  assert.equal(missing.status, 404);
  await new Promise((resolve) => server.close(resolve));
  fs.rmSync(testDbFile, { force: true });
});
