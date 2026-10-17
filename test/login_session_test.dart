import 'dart:async';
import 'dart:convert';

import 'package:cmc_checkin/app.dart';
import 'package:cmc_checkin/core/app_preferences.dart';
import 'package:cmc_checkin/core/models.dart';
import 'package:cmc_checkin/features/login/login_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'academic_fixture.dart';

class _LoginPlatform extends InAppWebViewPlatform {
  int webViews = 0;
  String token = 'synthetic-login-token';
  final cleared = <String>[];
  Completer<void>? cleanup;

  @override
  PlatformCookieManager createPlatformCookieManager(
    PlatformCookieManagerCreationParams params,
  ) => _LoginCookies(params, this);

  @override
  PlatformWebStorageManager createPlatformWebStorageManager(
    PlatformWebStorageManagerCreationParams params,
  ) => _LoginStorage(params, this);

  @override
  PlatformInAppWebViewController createPlatformInAppWebViewControllerStatic() =>
      _LoginController(this);

  @override
  PlatformInAppWebViewWidget createPlatformInAppWebViewWidget(
    PlatformInAppWebViewWidgetCreationParams params,
  ) {
    webViews++;
    return _LoginWebView(params, this);
  }
}

class _LoginCookies extends PlatformCookieManager {
  _LoginCookies(super.params, this.owner) : super.implementation();
  final _LoginPlatform owner;

  @override
  Future<List<Cookie>> getCookies({
    required WebUri url,
    PlatformInAppWebViewController? iosBelow11WebViewController,
    PlatformInAppWebViewController? webViewController,
  }) async => [];

  @override
  Future<bool> deleteAllCookies() async {
    owner.cleared.add('cookies');
    await owner.cleanup?.future;
    return true;
  }
}

class _LoginStorage extends PlatformWebStorageManager {
  _LoginStorage(super.params, this.owner) : super.implementation();
  final _LoginPlatform owner;

  @override
  Future<void> deleteAllData() async => owner.cleared.add('storage');
}

class _LoginWebView extends PlatformInAppWebViewWidget {
  _LoginWebView(super.params, this.owner) : super.implementation();
  final _LoginPlatform owner;
  bool _created = false;

  @override
  Widget build(BuildContext context) {
    if (!_created) {
      _created = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        params.onWebViewCreated?.call(
          controllerFromPlatform<InAppWebViewController>(
            _LoginController(owner),
          ),
        );
      });
    }
    return const SizedBox.expand();
  }

  @override
  T controllerFromPlatform<T>(PlatformInAppWebViewController controller) =>
      InAppWebViewController.fromPlatform(platform: controller) as T;

  @override
  void dispose() {}
}

class _LoginController extends PlatformInAppWebViewController {
  _LoginController(this.owner)
    : super.implementation(
        const PlatformInAppWebViewControllerCreationParams(id: 'login-test'),
      );
  final _LoginPlatform owner;

  @override
  Future<String> getDefaultUserAgent() async => 'synthetic-default-agent';

  @override
  Future<void> clearAllCache({bool includeDiskFiles = true}) async =>
      owner.cleared.add('cache');

  @override
  Future<WebUri?> getUrl() async =>
      WebUri('https://iu.cmcu.edu.vn/congthongtin/Index.aspx');

  @override
  Future<dynamic> evaluateJavascript({
    required String source,
    ContentWorld? contentWorld,
  }) async {
    expect(source, contains('navigator.userAgent'));
    return jsonEncode({
      'token': owner.token,
      'userId': 'synthetic-student',
      'chucNangId': 'schedule-menu',
      'menuLoaded': true,
      'userAgent': 'synthetic-login-user-agent',
    });
  }
}

