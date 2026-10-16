import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../core/app_preferences.dart';
import '../../theme/formatters.dart';
import '../../theme/motion.dart';
import '../../theme/campus_brand.dart';
import '../grades/grades_controller.dart';
import '../grades/grades_screen.dart';
import '../settings/preferences_sheet.dart';
import 'check_in_sheet.dart';
import 'schedule_content.dart';
import 'schedule_controller.dart';

class ScheduleScreen extends StatefulWidget {
  const ScheduleScreen({
    super.key,
    required this.controller,
    required this.preferences,
    required this.checkInRequested,
    required this.onCheckInRequestHandled,
    required this.onSignOut,
    required this.onSessionExpired,
  });
  final ScheduleController controller;
  final bool checkInRequested;
  final VoidCallback onCheckInRequestHandled, onSignOut, onSessionExpired;
  final AppPreferences preferences;
  @override
  State<ScheduleScreen> createState() => _ScheduleScreenState();
}

class _ScheduleScreenState extends State<ScheduleScreen>
    with WidgetsBindingObserver, SingleTickerProviderStateMixin {
  bool _sheetOpen = false;
  bool _expiredHandled = false;
  bool _gradesVisited = false;
  int _tab = 0;
  late GradesController _grades;
  AppPreferences get preferences => widget.preferences;
  late final AnimationController _transition = AnimationController(
    vsync: this,
    value: 1,
  );
  late final Animation<double> _fade = CurvedAnimation(
    parent: _transition,
    curve: Curves.easeOutCubic,
  );
  Timer? _minuteTimer;
  ScheduleController get c => widget.controller;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _grades = GradesController(c.api);
    c.addListener(_onChange);
    _minuteTimer = Timer.periodic(const Duration(minutes: 1), (_) {
      if (mounted &&
          WidgetsBinding.instance.lifecycleState != AppLifecycleState.paused)
        c.refreshTime();
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _handleRequest();
    });
  }

  @override
  void didUpdateWidget(covariant ScheduleScreen old) {
    super.didUpdateWidget(old);
    if (old.controller != c) {
      old.controller.removeListener(_onChange);
      c.addListener(_onChange);
      _grades.dispose();
      _grades = GradesController(c.api);
      _gradesVisited = false;
      _tab = 0;
      _expiredHandled = false;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _handleRequest();
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _minuteTimer?.cancel();
    c.removeListener(_onChange);
    _grades.dispose();
    _transition.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) c.refreshTime();
  }

  void _selectTab(int value) {
    if (_tab == value) return;
    FocusManager.instance.primaryFocus?.unfocus();
    HapticFeedback.selectionClick();
    setState(() {
      _tab = value;
      if (value == 1) _gradesVisited = true;
    });
    if (MediaQuery.disableAnimationsOf(context) || preferences.reduceMotion) {
      _transition.value = 1;
    } else {
      _transition.duration = motionDuration(context);
      _transition.forward(from: 0);
    }
    if (value == 0)
      WidgetsBinding.instance.addPostFrameCallback((_) => _syncSheet());
  }

  void _handleRequest() {
    if (!widget.checkInRequested) return;
    _selectTab(0);
    c.checkInNow();
    widget.onCheckInRequestHandled();
  }

  void _onChange() {
    if (!mounted) return;
    if (c.sessionExpired && !_expiredHandled) {
      _expiredHandled = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) widget.onSessionExpired();
      });
    }
    final notice = c.notice;
    if (notice != null) {
      c.noticeShown();
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(SnackBar(content: Text(notice)));
      });
    }
    WidgetsBinding.instance.addPostFrameCallback((_) => _syncSheet());
  }

  void _syncSheet() {
    if (!mounted) return;
    if (c.checkIn != null && !_sheetOpen && _tab == 0) {
      _sheetOpen = true;
      showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        useSafeArea: true,
        showDragHandle: true,
        builder: (_) => CheckInSheet(controller: c),
      ).whenComplete(() {
        _sheetOpen = false;
        if (mounted) c.dismissCheckIn();
      });
    } else if (c.checkIn == null && _sheetOpen) {
      Navigator.of(context).maybePop();
    }
  }

  void _settings() => showModalBottomSheet<void>(
    context: context,
    useSafeArea: true,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) =>
        PreferencesSheet(preferences: preferences, onSignOut: widget.onSignOut),
  );

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: Listenable.merge([c, preferences]),
    builder: (context, _) {
      final s = Theme.of(context).colorScheme;
      return Scaffold(
        appBar: AppBar(
          toolbarHeight: 24 + MediaQuery.textScalerOf(context).scale(44),
          title: CampusWordmark(
            subtitle: _tab == 0
                ? weekLabel(c.weekStart)
                : 'Hồ sơ học tập cá nhân',
          ),
          actions: [
            if (_tab == 0)
              IconButton(
                onPressed: c.goToToday,
                tooltip: 'Hôm nay',
                icon: const Icon(Icons.today_outlined),
              ),
            IconButton(
              onPressed: _settings,
              tooltip: 'Tùy chỉnh',
              icon: const Icon(Icons.tune_rounded),
            ),
            const SizedBox(width: 6),
          ],
        ),
        bottomNavigationBar: SafeArea(
          top: false,
          minimum: const EdgeInsets.fromLTRB(16, 8, 16, 12),
          child: Container(
            clipBehavior: Clip.antiAlias,
            decoration: BoxDecoration(
              color: s.surface,
              borderRadius: BorderRadius.circular(24),
              border: Border.all(
                color: s.outlineVariant.withValues(alpha: .45),
              ),
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFF062A3D).withValues(alpha: .10),
                  blurRadius: 24,
                  offset: const Offset(0, 5),
                ),
              ],
            ),
            child: NavigationBar(
              selectedIndex: _tab,
              onDestinationSelected: _selectTab,
              destinations: const [
                NavigationDestination(
                  icon: Icon(Icons.calendar_month_outlined),
                  selectedIcon: Icon(Icons.calendar_month_rounded),
                  label: 'Lịch học',
                ),
                NavigationDestination(
                  icon: Icon(Icons.school_outlined),
                  selectedIcon: Icon(Icons.school_rounded),
                  label: 'Kết quả',
                ),
              ],
            ),
          ),
        ),
        body: SafeArea(
          top: false,
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 960),
              child: FadeTransition(
                opacity: _fade,
                child: SlideTransition(
                  position: Tween<Offset>(
                    begin: const Offset(0, .015),
                    end: Offset.zero,
                  ).animate(_fade),
                  child: IndexedStack(
                    index: _tab,
                    children: [
                      TickerMode(
                        enabled: _tab == 0,
                        child: ScheduleContent(
                          controller: c,
                          compact: preferences.compactSchedule,
                        ),
                      ),
                      if (_gradesVisited)
                        TickerMode(
                          enabled: _tab == 1,
                          child: GradesScreen(
                            controller: _grades,
                            onSessionExpired: widget.onSessionExpired,
                          ),
                        )
                      else
                        const SizedBox.shrink(),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      );
    },
  );
}
