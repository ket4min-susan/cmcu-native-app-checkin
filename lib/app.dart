import 'dart:async';

import 'package:app_links/app_links.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'core/models.dart';
import 'core/app_preferences.dart';
import 'core/app_brand.dart';
import 'core/portal_api.dart';
import 'core/session_store.dart';
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
  const AuthGate({
    super.key,
    this.initialSession,
    required this.preferences,
  });
  final Session? initialSession;
  final AppPreferences preferences;

  @override
  State<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<AuthGate> {
  Session? _session;
  ScheduleController? _controller;
  bool _creatingController = false;
  bool _checkInRequested = false;
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
      final ua = await WebSession.userAgent();
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
        onCurrentWeekLoaded: (week, entries) => WidgetBridge.publish(
          signedIn: true,
          weekStart: week,
          entries: entries,
        ),
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
    await SessionStore.save(s);
    if (!mounted) return;
    await _createController(s);
    await WidgetBridge.publish(signedIn: true);
  }

  Future<void> _onSessionExpired() async {
    await SessionStore.clear();
    if (!mounted) return;
    _controller?.api.close();
    _controller?.dispose();
    setState(() {
      _session = null;
      _controller = null;
    });
    await WidgetBridge.publish(signedIn: false);
  }

  Future<void> _onSignOut() async {
    await SessionStore.clear();
    await WidgetBridge.clear();
    await WebSession.clearAll();
    if (!mounted) return;
    _controller?.api.close();
    _controller?.dispose();
    setState(() {
      _session = null;
      _controller = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;
    if (_session == null) {
      return LoginScreen(onSignedIn: _onSignedIn);
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
