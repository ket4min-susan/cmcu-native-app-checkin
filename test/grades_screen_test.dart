import 'dart:io';
import 'dart:ui' as ui;
import 'package:cmc_checkin/core/academic_models.dart';
import 'package:cmc_checkin/core/app_brand.dart';
import 'package:cmc_checkin/core/models.dart';
import 'package:cmc_checkin/core/portal_api.dart';
import 'package:cmc_checkin/features/schedule/schedule_controller.dart';
import 'package:cmc_checkin/features/schedule/schedule_screen.dart';
import 'package:cmc_checkin/features/schedule/entry_card.dart';
import 'package:cmc_checkin/features/schedule/check_in_sheet.dart';
import 'package:cmc_checkin/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'academic_fixture.dart';

class ScreenApi extends PortalApi {
  ScreenApi()
    : super(
        session: testSession,
        userAgent: 'test',
        cookieHeader: (_) async => null,
      );
  int detailsRequests = 0;
  @override
  Future<List<ScheduleEntry>> weekSchedule(DateTime from, DateTime to) async =>
      parseSchedule([
        {
          'ID': 'lesson-synthetic',
          'IDLOPHOCPHAN': 'mobile-class',
          'TENHOCPHAN': 'Lập trình di động',
          'NGAYHOC': '15/10/2026',
          'GIOBATDAU': 7,
          'GIOKETTHUC': 9,
          'TENPHONGHOC': '301',
          'GIANGVIEN': 'Giảng viên bộ môn',
          'TENLOPHOCPHAN': 'Mobile-01<br>Có mặt<br>',
          'THONGTINCHUYENCAN': 'Có mặt(3)',
          'TIETBATDAU': 1,
          'TIETKETTHUC': 3,
        },
        {
          'ID': 'exam-synthetic',
          'TENHOCPHAN': 'Mạng máy tính',
          'PHANLOAI': 'LICHTHI',
          'NGAYHOC': '15/10/2026',
          'GIOBATDAU': 13,
          'GIOKETTHUC': 15,
          'TENPHONGHOC': '402',
        },
      ]);
  @override
  Future<List<StudyProgram>> studyPrograms() async => const [
    StudyProgram('a', 'Công nghệ thông tin'),
  ];
  @override
  Future<AcademicRecord> academicRecord(String programId) async =>
      AcademicRecord.parse(academicFixture());
  @override
  Future<List<GradeComponent>> gradeComponents(String resultId) async {
    detailsRequests++;
    return [
      GradeComponent({
        'DIEM_THANHPHANDIEM_TEN': 'Chuyên cần',
        'DIEM': 10,
        'LANHOC': 1,
        'LANTHI': 1,
      }),
    ];
  }
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));
  const previewKey = ValueKey('preview');
  setUpAll(() async {
    final icons = FontLoader('MaterialIcons')
      ..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'));
    await icons.load();
    final path = Platform.environment['CMC_PREVIEW_FONT'];
    if (path != null) {
      final loader = FontLoader('Roboto')
        ..addFont(File(path).readAsBytes().then(ByteData.sublistView));
      await loader.load();
    }
  });

  Future<void> capture(WidgetTester tester, String name) async {
    final directory = Platform.environment['CMC_PREVIEW_DIR'];
    if (directory == null) return;
    final previousShadows = debugDisableShadows;
    try {
      debugDisableShadows = false;
      void repaint(RenderObject object) {
        object.markNeedsPaint();
        object.visitChildren(repaint);
      }

      repaint(
        tester.renderObject<RenderRepaintBoundary>(find.byKey(previewKey)),
      );
      await tester.pump();
      await tester.runAsync(() async {
        final boundary = tester.renderObject<RenderRepaintBoundary>(
          find.byKey(previewKey),
        );
        final image = await boundary.toImage(pixelRatio: 2);
        final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
        await File('$directory/$name.png').create(recursive: true);
        await File(
          '$directory/$name.png',
        ).writeAsBytes(bytes!.buffer.asUint8List());
        image.dispose();
      });
    } finally {
      debugDisableShadows = previousShadows;
    }
  }

  Future<ScreenApi> mount(
    WidgetTester tester,
    Size size, {
    double scale = 1,
    Brightness brightness = Brightness.light,
    bool reducedMotion = false,
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final api = ScreenApi();
    final controller = ScheduleController(
      api: api,
      fallbackIp: '',
      clock: () => DateTime(2026, 10, 15, 8),
      ipLookup: () async => '192.0.2.1',
    );
    addTearDown(controller.dispose);
    addTearDown(api.close);
    await tester.pumpWidget(
      RepaintBoundary(
        key: previewKey,
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: buildTheme(brightness),
          locale: const Locale('vi'),
          supportedLocales: const [Locale('vi')],
          localizationsDelegates: GlobalMaterialLocalizations.delegates,
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context).copyWith(
              textScaler: TextScaler.linear(scale),
              disableAnimations: reducedMotion,
            ),
            child: child!,
          ),
          home: ScheduleScreen(
            controller: controller,
            checkInRequested: false,
            onCheckInRequestHandled: () {},
            onSignOut: () {},
            onSessionExpired: () {},
          ),
        ),
      ),
    );
    await tester.runAsync(
      () => precacheImage(
        const AssetImage(AppBrand.emblemAsset),
        tester.element(find.byType(ScheduleScreen)),
      ),
    );
    await tester.pumpAndSettle();
    // Đóng sheet đề xuất lớp hiện tại nếu giờ chạy test rơi vào buổi học giả lập.
    if (find.text('Từ khóa điểm danh').evaluate().isNotEmpty ||
        find
            .text('Không hỗ trợ điểm danh cho lịch thi.')
            .evaluate()
            .isNotEmpty) {
      final context = tester.element(find.byType(ScheduleScreen));
      Navigator.of(context).pop();
      await tester.pumpAndSettle();
    }
    return api;
  }

  testWidgets('Navigates, filters, searches and loads course details', (
    tester,
  ) async {
    final api = await mount(tester, const Size(390, 844));
    await capture(tester, 'schedule-light');
    await tester.tap(find.text('Kết quả'));
    await tester.pumpAndSettle();
    expect(find.text('GPA tích lũy / 4'), findsOneWidget);
    expect(find.text('3.2'), findsOneWidget);
    await capture(tester, 'grades-light');
    final scrollable = find
        .descendant(
          of: find.byType(CustomScrollView),
          matching: find.byType(Scrollable),
        )
        .first;
    await tester.scrollUntilVisible(
      find.text('Toàn bộ học kỳ').last,
      180,
      scrollable: scrollable,
    );
    await tester.tap(find.text('Toàn bộ học kỳ').hitTestable());
    await tester.pumpAndSettle();
    await tester.tap(find.text('HK 2 · 2025-2026').last);
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextFormField).last, 'MOB101');
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('Lập trình di động'),
      180,
      scrollable: scrollable,
    );
    await tester.tap(find.text('Lập trình di động'));
    await tester.pumpAndSettle();
    expect(find.text('Điểm thành phần'), findsOneWidget);
    expect(find.text('Chuyên cần'), findsOneWidget);
    expect(api.detailsRequests, 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'Renders attendance without HTML and copies clean lesson details',
    (tester) async {
      String? copied;
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (call) async {
          if (call.method == 'Clipboard.setData')
            copied = (call.arguments as Map)['text'] as String?;
          return null;
        },
      );
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform,
          null,
        ),
      );
      await mount(tester, const Size(390, 844), brightness: Brightness.dark);
      final scrollable = find
          .descendant(
            of: find.byKey(const PageStorageKey('schedule-scroll')),
            matching: find.byType(Scrollable),
          )
          .first;
      final lessonCard = find.byWidgetPredicate(
        (widget) =>
            widget is EntryCard && widget.entry.id == 'lesson-synthetic',
      );
      await tester.scrollUntilVisible(lessonCard, 200, scrollable: scrollable);
      expect(find.textContaining('<br>'), findsNothing);
      expect(find.text('Có mặt'), findsOneWidget);
      await capture(tester, 'schedule-dark');
      final title = find.descendant(
        of: find.byType(EntryCard).first,
        matching: find.text('Lập trình di động'),
      );
      await Scrollable.ensureVisible(tester.element(title), alignment: .2);
      await tester.pumpAndSettle();
      await tester.tap(title);
      await tester.pumpAndSettle();
      expect(
        find.descendant(
          of: find.byType(CheckInSheet),
          matching: find.text('Có mặt'),
        ),
        findsOneWidget,
      );
      expect(find.text('Từ khóa điểm danh'), findsNothing);
      expect(find.textContaining('<br>'), findsNothing);
      await capture(tester, 'attendance-details');
      await tester.tap(find.text('Sao chép thông tin'));
      await tester.pumpAndSettle();
      expect(copied, contains('Mobile-01'));
      expect(copied, isNot(contains('<br>')));
      expect(copied?.split('Có mặt').length, 2);
      expect(find.text('Đã sao chép thông tin'), findsOneWidget);
      await tester.tap(find.text('Hoàn tất'));
      await tester.pumpAndSettle();
    },
  );

  testWidgets('Keeps schedule search and scroll position when switching tabs', (
    tester,
  ) async {
    await mount(tester, const Size(390, 844));
    final search = find.byKey(const ValueKey('schedule-search'));
    await tester.ensureVisible(search);
    await tester.pumpAndSettle();
    await tester.enterText(search, 'mang may tinh');
    await tester.pumpAndSettle();
    final scrollable = find
        .descendant(
          of: find.byKey(const PageStorageKey('schedule-scroll')),
          matching: find.byType(Scrollable),
        )
        .first;
    final before = tester.state<ScrollableState>(scrollable).position.pixels;
    await tester.tap(find.widgetWithText(NavigationDestination, 'Kết quả'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(NavigationDestination, 'Lịch học'));
    await tester.pumpAndSettle();
    expect(tester.widget<TextField>(search).controller!.text, 'mang may tinh');
    expect(tester.state<ScrollableState>(scrollable).position.pixels, before);
    await tester.tap(find.byTooltip('Xóa tìm kiếm'));
    await tester.pumpAndSettle();
    expect(tester.widget<TextField>(search).controller!.text, isEmpty);
  });

  testWidgets('Settings exposes persisted appearance and motion options', (
    tester,
  ) async {
    await mount(tester, const Size(390, 844), brightness: Brightness.dark);
    await tester.tap(find.byTooltip('Tùy chỉnh'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Giảm chuyển động'));
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<SwitchListTile>(
            find.widgetWithText(SwitchListTile, 'Giảm chuyển động'),
          )
          .value,
      isTrue,
    );
    final store = await SharedPreferences.getInstance();
    expect(store.getBool('appearance.reduceMotion'), isTrue);
    await capture(tester, 'preferences-dark');
    await tester.tap(find.widgetWithText(ListTile, 'Đăng xuất'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Ở lại'));
    await tester.pumpAndSettle();
    expect(find.text('Theo cách của bạn'), findsOneWidget);
  });

  testWidgets(
    'Filters exams, switches to week view and selects a calendar date',
    (tester) async {
      await mount(tester, const Size(390, 844), reducedMotion: true);
      final exams = find.widgetWithText(ChoiceChip, 'Lịch thi');
      await tester.ensureVisible(exams);
      await tester.pumpAndSettle();
      await tester.tap(exams);
      await tester.pumpAndSettle();
      expect(tester.widget<ChoiceChip>(exams).selected, isTrue);
      final week = find.widgetWithText(FilterChip, 'Cả tuần');
      await tester.ensureVisible(week);
      await tester.pumpAndSettle();
      await tester.tap(week);
      await tester.pumpAndSettle();
      expect(find.text('Lịch trong tuần'), findsOneWidget);
      await tester.tap(find.byTooltip('Chọn ngày'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('16').last);
      await tester.pumpAndSettle();
      await tester.tap(find.text('OK').last);
      await tester.pumpAndSettle();
      expect(find.text('Thứ 6, 16/10/2026'), findsOneWidget);
      expect(find.text('Lịch trong tuần'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('Supports system reduced motion and 200% text without overflow', (
    tester,
  ) async {
    await mount(tester, const Size(320, 720), scale: 2, reducedMotion: true);
    expect(tester.takeException(), isNull);
    // Nhãn phải xuống hàng ở chữ lớn, không chèn ép tiêu đề vào cột hẹp.
    final heading = find.byWidgetPredicate(
      (widget) =>
          widget is Text &&
          widget.data == 'Lịch học' &&
          widget.style?.fontWeight == FontWeight.w900,
    );
    final count = find.text('2 buổi / tuần');
    expect(
      tester.getTopLeft(count).dy,
      greaterThan(tester.getBottomLeft(heading).dy),
    );
    expect(tester.getSize(heading).width, lessThanOrEqualTo(280));
    await tester.tap(find.widgetWithText(NavigationDestination, 'Kết quả'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await tester.tap(find.byTooltip('Tùy chỉnh'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  for (final brightness in Brightness.values) {
    testWidgets('No overflow at 320px and large text: $brightness', (
      tester,
    ) async {
      await mount(
        tester,
        const Size(320, 720),
        scale: 1.5,
        brightness: brightness,
      );
      expect(tester.takeException(), isNull);
      await tester.tap(find.text('Kết quả'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await tester.drag(find.byType(CustomScrollView), const Offset(0, -600));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await capture(
        tester,
        brightness == Brightness.dark
            ? 'grades-dark-small'
            : 'grades-light-small',
      );
    });
  }
}
