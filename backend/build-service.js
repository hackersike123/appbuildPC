const sqlModels = require('./sql-models');
const money = (value) => Math.round(Number(value) || 0);

function catalogPromptSelection(catalog, messages = [], activeBuild = null, limit = 32) {
  const userText = messages
    .filter((message) => message?.role === 'user')
    .slice(-3)
    .map((message) => String(message.content || ''))
    .join(' ')
    .toLowerCase();
  const tokens = userText.split(/[^a-z0-9]+/i).filter((token) => token.length >= 3);
  const typeTerms = new Map([
    ['GPU', ['gpu', 'rtx', 'geforce', 'radeon', 'arc', 'vga']],
    ['CPU', ['cpu', 'ryzen', 'intel', 'xeon', 'processor']],
    ['MAINBOARD', ['mainboard', 'motherboard', 'bo mach', 'b650', 'x670', 'am5', 'lga']],
    ['RAM', ['ram', 'ddr4', 'ddr5', 'memory']],
    ['SSD', ['ssd', 'nvme', 'm.2']],
    ['PSU', ['psu', 'nguon', 'nguồn', 'watt']],
    ['CASE', ['case', 'vo may', 'vỏ máy']],
    ['TẢN NHIỆT', ['tan nhiet', 'tản nhiệt', 'cooler', 'aio']]
  ]);
  const requestedTypes = new Set();
  for (const [type, terms] of typeTerms) {
    if (terms.some((term) => userText.includes(term))) requestedTypes.add(type);
  }
  const ranked = catalog.map((item) => {
    const name = String(item.name || '').toLowerCase();
    const id = String(item.id || '').toLowerCase();
    let score = requestedTypes.has(item.type) ? 4 : 0;
    if (name && userText.includes(name)) score += 100;
    if (id && userText.includes(id)) score += 100;
    for (const token of tokens) {
      if (name.includes(token) || id.includes(token)) score += 8;
    }
    if (hasMarketProductPrice(item)) score += 1;
    return { item, score };
  }).sort((a, b) => b.score - a.score || Number(a.item.price) - Number(b.item.price));

  const selected = new Map();
  const add = (item) => {
    if (item?.id && selected.size < limit) selected.set(item.id, item);
  };
  if (activeBuild?.components) {
    for (const productId of Object.values(activeBuild.components)) {
      add(catalog.find((item) => item.id === productId));
    }
  }
  const typesToSeed = requestedTypes.size ? requestedTypes : new Set([...typeTerms.keys()]);
  for (const type of typesToSeed) {
    for (const { item } of ranked.filter(({ item }) => item.type === type).slice(0, 3)) add(item);
  }
  for (const { item } of ranked) {
    if (selected.size >= limit) break;
    add(item);
  }
  return [...selected.values()];
}

