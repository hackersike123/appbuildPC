class AIConfig {
  static const enabled = bool.fromEnvironment(
    'LM_STUDIO_ENABLED',
    defaultValue: true,
  );
}
