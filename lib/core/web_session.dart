import 'package:flutter/foundation.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';

class WebSession {
  WebSession._();
  static String? _ua;

  /// UA mặc định của WebView (cùng UA dùng lúc đăng nhập).
  static Future<String> userAgent() async {
    if (_ua != null) return _ua!;
    try {
      _ua = await InAppWebViewController.getDefaultUserAgent();
    } catch (_) {}
    return _ua ??=
        'Mozilla/5.0 (Linux; Android 14) AppleWebKit/537.36 '
        '(KHTML, like Gecko) Chrome/120.0 Mobile Safari/537.36';
  }

  /// Ưu tiên UA thực sự của trang đăng nhập thay vì đoán từ UA mặc định.
  static Future<void> rememberUserAgent(String value) async {
    if (value.trim().isNotEmpty) _ua = value;
  }

  /// Header `Cookie` từ store của WebView (gồm cả cookie HttpOnly) cho [url].
  static Future<String?> cookieHeader(Uri url) async {
    final cookies = await CookieManager.instance().getCookies(
      url: WebUri.uri(url),
    );
    if (cookies.isEmpty) return null;
    return cookies.map((c) => '${c.name}=${c.value}').join('; ');
  }

  /// Xóa cookie/cache/storage trước khi tạo WebView cho phiên mới.
  static Future<void> clearAll() async {
    _ua = null;
    await Future.wait([
      Future<void>.sync(() async {
        // Android trả false cả khi store đã rỗng; không coi đó là lỗi.
        await CookieManager.instance().deleteAllCookies();
      }),
      Future<void>.sync(() async {
        await InAppWebViewController.clearAllCache();
      }),
      Future<void>.sync(() async {
        final storage = WebStorageManager.instance();
        if (defaultTargetPlatform == TargetPlatform.iOS ||
            defaultTargetPlatform == TargetPlatform.macOS) {
          // deleteAllData chỉ dành cho Android; iOS cần WKWebsiteDataStore.
          await storage.removeDataModifiedSince(
            dataTypes: WebsiteDataType.ALL,
            date: DateTime.fromMillisecondsSinceEpoch(0),
          );
        } else {
          await storage.deleteAllData();
        }
      }),
    ]);
  }
}
