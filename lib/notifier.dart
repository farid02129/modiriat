import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;
import 'main.dart';

class Notifier {
  static final _p = FlutterLocalNotificationsPlugin();
  static bool _ok = false;

  static Future<void> init() async {
    try {
      tzdata.initializeTimeZones();
      tz.setLocalLocation(tz.getLocation('Asia/Tehran'));
      await _p.initialize(const InitializationSettings(android: AndroidInitializationSettings('@mipmap/ic_launcher')));
      final a = _p.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
      await a?.requestNotificationsPermission();
      _ok = true;
    } catch (_) {}
  }

  static int _id(Task t) => t.id.hashCode & 0x7fffffff;

  /// همه‌ی یادآورها را از نو بر اساس کارهای ثبت‌شده می‌چیند
  static Future<void> sync(List<Task> tasks) async {
    if (!_ok) return;
    try {
      await _p.cancelAll();
      final now = tz.TZDateTime.now(tz.local);
      for (final t in tasks) {
        if (!t.remind || t.done) continue;
        final hm = t.time.split(':');
        final when = tz.TZDateTime(tz.local, t.date.year, t.date.month, t.date.day, int.parse(hm[0]), int.parse(hm[1]));
        if (!when.isAfter(now)) continue;
        await _p.zonedSchedule(
          _id(t),
          'یادآوری: ${prioNames[t.priority]}',
          t.title,
          when,
          const NotificationDetails(
            android: AndroidNotificationDetails(
              'tasks', 'یادآوری کارها',
              channelDescription: 'اعلان زمان انجام کارها',
              importance: Importance.max,
              priority: Priority.high,
              playSound: true,
              enableVibration: true,
              category: AndroidNotificationCategory.alarm,
            ),
          ),
          androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
          uiLocalNotificationDateInterpretation: UILocalNotificationDateInterpretation.absoluteTime,
        );
      }
    } catch (_) {}
  }
}
