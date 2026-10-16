import 'package:flutter/material.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'app.dart';
import 'core/app_preferences.dart';
import 'core/session_store.dart';
import 'core/widget_bridge.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initializeDateFormatting();
  await WidgetBridge.init();
  // Nạp trước khi dựng app: theme/giảm chuyển động đã lưu được áp ngay frame
  // đầu, không chuyển giao diện sau khi app đã vẽ.
  final preferences = AppPreferences();
  await preferences.load();
  final session = await SessionStore.load();
  runApp(CmcCheckinApp(initialSession: session, preferences: preferences));
}
