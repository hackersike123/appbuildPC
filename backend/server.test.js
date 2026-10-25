const { randomBytes } = require('node:crypto');

process.env.JWT_SECRET ??= randomBytes(32).toString('hex');

const test = require('node:test');
const assert = require('node:assert/strict');

const {
  server,
  compatibility,
  powerAssessment,
  pcChatNeedsExpertReview,
  scanCompletionMatchesCatalog,
  hasVisibleSkuEvidence,
  hasUsableProductPrice,
  selectSqlBuild,
  catalogPromptSelection,
  catalogForVisionCandidate
} = require('./server');

test('health and OpenAPI work while debug headers require authentication', async (t) => {
  await new Promise((resolve, reject) => {
    server.once('error', reject);
    server.listen(0, '127.0.0.1', resolve);
  });
  t.after(() => new Promise((resolve) => server.close(resolve)));

  const baseUrl = `http://127.0.0.1:${server.address().port}`;
  const healthResponse = await fetch(`${baseUrl}/health`);
  assert.equal(healthResponse.status, 200);
  assert.deepEqual(await healthResponse.json(), {
    ok: true,
    service: 'pcbuild-local-api'
  });

  const openApiResponse = await fetch(`${baseUrl}/openapi.json`);
  assert.equal(openApiResponse.status, 200);
  const openApi = await openApiResponse.json();
  assert.equal(openApi.openapi, '3.0.3');
  assert.ok(openApi.paths['/api/v1/builds']);

  const debugHeaders = await fetch(`${baseUrl}/api/v1/debug/headers`);
  assert.equal(debugHeaders.status, 401);
  assert.deepEqual(await debugHeaders.json(), {
    error: 'UNAUTHORIZED',
    message: 'Bearer token is required.'
  });
});

test('PSU recommendations honor the GPU maker minimum and explain shortfall', () => {
  const components = [
    { id: 'cpu', type: 'CPU', name: 'CPU thử nghiệm', power: 65 },
    { id: 'gpu', type: 'GPU', name: 'RTX 3060 Twin Edge', power: 170, recommendedPsuW: 600, recommendedPsuSource: 'https://maker.example/gpu.pdf' },
    { id: 'psu', type: 'PSU', name: 'PSU 550W', watts: 550 }
  ];
  const assessment = powerAssessment(components);
  assert.equal(assessment.estimatedLoadW, 235);
  assert.equal(assessment.recommendedPsuW, 600);
  assert.equal(assessment.marginW, -50);
  assert.equal(assessment.marginFromLoadW, 315);
  assert.equal(assessment.marginVsManufacturerW, -50);

  const report = compatibility({ CPU: 'cpu', GPU: 'gpu', PSU: 'psu' }, components);
  assert.equal(report.status, 'warning');
  assert.equal(report.issues[0].code, 'PSU');
  assert.match(report.issues[0].message, /thiếu 50W.*hãng khuyến nghị 600W/);
  assert.match(report.criteria.find((item) => item.code === 'PSU').detail, /PSU 550W.*thiếu 50W/);
});

test('PSU system estimate is not mislabeled as the GPU manufacturer minimum', () => {
  const components = [
    { id: 'cpu', type: 'CPU', name: 'CPU thử nghiệm', power: 65 },
    { id: 'gpu', type: 'GPU', name: 'RTX 4060', power: 500, recommendedPsuW: 550, recommendedPsuSource: 'https://maker.example/4060.pdf' },
    { id: 'psu', type: 'PSU', name: 'PSU 800W', watts: 800 }
  ];
  const report = compatibility({ CPU: 'cpu', GPU: 'gpu', PSU: 'psu' }, components);
  assert.equal(report.powerAssessment.estimatedLoadW, 565);
  assert.equal(report.powerAssessment.recommendedPsuW, 850);
  assert.equal(report.powerAssessment.marginW, -50);
  assert.equal(report.powerAssessment.marginVsManufacturerW, 250);
  assert.match(report.issues[0].message, /thiếu 50W so với mức hệ thống đề nghị 850W \(mức hãng là 550W\)/);
  assert.doesNotMatch(report.issues[0].message, /hãng khuyến nghị 850W/);
});

test('an empty component list reports no estimated or recommended PSU power', () => {
  const assessment = powerAssessment([]);
  assert.equal(assessment.estimatedLoadW, 0);
  assert.equal(assessment.calculatedMinimumW, 0);
  assert.equal(assessment.recommendedPsuW, 0);
  assert.equal(assessment.selectedPsuW, null);
});

