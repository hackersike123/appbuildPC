import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';

void main() => runApp(const PcBuildApp());

const mint = Color(0xff63e6be);
const bg = Color(0xff070a0f);
const panel = Color(0xff10161f);
const panel2 = Color(0xff171e28);
const stroke = Color(0xff263140);
const muted = Color(0xff8d99a8);
const greenPanel = Color(0xff173f38);

Future<bool> requestLocationPermission(BuildContext context) async {
  final status = await Permission.locationWhenInUse.request();
  if (context.mounted) {
    showDemoMessage(
      context,
      status.isGranted
          ? 'Đã cấp quyền vị trí. Giá demo vẫn dùng dữ liệu mẫu.'
          : 'Chưa cấp quyền vị trí. Demo vẫn tiếp tục với TP. Hồ Chí Minh.',
    );
  }
  return status.isGranted;
}

Future<bool> requestCameraPermission(BuildContext context) async {
  final status = await Permission.camera.request();
  if (context.mounted) {
    showDemoMessage(
      context,
      status.isGranted
          ? 'Đã cấp quyền camera. Scanner demo vẫn dùng ảnh mẫu.'
          : 'Chưa cấp quyền camera. Scanner demo vẫn dùng ảnh mẫu.',
    );
  }
  return status.isGranted;
}

void showDemoMessage(BuildContext context, String message) {
  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
}

double productPriceInMillions(String value) {
  if (value.contains('tr')) {
    return double.parse(value.replaceAll(',', '.').replaceAll('tr', ''));
  }
  final digits = value.replaceAll('.', '').replaceAll(RegExp(r'[^0-9]'), '');
  return (double.tryParse(digits) ?? 0) / 1000000;
}

class Product {
  const Product(
    this.name,
    this.price,
    this.detail,
    this.image, {
    this.used = false,
  });
  final String name;
  final String price;
  final String detail;
  final String image;
  final bool used;
}

const products = [
  Product(
    'ASUS Dual GeForce RTX 4060 OC 8GB',
    '8.690.000đ',
    'MỚI  ·  GEARVN',
    'assets/figma/gpu1.jpeg',
  ),
  Product(
    'Gigabyte RTX 4060 Windforce OC 8GB',
    '7.250.000đ',
    'CŨ 98%  ·  Q.10',
    'assets/figma/gpu2.png',
    used: true,
  ),
  Product(
    'MSI RTX 4060 Ventus 2X Black 8G OC',
    '8.490.000đ',
    'MỚI  ·  MEMORYZONE',
    'assets/figma/gpu1.jpeg',
  ),
  Product(
    'Zotac Gaming RTX 3060 Twin Edge 12GB',
    '5.900.000đ',
    'CŨ 95%  ·  THỦ ĐỨC',
    'assets/figma/gpu2.png',
    used: true,
  ),
];

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
    home: const WelcomeScreen(),
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
  });
  final Widget child;
  final String? title;
  final String? subtitle;
  final bool back;
  final Widget? action;
  @override
  Widget build(BuildContext context) => Scaffold(
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
  );
}

class WelcomeScreen extends StatelessWidget {
  const WelcomeScreen({super.key});
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
              onPressed: () => _startWithLocation(context),
            ),
            const SizedBox(height: 10),
            SecondaryButton(
              text: 'Chọn khu vực thủ công',
              onPressed: () => _openHome(context),
            ),
          ],
        ),
      ),
    ),
  );
  Future<void> _startWithLocation(BuildContext context) async {
    await requestLocationPermission(context);
    if (context.mounted) _openHome(context);
  }

  void _openHome(BuildContext context) => Navigator.pushReplacement(
    context,
    MaterialPageRoute(builder: (_) => const MainScreen()),
  );
}

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});
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
              const Text('Chào mừng trở lại', style: TextStyle(fontSize: 29)),
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
                  errorText: email.text.isNotEmpty && !email.text.contains('@')
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
                      obscurePassword ? Icons.visibility : Icons.visibility_off,
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
                            'Demo yêu cầu email hợp lệ và mật khẩu từ 6 ký tự.',
                          );
                          return;
                        }
                        setState(() => busy = true);
                        await Future<void>.delayed(
                          const Duration(milliseconds: 450),
                        );
                        if (!context.mounted) return;
                        Navigator.pushReplacement(
                          context,
                          MaterialPageRoute(builder: (_) => const MainScreen()),
                        );
                      },
              ),
              const SizedBox(height: 20),
              const Center(
                child: Text(
                  'HOẶC TIẾP TỤC VỚI',
                  style: TextStyle(color: Color(0xff596574), fontSize: 11),
                ),
              ),
              const SizedBox(height: 14),
              SecondaryButton(
                text: 'Google',
                onPressed: () => Navigator.pushReplacement(
                  context,
                  MaterialPageRoute(builder: (_) => const MainScreen()),
                ),
              ),
              Center(
                child: TextButton(
                  onPressed: () => Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const SignupScreen()),
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
              Navigator.pop(dialogContext);
              showDemoMessage(
                context,
                'Đã gửi hướng dẫn khôi phục (mô phỏng demo).',
              );
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
  const SignupScreen({super.key});
  @override
  State<SignupScreen> createState() => _SignupScreenState();
}

