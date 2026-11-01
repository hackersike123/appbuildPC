// ignore_for_file: use_build_context_synchronously

part of '../main.dart';

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