test('PSU wattage can be read from its model name and is not counted as system load', () => {
  const components = [
    { id: 'cpu', type: 'CPU', name: 'Ryzen', power: 120, socket: 'AM5' },
    { id: 'gpu', type: 'GPU', name: 'RTX sample', power: 220 },
    { id: 'psu', type: 'PSU', name: 'iStarUSA TC-1200PD8G Gray ATX 1200W Fully Modular', power: 1200 },
    { id: 'board', type: 'MAINBOARD', name: 'Board ATX', socket: 'AM5', form: 'ATX' },
    { id: 'case', type: 'CASE', name: 'Mid Tower', form: 'ATX Mid Tower' }
  ];
  const report = compatibility({ CPU: 'cpu', GPU: 'gpu', PSU: 'psu', MAINBOARD: 'board', CASE: 'case' }, components);
  assert.equal(report.powerAssessment.estimatedLoadW, 340);
  assert.equal(report.powerAssessment.selectedPsuW, 1200);
  assert.equal(report.issues.some((issue) => issue.code === 'PSU'), false);
  assert.equal(report.issues.some((issue) => issue.code === 'CASE_FORM'), false);
});

test('an absent PSU stays unchecked but includes an actionable recommendation', () => {
  const components = [
    { id: 'cpu', type: 'CPU', name: 'CPU thử nghiệm', power: 65, price: 1000000 },
    { id: 'gpu', type: 'GPU', name: 'RTX 4060', power: 115, recommendedPsuW: 550, recommendedPsuSource: 'https://maker.example/4060.pdf', price: 10000000 },
    { id: 'psu-650', type: 'PSU', name: 'PSU 650W', watts: 650, price: 1500000 }
  ];
  const report = compatibility({ CPU: 'cpu', GPU: 'gpu' }, components);
  assert.equal(report.status, 'partial');
  assert.equal(report.powerAssessment.recommendedPsuW, 550);
  assert.equal(report.powerAssessment.selectedPsuW, null);
  assert.equal(report.powerAssessment.marginVsManufacturerW, null);
  assert.equal(report.criteria.find((item) => item.code === 'PSU').status, 'unchecked');
  assert.equal(report.recommendations[0].name, 'PSU 650W');
});

test('high-risk PC questions are sent for expert review when local answers miss required details', () => {
  const answer = (content) => ({ choices: [{ message: { content } }] });
  const question = (content) => [{ role: 'user', content }];

  assert.equal(pcChatNeedsExpertReview(
    question('Dây modular PSU cũ cùng hãng dùng cho PSU mới được không?'),
    answer('Không nên dùng dây cũ nếu chưa rõ model.')
  ), true);
  assert.equal(pcChatNeedsExpertReview(
    question('Dây modular PSU cũ cùng hãng dùng cho PSU mới được không?'),
    answer('Không dùng nếu chưa xác nhận sơ đồ chân pinout theo đúng model PSU.')
  ), false);
  assert.equal(pcChatNeedsExpertReview(
    question('PC có mùi khét và tiếng tách điện, tôi làm gì?'),
    answer('Tắt máy và rút điện ngay, không sử dụng lại, gọi kỹ thuật viên.')
  ), false);
  assert.equal(pcChatNeedsExpertReview(
    question('PC có mùi khét và tiếng tách điện, tôi làm gì?'),
    answer('Tắt máy, mở PSU kiểm tra tụ điện.')
  ), true);
  assert.equal(pcChatNeedsExpertReview(
    question('Gửi tôi đúng file BIOS cho mainboard chưa rõ model.'),
    answer('Chưa thể xác định; cần đúng model/revision và manual của hãng.')
  ), false);
  assert.equal(pcChatNeedsExpertReview(
    question('DDR5 memory training ở lần boot đầu, nên làm gì?'),
    answer('Chờ theo manual và quan sát đèn POST, không ngắt nguồn lặp lại.')
  ), false);
  assert.equal(pcChatNeedsExpertReview(
    question('DDR5 memory training ở lần boot đầu, nên làm gì?'),
    answer('Rút điện rồi chờ 15–30 phút để RAM xả.')
  ), true);
});

test('vision scan only accepts a high-confidence exact catalog product ID', () => {
  const catalog = [{ id: 'gpu-3060-zotac', type: 'GPU', name: 'Zotac RTX 3060 Twin Edge' }];
  const completion = (content) => ({ choices: [{ message: { content } }] });

  assert.equal(scanCompletionMatchesCatalog(completion(
    '{"recognized":true,"productId":"gpu-3060-zotac","confidence":0.98,"summary":"Tem khớp chính xác."}'
  ), catalog), true);
  assert.equal(scanCompletionMatchesCatalog(completion(
    '{"recognized":true,"productId":"gpu-3060-other","confidence":0.99,"summary":"Có vẻ giống."}'
  ), catalog), false);
  assert.equal(scanCompletionMatchesCatalog(completion(
    '{"recognized":true,"productId":"gpu-3060-zotac","confidence":0.7,"summary":"Ảnh chưa đủ rõ."}'
  ), catalog), false);
});

test('vision only confirms an exact GPU SKU when its model number is visibly read', () => {
  const gpu = { id: 'gpu-3060-gigabyte', type: 'GPU', name: 'Gigabyte GeForce RTX 3060 Gaming OC' };
  const gpuTi = { id: 'gpu-5060-ti', type: 'GPU', name: 'ASUS GeForce RTX 5060 Ti OC' };
  assert.equal(hasVisibleSkuEvidence(gpu, { visibleText: 'GIGABYTE GEFORCE RTX' }), false);
  assert.equal(hasVisibleSkuEvidence(gpu, { visibleText: 'GIGABYTE GEFORCE RTX 3060' }), true);
  assert.equal(hasVisibleSkuEvidence(gpuTi, { visibleText: 'ASUS GEFORCE RTX 5060' }), false);
  assert.equal(hasVisibleSkuEvidence(gpuTi, { visibleText: 'ASUS GEFORCE RTX 5060 Ti' }), true);
});

