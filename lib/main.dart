// The screen-level async actions intentionally report through their active route.
// ignore_for_file: use_build_context_synchronously

import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:geolocator/geolocator.dart';
import 'package:image_picker/image_picker.dart';
import 'package:permission_handler/permission_handler.dart';

import 'api_client.dart';

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

class Product {
  const Product(
    this.name,
    this.price,
    this.detail,
    this.image, {
    this.used = false,
    this.hasPrice = true,
    this.priceEstimate = false,
    this.id = '',
    this.powerW = 0,
    this.priceSource = 'missing',
  });
  final String name;
  final String price;
  final String detail;
  final String image;
  final bool used;
  final bool hasPrice;
  final bool priceEstimate;
  final String id;
  final int powerW;
  final String priceSource;
}

class PcBuildApp extends StatelessWidget {
  const PcBuildApp({super.key});
  @override
  Widget build(BuildContext context) => MaterialApp(
    debugShowCheckedModeBanner: false,
    title: 'PCBUILD LOCAL',
    theme: ThemeData(
      brightness: Brightness.dark,
      scaffoldBackgroundColor: bg,
      colorScheme: const ColorScheme.dark(primary: mint, surface: bg),
      fontFamily: 'Arial',
      appBarTheme: const AppBarTheme(backgroundColor: bg, elevation: 0),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: const Color(0xff0c121a),
        labelStyle: const TextStyle(color: muted),
        hintStyle: const TextStyle(color: muted),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.all(Radius.circular(12)),
          borderSide: BorderSide(color: stroke),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.all(Radius.circular(12)),
          borderSide: BorderSide(color: stroke),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.all(Radius.circular(12)),
          borderSide: BorderSide(color: mint),
        ),
      ),
    ),
    home: Uri.base.queryParameters['token']?.isNotEmpty == true
        ? ResetPasswordScreen(token: Uri.base.queryParameters['token']!)
        : const WelcomeScreen(),
  );
}

class ResetPasswordScreen extends StatefulWidget {
  const ResetPasswordScreen({super.key, required this.token});
  final String token;

  @override
  State<ResetPasswordScreen> createState() => _ResetPasswordScreenState();
}

class _ResetPasswordScreenState extends State<ResetPasswordScreen> {
  final password = TextEditingController();
  final confirmation = TextEditingController();
  bool busy = false;

  @override
  void dispose() {
    password.dispose();
    confirmation.dispose();
    super.dispose();
  }

  Future<void> _reset() async {
    if (busy) return;
    if (password.text.length < 8 || password.text != confirmation.text) {
      showDemoMessage(
        context,
        'Mật khẩu phải có ít nhất 8 ký tự và hai ô phải giống nhau.',
      );
      return;
    }
    setState(() => busy = true);
    try {
      await ApiClient.instance.resetPassword(widget.token, password.text);
      if (!mounted) return;
      showDemoMessage(context, 'Đã đổi mật khẩu. Bạn có thể đăng nhập.');
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => const LoginScreen()),
      );
    } on ApiException catch (error) {
      if (mounted) showDemoMessage(context, error.message);
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: bg,
    body: Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 390),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Icon(Icons.lock_reset, color: mint, size: 48),
              const SizedBox(height: 18),
              const Text(
                'ĐẶT LẠI MẬT KHẨU',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 24),
              TextField(
                controller: password,
                obscureText: true,
                decoration: const InputDecoration(
                  labelText: 'Mật khẩu mới',
                  prefixIcon: Icon(Icons.lock_outline),
                ),
              ),
              const SizedBox(height: 14),
              TextField(
                controller: confirmation,
                obscureText: true,
                decoration: const InputDecoration(
                  labelText: 'Nhập lại mật khẩu mới',
                  prefixIcon: Icon(Icons.lock_outline),
                ),
              ),
              const SizedBox(height: 20),
              PrimaryButton(
                text: busy ? 'ĐANG CẬP NHẬT...' : 'ĐẶT LẠI MẬT KHẨU',
                onPressed: _reset,
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

class Shell extends StatelessWidget {
  const Shell({
    super.key,
    required this.child,
    this.title,
    this.subtitle,
    this.back = false,
    this.action,
    this.bottomNavigationBar,
  });
  final Widget child;
  final String? title;
  final String? subtitle;
  final bool back;
  final Widget? action;
  final Widget? bottomNavigationBar;
  @override
  Widget build(BuildContext context) => _keepAndroidAppInBackgroundOnRootBack(
    context,
    child: Scaffold(
      appBar: title == null
          ? null
          : AppBar(
              automaticallyImplyLeading: false,
              titleSpacing: 18,
              leading: back
                  ? IconButton(
                      onPressed: () => Navigator.pop(context),
                      icon: const Icon(Icons.chevron_left),
                    )
                  : null,
              title: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title!,
                    style: const TextStyle(
                      fontSize: 21,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  if (subtitle != null)
                    Text(
                      subtitle!,
                      style: const TextStyle(fontSize: 12, color: muted),
                    ),
                ],
              ),
              actions: [?action, const SizedBox(width: 10)],
            ),
      body: child,
      bottomNavigationBar: bottomNavigationBar,
    ),
  );
}

class WelcomeScreen extends StatefulWidget {
  const WelcomeScreen({super.key});
  @override
  State<WelcomeScreen> createState() => _WelcomeScreenState();
}

class _WelcomeScreenState extends State<WelcomeScreen> {
  String areaId = 'hcm';
  String areaName = 'TP. Hồ Chí Minh';
  bool loadingArea = false;

  @override
  Widget build(BuildContext context) => Shell(
    child: SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(18, 18, 18, 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Brand(),
            const SizedBox(height: 16),
            ClipRRect(
              borderRadius: BorderRadius.circular(18),
              child: Image.asset(
                'assets/figma/hero.jpg',
                height: 300,
                width: double.infinity,
                fit: BoxFit.cover,
              ),
            ),
            const SizedBox(height: 16),
            const Tag('GIÁ THẬT • GẦN BẠN'),
            const SizedBox(height: 10),
            const Text(
              'Build đúng cấu hình.\nMua đúng giá khu vực.',
              style: TextStyle(fontSize: 30, height: 1.08),
            ),
            const SizedBox(height: 10),
            const Text(
              'So sánh linh kiện mới & cũ, kiểm tra tương thích và tham khảo giá tại nơi bạn sống.',
              style: TextStyle(color: muted, height: 1.5),
            ),
            const SizedBox(height: 16),
            const InfoTile(
              icon: Icons.location_on_outlined,
              text: 'Cho phép vị trí để xem giá tại TP. Hồ Chí Minh',
            ),
            const SizedBox(height: 16),
            PrimaryButton(
              text: 'Bắt đầu với vị trí của tôi',
              onPressed: loadingArea
                  ? () {}
                  : () => _startWithLocation(context),
            ),
            const SizedBox(height: 10),
            SecondaryButton(
              text: 'Chọn khu vực thủ công',
              onPressed: loadingArea ? () {} : () => _chooseArea(context),
            ),
          ],
        ),
      ),
    ),
  );
  Future<void> _startWithLocation(BuildContext context) async {
    setState(() => loadingArea = true);
    Position? position;
    try {
      final granted = await requestLocationPermission(context);
      if (granted) {
        position = await Geolocator.getCurrentPosition();
      }
      final result = await ApiClient.instance.resolveLocation(
        lat: position?.latitude,
        lng: position?.longitude,
      );
      if (!mounted) return;
      final area = Map<String, dynamic>.from(result['area'] as Map);
      areaId = area['id'] as String;
      areaName = area['name'] as String;
      showMessage(
        context,
        position == null
            ? 'Không lấy được GPS. Hãy chọn khu vực thủ công.'
            : 'Đã xác định khu vực theo GPS.',
      );
      _openLogin();
    } catch (_) {
      if (mounted) {
        showMessage(
          context,
          position == null
              ? 'Không lấy được GPS. Hãy chọn khu vực thủ công.'
              : 'Đã xác định khu vực theo GPS.',
        );
        _openLogin();
      }
    } finally {
      if (mounted) setState(() => loadingArea = false);
    }
  }

  Future<void> _chooseArea(BuildContext context) async {
    setState(() => loadingArea = true);
    try {
      final areas = await ApiClient.instance.areas();
      if (!mounted) return;
      final chosen = await showModalBottomSheet<Map<String, dynamic>>(
        context: context,
        backgroundColor: panel2,
        builder: (sheetContext) => SafeArea(
          child: ListView(
            shrinkWrap: true,
            padding: const EdgeInsets.all(18),
            children: [
              const Text(
                'Chọn khu vực',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 12),
              ...areas.map(
                (area) => ListTile(
                  title: Text(area['name'] as String),
                  trailing: area['id'] == areaId
                      ? const Icon(Icons.check, color: mint)
                      : null,
                  onTap: () => Navigator.pop(sheetContext, area),
                ),
              ),
            ],
          ),
        ),
      );
      if (chosen != null && mounted) {
        final result = await ApiClient.instance.resolveLocation(
          areaId: chosen['id'] as String,
        );
        final area = Map<String, dynamic>.from(result['area'] as Map);
        areaId = area['id'] as String;
        areaName = area['name'] as String;
        _openLogin();
      }
    } catch (_) {
      if (mounted) {
        showDemoMessage(context, 'Không tải được danh sách khu vực.');
      }
    } finally {
      if (mounted) setState(() => loadingArea = false);
    }
  }

  void _openLogin() => Navigator.pushReplacement(
    context,
    MaterialPageRoute(
      builder: (_) => LoginScreen(areaId: areaId, areaName: areaName),
    ),
  );
}

class LoginScreen extends StatefulWidget {
  const LoginScreen({
    super.key,
    this.areaId = 'hcm',
    this.areaName = 'TP. Hồ Chí Minh',
  });
  final String areaId;
  final String areaName;
  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final formKey = GlobalKey<FormState>();
  final email = TextEditingController();
  final password = TextEditingController();
  bool obscurePassword = true;
  bool busy = false;
  @override
  void dispose() {
    email.dispose();
    password.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Shell(
    child: Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 390),
        child: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(18, 38, 18, 24),
            child: Form(
              key: formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Logo(),
                  const SizedBox(height: 14),
                  const Text(
                    'PCBUILD LOCAL',
                    style: TextStyle(color: mint, fontSize: 11),
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    'Chào mừng trở lại',
                    style: TextStyle(fontSize: 29),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Đăng nhập để đồng bộ và lưu mọi cấu hình.',
                    style: TextStyle(color: muted),
                  ),
                  const SizedBox(height: 42),
                  const FieldLabel('EMAIL'),
                  TextField(
                    controller: email,
                    keyboardType: TextInputType.emailAddress,
                    decoration: InputDecoration(
                      prefixIcon: const Icon(Icons.mail_outline),
                      hintText: 'minh.nguyen@email.com',
                      errorText:
                          email.text.isNotEmpty && !email.text.contains('@')
                          ? 'Email chưa hợp lệ'
                          : null,
                    ),
                    onChanged: (_) => setState(() {}),
                  ),
                  const SizedBox(height: 14),
                  const FieldLabel('MẬT KHẨU'),
                  TextField(
                    controller: password,
                    obscureText: obscurePassword,
                    decoration: InputDecoration(
                      prefixIcon: const Icon(Icons.lock_outline),
                      hintText: '••••••••••',
                      suffixIcon: IconButton(
                        onPressed: () =>
                            setState(() => obscurePassword = !obscurePassword),
                        icon: Icon(
                          obscurePassword
                              ? Icons.visibility
                              : Icons.visibility_off,
                        ),
                      ),
                    ),
                  ),
                  Align(
                    alignment: Alignment.centerRight,
                    child: TextButton(
                      onPressed: () => _showForgotPassword(context),
                      child: const Text(
                        'Quên mật khẩu?',
                        style: TextStyle(color: mint),
                      ),
                    ),
                  ),
                  PrimaryButton(
                    text: 'Đăng nhập',
                    onPressed: busy
                        ? () {}
                        : () async {
                            if (!email.text.contains('@') ||
                                password.text.length < 6) {
                              showDemoMessage(
                                context,
                                'Email hợp lệ và mật khẩu tối thiểu 8 ký tự là bắt buộc.',
                              );
                              return;
                            }
                            setState(() => busy = true);
                            try {
                              await ApiClient.instance.login(
                                email.text.trim(),
                                password.text,
                              );
                            } on ApiException catch (error) {
                              if (!context.mounted) return;
                              showDemoMessage(
                                context,
                                error.statusCode == 401
                                    ? 'Email hoặc mật khẩu không đúng. Nếu chưa có tài khoản, hãy đăng ký trước.'
                                    : error.message,
                              );
                              return;
                            } catch (_) {
                              if (!context.mounted) return;
                              showDemoMessage(
                                context,
                                'Không kết nối được máy chủ. Hãy chạy backend tại cổng 3000.',
                              );
                              return;
                            }
                            if (!context.mounted) return;
                            Navigator.pushReplacement(
                              context,
                              MaterialPageRoute(
                                builder: (_) => MainScreen(
                                  areaId: widget.areaId,
                                  areaName: widget.areaName,
                                ),
                              ),
                            );
                          },
                  ),
                  Center(
                    child: TextButton(
                      onPressed: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => SignupScreen(
                            areaId: widget.areaId,
                            areaName: widget.areaName,
                          ),
                        ),
                      ),
                      child: const Text(
                        'Chưa có tài khoản?  Đăng ký ngay',
                        style: TextStyle(color: muted),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    ),
  );

  Future<void> _showForgotPassword(BuildContext context) async {
    final controller = TextEditingController(text: email.text);
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: panel2,
        title: const Text('Khôi phục mật khẩu'),
        content: TextField(
          controller: controller,
          keyboardType: TextInputType.emailAddress,
          decoration: const InputDecoration(
            labelText: 'Email nhận hướng dẫn',
            prefixIcon: Icon(Icons.mail_outline),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Hủy'),
          ),
          ElevatedButton(
            onPressed: () {
              if (!controller.text.contains('@')) {
                showDemoMessage(context, 'Vui lòng nhập email hợp lệ.');
                return;
              }
              ApiClient.instance
                  .forgotPassword(controller.text.trim())
                  .then((_) {
                    if (!context.mounted) return;
                    Navigator.pop(dialogContext);
                    showDemoMessage(
                      context,
                      'Nếu email tồn tại, hướng dẫn khôi phục đã được gửi.',
                    );
                  })
                  .catchError((_) {
                    if (context.mounted) {
                      showDemoMessage(
                        context,
                        'Không gửi được yêu cầu. Hãy thử lại sau.',
                      );
                    }
                  });
            },
            child: const Text('Gửi hướng dẫn'),
          ),
        ],
      ),
    );
    controller.dispose();
  }
}

class SignupScreen extends StatefulWidget {
  const SignupScreen({
    super.key,
    this.areaId = 'hcm',
    this.areaName = 'TP. Hồ Chí Minh',
  });
  final String areaId;
  final String areaName;
  @override
  State<SignupScreen> createState() => _SignupScreenState();
}

class _SignupScreenState extends State<SignupScreen> {
  final name = TextEditingController();
  final email = TextEditingController();
  final password = TextEditingController();
  late final TextEditingController area;
  late String selectedAreaId;
  bool acceptedTerms = false;
  bool obscurePassword = true;
  bool busy = false;

  @override
  void dispose() {
    name.dispose();
    email.dispose();
    password.dispose();
    area.dispose();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    area = TextEditingController(text: widget.areaName);
    selectedAreaId = widget.areaId;
  }