void main() {
  late _LoginPlatform platform;
  setUp(() {
    platform = _LoginPlatform();
    InAppWebViewPlatform.instance = platform;
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(
      const MethodChannel('com.llfbandit.app_links/messages'),
      (_) async => null,
    );
    messenger.setMockMethodCallHandler(
      const MethodChannel('com.llfbandit.app_links/events'),
      (_) async => null,
    );
    messenger.setMockMethodCallHandler(
      const MethodChannel('plugins.it_nomads.com/flutter_secure_storage'),
      (_) async => null,
    );
    messenger.setMockMethodCallHandler(
      const MethodChannel('home_widget'),
      (_) async => true,
    );
  });

  Future<void> unmount(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
  }

  testWidgets(
    'AuthGate waits for cleanup and stops after two rejected sessions',
    (tester) async {
      final preferences = AppPreferences();
      addTearDown(preferences.dispose);
      var requests = 0;
      final client = MockClient((_) async {
        requests++;
        return http.Response('', 401);
      });
      addTearDown(client.close);
      await http.runWithClient(() async {
        final gate = AuthGate(
          initialSession: testSession,
          preferences: preferences,
        );
        platform.cleanup = Completer<void>();
        await tester.pumpWidget(MaterialApp(home: gate));
        for (var i = 0; i < 8; i++) {
          await tester.pump();
        }
        expect(requests, 1);
        expect(platform.webViews, 0);
        expect(
          find.text('Đang xóa dữ liệu phiên đăng nhập cũ…'),
          findsOneWidget,
        );
        expect(platform.cleared, containsAll(['cookies', 'cache', 'storage']));
        platform.cleanup!.complete();
        await tester.pump();
        await tester.pump();
        expect(platform.webViews, 1);
        // WebView cấp token khác nhưng API vẫn từ chối: chỉ một lần phục hồi tự động.
        await tester.pump(const Duration(milliseconds: 700));
        for (var i = 0; i < 8; i++) {
          await tester.pump();
        }
        expect(requests, 2);
        expect(
          find.text('Không thể khôi phục phiên đăng nhập'),
          findsOneWidget,
        );
        expect(find.byType(InAppWebView), findsNothing);
        await tester.pump(const Duration(seconds: 5));
        expect(requests, 2);
        final oldWebViews = platform.webViews;
        await tester.tap(find.text('Đăng nhập lại'));
        for (var i = 0; i < 8; i++) {
          await tester.pump();
        }
        expect(platform.webViews, oldWebViews + 1);
        expect(find.byType(InAppWebView), findsOneWidget);
        expect(requests, 2); // Bấm thử lại chỉ mở login, chưa tự gọi API.
        await unmount(tester);
        await tester.pump();
      }, () => client);
    },
  );

  testWidgets(
    'Does not create a WebView while old session data is being cleared',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: LoginScreen(
            resetting: true,
            onSignedIn: (_) => fail('Must not sign in during cleanup'),
          ),
        ),
      );
      await tester.pump(const Duration(seconds: 3));
      expect(platform.webViews, 0);
      expect(find.text('Đang xóa dữ liệu phiên đăng nhập cũ…'), findsOneWidget);
      await unmount(tester);
    },
  );

  testWidgets(
    'Blocked recovery does not create WebView or retry without user action',
    (tester) async {
      var retries = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: LoginScreen(
            blocked: true,
            sessionNotice: 'HTTP 401: synthetic test error',
            onRetrySession: () => retries++,
            onSignedIn: (_) => fail('Must not auto sign in after repeated 401'),
          ),
        ),
      );
      await tester.pump(const Duration(seconds: 3));
      expect(platform.webViews, 0);
      expect(retries, 0);
      expect(find.text('HTTP 401: synthetic test error'), findsOneWidget);
      await tester.tap(find.text('Đăng nhập lại'));
      expect(retries, 1);
      await unmount(tester);
    },
  );

  testWidgets(
    'Stale token returned by Index.aspx stops probing and never signs in',
    (tester) async {
      var accepted = 0;
      var retries = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: LoginScreen(
            onSignedIn: (_) => fail('Rejected token must not reach API'),
            acceptToken: (_) {
              accepted++;
              return false;
            },
            onRetrySession: () => retries++,
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 700));
      await tester.pump();
      expect(accepted, 1);
      expect(find.byType(InAppWebView), findsNothing);
      expect(find.textContaining('phiên cũ đã bị từ chối'), findsOneWidget);
      await tester.pump(const Duration(seconds: 3));
      expect(accepted, 1);
      await tester.tap(find.text('Đăng nhập lại'));
      expect(retries, 1);
      await unmount(tester);
    },
  );

  testWidgets(
    'Captures actual login UA before publishing session; publishes only once',
    (tester) async {
      final events = <String>[];
      Session? session;
      await tester.pumpWidget(
        MaterialApp(
          home: LoginScreen(
            acceptToken: (_) => true,
            onUserAgentCaptured: (ua) async => events.add(ua),
            onSignedIn: (value) {
              session = value;
              events.add('signed-in');
            },
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 700));
      await tester.pump();
      expect(events, ['synthetic-login-user-agent', 'signed-in']);
      expect(session!.token, platform.token);
      expect(session!.chucNangId, 'schedule-menu');
      await tester.pump(const Duration(seconds: 3));
      expect(events, hasLength(2));
      await unmount(tester);
    },
  );

  testWidgets('Blocked screen remains usable at 320px with 200% text', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: const TextScaler.linear(2)),
          child: child!,
        ),
        home: LoginScreen(
          blocked: true,
          sessionNotice:
              'Cổng sinh viên vẫn trả HTTP 401 sau khi đăng nhập lại. '
              'Đã dừng tự đăng nhập. Vui lòng thử lại sau.',
          onSignedIn: (_) {},
          onRetrySession: () {},
        ),
      ),
    );
    expect(tester.takeException(), isNull);
    await tester.ensureVisible(find.text('Đăng nhập lại'));
    await tester.tap(find.text('Đăng nhập lại'));
    await unmount(tester);
  });
}
