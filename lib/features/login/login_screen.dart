import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/models.dart';
import '../../theme/campus_brand.dart';
import '../../core/portal_api.dart' show portalOrigin;

const _loginUrl = '$portalOrigin/congthongtin/login.aspx';
const _probeInterval = Duration(milliseconds: 700);
const _menuWaitProbes = 15;

const _probeJs = r'''
(function () {
  try {
    var s = (typeof edu !== 'undefined' && edu) ? edu.system : null;
    if (!s || !s.tokenJWT || !s.userId) return null;
    var list = s.dtChucNang || [], match = null, grades = null;
    for (var i = 0; i < list.length; i++) {
      var file = String(list[i].DUONGDANFILE || '').toLowerCase();
      var name = String(list[i].TENCHUCNANG || '').toLowerCase();
      if (file.indexOf('lichgiang') >= 0 || file.indexOf('lichhoc') >= 0 || name.indexOf('lịch cá nhân') >= 0) match = list[i].ID;
      if (file.indexOf('diemhoc') >= 0 || name.indexOf('điểm học') >= 0 || name.indexOf('kết quả học tập') >= 0) grades = list[i].ID;
    }
    return JSON.stringify({
      token: s.tokenJWT, userId: s.userId, clientIP: s.clientIP || '',
      chucNangId: match == null ? null : String(match),
      gradesChucNangId: grades == null ? '' : String(grades),
      currentChucNangId: s.strChucNang_Id || '', menuLoaded: list.length > 0
    });
  } catch (e) { return null; }
})();
''';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key, required this.onSignedIn});
  final void Function(Session session) onSignedIn;

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  InAppWebViewController? _web;
  double _progress = 0;
  bool _canGoBack = false;
  Timer? _timer;
  bool _done = false;
  bool _probing = false;
  bool _menuError = false;
  int _probesWithToken = 0;

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _startProbe() {
    _timer?.cancel();
    _menuError = false;
    _timer = Timer.periodic(_probeInterval, (_) => _probe());
  }

  void _retry() {
    _probesWithToken = 0;
    _startProbe();
    _web?.reload();
  }

  Future<void> _probe() async {
    final web = _web;
    if (_done || _probing || web == null || !mounted) return;
    _probing = true;
    try {
      final uri = await web.getUrl();
      if (uri?.host != 'iu.cmcu.edu.vn' || uri?.scheme != 'https') return;
      final raw = await web.evaluateJavascript(source: _probeJs);
      if (raw is! String || _done) return;
      final obj = jsonDecode(raw) as Map<String, dynamic>;
      final token = obj['token'] as String?;
      final userId = obj['userId'] as String?;
      if (token == null || token.isEmpty || userId == null || userId.isEmpty)
        return;
      final chucNangId = obj['chucNangId'] as String?;
      final menuLoaded = obj['menuLoaded'] == true;
      final gradesId = obj['gradesChucNangId'] as String? ?? '';
      final scheduleId =
          chucNangId ?? (obj['currentChucNangId'] as String? ?? '');
      final menuReady = menuLoaded && chucNangId != null;
      final timedOut = _probesWithToken >= _menuWaitProbes;
      if (menuReady || (timedOut && scheduleId.isNotEmpty)) {
        _done = true;
        _timer?.cancel();
        widget.onSignedIn(
          Session(
            token: token,
            userId: userId,
            chucNangId: scheduleId,
            portalIp: obj['clientIP'] as String? ?? '',
            // Tài khoản không có mục Điểm học vẫn dùng được lịch; tab Kết quả
            // tự báo lỗi khi `gradesChucNangId` rỗng.
            gradesChucNangId: gradesId,
          ),
        );
      } else if (timedOut) {
        _timer?.cancel();
        setState(() => _menuError = true);
      } else {
        _probesWithToken++;
      }
    } catch (_) {
      // Trang đang chuyển hướng / chưa có `edu` → thử lại ở nhịp sau.
    } finally {
      _probing = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: !_canGoBack,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && _canGoBack) _web?.goBack();
      },
      child: Scaffold(
        appBar: AppBar(
          toolbarHeight: 24 + MediaQuery.textScalerOf(context).scale(44),
          title: const CampusWordmark(subtitle: 'Đăng nhập tài khoản trường'),
          bottom: _progress < 1
              ? PreferredSize(
                  preferredSize: const Size.fromHeight(3),
                  child: LinearProgressIndicator(
                    value: _progress,
                    minHeight: 3,
                  ),
                )
              : null,
        ),
        body: Stack(
          children: [
            InAppWebView(
              initialUrlRequest: URLRequest(url: WebUri(_loginUrl)),
              initialSettings: InAppWebViewSettings(
                javaScriptEnabled: true,
                domStorageEnabled: true,
                thirdPartyCookiesEnabled: true,
                javaScriptCanOpenWindowsAutomatically: true,
                supportMultipleWindows: false,
                allowsBackForwardNavigationGestures: true,
                useShouldOverrideUrlLoading: true,
              ),
              onWebViewCreated: (c) {
                _web = c;
                _startProbe();
              },
              onProgressChanged: (_, p) => setState(() => _progress = p / 100),
              onUpdateVisitedHistory: (c, _, __) async {
                final can = await c.canGoBack();
                if (mounted && can != _canGoBack)
                  setState(() => _canGoBack = can);
              },
              shouldOverrideUrlLoading: (c, action) async {
                final uri = action.request.url;
                final scheme = uri?.scheme.toLowerCase();
                if (uri == null ||
                    const {
                      'http',
                      'https',
                      'about',
                      'data',
                      'blob',
                    }.contains(scheme)) {
                  return NavigationActionPolicy.ALLOW;
                }
                try {
                  await launchUrl(
                    Uri.parse(uri.toString()),
                    mode: LaunchMode.externalApplication,
                  );
                } catch (_) {}
                return NavigationActionPolicy.CANCEL;
              },
            ),
            if (_menuError) _menuErrorBanner(context),
          ],
        ),
      ),
    );
  }

  Widget _menuErrorBanner(BuildContext context) {
    final s = Theme.of(context).colorScheme;
    return Align(
      alignment: Alignment.bottomCenter,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Material(
          color: s.errorContainer,
          borderRadius: BorderRadius.circular(20),
          clipBehavior: Clip.antiAlias,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(18, 14, 10, 14),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    'Không đọc được mục “Lịch cá nhân” của tài khoản này. '
                    'Kiểm tra lại quyền truy cập rồi thử lại.',
                    style: TextStyle(color: s.onErrorContainer),
                  ),
                ),
                const SizedBox(width: 8),
                TextButton(onPressed: _retry, child: const Text('Thử lại')),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