  Future<void> _chooseArea() async {
    try {
      final areas = await ApiClient.instance.areas();
      if (!mounted) return;
      final chosen = await showModalBottomSheet<Map<String, dynamic>>(
        context: context,
        backgroundColor: panel,
        builder: (sheetContext) => SafeArea(
          child: ListView(
            shrinkWrap: true,
            children: [
              const Padding(
                padding: EdgeInsets.all(18),
                child: Text(
                  'Chọn khu vực định giá',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 17),
                ),
              ),
              ...areas.map(
                (item) => ListTile(
                  title: Text(item['name'] as String),
                  trailing: item['id'] == selectedAreaId
                      ? const Icon(Icons.check, color: mint)
                      : null,
                  onTap: () => Navigator.pop(sheetContext, item),
                ),
              ),
            ],
          ),
        ),
      );
      if (chosen == null || !mounted) return;
      final result = await ApiClient.instance.resolveLocation(
        areaId: chosen['id'] as String,
      );
      final resolved = Map<String, dynamic>.from(result['area'] as Map);
      setState(() {
        selectedAreaId = resolved['id'] as String;
        area.text = resolved['name'] as String;
      });
    } catch (_) {
      if (mounted) {
        showDemoMessage(context, 'Không tải được danh sách khu vực.');
      }
    }
  }

  @override
  Widget build(BuildContext context) => Shell(
    title: 'Tạo tài khoản',
    subtitle: 'Lưu build, theo dõi giá và nhận tư vấn',
    back: true,
    child: Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 390),
        child: SafeArea(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(18, 18, 18, 24),
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: greenPanel,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Text(
                  '✓ Lưu cấu hình không giới hạn\n✓ Cập nhật giá mới / cũ theo khu vực\n✓ Cảnh báo tương thích tự động',
                  style: TextStyle(height: 1.6),
                ),
              ),
              const SizedBox(height: 18),
              const FieldLabel('HỌ VÀ TÊN'),
              TextField(
                controller: name,
                decoration: InputDecoration(
                  prefixIcon: const Icon(Icons.person_outline),
                  hintText: 'Nguyễn Minh Anh',
                ),
              ),
              const SizedBox(height: 14),
              const FieldLabel('EMAIL'),
              TextField(
                controller: email,
                keyboardType: TextInputType.emailAddress,
                decoration: InputDecoration(
                  prefixIcon: const Icon(Icons.mail_outline),
                  hintText: 'minhanh@email.com',
                ),
              ),
              const SizedBox(height: 14),
              const FieldLabel('MẬT KHẨU'),
              TextField(
                controller: password,
                obscureText: obscurePassword,
                decoration: InputDecoration(
                  prefixIcon: const Icon(Icons.lock_outline),
                  hintText: 'Tối thiểu 8 ký tự',
                  suffixIcon: IconButton(
                    onPressed: () =>
                        setState(() => obscurePassword = !obscurePassword),
                    icon: Icon(
                      obscurePassword ? Icons.visibility : Icons.visibility_off,
                    ),
                  ),
                ),
              ),
              const FieldLabel('KHU VỰC ĐỊNH GIÁ'),
              InkWell(
                borderRadius: BorderRadius.circular(12),
                onTap: _chooseArea,
                child: IgnorePointer(
                  child: TextField(
                    controller: area,
                    readOnly: true,
                    decoration: const InputDecoration(
                      prefixIcon: Icon(Icons.location_on_outlined),
                      suffixIcon: Icon(Icons.keyboard_arrow_down),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              CheckboxListTile(
                value: acceptedTerms,
                onChanged: (value) =>
                    setState(() => acceptedTerms = value ?? false),
                dense: true,
                contentPadding: EdgeInsets.zero,
                activeColor: mint,
                checkColor: bg,
                title: const Text(
                  'Tôi đồng ý Điều khoản sử dụng và Chính sách bảo mật.',
                  style: TextStyle(color: muted, fontSize: 12),
                ),
              ),
              const SizedBox(height: 16),
              PrimaryButton(
                text: 'Tạo tài khoản',
                onPressed: busy ? () {} : () => _createAccount(context),
              ),
              Center(
                child: TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text(
                    'Đã có tài khoản?  Đăng nhập',
                    style: TextStyle(color: muted),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );

  Future<void> _createAccount(BuildContext context) async {
    final errors = <String>[];
    if (name.text.trim().length < 2) errors.add('họ tên');
    if (!email.text.contains('@')) errors.add('email hợp lệ');
    if (password.text.length < 8) errors.add('mật khẩu từ 8 ký tự');
    if (area.text.trim().isEmpty) errors.add('khu vực định giá');
    if (!acceptedTerms) errors.add('đồng ý điều khoản');
    if (errors.isNotEmpty) {
      showDemoMessage(context, 'Vui lòng kiểm tra: ${errors.join(', ')}.');
      return;
    }
    setState(() => busy = true);
    try {
      await ApiClient.instance.register(
        name.text.trim(),
        email.text.trim(),
        password.text,
        areaId: selectedAreaId,
      );
      await ApiClient.instance.login(email.text.trim(), password.text);
      if (!context.mounted) return;
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (_) =>
              MainScreen(areaId: selectedAreaId, areaName: area.text),
        ),
      );
    } on ApiException catch (error) {
      if (context.mounted) {
        showDemoMessage(context, error.message);
      }
    } catch (_) {
      if (context.mounted) {
        showDemoMessage(
          context,
          'Không kết nối được máy chủ. Hãy chạy backend tại cổng 3000.',
        );
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }
}

class MainScreen extends StatefulWidget {
  const MainScreen({
    super.key,
    this.areaId = 'hcm',
    this.areaName = 'TP. Hồ Chí Minh',
  });
  final String areaId;
  final String areaName;
  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> {
  final _homeKey = GlobalKey<_HomeTabState>();
  final _buildKey = GlobalKey<_BuildTabState>();
  int tab = 0;
  int savedVersion = 0;
  late String areaId = widget.areaId;
  late String areaName = widget.areaName;
  @override
  Widget build(BuildContext context) => _keepAndroidAppInBackgroundOnRootBack(
    context,
    child: Scaffold(
      body: IndexedStack(
        index: tab,
        children: [
          HomeTab(
            key: _homeKey,
            onOpen: _open,
            onTabOpen: _switchTab,
            areaId: areaId,
            areaName: areaName,
            onAreaChanged: (id, name) => setState(() {
              areaId = id;
              areaName = name;
            }),
          ),
          BuildTab(key: _buildKey),
          SavedTab(key: ValueKey(savedVersion)),
          ChatTab(onOpenBuild: _openBuildTab),
          AccountTab(
            onAreaChanged: (id, name) => setState(() {
              areaId = id;
              areaName = name;
            }),
          ),
        ],
      ),
      bottomNavigationBar: SizedBox(
        height: 72,
        child: NavigationBar(
          backgroundColor: panel,
          indicatorColor: Colors.transparent,
          labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
          selectedIndex: tab,
          onDestinationSelected: _switchTab,
          destinations: const [
            NavigationDestination(
              icon: Icon(Icons.home_outlined),
              selectedIcon: Icon(Icons.home),
              label: 'Trang chủ',
            ),
            NavigationDestination(
              icon: Icon(Icons.memory_outlined),
              selectedIcon: Icon(Icons.memory),
              label: 'Build',
            ),
            NavigationDestination(
              icon: Icon(Icons.bookmark_border),
              selectedIcon: Icon(Icons.bookmark),
              label: 'Đã lưu',
            ),
            NavigationDestination(
              icon: Icon(Icons.chat_bubble_outline),
              selectedIcon: Icon(Icons.chat_bubble),
              label: 'Tư vấn',
            ),
            NavigationDestination(
              icon: Icon(Icons.person_outline),
              selectedIcon: Icon(Icons.person),
              label: 'Tài khoản',
            ),
          ],
        ),
      ),
    ),
  );
  void _open(Widget page) =>
      Navigator.push(context, MaterialPageRoute(builder: (_) => page));

  void _switchTab(int value) {
    setState(() {
      tab = value;
      if (value == 2) savedVersion++;
    });
    if (value == 0) _homeKey.currentState?._loadBuild();
    if (value == 1) _buildKey.currentState?._loadLatestBuild();
  }

  void _openBuildTab() => _switchTab(1);
}

class HomeTab extends StatefulWidget {
  const HomeTab({
    super.key,
    required this.onOpen,
    required this.onTabOpen,
    required this.onAreaChanged,
    this.areaId = 'hcm',
    this.areaName = 'TP. Hồ Chí Minh',
  });
  final void Function(Widget) onOpen;
  final void Function(int) onTabOpen;
  final String areaId;
  final String areaName;
  final void Function(String id, String name) onAreaChanged;
  @override
  State<HomeTab> createState() => _HomeTabState();
}

class _HomeTabState extends State<HomeTab> {
  late String currentAreaId = widget.areaId;
  late String currentAreaName = widget.areaName;
  bool loadingMarket = true;
  List<Map<String, dynamic>> marketItems = const [];
  String? marketError;
  String? marketUpdatedAt;
  Map<String, dynamic>? activeBuild;
  bool loadingBuild = true;
  List<Map<String, dynamic>> notifications = const [];

  @override
  void initState() {
    super.initState();
    _loadMarket();
    _loadBuild();
    _loadNotifications();
  }

  @override
  void didUpdateWidget(covariant HomeTab oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.areaId != widget.areaId ||
        oldWidget.areaName != widget.areaName) {
      currentAreaId = widget.areaId;
      currentAreaName = widget.areaName;
      loadingMarket = true;
      _loadMarket();
    }
  }

  Future<void> _loadNotifications() async {
    try {
      final items = await ApiClient.instance.notifications();
      if (mounted) setState(() => notifications = items);
    } catch (_) {}
  }

  Future<void> _openNotifications() async {
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: panel,
      builder: (sheetContext) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            const Padding(
              padding: EdgeInsets.all(18),
              child: Text(
                'Thông báo',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 17),
              ),
            ),
            if (notifications.isEmpty)
              const Padding(
                padding: EdgeInsets.fromLTRB(18, 0, 18, 24),
                child: Text(
                  'Bạn chưa có thông báo mới.',
                  style: TextStyle(color: muted),
                ),
              )
            else
              ...notifications.map(
                (item) => ListTile(
                  leading: const Icon(Icons.notifications_none, color: mint),
                  title: Text(item['title'] as String? ?? 'Thông báo'),
                  subtitle: Text(item['message'] as String? ?? ''),
                ),
              ),
          ],
        ),
      ),
    );
    if (notifications.any((item) => item['read'] == false)) {
      await ApiClient.instance.markNotificationsRead();
      if (mounted) {
        setState(() {
          notifications = notifications
              .map((item) => {...item, 'read': true})
              .toList();
        });
      }
    }
  }

  Future<void> _loadBuild() async {
    try {
      final builds = await ApiClient.instance.builds();
      if (!mounted) return;
      setState(() {
        activeBuild = builds.isEmpty ? null : builds.first;
        loadingBuild = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => loadingBuild = false);
    }
  }

  Future<void> _changeArea() async {
    try {
      final areas = await ApiClient.instance.areas();
      if (!mounted) return;
      final chosen = await showModalBottomSheet<Map<String, dynamic>>(
        context: context,
        backgroundColor: panel,
        builder: (sheetContext) => SafeArea(
          child: ListView(
            shrinkWrap: true,
            children: [
              const Padding(
                padding: EdgeInsets.all(18),
                child: Text(
                  'Chọn khu vực định giá',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 17),
                ),
              ),
              ...areas.map(
                (item) => ListTile(
                  title: Text(item['name'] as String),
                  trailing: item['id'] == currentAreaId
                      ? const Icon(Icons.check, color: mint)
                      : null,
                  onTap: () => Navigator.pop(sheetContext, item),
                ),
              ),
            ],
          ),
        ),
      );
      if (chosen == null || !mounted) return;
      final result = await ApiClient.instance.resolveLocation(
        areaId: chosen['id'] as String,
      );
      final area = Map<String, dynamic>.from(result['area'] as Map);
      await ApiClient.instance.updateProfile(areaId: area['id'] as String);
      currentAreaId = area['id'] as String;
      currentAreaName = area['name'] as String;
      if (mounted) {
        setState(() {
          loadingMarket = true;
          marketError = null;
        });
      }
      widget.onAreaChanged(currentAreaId, currentAreaName);
      await _loadMarket();
    } catch (_) {
      if (mounted) {
        showDemoMessage(context, 'Không tải được danh sách khu vực.');
      }
    }
  }

  Future<void> _loadMarket() async {
    try {
      final result = await ApiClient.instance.marketSummary(currentAreaId);
      final items = (result['items'] as List? ?? const [])
          .map((item) => Map<String, dynamic>.from(item as Map))
          .toList();
      if (!mounted) return;
      setState(() {
        marketItems = items;
        marketUpdatedAt = result['updatedAt']?.toString();
        marketError = null;
        loadingMarket = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        marketError = 'Chưa tải được dữ liệu giá';
        loadingMarket = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) => Shell(
    child: SafeArea(
      child: ListView(
        padding: const EdgeInsets.fromLTRB(18, 28, 18, 20),
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Xin chào, ${ApiClient.instance.currentUser?['name'] ?? 'bạn'} 👋',
                    style: TextStyle(fontSize: 21, fontWeight: FontWeight.bold),
                  ),
                  SizedBox(height: 4),
                  Text(
                    'Sẵn sàng lên cấu hình mới?',
                    style: TextStyle(color: muted, fontSize: 12),
                  ),
                ],
              ),
              InkWell(
                onTap: _openNotifications,
                borderRadius: BorderRadius.circular(20),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 9,
                  ),
                  decoration: BoxDecoration(
                    color: panel2,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.notifications_none, size: 16),
                      if (notifications.any(
                        (item) => item['read'] == false,
                      )) ...[
                        const SizedBox(width: 5),
                        Flexible(
                          child: Text(
                            '${notifications.where((item) => item['read'] == false).length}',
                            overflow: TextOverflow.ellipsis,
                            softWrap: false,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: _changeArea,
            child: InfoTile(
              icon: Icons.location_on_outlined,
              text: 'Giá theo khu vực · $currentAreaName',
              trailing: 'Thay đổi',
            ),
          ),
          const SizedBox(height: 16),
          InfoTile(
            icon: Icons.check_circle_outline,
            text:
                'Giá thị trường tại $currentAreaName\nNguồn: SQL • ${marketUpdatedAt == null ? 'đang tải thời điểm cập nhật' : 'cập nhật ${marketUpdatedAt!.replaceFirst('T', ' ').split('.').first}'}',
          ),
          const SizedBox(height: 16),
          MarketCard(
            items: marketItems,
            loading: loadingMarket,
            error: marketError,
            onTap: () => widget.onOpen(
              MarketChangesScreen(
                areaName: currentAreaName,
                items: marketItems,
              ),
            ),
          ),
          const SizedBox(height: 18),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Lối vào nhanh',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
              Text(
                'Tối ưu một tay',
                style: TextStyle(color: muted, fontSize: 11),
              ),
            ],
          ),
          const SizedBox(height: 10),
          GridView.count(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            crossAxisCount: 2,
            childAspectRatio: 1.65,
            crossAxisSpacing: 10,
            mainAxisSpacing: 10,
            children: [
              QuickCard(
                icon: Icons.memory,
                text: 'Build PC',
                onTap: () => widget.onTabOpen(1),
              ),
              QuickCard(
                icon: Icons.camera_alt_outlined,
                text: 'Quét SP',
                onTap: () => widget.onOpen(
                  ScannerScreen(
                    onOpenBuild: () {
                      Navigator.of(context).pop();
                      Navigator.of(context).pop();
                      widget.onTabOpen(1);
                    },
                  ),
                ),
              ),
              QuickCard(
                icon: Icons.scatter_plot,
                text: 'So giá',
                onTap: () => widget.onOpen(const CompareProductsScreen()),
              ),
              QuickCard(
                icon: Icons.chat_bubble_outline,
                text: 'Tư vấn',
                onTap: () => widget.onOpen(
                  ChatTab(
                    onOpenBuild: () {
                      Navigator.of(context).pop();
                      widget.onTabOpen(1);
                    },
                  ),
                ),
              ),
              QuickCard(
                icon: Icons.category_outlined,
                text: 'Chọn linh kiện',
                onTap: () => widget.onTabOpen(1),
              ),
              QuickCard(
                icon: Icons.bookmark_border,
                text: 'Cấu hình đã lưu',
                onTap: () => widget.onTabOpen(2),
              ),
            ],
          ),
          const SizedBox(height: 18),
          BuildProgress(
            buildData: activeBuild,
            loading: loadingBuild,
            onContinue: activeBuild == null ? null : () => widget.onTabOpen(1),
          ),
        ],
      ),
    ),
  );
}

class BuildTab extends StatefulWidget {
  const BuildTab({super.key, this.initialBuild, this.loadLatest = true});
  final Map<String, dynamic>? initialBuild;
  final bool loadLatest;
  @override
  State<BuildTab> createState() => _BuildTabState();
}

class _BuildTabState extends State<BuildTab> {
  bool saved = false;
  bool loadingBuild = false;
  Map<String, dynamic>? loadedBuild;
  final selectedIds = <String, String>{};
  final powers = <String, int>{};
  final missingPriceTypes = <String>{};
  final estimatePriceTypes = <String>{};
  final selected = <String, String>{
    'CPU': 'Chọn CPU',
    'MAINBOARD': 'Chọn MAINBOARD',
    'GPU': 'Chọn GPU',
    'RAM': 'Chọn RAM',
    'SSD': 'Chọn SSD',
    'PSU': 'Chọn nguồn',
    'CASE': 'Chọn CASE',
    'TẢN NHIỆT': 'Chọn tản nhiệt',
  };
  final prices = <String, double>{};
  Timer? _compatibilityDebounce;
  Map<String, dynamic>? liveCompatibility;
  bool checkingCompatibility = false;
  bool get isComplete =>
      selected.values.every((value) => !value.startsWith('Chọn'));
  bool get canCheckCompatibility => selectedIds.length >= 2;
  Map<String, dynamic>? get _currentBuild => loadedBuild ?? widget.initialBuild;
  String get _buildTitle => _currentBuild?['name']?.toString() ?? 'Build mới';
  String get _buildSubtitle {
    final areaId = _currentBuild?['areaId']?.toString();
    const areas = {
      'hcm': 'TP. Hồ Chí Minh',
      'hanoi': 'Hà Nội',
      'danang': 'Đà Nẵng',
    };
    final area = areas[areaId] ?? 'Khu vực hiện tại';
    final selectedCount = selected.values
        .where((value) => !value.startsWith('Chọn'))
        .length;
    return '$selectedCount/8 linh kiện • $area';
  }

  @override
  void initState() {
    super.initState();
    final build = widget.initialBuild;
    if (build == null) {
      ApiClient.instance.buildId = null;
      if (widget.loadLatest) _loadLatestBuild();
      return;
    }
    _applyBuild(build);
  }

  Future<void> reloadLatestBuild() => _loadLatestBuild();

  Future<void> _loadLatestBuild() async {
    if (ApiClient.instance.token == null) return;
    setState(() => loadingBuild = true);
    try {
      final builds = await ApiClient.instance.builds();
      if (!mounted) return;
      if (builds.isEmpty) {
        ApiClient.instance.buildId = null;
        return;
      }
      _applyBuild(builds.first);
    } catch (error) {
      if (mounted) {
        showMessage(context, 'Không tải được cấu hình gần nhất: $error');
      }
    } finally {
      if (mounted) setState(() => loadingBuild = false);
    }
  }

