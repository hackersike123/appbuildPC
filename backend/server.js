require('dotenv').config();

const http = require('node:http');
const sqlModels = require('./sql-models');
const route = require('./routes');
const { send } = require('./http-utils');
const aiService = require('./ai-service');
const buildService = require('./build-service');

async function ensureSqlSchema() {
  await sqlModels.ensureFeatureSchema();
}

const PORT = Number(process.env.PORT || 3000);
const server = http.createServer((req, res) => route(req, res).catch((error) => send(res, error.statusCode || 500, { error: error.statusCode === 413 ? 'PAYLOAD_TOO_LARGE' : error.statusCode === 400 ? 'INVALID_JSON' : 'INTERNAL_ERROR', message: error.message })));
if (require.main === module) {
  ensureSqlSchema()
    .catch((error) => console.error('Failed to load API reference data: ' + error.message))
    .finally(() => server.listen(PORT, '0.0.0.0', () => console.log('PCBUILD API listening on port ' + PORT)));
}
module.exports = {
  server,
  route,
  compatibility: buildService.compatibility,
  powerAssessment: buildService.powerAssessment,
  pcChatNeedsExpertReview: aiService.pcChatNeedsExpertReview,
  scanCompletionMatchesCatalog: aiService.scanCompletionMatchesCatalog,
  hasVisibleSkuEvidence: aiService.hasVisibleSkuEvidence,
  hasUsableProductPrice: buildService.hasUsableProductPrice,
  normalizeBuildName: buildService.normalizeBuildName,
  catalogPromptSelection: buildService.catalogPromptSelection,
  catalogForVisionCandidate: aiService.catalogForVisionCandidate,
  selectSqlBuild: buildService.selectSqlBuild,
};