function pcKnowledgePrompt(catalog, areaId, examples = [], activeBuild = null, messages = []) {
  const facts = catalogPromptSelection(catalog, messages, activeBuild).map(({ id: productId, type, name, price, priceSource, power, watts, socket, ram, form, length, gpuLength, recommendedPsuW, recommendedPsuSource }) => ({
    id: productId, type, name, price: Number(price), priceSource, power, watts, socket, ram, form, length, gpuLength, recommendedPsuW, recommendedPsuSource
  }));
  const examplesText = examples.map((item) => `Chủ đề: ${item.topic}\nNgười dùng: ${item.userPrompt}\nCách trả lời: ${item.assistantResponse}`).join('\n\n');
  const buildParts = activeBuild
    ? Object.entries(activeBuild.components || {}).map(([type, productId]) => catalog.find((item) => item.id === productId && item.type === type)).filter(Boolean)
    : [];
  const buildPower = activeBuild ? powerAssessment(buildParts) : null;
  const buildText = activeBuild
    ? `Build SQL gần nhất và số điện đã tính sẵn (không tự tính lại): ${JSON.stringify({ name: activeBuild.name, budget: activeBuild.budget, components: buildParts.map((item) => ({ type: item.type, name: item.name, powerTdpW: Number(item.power || 0), psuCapacityW: Number(item.watts || 0), gpuManufacturerPsuW: item.recommendedPsuW || null })), power: buildPower, totalPrice: buildParts.reduce((sum, item) => sum + Number(item.price || 0), 0) })}`
    : 'Tài khoản chưa có build SQL hiện tại.';
  return [
    'Bạn là PCBuild Coach, trợ lý CHỈ phục vụ cấu hình, linh kiện, nguồn, tương thích, nâng cấp, khắc phục lỗi PC và nhận diện sản phẩm PC.',
    'Luôn trả lời bằng tiếng Việt, ngắn gọn, nêu kết luận trước rồi mới nêu lý do. Nếu câu hỏi ngoài PC, từ chối lịch sự và hướng người dùng về PC.',
    'SQL là nguồn duy nhất cho tên/mã sản phẩm, giá khu vực, mức PSU hãng khuyến nghị và cấu hình tài khoản. Không bịa giá, lịch sử giá, thông số hay linh kiện.',
    'Khi đánh giá PSU, chỉ chép số từ powerAssessment: estimatedLoadW là tải; recommendedPsuW là mức đề nghị hệ thống; selectedPsuW là PSU đã chọn; marginW là chênh so với recommendedPsuW; marginFromLoadW là chênh so với tải; marginVsManufacturerW là chênh so với mức hãng. Dấu dương là dư, dấu âm là thiếu. Nếu manufacturerMinimumW hoặc marginVsManufacturerW null thì SQL không có mức hãng: không được ghi một con số dưới nhãn “PSU hãng khuyến nghị” và không được nêu số dư/thiếu theo hãng. Không lấy recommendedPsuW hay marginW thay cho dữ liệu hãng. Không tự tính lại, đổi định nghĩa, thêm phần trăm hoặc nhận xét ngoài dữ liệu.',
    'Khi đánh giá tương thích: chỉ kết luận những cặp có đủ thông số SQL; linh kiện hoặc thông số còn thiếu phải ghi “chưa kiểm tra/chưa đủ dữ liệu”, tuyệt đối không gọi là đạt.',
    'Khi quét ảnh: chỉ xác nhận model khi khớp catalog SQL; nếu ảnh mờ hoặc chưa chắc, nói rõ và không tự tạo mã sản phẩm.',
    'Nếu không thể đưa câu trả lời PC hữu ích, có căn cứ từ ngữ cảnh, hãy trả chính xác __PCBUILD_NEED_EXPERT__ để lượt chuyên gia dự phòng kiểm tra; không dùng dấu này chỉ vì SQL thiếu giá hoặc thông số mà cần được giữ ở trạng thái chưa xác nhận.',
    `Ví dụ hướng dẫn đã duyệt từ SQL:\n${examplesText || 'Không có ví dụ bổ sung.'}`,
    buildText,
    `Khu vực tài khoản: ${areaId}. Catalog SQL rút gọn theo câu hỏi: ${JSON.stringify(facts)}`
  ].join('\n\n');
}

function psuRatedWatts(item) {
  const explicit = Number(item?.watts);
  if (Number.isFinite(explicit) && explicit > 0) return explicit;
  const match = String(item?.name || '').match(/\b(\d{3,4})\s*W\b/i);
  return match ? Number(match[1]) : 0;
}

function normalizeFormFactor(value) {
  const normalized = String(value || '').toLowerCase().replace(/[^a-z0-9]+/g, ' ').trim();
  if (/e ?atx|extended atx/.test(normalized)) return 'eatx';
  if (/micro ?atx|\bmatx\b/.test(normalized)) return 'matx';
  if (/mini ?itx|\bitx\b/.test(normalized)) return 'itx';
  if (/\batx\b/.test(normalized)) return 'atx';
  return normalized;
}

function caseSupportsBoardForm(caseForm, boardForm) {
  const box = normalizeFormFactor(caseForm);
  const board = normalizeFormFactor(boardForm);
  const supportedBoards = {
    eatx: ['eatx', 'atx', 'matx', 'itx'],
    atx: ['atx', 'matx', 'itx'],
    matx: ['matx', 'itx'],
    itx: ['itx']
  };
  return Boolean(box && board && supportedBoards[box]?.includes(board));
}

