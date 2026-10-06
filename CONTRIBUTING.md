# Contributing

## Development setup

```bash
flutter pub get
flutter analyze
flutter test
```

Run the app with `flutter run -d chrome` or an Android device/emulator.

## Branches and pull requests

- Keep `main` stable and release-ready.
- Use descriptive branches such as `feature/login-validation`,
  `fix/android-permissions`, or `chore/ci`.
- Keep commits focused and avoid committing `build/`, `.dart_tool/`, credentials,
  signing keys, or generated IDE files.
- Every pull request should explain the user-visible change and include the
  commands used for validation.

## Scope

The current app is a local demo. Do not introduce production credentials,
real user data, or API keys into the repository. Backend integrations should
be added behind explicit configuration and documented separately.