  void _applyBuild(Map<String, dynamic> build) {
    loadedBuild = build;
    ApiClient.instance.buildId = build['id'] as String?;
    selectedIds.clear();
    powers.clear();
    prices.clear();
    selected.updateAll(
      (type, _) => type == 'PSU' ? 'Chọn nguồn' : 'Chọn $type',
    );
    missingPriceTypes.clear();
    estimatePriceTypes.clear();
    final components = build['components'];
    if (components is! Map) return;
    for (final entry in components.entries) {
      final type = entry.key.toString();
      final item = entry.value;
      if (item is Map) {
        selected[type] = item['name']?.toString() ?? selected[type]!;
        final itemPrice = parseApiNumber(item['price']) ?? 0;
        prices[type] = itemPrice / 1000000;
        if (itemPrice <= 0) {
          missingPriceTypes.add(type);
        } else if (item['priceSource'] != 'market') {
          estimatePriceTypes.add(type);
        }
        selectedIds[type] = item['id']?.toString() ?? '';
        powers[type] = (parseApiNumber(item['power']) ?? 0).toInt();
      }
    }
    if (mounted) setState(() {});
    if (selectedIds.length >= 2) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _scheduleCompatibilityCheck();
      });
    }
  }

  Future<void> _openCompatibilityDetails() async {
    final changed = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => CompatibilityScreen(report: liveCompatibility),
      ),
    );
    if (changed == true) await _loadLatestBuild();
  }

  Future<void> _choose(String type) async {
    final result = await Navigator.push<Product>(
      context,
      MaterialPageRoute(
        builder: (_) => ProductListScreen(
          componentType: type,
          areaId:
              _currentBuild?['areaId']?.toString() ??
              ApiClient.instance.currentUser?['areaId']?.toString() ??
              'hcm',
          onSelected: (product) => Navigator.pop(context, product),
        ),
      ),
    );
    if (result != null) {
      final productId = result.id;
      setState(() {
        selected[type] = result.name;
        prices[type] = productPriceInMillions(result.price);
        missingPriceTypes.remove(type);
        if (result.priceSource == 'market') {
          estimatePriceTypes.remove(type);
        } else {
          estimatePriceTypes.add(type);
        }
        powers[type] = result.powerW;
        saved = false;
        if (productId.isNotEmpty) {
          selectedIds[type] = productId;
        }
      });
      if (ApiClient.instance.token == null) {
        if (mounted) {
          showDemoMessage(
            context,
            'Đã chọn tạm. Hãy đăng nhập để đồng bộ linh kiện vào tài khoản.',
          );
        }
        return;
      }
      if (productId.isEmpty) {
        if (mounted) {
          showDemoMessage(context, 'Sản phẩm chưa có mã API hợp lệ.');
        }
        return;
      }
      selectedIds[type] = productId;
      try {
        final updatedBuild = await ApiClient.instance.updateComponent(
          type,
          productId,
        );
        if (mounted) {
          setState(() => loadedBuild = updatedBuild);
          _scheduleCompatibilityCheck();
        }
      } catch (error) {
        if (mounted) {
          showDemoMessage(context, 'Chưa đồng bộ được linh kiện: $error');
        }
      }
    }
  }

  void _scheduleCompatibilityCheck() {
    _compatibilityDebounce?.cancel();
    if (selectedIds.length < 2 || ApiClient.instance.token == null) {
      setState(() {
        liveCompatibility = null;
        checkingCompatibility = false;
      });
      return;
    }
    setState(() {
      checkingCompatibility = true;
      liveCompatibility = null;
    });
    _compatibilityDebounce = Timer(const Duration(milliseconds: 450), () async {
      final selectedSnapshot = Map<String, String>.from(selectedIds);
      try {
        final report = await ApiClient.instance.checkBuild(selectedSnapshot);
        if (mounted && mapEquals(selectedSnapshot, selectedIds)) {
          setState(() {
            liveCompatibility = report;
            checkingCompatibility = false;
          });
        }
      } catch (error) {
        if (mounted) {
          setState(() {
            checkingCompatibility = false;
            liveCompatibility = {
              'status': 'error',
              'message': 'Chưa kiểm tra được: $error',
            };
          });
        }
      }
    });
  }

  @override
  void dispose() {
    _compatibilityDebounce?.cancel();
    super.dispose();
  }

  Future<void> _removeComponent(String type) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Xóa linh kiện?'),
        content: Text('Bạn muốn gỡ bỏ $type khỏi cấu hình này?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Hủy'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Xóa', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      if (ApiClient.instance.token == null ||
          ApiClient.instance.buildId == null) {
        if (mounted) {
          showDemoMessage(context, 'Hãy lưu cấu hình trước khi xóa linh kiện.');
        }
        return;
      }
      try {
        final updatedBuild = await ApiClient.instance.updateComponent(
          type,
          null,
        );
        if (!mounted) return;
        setState(() {
          selected[type] = 'Chọn $type';
          prices[type] = 0;
          missingPriceTypes.remove(type);
          estimatePriceTypes.remove(type);
          selectedIds.remove(type);
          loadedBuild = updatedBuild;
          saved = false;
        });
        _scheduleCompatibilityCheck();
        showDemoMessage(context, 'Đã gỡ bỏ $type khỏi cấu hình.');
      } catch (error) {
        if (mounted) {
          showDemoMessage(context, 'Lỗi khi xóa linh kiện: $error');
        }
      }
    }
  }

  Future<void> _deleteCurrentBuild() async {
    final id = _currentBuild?['id']?.toString();
    if (id == null) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Xóa cấu hình?'),
        content: const Text('Cấu hình này sẽ bị xóa khỏi tài khoản.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Hủy'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Xóa'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await ApiClient.instance.deleteBuild(id);
      if (mounted) {
        if (widget.initialBuild != null) {
          showDemoMessage(context, 'Đã xóa cấu hình.');
          Navigator.pop(context, true);
        } else {
          setState(() {
            loadedBuild = null;
            saved = false;
            selectedIds.clear();
            powers.clear();
            prices.clear();
            missingPriceTypes.clear();
            estimatePriceTypes.clear();
            selected.updateAll(
              (type, _) => type == 'PSU' ? 'Chọn nguồn' : 'Chọn $type',
            );
          });
          ApiClient.instance.buildId = null;
          showDemoMessage(context, 'Đã xóa cấu hình.');
        }
      }
    } catch (error) {
      if (mounted) showDemoMessage(context, 'Không thể xóa cấu hình: $error');
    }
  }

  String _total() {
    if (missingPriceTypes.isNotEmpty) return 'Thiếu giá SQL';
    final total = prices.values.fold<double>(0, (sum, value) => sum + value);
    final formatted = '${total.toStringAsFixed(2).replaceAll('.', ',')}tr';
    return estimatePriceTypes.isEmpty ? formatted : '$formatted*';
  }

  int get _estimatedPower =>
      selectedIds.keys.fold<int>(0, (sum, type) => sum + (powers[type] ?? 0));
  int get _recommendedPsu {
    if (selectedIds.isEmpty) return 0;
    final fromApi =
        parseApiNumber(_currentBuild?['recommendedPsu'])?.round() ?? 0;
    final gpu = selected['GPU'];
    final manufacturerMinimum =
        ApiClient.instance.productRecommendedPsuByName[gpu] ?? 0;
    final calculated = ((_estimatedPower * 1.3 + 100 + 49) / 50).floor() * 50;
    return math
        .max(450, math.max(fromApi, math.max(manufacturerMinimum, calculated)))
        .clamp(450, 2000)
        .toInt();
  }

  Future<void> _saveBuild() async {
    if (missingPriceTypes.isNotEmpty) {
      showDemoMessage(context, 'Hãy bổ sung giá SQL trước khi lưu build này.');
      return;
    }
    final selectedCount = selectedIds.values
        .where((productId) => productId.isNotEmpty)
        .length;
    if (selectedCount == 0) {
      showDemoMessage(context, 'Hãy chọn ít nhất một linh kiện trước khi lưu.');
      return;
    }
    if (ApiClient.instance.token == null) {
      showDemoMessage(context, 'Hãy đăng nhập để lưu cấu hình vào tài khoản.');
      return;
    }
    try {
      if (ApiClient.instance.buildId == null) {
        await ApiClient.instance.createBuild();
      }
      for (final entry in selectedIds.entries) {
        if (entry.value.isNotEmpty) {
          await ApiClient.instance.updateComponent(entry.key, entry.value);
        }
      }
      if (!mounted) return;
      setState(() => saved = true);
      showDemoMessage(
        context,
        selectedCount == selected.length
            ? 'Đã lưu đầy đủ cấu hình lên tài khoản.'
            : 'Đã lưu $selectedCount/8 linh kiện lên tài khoản.',
      );
    } catch (error) {
      if (mounted) showDemoMessage(context, 'Không thể lưu cấu hình: $error');
    }
  }

  @override
  Widget build(BuildContext context) => Shell(
    title: _buildTitle,
    subtitle: _buildSubtitle,
    action: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        TextButton.icon(
          onPressed: _saveBuild,
          icon: Icon(saved ? Icons.check : Icons.bookmark_border, color: mint),
          label: Text(
            saved ? 'Đã lưu' : 'Lưu',
            style: const TextStyle(color: mint),
          ),
        ),
        if (_currentBuild != null)
          IconButton(
            tooltip: 'Xóa cấu hình',
            onPressed: _deleteCurrentBuild,
            icon: const Icon(Icons.delete_outline, color: Colors.redAccent),
          ),
      ],
    ),
    child: SafeArea(
      child: ListView(
        padding: const EdgeInsets.fromLTRB(18, 6, 18, 20),
        children: [
          ProgressLine(
            label: 'TIẾN ĐỘ BUILD',
            value: '${(selectedIds.length / selected.length * 100).round()}%',
            progress: selectedIds.length / 8,
          ),
          ProgressLine(
            label: 'TẢI ƯỚC TÍNH • PSU ĐỀ NGHỊ',
            value: selectedIds.isEmpty
                ? 'Chưa đủ dữ liệu'
                : '~${_estimatedPower}W tải • ≥${_recommendedPsu}W nguồn',
            progress: selectedIds.isEmpty || _recommendedPsu == 0
                ? 0
                : (_estimatedPower / _recommendedPsu)
                      .clamp(0.0, 1.0)
                      .toDouble(),
            amber: true,
          ),
          if (checkingCompatibility)
            const CardBox(
              child: Row(
                children: [
                  SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                  SizedBox(width: 10),
                  Text('Đang kiểm tra tương thích…'),
                ],
              ),
            ),
          if (liveCompatibility != null)
            _LiveCompatibilitySummary(
              report: liveCompatibility!,
              onDetails: _openCompatibilityDetails,
            ),
          PCAssemblyPreview(installedTypes: selectedIds.keys.toSet()),
          ...selected.entries.map(
            (item) => ComponentRow(
              type: item.key,
              name: item.value,
              price: missingPriceTypes.contains(item.key)
                  ? 'Thiếu giá SQL'
                  : (prices[item.key] ?? 0) == 0
                  ? '–'
                  : estimatePriceTypes.contains(item.key)
                  ? '~${prices[item.key]!.toStringAsFixed(2).replaceAll('.', ',')}tr'
                  : '${prices[item.key]!.toStringAsFixed(2).replaceAll('.', ',')}tr',
              onTap: () => _choose(item.key),
              onDelete: item.value.startsWith('Chọn')
                  ? null
                  : () => _removeComponent(item.key),
            ),
          ),
          const SizedBox(height: 18),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Tag(
                selectedIds.length < 2
                    ? '⚠ CHỌN THÊM LINH KIỆN'
                    : isComplete
                    ? '✓ ĐỦ 8 LINH KIỆN'
                    : '✓ CÓ THỂ KIỂM TRA',
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  const Text(
                    'TẠM TÍNH',
                    style: TextStyle(color: muted, fontSize: 10),
                  ),
                  Text(
                    _total(),
                    style: const TextStyle(color: mint, fontSize: 21),
                  ),
                  if (missingPriceTypes.isNotEmpty ||
                      estimatePriceTypes.isNotEmpty)
                    Text(
                      missingPriceTypes.isNotEmpty
                          ? '${missingPriceTypes.length} món chưa có giá; tổng chưa hoàn chỉnh.'
                          : '* Giá ước tính, chưa phải giá thị trường.',
                      textAlign: TextAlign.end,
                      style: const TextStyle(color: Colors.orange, fontSize: 9),
                    ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 12),
          SecondaryButton(
            text: 'Kiểm tra tương thích',
            onPressed: () async {
              if (!canCheckCompatibility) {
                showDemoMessage(
                  context,
                  'Cần chọn ít nhất hai linh kiện để kiểm tra.',
                );
                return;
              }
              if (ApiClient.instance.token != null) {
                try {
                  final report = await ApiClient.instance.checkBuild(
                    selectedIds,
                  );
                  if (!mounted) return;
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => CompatibilityScreen(report: report),
                    ),
                  );
                  return;
                } catch (error) {
                  if (mounted) {
                    showDemoMessage(context, 'Không kiểm tra được: $error');
                  }
                  return;
                }
              }
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const CompatibilityScreen()),
              );
            },
          ),
        ],
      ),
    ),
  );
}

class PCAssemblyPreview extends StatefulWidget {
  const PCAssemblyPreview({super.key, required this.installedTypes});

  final Set<String> installedTypes;

  @override
  State<PCAssemblyPreview> createState() => _PCAssemblyPreviewState();
}

class _PCAssemblyPreviewState extends State<PCAssemblyPreview> {
  double rotation = 0;

  @override
  Widget build(BuildContext context) => CardBox(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'MÔ HÌNH LẮP RÁP 3D',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 4),
        const Text(
          'Kéo ngang để xoay • linh kiện sáng lên khi được thêm.',
          style: TextStyle(color: muted, fontSize: 11),
        ),
        const SizedBox(height: 10),
        SizedBox(
          height: 170,
          width: double.infinity,
          child: GestureDetector(
            onHorizontalDragUpdate: (details) => setState(() {
              rotation = (rotation + details.delta.dx * .012) % (2 * math.pi);
            }),
            child: TweenAnimationBuilder<double>(
              tween: Tween<double>(
                begin: 0,
                end: widget.installedTypes.length / 8,
              ),
              duration: const Duration(milliseconds: 650),
              curve: Curves.easeOutCubic,
              builder: (context, progress, _) => CustomPaint(
                painter: _PcAssemblyPainter(
                  widget.installedTypes,
                  progress,
                  rotation,
                ),
                child: const SizedBox.expand(),
              ),
            ),
          ),
        ),
        Align(
          alignment: Alignment.centerRight,
          child: Text(
            '${widget.installedTypes.length}/8 đã lắp',
            style: const TextStyle(color: mint, fontSize: 11),
          ),
        ),
      ],
    ),
  );
}

class _PcAssemblyPainter extends CustomPainter {
  const _PcAssemblyPainter(this.installedTypes, this.progress, this.rotation);

