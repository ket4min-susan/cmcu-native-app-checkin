import 'dart:async';

import 'package:app_links/app_links.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'core/models.dart';
import 'core/app_preferences.dart';
import 'core/app_brand.dart';
import 'core/portal_api.dart';
import 'core/session_store.dart';
import 'core/session_recovery.dart';
import 'core/web_session.dart';
import 'core/widget_bridge.dart';
import 'features/login/login_screen.dart';
import 'features/schedule/schedule_controller.dart';
import 'features/schedule/schedule_screen.dart';
import 'theme/app_theme.dart';

class CmcCheckinApp extends StatelessWidget {
  const CmcCheckinApp({
    super.key,
    this.initialSession,
    required this.preferences,
  });
  final Session? initialSession;
  final AppPreferences preferences;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: preferences,
      builder: (context, _) => MaterialApp(
        title: AppBrand.name,
        debugShowCheckedModeBanner: false,
        locale: const Locale('vi'),
        supportedLocales: const [Locale('vi')],
        localizationsDelegates: GlobalMaterialLocalizations.delegates,
        theme: buildTheme(Brightness.light),
        darkTheme: buildTheme(Brightness.dark),
        themeMode: preferences.themeMode,
        themeAnimationDuration: preferences.reduceMotion
            ? Duration.zero
            : const Duration(milliseconds: 240),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(
            disableAnimations:
                preferences.reduceMotion ||
                MediaQuery.disableAnimationsOf(context),
          ),
          child: child!,
        ),
        home: AuthGate(
          initialSession: initialSession,
          preferences: preferences,
        ),
      ),
    );
  }
}

class AuthGate extends StatefulWidget {
  const AuthGate({super.key, this.initialSession, required this.preferences});
  final Session? initialSession;
  final AppPreferences preferences;

  @override
  State<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<AuthGate> {
  Session? _session;
  ScheduleController? _controller;
  bool _creatingController = false;
  bool _resettingSession = false;
  bool _checkInRequested = false;
  int _loginGeneration = 0;
  final _recovery = SessionRecovery();
  StreamSubscription<Uri>? _links;

  @override
  void initState() {
    super.initState();
    _session = widget.initialSession;
    if (_session != null) _createController(_session!);
    _listenDeepLinks();
  }

  @override
  void dispose() {
    _links?.cancel();
    _controller?.api.close();
    _controller?.dispose();
    super.dispose();
  }

  Future<void> _listenDeepLinks() async {
    final links = AppLinks();
    final initial = await links.getInitialLink();
    if (!mounted) return;
    if (initial != null) _handle(initial);
    _links = links.uriLinkStream.listen(_handle);
  }

  void _handle(Uri uri) {
    if (!mounted) return;
    if (uri.scheme == 'cmccheckin' && uri.host == 'checkin') {
      setState(() => _checkInRequested = true);
    }
  }

  /// Tạo controller rồi mới công bố [s] trong cùng một `setState`, nên không có
  /// frame nào vừa có phiên vừa chưa có controller (không nhấp nháy spinner).
  Future<void> _createController(Session s) async {
    if (_creatingController) return;
    _creatingController = true;
    try {
      final generation = _loginGeneration;
      final ua = await WebSession.userAgent();
      if (_resettingSession || generation != _loginGeneration) return;
      final existing = _controller;
      if (existing != null && identical(existing.api.session, s)) return;
      if (!mounted) return;
      final api = PortalApi(
        session: s,
        userAgent: ua,
        cookieHeader: WebSession.cookieHeader,
      );
      final controller = ScheduleController(
        api: api,
        fallbackIp: s.portalIp,
        onCurrentWeekLoaded: (week, entries) {
          _recovery.confirmAuthenticated();
          WidgetBridge.publish(
            signedIn: true,
            weekStart: week,
            entries: entries,
          );
        },
      );
      final old = _controller;
      setState(() {
        _session = s;
        _controller = controller;
      });
      old?.dispose();
      old?.api.close();
    } finally {
      _creatingController = false;
    }
  }

  Future<void> _onSignedIn(Session s) async {
    if (_resettingSession || !_recovery.acceptToken(s.token)) return;
    final generation = _loginGeneration;
    await SessionStore.save(s);
    if (!mounted || _resettingSession || generation != _loginGeneration) return;
    await _createController(s);
    if (mounted && identical(_session, s) && !_resettingSession) {
      await WidgetBridge.publish(signedIn: true);
    }
  }

  Future<void> _onSessionExpired() async {
    final session = _session;
    if (session == null || _resettingSession) return;
    await _resetSession(() => _recovery.expire(session));
  }

  Future<void> _onSignOut() => _resetSession(_recovery.retry);

  Future<void> _resetSession(Future<void> Function() reset) async {
    if (_resettingSession || !mounted) return;
    final old = _controller;
    setState(() {
      _resettingSession = true;
      _loginGeneration++;
      _session = null;
      _controller = null;
      _checkInRequested = false;
    });
    // Chặn kết quả request đang chạy trước khi dọn session/cookie.
    old?.dispose();
    old?.api.close();
    try {
      await reset();
    } finally {
      if (mounted) setState(() => _resettingSession = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;
    if (_session == null) {
      return LoginScreen(
        key: ValueKey(_loginGeneration),
        onSignedIn: _onSignedIn,
        onUserAgentCaptured: WebSession.rememberUserAgent,
        acceptToken: _recovery.acceptToken,
        resetting: _resettingSession,
        blocked: _recovery.blocked,
        sessionNotice: _recovery.notice,
        onRetrySession: _onSignOut,
      );
    }
    if (controller == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    return ScheduleScreen(
      key: ValueKey(_session!.token),
      controller: controller,
      preferences: widget.preferences,
      checkInRequested: _checkInRequested,
      onCheckInRequestHandled: () => setState(() => _checkInRequested = false),
      onSignOut: _onSignOut,
      onSessionExpired: _onSessionExpired,
    );
  }
}
