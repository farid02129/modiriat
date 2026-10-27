import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;
import 'main.dart';

class Notifier {
  static final _p = FlutterLocalNotificationsPlugin();
  static bool _ok = false;
  /// آخرین خطا برای نمایش به کاربر (در تنظیمات / تست آلارم)
  static String lastError = '';
  static int scheduled = 0;

  static const _channel = AndroidNotificationDetails(
    'routino_alarm_v2', 'یادآور روتینو',
    channelDescription: 'اعلان زمان انجام کارها',
    importance: Importance.max,
    priority: Priority.high,
    playSound: true,
    enableVibration: true,
    category: AndroidNotificationCategory.alarm,
    fullScreenIntent: true,
  );

  static Future<void> init() async {
    try {
      tzdata.initializeTimeZones();
      tz.setLocalLocation(tz.getLocation('Asia/Tehran'));
      await _p.initialize(const InitializationSettings(
          android: AndroidInitializationSettings('@mipmap/ic_launcher')));
      final a = _p.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
      await a?.requestNotificationsPermission();
      await a?.requestExactAlarmsPermission();
      _ok = true;
    } catch (e) {
      lastError = 'راه‌اندازی اعلان ناموفق: $e';
    }
  }

  /// هش پایدار (به‌جای hashCode که ممکن است بین اجراها فرق کند)
  static int _id(Task t) {
    var h = 0x811c9dc5;
    for (final c in t.id.codeUnits) {
      h = ((h ^ c) * 0x01000193) & 0x7fffffff;
    }
    return h;
  }

  /// همه‌ی یادآورها را از نو بر اساس کارهای ثبت‌شده زمان‌بندی می‌کند
  static Future<void> sync(List<Task> tasks) async {
    if (!_ok) return;
    lastError = '';
    scheduled = 0;
    try {
      await _p.cancelAll();
    } catch (e) {
      lastError = 'لغو یادآورهای قبلی ناموفق: $e';
    }
    final now = tz.TZDateTime.now(tz.local);
    for (final t in tasks) {
      if (!t.remind || t.done) continue;
      try {
        final hm = t.time.split(':');
        final when = tz.TZDateTime(tz.local, t.date.year, t.date.month, t.date.day,
            int.parse(hm[0]), int.parse(hm[1]));
        if (!when.isAfter(now)) continue;
        await _p.zonedSchedule(
          _id(t),
          'یادآوری: ${prioNames[t.priority]}',
          t.title,
          when,
          const NotificationDetails(android: _channel),
          androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
          uiLocalNotificationDateInterpretation: UILocalNotificationDateInterpretation.absoluteTime,
        );
        scheduled++;
      } catch (e) {
        lastError = 'زمان‌بندی «${t.title}» ناموفق: $e';
      }
    }
  }

  /// تست: یک اعلان ۱۰ ثانیه بعد
  static Future<String> test() async {
    if (!_ok) return 'اعلان‌ها راه‌اندازی نشده‌اند: $lastError';
    try {
      final when = tz.TZDateTime.now(tz.local).add(const Duration(seconds: 10));
      await _p.zonedSchedule(
        999999,
        'تست روتینو',
        'اگر این را می‌بینی، آلارم کار می‌کند',
        when,
        const NotificationDetails(android: _channel),
        androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
        uiLocalNotificationDateInterpretation: UILocalNotificationDateInterpretation.absoluteTime,
      );
      return '۱۰ ثانیه دیگر اعلان تست می‌آید.';
    } catch (e) {
      return 'خطا: $e';
    }
  }
}