  final Set<String> installedTypes;
  final double progress;
  final double rotation;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.scale(size.width / 300, size.height / 180);
    canvas.translate(150, 90);
    canvas.scale(math.cos(rotation).abs().clamp(.28, 1.0), 1);
    canvas.translate(-150, -90);
    final edge = Paint()
      ..color = stroke
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;
    final caseFill = Paint()..color = panel2;
    final side = Path()
      ..moveTo(63, 32)
      ..lineTo(202, 32)
      ..lineTo(241, 54)
      ..lineTo(241, 151)
      ..lineTo(102, 151)
      ..lineTo(63, 130)
      ..close();
    canvas.drawPath(side, caseFill);
    canvas.drawPath(side, edge);
    final front = Path()
      ..moveTo(63, 32)
      ..lineTo(102, 54)
      ..lineTo(102, 151)
      ..lineTo(63, 130)
      ..close();
    canvas.drawPath(front, Paint()..color = const Color(0xff202b37));
    canvas.drawPath(front, edge);
    final board = Path()
      ..moveTo(111, 60)
      ..lineTo(195, 60)
      ..lineTo(224, 76)
      ..lineTo(140, 76)
      ..close();
    _part(canvas, board, 'MAINBOARD', const Color(0xff2b8e75));
    final cpu = Path()
      ..moveTo(129, 64)
      ..lineTo(149, 64)
      ..lineTo(158, 69)
      ..lineTo(138, 69)
      ..close();
    _part(canvas, cpu, 'CPU', const Color(0xffd6913d));
    final ram = Path()
      ..moveTo(163, 61)
      ..lineTo(168, 61)
      ..lineTo(178, 67)
      ..lineTo(173, 67)
      ..close();
    _part(canvas, ram, 'RAM', const Color(0xff7694cb));
    final gpu = Path()
      ..moveTo(127, 91)
      ..lineTo(207, 91)
      ..lineTo(222, 100)
      ..lineTo(142, 100)
      ..close();
    _part(canvas, gpu, 'GPU', const Color(0xff55a8e2));
    final storage = Path()
      ..moveTo(111, 111)
      ..lineTo(143, 111)
      ..lineTo(154, 117)
      ..lineTo(122, 117)
      ..close();
    _part(canvas, storage, 'SSD', const Color(0xffa77ce0));
    final psu = Path()
      ..moveTo(113, 130)
      ..lineTo(165, 130)
      ..lineTo(178, 137)
      ..lineTo(126, 137)
      ..close();
    _part(canvas, psu, 'PSU', const Color(0xffd4a943));
    final fan = Paint()
      ..color = installedTypes.contains('CASE') ? mint : stroke
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;
    canvas.drawCircle(const Offset(82, 77), 10, fan);
    canvas.drawCircle(const Offset(82, 107), 10, fan);
    final cooler = Paint()
      ..color = installedTypes.contains('TẢN NHIỆT') ? mint : stroke
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;
    canvas.drawCircle(const Offset(147, 57), 13, cooler);
    final label = TextPainter(
      text: TextSpan(
        text: '${(progress * 100).round()}%',
        style: const TextStyle(
          color: mint,
          fontSize: 12,
          fontWeight: FontWeight.bold,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    label.paint(canvas, const Offset(250, 32));
    canvas.restore();
  }

  void _part(Canvas canvas, Path path, String type, Color color) {
    final installed = installedTypes.contains(type);
    final fill = installed
        ? Color.lerp(panel, color, .45 + .55 * progress.clamp(0.0, 1.0))!
        : panel.withValues(alpha: .85);
    canvas.drawPath(path, Paint()..color = fill);
    final outline = Paint()
      ..color = installed ? mint : stroke
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;
    canvas.drawPath(path, outline);
  }

  @override
  bool shouldRepaint(covariant _PcAssemblyPainter oldDelegate) =>
      oldDelegate.progress != progress ||
      oldDelegate.rotation != rotation ||
      !setEquals(oldDelegate.installedTypes, installedTypes);
}

class MarketChangesScreen extends StatelessWidget {
  const MarketChangesScreen({
    super.key,
    required this.areaName,
    required this.items,
  });
  final String areaName;
  final List<Map<String, dynamic>> items;

  @override
  Widget build(BuildContext context) {
    final changed = items
        .where((item) => (parseApiNumber(item['trend']) ?? 0) != 0)
        .toList();
    return Shell(
      title: 'Biến động giá',
      subtitle: areaName,
      back: true,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(18, 8, 18, 20),
        children: [
          const InfoTile(
            icon: Icons.trending_up,
            text: 'Linh kiện có thay đổi giá trong khu vực hiện tại.',
          ),
          const SizedBox(height: 12),
          ...changed.map(
            (item) => CardBox(
              child: ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(item['name']?.toString() ?? 'Linh kiện'),
                subtitle: Text(
                  'Giá trước: ${_money(item['previousPrice'])}\nGiá hiện tại: ${_money(item['price'])}',
                ),
                trailing: Text(
                  '${(parseApiNumber(item['trend']) ?? 0).toStringAsFixed(2)}%',
                  style: TextStyle(
                    color: (parseApiNumber(item['trend']) ?? 0) < 0
                        ? mint
                        : Colors.orange,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  static String _money(dynamic value) =>
      '${(parseApiNumber(value) ?? 0).toStringAsFixed(0)}đ';
}

class CompareProductsScreen extends StatefulWidget {
  const CompareProductsScreen({super.key, this.initialProductIds = const []});
  final List<String> initialProductIds;
  @override
  State<CompareProductsScreen> createState() => _CompareProductsScreenState();
}

class _CompareProductsScreenState extends State<CompareProductsScreen> {
  late Future<List<Map<String, dynamic>>> productsFuture;
  final selected = <String>{};
  Map<String, dynamic>? result;
  String query = '';
  String typeFilter = 'Tất cả';
  Timer? _searchDebounce;
  String get areaId =>
      ApiClient.instance.currentUser?['areaId']?.toString() ?? 'hcm';

  @override
  void initState() {
    super.initState();
    selected.addAll(widget.initialProductIds.take(3));
    productsFuture = ApiClient.instance.products('');
  }

  Future<void> _compare() async {
    if (selected.length < 2 || selected.length > 3) {
      showMessage(context, 'Hãy chọn từ 2 đến 3 linh kiện để so sánh.');
      return;
    }
    try {
      final response = await ApiClient.instance.compareProducts(
        selected.toList(),
        areaId: areaId,
      );
      if (mounted) setState(() => result = response);
    } catch (error) {
      if (mounted) showMessage(context, 'Không thể so giá: $error');
    }
  }

  void _compareFromButton() {
    if (selected.length < 2 || selected.length > 3) {
      showMessage(context, 'Chọn thêm ít nhất một linh kiện để so sánh.');
      return;
    }
    _compare();
  }

  void _setQuery(String value) {
    _searchDebounce?.cancel();
    _searchDebounce = Timer(const Duration(milliseconds: 250), () {
      if (mounted) setState(() => query = value.trim().toLowerCase());
    });
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Shell(
    title: 'So giá linh kiện',
    subtitle: 'Chọn từ 2 đến 3 linh kiện • SQL $areaId',
    back: true,
    bottomNavigationBar: SafeArea(
      minimum: const EdgeInsets.fromLTRB(18, 8, 18, 12),
      child: PrimaryButton(
        text: result == null
            ? 'So sánh giá (${selected.length}/2–3)'
            : 'Cập nhật so sánh (${selected.length})',
        onPressed: _compareFromButton,
      ),
    ),
    child: FutureBuilder<List<Map<String, dynamic>>>(
      future: productsFuture,
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator(color: mint));
        }
        final products = snapshot.data!;
        final visible = products.where((item) {
          final type = item['type']?.toString() ?? '';
          final name = item['name']?.toString().toLowerCase() ?? '';
          return (typeFilter == 'Tất cả' || type == typeFilter) &&
              matchesCatalogSearch(name, query);
        }).toList();
        final types =
            products.map((item) => item['type'].toString()).toSet().toList()
              ..sort();
        types.insert(0, 'Tất cả');
        return CustomScrollView(
          slivers: [
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(18, 8, 18, 8),
              sliver: SliverList(
                delegate: SliverChildListDelegate([
                  const InfoTile(
                    icon: Icons.compare_arrows,
                    text: 'So sánh giá hiện tại, thông số và lịch sử. Giá ước tính được đánh dấu; chỉ giá khu vực có lịch sử biến động.',
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    onChanged: _setQuery,
                    decoration: const InputDecoration(
                      prefixIcon: Icon(Icons.search),
                      hintText: 'Tìm tên linh kiện',
                    ),
                  ),
                  const SizedBox(height: 8),
                  DropdownButtonFormField<String>(
                    initialValue: typeFilter,
                    decoration: const InputDecoration(
                      labelText: 'Loại linh kiện',
                    ),
                    items: types
                        .map(
                          (type) =>
                              DropdownMenuItem(value: type, child: Text(type)),
                        )
                        .toList(),
                    onChanged: (value) =>
                        setState(() => typeFilter = value ?? 'Tất cả'),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '${visible.length} / ${products.length} linh kiện từ SQL',
                  ),
                  if (result != null) ...[
                    const SizedBox(height: 12),
                    const Text(
                      'SO SÁNH GIÁ',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 8),
                    ...((result!['products'] as List? ?? const []).map(
                      (item) => ComparedProductCard(
                        product: Map<String, dynamic>.from(item as Map),
                        areaId: areaId,
                      ),
                    )),
                  ],
                ]),
              ),
            ),
            SliverPadding(
              padding: const EdgeInsets.symmetric(horizontal: 18),
              sliver: SliverList(
                delegate: SliverChildBuilderDelegate((context, index) {
                  final item = visible[index];
                  final id = item['id'].toString();
                  final price = parseApiNumber(item['price']) ?? 0;
                  final hasPrice = price > 0;
                  final isEstimate = item['priceSource'] == 'catalog_estimate';
                  return CheckboxListTile(
                    value: selected.contains(id),
                    onChanged: !hasPrice
                        ? null
                        : (checked) {
                            setState(() {
                              result = null;
                              if (checked == true && selected.length < 3) {
                                selected.add(id);
                              } else if (checked != true) {
                                selected.remove(id);
                              }
                            });
                          },
                    title: Text(item['name'].toString()),
                    subtitle: Text(
                      '${item['type']} • ${!hasPrice ? 'Chưa có giá SQL' : '${isEstimate ? '≈ ' : ''}${formatVnd(price)}${isEstimate ? ' · ước tính' : ''}'}',
                    ),
                  );
                }, childCount: visible.length),
              ),
            ),
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(18, 8, 18, 20),
              sliver: SliverList(
                delegate: SliverChildListDelegate([const SizedBox(height: 8)]),
              ),
            ),
          ],
        );
      },
    ),
  );
}

class ComparedProductCard extends StatefulWidget {
  const ComparedProductCard({
    super.key,
    required this.product,
    required this.areaId,
  });
  final Map<String, dynamic> product;
  final String areaId;

  @override
  State<ComparedProductCard> createState() => _ComparedProductCardState();
}

class _ComparedProductCardState extends State<ComparedProductCard> {
  String period = 'day';
  late Future<Map<String, dynamic>> history;

  @override
  void initState() {
    super.initState();
    history = _loadHistory();
  }

  Future<Map<String, dynamic>> _loadHistory() =>
      ApiClient.instance.priceHistory(
        widget.product['id'].toString(),
        areaId: widget.areaId,
        period: period,
      );

  void _setPeriod(String value) {
    setState(() {
      period = value;
      history = _loadHistory();
    });
  }

  Future<void> _setPriceAlert() async {
    final controller = TextEditingController(
      text: (parseApiNumber(widget.product['price']) ?? 0).round().toString(),
    );
    final targetPrice = await showDialog<int>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Theo dõi giá linh kiện'),
        content: TextField(
          controller: controller,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(
            labelText: 'Thông báo khi giá xuống dưới (VNĐ)',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Hủy'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(
              dialogContext,
              int.tryParse(controller.text.replaceAll(RegExp(r'[^0-9]'), '')),
            ),
            child: const Text('Lưu cảnh báo'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (targetPrice == null || targetPrice <= 0) return;
    try {
      await ApiClient.instance.createPriceAlert(
        productId: widget.product['id'].toString(),
        targetPrice: targetPrice,
        areaId: widget.areaId,
      );
      if (mounted) showDemoMessage(context, 'Đã lưu cảnh báo giá trên SQL.');
    } catch (error) {
      if (mounted) showDemoMessage(context, 'Không lưu được cảnh báo: $error');
    }
  }

  @override
  Widget build(BuildContext context) {
    final isMarketPrice = widget.product['priceSource'] == 'market';
    return CardBox(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            widget.product['name'].toString(),
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
          Text(
            '${widget.product['type']} • ${isMarketPrice ? 'Giá khu vực SQL ${widget.areaId}' : 'Giá ước tính trong catalog SQL'}',
            style: TextStyle(
              color: isMarketPrice ? muted : Colors.orange,
              fontSize: 11,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            formatVnd(widget.product['price']),
            style: TextStyle(
              color: isMarketPrice ? mint : Colors.orange,
              fontSize: 20,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 4,
            children: [
              _specChip('Socket', widget.product['socket']),
              _specChip('RAM', widget.product['ram']),
              _specChip('Form', widget.product['form']),
              _specChip(
                'Điện',
                widget.product['power'] == null
                    ? widget.product['watts']
                    : '${widget.product['power']}W',
              ),
              _specChip(
                'Dài',
                widget.product['length'] == null
                    ? widget.product['gpuLength']
                    : '${widget.product['length']}mm',
              ),
            ],
          ),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton.icon(
              onPressed: isMarketPrice ? _setPriceAlert : null,
              icon: const Icon(Icons.notifications_active_outlined, size: 16),
              label: Text(
                isMarketPrice ? 'Theo dõi giá SQL' : 'Chưa có giá thị trường',
              ),
            ),
          ),
          const SizedBox(height: 8),
          SegmentedButton<String>(
            segments: const [
              ButtonSegment(value: 'day', label: Text('Ngày')),
              ButtonSegment(value: 'month', label: Text('Tháng')),
              ButtonSegment(value: 'year', label: Text('Năm')),
            ],
            selected: {period},
            onSelectionChanged: (value) => _setPeriod(value.first),
            showSelectedIcon: false,
          ),
          const SizedBox(height: 8),
          FutureBuilder<Map<String, dynamic>>(
            future: history,
            builder: (context, snapshot) {
              if (snapshot.connectionState != ConnectionState.done) {
                return const SizedBox(
                  height: 110,
                  child: Center(child: CircularProgressIndicator(color: mint)),
                );
              }
              if (snapshot.hasError) {
                return Text(
                  'Không tải được lịch sử giá: ${snapshot.error}',
                  style: const TextStyle(color: Colors.amber, fontSize: 11),
                );
              }
              final data = snapshot.data!;
              final points = (data['history'] as List? ?? const [])
                  .map((item) => Map<String, dynamic>.from(item as Map))
                  .toList();
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    data['priceSource'] == 'market'
                        ? 'Hiện tại ${formatVnd(data['price'])} • trước ${formatVnd(data['previousPrice'])} • ${parseApiNumber(data['changePercent'])?.toStringAsFixed(2) ?? '0.00'}%'
                        : 'Giá ước tính ${formatVnd(data['price'])} • chưa có giá khu vực SQL.',
                    style: TextStyle(
                      fontSize: 11,
                      color: data['priceSource'] == 'market'
                          ? null
                          : Colors.orange,
                    ),
                  ),
                  const SizedBox(height: 4),
                  SizedBox(
                    height: 110,
                    width: double.infinity,
                    child: CustomPaint(painter: _PriceChartPainter(points)),
                  ),
                  Text(
                    points.length < 2
                        ? data['priceSource'] != 'market'
                              ? 'Chưa có lịch sử giá thị trường để vẽ xu hướng.'
                              : 'SQL có ${points.length} mốc giá; cần thêm lịch sử để vẽ xu hướng.'
                        : '${points.length} mốc giá ${period == 'day'
                              ? 'theo ngày'
                              : period == 'month'
                              ? 'theo tháng'
                              : 'theo năm'}',
                    style: const TextStyle(color: muted, fontSize: 10),
                  ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _specChip(String label, dynamic value) {
    if (value == null || value.toString().isEmpty) {
      return const SizedBox.shrink();
    }
    return Chip(
      label: Text('$label: $value', style: const TextStyle(fontSize: 10)),
      visualDensity: VisualDensity.compact,
    );
  }
}

class _PriceChartPainter extends CustomPainter {
  const _PriceChartPainter(this.points);
  final List<Map<String, dynamic>> points;

  @override
  void paint(Canvas canvas, Size size) {
    final grid = Paint()
      ..color = stroke
      ..strokeWidth = 1;
    for (var line = 1; line <= 3; line++) {
      final y = size.height * line / 4;
      canvas.drawLine(Offset(0, y), Offset(size.width, y), grid);
    }
    final values = points
        .map((point) => parseApiNumber(point['price']) ?? 0)
        .toList();
    if (values.isEmpty) return;
    final minValue = values.reduce((a, b) => a < b ? a : b);
    final maxValue = values.reduce((a, b) => a > b ? a : b);
    final spread = (maxValue - minValue).abs();
    final path = Path();
    final linePaint = Paint()
      ..color = mint
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.5;
    for (var index = 0; index < values.length; index++) {
      final x = values.length == 1
          ? size.width / 2
          : size.width * index / (values.length - 1);
      final normalized = spread == 0 ? .5 : (values[index] - minValue) / spread;
      final y = size.height - 10 - normalized * (size.height - 20);
      if (index == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
      canvas.drawCircle(Offset(x, y), 3.5, Paint()..color = mint);
    }
    canvas.drawPath(path, linePaint);
  }

  @override
  bool shouldRepaint(covariant _PriceChartPainter oldDelegate) =>
      oldDelegate.points != points;
}

class ProductListScreen extends StatefulWidget {
  const ProductListScreen({
    super.key,
    this.componentType = 'GPU',
    this.areaId = 'hcm',
    this.onSelected,
  });
  final String componentType;
  final String areaId;
  final void Function(Product product)? onSelected;
  @override
  State<ProductListScreen> createState() => _ProductListScreenState();
}

class _ProductListScreenState extends State<ProductListScreen> {
  late Future<List<Product>> productsFuture;
  String query = '';
  int? maxPrice;
  Timer? _searchDebounce;

  @override
  void initState() {
    super.initState();
    productsFuture = _loadProducts();
  }

  Future<List<Product>> _loadProducts() async {
    try {
      final data = await ApiClient.instance.products(
        widget.componentType,
        query: query,
        maxPrice: maxPrice,
        areaId: widget.areaId,
      );
      return data.map((item) {
        final name = item['name'] as String;
        final price = parseApiNumber(item['price']);
        final hasPrice = price != null && price > 0;
        final priceEstimate = item['priceSource'] == 'catalog_estimate';
        final id = item['id']?.toString() ?? '';
        ApiClient.instance.productPriceSourceByName[name] =
            item['priceSource']?.toString() ?? 'missing';
        ApiClient.instance.productPowerByName[name] =
            (parseApiNumber(item['power']) ?? 0).toInt();
        ApiClient.instance.productRecommendedPsuByName[name] =
            (parseApiNumber(item['recommendedPsuW']) ?? 0).toInt();
        return Product(
          name,
          hasPrice
              ? '${(price / 1000000).toStringAsFixed(2).replaceAll('.', ',')}tr'
              : 'Chưa có giá SQL',
          '${item['socket'] ?? item['ram'] ?? item['form'] ?? 'Linh kiện'} · ${priceEstimate ? 'Giá ước tính' : 'Giá khu vực'}',
          item['type'] == 'GPU'
              ? 'assets/figma/gpu1.jpeg'
              : 'assets/figma/gpu2.png',
          hasPrice: hasPrice,
          priceEstimate: priceEstimate,
          id: id,
          powerW: (parseApiNumber(item['power']) ?? 0).toInt(),
          priceSource: item['priceSource']?.toString() ?? 'missing',
        );
      }).toList();
    } catch (error) {
      throw ApiException('Không tải được ${widget.componentType}: $error');
    }
  }

  void _refreshProducts({String? nextQuery, int? nextMaxPrice}) {
    setState(() {
      query = nextQuery ?? query;
      maxPrice = nextMaxPrice;
      productsFuture = _loadProducts();
    });
  }

  void _onSearchChanged(String value) {
    _searchDebounce?.cancel();
    _searchDebounce = Timer(const Duration(milliseconds: 300), () {
      if (mounted) _refreshProducts(nextQuery: value);
    });
  }

  void _selectProduct(Product product) {
    if (widget.onSelected != null) {
      if (!product.hasPrice) {
        showMessage(context, 'Chưa thể thêm sản phẩm này: chưa có giá SQL.');
        return;
      }
      widget.onSelected!(product);
      return;
    }
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const CompatibilityScreen()),
    );
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Shell(
    title: 'Chọn ${widget.componentType}',
    subtitle: 'Giá và sản phẩm lấy từ PCBUILD API',
    back: true,
    child: SafeArea(
      child: FutureBuilder<List<Product>>(
        future: productsFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator(color: mint));
          }
          if (snapshot.hasError) {
            return const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Text(
                  'Chưa tải được sản phẩm. Hãy kiểm tra backend và thử lại.',
                  style: TextStyle(color: Colors.amber),
                ),
              ),
            );
          }
          final products = snapshot.data ?? const <Product>[];
          return CustomScrollView(
            slivers: [
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(18, 4, 18, 8),
                sliver: SliverList(
                  delegate: SliverChildListDelegate([
                    TextField(
                      onChanged: _onSearchChanged,
                      decoration: const InputDecoration(
                        prefixIcon: Icon(Icons.search),
                        hintText: 'Tìm RTX 4060, RX 7600...',
                        suffixIcon: Icon(Icons.search),
                      ),
                    ),
                    const SizedBox(height: 14),
                    Wrap(
                      spacing: 8,
                      children: [
                        ActionChip(
                          label: const Text('Tất cả'),
                          onPressed: () => _refreshProducts(nextMaxPrice: null),
                        ),
                        ActionChip(
                          label: const Text('≤ 10 triệu'),
                          onPressed: () =>
                              _refreshProducts(nextMaxPrice: 10000000),
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    const InfoTile(
                      text: 'Sản phẩm lấy từ SQL; giá ước tính được đánh dấu riêng.',
                      trailing: 'SQL',
                    ),
                    const SizedBox(height: 8),
                    if (products.isEmpty)
                      const CardBox(child: Text('Không có sản phẩm phù hợp.')),
                  ]),
                ),
              ),
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(18, 0, 18, 20),
                sliver: SliverList(
                  delegate: SliverChildBuilderDelegate(
                    (context, index) => ProductCard(
                      product: products[index],
                      onTap: () => _selectProduct(products[index]),
                    ),
                    childCount: products.length,
                  ),
                ),
              ),
            ],
          );
        },
      ),
    ),
  );
}

class ScannerScreen extends StatefulWidget {
  const ScannerScreen({super.key, this.initialAnalysis, this.onOpenBuild});
  final String? initialAnalysis;
  final VoidCallback? onOpenBuild;
  @override
  State<ScannerScreen> createState() => _ScannerScreenState();
}

class _ScannerScreenState extends State<ScannerScreen> {
  bool scanned = false;
  XFile? selectedImage;
  String? analysis;
  bool analyzing = false;
  bool loadingHistory = false;
  List<Map<String, dynamic>> scanHistory = const [];

  @override
  void initState() {
    super.initState();
    analysis = widget.initialAnalysis;
    scanned = analysis != null;
    _loadHistory();
  }

  Future<void> _loadHistory() async {
    if (ApiClient.instance.token == null) return;
    setState(() => loadingHistory = true);
    try {
      final result = await ApiClient.instance.scans();
      if (mounted) setState(() => scanHistory = result);
    } catch (error) {
      if (mounted) {
        showDemoMessage(context, 'Không tải được lịch sử quét: $error');
      }
    } finally {
      if (mounted) setState(() => loadingHistory = false);
    }
  }

  Future<void> _pickAndAnalyze(ImageSource source) async {
    if (source == ImageSource.camera &&
        !await requestCameraPermission(context)) {
      return;
    }
    final image = await ImagePicker().pickImage(
      source: source,
      imageQuality: 70,
      maxWidth: 1024,
    );
    if (image == null || !mounted) return;
    if (ApiClient.instance.token == null) {
      showDemoMessage(context, 'Đăng nhập để lưu lịch sử quét vào tài khoản.');
      return;
    }
    setState(() {
      selectedImage = image;
      analysis = null;
      analyzing = true;
      scanned = true;
    });
    try {
      final bytes = await image.readAsBytes();
      if (bytes.length > 4_000_000) {
        throw ApiException(
          'Ảnh còn quá lớn. Hãy chụp lại gần hơn hoặc chọn ảnh nhỏ hơn 4 MB.',
        );
      }
      final scan = await ApiClient.instance.analyzeProductImage(
        imageBytes: bytes,
        imageMimeType: image.name.toLowerCase().endsWith('.png')
            ? 'image/png'
            : image.name.toLowerCase().endsWith('.webp')
            ? 'image/webp'
            : 'image/jpeg',
      );
      final answer =
          scan['analysis']?.toString() ?? 'AI chưa nhận diện được sản phẩm.';
      final product = scan['product'] is Map
          ? Map<String, dynamic>.from(scan['product'] as Map)
          : null;
      final candidateProducts = scan['candidateProducts'] is List
          ? (scan['candidateProducts'] as List)
                .whereType<Map>()
                .map((item) => Map<String, dynamic>.from(item))
                .toList()
          : <Map<String, dynamic>>[];
      Map<String, dynamic>? selectedProduct = product;
      if (mounted) {
        setState(() => analysis = answer);
        await _loadHistory();
        if (selectedProduct != null) {
          await _offerGeneratedBuild(scan, selectedProduct);
        } else if (candidateProducts.isNotEmpty) {
          selectedProduct = await _chooseScanCandidate(candidateProducts);
          if (selectedProduct != null) {
            await _offerGeneratedBuild(scan, selectedProduct);
          }
        }
        if (!mounted) return;
        // Keep a clean scanner route underneath consultation, while history stays in SQL.
        setState(() {
          selectedImage = null;
          analysis = null;
          scanned = false;
        });
        await Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => ChatTab(
              initialPrompt: answer,
              initialPinnedComponents: selectedProduct == null
                  ? const {}
                  : {
                      selectedProduct['type']?.toString() ?? 'GPU':
                          selectedProduct['id']?.toString() ?? '',
                    },
              onOpenBuild: widget.onOpenBuild,
            ),
          ),
        );
      }
    } catch (error) {
      if (mounted) setState(() => analysis = 'Không thể phân tích ảnh: $error');
    } finally {
      if (mounted) setState(() => analyzing = false);
    }
  }

  Future<Map<String, dynamic>?> _chooseScanCandidate(
    List<Map<String, dynamic>> candidates,
  ) => showDialog<Map<String, dynamic>>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: const Text('AI tìm được sản phẩm gần giống'),
      content: SizedBox(
        width: double.maxFinite,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Ảnh chưa đủ rõ để xác nhận SKU. Chọn một mẫu trong catalog SQL để xem cấu hình build tương tự:',
              ),
              const SizedBox(height: 8),
              ...candidates.map(
                (item) => ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(item['name']?.toString() ?? 'Sản phẩm SQL'),
                  subtitle: Text(
                    '${item['type'] ?? 'Linh kiện'} • ${formatVnd(parseApiNumber(item['price'])?.round() ?? 0)}',
                  ),
                  trailing: const Icon(Icons.arrow_forward_ios, size: 16),
                  onTap: () => Navigator.pop(dialogContext, item),
                ),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(dialogContext),
          child: const Text('Bỏ qua'),
        ),
      ],
    ),
  );

  Future<void> _offerGeneratedBuild(
    Map<String, dynamic> scan,
    Map<String, dynamic> product,
  ) async {
    final type = product['type']?.toString() ?? '';
    final productId = product['id']?.toString() ?? '';
    if (type.isEmpty || productId.isEmpty) return;
    final areaId =
        ApiClient.instance.currentUser?['areaId']?.toString() ?? 'hcm';
    Map<String, dynamic> proposal;
    try {
      proposal = await ApiClient.instance.generateBuildSuggestion(
        budget: 40000000,
        purpose: 'Build PC có linh kiện ${product['name']}',
        areaId: areaId,
        pinnedComponents: {type: productId},
      );
    } catch (_) {
      if (mounted) {
        showDemoMessage(
          context,
          'Chưa tạo được cấu hình từ catalog SQL. Hãy kiểm tra kết nối rồi thử lại; chưa có build nào được lưu.',
        );
      }
      return;
    }
    if (!mounted) return;
    final components = proposal['components'] is Map
        ? Map<String, dynamic>.from(proposal['components'] as Map)
        : <String, dynamic>{type: productId};
    final save = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Tạo cấu hình từ sản phẩm quét?'),
        content: Text(
          'Đã nhận diện ${product['name']}. Tạo cấu hình nháp gồm ${components.length}/8 linh kiện và lưu vào tài khoản SQL?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Bỏ qua'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Lưu vào tài khoản'),
          ),
        ],
      ),
    );
    if (save != true || !mounted) return;
    final previousBuildId = ApiClient.instance.buildId;
    String? createdBuildId;
    try {
      final created = await ApiClient.instance.createBuild(
        name: proposal['name']?.toString() ?? 'Build nháp từ sản phẩm quét',
        budget: (parseApiNumber(proposal['budget']) ?? 40000000).round(),
        areaId: areaId,
      );
      final newBuildId = created['id']?.toString();
      if (newBuildId == null) {
        throw ApiException('SQL không trả mã cấu hình mới.');
      }
      createdBuildId = newBuildId;
      ApiClient.instance.buildId = newBuildId;
      for (final entry in components.entries) {
        final componentId = entry.value?.toString() ?? '';
        if (componentId.isNotEmpty) {
          await ApiClient.instance.updateComponent(entry.key, componentId);
        }
      }
      await ApiClient.instance.confirmScan(scan['id'].toString(), productId);
      if (mounted) {
        showDemoMessage(
          context,
          'Đã lưu build ${components.length}/8 linh kiện vào SQL.',
        );
      }
      await _loadHistory();
    } catch (error) {
      if (createdBuildId != null) {
        try {
          await ApiClient.instance.deleteBuild(createdBuildId);
        } catch (_) {}
      }
      if (mounted) {
        showDemoMessage(context, 'Không lưu được build vào SQL: $error');
      }
    } finally {
      ApiClient.instance.buildId = previousBuildId;
    }
  }

  Future<void> _showScanHistory() => showModalBottomSheet<void>(
    context: context,
    backgroundColor: panel,
    builder: (sheetContext) => SafeArea(
      child: ListView(
        shrinkWrap: true,
        padding: const EdgeInsets.all(18),
        children: [
          const Text(
            'Lịch sử quét đã lưu',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 12),
          if (loadingHistory)
            const Center(child: CircularProgressIndicator(color: mint))
          else if (scanHistory.isEmpty)
            const Text(
              'Chưa có lịch sử trong tài khoản SQL.',
              style: TextStyle(color: muted),
            )
          else
            ...scanHistory.map(
              (result) => CardBox(
                child: ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.qr_code_scanner, color: mint),
                  title: Text(
                    result['productName']?.toString() ?? 'Chưa nhận diện được',
                  ),
                  subtitle: Text(
                    '${result['productType'] ?? result['status']} • ${result['createdAt'] ?? ''}\n${result['analysis'] ?? ''}',
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                  ),
                  trailing: IconButton(
                    tooltip: 'Xóa lịch sử',
                    onPressed: () => _deleteScan(result),
                    icon: const Icon(
                      Icons.delete_outline,
                      color: Colors.redAccent,
                    ),
                  ),
                  onTap: () => _showScanDetails(result),
                ),
              ),
            ),
        ],
      ),
    ),
  );

  Future<void> _showScanDetails(Map<String, dynamic> scan) async {
    try {
      final details = await ApiClient.instance.scanDetails(
        scan['id'].toString(),
      );
      if (!mounted) return;
      final imageData = details['imageData']?.toString();
      await showDialog<void>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: Text(
            details['product']?['name']?.toString() ??
                scan['productName']?.toString() ??
                'Kết quả quét',
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (imageData != null && imageData.isNotEmpty)
                  ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: Image.memory(
                      base64Decode(imageData),
                      fit: BoxFit.contain,
                    ),
                  ),
                const SizedBox(height: 10),
                SelectableText(
                  details['analysis']?.toString() ??
                      'Không có phân tích lưu trong SQL.',
                ),
                const SizedBox(height: 8),
                Text(
                  'Thời gian: ${details['createdAt'] ?? ''}',
                  style: const TextStyle(color: muted, fontSize: 11),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Đóng'),
            ),
          ],
        ),
      );
    } catch (error) {
      if (mounted) {
        showDemoMessage(context, 'Không mở được chi tiết lịch sử: $error');
      }
    }
  }

  Future<void> _deleteScan(Map<String, dynamic> scan) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Xóa lịch sử quét?'),
        content: const Text(
          'Ảnh và kết quả lưu trong tài khoản SQL sẽ bị xóa.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Hủy'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Xóa'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await ApiClient.instance.deleteScan(scan['id'].toString());
      await _loadHistory();
    } catch (error) {
      if (mounted) showDemoMessage(context, 'Không xóa được lịch sử: $error');
    }
  }

  @override
  Widget build(BuildContext context) => Shell(
    title: 'Nhận diện linh kiện',
    subtitle: 'Đưa sản phẩm hoặc hộp vào khung',
    back: true,
    action: TextButton(
      onPressed: _showScanHistory,
      child: const Text('Lịch sử', style: TextStyle(color: mint)),
    ),
    child: SafeArea(
      child: ListView(
        padding: const EdgeInsets.fromLTRB(18, 8, 18, 20),
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(18),
            child: Stack(
              children: [
                selectedImage == null
                    ? Image.asset(
                        'assets/figma/scan.jpg',
                        height: 500,
                        width: double.infinity,
                        fit: BoxFit.cover,
                      )
                    : FutureBuilder(
                        future: selectedImage!.readAsBytes(),
                        builder: (context, snapshot) => snapshot.hasData
                            ? Image.memory(
                                snapshot.data!,
                                height: 500,
                                width: double.infinity,
                                fit: BoxFit.cover,
                              )
                            : const SizedBox(
                                height: 500,
                                child: Center(
                                  child: CircularProgressIndicator(),
                                ),
                              ),
                      ),
                Positioned.fill(
                  child: Container(
                    decoration: BoxDecoration(
                      border: Border.all(color: mint, width: 2),
                      borderRadius: BorderRadius.circular(18),
                    ),
                  ),
                ),
                Positioned(
                  top: 14,
                  left: 0,
                  right: 0,
                  child: Center(
                    child: Tag(
                      analyzing
                          ? 'AI ĐANG PHÂN TÍCH'
                          : analysis != null
                          ? 'ĐÃ PHÂN TÍCH'
                          : scanned
                          ? 'ẢNH ĐÃ CHỌN'
                          : 'SẴN SÀNG QUÉT',
                    ),
                  ),
                ),
                Positioned(
                  left: 14,
                  right: 14,
                  bottom: 15,
                  child: Text(
                    analysis != null || scanned
                        ? 'SẴN SÀNG PHÂN TÍCH ẢNH'
                        : 'SẴN SÀNG QUÉT\nĐưa linh kiện vào khung',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
          ),
          if (analysis != null) ...[
            const SizedBox(height: 12),
            CardBox(
              child: SelectableText(
                analysis!,
                style: const TextStyle(fontSize: 13, height: 1.45),
              ),
            ),
          ],
          const SizedBox(height: 18),
          Center(
            child: InkWell(
              borderRadius: BorderRadius.circular(40),
              onTap: analyzing
                  ? null
                  : () => _pickAndAnalyze(ImageSource.camera),
              child: CircleAvatar(
                radius: 34,
                backgroundColor: mint,
                child: analyzing
                    ? const SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(color: bg),
                      )
                    : const Icon(Icons.camera_alt, color: bg, size: 28),
              ),
            ),
          ),
          const SizedBox(height: 10),
          OutlinedButton.icon(
            onPressed: analyzing
                ? null
                : () => _pickAndAnalyze(ImageSource.gallery),
            icon: const Icon(Icons.photo_library_outlined),
            label: const Text('Chọn ảnh từ thư viện để phân tích'),
          ),
          const SizedBox(height: 10),
          const Center(
            child: Text(
              'Chụp hoặc chọn ảnh • LM Studio Vision sẽ phân tích',
              style: TextStyle(color: muted),
            ),
          ),
        ],
      ),
    ),
  );
}