function powerAssessment(items) {
  const selected = items.filter(Boolean);
  const estimatedLoadW = selected.filter((item) => item.type !== 'PSU')
    .reduce((sum, item) => sum + Math.max(0, Number(item.power || 0)), 0);
  const gpus = selected.filter((item) => item.type === 'GPU');
  const manufacturerMinimumW = gpus.reduce((maximum, gpu) => Math.max(maximum, Number(gpu.recommendedPsuW || 0)), 0);
  const calculatedMinimumW = selected.length ? Math.ceil((estimatedLoadW * 1.3 + 100) / 50) * 50 : 0;
  const recommendedPsuW = selected.length ? Math.max(450, calculatedMinimumW, manufacturerMinimumW) : 0;
  const selectedPsu = selected.filter((item) => item.type === 'PSU').sort((a, b) => psuRatedWatts(a) - psuRatedWatts(b))[0] || null;
  const selectedPsuW = selectedPsu ? psuRatedWatts(selectedPsu) || null : null;
  const sourceEntry = gpus.find((gpu) => gpu.recommendedPsuW && gpu.recommendedPsuSource);
  return {
    estimatedLoadW,
    calculatedMinimumW,
    manufacturerMinimumW: manufacturerMinimumW || null,
    manufacturerGpuNames: gpus.filter((gpu) => gpu.recommendedPsuW).map((gpu) => gpu.name),
    manufacturerSources: [...new Set(gpus.map((gpu) => gpu.recommendedPsuSource).filter(Boolean))],
    recommendedPsuW,
    selectedPsuW,
    selectedPsuName: selectedPsu?.name || null,
    marginW: selectedPsuW == null ? null : selectedPsuW - recommendedPsuW,
    marginFromLoadW: selectedPsuW == null ? null : selectedPsuW - estimatedLoadW,
    marginVsManufacturerW: selectedPsuW == null || !manufacturerMinimumW ? null : selectedPsuW - manufacturerMinimumW,
    sourceEntry: sourceEntry ? { gpuName: sourceEntry.name, url: sourceEntry.recommendedPsuSource } : null,
    method: !selected.length
      ? 'Chưa chọn linh kiện; chưa tính công suất.'
      : manufacturerMinimumW
      ? 'max(mức PSU tối thiểu trong SQL của GPU, tải CPU/GPU × 1,3 + 100W dự phòng, 450W)'
      : 'max(tải CPU/GPU × 1,3 + 100W dự phòng, 450W)'
  };
}

function formatBuildPowerSummary(build, catalog) {
  const components = Object.entries(build.components || {})
    .map(([type, productId]) => catalog.find((item) => item.id === productId && item.type === type))
    .filter(Boolean);
  const power = powerAssessment(components);
  const formatMargin = (margin) => margin == null
    ? 'chưa đủ dữ liệu để tính'
    : margin >= 0 ? `dư ${margin} W` : `thiếu ${Math.abs(margin)} W`;
  const selected = power.selectedPsuW == null
    ? 'Chưa chọn PSU trong build SQL.'
    : `PSU đang chọn: ${power.selectedPsuName} (${power.selectedPsuW} W).`;
  const manufacturer = power.manufacturerMinimumW == null
    ? 'Mức PSU hãng khuyến nghị: SQL chưa có dữ liệu cho GPU trong build.'
    : `Mức PSU hãng khuyến nghị: ${power.manufacturerMinimumW} W${power.manufacturerGpuNames.length ? ` (${power.manufacturerGpuNames.join(', ')})` : ''}.`;
  const manufacturerMargin = power.marginVsManufacturerW == null
    ? 'Dư/thiếu so với mức hãng: chưa đủ dữ liệu để tính.'
    : `Dư/thiếu so với mức hãng: ${formatMargin(power.marginVsManufacturerW)}.`;
  return [
    `Theo build “${build.name}” trong SQL:`,
    `Tải CPU/GPU ước tính: ${power.estimatedLoadW} W.`,
    manufacturer,
    `Mức PSU hệ thống đề nghị: ${power.recommendedPsuW} W.`,
    selected,
    `Dư/thiếu so với mức hệ thống đề nghị: ${formatMargin(power.marginW)}.`,
    manufacturerMargin,
    `Chênh so với tải ước tính: ${formatMargin(power.marginFromLoadW)}; đây không phải mức PSU hãng khuyến nghị.`
  ].join('\n');
}