test('zero-price catalog items are not treated as priced products', () => {
  assert.equal(hasUsableProductPrice({ price: 0 }), false);
  assert.equal(hasUsableProductPrice({ price: '0' }), false);
  assert.equal(hasUsableProductPrice({ price: null }), false);
  assert.equal(hasUsableProductPrice({ price: 1250000 }), true);
});

test('SQL build selection ignores zero-price items and marks estimates', () => {
  const parts = [
    { id: 'cpu', type: 'CPU', name: 'CPU', price: 500, socket: 'AM5', power: 65, priceSource: 'market' },
    { id: 'board', type: 'MAINBOARD', name: 'Board', price: 500, socket: 'AM5', ram: 'DDR5', form: 'mATX', priceSource: 'market' },
    { id: 'gpu', type: 'GPU', name: 'GPU', price: 600, power: 170, length: 200, recommendedPsuW: 550, priceSource: 'market' },
    { id: 'ram', type: 'RAM', name: 'RAM', price: 100, ram: 'DDR5', priceSource: 'market' },
    { id: 'ssd', type: 'SSD', name: 'SSD', price: 100, priceSource: 'market' },
    { id: 'psu', type: 'PSU', name: 'PSU', price: 100, watts: 650, priceSource: 'market' },
    { id: 'case', type: 'CASE', name: 'Case', price: 100, form: 'mATX', gpuLength: 260, priceSource: 'market' },
    { id: 'cooler', type: 'TẢN NHIỆT', name: 'Cooler', price: 100, socket: 'AM5', priceSource: 'market' }
  ];
  const zeroPrice = parts.map((item) => ({ ...item, id: `zero-${item.id}`, price: 0 }));

  const marketBuild = selectSqlBuild([...zeroPrice, ...parts], 10000, 'test', 'hcm');
  assert.ok(marketBuild);
  assert.equal(marketBuild.totalPrice, 2100);
  assert.equal(marketBuild.priceEstimate, false);

  const estimatedBuild = selectSqlBuild(
    parts.map((item) => ({ ...item, priceSource: 'catalog_estimate' })),
    10000,
    'test',
    'hcm'
  );
  assert.ok(estimatedBuild);
  assert.equal(estimatedBuild.priceEstimate, true);
});

test('PC chat receives a compact catalog slice that includes matching products', () => {
  const catalog = [
    ...Array.from({ length: 200 }, (_, index) => ({
      id: `cpu-${index}`,
      type: 'CPU',
      name: `CPU model ${index}`,
      price: 2000000 + index,
      priceSource: 'market'
    })),
    ...Array.from({ length: 80 }, (_, index) => ({
      id: `gpu-rtx-4060-${index}`,
      type: 'GPU',
      name: `RTX 4060 model ${index}`,
      price: 10000000 + index,
      priceSource: 'market'
    }))
  ];
  const selected = catalogPromptSelection(
    catalog,
    [{ role: 'user', content: 'Tìm card RTX 4060 trong SQL' }]
  );
  assert.ok(selected.length <= 32);
  assert.ok(selected.some((item) => item.name.includes('RTX 4060')));
  assert.ok(selected.some((item) => item.type === 'GPU'));
});

test('vision catalog context stays bounded and promotes OCR model matches', () => {
  const catalog = [
    ...Array.from({ length: 100 }, (_, index) => ({
      id: `gpu-other-${index}`,
      type: 'GPU',
      name: `GPU unrelated model ${index}`,
      price: 5000000 + index,
      priceSource: 'catalog_estimate'
    })),
    { id: 'gpu-rtx-4060', type: 'GPU', name: 'Gigabyte RTX 4060 Windforce OC', price: 7000000, priceSource: 'market' }
  ];
  const selected = catalogForVisionCandidate(
    { componentType: 'GPU', visibleText: 'Gigabyte RTX 4060 Windforce' },
    catalog
  );
  assert.ok(selected.length <= 80);
  assert.ok(selected.some((item) => item.id === 'gpu-rtx-4060'));
});

test('vision shortlist follows visible GPU family text over a conflicting visual guess', () => {
  const selected = catalogForVisionCandidate(
    { componentType: 'GPU', brand: 'Gigabyte', visibleText: 'GIGABYTE GEFORCE RTX', modelFamily: 'Radeon RX 7600' },
    [
      { id: 'gpu-rx-7600', type: 'GPU', name: 'Gigabyte Radeon RX 7600 Gaming', price: 100 },
      { id: 'gpu-rtx-3050', type: 'GPU', name: 'Gigabyte GeForce RTX 3050 Eagle', price: 200 }
    ]
  );
  assert.equal(selected[0].id, 'gpu-rtx-3050');
});