class _SignupScreenState extends State<SignupScreen> {
  final name = TextEditingController();
  final email = TextEditingController();
  final password = TextEditingController();
  final confirmPassword = TextEditingController();
  final area = TextEditingController(text: 'TP. Hồ Chí Minh');
  bool acceptedTerms = false;
  bool obscurePassword = true;
  bool obscureConfirmPassword = true;
  bool busy = false;

  @override
  void dispose() {
    name.dispose();
    email.dispose();
    password.dispose();
    confirmPassword.dispose();
    area.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Shell(
    title: 'Tạo tài khoản',
    subtitle: 'Lưu build, theo dõi giá và nhận tư vấn',
    back: true,
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
          const SizedBox(height: 14),
          const FieldLabel('XÁC NHẬN MẬT KHẨU'),
          TextField(
            controller: confirmPassword,
            obscureText: obscureConfirmPassword,
            decoration: InputDecoration(
              prefixIcon: const Icon(Icons.lock_reset_outlined),
              hintText: 'Nhập lại mật khẩu',
              suffixIcon: IconButton(
                onPressed: () => setState(
                  () => obscureConfirmPassword = !obscureConfirmPassword,
                ),
                icon: Icon(
                  obscureConfirmPassword
                      ? Icons.visibility
                      : Icons.visibility_off,
                ),
              ),
            ),
          ),
          const SizedBox(height: 14),
          const FieldLabel('KHU VỰC ĐỊNH GIÁ'),
          TextField(
            controller: area,
            decoration: InputDecoration(
              prefixIcon: const Icon(Icons.location_on_outlined),
              hintText: 'TP. Hồ Chí Minh',
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
  );

  Future<void> _createAccount(BuildContext context) async {
    final errors = <String>[];
    if (name.text.trim().length < 2) errors.add('họ tên');
    if (!email.text.contains('@')) errors.add('email hợp lệ');
    if (password.text.length < 8) errors.add('mật khẩu từ 8 ký tự');
    if (password.text != confirmPassword.text) {
      errors.add('mật khẩu xác nhận trùng khớp');
    }
    if (area.text.trim().isEmpty) errors.add('khu vực định giá');
    if (!acceptedTerms) errors.add('đồng ý điều khoản');
    if (errors.isNotEmpty) {
      showDemoMessage(context, 'Vui lòng kiểm tra: ${errors.join(', ')}.');
      return;
    }
    setState(() => busy = true);
    await Future<void>.delayed(const Duration(milliseconds: 550));
    if (!context.mounted) return;
    showDemoMessage(context, 'Tạo tài khoản thành công trong chế độ demo.');
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(builder: (_) => const MainScreen()),
    );
  }
}

class MainScreen extends StatefulWidget {
  const MainScreen({super.key});
  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> {
  int tab = 0;
  @override
  Widget build(BuildContext context) => Scaffold(
    body: IndexedStack(
      index: tab,
      children: [
        HomeTab(onOpen: _open),
        const BuildTab(),
        const SavedTab(),
        const ChatTab(),
        const AccountTab(),
      ],
    ),
    bottomNavigationBar: NavigationBar(
      selectedIndex: tab,
      onDestinationSelected: (value) => setState(() => tab = value),
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
  );
  void _open(Widget page) =>
      Navigator.push(context, MaterialPageRoute(builder: (_) => page));
}

class HomeTab extends StatelessWidget {
  const HomeTab({super.key, required this.onOpen});
  final void Function(Widget) onOpen;
  @override
  Widget build(BuildContext context) => Shell(
    child: SafeArea(
      child: ListView(
        padding: const EdgeInsets.fromLTRB(18, 28, 18, 20),
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Xin chào, Minh 👋',
                    style: TextStyle(fontSize: 21, fontWeight: FontWeight.bold),
                  ),
                  SizedBox(height: 4),
                  Text(
                    'Sẵn sàng lên cấu hình mới?',
                    style: TextStyle(color: muted, fontSize: 12),
                  ),
                ],
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 9,
                ),
                decoration: BoxDecoration(
                  color: panel2,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: const Text('🔔 2'),
              ),
            ],
          ),
          const SizedBox(height: 16),
          const InfoTile(
            icon: Icons.location_on_outlined,
            text: 'GIÁ THỊ TRƯỜNG TẠI\nTP. Hồ Chí Minh • GPS',
            trailing: 'Thay đổi',
          ),
          const SizedBox(height: 16),
          const MarketCard(),
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
                onTap: () => onOpen(const BuildTab()),
              ),
              QuickCard(
                icon: Icons.camera_alt_outlined,
                text: 'Quét SP',
                onTap: () => onOpen(const ScannerScreen()),
              ),
              QuickCard(
                icon: Icons.scatter_plot,
                text: 'So giá',
                onTap: () => onOpen(const ProductListScreen()),
              ),
              QuickCard(
                icon: Icons.chat_bubble_outline,
                text: 'Tư vấn',
                onTap: () => onOpen(const ChatTab()),
              ),
            ],
          ),
          const SizedBox(height: 18),
          const BuildProgress(),
        ],
      ),
    ),
  );
}