class _LiveCompatibilitySummary extends StatelessWidget {
  const _LiveCompatibilitySummary({
    required this.report,
    required this.onDetails,
  });
  final Map<String, dynamic> report;
  final VoidCallback onDetails;

  @override
  Widget build(BuildContext context) {
    final status = report['status']?.toString() ?? 'partial';
    final issues = (report['issues'] as List? ?? const [])
        .whereType<Map>()
        .map((item) => Map<String, dynamic>.from(item))
        .toList();
    final recommendations = (report['recommendations'] as List? ?? const [])
        .whereType<Map>()
        .map((item) => Map<String, dynamic>.from(item))
        .toList();
    final color = status == 'incompatible' || status == 'error'
        ? Colors.redAccent
        : status == 'warning'
        ? Colors.amber
        : mint;
    return CardBox(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                status == 'compatible'
                    ? Icons.check_circle
                    : Icons.warning_amber,
                color: color,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  report['message']?.toString() ??
                      switch (status) {
                        'compatible' => 'Các thông số đã có đều tương thích.',
                        'incompatible' =>
                          'Phát hiện linh kiện không tương thích.',
                        'warning' => 'Cần xem cảnh báo của cấu hình.',
                        'error' => 'Kiểm tra chưa hoàn tất.',
                        _ =>
                          'Đã kiểm tra một phần; còn thiếu thông số catalog.',
                      },
                  style: TextStyle(color: color, fontWeight: FontWeight.bold),
                ),
              ),
            ],
          ),
          if (issues.isNotEmpty) ...[
            const SizedBox(height: 8),
            ...issues
                .take(2)
                .map(
                  (issue) => Padding(
                    padding: const EdgeInsets.only(bottom: 5),
                    child: Text(
                      '• ${issue['message']}',
                      style: const TextStyle(fontSize: 12),
                    ),
                  ),
                ),
          ],
          if (recommendations.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(
              'Đề xuất: ${recommendations.take(2).map((item) => '${item['name']} — ${item['recommendationReason'] ?? 'phù hợp hơn'}').join('; ')}',
              style: const TextStyle(color: mint, fontSize: 11),
            ),
          ],
          Align(
            alignment: Alignment.centerRight,
            child: TextButton.icon(
              onPressed: onDetails,
              icon: const Icon(Icons.article_outlined, size: 17),
              label: const Text('Xem báo cáo đầy đủ'),
            ),
          ),
        ],
      ),
    );
  }
}

class CompatibilityScreen extends StatelessWidget {
  const CompatibilityScreen({super.key, this.report});
  final Map<String, dynamic>? report;

  String _criterionTitle(String code) =>
      const {
        'SOCKET': 'Socket CPU / mainboard',
        'RAM': 'Chuẩn bộ nhớ RAM',
        'PSU': 'Công suất bộ nguồn',
        'CASE_SIZE': 'Chiều dài card đồ họa',
        'COOLER_SOCKET': 'Socket tản nhiệt',
        'CASE_FORM': 'Kích thước mainboard / case',
      }[code] ??
      code;

  String _issueTitle(String code) => _criterionTitle(code);

  Future<void> _replace(BuildContext context, Map<String, dynamic> item) async {
    try {
      await ApiClient.instance.updateComponent(
        item['type'].toString(),
        item['id'].toString(),
      );
      if (context.mounted) {
        showDemoMessage(context, 'Đã thay thế bằng ${item['name']}.');
        Navigator.pop(context, true);
      }
    } catch (error) {
      if (context.mounted) {
        showDemoMessage(context, 'Không thể thay thế: $error');
      }
    }
  }

  @override
  Widget build(BuildContext context) => Shell(
    title: 'Báo cáo tương thích',
    subtitle: 'Phân tích tự động • vừa xong',
    back: true,
    child: SafeArea(
      child: ListView(
        padding: const EdgeInsets.fromLTRB(18, 8, 18, 20),
        children: [
          ScoreCard(
            score: parseApiNumber(report?['score'])?.round(),
            verdict: report?['status']?.toString(),
            selectedCount: parseApiNumber(report?['selectedCount'])?.round(),
            checkedCount: report?['criteria'] is List
                ? (report!['criteria'] as List)
                      .where(
                        (item) => item is Map && item['status'] != 'unchecked',
                      )
                      .length
                : null,
          ),
          const SizedBox(height: 14),
          if (report?['powerAssessment'] is Map)
            PowerAssessmentCard(
              assessment: Map<String, dynamic>.from(
                report!['powerAssessment'] as Map,
              ),
            ),
          if (report?['powerAssessment'] is Map) const SizedBox(height: 12),
          if (report != null)
            InfoTile(
              icon: report!['status'] == 'incompatible'
                  ? Icons.error_outline
                  : report!['status'] == 'partial'
                  ? Icons.info_outline
                  : Icons.check_circle_outline,
              text: switch (report!['status']) {
                'incompatible' =>
                  'Không tương thích • ${report!['selectedCount'] ?? 0} linh kiện đã kiểm tra.',
                'warning' =>
                  'Có cảnh báo • ${report!['selectedCount'] ?? 0} linh kiện đã kiểm tra.',
                'partial' => 'Đã kiểm tra các cặp có đủ dữ liệu; tiêu chí còn lại thiếu thông số trong SQL.',
                _ => 'Tương thích trong phạm vi các thông số SQL hiện có.',
              },
            ),
          if (report != null) const SizedBox(height: 10),
          if (report == null)
            const WarningRow(
              icon: Icons.info_outline,
              color: Colors.amber,
              title: 'Chưa có báo cáo từ API',
              text: 'Đăng nhập và chọn linh kiện để kiểm tra cấu hình thật.',
            )
          else
            ...(report!['issues'] as List<dynamic>).map(
              (issue) => WarningRow(
                icon: issue['severity'] == 'error'
                    ? Icons.error_outline
                    : Icons.warning_amber,
                color: issue['severity'] == 'error'
                    ? Colors.redAccent
                    : Colors.amber,
                title: _issueTitle(issue['code'].toString()),
                text: issue['message'].toString(),
              ),
            ),
          if (report?['criteria'] is List)
            ...((report!['criteria'] as List).map(
              (criterion) => CompatibilityCriterionCard(
                title: _criterionTitle(criterion['code'].toString()),
                status: criterion['status']?.toString() ?? 'unchecked',
                detail: criterion['detail']?.toString() ?? '',
                remediation: criterion['remediation']?.toString() ?? '',
              ),
            )),
          const SizedBox(height: 14),
          const Text(
            'Đề xuất thay thế',
            style: TextStyle(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 10),
          if (report?['recommendations'] is List &&
              (report!['recommendations'] as List).isNotEmpty)
            ...(report!['recommendations'] as List).map((item) {
              final product = Map<String, dynamic>.from(item as Map);
              return CardBox(
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        '${product['name']}\n${product['price']}đ',
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                    ),
                    OutlinedButton(
                      onPressed: () => _replace(context, product),
                      child: const Text('Thay thế'),
                    ),
                  ],
                ),
              );
            })
          else
            const Text(
              'Chưa có linh kiện thay thế phù hợp từ catalog hiện tại.',
              style: TextStyle(color: muted),
            ),
        ],
      ),
    ),
  );
}

class ChatTab extends StatefulWidget {
  const ChatTab({
    super.key,
    this.initialPrompt,
    this.initialPinnedComponents = const {},
    this.responseTimeout = const Duration(minutes: 11),
    this.onOpenBuild,
  });
  final String? initialPrompt;
  final Map<String, String> initialPinnedComponents;
  final Duration responseTimeout;
  final VoidCallback? onOpenBuild;
  @override
  State<ChatTab> createState() => _ChatTabState();
}

class _ChatTabState extends State<ChatTab> {
  final question = TextEditingController();
  final messages = <Map<String, String>>[];
  String? conversationId;
  late Future<void> conversationReady;
  bool sending = false;
  String? sendError;

  @override
  void initState() {
    super.initState();
    if (widget.initialPrompt != null && widget.initialPrompt!.isNotEmpty) {
      messages.add({'role': 'assistant', 'text': widget.initialPrompt!});
    }
    conversationReady = _startConversation();
  }

  Future<void> _startConversation() async {
    if (ApiClient.instance.token == null) return;
    try {
      final conversation = await ApiClient.instance.createConversation(
        initialMessage: widget.initialPrompt,
      );
      if (mounted) {
        setState(() => conversationId = conversation['id'] as String?);
      }
    } catch (_) {
      // Sending still works through the stateless AI endpoint if SQL history
      // cannot be created for this conversation.
    }
  }

  Future<void> _clearConversation() async {
    await conversationReady;
    final currentConversationId = conversationId;
    if (currentConversationId != null) {
      try {
        await ApiClient.instance.deleteConversation(currentConversationId);
      } catch (error) {
        if (mounted) {
          setState(() => sendError = 'Không thể xóa cuộc trò chuyện: $error');
        }
        return;
      }
    }
    if (!mounted) return;
    setState(() {
      conversationId = null;
      messages.clear();
      sendError = null;
    });
    conversationReady = _startConversation();
    await conversationReady;
  }

