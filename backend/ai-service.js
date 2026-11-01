const { parseModelJson } = require('./build-service');

function completionText(completion) {
  const content = completion?.choices?.[0]?.message?.content;
  if (typeof content === 'string') return content.trim();
  if (Array.isArray(content)) {
    return content.map((part) => typeof part === 'string' ? part : String(part?.text || '')).join('\n').trim();
  }
  return '';
}

async function requestOpenAICompatibleChat({ url, model, messages, requestOptions = {}, provider, apiKey }) {
  const endpoint = String(url || '').replace(/\/$/, '');
  if (!endpoint) {
    const error = new Error(`${provider} chưa được cấu hình.`);
    error.statusCode = 503;
    throw error;
  }
  const headers = { 'content-type': 'application/json' };
  if (endpoint.includes('ngrok')) headers['ngrok-skip-browser-warning'] = 'true';
  if (apiKey) headers.authorization = `Bearer ${apiKey}`;
  const controller = new AbortController();
  const timeoutMs = Math.max(1000, Number(requestOptions.timeoutMs || process.env.AI_PROVIDER_TIMEOUT_MS || 300000));
  const timeout = setTimeout(() => controller.abort(), timeoutMs);
  try {
    const response = await fetch(`${endpoint}/chat/completions`, {
      method: 'POST',
      headers,
      signal: controller.signal,
      body: JSON.stringify({
        model,
        messages: messages.slice(-12),
        temperature: Number(requestOptions.temperature ?? process.env.LOCAL_AI_TEMPERATURE ?? 0.4),
        top_p: Number(requestOptions.topP ?? process.env.LOCAL_AI_TOP_P ?? 0.8),
        max_tokens: Number(requestOptions.maxTokens ?? process.env.LOCAL_AI_MAX_TOKENS ?? 512),
        stream: false
      })
    });
    const responseText = await response.text();
    let responseBody;
    try {
      responseBody = responseText ? JSON.parse(responseText) : null;
    } catch {
      responseBody = { error: { message: responseText || 'Phản hồi trống.' } };
    }
    if (!response.ok) {
      const error = new Error(responseBody?.error?.message || `${provider} trả về HTTP ${response.status}.`);
      error.statusCode = 502;
      throw error;
    }
    if (!completionText(responseBody)) {
      const error = new Error(`${provider} không trả về câu trả lời hợp lệ.`);
      error.statusCode = 502;
      throw error;
    }
    return responseBody;
  } catch (error) {
    if (controller.signal.aborted) {
      error.message = `${provider} quá thời gian chờ (${timeoutMs} ms).`;
      error.statusCode = 504;
    }
    throw error;
  } finally {
    clearTimeout(timeout);
  }
}

function answerNeedsExpertFallback(completion) {
  const answer = completionText(completion);
  return !answer || /__PCBUILD_NEED_EXPERT__|không thể trả lời|chưa thể trả lời|chưa đủ căn cứ|chưa đủ dữ liệu|chưa đủ thông tin|không đủ thông tin|không chắc chắn|chưa thể xác nhận|không thể xác định|tôi không biết|I don't know|I cannot answer|unable to answer|not enough information|not sure/i.test(answer);
}

function pcChatNeedsExpertReview(messages, completion) {
  if (answerNeedsExpertFallback(completion)) return true;
  const latestQuestion = [...messages].reverse().find((item) => item?.role === 'user')?.content;
  const question = String(latestQuestion || '').toLowerCase();
  const answer = completionText(completion).toLowerCase();
  if (/modular.{0,35}(psu|nguồn|power supply)|(psu|nguồn).{0,35}modular|dây.{0,35}(modular|nguồn)/i.test(question)) {
    return !/pinout|sơ đồ chân|đúng model|đúng sku|nhà sản xuất xác nhận/i.test(answer);
  }
  if (/mùi khét|cháy|tia lửa|tách điện|smoke|burning smell|melted connector/i.test(question)) {
    return !/(rút điện|ngắt điện|ngắt nguồn)/i.test(answer)
      || /(bật lại|tiếp tục sử dụng|mở psu)/i.test(answer);
  }
  if (/bios|flash.*firmware/i.test(question)) {
    return !/(revision|model mainboard|mã mainboard|manual|tài liệu|trang hỗ trợ|nhà sản xuất)/i.test(answer);
  }
  if (/ddr5|memory training|train ram|đèn dram/i.test(question)) {
    return !/(chờ|đợi).{0,60}(training|manual|đèn|post)|training.{0,80}(chờ|đợi)/i.test(answer)
      || /(xả ram|15.?30 phút)/i.test(answer);
  }
  return false;
}