class BuildTab extends StatefulWidget {
  const BuildTab({super.key});
  @override
  State<BuildTab> createState() => _BuildTabState();
}

class _BuildTabState extends State<BuildTab> {
  bool saved = false;
  final selected = <String, String>{
    'CPU': 'Ryzen 5 7600',
    'MAINBOARD': 'MSI B650M Gaming Plus',
    'GPU': 'Chọn GPU',
    'RAM': 'Kingston Fury 32GB DDR5',
    'SSD': 'WD Black SN770 1TB',
    'PSU': 'Chọn nguồn',
    'CASE': 'Montech Air 100',
    'TẢN NHIỆT': 'Chọn tản nhiệt',
  };
  final prices = <String, double>{
    'CPU': 4.89,
    'MAINBOARD': 3.69,
    'GPU': 0,
    'RAM': 2.15,
    'SSD': 1.89,
    'PSU': 0,
    'CASE': 1.19,
    'TẢN NHIỆT': 0,
  };
  bool get isComplete =>
      selected.values.every((value) => !value.startsWith('Chọn'));

  Future<void> _choose(String type) async {
    final result = await Navigator.push<(String, double)>(
      context,
      MaterialPageRoute(
        builder: (_) => ProductListScreen(
          componentType: type,
          onSelected: (name, price) => Navigator.pop(context, (name, price)),
        ),
      ),
    );
    if (result != null) {
      setState(() {
        selected[type] = result.$1;
        prices[type] = result.$2;
        saved = false;
      });
    }
  }

  String _total() {
    final total = prices.values.fold<double>(0, (sum, value) => sum + value);
    return '${total.toStringAsFixed(2).replaceAll('.', ',')}tr';
  }

