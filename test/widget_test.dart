import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:appbuildpc/api_client.dart';
import 'package:appbuildpc/main.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  testWidgets('Android back on the root screen backgrounds the app', (
    tester,
  ) async {
    const channel = MethodChannel('appbuildpc/app_lifecycle');
    final calls = <MethodCall>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          calls.add(call);
          return true;
        });
    final previousPlatformOverride = debugDefaultTargetPlatformOverride;
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    try {
      await tester.pumpWidget(const PcBuildApp());
      await tester.binding.handlePopRoute();
      await tester.pump();

      expect(calls.map((call) => call.method), contains('moveToBackground'));
      expect(find.text('PCBUILD LOCAL'), findsOneWidget);
    } finally {
      debugDefaultTargetPlatformOverride = previousPlatformOverride;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null);
    }
  });

  test('parses numeric values returned by SQL Server', () {
    expect(parseApiNumber(4890000), 4890000);
    expect(parseApiNumber('4890000'), 4890000);
    expect(parseApiNumber('not-a-price'), isNull);
  });

  testWidgets('opens the BuildPC app and starts a configuration', (
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
    expect(find.text('Build mới'), findsOneWidget);
  });

  testWidgets('can use the scanner flow', (tester) async {
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

  testWidgets('does not show catalog products without the API', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: BuildTab()));
    await tester.tap(find.text('Chọn GPU'));
    await tester.pumpAndSettle();
    expect(find.text('Chọn GPU'), findsOneWidget);
    expect(find.text('ASUS Dual GeForce RTX 4060 OC 8GB'), findsNothing);
  });

  testWidgets('validates login and opens the demo home', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: LoginScreen()));
    await tester.tap(find.text('Đăng nhập'));
    await tester.pump();
    expect(
      find.text('Email hợp lệ và mật khẩu tối thiểu 8 ký tự là bắt buộc.'),
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

  testWidgets('main screens fit a compact phone viewport', (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(320, 568);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final screens = <Widget>[
      const WelcomeScreen(),
      const LoginScreen(),
      const SignupScreen(),
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
      final exception = tester.takeException();
      expect(exception, isNull, reason: '${screen.runtimeType}');
    }
  });

  testWidgets('new build stays blank and rejects an empty save', (
    tester,
  ) async {
    ApiClient.instance.logout();
    await tester.pumpWidget(
      const MaterialApp(home: BuildTab(loadLatest: false)),
    );
    await tester.pumpAndSettle();

    expect(find.text('Build mới'), findsOneWidget);
    expect(find.textContaining('0/8 linh kiện'), findsOneWidget);
    expect(find.byType(PCAssemblyPreview), findsOneWidget);
    expect(find.byTooltip('Xóa cấu hình'), findsNothing);

    await tester.tap(find.text('Lưu'));
    await tester.pumpAndSettle();
    expect(
      find.text('Hãy chọn ít nhất một linh kiện trước khi lưu.'),
      findsOneWidget,
    );
    expect(find.text('Đã lưu đầy đủ cấu hình lên tài khoản.'), findsNothing);
  });

  testWidgets('market changes accepts numeric strings from the API', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: MarketChangesScreen(
          areaName: 'TP. Hồ Chí Minh',
          items: [
            {
              'name': 'Montech Air 100',
              'price': '1190000',
              'previousPrice': '1168580',
              'trend': 1.83,
            },
          ],
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.textContaining('1.83%'), findsOneWidget);
    expect(find.textContaining('1168580đ'), findsOneWidget);
    expect(find.textContaining('1190000đ'), findsOneWidget);
  });

  testWidgets('compatibility report explains PSU watts in Vietnamese', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: CompatibilityScreen(
          report: {
            'status': 'warning',
            'score': 80,
            'selectedCount': 3,
            'estimatedPower': 235,
            'recommendedPsu': 600,
            'issues': [
              {
                'code': 'PSU',
                'severity': 'warning',
                'message': 'Nguồn 550W thiếu 50W so với mức tối thiểu 600W được hãng khuyến nghị.',
              },
            ],
            'criteria': [
              {
                'code': 'PSU',
                'status': 'warning',
                'detail': 'Nguồn 550W thiếu 50W so với đề nghị 600W.',
                'remediation': 'Chọn PSU từ 600W trở lên.',
              },
            ],
            'powerAssessment': {
              'estimatedLoadW': 235,
              'recommendedPsuW': 600,
              'manufacturerMinimumW': 600,
              'manufacturerGpuNames': ['RTX 3060'],
              'manufacturerSources': ['https://maker.example/gpu.pdf'],
              'selectedPsuW': 550,
              'selectedPsuName': 'Nguồn 550W',
              'marginW': -50,
              'method': 'Theo mức PSU hãng GPU trong SQL và dự phòng.',
            },
          },
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('ĐÁNH GIÁ BỘ NGUỒN'), findsOneWidget);
    expect(find.text('Công suất bộ nguồn'), findsWidgets);
    expect(find.text('CẢNH BÁO'), findsWidgets);
    expect(find.textContaining('thiếu 50W so với đề nghị'), findsOneWidget);
    expect(find.textContaining('PSU:'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('build progress accepts numeric strings from SQL models', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: BuildProgress(
            buildData: {
              'name': 'QA build',
              'completion': '50',
              'budget': '20000000',
              'totalPrice': '10000000',
              'components': {
                'CPU': {'id': 'cpu-7600'},
                'GPU': null,
              },
            },
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.textContaining('QA build • 50%'), findsOneWidget);
    expect(find.textContaining('10.000.000đ'), findsNWidgets(2));
    expect(find.textContaining('thiếu 1 linh kiện'), findsOneWidget);
  });

  testWidgets('chat suggestions fill the prompt without sending', (
    tester,
  ) async {
    ApiClient.instance.logout();
    await tester.pumpWidget(const MaterialApp(home: ChatTab()));
    final suggestion = find.text('GPU dưới 10 triệu');
    await tester.ensureVisible(suggestion);
    await tester.tap(suggestion);
    await tester.pumpAndSettle();

    final input = tester.widget<TextField>(find.byType(TextField));
    expect(input.controller?.text, 'GPU dưới 10 triệu');
  });

  testWidgets(
    'chat waits for the SQL conversation before saving the first message',
    (tester) async {
      final paths = <String>[];
      ApiClient.instance.logout();
      ApiClient.instance.token = 'test-token';
      ApiClient.instance.setClientFactoryForTesting(
        () => MockClient((request) async {
          paths.add(request.url.path);
          if (request.url.path == '/api/v1/conversations') {
            await Future<void>.delayed(const Duration(milliseconds: 30));
            return http.Response(
              jsonEncode({'id': 'conversation-sql'}),
              201,
              headers: {'content-type': 'application/json; charset=utf-8'},
            );
          }
          if (request.url.path ==
              '/api/v1/conversations/conversation-sql/messages') {
            return http.Response(
              jsonEncode({
                'choices': [
                  {
                    'message': {'content': 'Đã lưu vào SQL.'},
                  },
                ],
              }),
              200,
              headers: {'content-type': 'application/json; charset=utf-8'},
            );
          }
          return http.Response('{}', 404);
        }),
      );
      addTearDown(() {
        ApiClient.instance.setClientFactoryForTesting(() => http.Client());
        ApiClient.instance.logout();
      });

      await tester.pumpWidget(const MaterialApp(home: ChatTab()));
      await tester.enterText(find.byType(TextField), 'Kiểm tra socket CPU');
      await tester.tap(find.byIcon(Icons.arrow_forward));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 40));
      await tester.pumpAndSettle();

      expect(paths, [
        '/api/v1/conversations',
        '/api/v1/conversations/conversation-sql/messages',
      ]);
      expect(find.text('Đã lưu vào SQL.'), findsOneWidget);
    },
  );

  testWidgets('clear chat removes the current conversation from the view', (
    tester,
  ) async {
    ApiClient.instance.logout();
    await tester.pumpWidget(
      const MaterialApp(home: ChatTab(initialPrompt: 'Old scan result')),
    );
    expect(find.text('Old scan result'), findsOneWidget);

    await tester.tap(find.text('Xóa'));
    await tester.pumpAndSettle();

    expect(find.text('Old scan result'), findsNothing);
    expect(
      find.text('Chào bạn! Hãy hỏi về linh kiện, giá hoặc tương thích.'),
      findsOneWidget,
    );
  });

  testWidgets('chat shows a retry after the AI request times out', (
    tester,
  ) async {
    final pending = Completer<http.Response>();
    ApiClient.instance.logout();
    ApiClient.instance.setClientFactoryForTesting(
      () => MockClient((_) => pending.future),
    );
    addTearDown(() {
      ApiClient.instance.setClientFactoryForTesting(() => http.Client());
      ApiClient.instance.logout();
    });

    await tester.pumpWidget(
      const MaterialApp(
        home: ChatTab(responseTimeout: Duration(milliseconds: 30)),
      ),
    );
    await tester.enterText(find.byType(TextField), 'AM5');
    await tester.tap(find.byIcon(Icons.arrow_forward));
    await tester.pump();
    expect(find.text('Đang chờ BuildMate trả lời…'), findsOneWidget);

    await tester.pump(const Duration(milliseconds: 40));
    await tester.pumpAndSettle();
    expect(find.textContaining('TimeoutException'), findsOneWidget);
    expect(find.text('Thử lại'), findsOneWidget);
  });

  test('Build generation accepts a delayed API response', () async {
    ApiClient.instance.logout();
    ApiClient.instance.token = 'test-token';
    ApiClient.instance.setClientFactoryForTesting(
      () => MockClient((_) async {
        await Future<void>.delayed(const Duration(milliseconds: 30));
        return http.Response(
          jsonEncode({'name': 'Test Gaming PC'}),
          200,
          headers: {'content-type': 'application/json'},
        );
      }),
    );
    addTearDown(() {
      ApiClient.instance.setClientFactoryForTesting(() => http.Client());
      ApiClient.instance.logout();
    });

    final result = await ApiClient.instance.generateBuildSuggestion(
      budget: 20000000,
      purpose: 'Gaming',
      areaId: 'hcm',
      timeout: const Duration(seconds: 1),
    );

    expect(result['name'], 'Test Gaming PC');
  });

  testWidgets('scanner places long analysis below the photo without overflow', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(320, 568);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(
        home: ScannerScreen(initialAnalysis: 'Kết quả nhận diện. ' * 120),
      ),
    );
    await tester.pump();

    expect(
      tester.widget<ScannerScreen>(find.byType(ScannerScreen)).initialAnalysis,
      isNotNull,
    );
    expect(tester.takeException(), isNull);
    await tester.drag(find.byType(ListView).first, const Offset(0, -480));
    await tester.pumpAndSettle();
    expect(find.textContaining('Kết quả nhận diện.'), findsOneWidget);
    await tester.tap(find.text('Lịch sử'));
    await tester.pumpAndSettle();
    expect(find.text('Lịch sử quét đã lưu'), findsOneWidget);
  });
}
