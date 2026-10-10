import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/material.dart';
import 'package:appbuildpc/main.dart';

void main() {
  testWidgets('opens the BuildPC demo and starts a configuration', (
    tester,
  ) async {
    await tester.pumpWidget(const PcBuildApp());
    expect(find.text('PCBUILD LOCAL'), findsOneWidget);
    final start = find.text('Bắt đầu với vị trí của tôi');
    await tester.ensureVisible(start);
    await tester.tap(start);
    await tester.pumpAndSettle();
    await tester.pumpWidget(const MaterialApp(home: MainScreen()));
    await tester.pumpAndSettle();
    final build = find.text('Build PC');
    await tester.ensureVisible(build);
    await tester.tap(build);
    await tester.pumpAndSettle();
    expect(find.text('Gaming 20 triệu'), findsOneWidget);
  });

  testWidgets('can use the recommendation flow', (tester) async {
    await tester.pumpWidget(const PcBuildApp());
    final start = find.text('Bắt đầu với vị trí của tôi');
    await tester.ensureVisible(start);
    await tester.tap(start);
    await tester.pumpAndSettle();
    await tester.pumpWidget(const MaterialApp(home: MainScreen()));
    await tester.pumpAndSettle();
    final scan = find.text('Quét SP');
    await tester.ensureVisible(scan);
    await tester.tap(scan);
    await tester.pumpAndSettle();
    expect(find.text('Nhận diện linh kiện'), findsOneWidget);
  });

  testWidgets('can choose an individual component in the builder', (
    tester,
  ) async {
    await tester.pumpWidget(const MaterialApp(home: BuildTab()));
    await tester.tap(find.text('Chọn GPU'));
    await tester.pumpAndSettle();
    expect(find.text('Chọn GPU'), findsOneWidget);
    await tester.tap(find.text('ASUS Dual GeForce RTX 4060 OC 8GB'));
    await tester.pumpAndSettle();
    expect(find.text('ASUS Dual GeForce RTX 4060 OC 8GB'), findsOneWidget);
    expect(find.text('8,69tr'), findsOneWidget);
  });

  testWidgets('validates login and opens the demo home', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: LoginScreen()));
    await tester.tap(find.text('Đăng nhập'));
    await tester.pump();
    expect(
      find.text('Demo yêu cầu email hợp lệ và mật khẩu từ 6 ký tự.'),
      findsOneWidget,
    );
    await tester.enterText(find.byType(TextField).at(0), 'demo@example.com');
    await tester.enterText(find.byType(TextField).at(1), '123456');
    await tester.tap(find.text('Đăng nhập'));
    await tester.pumpAndSettle();
    expect(find.text('Xin chào, Minh 👋'), findsNothing);
  });

  testWidgets('validates and creates a demo account', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: SignupScreen()));
    final createButton = find.text('Tạo tài khoản').first;
    await tester.ensureVisible(createButton);
    await tester.tap(createButton);
    await tester.pumpAndSettle();
    expect(find.text('Tạo tài khoản'), findsOneWidget);
    final fields = find.byType(TextField);
    await tester.enterText(fields.at(0), 'Demo User');
    await tester.enterText(fields.at(1), 'demo@example.com');
    await tester.enterText(fields.at(2), '12345678');
    final submitButton = find.text('Tạo tài khoản').first;
    await tester.ensureVisible(submitButton);
    await tester.tap(submitButton);
    await tester.pumpAndSettle();
    expect(find.text('Xin chào, Minh 👋'), findsNothing);
  });

  testWidgets('all Figma screens render without layout exceptions', (
    tester,
  ) async {
    final screens = <Widget>[
      const WelcomeScreen(),
      const LoginScreen(),
      const SignupScreen(),
      const MainScreen(),
      const BuildTab(),
      const ProductListScreen(),
      const ScannerScreen(),
      const CompatibilityScreen(),
      const ChatTab(),
      const SavedTab(),
      const AccountTab(),
    ];
    for (final screen in screens) {
      await tester.pumpWidget(
        MaterialApp(theme: ThemeData.dark(), home: screen),
      );
      await tester.pump();
      expect(tester.takeException(), isNull);
    }
  });
}
