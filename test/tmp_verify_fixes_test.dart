import 'package:cmc_checkin/core/app_preferences.dart';
import 'package:cmc_checkin/core/models.dart';
import 'package:cmc_checkin/core/portal_api.dart';
import 'package:cmc_checkin/features/schedule/schedule_controller.dart';
import 'package:cmc_checkin/features/schedule/schedule_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

class _StubApi extends PortalApi {
  _StubApi()
    : super(
        session: const Session(
          token: 't',
          userId: 'u',
          chucNangId: 'cn',
          portalIp: '10.0.0.1',
        ),
        userAgent: 'test',
        cookieHeader: (_) async => null,
      );
  @override
  Future<List<ScheduleEntry>> weekSchedule(DateTime from, DateTime to) async {
    await Future<void>.delayed(const Duration(milliseconds: 5));
    return const [];
  }
}

void main() {
  testWidgets('ScheduleController does not emit a spinner frame while '
      'the first load is still in flight', (tester) async {
    final api = _StubApi();
    final controller = ScheduleController(api: api, fallbackIp: '10.0.0.1');
    var spinners = 0;
    void listener() {
      if (controller.loading && controller.entries.isEmpty) spinners++;
    }

    controller.addListener(listener);
    await Future<void>.delayed(const Duration(milliseconds: 20));
    controller.removeListener(listener);
    controller.dispose();
    api.close();
    expect(
      spinners,
      0,
      reason: 'không được báo "đang tải" khi chưa từng vẽ bảng rỗng',
    );
  });

  testWidgets('Placeholder spinner is gone by the first frame after app '
      'start once sign-in resolves', (tester) async {
    final preferences = AppPreferences();
    addTearDown(preferences.dispose);
    final api = _StubApi();
    final controller = ScheduleController(api: api, fallbackIp: '10.0.0.1');
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('vi'),
        supportedLocales: const [Locale('vi')],
        localizationsDelegates: GlobalMaterialLocalizations.delegates,
        home: ScheduleScreen(
          controller: controller,
          preferences: preferences,
          checkInRequested: false,
          onCheckInRequestHandled: () {},
          onSignOut: () {},
          onSessionExpired: () {},
        ),
      ),
    );
    expect(find.byType(CircularProgressIndicator), findsNothing);
    controller.dispose();
    api.close();
  });
}