function isPowerQuestion(messages) {
  const lastUserMessage = [...messages].reverse().find((message) => message?.role === 'user');
  const content = Array.isArray(lastUserMessage?.content)
    ? lastUserMessage.content.map((part) => part?.text || '').join(' ')
    : String(lastUserMessage?.content || '');
  return /psu|nguồn|nguon|watt|công suất|cong suat/i.test(content);
}

function selectSqlBuild(catalog, budget, purpose, areaId, pinnedComponents = {}) {
  const byType = (type) => catalog.filter((item) => item.type === type && hasUsableProductPrice(item)).sort((a, b) => Number(a.price) - Number(b.price));
  const pick = (type, predicate = () => true) => {
    const pinnedId = pinnedComponents[type];
    return pinnedId
      ? catalog.find((item) => item.id === String(pinnedId) && item.type === type && hasUsableProductPrice(item) && predicate(item))
      : byType(type).find(predicate);
  };
  const cpu = pick('CPU');
  if (!cpu) return null;
  const board = pick('MAINBOARD', (item) => item.socket === cpu.socket);
  if (!board) return null;
  const ram = pick('RAM', (item) => !board.ram || item.ram === board.ram);
  const gpu = pick('GPU');
  const box = pick('CASE', (item) => !gpu || !gpu.length || !item.gpuLength || gpu.length <= item.gpuLength);
  const ssd = pick('SSD');
  const cooler = pick('TẢN NHIỆT', (item) => !item.socket || item.socket === cpu.socket);
  if (!ram || !gpu || !box || !ssd || !cooler) return null;
  const power = powerAssessment([cpu, gpu]);
  const psu = pick('PSU', (item) => Number(item.watts || 0) >= power.recommendedPsuW);
  if (!psu) return null;
  const chosen = { CPU: cpu, MAINBOARD: board, GPU: gpu, RAM: ram, SSD: ssd, PSU: psu, CASE: box, 'TẢN NHIỆT': cooler };
  const total = Object.values(chosen).reduce((sum, item) => sum + Number(item.price || 0), 0);
  if (total > budget) return null;
  const report = compatibility(Object.fromEntries(Object.entries(chosen).map(([type, item]) => [type, item.id])), catalog);
  if (report.status === 'incompatible') return null;
  return {
    name: normalizeBuildName(`PC ${purpose} theo catalog SQL`, 'PC theo catalog SQL'),
    budget,
    areaId,
    components: Object.fromEntries(Object.entries(chosen).map(([type, item]) => [type, item.id])),
    totalPrice: total,
    priceEstimate: Object.values(chosen).some((item) => item.priceSource !== 'market'),
    source: 'sql'
  };
}

function parseModelJson(text) {
  const cleaned = String(text || '').replace(/^```(?:json)?\s*/i, '').replace(/\s*```$/, '').trim();
  return JSON.parse(cleaned);
}

function normalizeBuildName(value, fallback = 'PC theo yêu cầu') {
  const clean = (candidate) => String(candidate ?? '').replace(/\s+/gu, ' ').trim();
  let name = clean(value);
  if (name.length < 2) name = clean(fallback);
  if (name.length < 2) name = 'PC Build';

  let bounded = '';
  for (const character of name) {
    if (bounded.length + character.length > 60) break;
    bounded += character;
  }
  bounded = bounded.trim();
  return bounded.length >= 2 ? bounded : 'PC Build';
}