function addLmStudioExpertInstructions(messages, task) {
  const instructions = [
    'Bạn là trợ lý AI chính thức của PCBUILD, chạy trên LM Studio. Hãy tự xử lý toàn bộ yêu cầu bằng tiếng Việt, chuyên nghiệp, chính xác và dựa trên ngữ cảnh được cung cấp.',
    'Chỉ hỗ trợ PC và linh kiện PC. Kiến thức kỹ thuật tổng quát có thể giải thích, nhưng mọi mã/tên SKU, giá, lịch sử giá, cấu hình tài khoản, thông số riêng của sản phẩm và dữ liệu tương thích phải khớp SQL trong system prompt. Thiếu SQL thì nói rõ chưa xác nhận; tuyệt đối không đoán hoặc tự tạo dữ liệu.',
    task === 'scan'
      ? 'Với ảnh, phân biệt loại linh kiện, đọc chữ và tìm ứng viên gần nhất trong catalog SQL. Chỉ đánh dấu recognized=true khi model/SKU in trên sản phẩm khớp rõ ràng và duy nhất. Nếu chưa chắc, recognized=false, productId=null nhưng vẫn trả tối đa 5 candidateProductIds có trong catalog, xếp theo mức giống hình/chữ; tuyệt đối không bịa ID.'
      : task === 'build'
        ? 'Chọn cấu hình chỉ từ product ID trong catalog SQL được cung cấp. Giữ nguyên linh kiện ghim, đúng ngân sách, đủ nhóm được yêu cầu và không khẳng định tương thích nếu dữ liệu SQL thiếu.'
        : 'Nếu câu hỏi cần dữ liệu SQL chưa có, nêu đúng giới hạn thay vì tự điền một con số.'
  ].join('\n');
  const cloned = messages.map((message) => ({ ...message }));
  const systemIndex = cloned.findIndex((message) => message.role === 'system');
  if (systemIndex >= 0) {
    cloned[systemIndex].content = `${cloned[systemIndex].content || ''}\n\n${instructions}`;
  } else {
    cloned.unshift({ role: 'system', content: instructions });
  }
  return cloned;
}

function removeHandoffMarker(completion) {
  const message = completion?.choices?.[0]?.message;
  if (typeof message?.content === 'string') {
    message.content = message.content.replaceAll('__PCBUILD_NEED_EXPERT__', '').trim()
      || 'Tôi chưa đủ căn cứ để trả lời chính xác từ dữ liệu hiện có.';
  }
  return completion;
}

async function requestProjectLmStudio(messages, {
  task = 'chat',
  requestOptions = {},
} = {}) {
  const lmStudioUrl = String(process.env.LM_STUDIO_URL || '').replace(/\/$/, '');
  const lmStudioModel = String((task === 'scan'
    ? process.env.LM_STUDIO_VISION_MODEL || process.env.LM_STUDIO_MODEL
    : process.env.LM_STUDIO_MODEL) || 'qwen3-vl-8b-instruct');
  const lmStudioRequestOptions = {
    ...requestOptions,
    timeoutMs: Number(requestOptions.timeoutMs || process.env.LM_STUDIO_TIMEOUT_MS || 240000)
  };
  if (!lmStudioUrl) {
    const error = new Error('LM_STUDIO_URL chưa được cấu hình.');
    error.statusCode = 503;
    throw error;
  }
  return requestOpenAICompatibleChat({
    url: lmStudioUrl,
    model: lmStudioModel,
    messages: addLmStudioExpertInstructions(messages, task),
    requestOptions: lmStudioRequestOptions,
    provider: 'LM Studio',
    apiKey: process.env.LM_STUDIO_API_KEY
  });
}

function appendSystemContext(messages, context) {
  const cloned = messages.map((message) => ({ ...message }));
  const systemIndex = cloned.findIndex((message) => message.role === 'system');
  if (systemIndex >= 0) {
    cloned[systemIndex].content = `${cloned[systemIndex].content || ''}\n\n${context}`;
  } else {
    cloned.unshift({ role: 'system', content: context });
  }
  return cloned;
}