  @override
  Widget build(BuildContext context) => Shell(
    title: 'Gaming 20 triệu',
    subtitle: '5/8 linh kiện • TP. Hồ Chí Minh',
    action: TextButton.icon(
      onPressed: () {
        if (!isComplete) {
          showDemoMessage(
            context,
            'Hãy chọn đủ GPU, PSU và tản nhiệt trước khi lưu.',
          );
          return;
        }
        setState(() => saved = true);
        showDemoMessage(context, 'Đã lưu cấu hình Gaming 20 triệu.');
      },
      icon: Icon(saved ? Icons.check : Icons.bookmark_border, color: mint),
      label: Text(
        saved ? 'Đã lưu' : 'Lưu',
        style: const TextStyle(color: mint),
      ),
    ),
    child: SafeArea(
      child: ListView(
        padding: const EdgeInsets.fromLTRB(18, 6, 18, 20),
        children: [
          const ProgressLine(
            label: 'TIẾN ĐỘ BUILD',
            value: '62%',
            progress: .62,
          ),
          const ProgressLine(
            label: 'LƯỢNG ĐIỆN TIÊU THỤ',
            value: '320W / 650W',
            progress: .42,
            amber: true,
          ),
          ...selected.entries.map(
            (item) => ComponentRow(
              type: item.key,
              name: item.value,
              price: prices[item.key] == 0
                  ? '–'
                  : '${prices[item.key]!.toStringAsFixed(2).replaceAll('.', ',')}tr',
              onTap: () => _choose(item.key),
            ),
          ),
          const SizedBox(height: 18),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Tag(
                selected.values.any((value) => value.startsWith('Chọn'))
                    ? '⚠ CHƯA ĐỦ LINH KIỆN'
                    : '✓ TƯƠNG THÍCH',
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
                ],
              ),
            ],
          ),
          const SizedBox(height: 12),
          PrimaryButton(
            text: '+ Thêm linh kiện',
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const ProductListScreen()),
            ),
          ),
          const SizedBox(height: 10),
          SecondaryButton(
            text: 'Kiểm tra tương thích',
            onPressed: () {
              if (!isComplete) {
                showDemoMessage(
                  context,
                  'Chưa thể kiểm tra: cấu hình còn thiếu linh kiện.',
                );
                return;
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

class ProductListScreen extends StatelessWidget {
  const ProductListScreen({
    super.key,
    this.componentType = 'GPU',
    this.onSelected,
  });
  final String componentType;
  final void Function(String name, double price)? onSelected;

  List<Product> get _items {
    if (componentType == 'GPU') return products;
    final options = <String, List<Product>>{
      'CPU': [
        const Product(
          'AMD Ryzen 5 7600',
          '4,89tr',
          'AM5 · 6 nhân',
          'assets/figma/gpu1.jpeg',
        ),
        const Product(
          'AMD Ryzen 7 7800X3D',
          '9,99tr',
          'AM5 · Gaming',
          'assets/figma/gpu2.png',
        ),
      ],
      'MAINBOARD': [
        const Product(
          'MSI B650M Gaming Plus',
          '3,69tr',
          'AM5 · DDR5',
          'assets/figma/gpu1.jpeg',
        ),
        const Product(
          'ASUS TUF B650-PLUS',
          '4,29tr',
          'AM5 · ATX',
          'assets/figma/gpu2.png',
        ),
      ],
      'RAM': [
        const Product(
          'Kingston Fury 32GB DDR5',
          '2,15tr',
          '6000 MT/s',
          'assets/figma/gpu1.jpeg',
        ),
        const Product(
          'Corsair Vengeance 32GB',
          '2,39tr',
          '6000 MT/s',
          'assets/figma/gpu2.png',
        ),
      ],
      'SSD': [
        const Product(
          'WD Black SN770 1TB',
          '1,89tr',
          'NVMe Gen4',
          'assets/figma/gpu1.jpeg',
        ),
        const Product(
          'Samsung 990 EVO 1TB',
          '2,29tr',
          'NVMe Gen4',
          'assets/figma/gpu2.png',
        ),
      ],
      'PSU': [
        const Product(
          'Corsair RM650e 650W',
          '1,79tr',
          '80+ Gold · ATX 3.0',
          'assets/figma/gpu1.jpeg',
        ),
        const Product(
          'MSI MAG A750GL 750W',
          '2,19tr',
          '80+ Gold · ATX 3.0',
          'assets/figma/gpu2.png',
        ),
      ],
      'CASE': [
        const Product(
          'Montech Air 100',
          '1,19tr',
          'M-ATX · Mesh',
          'assets/figma/gpu1.jpeg',
        ),
        const Product(
          'Lian Li Lancool 216',
          '2,49tr',
          'ATX · Airflow',
          'assets/figma/gpu2.png',
        ),
      ],
      'TẢN NHIỆT': [
        const Product(
          'DeepCool AK400',
          '0,79tr',
          'TDP 220W',
          'assets/figma/gpu1.jpeg',
        ),
        const Product(
          'Thermalright Peerless Assassin',
          '1,19tr',
          'TDP 265W',
          'assets/figma/gpu2.png',
        ),
      ],
    };
    return options[componentType] ?? products;
  }

  @override
  Widget build(BuildContext context) => Shell(
    title: 'Chọn $componentType',
    subtitle: '${_items.length} sản phẩm phù hợp tại TP. Hồ Chí Minh',
    back: true,
    child: SafeArea(
      child: ListView(
        padding: const EdgeInsets.fromLTRB(18, 4, 18, 20),
        children: [
          const TextField(
            decoration: InputDecoration(
              prefixIcon: Icon(Icons.search),
              hintText: 'Tìm RTX 4060, RX 7600...',
              suffixIcon: Icon(Icons.tune),
            ),
          ),
          const SizedBox(height: 14),
          const Wrap(
            spacing: 8,
            children: [
              Tag('Tất cả'),
              Tag('Hàng mới'),
              Tag('Hàng cũ'),
              Tag('≤ 10 triệu'),
            ],
          ),
          const SizedBox(height: 14),
          const InfoTile(
            text: 'Giá trung vị RTX 4060 tại khu vực',
            trailing: '8,55tr',
          ),
          const SizedBox(height: 8),
          ..._items.map(
            (p) => ProductCard(
              product: p,
              onTap: () {
                final price = productPriceInMillions(p.price);
                if (onSelected != null) {
                  onSelected!(p.name, price);
                } else {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => const CompatibilityScreen(),
                    ),
                  );
                }
              },
            ),
          ),
        ],
      ),
    ),
  );
}

class ScannerScreen extends StatefulWidget {
  const ScannerScreen({super.key});
  @override
  State<ScannerScreen> createState() => _ScannerScreenState();
}

class _ScannerScreenState extends State<ScannerScreen> {
  bool scanned = true;
  @override
  Widget build(BuildContext context) => Shell(
    title: 'Nhận diện linh kiện',
    subtitle: 'Đưa sản phẩm hoặc hộp vào khung',
    back: true,
    action: const Tag('Lịch sử'),
    child: SafeArea(
      child: ListView(
        padding: const EdgeInsets.fromLTRB(18, 8, 18, 20),
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(18),
            child: Stack(
              children: [
                Image.asset(
                  'assets/figma/scan.jpg',
                  height: 500,
                  width: double.infinity,
                  fit: BoxFit.cover,
                ),
                Positioned.fill(
                  child: Container(
                    decoration: BoxDecoration(
                      border: Border.all(color: mint, width: 2),
                      borderRadius: BorderRadius.circular(18),
                    ),
                  ),
                ),
                const Positioned(
                  top: 14,
                  left: 0,
                  right: 0,
                  child: Center(child: Tag('AI ĐANG QUÉT')),
                ),
                Positioned(
                  left: 14,
                  bottom: 15,
                  child: Text(
                    scanned
                        ? 'NHẬN DIỆN 96%\nMSI GeForce RTX 4060 Ventus 2X'
                        : 'SẴN SÀNG QUÉT\nĐưa linh kiện vào khung',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 18),
          Center(
            child: InkWell(
              borderRadius: BorderRadius.circular(40),
              onTap: () async {
                final allowed = await requestCameraPermission(context);
                if (allowed && mounted) {
                  setState(() => scanned = true);
                  showDemoMessage(
                    this.context,
                    'Đã nhận diện GPU mẫu trong chế độ demo.',
                  );
                }
              },
              child: const CircleAvatar(
                radius: 34,
                backgroundColor: mint,
                child: Icon(Icons.camera_alt, color: bg, size: 28),
              ),
            ),
          ),
          const SizedBox(height: 10),
          const Center(
            child: Text(
              'Chạm để quét • Giữ máy ổn định',
              style: TextStyle(color: muted),
            ),
          ),
        ],
      ),
    ),
  );
}

class CompatibilityScreen extends StatelessWidget {
  const CompatibilityScreen({super.key});
  @override
  Widget build(BuildContext context) => Shell(
    title: 'Báo cáo tương thích',
    subtitle: 'Phân tích tự động • vừa xong',
    back: true,
    child: SafeArea(
      child: ListView(
        padding: const EdgeInsets.fromLTRB(18, 8, 18, 20),
        children: [
          ScoreCard(),
          const SizedBox(height: 14),
          WarningRow(
            icon: Icons.error_outline,
            color: Colors.redAccent,
            title: 'PSU 550W không đủ công suất',
            text: 'RTX 4070 Super + Ryzen 7 7800X3D cần tối thiểu 650W; khuyến nghị 750W.',
          ),
          WarningRow(
            icon: Icons.warning_amber,
            color: Colors.amber,
            title: 'RAM có thể chạy dưới tốc độ công bố',
            text: 'DDR5-6400 sẽ hạ về 6000 MT/s theo mức tối ưu của CPU.',
          ),
          WarningRow(
            icon: Icons.warning_amber,
            color: Colors.amber,
            title: 'Khoảng hở tản nhiệt sát giới hạn',
            text: 'Tản khí cao 158 mm, case hỗ trợ tối đa 160 mm.',
          ),
          WarningRow(
            icon: Icons.check_circle_outline,
            color: Colors.greenAccent,
            title: 'Socket & chipset tương thích',
            text: 'Ryzen 7 7800X3D sử dụng AM5, tương thích mainboard B650.',
          ),
          const SizedBox(height: 14),
          const Text(
            'Đề xuất thay thế',
            style: TextStyle(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 10),
          ProductCard(
            product: const Product(
              'Corsair RM750e 750W Gold',
              '2.590.000đ',
              'Dư 24% công suất • ATX 3.0',
              'assets/figma/gpu2.png',
            ),
            onTap: () {},
          ),
        ],
      ),
    ),
  );
}

class ChatTab extends StatefulWidget {
  const ChatTab({super.key});
  @override
  State<ChatTab> createState() => _ChatTabState();
}

class _ChatTabState extends State<ChatTab> {
  final question = TextEditingController();
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
      onPressed: () => showDemoMessage(context, 'Đã xóa cuộc trò chuyện demo.'),
      child: const Text('Xóa', style: TextStyle(color: mint)),
    ),
    child: SafeArea(
      child: Column(
        children: [
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(18, 8, 18, 8),
              children: [
                ChatBubble(
                  text: 'Chào Minh! Bạn đang tìm linh kiện nào, ngân sách và nhu cầu chính là gì?',
                  dark: true,
                ),
                const Wrap(
                  spacing: 6,
                  children: [
                    Tag('GPU dưới 10 triệu'),
                    Tag('Build gaming 20 triệu'),
                    Tag('So sánh hàng cũ/mới'),
                  ],
                ),
                ChatBubble(
                  text: 'Gợi ý GPU chơi 2K, nguồn 650W, ưu tiên giá tốt tại TP.HCM.',
                  dark: false,
                ),
                ChatBubble(
                  text: 'RTX 4060 Ti 8GB phù hợp nhất: hiệu suất 2K tốt, nguồn 650W đủ và giá mới đang giảm 4%.',
                  dark: true,
                  product: true,
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 6, 18, 10),
            child: TextField(
              controller: question,
              onSubmitted: (_) => _send(context),
              decoration: InputDecoration(
                hintText: 'Hỏi về linh kiện, giá, tương thích...',
                suffixIcon: IconButton(
                  onPressed: () => _send(context),
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

  void _send(BuildContext context) {
    final text = question.text.trim();
    if (text.isEmpty) {
      showDemoMessage(context, 'Hãy nhập câu hỏi trước khi gửi.');
      return;
    }
    question.clear();
    showDemoMessage(
      context,
      'BuildMate: Mình đã ghi nhận “$text”. Đây là tư vấn mô phỏng trong demo.',
    );
  }
}

class SavedTab extends StatelessWidget {
  const SavedTab({super.key});
  @override
  Widget build(BuildContext context) => Shell(
    title: 'Cấu hình đã lưu',
    subtitle: '3 build được đồng bộ với tài khoản',
    action: TextButton.icon(
      onPressed: () => Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => const BuildTab()),
      ),
      icon: const Icon(Icons.add, color: mint, size: 18),
      label: const Text('Tạo mới', style: TextStyle(color: mint)),
    ),
    child: SafeArea(
      child: ListView(
        padding: const EdgeInsets.fromLTRB(18, 8, 18, 20),
        children: [
          const InfoTile(
            icon: Icons.cloud_done_outlined,
            text: 'Đã lưu vào tài khoản minh.nguyen@email.com',
          ),
          const SizedBox(height: 14),
          const Wrap(
            spacing: 8,
            children: [
              Tag('Tất cả 3'),
              Tag('Tương thích 2'),
              Tag('Cảnh báo 1'),
            ],
          ),
          const SizedBox(height: 14),
          ...[
            [
              'Gaming 2K • Ryzen 5',
              '22.410.000đ',
              'TƯƠNG THÍCH',
              'TP. HỒ CHÍ MINH',
            ],
            ['Workstation Creator', '48.790.000đ', '1 CẢNH BÁO', 'HÀ NỘI'],
            ['Esports tiết kiệm', '11.280.000đ', 'TƯƠNG THÍCH', 'ĐÀ NẴNG'],
          ].map(
            (item) => SavedCard(
              name: item[0],
              price: item[1],
              status: item[2],
              area: item[3],
            ),
          ),
          const SizedBox(height: 10),
          const InfoTile(
            text: 'So với giá TP.HCM',
            trailing: 'Hà Nội +2,4% • Đà Nẵng +1,1%',
          ),
        ],
      ),
    ),
  );
}

class AccountTab extends StatelessWidget {
  const AccountTab({super.key});
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
                const CircleAvatar(
                  radius: 23,
                  backgroundColor: greenPanel,
                  child: Text(
                    'MN',
                    style: TextStyle(color: mint, fontWeight: FontWeight.bold),
                  ),
                ),
                const SizedBox(width: 12),
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Minh Nguyễn',
                        style: TextStyle(fontWeight: FontWeight.bold),
                      ),
                      Text(
                        'minh.nguyen@email.com',
                        style: TextStyle(color: muted, fontSize: 11),
                      ),
                    ],
                  ),
                ),
                const Tag('Chỉnh sửa'),
              ],
            ),
          ),
          const SizedBox(height: 12),
          InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: () => requestLocationPermission(context),
            child: const InfoTile(
              icon: Icons.location_on_outlined,
              text: 'ĐỊNH GIÁ HIỆN TẠI · GPS\nTP. Hồ Chí Minh',
              trailing: 'Thay đổi',
            ),
          ),
          const SizedBox(height: 12),
          CardBox(
            child: Column(
              children: const [
                SettingRow(
                  icon: Icons.bookmark_border,
                  title: 'Cấu hình đã lưu',
                  detail: '3 build đã đồng bộ',
                  end: '3',
                ),
                SettingRow(
                  icon: Icons.local_offer_outlined,
                  title: 'Ưu tiên giá linh kiện',
                  detail: 'Hiển thị hàng mới trước',
                  end: 'Hàng mới',
                ),
                SettingRow(
                  icon: Icons.notifications_none,
                  title: 'Thông báo biến động giá',
                  detail: 'Báo khi giá thay đổi từ 3%',
                  toggle: true,
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          CardBox(
            child: Column(
              children: const [
                SettingRow(
                  icon: Icons.cancel_outlined,
                  title: 'Bảo mật & đổi mật khẩu',
                  end: '›',
                ),
                SettingRow(
                  icon: Icons.lock_outline,
                  title: 'Quyền riêng tư & vị trí',
                  detail: 'Vị trí: Khi dùng ứng dụng',
                  end: '›',
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          CardBox(
            child: Column(
              children: const [
                SettingRow(
                  icon: Icons.help_outline,
                  title: 'Trợ giúp & liên hệ',
                  end: '›',
                ),
                SettingRow(
                  icon: Icons.help_outline,
                  title: 'PCBuild Local',
                  detail: 'Phiên bản 1.8.2 • Build 246',
                  end: 'Mới nhất',
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          SecondaryButton(
            text: 'Đăng xuất',
            onPressed: () => Navigator.pushReplacement(
              context,
              MaterialPageRoute(builder: (_) => const LoginScreen()),
            ),
          ),
        ],
      ),
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
  const MarketCard({super.key});
  @override
  Widget build(BuildContext context) => CardBox(
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
        ...[
          ['RTX 4060 8GB', '8,49tr  ↓ 3,2%'],
          ['Ryzen 5 7600', '4,89tr  ↑ 1,8%'],
          ['DDR5 32GB', '2,15tr  ↑ 2,1%'],
        ].map(
          (v) => Padding(
            padding: const EdgeInsets.only(bottom: 7),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(v[0], style: const TextStyle(color: muted)),
                Text(v[1], style: const TextStyle(fontWeight: FontWeight.bold)),
              ],
            ),
          ),
        ),
      ],
    ),
  );
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
  const BuildProgress({super.key});
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
        const Text(
          'Gaming 20 triệu • 5/8 linh kiện',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 10),
        LinearProgressIndicator(
          value: .62,
          color: mint,
          backgroundColor: stroke,
        ),
      ],
    ),
  );
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
    child: Column(
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(label, style: const TextStyle(color: muted, fontSize: 10)),
            Text(
              value,
              style: TextStyle(
                color: amber ? Colors.amber : mint,
                fontSize: 11,
              ),
            ),
          ],
        ),
        const SizedBox(height: 7),
        LinearProgressIndicator(
          value: progress,
          color: amber ? Colors.orange : mint,
          backgroundColor: stroke,
        ),
      ],
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
  });
  final String type;
  final String name;
  final String price;
  final VoidCallback? onTap;
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
            Text(price, style: const TextStyle(color: mint, fontSize: 12)),
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
                  style: const TextStyle(
                    color: mint,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),
          if (!product.used) const Tag('Phù hợp'),
        ],
      ),
    ),
  );
}