function decodePathPart(value) {
  try { return decodeURIComponent(value); } catch { return value; }
}
const componentTypes = ['CPU', 'MAINBOARD', 'GPU', 'RAM', 'SSD', 'PSU', 'CASE', 'TẢN NHIỆT'];
function hasUsableProductPrice(item) {
  const price = Number(item?.price);
  return Number.isFinite(price) && price > 0;
}
function hasMarketProductPrice(item) {
  return hasUsableProductPrice(item) && item?.priceSource === 'market';
}
async function buildView(build) {
  const catalog = await sqlModels.listProducts({ areaId: build.areaId });
  const catalogById = new Map(catalog.map((item) => [item.id, item]));
  const components = Object.fromEntries(
    componentTypes.map((type) => [type, catalogById.get(build.components[type]) || null])
  );
  const selected = Object.values(components).filter(Boolean);
  const priced = selected.filter(hasUsableProductPrice);
  const total = priced.reduce((sum, item) => sum + Number(item.price), 0);
  const power = powerAssessment(selected);
  return {
    ...build,
    version: Number(build.version || 1),
    syncState: 'synced',
    components,
    totalPrice: total,
    priceComplete: selected.every(hasUsableProductPrice),
    missingPriceCount: selected.length - priced.length,
    priceEstimate: priced.some((item) => item.priceSource !== 'market'),
    completion: Math.round(selected.length / componentTypes.length * 100),
    estimatedPower: power.estimatedLoadW,
    recommendedPsu: power.recommendedPsuW,
    powerAssessment: power,
    powerDetails: selected.map((item) => ({ id: item.id, name: item.name, watts: Number(item.power || 0), type: item.type }))
  };
}
function compatibility(components, catalog = []) {
  const catalogById = new Map(catalog.map((item) => [item.id, item]));
  const items = Object.entries(components || {}).map(([type, productId]) => {
    const item = catalogById.get(String(productId));
    return item?.type === type ? item : null;
  }).filter(Boolean);
  const selectedIds = new Set(items.map((item) => item.id));
  const issues = [];
  const cpu = items.find((item) => item?.type === 'CPU');
  const board = items.find((item) => item?.type === 'MAINBOARD');
  const ram = items.find((item) => item?.type === 'RAM');
  const psu = items.find((item) => item?.type === 'PSU');
  const gpu = items.find((item) => item?.type === 'GPU');
  const box = items.find((item) => item?.type === 'CASE');
  const cooler = items.find((item) => item?.type === 'TẢN NHIỆT');
  const power = powerAssessment(items);
  const powerBasis = power.manufacturerMinimumW && power.recommendedPsuW === power.manufacturerMinimumW
    ? `mức PSU hãng khuyến nghị ${power.manufacturerMinimumW}W`
    : `mức hệ thống đề nghị ${power.recommendedPsuW}W${power.manufacturerMinimumW ? ` (mức hãng là ${power.manufacturerMinimumW}W)` : ''}`;
  const caseFitsBoard = caseSupportsBoardForm(box?.form, board?.form);
  const validCpuBoardSocket = Boolean(cpu?.socket && board?.socket);
  const validBoardRam = Boolean(board?.ram && ram?.ram);
  const validGpuLength = Number.isFinite(Number(gpu?.length)) && Number.isFinite(Number(box?.gpuLength));
  const validCaseForm = Boolean(board?.form && box?.form);
  if (validCpuBoardSocket && cpu.socket !== board.socket) issues.push({ code: 'SOCKET', severity: 'error', message: `Socket không khớp: ${cpu.name} dùng ${cpu.socket}, còn ${board.name} là ${board.socket}.` });
  if (validBoardRam && board.ram !== ram.ram) issues.push({ code: 'RAM', severity: 'error', message: `Chuẩn RAM không khớp: mainboard hỗ trợ ${board.ram}, còn RAM đang chọn là ${ram.ram}.` });
  if (psu && power.selectedPsuW == null) {
    issues.push({ code: 'PSU', severity: 'warning', message: `Catalog chưa có công suất xác nhận cho ${psu.name}; cần kiểm tra nhãn PSU trước khi kết luận có đủ ${power.recommendedPsuW}W.` });
  } else if (psu && power.selectedPsuW < power.recommendedPsuW) {
    const shortfall = power.recommendedPsuW - Number(power.selectedPsuW || 0);
    const gpuName = power.manufacturerGpuNames.join(', ');
    issues.push({ code: 'PSU', severity: 'warning', message: `Nguồn ${psu.name} (${power.selectedPsuW || 'chưa xác định'}W) thiếu ${shortfall}W so với ${powerBasis}${gpuName && power.recommendedPsuW === power.manufacturerMinimumW ? ` cho ${gpuName}` : ''}.` });
  }
  if (validGpuLength && Number(gpu.length) > Number(box.gpuLength)) issues.push({ code: 'CASE_SIZE', severity: 'error', message: `GPU dài ${gpu.length}mm, vượt khoảng trống ${box.gpuLength}mm của case.` });
  if (cpu?.socket && cooler?.socket && cpu.socket !== cooler.socket) issues.push({ code: 'COOLER_SOCKET', severity: 'error', message: `Tản nhiệt hỗ trợ ${cooler.socket}, không khớp socket ${cpu.socket} của CPU.` });
  if (validCaseForm && !caseFitsBoard) issues.push({ code: 'CASE_FORM', severity: 'error', message: `Mainboard ${board.form} không vừa case ${box.form}.` });
  const recommendations = [];
  const recommendationIds = new Set();
  const addRecommendations = (type, predicate, reason) => {
    catalog
      .filter((item) => item.type === type && hasUsableProductPrice(item) && !selectedIds.has(item.id) && !recommendationIds.has(item.id) && predicate(item))
      .sort((a, b) => Number(a.price || 0) - Number(b.price || 0))
      .slice(0, 3)
      .forEach((item) => {
        recommendationIds.add(item.id);
        recommendations.push({ ...item, recommendationReason: reason });
      });
  };
  if (gpu && (!psu || power.selectedPsuW == null || power.selectedPsuW < power.recommendedPsuW)) {
    addRecommendations('PSU', (item) => psuRatedWatts(item) >= power.recommendedPsuW,
      `Công suất từ ${power.recommendedPsuW}W để đạt mức đề nghị cho cấu hình.`);
  }
  if (cpu && board && cpu.socket !== board.socket) {
    addRecommendations('MAINBOARD', (item) => item.socket === cpu.socket,
      `Socket ${cpu.socket} tương thích với CPU đang chọn.`);
  }
  if (board && ram && board.ram && ram.ram && board.ram !== ram.ram) {
    addRecommendations('RAM', (item) => item.ram === board.ram,
      `Chuẩn ${board.ram} được mainboard hỗ trợ.`);
  }
  if (cpu && cooler && cpu.socket && cooler.socket && cpu.socket !== cooler.socket) {
    addRecommendations('TẢN NHIỆT', (item) => !item.socket || item.socket === cpu.socket,
      `Hỗ trợ socket ${cpu.socket} của CPU.`);
  }
  if (board && box && validCaseForm && !caseFitsBoard) {
    addRecommendations('CASE', (item) => caseSupportsBoardForm(item.form, board.form),
      `Hỗ trợ mainboard form factor ${board.form}.`);
  }
  if (gpu && box && validGpuLength && Number(gpu.length) > Number(box.gpuLength)) {
    addRecommendations('CASE', (item) => Number(item.gpuLength || 0) >= Number(gpu.length),
      `Khoảng trống GPU ít nhất ${gpu.length}mm.`);
  }
  const psuDetail = psu
    ? power.selectedPsuW == null
      ? `Chưa xác minh được công suất của ${psu.name} trong SQL; cần kiểm tra nhãn nguồn.`
      : power.selectedPsuW >= power.recommendedPsuW
      ? `Nguồn đang chọn ${psu.name}, đạt ${powerBasis} (dư ${power.marginW}W so với mức đề nghị hệ thống).`
      : `Nguồn đang chọn ${psu.name}, thiếu ${Math.abs(power.marginW)}W so với ${powerBasis}.`
    : `Chưa chọn PSU. Nên dùng nguồn tối thiểu ${power.recommendedPsuW}W.`;
  const criteria = [
    {
      code: 'SOCKET',
      severity: 'error',
      status: validCpuBoardSocket ? (cpu.socket === board.socket ? 'pass' : 'error') : 'unchecked',
      comparedFields: ['CPU.socket', 'MAINBOARD.socket'],
      assumptions: [],
      detail: validCpuBoardSocket ? `CPU ${cpu.socket}; mainboard ${board.socket}.` : 'Chọn CPU và mainboard có socket trong catalog để kiểm tra.',
      remediation: 'Chọn mainboard cùng socket với CPU.'
    },
    {
      code: 'RAM',
      severity: 'error',
      status: validBoardRam ? (board.ram === ram.ram ? 'pass' : 'error') : 'unchecked',
      comparedFields: ['MAINBOARD.ram', 'RAM.ram'],
      assumptions: [],
      detail: validBoardRam ? `Mainboard ${board.ram}; RAM ${ram.ram}.` : !ram || !board ? 'Chọn cả mainboard và RAM để kiểm tra chuẩn bộ nhớ.' : `Đã chọn mainboard và RAM, nhưng SQL chưa có chuẩn bộ nhớ cho ${!board.ram ? board.name : ram.name}.`,
      remediation: 'Chọn RAM đúng chuẩn mà mainboard hỗ trợ.'
    },
    {
      code: 'PSU',
      severity: 'warning',
      status: psu ? (power.selectedPsuW != null && power.selectedPsuW >= power.recommendedPsuW ? 'pass' : 'warning') : 'unchecked',
      comparedFields: ['PSU.watts', 'GPU.recommendedPsuW', 'estimatedLoadW'],
      assumptions: ['Tải CPU/GPU lấy từ catalog; mức PSU của GPU lấy theo nhà sản xuất khi SQL có dữ liệu.'],
      detail: `${psuDetail} Tải CPU/GPU ước tính ${power.estimatedLoadW}W; cách tính: ${power.method}.`,
      source: power.sourceEntry,
      remediation: `Chọn PSU từ ${power.recommendedPsuW}W trở lên; đối chiếu nhãn công suất và dây cấp nguồn của GPU.`
    },
    {
      code: 'CASE_SIZE',
      severity: 'error',
      status: validGpuLength ? (Number(gpu.length) <= Number(box.gpuLength) ? 'pass' : 'error') : 'unchecked',
      comparedFields: ['GPU.length', 'CASE.gpuLength'],
      assumptions: [],
      detail: validGpuLength ? `GPU ${gpu.length}mm; case hỗ trợ tối đa ${box.gpuLength}mm.` : 'Chưa đủ dữ liệu chiều dài GPU hoặc khoảng trống case trong SQL.',
      remediation: 'Chọn case có khoảng trống GPU phù hợp.'
    },
    {
      code: 'COOLER_SOCKET',
      severity: 'error',
      status: cpu && cooler && cooler.socket ? (cpu.socket === cooler.socket ? 'pass' : 'error') : 'unchecked',
      comparedFields: ['CPU.socket', 'TẢN NHIỆT.socket'],
      assumptions: cooler && !cooler.socket ? ['SQL chưa có socket hỗ trợ của tản nhiệt.'] : [],
      detail: cpu && cooler?.socket ? `CPU ${cpu.socket}; tản nhiệt hỗ trợ ${cooler.socket}.` : !cpu || !cooler ? 'Chọn cả CPU và tản nhiệt để kiểm tra socket.' : `Đã chọn tản nhiệt ${cooler.name}, nhưng SQL chưa có socket hỗ trợ để đối chiếu.`,
      remediation: 'Chọn tản nhiệt hỗ trợ socket của CPU.'
    },
    {
      code: 'CASE_FORM',
      severity: 'error',
      status: validCaseForm ? (caseFitsBoard ? 'pass' : 'error') : 'unchecked',
      comparedFields: ['MAINBOARD.form', 'CASE.form'],
      assumptions: [],
      detail: validCaseForm ? `Mainboard ${board.form}; case ${box.form}.` : 'Chưa đủ dữ liệu form factor của mainboard hoặc case.',
      remediation: 'Chọn case hỗ trợ kích thước mainboard.'
    }
  ];
  const checkedCriteria = criteria.filter((item) => item.status !== 'unchecked');
  const hasUnchecked = criteria.some((item) => item.status === 'unchecked');
  const status = issues.some((item) => item.severity === 'error')
    ? 'incompatible'
    : issues.length
      ? 'warning'
      : hasUnchecked || !checkedCriteria.length ? 'partial' : 'compatible';
  return {
    status,
    selectedCount: selectedIds.size,
    score: checkedCriteria.length
      ? Math.max(0, Math.round(((checkedCriteria.length - issues.length) / checkedCriteria.length) * 100))
      : null,
    issues,
    estimatedPower: power.estimatedLoadW,
    recommendedPsu: power.recommendedPsuW,
    powerAssessment: power,
    recommendations,
    criteria,
    checkedAt: new Date().toISOString(),
    rulesVersion: 'catalog-v1'
  };
}

module.exports = { money, catalogPromptSelection, pcKnowledgePrompt, psuRatedWatts, normalizeFormFactor, caseSupportsBoardForm, powerAssessment, formatBuildPowerSummary, isPowerQuestion, selectSqlBuild, parseModelJson, normalizeBuildName, decodePathPart, componentTypes, hasUsableProductPrice, hasMarketProductPrice, buildView, compatibility };
