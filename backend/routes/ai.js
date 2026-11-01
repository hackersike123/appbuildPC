const sqlModels = require('../sql-models');
const { send } = require('../http-utils');
const { completionText, pcChatNeedsExpertReview, requestProjectLmStudio } = require('../ai-service');
const { pcKnowledgePrompt, formatBuildPowerSummary, isPowerQuestion, selectSqlBuild, parseModelJson, normalizeBuildName, componentTypes, hasUsableProductPrice, hasMarketProductPrice, compatibility } = require('../build-service');

module.exports = async function handleAiRoutes(context) {
  const { req, res, method, url, parts, body, user, id } = context;
  if (method === 'POST' && parts.join('/') === 'api/v1/conversations') {
    const conversation = { id: id('conversation'), userId: user.id };
    await sqlModels.createConversation(conversation);
    const initialMessage = String(body.initialMessage || '').trim();
    if (initialMessage) {
      await sqlModels.addMessage({
        conversationId: conversation.id,
        role: 'assistant',
        content: initialMessage
      });
    }
    return send(res, 201, {
      ...conversation,
      messages: initialMessage ? [{ role: 'assistant', content: initialMessage }] : []
    });
  }
  if (method === 'DELETE' && parts.length === 4 && parts[0] === 'api' && parts[1] === 'v1' && parts[2] === 'conversations') {
    const deleted = await sqlModels.deleteConversation(parts[3], user.id);
    return deleted
      ? send(res, 204, {})
      : send(res, 404, { error: 'CONVERSATION_NOT_FOUND' });
  }
  if (method === 'POST' && parts.join('/') === 'api/v1/ai/chat') {
    const messages = Array.isArray(body.messages) ? body.messages : [];
    if (messages.length === 0) return send(res, 422, { error: 'INVALID_MESSAGES' });
    try {
      const catalog = await sqlModels.listProducts({ areaId: user.areaId });
      const conversation = messages
        .filter((message) => ['user', 'assistant'].includes(message?.role))
        .slice(-10)
        .map(({ role, content }) => ({ role, content }));
      const [examples, builds] = await Promise.all([
        sqlModels.listAiPcExamples(),
        sqlModels.listBuildsByUser(user.id)
      ]);
      const completion = await requestProjectLmStudio([
        { role: 'system', content: pcKnowledgePrompt(catalog, user.areaId, examples, builds[0], conversation) },
        ...conversation
      ], {
        task: 'chat',
        shouldFallback: (candidate) => pcChatNeedsExpertReview(conversation, candidate)
      });
      if (builds[0] && isPowerQuestion(conversation) && completion?.choices?.[0]?.message) {
        completion.choices[0].message.content = formatBuildPowerSummary(builds[0], catalog);
        completion.choices[0].finish_reason = 'stop';
      }
      return send(res, 200, completion);
    } catch (error) {
      return send(res, error.statusCode || 502, {
        error: 'AI_PROVIDER_UNREACHABLE',
        message: error.message
      });
    }
  }
  if (method === 'POST' && parts.join('/') === 'api/v1/ai/generate-build') {
    const budget = Number(body.budget);
    const purpose = String(body.purpose || '').trim();
    const areaId = String(body.areaId || user.areaId || '').trim();
    const areas = await sqlModels.listAreas();
    if (!Number.isFinite(budget) || budget <= 0 || !purpose || !areas.some((area) => area.id === areaId)) {
      return send(res, 422, {
        error: 'INVALID_BUILD_REQUEST',
        message: 'Ngân sách, mục đích và khu vực hợp lệ là bắt buộc.'
      });
    }

    const catalog = await sqlModels.listProducts({ areaId });
    const pricedCatalog = catalog.filter(hasUsableProductPrice);
    const marketCatalog = pricedCatalog.filter(hasMarketProductPrice);
    const pinnedComponents = body.pinnedComponents && typeof body.pinnedComponents === 'object'
      ? body.pinnedComponents
      : {};
    for (const [type, productId] of Object.entries(pinnedComponents)) {
      if (!componentTypes.includes(type) || !catalog.some((item) => item.id === String(productId) && item.type === type)) {
        return send(res, 422, { error: 'INVALID_PINNED_COMPONENT', message: 'Linh kiện được ghim không có trong catalog SQL.' });
      }
      if (!hasUsableProductPrice(catalog.find((item) => item.id === String(productId) && item.type === type))) {
        return send(res, 422, { error: 'PRICE_UNAVAILABLE', message: 'Linh kiện được ghim chưa có giá SQL.' });
      }
    }
    const missingPriceTypes = componentTypes.filter((type) => !pricedCatalog.some((item) => item.type === type));
    if (missingPriceTypes.length) {
      return send(res, 422, {
        error: 'PRICED_CATALOG_INCOMPLETE',
        message: 'Chưa đủ linh kiện có giá SQL để tạo cấu hình.',
        missingTypes: missingPriceTypes
      });
    }
    const sqlBuild = selectSqlBuild(marketCatalog, budget, purpose, areaId, pinnedComponents)
      || selectSqlBuild(pricedCatalog, budget, purpose, areaId, pinnedComponents);
    if (sqlBuild) {
      const catalogById = new Map(catalog.map((item) => [item.id, item]));
      const componentDetails = Object.fromEntries(Object.entries(sqlBuild.components)
        .map(([type, productId]) => [type, catalogById.get(productId) || null]));
      return send(res, 200, { ...sqlBuild, componentDetails });
    }
    const fallbackCatalogById = new Map();
    for (const type of componentTypes) {
      const candidates = pricedCatalog
        .filter((item) => item.type === type)
        .sort((a, b) => Number(a.priceSource !== 'market') - Number(b.priceSource !== 'market') || Number(a.price) - Number(b.price))
        .slice(0, 8);
      for (const item of candidates) fallbackCatalogById.set(item.id, item);
      const pinnedId = pinnedComponents[type];
      const pinned = pinnedId && pricedCatalog.find((item) => item.id === String(pinnedId));
      if (pinned) fallbackCatalogById.set(pinned.id, pinned);
    }
    const fallbackCatalog = [...fallbackCatalogById.values()];
    const prompt = [
      'Bạn là trợ lý xây dựng cấu hình PC. Đây là phương án dự phòng vì catalog SQL chưa tạo được cấu hình phù hợp.',
      `Ngân sách: ${budget} VND. Mục đích: ${purpose}. Khu vực: ${areaId}.`,
      'Chỉ chọn sản phẩm có giá dương từ catalog SQL. Ưu tiên giá thị trường (priceSource=market); giá catalog_estimate chỉ dùng khi không có phương án thị trường phù hợp và phải nêu là ước tính. Phải đủ 8 nhóm linh kiện và tổng không vượt ngân sách. Nếu không thể đáp ứng, trả JSON {"error":"NO_VALID_BUILD"}.',
      `Bắt buộc giữ nguyên các linh kiện này: ${JSON.stringify(pinnedComponents)}.`,
      'Trả về đúng JSON, không markdown, với các trường name, budget, areaId, components và optionalNotes. Giá trị component là product ID, không bịa sản phẩm.',
      `Catalog mẫu có giá (tối đa 8 sản phẩm mỗi nhóm): ${JSON.stringify(fallbackCatalog)}`
    ].join('\n');

    try {
      const response = await requestProjectLmStudio([
        { role: 'system', content: 'Bạn là chuyên gia build PC của PCBUILD, phải chọn chính xác từ catalog SQL và chỉ trả JSON theo yêu cầu.' },
        { role: 'user', content: prompt }
      ], {
        task: 'build',
        requestOptions: { timeoutMs: Number(process.env.LM_STUDIO_TIMEOUT_MS || 240000), temperature: 0.1, maxTokens: 1800 }
      });
      const text = completionText(response);
      if (!text) throw new Error('LM Studio không trả về cấu hình.');
      const generated = parseModelJson(text);
      if (generated?.error === 'NO_VALID_BUILD') {
        return send(res, 422, { error: 'NO_VALID_BUILD', message: 'Catalog SQL chưa có cấu hình tương thích trong ngân sách này.' });
      }
      if (!generated || typeof generated !== 'object' || !generated.components || typeof generated.components !== 'object') {
        throw new Error('LM Studio trả về cấu hình không đúng định dạng.');
      }
      const components = {};
      for (const [type, productId] of Object.entries(generated.components)) {
        const item = fallbackCatalog.find((candidate) => candidate.id === String(productId));
        if (item && item.type === type) components[type] = item.id;
      }
      if (Object.keys(components).length !== componentTypes.length) {
        throw new Error('LM Studio không chọn đủ tám linh kiện hợp lệ trong catalog SQL.');
      }
      for (const [type, productId] of Object.entries(pinnedComponents)) {
        if (components[type] !== String(productId)) throw new Error(`Cấu hình không giữ lại linh kiện ${type} đã ghim.`);
      }
      const totalPrice = Object.values(components).reduce((sum, productId) => sum + Number(fallbackCatalog.find((item) => item.id === productId)?.price || 0), 0);
      const report = compatibility(components, fallbackCatalog);
      if (totalPrice > budget || report.status === 'incompatible') {
        throw new Error('Cấu hình dự phòng vượt ngân sách hoặc không tương thích theo dữ liệu SQL.');
      }
      return send(res, 200, {
        name: normalizeBuildName(generated.name, `PC ${purpose}`),
        budget,
        areaId,
        components,
        componentDetails: Object.fromEntries(Object.entries(components)
          .map(([type, productId]) => [type, fallbackCatalog.find((item) => item.id === productId) || null])),
        totalPrice,
        priceEstimate: Object.values(components).some((productId) => fallbackCatalog.find((item) => item.id === productId)?.priceSource !== 'market'),
        optionalNotes: String(generated.optionalNotes || ''),
        source: 'lm_studio_fallback'
      });
    } catch (error) {
      return send(res, 502, { error: 'AI_BUILD_GENERATION_FAILED', message: error.message });
    }
  }
  if (method === 'POST' && parts[0] === 'api' && parts[1] === 'v1' && parts[2] === 'conversations' && parts[4] === 'messages') {
    const conversation = await sqlModels.getConversationById(parts[3], user.id);
    if (!conversation) return send(res, 404, { error: 'CONVERSATION_NOT_FOUND' });
    const message = String(body.message || '').trim();
    if (!message) return send(res, 422, { error: 'INVALID_MESSAGE', message: 'Nội dung tư vấn không được để trống.' });
    await sqlModels.addMessage({
      conversationId: conversation.id,
      role: 'user',
      content: message
    });
    try {
      const history = await sqlModels.listMessages(conversation.id);
      const [catalog, examples, builds] = await Promise.all([
        sqlModels.listProducts({ areaId: user.areaId }),
        sqlModels.listAiPcExamples(),
        sqlModels.listBuildsByUser(user.id)
      ]);
      const completion = await requestProjectLmStudio([
        {
          role: 'system',
          content: pcKnowledgePrompt(catalog, user.areaId, examples, builds[0], history)
        },
        ...history.slice(-10).map(({ role, content }) => ({ role, content }))
      ], {
        task: 'chat',
        shouldFallback: (candidate) => pcChatNeedsExpertReview(history, candidate)
      });
      const answer = completion?.choices?.[0]?.message?.content;
      if (typeof answer !== 'string' || !answer.trim()) {
        return send(res, 502, { error: 'AI_INVALID_RESPONSE', message: 'LM Studio không trả về nội dung hợp lệ.' });
      }
      await sqlModels.addMessage({
        conversationId: conversation.id,
        role: 'assistant',
        content: answer
      });
      return send(res, 200, completion);
    } catch (error) {
      return send(res, error.statusCode || 502, {
        error: 'AI_PROVIDER_UNREACHABLE',
        message: error.message
      });
    }
  }
};