  @override
  void dispose() {
    question.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Shell(
    title: 'BuildMate AI',
    subtitle: '● Trực tuyến • hiểu giá địa phương',
    action: TextButton(
      onPressed: sending ? null : _clearConversation,
      child: const Text('Xóa', style: TextStyle(color: mint)),
    ),
    child: SafeArea(
      child: Column(
        children: [
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(18, 8, 18, 8),
              children: [
                if (messages.isEmpty)
                  const ChatBubble(
                    text:
                        'Chào bạn! Hãy hỏi về linh kiện, giá hoặc tương thích.',
                    dark: true,
                  ),
                Wrap(
                  spacing: 6,
                  children: [
                    _SuggestionChip(
                      text: 'GPU dưới 10 triệu',
                      onTap: sending
                          ? null
                          : () => _useSuggestion('GPU dưới 10 triệu'),
                    ),
                    _SuggestionChip(
                      text: 'Build gaming 20 triệu',
                      onTap: sending
                          ? null
                          : () => _useSuggestion('Build gaming 20 triệu'),
                    ),
                    _SuggestionChip(
                      text: 'So sánh hàng cũ/mới',
                      onTap: sending
                          ? null
                          : () => _useSuggestion('So sánh hàng cũ/mới'),
                    ),
                  ],
                ),
                ...messages.map(
                  (message) => ChatBubble(
                    text: message['text']!,
                    dark: message['role'] == 'assistant',
                  ),
                ),
                if (sending)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 12),
                    child: Row(
                      children: [
                        SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                        SizedBox(width: 10),
                        Text('Đang chờ BuildMate trả lời…'),
                      ],
                    ),
                  ),
                if (sendError != null)
                  CardBox(
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            sendError!,
                            style: const TextStyle(color: Colors.amber),
                          ),
                        ),
                        TextButton.icon(
                          onPressed: sending ? null : _retryLastMessage,
                          icon: const Icon(Icons.refresh),
                          label: const Text('Thử lại'),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 6, 18, 10),
            child: TextField(
              controller: question,
              enabled: !sending,
              onSubmitted: (_) => _send(context),
              decoration: InputDecoration(
                hintText: 'Hỏi về linh kiện, giá, tương thích...',
                suffixIcon: IconButton(
                  onPressed: sending ? null : () => _send(context),
                  icon: Container(
                    padding: const EdgeInsets.all(7),
                    decoration: BoxDecoration(
                      color: mint,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(Icons.arrow_forward, color: bg),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    ),
  );

  Future<void> _send(BuildContext context) async {
    if (sending) return;
    final text = question.text.trim();
    if (text.isEmpty) {
      showDemoMessage(context, 'Hãy nhập câu hỏi trước khi gửi.');
      return;
    }
    question.clear();
    setState(() {
      messages.add({'role': 'user', 'text': text});
      sendError = null;
      sending = true;
    });
    await _processRequest(text);
  }

  Future<void> _retryLastMessage() async {
    if (sending || messages.isEmpty || messages.last['role'] != 'user') return;
    setState(() {
      sendError = null;
      sending = true;
    });
    await _processRequest(messages.last['text']!);
  }

  Future<void> _processRequest(String text) async {
    if (_isBuildRequest(text)) {
      try {
        await _createBuildFromChat(text);
      } catch (error) {
        if (mounted) {
          setState(() => sendError = 'Không tạo được build từ SQL: $error');
        }
      } finally {
        if (mounted) setState(() => sending = false);
      }
      return;
    }
    await _requestAnswer(text);
  }

  Future<void> _requestAnswer(String text) async {
    try {
      if (ApiClient.instance.token != null) {
        await conversationReady;
        if (conversationId == null) {
          conversationReady = _startConversation();
          await conversationReady;
        }
        if (conversationId == null) {
          throw ApiException(
            'Không tạo được hội thoại trong SQL. Kiểm tra kết nối rồi thử lại.',
          );
        }
      }
      final String answer;
      if (conversationId != null) {
        final response = await ApiClient.instance.sendMessage(
          conversationId!,
          text,
        );
        final choices = response['choices'];
        final firstChoice = choices is List && choices.isNotEmpty
            ? choices.first
            : null;
        final message = firstChoice is Map ? firstChoice['message'] : null;
        final content = message is Map ? message['content'] : null;
        if (content is! String || content.trim().isEmpty) {
          throw ApiException('BuildMate không trả về nội dung hợp lệ.');
        }
        answer = content;
      } else {
        answer = await ApiClient.instance.sendLmStudioMessage(
          text,
          history: messages
              .take(messages.length - 1)
              .map(
                (message) => {
                  'role': message['role']!,
                  'content': message['text']!,
                },
              )
              .toList(),
          timeout: widget.responseTimeout,
        );
      }
      if (mounted) {
        setState(() => messages.add({'role': 'assistant', 'text': answer}));
      }
      if (_isBuildRequest(text) && mounted) {
        try {
          await _createBuildFromChat(text);
        } catch (error) {
          if (mounted) {
            showDemoMessage(context, 'Chưa tạo được cấu hình: $error');
          }
        }
      }
    } catch (error) {
      if (mounted) {
        setState(() => sendError = 'Không nhận được phản hồi: $error');
      }
    } finally {
      if (mounted) setState(() => sending = false);
    }
  }

  bool _isBuildRequest(String text) {
    final normalized = text.toLowerCase();
    final explicitBuildPhrases = <String>[
      'build pc gaming',
      'build gaming',
      'build game',
      'build theo',
      'build với',
      'build voi',
      'build từ',
      'build tu',
      'build dựa',
      'build dua',
      'build cho',
      'build giúp',
      'build giup',
      'build cấu hình',
      'build cau hinh',
      'build một bộ',
      'build mot bo',
      'build bộ pc',
      'build bo pc',
      'build dàn pc',
      'build dan pc',
      'build máy',
      'build may',
      'tạo build',
      'tao build',
      'lên cấu hình',
      'len cau hinh',
      'tạo cấu hình',
      'tao cau hinh',
      'dựng pc',
      'dung pc',
      'dựng cấu hình',
      'dung cau hinh',
      'lắp pc',
      'lap pc',
      'lắp ráp pc',
      'lap rap pc',
      'làm cấu hình',
      'lam cau hinh',
      'tạo bộ pc',
      'tao bo pc',
      'tạo dàn pc',
      'tao dan pc',
      'cho tôi build',
      'cho toi build',
      'giúp tôi build',
      'giup toi build',
      'muốn build',
      'muon build',
      'cần build',
      'can build',
    ];
    if (explicitBuildPhrases.any(normalized.contains)) return true;
    final compactBuildCommand = RegExp(
      r'^\s*(?:(?:hãy|hay)\s+)?build\s+(?:(?:pc|máy tính|may tinh)\s+)?(?:rtx\s*)?\d{3,4}\b',
    );
    return compactBuildCommand.hasMatch(normalized) ||
        RegExp(r'^\s*build\s+(?:nó|no|card này|card nay|cấu hình|cau hinh)\b')
            .hasMatch(normalized);
  }

  Future<void> _createBuildFromChat(String prompt) async {
    if (!mounted) return;
    final areaId =
        ApiClient.instance.currentUser?['areaId']?.toString() ?? 'hcm';
    final contextText = messages
        .map((message) => message['text'] ?? '')
        .join('\n');
    final pinnedComponents = await _findPinnedComponents(
      '$contextText\n$prompt',
      areaId,
      prompt: prompt,
      preferred: widget.initialPinnedComponents,
    );
    final userRequestText = messages
        .where((message) => message['role'] == 'user')
        .map((message) => message['text'] ?? '')
        .join('\n');
    final budget = _requestedBudget(userRequestText);
    var proposalBudget = budget;
    Map<String, dynamic> proposal;
    try {
      proposal = await ApiClient.instance.generateBuildSuggestion(
        budget: proposalBudget,
        purpose: prompt,
        areaId: areaId,
        pinnedComponents: pinnedComponents,
      );
    } on ApiException catch (error) {
      final budgetRejected =
          error.statusCode == 422 &&
          (error.message.toLowerCase().contains('ngân sách') ||
              error.message.toLowerCase().contains('cấu hình tương thích'));
      if (!budgetRejected) rethrow;
      proposalBudget = (((budget * 1.25) / 1000000).ceil() * 1000000).toInt();
      if (proposalBudget <= budget) proposalBudget = budget + 5000000;
      proposal = await ApiClient.instance.generateBuildSuggestion(
        budget: proposalBudget,
        purpose: prompt,
        areaId: areaId,
        pinnedComponents: pinnedComponents,
      );
    }
    if (!mounted) return;
    final components = proposal['components'] is Map
        ? Map<String, dynamic>.from(proposal['components'] as Map)
        : <String, dynamic>{};
    final componentDetails = proposal['componentDetails'] is Map
        ? Map<String, dynamic>.from(proposal['componentDetails'] as Map)
        : <String, dynamic>{};
    if (components.isEmpty) {
      showDemoMessage(
        context,
        'AI chưa đề xuất được linh kiện cho cấu hình này.',
      );
      return;
    }
    final action = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Cấu hình AI đề xuất'),
        content: SizedBox(
          width: double.maxFinite,
          height: 410,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${proposal['name'] ?? 'BuildMate'} • ${components.length}/8 linh kiện',
                ),
                if (proposalBudget > budget) ...[
                  const SizedBox(height: 4),
                  Text(
                    'Ngân sách ${formatVnd(budget)} chưa đủ cho linh kiện đã chọn; đây là phương án gần nhất trong mức ${formatVnd(proposalBudget)}.',
                    style: const TextStyle(color: Colors.amber),
                  ),
                ],
                if (parseApiNumber(proposal['totalPrice']) != null) ...[
                  const SizedBox(height: 4),
                  Text(
                    '${proposal['priceEstimate'] == true ? 'Tạm tính' : 'Tổng giá SQL'}: ${formatVnd(parseApiNumber(proposal['totalPrice'])!.round())}',
                    style: const TextStyle(
                      color: mint,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
                const SizedBox(height: 10),
                ...components.entries.map(
                  (entry) => Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Text(
                      _proposalComponentLine(
                        entry.key.toString(),
                        entry.value,
                        componentDetails,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                const Text(
                  'Lưu vào tài khoản SQL để mở và chỉnh sửa trong tab Build?',
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, 'skip'),
            child: const Text('Để sau'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, 'save'),
            child: const Text('Lưu build'),
          ),
        ],
      ),
    );
    if (action != 'save' || !mounted) return;
    final previousBuildId = ApiClient.instance.buildId;
    String? createdBuildId;
    try {
      final created = await ApiClient.instance.createBuild(
        name: proposal['name']?.toString() ?? 'BuildMate AI',
        budget: (parseApiNumber(proposal['budget']) ?? budget).round(),
        areaId: areaId,
      );
      createdBuildId = created['id']?.toString();
      if (createdBuildId == null) {
        throw ApiException('SQL không trả mã build mới.');
      }
      ApiClient.instance.buildId = createdBuildId;
      for (final entry in components.entries) {
        final id = _proposalComponentId(entry.value);
        if (id.isNotEmpty) {
          await ApiClient.instance.updateComponent(entry.key, id);
        }
      }
      ApiClient.instance.buildId = previousBuildId;
      if (!mounted) return;
      showDemoMessage(context, 'Đã lưu cấu hình vào SQL. Đang mở tab Build.');
      widget.onOpenBuild?.call();
    } catch (error) {
      if (createdBuildId != null) {
        try {
          await ApiClient.instance.deleteBuild(createdBuildId);
        } catch (_) {}
      }
      if (mounted) showDemoMessage(context, 'Không lưu được cấu hình: $error');
    } finally {
      ApiClient.instance.buildId = previousBuildId;
    }
  }

  String _proposalComponentId(dynamic value) => value is Map
      ? (value['id'] ?? value['productId'] ?? '').toString()
      : value?.toString() ?? '';

  String _proposalComponentName(dynamic value) => value is Map
      ? (value['name'] ?? value['productName'] ?? value['id'] ?? 'Chưa có tên')
            .toString()
      : value?.toString() ?? 'Chưa có dữ liệu';

  String _proposalComponentLine(
    String type,
    dynamic value,
    Map<String, dynamic> componentDetails,
  ) {
    final detail = componentDetails[type];
    final name = _proposalComponentName(detail ?? value);
    final price = detail is Map ? parseApiNumber(detail['price']) : null;
    return price == null
        ? '$type: $name'
        : '$type: $name • ${formatVnd(price.round())}';
  }

  int _requestedBudget(String text) {
    final matches = RegExp(
      r'(\d+(?:[.,]\d+)?)\s*(?:triệu|trieu|tr|m)\b',
      caseSensitive: false,
    ).allMatches(text).toList();
    if (matches.isEmpty) return 40000000;
    final match = matches.last;
    final amount = double.tryParse(match.group(1)!.replaceAll(',', '.'));
    if (amount == null || amount <= 0) return 40000000;
    return (amount * 1000000).round().clamp(5000000, 2000000000).toInt();
  }

  Future<Map<String, String>> _findPinnedComponents(
    String contextText,
    String areaId, {
    String prompt = '',
    Map<String, String> preferred = const {},
  }) async {
    final validPreferred = Map<String, String>.from(preferred)
      ..removeWhere((type, id) => type.isEmpty || id.isEmpty);
    final userText = messages
        .where((message) => message['role'] == 'user')
        .map((message) => message['text'] ?? '')
        .join('\n')
        .toLowerCase();
    final latestRequest = prompt.trim().isNotEmpty ? prompt : userText;
    final explicitGpuPattern = RegExp(
      r'\b(?:nvidia\s*)?(?:geforce\s*)?rtx\s*(\d{4})(?:\s*(ti|super))?\b',
      caseSensitive: false,
    );
    final modelPattern = RegExp(
      r'\b(\d{4})(?:\s*(ti|super))?\b',
      caseSensitive: false,
    );
    final explicitPromptModel =
        explicitGpuPattern.firstMatch(prompt) ??
        (() {
          final promptSeriesMatches = modelPattern.allMatches(prompt).toList();
          return promptSeriesMatches.length == 1
              ? promptSeriesMatches.single
              : null;
        })();
    if (explicitPromptModel == null && validPreferred.isNotEmpty) {
      return validPreferred;
    }
    if (validPreferred.isNotEmpty && explicitPromptModel != null) {
      final preferredModel = explicitGpuPattern.firstMatch(contextText);
      if (preferredModel != null &&
          preferredModel.group(1) == explicitPromptModel.group(1) &&
          (preferredModel.group(2) ?? '').toLowerCase() ==
              (explicitPromptModel.group(2) ?? '').toLowerCase()) {
        return validPreferred;
      }
    }
    Match? modelMatch =
        explicitPromptModel ?? explicitGpuPattern.firstMatch(latestRequest);
    if (modelMatch == null) {
      final bareMatches = modelPattern.allMatches(latestRequest).toList();
      if (bareMatches.length == 1) modelMatch = bareMatches.single;
    }
    if (modelMatch == null && latestRequest != contextText) {
      final priorExplicitMatches = explicitGpuPattern
          .allMatches(contextText)
          .toList();
      if (priorExplicitMatches.isNotEmpty) {
        modelMatch = priorExplicitMatches.last;
      }
      if (modelMatch == null) {
        final priorBareMatches = modelPattern.allMatches(contextText).toList();
        if (priorBareMatches.length == 1) modelMatch = priorBareMatches.single;
      }
    }
    if (modelMatch == null) return const {};
    final series = modelMatch.group(1)!;
    final suffix = (modelMatch.group(2) ?? '').toLowerCase();
    final products = await ApiClient.instance.products(
      'GPU',
      query: series,
      areaId: areaId,
    );
    if (products.isEmpty) return const {};
    final requestText = latestRequest.toLowerCase();
    final asksTi = suffix == 'ti';
    final asksSuper = suffix == 'super';
    final requestedBrand = RegExp(
      r'\b(msi|asus|gigabyte|zotac|palit|galax|gainward|inno3d|pny|evga)\b',
      caseSensitive: false,
    ).firstMatch(requestText)?.group(1)?.toLowerCase();
    final candidates = products.where((item) {
      final name = item['name']?.toString().toLowerCase() ?? '';
      final isRtx = name.contains('rtx') || name.contains('geforce');
      final isTi = RegExp(r'\bti\b').hasMatch(name);
      final isSuper = name.contains('super');
      return isRtx &&
          name.contains(series) &&
          isTi == asksTi &&
          isSuper == asksSuper;
    }).toList();
    if (candidates.isEmpty) return const {};
    candidates.sort((a, b) {
      final an = a['name']?.toString().toLowerCase() ?? '';
      final bn = b['name']?.toString().toLowerCase() ?? '';
      final aBrand = requestedBrand == null
          ? 0
          : (an.contains(requestedBrand) ? 0 : 1);
      final bBrand = requestedBrand == null
          ? 0
          : (bn.contains(requestedBrand) ? 0 : 1);
      if (aBrand != bBrand) return aBrand.compareTo(bBrand);
      final aPrice = parseApiNumber(a['price']) ?? double.maxFinite;
      final bPrice = parseApiNumber(b['price']) ?? double.maxFinite;
      return aPrice.compareTo(bPrice);
    });
    final productId = candidates.first['id']?.toString();
    return productId == null ? const {} : {'GPU': productId};
  }

  void _useSuggestion(String value) {
    question
      ..text = value
      ..selection = TextSelection.collapsed(offset: value.length);
  }
}

class _SuggestionChip extends StatelessWidget {
  const _SuggestionChip({required this.text, required this.onTap});
  final String text;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => ActionChip(
    label: Text(text),
    onPressed: onTap,
    labelStyle: const TextStyle(color: mint, fontSize: 11),
    backgroundColor: greenPanel,
    side: BorderSide.none,
  );
}

class SavedTab extends StatefulWidget {
  const SavedTab({super.key});
  @override
  State<SavedTab> createState() => _SavedTabState();
}

class _SavedTabState extends State<SavedTab> {
  late Future<List<Map<String, dynamic>>> buildsFuture;

  @override
  void initState() {
    super.initState();
    buildsFuture = _loadBuilds();
  }

  Future<List<Map<String, dynamic>>> _loadBuilds() async {
    if (ApiClient.instance.token == null) {
      throw ApiException(
        'Phiên đăng nhập đã hết. Hãy đăng nhập lại để xem cấu hình đã lưu.',
      );
    }
    return ApiClient.instance.builds();
  }

  Future<void> _deleteBuild(Map<String, dynamic> build) async {
    final id = build['id']?.toString();
    if (id == null) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Xóa cấu hình?'),
        content: Text(
          'Bạn có muốn xóa "${build['name'] ?? 'cấu hình'}" không?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Hủy'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Xóa'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await ApiClient.instance.deleteBuild(id);
      if (mounted) {
        setState(() {
          buildsFuture = _loadBuilds();
        });
        showDemoMessage(context, 'Đã xóa cấu hình khỏi tài khoản.');
      }
    } on ApiException catch (error) {
      if (error.statusCode == 404 && mounted) {
        setState(() {
          buildsFuture = _loadBuilds();
        });
        showDemoMessage(context, 'Cấu hình này đã được xóa trước đó.');
      } else if (mounted) {
        showDemoMessage(context, 'Không thể xóa cấu hình: $error');
      }
    } catch (error) {
      if (mounted) showDemoMessage(context, 'Không thể xóa cấu hình: $error');
    }
  }

  @override
  Widget build(BuildContext context) => Shell(
    title: 'Cấu hình đã lưu',
    subtitle: 'Cấu hình được đồng bộ với tài khoản',
    action: TextButton.icon(
      onPressed: () =>
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => const BuildTab(loadLatest: false),
            ),
          ).then((_) {
            if (mounted) {
              setState(() {
                buildsFuture = _loadBuilds();
              });
            }
          }),
      icon: const Icon(Icons.add, color: mint, size: 18),
      label: const Text('Tạo mới', style: TextStyle(color: mint)),
    ),
    child: SafeArea(
      child: FutureBuilder<List<Map<String, dynamic>>>(
        future: buildsFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator(color: mint));
          }
          if (snapshot.hasError) {
            return Center(
              child: Text('Không tải được cấu hình: ${snapshot.error}'),
            );
          }
          final builds = snapshot.data ?? const <Map<String, dynamic>>[];
          if (builds.isEmpty) {
            return const Center(
              child: Text('Bạn chưa có cấu hình nào được lưu.'),
            );
          }
          return ListView(
            padding: const EdgeInsets.fromLTRB(18, 8, 18, 20),
            children: [
              InfoTile(
                icon: Icons.cloud_done_outlined,
                text:
                    'Đã lưu vào tài khoản ${ApiClient.instance.currentUser?['email'] ?? ''}',
              ),
              const SizedBox(height: 14),
              Tag('Tất cả ${builds.length}'),
              const SizedBox(height: 14),
              ...builds.map(
                (build) => SavedCard(
                  name: build['name']?.toString() ?? 'Cấu hình mới',
                  price: build['priceComplete'] == false
                      ? 'Chưa đủ giá SQL'
                      : '${build['priceEstimate'] == true ? '≈ ' : ''}${(parseApiNumber(build['totalPrice']) ?? 0).toStringAsFixed(0)}đ${build['priceEstimate'] == true ? ' • ước tính' : ''}',
                  status: build['priceComplete'] == false
                      ? 'THIẾU GIÁ'
                      : (parseApiNumber(build['completion']) ?? 0) == 100
                      ? 'TƯƠNG THÍCH'
                      : 'ĐANG LÀM',
                  area: build['areaId']?.toString() ?? 'TP. HỒ CHÍ MINH',
                  components: build['components'] is Map
                      ? Map<String, dynamic>.from(build['components'] as Map)
                      : const {},
                  onEdit: () =>
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => BuildTab(initialBuild: build),
                        ),
                      ).then((_) {
                        if (mounted) {
                          setState(() {
                            buildsFuture = _loadBuilds();
                          });
                        }
                      }),
                  onDelete: () => _deleteBuild(build),
                ),
              ),
            ],
          );
        },
      ),
    ),
  );
}

class AccountTab extends StatefulWidget {
  const AccountTab({super.key, this.onAreaChanged});
  final void Function(String id, String name)? onAreaChanged;
  @override
  State<AccountTab> createState() => _AccountTabState();
}

class _AccountTabState extends State<AccountTab> {
  bool pricePreference = true;
  bool priceNotifications = true;
  Map<String, dynamic>? get user => ApiClient.instance.currentUser;

