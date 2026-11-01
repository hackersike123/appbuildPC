const sqlModels = require('../sql-models');
const { send } = require('../http-utils');
const { completionText, hasVisibleSkuEvidence, requestVisionWithLmStudio } = require('../ai-service');
const { parseModelJson } = require('../build-service');

module.exports = async function handleScanRoutes(context) {
  const { req, res, method, url, parts, body, user, id } = context;
  if (method === 'GET' && parts.join('/') === 'api/v1/scans') {
    const scans = await sqlModels.listScansByUser(user.id);
    return send(res, 200, scans);
  }
  if (method === 'GET' && parts[0] === 'api' && parts[1] === 'v1' && parts[2] === 'scans' && parts[3] && parts.length === 4) {
    const scan = await sqlModels.getScanById(parts[3], user.id);
    return scan ? send(res, 200, scan) : send(res, 404, { error: 'SCAN_NOT_FOUND' });
  }
  if (method === 'DELETE' && parts[0] === 'api' && parts[1] === 'v1' && parts[2] === 'scans' && parts[3] && parts.length === 4) {
    const deleted = await sqlModels.deleteScan(parts[3], user.id);
    return deleted ? send(res, 204, {}) : send(res, 404, { error: 'SCAN_NOT_FOUND' });
  }
  if (method === 'POST' && parts.join('/') === 'api/v1/ai/scan') {
    const imageData = String(body.imageBase64 || '').replace(/^data:[^,]+,/, '');
    const imageMimeType = String(body.imageMimeType || 'image/jpeg').toLowerCase();
    if (!imageData || imageData.length > 6_000_000 || !['image/jpeg', 'image/png', 'image/webp'].includes(imageMimeType)) {
      return send(res, 422, { error: 'INVALID_SCAN_IMAGE', message: 'Ảnh không hợp lệ hoặc vượt quá dung lượng cho phép.' });
    }
    try {
      const catalog = await sqlModels.listProducts({ areaId: user.areaId });
      const system = [
        'Đây là lượt nhận diện ảnh của LM Studio. Phân loại linh kiện và đọc nguyên văn chữ/model/SKU; đồng thời mô tả hãng, họ sản phẩm và đặc điểm nhìn thấy để tìm ứng viên SQL gần giống.',
        'Chỉ nhận một trong tám nhóm linh kiện: CPU, MAINBOARD, GPU, RAM, SSD, PSU, CASE, TẢN NHIỆT.',
        'Không khẳng định model nếu không có bằng chứng. Trả duy nhất JSON: {"componentType":string|null,"visibleText":string,"brand":string|null,"modelFamily":string|null,"visualDescription":string,"confidence":number,"summary":string}.'
      ].join('\n');
      const scanMessages = [
        { role: 'system', content: system },
        { role: 'user', content: [
          { type: 'text', text: 'Phân tích ảnh và đọc nguyên văn nhãn/model/SKU nhìn thấy được.' },
          { type: 'image_url', image_url: { url: `data:${imageMimeType};base64,${imageData}` } }
        ] }
      ];
      const vision = await requestVisionWithLmStudio(
        scanMessages,
        catalog,
        { temperature: 0.1, topP: 0.5, maxTokens: 300, timeoutMs: 240000 }
      );
      const completion = vision.completion;
      const modelText = completionText(completion);
      let recognition;
      try {
        recognition = parseModelJson(modelText);
      } catch {
        recognition = { recognized: false, productId: null, componentType: null, confidence: 0, summary: String(modelText || 'AI chưa nhận diện được sản phẩm.') };
      }
      const confidence = Math.max(0, Math.min(1, Number(recognition.confidence) || 0));
      const rawAnalysis = String(recognition.summary || modelText || 'AI chưa nhận diện được sản phẩm.');
      const analysisSignalsUncertainty = /chưa đủ rõ|không đủ rõ|không chắc|chưa thể xác nhận|chưa xác định|chưa phân biệt|nhiều khả năng|nhiều bản ghi|nhiều sản phẩm|bản ghi cụ thể|có thể là|phân biệt|mơ hồ|không đọc được|không xác định được|uncertain|ambiguous|not sure|cannot confirm/i.test(rawAnalysis);
      const canConfirmFromModel = recognition.recognized === true && confidence >= 0.9 && !analysisSignalsUncertainty;
      let selectedProduct = canConfirmFromModel
        ? catalog.find((item) => item.id === String(recognition.productId || '')) || null
        : null;
      if (canConfirmFromModel && !selectedProduct && recognition.name) {
        const normalizedName = String(recognition.name).trim().toLowerCase();
        selectedProduct = catalog.find((item) => item.name.toLowerCase() === normalizedName) || null;
      }
      const exactMatchNeedsConfirmation = Boolean(
        selectedProduct && !hasVisibleSkuEvidence(selectedProduct, vision.firstVision)
      );
      if (exactMatchNeedsConfirmation) selectedProduct = null;
      const rawExpectedType = String(recognition.componentType || vision.firstVision.componentType || '').toUpperCase();
      const expectedType = ({
        'GRAPHICS CARD': 'GPU',
        'VIDEO CARD': 'GPU',
        VGA: 'GPU',
        MOTHERBOARD: 'MAINBOARD',
        MEMORY: 'RAM',
        COOLER: 'TẢN NHIỆT',
        'CPU COOLER': 'TẢN NHIỆT',
        'POWER SUPPLY': 'PSU',
        'POWER SUPPLY UNIT': 'PSU',
        STORAGE: 'SSD',
        HDD: 'SSD',
        CHASSIS: 'CASE',
        'PC CASE': 'CASE'
      })[rawExpectedType] || rawExpectedType;
      const modelCandidateIds = Array.isArray(recognition.candidateProductIds)
        ? recognition.candidateProductIds.map((value) => String(value))
        : [];
      if (recognition.productId && !selectedProduct) modelCandidateIds.unshift(String(recognition.productId));
      const candidateById = new Map(catalog.map((item) => [item.id, item]));
      const candidateProducts = [];
      const addCandidate = (candidateId) => {
        const candidate = candidateById.get(candidateId);
        if (candidate && (!expectedType || candidate.type === expectedType) && !candidateProducts.some((item) => item.id === candidate.id)) {
          candidateProducts.push(candidate);
        }
      };
      for (const candidate of (vision.candidateCatalog || []).slice(0, 2)) {
        addCandidate(candidate.id);
      }
      for (const candidateId of modelCandidateIds) {
        addCandidate(candidateId);
        if (candidateProducts.length >= 5) break;
      }
      if (selectedProduct) {
        candidateProducts.splice(0, candidateProducts.length, selectedProduct);
      } else {
        for (const candidate of vision.candidateCatalog || []) {
          addCandidate(candidate.id);
          if (candidateProducts.length >= 5) break;
        }
      }
      const candidates = candidateProducts.map((item, index) => ({
        productId: item.id,
        model: item.name,
        confidence: selectedProduct ? confidence : Math.max(0.15, Math.min(0.89, confidence || (0.65 - index * 0.08)))
      }));
      const unverifiedProduct = exactMatchNeedsConfirmation
        ? candidateById.get(String(recognition.productId || ''))
        : null;
      const analysis = selectedProduct
        ? rawAnalysis
        : candidateProducts.length
          ? exactMatchNeedsConfirmation && unverifiedProduct
            ? `Ảnh cho thấy ${expectedType || 'một linh kiện PC'}. AI nghiêng về mẫu ${unverifiedProduct.name}, nhưng model/SKU không nhìn thấy rõ trong ảnh nên chưa xác nhận. Đây là gợi ý trong SQL; hãy chọn mẫu phù hợp để tạo build tương tự.`
            : `${rawAnalysis}\n\nChưa xác nhận chính xác SKU. Đây là các ứng viên gần giống trong SQL; chọn đúng mẫu để tạo build tương tự.`
          : `${rawAnalysis}\n\nChưa tìm thấy ứng viên phù hợp trong catalog SQL. Hãy chụp rõ nhãn/model sản phẩm.`;
      const scan = {
        id: id('scan'),
        userId: user.id,
        status: selectedProduct ? 'recognized' : candidateProducts.length ? 'awaiting_confirmation' : 'unrecognized',
        detectedProductId: selectedProduct?.id || null,
        confirmedByUser: false,
        candidates,
        analysis: analysis.slice(0, 8000),
        imageMimeType,
        imageData,
        createdAt: new Date().toISOString()
      };
      await sqlModels.createScan(scan);
      return send(res, 201, {
        ...scan,
        product: selectedProduct,
        candidateProducts: candidateProducts.map((item, index) => ({
          ...item,
          confidence: candidates[index]?.confidence ?? confidence
        }))
      });
    } catch (error) {
      return send(res, error.statusCode || 502, { error: 'AI_SCAN_FAILED', message: error.message });
    }
  }
  if (method === 'POST' && parts.join('/') === 'api/v1/scans') {
    const candidateIds = Array.isArray(body.candidateProductIds) ? body.candidateProductIds : [];
    const catalog = await sqlModels.listProducts({ areaId: user.areaId });
    const catalogById = new Map(catalog.map((item) => [item.id, item]));
    const candidates = candidateIds.map((candidateId) => catalogById.get(candidateId)).filter(Boolean).map((item) => ({
      productId: item.id,
      model: item.name,
      confidence: Number(body.confidenceByProduct?.[item.id] || body.confidence || 0) || null
    }));
    const detectedProductId = catalogById.get(String(body.confirmedProductId || ''))?.id || null;
    const scan = {
      id: id('scan'),
      userId: user.id,
      status: detectedProductId ? 'confirmed' : (candidates.length ? 'awaiting_confirmation' : 'pending_analysis'),
      detectedProductId,
      candidates,
      confirmedByUser: Boolean(detectedProductId),
      createdAt: new Date().toISOString()
    };
    await sqlModels.createScan(scan);
    return send(res, 201, { ...scan, product: catalogById.get(scan.detectedProductId) || null });
  }
  if (method === 'POST' && parts[0] === 'api' && parts[1] === 'v1' && parts[2] === 'scans' && parts[4] === 'confirm') {
    const scan = await sqlModels.getScanById(parts[3], user.id);
    const catalog = await sqlModels.listProducts({ areaId: user.areaId });
    const selected = catalog.find((item) => item.id === String(body.productId || ''));
    if (!scan) return send(res, 404, { error: 'SCAN_NOT_FOUND' });
    if (!selected || !scan.candidates.some((candidate) => candidate.productId === selected.id)) {
      return send(res, 422, { error: 'INVALID_SCAN_CANDIDATE', message: 'Sản phẩm xác nhận phải nằm trong danh sách nhận diện.' });
    }
    await sqlModels.confirmScan(scan.id, user.id, selected.id);
    const confirmed = await sqlModels.getScanById(scan.id, user.id);
    return send(res, 200, { ...confirmed, product: selected });
  }
};
