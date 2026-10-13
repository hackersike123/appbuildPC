class AIConfig {
  static const baseUrl = String.fromEnvironment(
    'LM_STUDIO_URL',
    defaultValue: 'http://localhost:3105/v1',
  );
  static const model = String.fromEnvironment(
    'LM_STUDIO_MODEL',
    defaultValue: 'qwen3-vl-8b-instruct',
  );
  static const apiKey = String.fromEnvironment('LM_STUDIO_API_KEY');
  static const enabled = bool.fromEnvironment(
    'LM_STUDIO_ENABLED',
    defaultValue: true,
  );
}