  @override
  void initState() {
    super.initState();
    final preferences = user?['preferences'];
    if (preferences is Map) {
      pricePreference = preferences['pricePreference'] as bool? ?? true;
      priceNotifications = preferences['priceNotifications'] as bool? ?? true;
    }
  }

  Future<void> _updatePreference({
    bool? pricePreference,
    bool? priceNotifications,
  }) async {
    try {
      await ApiClient.instance.updateProfile(
        pricePreference: pricePreference,
        priceNotifications: priceNotifications,
      );
      if (!mounted) return;
      setState(() {
        if (pricePreference != null) this.pricePreference = pricePreference;
        if (priceNotifications != null) {
          this.priceNotifications = priceNotifications;
        }
      });
    } catch (error) {
      if (mounted) showMessage(context, 'Không thể lưu tùy chọn: $error');
    }
  }

  Future<void> _editProfile() async {
    final name = TextEditingController(text: user?['name']?.toString() ?? '');
    final result = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Chỉnh sửa tài khoản'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: name,
              decoration: const InputDecoration(labelText: 'Tên người dùng'),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Hủy'),
          ),
          FilledButton(
            onPressed: () async {
              try {
                await ApiClient.instance.updateProfile(name: name.text.trim());
                if (dialogContext.mounted) Navigator.pop(dialogContext, true);
              } catch (error) {
                if (dialogContext.mounted) {
                  showDemoMessage(dialogContext, '$error');
                }
              }
            },
            child: const Text('Lưu'),
          ),
        ],
      ),
    );
    name.dispose();
    if (result == true && mounted) setState(() {});
  }

  Future<void> _changeArea() async {
    final areas = await ApiClient.instance.areas();
    if (!mounted) return;
    final area = await showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      builder: (sheetContext) => ListView(
        shrinkWrap: true,
        children: areas
            .map(
              (item) => ListTile(
                title: Text(item['name'].toString()),
                onTap: () => Navigator.pop(sheetContext, item),
              ),
            )
            .toList(),
      ),
    );
    if (area == null) return;
    await ApiClient.instance.updateProfile(areaId: area['id'].toString());
    widget.onAreaChanged?.call(
      area['id'].toString(),
      area['name']?.toString() ?? area['id'].toString(),
    );
    if (mounted) setState(() {});
  }

  Future<void> _openPrivacy() async {
    final areaId = user?['areaId']?.toString() ?? 'hcm';
    String areaName = areaId;
    try {
      final areas = await ApiClient.instance.areas();
      areaName = areas
          .firstWhere(
            (item) => item['id']?.toString() == areaId,
            orElse: () => {'name': areaId},
          )['name']
          .toString();
    } catch (_) {}
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Quyền riêng tư & vị trí'),
        content: Text(
          'Vị trí định giá hiện tại: $areaName\n\n'
          '• Vị trí: chỉ dùng khi bạn yêu cầu xác định khu vực giá.\n'
          '• Camera: chỉ dùng khi bạn mở chức năng quét sản phẩm.\n'
          '• Ảnh/thư viện: chỉ đọc ảnh bạn chọn để phân tích.\n'
          '• Dữ liệu cấu hình: lưu theo tài khoản và không chia sẻ công khai.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Đóng'),
          ),
          FilledButton(
            onPressed: () {
              Navigator.pop(dialogContext);
              _changeArea();
            },
            child: const Text('Đổi khu vực'),
          ),
        ],
      ),
    );
  }

  Future<void> _openSupport() async {
    final message = TextEditingController();
    final result = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Trợ giúp & hỗ trợ'),
        content: TextField(
          controller: message,
          minLines: 4,
          maxLines: 7,
          decoration: const InputDecoration(
            hintText: 'Mô tả vấn đề (10–2.000 ký tự)',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Hủy'),
          ),
          FilledButton(
            onPressed: () async {
              try {
                final request = await ApiClient.instance.submitSupportRequest(
                  message: message.text.trim(),
                );
                if (dialogContext.mounted) {
                  Navigator.pop(dialogContext, true);
                  showMessage(
                    context,
                    'Đã tiếp nhận yêu cầu ${request['id']}.',
                  );
                }
              } catch (error) {
                if (dialogContext.mounted) showMessage(dialogContext, '$error');
              }
            },
            child: const Text('Gửi'),
          ),
        ],
      ),
    );
    message.dispose();
    if (result == true && mounted) setState(() {});
  }

  String _areaName(String? id) =>
      const {
        'hcm': 'TP. Hồ Chí Minh',
        'hanoi': 'Hà Nội',
        'danang': 'Đà Nẵng',
      }[id] ??
      id ??
      'TP. Hồ Chí Minh';

  @override
  Widget build(BuildContext context) => Shell(
    title: 'Tài khoản',
    subtitle: 'Quản lý hồ sơ và trải nghiệm mua sắm',
    child: SafeArea(
      child: ListView(
        padding: const EdgeInsets.fromLTRB(18, 8, 18, 20),
        children: [
          CardBox(
            child: Row(
              children: [
                CircleAvatar(
                  radius: 23,
                  backgroundColor: greenPanel,
                  backgroundImage:
                      user?['avatarUrl']?.toString().isNotEmpty == true
                      ? NetworkImage(user!['avatarUrl'].toString())
                      : null,
                  child: user?['avatarUrl']?.toString().isNotEmpty == true
                      ? null
                      : Text(
                          (user?['name']?.toString() ?? 'U')
                              .trim()
                              .split(RegExp(r'\s+'))
                              .last
                              .substring(0, 1)
                              .toUpperCase(),
                          style: const TextStyle(
                            color: mint,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        user?['name']?.toString() ?? 'Người dùng',
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                      Text(
                        user?['email']?.toString() ?? '',
                        style: const TextStyle(color: muted, fontSize: 11),
                      ),
                    ],
                  ),
                ),
                TextButton(
                  onPressed: _editProfile,
                  child: const Text('Chỉnh sửa'),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: _changeArea,
            child: InfoTile(
              icon: Icons.location_on_outlined,
              text:
                  'ĐỊNH GIÁ HIỆN TẠI · KHU VỰC\n${_areaName(user?['areaId']?.toString())}',
              trailing: 'Thay đổi',
            ),
          ),
          const SizedBox(height: 12),
          CardBox(
            child: Column(
              children: [
                SettingRow(
                  icon: Icons.local_offer_outlined,
                  title: 'Ưu tiên giá linh kiện',
                  detail: 'Hiển thị hàng mới trước',
                  end: pricePreference ? 'Hàng mới' : 'Giá tốt',
                  toggle: true,
                  value: pricePreference,
                  onToggle: (value) =>
                      _updatePreference(pricePreference: value),
                ),
                SettingRow(
                  icon: Icons.notifications_none,
                  title: 'Thông báo biến động giá',
                  detail: 'Báo khi giá thay đổi từ 3%',
                  toggle: true,
                  value: priceNotifications,
                  onToggle: (value) =>
                      _updatePreference(priceNotifications: value),
                ),
                SettingRow(
                  icon: Icons.price_change_outlined,
                  title: 'Cảnh báo giá đã đặt',
                  detail: 'Thêm, sửa hoặc xóa cảnh báo trên SQL',
                  end: '›',
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => const PriceAlertsScreen(),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          CardBox(
            child: Column(
              children: [
                SettingRow(
                  icon: Icons.cancel_outlined,
                  title: 'Bảo mật & đổi mật khẩu',
                  end: '›',
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => const ChangePasswordScreen(),
                    ),
                  ),
                ),
                SettingRow(
                  icon: Icons.lock_outline,
                  title: 'Quyền riêng tư & vị trí',
                  detail: 'Vị trí: Khi dùng ứng dụng',
                  end: '›',
                  onTap: _openPrivacy,
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          CardBox(
            child: Column(
              children: [
                SettingRow(
                  icon: Icons.help_outline,
                  title: 'Trợ giúp & liên hệ',
                  end: '›',
                  onTap: _openSupport,
                ),
                SettingRow(
                  icon: Icons.help_outline,
                  title: 'PCBuild Local',
                  detail: 'Ứng dụng xây dựng cấu hình PC',
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          SecondaryButton(
            text: 'Đăng xuất',
            onPressed: () {
              ApiClient.instance.logout();
              Navigator.pushReplacement(
                context,
                MaterialPageRoute(builder: (_) => const LoginScreen()),
              );
            },
          ),
        ],
      ),
    ),
  );
}

class PriceAlertsScreen extends StatefulWidget {
  const PriceAlertsScreen({super.key});

  @override
  State<PriceAlertsScreen> createState() => _PriceAlertsScreenState();
}

class _PriceAlertsScreenState extends State<PriceAlertsScreen> {
  late Future<List<Map<String, dynamic>>> alerts;

  @override
  void initState() {
    super.initState();
    alerts = ApiClient.instance.priceAlerts();
  }

  void _reload() => setState(() => alerts = ApiClient.instance.priceAlerts());

  Future<void> _edit(Map<String, dynamic> alert) async {
    final controller = TextEditingController(
      text: alert['targetPrice'].toString(),
    );
    final target = await showDialog<int>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Sửa mức cảnh báo'),
        content: TextField(
          controller: controller,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(labelText: 'Giá mục tiêu (VNĐ)'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Hủy'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(
              dialogContext,
              int.tryParse(controller.text.replaceAll(RegExp(r'[^0-9]'), '')),
            ),
            child: const Text('Cập nhật'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (target == null || target <= 0) return;
    try {
      await ApiClient.instance.updatePriceAlert(
        id: alert['id'].toString(),
        productId: alert['productId'].toString(),
        targetPrice: target,
        areaId: alert['areaId'].toString(),
      );
      if (mounted) _reload();
    } catch (error) {
      if (mounted) showDemoMessage(context, 'Không sửa được cảnh báo: $error');
    }
  }

  Future<void> _delete(Map<String, dynamic> alert) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Xóa cảnh báo giá?'),
        content: Text(
          'Xóa cảnh báo cho ${alert['productName'] ?? 'linh kiện này'}?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Hủy'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Xóa'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await ApiClient.instance.deletePriceAlert(alert['id'].toString());
      if (mounted) _reload();
    } catch (error) {
      if (mounted) showDemoMessage(context, 'Không xóa được cảnh báo: $error');
    }
  }

  @override
  Widget build(BuildContext context) => Shell(
    title: 'Cảnh báo giá',
    subtitle: 'Các mức giá được lưu trong SQL',
    back: true,
    child: FutureBuilder<List<Map<String, dynamic>>>(
      future: alerts,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Center(child: CircularProgressIndicator(color: mint));
        }
        if (snapshot.hasError) {
          return Center(
            child: Text('Không tải được cảnh báo: ${snapshot.error}'),
          );
        }
        final items = snapshot.data ?? const [];
        if (items.isEmpty) {
          return const Center(child: Text('Chưa có cảnh báo giá nào.'));
        }
        return ListView(
          padding: const EdgeInsets.all(16),
          children: items
              .map(
                (item) => CardBox(
                  child: ListTile(
                    title: Text(
                      item['productName']?.toString() ??
                          item['productId'].toString(),
                    ),
                    subtitle: Text(
                      'Báo khi ≤ ${formatVnd(item['targetPrice'])} • ${item['areaId']} • hiện tại ${formatVnd(item['currentPrice'])}',
                    ),
                    trailing: PopupMenuButton<String>(
                      onSelected: (action) =>
                          action == 'edit' ? _edit(item) : _delete(item),
                      itemBuilder: (_) => const [
                        PopupMenuItem(value: 'edit', child: Text('Sửa')),
                        PopupMenuItem(value: 'delete', child: Text('Xóa')),
                      ],
                    ),
                  ),
                ),
              )
              .toList(),
        );
      },
    ),
  );
}

class ChangePasswordScreen extends StatefulWidget {
  const ChangePasswordScreen({super.key});
  @override
  State<ChangePasswordScreen> createState() => _ChangePasswordScreenState();
}

class _ChangePasswordScreenState extends State<ChangePasswordScreen> {
  final current = TextEditingController();
  final next = TextEditingController();
  final confirmation = TextEditingController();
  bool busy = false;

  @override
  void dispose() {
    current.dispose();
    next.dispose();
    confirmation.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (next.text.length < 8 || next.text != confirmation.text) {
      showMessage(
        context,
        'Mật khẩu mới phải có ít nhất 8 ký tự và khớp xác nhận.',
      );
      return;
    }
    setState(() => busy = true);
    try {
      await ApiClient.instance.changePassword(current.text, next.text);
      if (!mounted) return;
      showMessage(context, 'Đã đổi mật khẩu thành công.');
      Navigator.pop(context);
    } catch (error) {
      if (mounted) showMessage(context, 'Không thể đổi mật khẩu: $error');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Shell(
    title: 'Đổi mật khẩu',
    subtitle: 'Bảo vệ tài khoản của bạn',
    back: true,
    child: ListView(
      padding: const EdgeInsets.fromLTRB(18, 12, 18, 20),
      children: [
        TextField(
          controller: current,
          obscureText: true,
          decoration: const InputDecoration(labelText: 'Mật khẩu hiện tại'),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: next,
          obscureText: true,
          decoration: const InputDecoration(labelText: 'Mật khẩu mới'),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: confirmation,
          obscureText: true,
          decoration: const InputDecoration(labelText: 'Nhập lại mật khẩu mới'),
        ),
        const SizedBox(height: 20),
        PrimaryButton(
          text: busy ? 'ĐANG CẬP NHẬT...' : 'ĐỔI MẬT KHẨU',
          onPressed: busy ? () {} : _submit,
        ),
      ],
    ),
  );
}

class CardBox extends StatelessWidget {
  const CardBox({super.key, required this.child});
  final Widget child;
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
      color: panel,
      border: Border.all(color: stroke),
      borderRadius: BorderRadius.circular(14),
    ),
    child: child,
  );
}

class Brand extends StatelessWidget {
  const Brand({super.key});
  @override
  Widget build(BuildContext context) => Row(
    children: [
      const Logo(),
      const SizedBox(width: 9),
      const Text(
        'PCBUILD LOCAL',
        style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
      ),
    ],
  );
}

class Logo extends StatelessWidget {
  const Logo({super.key});
  @override
  Widget build(BuildContext context) => Container(
    width: 36,
    height: 36,
    decoration: BoxDecoration(
      color: mint,
      borderRadius: BorderRadius.circular(10),
    ),
    child: const Icon(Icons.memory, color: bg, size: 20),
  );
}

class Tag extends StatelessWidget {
  const Tag(this.text, {super.key});
  final String text;
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
    decoration: BoxDecoration(
      color: greenPanel,
      borderRadius: BorderRadius.circular(20),
    ),
    child: Text(
      text,
      style: const TextStyle(
        color: mint,
        fontWeight: FontWeight.bold,
        fontSize: 10,
      ),
    ),
  );
}

class FieldLabel extends StatelessWidget {
  const FieldLabel(this.text, {super.key});
  final String text;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 7),
    child: Text(
      text,
      style: const TextStyle(
        color: muted,
        fontSize: 11,
        fontWeight: FontWeight.bold,
      ),
    ),
  );
}

class PrimaryButton extends StatelessWidget {
  const PrimaryButton({super.key, required this.text, required this.onPressed});
  final String text;
  final VoidCallback onPressed;
  @override
  Widget build(BuildContext context) => SizedBox(
    height: 50,
    width: double.infinity,
    child: ElevatedButton(
      onPressed: onPressed,
      style: ElevatedButton.styleFrom(
        backgroundColor: mint,
        foregroundColor: bg,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
      child: Text(text, style: const TextStyle(fontWeight: FontWeight.bold)),
    ),
  );
}

class SecondaryButton extends StatelessWidget {
  const SecondaryButton({
    super.key,
    required this.text,
    required this.onPressed,
  });
  final String text;
  final VoidCallback onPressed;
  @override
  Widget build(BuildContext context) => SizedBox(
    height: 50,
    width: double.infinity,
    child: OutlinedButton(
      onPressed: onPressed,
      style: OutlinedButton.styleFrom(
        foregroundColor: Colors.white,
        side: const BorderSide(color: stroke),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
      child: Text(text, style: const TextStyle(fontWeight: FontWeight.bold)),
    ),
  );
}

class InfoTile extends StatelessWidget {
  const InfoTile({super.key, this.icon, required this.text, this.trailing});
  final IconData? icon;
  final String text;
  final String? trailing;
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
      color: greenPanel,
      borderRadius: BorderRadius.circular(12),
    ),
    child: Row(
      children: [
        if (icon != null) Icon(icon, color: mint),
        if (icon != null) const SizedBox(width: 10),
        Expanded(
          child: Text(text, style: const TextStyle(fontSize: 12, height: 1.4)),
        ),
        if (trailing != null)
          Text(trailing!, style: const TextStyle(color: mint, fontSize: 11)),
      ],
    ),
  );
}

class MarketCard extends StatelessWidget {
  const MarketCard({
    super.key,
    this.items = const [],
    this.loading = false,
    this.error,
    this.onTap,
  });
  final List<Map<String, dynamic>> items;
  final bool loading;
  final String? error;
  final VoidCallback? onTap;

  String _price(dynamic value) {
    final price = (num.tryParse(value.toString()) ?? 0) / 1000000;
    return '${price.toStringAsFixed(2).replaceAll('.', ',')}tr';
  }

  @override
  Widget build(BuildContext context) {
    final changedItems = items
        .where((item) => (parseApiNumber(item['trend']) ?? 0) != 0)
        .toList();
    return InkWell(
      onTap: changedItems.isEmpty ? null : onTap,
      borderRadius: BorderRadius.circular(14),
      child: CardBox(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'Nhịp giá thị trường',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                const Tag('HÔM NAY'),
              ],
            ),
            const SizedBox(height: 10),
            if (loading)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 8),
                child: LinearProgressIndicator(
                  color: mint,
                  backgroundColor: stroke,
                ),
              )
            else if (error != null)
              Text(error!, style: const TextStyle(color: muted))
            else if (changedItems.isEmpty)
              const Text(
                'Chưa có linh kiện thay đổi giá trong khu vực này.',
                style: TextStyle(color: muted),
              )
            else
              ...changedItems
                  .take(3)
                  .map(
                    (item) => Padding(
                      padding: const EdgeInsets.only(bottom: 7),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Expanded(
                            child: Text(
                              item['name'] as String? ?? 'Sản phẩm',
                              style: const TextStyle(color: muted),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          Builder(
                            builder: (context) {
                              final trend = parseApiNumber(item['trend']) ?? 0;
                              return Text(
                                '${_price(item['price'])}  ${trend < 0 ? '↓' : '↑'} ${trend.abs()}%',
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                ),
                              );
                            },
                          ),
                        ],
                      ),
                    ),
                  ),
            if (!loading && error == null && changedItems.isNotEmpty) ...[
              const SizedBox(height: 4),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton(
                  onPressed: onTap,
                  child: const Text('Xem giá thị trường'),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class QuickCard extends StatelessWidget {
  const QuickCard({
    super.key,
    required this.icon,
    required this.text,
    required this.onTap,
  });
  final IconData icon;
  final String text;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => InkWell(
    onTap: onTap,
    child: CardBox(
      child: Row(
        children: [
          Icon(icon, color: mint),
          const SizedBox(width: 10),
          Text(text),
        ],
      ),
    ),
  );
}

class BuildProgress extends StatelessWidget {
  const BuildProgress({
    super.key,
    this.buildData,
    this.loading = false,
    this.onContinue,
  });
  final Map<String, dynamic>? buildData;
  final bool loading;
  final VoidCallback? onContinue;

  @override
  Widget build(BuildContext context) => CardBox(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'CẤU HÌNH ĐANG LÀM',
          style: TextStyle(color: Colors.amber, fontSize: 10),
        ),
        const SizedBox(height: 8),
        if (loading)
          const Text(
            'Đang tải cấu hình của bạn...',
            style: TextStyle(color: muted),
          )
        else if (buildData == null)
          const Text(
            'Bạn chưa có cấu hình nào',
            style: TextStyle(fontWeight: FontWeight.bold),
          )
        else ...[
          Text(
            '${buildData!['name'] ?? 'Build của tôi'} • ${buildData!['completion'] ?? 0}%',
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 10),
          LinearProgressIndicator(
            value: (parseApiNumber(buildData!['completion']) ?? 0) / 100,
            color: mint,
            backgroundColor: stroke,
          ),
          const SizedBox(height: 8),
          Text(
            'Tạm tính: ${_formatVnd(buildData!['totalPrice'])}',
            style: const TextStyle(color: mint, fontSize: 19),
          ),
          const SizedBox(height: 4),
          Text(
            '${_remainingPrice(buildData!)} • ${_missingComponents(buildData!)}',
            style: const TextStyle(color: muted, fontSize: 11),
          ),
          const SizedBox(height: 10),
          if (onContinue != null)
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: onContinue,
                child: const Text('Tiếp tục build'),
              ),
            ),
        ],
      ],
    ),
  );

  String _formatVnd(dynamic value) {
    final amount = (parseApiNumber(value) ?? 0).toInt();
    return '${amount.toString().replaceAllMapped(RegExp(r'(\d)(?=(\d{3})+(?!\d))'), (m) => '${m[1]}.')}đ';
  }

  String _remainingPrice(Map<String, dynamic> build) {
    final budget = (parseApiNumber(build['budget']) ?? 0).toInt();
    final total = (parseApiNumber(build['totalPrice']) ?? 0).toInt();
    return 'Còn ${_formatVnd((budget - total).clamp(0, budget))}';
  }

  String _missingComponents(Map<String, dynamic> build) {
    final components = build['components'];
    if (components is! Map) return 'chưa đủ dữ liệu';
    final missing = components.values.where((value) => value == null).length;
    return missing == 0 ? 'đủ linh kiện' : 'thiếu $missing linh kiện';
  }
}

class ProgressLine extends StatelessWidget {
  const ProgressLine({
    super.key,
    required this.label,
    required this.value,
    required this.progress,
    this.amber = false,
  });
  final String label;
  final String value;
  final double progress;
  final bool amber;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 15),
    child: LayoutBuilder(
      builder: (context, constraints) {
        final labelText = Text(
          label,
          style: const TextStyle(color: muted, fontSize: 10),
        );
        final valueText = Text(
          value,
          style: TextStyle(color: amber ? Colors.amber : mint, fontSize: 11),
        );
        final header = constraints.maxWidth < 380
            ? Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  labelText,
                  Align(alignment: Alignment.centerRight, child: valueText),
                ],
              )
            : Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [labelText, valueText],
              );
        return Column(
          children: [
            header,
            const SizedBox(height: 7),
            LinearProgressIndicator(
              value: progress,
              color: amber ? Colors.orange : mint,
              backgroundColor: stroke,
            ),
          ],
        );
      },
    ),
  );
}

