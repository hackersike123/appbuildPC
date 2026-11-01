part of '../main.dart';

void main() => runApp(const PcBuildApp());

const mint = Color(0xff63e6be);
const bg = Color(0xff070a0f);
const panel = Color(0xff10161f);
const panel2 = Color(0xff171e28);
const stroke = Color(0xff263140);
const muted = Color(0xff8d99a8);
const greenPanel = Color(0xff173f38);
const _androidLifecycleChannel = MethodChannel('appbuildpc/app_lifecycle');

Future<void> _moveAppToBackground() async {
  try {
    await _androidLifecycleChannel.invokeMethod<void>('moveToBackground');
  } catch (_) {
    // The native handler is only available on Android. Keep web and widget
    // tests usable if the platform channel is not installed.
  }
}

Widget _keepAndroidAppInBackgroundOnRootBack(
  BuildContext context, {
  required Widget child,
}) {
  final canPopRoute = Navigator.of(context).canPop();
  final moveToBackground =
      !kIsWeb &&
      defaultTargetPlatform == TargetPlatform.android &&
      !canPopRoute;

  return PopScope<Object?>(
    canPop: !moveToBackground,
    onPopInvokedWithResult: (didPop, _) {
      if (!didPop && moveToBackground) {
        unawaited(_moveAppToBackground());
      }
    },
    child: child,
  );
}

Future<bool> requestLocationPermission(BuildContext context) async {
  if (kIsWeb) {
    return false;
  }
  final status = await Permission.locationWhenInUse.request();
  return status.isGranted;
}

Future<bool> requestCameraPermission(BuildContext context) async {
  if (kIsWeb) return true;
  final status = await Permission.camera.request();
  return status.isGranted;
}

void showMessage(BuildContext context, String message) {
  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
}

void showDemoMessage(BuildContext context, String message) {
  showMessage(context, message);
}

double productPriceInMillions(String value) {
  if (value.contains('tr')) {
    return double.parse(value.replaceAll(',', '.').replaceAll('tr', ''));
  }
  final digits = value.replaceAll('.', '').replaceAll(RegExp(r'[^0-9]'), '');
  return (double.tryParse(digits) ?? 0) / 1000000;
}

double? parseApiNumber(dynamic value) {
  if (value is num) return value.toDouble();
  return double.tryParse(value?.toString().trim() ?? '');
}

String formatVnd(dynamic value) {
  final amount = (parseApiNumber(value) ?? 0).round().toString();
  final grouped = amount.replaceAllMapped(
    RegExp(r'\B(?=(\d{3})+(?!\d))'),
    (_) => '.',
  );
  return '$groupedđ';
}

bool matchesCatalogSearch(String value, String query) {
  final name = value.toLowerCase();
  final term = query.trim().toLowerCase();
  if (term.isEmpty) return true;
  if (!RegExp(r'^\d+$').hasMatch(term)) return name.contains(term);
  var start = 0;
  while (true) {
    final index = name.indexOf(term, start);
    if (index < 0) return false;
    final end = index + term.length;
    final beforeIsDigit =
        index > 0 && _isAsciiDigit(name.codeUnitAt(index - 1));
    final afterIsDigit =
        end < name.length && _isAsciiDigit(name.codeUnitAt(end));
    if (!beforeIsDigit && !afterIsDigit) return true;
    start = index + 1;
  }
}

bool _isAsciiDigit(int codeUnit) => codeUnit >= 48 && codeUnit <= 57;
