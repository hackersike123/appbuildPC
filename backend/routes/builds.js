const sqlModels = require('../sql-models');
const { send } = require('../http-utils');
const { money, decodePathPart, componentTypes, hasUsableProductPrice, buildView, compatibility } = require('../build-service');

module.exports = async function handleBuildRoutes(context) {
  const { req, res, method, url, parts, body, user, id } = context;
  if (method === 'POST' && parts.join('/') === 'api/v1/builds') {
    const { randomUUID } = require('crypto');
    const name = String(body.name || 'Build mới').trim();
    const budget = money(body.budget ?? 20000000);
    const areaId = String(body.areaId || user.areaId || '').trim();
    if (name.length < 2 || name.length > 60) {
      return send(res, 422, { error: 'INVALID_BUILD_NAME', message: 'Tên cấu hình phải từ 2 đến 60 ký tự.' });
    }
    const areas = await sqlModels.listAreas();
    if (budget <= 0 || !areas.some((area) => area.id === areaId)) {
      return send(res, 422, { error: 'INVALID_BUILD', message: 'Ngân sách và khu vực hợp lệ là bắt buộc.' });
    }
    const build = await sqlModels.insertBuild({
      id: randomUUID(),
      userId: user.id,
      name,
      budget,
      areaId,
      components: {},
      version: 1,
      status: 'draft',
      updatedAt: new Date().toISOString()
    });
    return send(res, 201, await buildView(build));
  }
  if (method === 'GET' && parts.join('/') === 'api/v1/builds') {
    const builds = await sqlModels.listBuildsByUser(user.id);
    return send(res, 200, await Promise.all(builds.map(buildView)));
  }
  if (parts[0] === 'api' && parts[1] === 'v1' && parts[2] === 'builds' && parts[3]) {
    const build = await sqlModels.getBuildById(parts[3], user.id);
    if (!build) return send(res, 404, { error: 'BUILD_NOT_FOUND' });
    if (method === 'GET') return send(res, 200, await buildView(build));
    if (method === 'DELETE') {
      const deleted = await sqlModels.deleteBuild(build.id, user.id);
      return deleted
        ? send(res, 204, {})
        : send(res, 404, { error: 'BUILD_NOT_FOUND' });
    }
    if (method === 'PUT' && parts.length === 4) {
      if (body.expectedVersion !== undefined && Number(body.expectedVersion) !== Number(build.version || 1)) {
        return send(res, 409, { error: 'BUILD_VERSION_CONFLICT', message: 'Cấu hình đã thay đổi ở nơi khác.', latest: await buildView(build) });
      }
      const fields = { expectedVersion: body.expectedVersion };
      if (body.name !== undefined) {
        const name = String(body.name).trim();
        if (name.length < 2) return send(res, 422, { error: 'INVALID_BUILD_NAME', message: 'Tên cấu hình phải có ít nhất 2 ký tự.' });
        if (name.length > 60) return send(res, 422, { error: 'INVALID_BUILD_NAME', message: 'Tên cấu hình không được dài quá 60 ký tự.' });
        fields.name = name;
      }
      if (body.budget !== undefined) {
        fields.budget = money(body.budget);
        if (fields.budget <= 0) return send(res, 422, { error: 'INVALID_BUILD_BUDGET' });
      }
      if (body.areaId !== undefined) {
        fields.areaId = String(body.areaId);
        const areas = await sqlModels.listAreas();
        if (!areas.some((area) => area.id === fields.areaId)) {
          return send(res, 422, { error: 'INVALID_AREA' });
        }
      }
      const updated = await sqlModels.updateBuild(build.id, user.id, fields);
      if (!updated) {
        const latest = await sqlModels.getBuildById(build.id, user.id);
        return send(res, 409, {
          error: 'BUILD_VERSION_CONFLICT',
          message: 'Cấu hình đã thay đổi ở nơi khác.',
          latest: latest ? await buildView(latest) : null
        });
      }
      return send(res, 200, await buildView(updated));
    }
    if (method === 'PUT' && parts[4] === 'components' && parts[5]) {
      if (body.expectedVersion !== undefined && Number(body.expectedVersion) !== Number(build.version || 1)) {
        return send(res, 409, { error: 'BUILD_VERSION_CONFLICT', message: 'Cấu hình đã thay đổi ở nơi khác.', latest: await buildView(build) });
      }
      const componentType = decodePathPart(parts[5]);
      if (!componentTypes.includes(componentType)) {
        return send(res, 422, { error: 'INVALID_COMPONENT_TYPE', message: 'Loại linh kiện không hợp lệ.' });
      }
      const components = { ...build.components };
      if (body.productId === null || body.productId === undefined || body.productId === '') {
        delete components[componentType];
      } else {
        const item = await sqlModels.getProductById(body.productId, build.areaId);
        if (!item || item.type !== componentType) {
          return send(res, 422, { error: 'INVALID_COMPONENT', message: `Sản phẩm không thuộc loại ${componentType}.` });
        }
        if (!hasUsableProductPrice(item)) {
          return send(res, 422, { error: 'PRICE_UNAVAILABLE', message: 'Sản phẩm chưa có giá SQL nên chưa thể thêm vào cấu hình.' });
        }
        components[componentType] = item.id;
      }
      const updated = await sqlModels.updateBuild(build.id, user.id, {
        components,
        expectedVersion: body.expectedVersion
      });
      if (!updated) {
        const latest = await sqlModels.getBuildById(build.id, user.id);
        return send(res, 409, {
          error: 'BUILD_VERSION_CONFLICT',
          message: 'Cấu hình đã thay đổi ở nơi khác.',
          latest: latest ? await buildView(latest) : null
        });
      }
      return send(res, 200, await buildView(updated));
    }
    if (method === 'POST' && parts[4] === 'duplicate') {
      const name = String(body.name || `${build.name} (bản sao)`).trim();
      if (name.length < 2 || name.length > 60) return send(res, 422, { error: 'INVALID_BUILD_NAME' });
      const copy = {
        id: require('crypto').randomUUID(),
        userId: user.id,
        name,
        budget: build.budget,
        areaId: build.areaId,
        components: { ...build.components },
        version: 1,
        status: build.status || 'draft',
        updatedAt: new Date().toISOString()
      };
      const duplicate = await sqlModels.insertBuild(copy);
      return send(res, 201, await buildView(duplicate));
    }
    if (method === 'POST' && parts[4] === 'check') {
      const catalog = await sqlModels.listProducts({ areaId: build.areaId });
      const report = compatibility(build.components, catalog);
      if (report.selectedCount < 2) return send(res, 422, { error: 'INSUFFICIENT_COMPONENTS', message: 'Cần ít nhất hai linh kiện để kiểm tra tương thích.', selectedCount: report.selectedCount });
      return send(res, 200, report);
    }
  }
  if (method === 'POST' && parts.join('/') === 'api/v1/compatibility/check') {
    const areaId = String(body.areaId || user.areaId || 'hcm');
    const catalog = await sqlModels.listProducts({ areaId });
    const report = compatibility(body.components || {}, catalog);
    if (report.selectedCount < 2) return send(res, 422, { error: 'INSUFFICIENT_COMPONENTS', message: 'Cần ít nhất hai linh kiện để kiểm tra tương thích.', selectedCount: report.selectedCount });
    return send(res, 200, report);
  }
};
