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
  const updatedProfile = await request('/api/v1/auth/me', {
    method: 'PUT',
    headers,
    body: {
      name: 'Updated User',
      areaId: 'hanoi',
      preferences: { pricePreference: false, priceNotifications: true }
    }
  });
  assert.equal(updatedProfile.status, 200);
  const updatedProfileBody = await updatedProfile.json();
  assert.equal(updatedProfileBody.name, 'Updated User');
  assert.equal(updatedProfileBody.preferences.pricePreference, false);
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
  const renamedBody = await renamed.json();
  assert.equal(renamedBody.name, 'Updated build');
  const conflict = await request(`/api/v1/builds/${buildBody.id}`, {
    method: 'PUT', headers, body: { name: 'Stale write', expectedVersion: 1 }
  });
  assert.equal(conflict.status, 409);
  const duplicateBuild = await request(`/api/v1/builds/${buildBody.id}/duplicate`, {
    method: 'POST', headers, body: { name: 'Copied build' }
  });
  assert.equal(duplicateBuild.status, 201);
  assert.equal((await duplicateBuild.json()).name, 'Copied build');
  const listedBuilds = await request('/api/v1/builds', { method: 'GET', headers });
  assert.equal((await listedBuilds.json()).length, 2);
  const products = await request('/api/v1/products?type=GPU', { method: 'GET' });
  assert.ok((await products.json()).length >= 4);
  const comparison = await request('/api/v1/compare?productIds=gpu-4060,gpu-4060-gigabyte', { method: 'GET' });
  assert.equal(comparison.status, 200);
  assert.equal((await comparison.json()).products.length, 2);
  const scan = await request('/api/v1/scans', {
    method: 'POST', headers, body: { candidateProductIds: ['gpu-4060', 'gpu-4060-msi'], confidence: 0.82 }
  });
  assert.equal(scan.status, 201);
  const scanBody = await scan.json();
  assert.equal(scanBody.status, 'awaiting_confirmation');
  const confirmedScan = await request(`/api/v1/scans/${scanBody.id}/confirm`, {
    method: 'POST', headers, body: { productId: 'gpu-4060-msi' }
  });
  assert.equal(confirmedScan.status, 200);
  assert.equal((await confirmedScan.json()).status, 'confirmed');
  const support = await request('/api/v1/support-requests', {
    method: 'POST', headers, body: { message: 'Tôi cần hỗ trợ kiểm tra cấu hình.' }
  });
  assert.equal(support.status, 201);
  const compatibility = await request('/api/v1/compatibility/check', {
    method: 'POST', headers, body: { components: { CPU: 'cpu-7600', MAINBOARD: 'mb-b650m' } }
  });
  assert.equal(compatibility.status, 200);
  assert.equal((await compatibility.json()).status, 'compatible');
  const areas = await request('/api/v1/areas', { method: 'GET' });
  assert.equal(areas.status, 200);
  assert.ok((await areas.json()).length >= 3);
  const location = await request('/api/v1/location/resolve', {
    method: 'POST', body: { lat: 21.0278, lng: 105.8342 }
  });
  const locationBody = await location.json();
  assert.equal(locationBody.area.id, 'hanoi');
  assert.equal(locationBody.source, 'gps');
  const market = await request('/api/v1/market/summary?areaId=hcm', { method: 'GET' });
  const hcmMarket = await market.json();
  assert.ok(hcmMarket.items.length >= 8);
  const hanoiMarket = await request('/api/v1/market/summary?areaId=hanoi', { method: 'GET' });
  assert.notEqual((await hanoiMarket.json()).items[0].price, hcmMarket.items[0].price);
  const deleted = await request(`/api/v1/builds/${buildBody.id}`, { method: 'DELETE', headers });
  assert.equal(deleted.status, 204);
  const missing = await request(`/api/v1/builds/${buildBody.id}`, { method: 'GET', headers });
  assert.equal(missing.status, 404);
  await new Promise((resolve) => server.close(resolve));
  fs.rmSync(testDbFile, { force: true });
});