class ScoreCard extends StatelessWidget {
  const ScoreCard({super.key});
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
        const Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Cần điều chỉnh',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              Text(
                '11 lỗi • 2 cảnh báo • 9 tiêu chí đạt',
                style: TextStyle(color: muted, fontSize: 11),
              ),
            ],
          ),
        ),
        const Tag('12/12'),
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
  const ChatBubble({
    super.key,
    required this.text,
    required this.dark,
    this.product = false,
  });
  final String text;
  final bool dark;
  final bool product;
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
      children: [
        Text(text, style: const TextStyle(fontSize: 12)),
        if (product)
          Padding(
            padding: const EdgeInsets.only(top: 10),
            child: ProductCard(product: products[0], onTap: () {}),
          ),
      ],
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
  });
  final String name;
  final String price;
  final String status;
  final String area;
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
        const Text(
          'Ryzen 5 7600 · B650M · RTX 4060 Ti · 32GB DDR5 · SSD 1TB · PSU 650W',
          style: TextStyle(color: muted, fontSize: 10),
        ),
        const SizedBox(height: 8),
        Text(
          'GIÁ TẠI $area',
          style: const TextStyle(color: muted, fontSize: 9),
        ),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(price, style: const TextStyle(color: mint, fontSize: 19)),
            const Row(
              children: [
                Icon(Icons.copy, size: 18),
                SizedBox(width: 14),
                Icon(Icons.more_horiz, size: 18),
              ],
            ),
          ],
        ),
      ],
    ),
  );
}

class SettingRow extends StatelessWidget {
  const SettingRow({
    super.key,
    required this.icon,
    required this.title,
    this.detail,
    this.end,
    this.toggle = false,
  });
  final IconData icon;
  final String title;
  final String? detail;
  final String? end;
  final bool toggle;
  @override
  Widget build(BuildContext context) => Padding(
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
          Switch(value: true, onChanged: (_) {}, activeThumbColor: mint)
        else
          Text(end ?? '›', style: const TextStyle(color: muted, fontSize: 11)),
      ],
    ),
  );
}