class ComponentRow extends StatelessWidget {
  const ComponentRow({
    super.key,
    required this.type,
    required this.name,
    required this.price,
    this.onTap,
    this.onDelete,
  });
  final String type;
  final String name;
  final String price;
  final VoidCallback? onTap;
  final VoidCallback? onDelete;
  @override
  Widget build(BuildContext context) {
    final empty = name.startsWith('Kéo') || name.startsWith('Chọn');
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: panel,
          border: Border.all(color: empty ? stroke : const Color(0xff145344)),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(
          children: [
            const Icon(Icons.drag_indicator, color: muted, size: 18),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(type, style: const TextStyle(color: mint, fontSize: 9)),
                  Text(
                    name,
                    style: TextStyle(
                      fontSize: 12,
                      color: empty ? muted : Colors.white,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
            if (!empty)
              IconButton(
                icon: const Icon(
                  Icons.delete_outline,
                  color: Colors.redAccent,
                  size: 20,
                ),
                onPressed: onDelete,
                constraints: const BoxConstraints(),
                padding: EdgeInsets.zero,
              ),
            if (!empty)
              Padding(
                padding: const EdgeInsets.only(left: 8),
                child: Text(
                  price,
                  style: const TextStyle(
                    color: mint,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class ProductCard extends StatelessWidget {
  const ProductCard({super.key, required this.product, required this.onTap});
  final Product product;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => InkWell(
    onTap: onTap,
    child: Container(
      margin: const EdgeInsets.only(bottom: 9),
      padding: const EdgeInsets.all(9),
      decoration: BoxDecoration(
        color: panel,
        border: Border.all(color: stroke),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: Image.asset(
              product.image,
              width: 64,
              height: 64,
              fit: BoxFit.cover,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  product.detail,
                  style: const TextStyle(color: mint, fontSize: 9),
                ),
                Text(product.name, style: const TextStyle(fontSize: 12)),
                const SizedBox(height: 4),
                Text(
                  product.price,
                  style: TextStyle(
                    color: product.hasPrice && !product.priceEstimate
                        ? mint
                        : Colors.orange,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),
          if (!product.hasPrice)
            const Tag('Thiếu giá')
          else if (product.priceEstimate)
            const Tag('Ước tính')
          else if (!product.used)
            const Tag('Phù hợp'),
        ],
      ),
    ),
  );
}

class PowerAssessmentCard extends StatelessWidget {
  const PowerAssessmentCard({super.key, required this.assessment});

  final Map<String, dynamic> assessment;

  @override
  Widget build(BuildContext context) {
    final estimated = parseApiNumber(assessment['estimatedLoadW'])?.round();
    final recommended = parseApiNumber(assessment['recommendedPsuW'])?.round();
    final manufacturer = parseApiNumber(assessment['manufacturerMinimumW'])
        ?.round();
    final selected = parseApiNumber(assessment['selectedPsuW'])?.round();
    final margin = parseApiNumber(assessment['marginW'])?.round();
    final manufacturerMargin = parseApiNumber(
      assessment['marginVsManufacturerW'],
    )?.round();
    final loadMargin = parseApiNumber(assessment['marginFromLoadW'])?.round();
    final gpuNames = (assessment['manufacturerGpuNames'] as List? ?? const [])
        .map((item) => item.toString())
        .toList();
    final sources = (assessment['manufacturerSources'] as List? ?? const [])
        .map((item) => item.toString())
        .toList();
    final resultColor = selected == null
        ? Colors.amber
        : selected >= (recommended ?? 0)
        ? mint
        : Colors.orange;
    String marginText(int? value) => value == null
        ? 'Chưa đủ dữ liệu'
        : value >= 0
        ? 'Dư ${value}W'
        : 'Thiếu ${value.abs()}W';

    return CardBox(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'ĐÁNH GIÁ BỘ NGUỒN',
            style: TextStyle(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          _powerLine(
            'Tải CPU/GPU ước tính',
            estimated == null ? 'Chưa đủ dữ liệu' : '~${estimated}W',
          ),
          _powerLine(
            'Mức PSU tối thiểu đề nghị',
            recommended == null ? 'Chưa xác định' : '≥ ${recommended}W',
          ),
          _powerLine(
            'Mức tối thiểu theo hãng GPU',
            manufacturer == null
                ? 'Chưa có trong SQL'
                : '$manufacturer W${gpuNames.isEmpty ? '' : ' • ${gpuNames.join(', ')}'}',
          ),
          _powerLine(
            'PSU đang chọn',
            selected == null
                ? 'Chưa chọn'
                : '${assessment['selectedPsuName'] ?? 'PSU'} • ${selected}W',
          ),
          _powerLine('Dư/thiếu so với mức đề nghị', marginText(margin)),
          if (manufacturer != null)
            _powerLine(
              'Dư/thiếu so với mức hãng',
              marginText(manufacturerMargin),
            ),
          _powerLine(
            'Chênh so với tải ước tính',
            '${marginText(loadMargin)} • không phải mức PSU đề nghị',
          ),
          const Divider(height: 18),
          Text(
            selected == null
                ? 'Chưa chọn bộ nguồn.'
                : selected >= (recommended ?? 0)
                ? 'Đạt mức PSU đề nghị của cấu hình.'
                : 'Chưa đạt mức PSU đề nghị của cấu hình.',
            style: TextStyle(color: resultColor, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 6),
          Text(
            assessment['method']?.toString() ??
                'Ước tính từ dữ liệu linh kiện SQL.',
            style: const TextStyle(color: muted, fontSize: 11),
          ),
          if (sources.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(
              'Nguồn dữ liệu hãng: ${sources.map((source) => Uri.tryParse(source)?.host ?? source).join(', ')}',
              style: const TextStyle(color: muted, fontSize: 10),
            ),
          ],
        ],
      ),
    );
  }

  Widget _powerLine(String label, String value) => Padding(
    padding: const EdgeInsets.only(bottom: 4),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Text(
            label,
            style: const TextStyle(color: muted, fontSize: 11),
          ),
        ),
        const SizedBox(width: 8),
        Flexible(
          child: Text(
            value,
            textAlign: TextAlign.right,
            style: const TextStyle(fontSize: 11),
          ),
        ),
      ],
    ),
  );
}

class CompatibilityCriterionCard extends StatelessWidget {
  const CompatibilityCriterionCard({
    super.key,
    required this.title,
    required this.status,
    required this.detail,
    required this.remediation,
  });

  final String title;
  final String status;
  final String detail;
  final String remediation;

  @override
  Widget build(BuildContext context) {
    final color = status == 'pass'
        ? mint
        : status == 'unchecked'
        ? Colors.amber
        : Colors.redAccent;
    final label = status == 'pass'
        ? 'ĐẠT'
        : status == 'unchecked'
        ? 'CHƯA KIỂM TRA'
        : status == 'warning'
        ? 'CẢNH BÁO'
        : 'KHÔNG ĐẠT';
    return CardBox(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    title,
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 9,
                    vertical: 5,
                  ),
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: .14),
                    border: Border.all(color: color.withValues(alpha: .5)),
                    borderRadius: BorderRadius.circular(18),
                  ),
                  child: Text(
                    label,
                    style: TextStyle(
                      color: color,
                      fontWeight: FontWeight.bold,
                      fontSize: 9,
                    ),
                  ),
                ),
              ],
            ),
            if (detail.isNotEmpty) ...[
              const SizedBox(height: 6),
              Text(detail, style: const TextStyle(fontSize: 12)),
            ],
            if (status != 'pass' && remediation.isNotEmpty) ...[
              const SizedBox(height: 5),
              Text(remediation, style: TextStyle(color: color, fontSize: 11)),
            ],
          ],
        ),
      ),
    );
  }
}

class ScoreCard extends StatelessWidget {
  const ScoreCard({
    super.key,
    this.score,
    this.verdict,
    this.selectedCount,
    this.checkedCount,
  });
  final int? score;
  final String? verdict;
  final int? selectedCount;
  final int? checkedCount;

  @override
  Widget build(BuildContext context) => CardBox(
    child: Row(
      children: [
        const CircleAvatar(
          radius: 30,
          backgroundColor: Color(0xff342c17),
          child: Text(
            'B',
            style: TextStyle(
              color: Colors.amber,
              fontSize: 20,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                verdict == 'incompatible'
                    ? 'Có linh kiện không tương thích'
                    : verdict == 'warning'
                    ? 'Có cảnh báo cần xem'
                    : verdict == 'partial'
                    ? 'Đã kiểm tra một phần'
                    : score == null
                    ? 'Chưa đủ dữ liệu'
                    : 'Không thấy xung đột đã biết',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              Text(
                '${selectedCount ?? 0}/8 linh kiện • ${checkedCount ?? 0} tiêu chí đã kiểm tra${score == null ? '' : ' • $score/100 trên tiêu chí đã kiểm tra'}',
                style: TextStyle(color: muted, fontSize: 11),
              ),
            ],
          ),
        ),
        Tag(score == null ? '—' : '$score/100'),
      ],
    ),
  );
}

class WarningRow extends StatelessWidget {
  const WarningRow({
    super.key,
    required this.icon,
    required this.color,
    required this.title,
    required this.text,
  });
  final IconData icon;
  final Color color;
  final String title;
  final String text;
  @override
  Widget build(BuildContext context) => Container(
    margin: const EdgeInsets.only(bottom: 8),
    padding: const EdgeInsets.all(10),
    decoration: BoxDecoration(
      color: panel,
      border: Border.all(color: color.withValues(alpha: .55)),
      borderRadius: BorderRadius.circular(12),
    ),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, color: color, size: 18),
        const SizedBox(width: 9),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 12,
                ),
              ),
              const SizedBox(height: 3),
              Text(text, style: const TextStyle(color: muted, fontSize: 10)),
            ],
          ),
        ),
      ],
    ),
  );
}

class ChatBubble extends StatelessWidget {
  const ChatBubble({super.key, required this.text, required this.dark});
  final String text;
  final bool dark;
  @override
  Widget build(BuildContext context) => Container(
    margin: const EdgeInsets.only(bottom: 10),
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
      color: dark ? panel : greenPanel,
      borderRadius: BorderRadius.circular(12),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [Text(text, style: const TextStyle(fontSize: 12))],
    ),
  );
}

class SavedCard extends StatelessWidget {
  const SavedCard({
    super.key,
    required this.name,
    required this.price,
    required this.status,
    required this.area,
    required this.components,
    this.onEdit,
    this.onDelete,
  });
  final String name;
  final String price;
  final String status;
  final String area;
  final Map<String, dynamic> components;
  final VoidCallback? onEdit;
  final VoidCallback? onDelete;
  @override
  Widget build(BuildContext context) => CardBox(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(child: Text(name, style: const TextStyle(fontSize: 14))),
            Tag(status),
          ],
        ),
        const SizedBox(height: 6),
        Text(
          _componentSummary,
          style: const TextStyle(color: muted, fontSize: 10),
        ),
        const SizedBox(height: 8),
        Text(
          'GIÁ TẠI $area',
          style: const TextStyle(color: muted, fontSize: 9),
        ),
        Text(price, style: const TextStyle(color: mint, fontSize: 19)),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: onEdit,
                icon: const Icon(Icons.edit_outlined, size: 16),
                label: const Text('Sửa'),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: OutlinedButton.icon(
                onPressed: onDelete,
                icon: const Icon(Icons.delete_outline, size: 16),
                label: const Text('Xóa'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.redAccent,
                ),
              ),
            ),
          ],
        ),
      ],
    ),
  );

  String get _componentSummary {
    final names = components.values
        .whereType<Map>()
        .map((item) => item['name']?.toString())
        .whereType<String>()
        .toList();
    return names.isEmpty ? 'Chưa chọn linh kiện' : names.join(' · ');
  }
}

class SettingRow extends StatelessWidget {
  const SettingRow({
    super.key,
    required this.icon,
    required this.title,
    this.detail,
    this.end,
    this.toggle = false,
    this.value = false,
    this.onTap,
    this.onToggle,
  });
  final IconData icon;
  final String title;
  final String? detail;
  final String? end;
  final bool toggle;
  final bool value;
  final VoidCallback? onTap;
  final ValueChanged<bool>? onToggle;
  @override
  Widget build(BuildContext context) => InkWell(
    onTap: onTap,
    borderRadius: BorderRadius.circular(10),
    child: Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(7),
            decoration: BoxDecoration(
              color: panel2,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(icon, size: 16, color: mint),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 12,
                  ),
                ),
                if (detail != null)
                  Text(
                    detail!,
                    style: const TextStyle(color: muted, fontSize: 10),
                  ),
              ],
            ),
          ),
          if (toggle)
            Switch(value: value, onChanged: onToggle, activeThumbColor: mint)
          else
            Text(
              end ?? '›',
              style: const TextStyle(color: muted, fontSize: 11),
            ),
        ],
      ),
    ),
  );
}