function scanCompletionMatchesCatalog(completion, catalog) {
  let proposed;
  try {
    proposed = parseModelJson(completionText(completion));
  } catch {
    return false;
  }
  const confidence = Math.max(0, Math.min(1, Number(proposed?.confidence) || 0));
  const summary = String(proposed?.summary || '');
  const uncertain = /chưa đủ rõ|không đủ rõ|không chắc|chưa thể xác nhận|chưa xác định|chưa phân biệt|nhiều khả năng|nhiều bản ghi|nhiều sản phẩm|bản ghi cụ thể|có thể là|phân biệt|mơ hồ|không đọc được|không xác định được|uncertain|ambiguous|not sure|cannot confirm/i.test(summary);
  if (proposed?.recognized !== true || confidence < 0.9 || uncertain) return false;
  const productId = String(proposed.productId || '');
  const productName = String(proposed.name || '').trim().toLowerCase();
  return catalog.some((item) => item.id === productId || (productName && item.name.toLowerCase() === productName));
}

function hasVisibleSkuEvidence(product, vision) {
  if (!product) return false;
  const visibleText = String(vision?.visibleText || '').toLowerCase();
  const name = String(product.name || '').toLowerCase();
  if (!visibleText || !name) return false;
  if (product.type === 'GPU') {
    const model = name.match(/\b(?:rtx|gtx)\D{0,4}(\d{3,4})\b/i);
    if (model && !new RegExp(`\\b${model[1]}\\b`).test(visibleText)) return false;
    if (/\bti\b/i.test(name) && !/\bti\b/i.test(visibleText)) return false;
    if (/\bsuper\b/i.test(name) && !/\bsuper\b/i.test(visibleText)) return false;
    return Boolean(model);
  }
  const modelTokens = name.match(/\b[a-z]{0,5}\d{3,}[a-z0-9-]*\b/gi) || [];
  return modelTokens.some((token) => visibleText.includes(token.toLowerCase()));
}

function addLmStudioInitialVisionInstructions(messages) {
  return appendSystemContext(messages, [
    'Bạn là bộ nhận diện hình ảnh PC của PCBUILD. Phân loại linh kiện; đọc nguyên văn mọi chữ/model/SKU rõ; nhận diện hãng, họ sản phẩm và mô tả đặc điểm nhìn thấy để lượt sau so với catalog SQL.',
    'Không khẳng định model cụ thể nếu không nhìn thấy bằng chứng. Nếu ảnh chỉ thấy hãng hoặc dòng chung, vẫn ghi brand/modelFamily/visualDescription để tạo danh sách gợi ý gần giống, nhưng giảm confidence và nêu giới hạn.',
    'Chỉ trả JSON đúng schema: {"componentType":string|null,"visibleText":string,"brand":string|null,"modelFamily":string|null,"visualDescription":string,"confidence":number,"summary":string}. componentType chỉ dùng CPU, MAINBOARD, GPU, RAM, SSD, PSU, CASE, TẢN NHIỆT hoặc null. Không thêm markdown hay văn bản ngoài JSON.'
  ].join('\n'));
}

function catalogForVisionCandidate(candidate, catalog) {
  const value = String(candidate?.componentType || '').trim().toUpperCase();
  const aliases = {
    'CPU COOLER': 'TẢN NHIỆT',
    COOLER: 'TẢN NHIỆT',
    'GRAPHICS CARD': 'GPU',
    'VIDEO CARD': 'GPU',
    VGA: 'GPU',
    MOTHERBOARD: 'MAINBOARD',
    MEMORY: 'RAM',
    'POWER SUPPLY': 'PSU',
    'POWER SUPPLY UNIT': 'PSU',
    'PC CASE': 'CASE',
    CHASSIS: 'CASE',
    STORAGE: 'SSD',
    HDD: 'SSD',
  };
  const type = aliases[value] || value;
  const focused = catalog.filter((item) => item.type === type);
  const source = focused.length ? focused : catalog;
  const visibleText = [candidate?.brand, candidate?.visibleText].filter(Boolean).join(' ').toLowerCase();
  const visualHints = [candidate?.modelFamily, candidate?.visualDescription].filter(Boolean).join(' ').toLowerCase();
  const tokens = visibleText.split(/[^a-z0-9]+/i).filter((token) => token.length >= 3);
  const hintTokens = visualHints.split(/[^a-z0-9]+/i).filter((token) => token.length >= 3);
  return source.map((item) => {
    const name = String(item.name || '').toLowerCase();
    const id = String(item.id || '').toLowerCase();
    let score = 0;
    if (name && visibleText.includes(name)) score += 100;
    if (id && visibleText.includes(id)) score += 100;
    for (const token of tokens) {
      if (name.includes(token) || id.includes(token)) score += 10;
    }
    for (const token of hintTokens) {
      if (name.includes(token) || id.includes(token)) score += 2;
    }
    if (/\b(?:geforce|rtx|gtx)\b/i.test(visibleText)) {
      score += /\b(?:geforce|rtx|gtx)\b/i.test(name) ? 40 : -40;
    }
    if (/\b(?:radeon|rx)\b/i.test(visibleText)) {
      score += /\b(?:radeon|rx)\b/i.test(name) ? 40 : -40;
    }
    return { ...item, _visionMatchScore: score };
  }).sort((a, b) => b._visionMatchScore - a._visionMatchScore
      || Number(b.priceSource === 'market') - Number(a.priceSource === 'market')
      || Number(a.price) - Number(b.price))
    .filter((item) => item._visionMatchScore > 0)
    .slice(0, 80);
}

function parseVisionStageOne(completion) {
  const raw = completionText(completion);
  try {
    return parseModelJson(raw);
  } catch {
    return { componentType: null, visibleText: raw.slice(0, 1000), confidence: 0, summary: 'Lượt OCR vision đầu không trả JSON hợp lệ.' };
  }
}

async function requestVisionWithLmStudio(messages, catalog, requestOptions = {}) {
  const lmStudioUrl = String(process.env.LM_STUDIO_URL || '').replace(/\/$/, '');
  const lmStudioModel = String(process.env.LM_STUDIO_VISION_MODEL || process.env.LM_STUDIO_MODEL || 'qwen3-vl-8b-instruct');
  if (!lmStudioUrl) {
    const error = new Error('LM_STUDIO_URL chưa được cấu hình.');
    error.statusCode = 503;
    throw error;
  }
  const firstVisionCompletion = await requestOpenAICompatibleChat({
    url: lmStudioUrl,
    model: lmStudioModel,
    messages: addLmStudioInitialVisionInstructions(messages),
    requestOptions: { ...requestOptions, temperature: 0.1 },
    provider: 'LM Studio vision OCR',
    apiKey: process.env.LM_STUDIO_API_KEY
  });
  const firstVision = parseVisionStageOne(firstVisionCompletion);
  const candidateCatalog = catalogForVisionCandidate(firstVision, catalog)
    .map(({ id, type, name, price, priceSource }) => ({ id, type, name, price, priceSource }));
  const finalMessages = [
    {
      role: 'system',
      content: [
        'Bạn là AI vision chuyên dụng của PCBUILD. Dùng ảnh gốc, chữ in, hình dáng và catalog SQL bên dưới để nhận diện hoặc đưa ra các ứng viên gần giống.',
        `Kết quả OCR sơ bộ: ${JSON.stringify(firstVision).slice(0, 1800)}`,
        `Các ứng viên catalog SQL: ${JSON.stringify(candidateCatalog)}`,
        'Nếu model/SKU đọc được và khớp duy nhất tên trong catalog, trả recognized=true, productId đúng và candidateProductIds gồm sản phẩm đó.',
        'Nếu không đọc rõ SKU, không được khẳng định chính xác. Hãy chọn tối đa 5 productId gần giống nhất từ danh sách catalog dựa trên chữ nhìn thấy, hãng, dòng sản phẩm và hình dáng; trả recognized=false, productId=null. Nếu ảnh chỉ cho biết hãng/loại chung, nói rõ đây là gợi ý gần đúng để người dùng xác nhận.',
        'Không tạo SKU, giá, hay thông số. Trả duy nhất JSON: {"recognized":boolean,"productId":string|null,"candidateProductIds":string[],"componentType":string|null,"confidence":number,"summary":string}.'
      ].join('\n')
    },
    ...messages.filter((message) => message.role === 'user')
  ];
  const completion = await requestOpenAICompatibleChat({
    url: lmStudioUrl,
    model: lmStudioModel,
    messages: addLmStudioExpertInstructions(finalMessages, 'scan'),
    requestOptions: { ...requestOptions, temperature: 0.1 },
    provider: 'LM Studio final vision review',
    apiKey: process.env.LM_STUDIO_API_KEY
  });
  return { completion, firstVision, candidateCatalog };
}

module.exports = { completionText, requestOpenAICompatibleChat, answerNeedsExpertFallback, pcChatNeedsExpertReview, addLmStudioExpertInstructions, removeHandoffMarker, requestProjectLmStudio, appendSystemContext, scanCompletionMatchesCatalog, hasVisibleSkuEvidence, addLmStudioInitialVisionInstructions, catalogForVisionCandidate, parseVisionStageOne, requestVisionWithLmStudio };
