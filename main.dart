import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';
import 'notifier.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Notifier.init();
  runApp(const App());
}

// ───────── مدل‌ها ─────────
class Goal {
  String id, title;
  Goal(this.id, this.title);
  Map toJson() => {'id': id, 'title': title};
  factory Goal.from(Map m) => Goal(m['id'], m['title']);
}

class Task {
  String id, title, goalId, time; // time مثل 09:00
  bool done;
  DateTime date;
  int priority; // 0 ضروری، 1 مهم، 2 کم‌اهمیت، 3 سر فرصت
  DateTime? doneAt;
  bool remind; // یادآور فعال
  Task(this.id, this.title, this.goalId, this.time, this.date, [this.done = false, this.priority = 1, this.doneAt, this.remind = true]);
  Map toJson() => {'id': id, 'title': title, 'goalId': goalId, 'time': time, 'date': date.toIso8601String(), 'done': done, 'priority': priority, 'doneAt': doneAt?.toIso8601String(), 'remind': remind};
  factory Task.from(Map m) => Task(m['id'], m['title'], m['goalId'], m['time'], DateTime.parse(m['date']), m['done'], m['priority'] ?? 1, m['doneAt'] == null ? null : DateTime.parse(m['doneAt']), m['remind'] ?? true);
}

const prioNames = ['ضروری', 'مهم', 'کم‌اهمیت', 'سر فرصت'];
const prioColors = [Colors.red, Colors.orange, Colors.blue, Colors.grey];

int byPrio(Task a, Task b) {
  final p = a.priority.compareTo(b.priority);
  return p != 0 ? p : a.time.compareTo(b.time);
}

String fmtDate(DateTime d) {
  final j = toJalali(d.year, d.month, d.day);
  return '${fa(j[0])}/${fa(j[1].toString().padLeft(2, '0'))}/${fa(j[2].toString().padLeft(2, '0'))}';
}

// ─── تبدیل میلادی و شمسی ───
List<int> toJalali(int gy, int gm, int gd) {
  const gdm = [0, 31, 59, 90, 120, 151, 181, 212, 243, 273, 304, 334];
  final gy2 = gm > 2 ? gy + 1 : gy;
  var days = 355666 + 365 * gy + (gy2 + 3) ~/ 4 - (gy2 + 99) ~/ 100 + (gy2 + 399) ~/ 400 + gd + gdm[gm - 1];
  var jy = -1595 + 33 * (days ~/ 12053);
  days %= 12053;
  jy += 4 * (days ~/ 1461);
  days %= 1461;
  if (days > 365) {
    jy += (days - 1) ~/ 365;
    days = (days - 1) % 365;
  }
  final jm = days < 186 ? 1 + days ~/ 31 : 7 + (days - 186) ~/ 30;
  final jd = 1 + (days < 186 ? days % 31 : (days - 186) % 30);
  return [jy, jm, jd];
}

DateTime fromJalali(int jy, int jm, int jd) {
  jy += 1595;
  var days = -355668 + 365 * jy + (jy ~/ 33) * 8 + ((jy % 33) + 3) ~/ 4 + jd + (jm < 7 ? (jm - 1) * 31 : (jm - 7) * 30 + 186);
  var gy = 400 * (days ~/ 146097);
  days %= 146097;
  if (days > 36524) {
    days--;
    gy += 100 * (days ~/ 36524);
    days %= 36524;
    if (days >= 365) days++;
  }
  gy += 4 * (days ~/ 1461);
  days %= 1461;
  if (days > 365) {
    gy += (days - 1) ~/ 365;
    days = (days - 1) % 365;
  }
  var gd = days + 1;
  final feb = ((gy % 4 == 0 && gy % 100 != 0) || gy % 400 == 0) ? 29 : 28;
  final sal = [0, 31, feb, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31];
  var gm = 0;
  while (gm < 13 && gd > sal[gm]) {
    gd -= sal[gm];
    gm++;
  }
  return DateTime(gy, gm, gd);
}

int jalaliMonthLen(int jy, int jm) {
  if (jm <= 6) return 31;
  if (jm <= 11) return 30;
  final g = fromJalali(jy, 12, 30);
  final j = toJalali(g.year, g.month, g.day);
  return (j[0] == jy && j[1] == 12 && j[2] == 30) ? 30 : 29;
}

const jMonths = ['فروردین', 'اردیبهشت', 'خرداد', 'تیر', 'مرداد', 'شهریور', 'مهر', 'آبان', 'آذر', 'دی', 'بهمن', 'اسفند'];

// انتخاب‌گر تاریخ شمسی
Future<DateTime?> pickJalali(BuildContext c, DateTime initial) {
  final j = toJalali(initial.year, initial.month, initial.day);
  var y = j[0], m = j[1], d = j[2];
  final nowY = toJalali(DateTime.now().year, DateTime.now().month, DateTime.now().day)[0];
  return showDialog<DateTime>(
    context: c,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, set) {
        final len = jalaliMonthLen(y, m);
        if (d > len) d = len;
        return AlertDialog(
          title: const Text('انتخاب تاریخ'),
          content: Row(children: [
            Expanded(child: DropdownButton<int>(isExpanded: true, value: d, items: [for (var i = 1; i <= len; i++) DropdownMenuItem(value: i, child: Text(fa(i)))], onChanged: (v) => set(() => d = v!))),
            const SizedBox(width: 6),
            Expanded(flex: 2, child: DropdownButton<int>(isExpanded: true, value: m, items: [for (var i = 1; i <= 12; i++) DropdownMenuItem(value: i, child: Text(jMonths[i - 1]))], onChanged: (v) => set(() => m = v!))),
            const SizedBox(width: 6),
            Expanded(flex: 2, child: DropdownButton<int>(isExpanded: true, value: y, items: [for (var i = nowY - 5; i <= nowY + 5; i++) DropdownMenuItem(value: i, child: Text(fa(i)))], onChanged: (v) => set(() => y = v!))),
          ]),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('لغو')),
            FilledButton(onPressed: () => Navigator.pop(ctx, fromJalali(y, m, d)), child: const Text('تأیید')),
          ],
        );
      },
    ),
  );
}

Widget prioChip(int p) => Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(color: prioColors[p].withOpacity(0.15), borderRadius: BorderRadius.circular(10)),
      child: Text(prioNames[p], style: TextStyle(fontSize: 11, color: prioColors[p])),
    );

class Tutorial {
  String id, title, url, time, goalId;
  bool practiced;
  Tutorial(this.id, this.title, this.url, this.time, this.goalId, [this.practiced = false]);
  Map toJson() => {'id': id, 'title': title, 'url': url, 'time': time, 'goalId': goalId, 'practiced': practiced};
  factory Tutorial.from(Map m) => Tutorial(m['id'], m['title'], m['url'], m['time'], m['goalId'], m['practiced']);
}

// ───────── ذخیره‌سازی و وضعیت ─────────
class Store extends ChangeNotifier {
  List<Goal> goals = [];
  List<Task> tasks = [];
  List<Tutorial> tutorials = [];

  Future<void> load() async {
    final p = await SharedPreferences.getInstance();
    List dec(String k) => jsonDecode(p.getString(k) ?? '[]');
    goals = dec('goals').map((e) => Goal.from(e)).toList();
    tasks = dec('tasks').map((e) => Task.from(e)).toList();
    tutorials = dec('tuts').map((e) => Tutorial.from(e)).toList();
    notifyListeners();
    Notifier.sync(tasks);
  }

  Future<void> save() async {
    final p = await SharedPreferences.getInstance();
    await p.setString('goals', jsonEncode(goals));
    await p.setString('tasks', jsonEncode(tasks));
    await p.setString('tuts', jsonEncode(tutorials));
    notifyListeners();
    Notifier.sync(tasks);
  }

  String newId() => DateTime.now().microsecondsSinceEpoch.toString();

  // پیشرفت هدف = (کارهای انجام‌شده + تمرین‌های انجام‌شده) / کل
  double progress(String goalId) {
    final t = tasks.where((e) => e.goalId == goalId).toList();
    final u = tutorials.where((e) => e.goalId == goalId).toList();
    final total = t.length + u.length;
    if (total == 0) return 0;
    return (t.where((e) => e.done).length + u.where((e) => e.practiced).length) / total;
  }

  double get overall {
    if (goals.isEmpty) return 0;
    return goals.map((g) => progress(g.id)).reduce((a, b) => a + b) / goals.length;
  }

  bool sameDay(DateTime a, DateTime b) => a.year == b.year && a.month == b.month && a.day == b.day;
  void setDone(Task t, bool v) {
    t.done = v;
    t.doneAt = v ? DateTime.now() : null;
    save();
  }

  List<Task> get today => tasks.where((t) => sameDay(t.date, DateTime.now())).toList()..sort(byPrio);
  int doneOn(DateTime d) => tasks.where((t) => t.done && sameDay(t.date, d)).length;
}

final store = Store();

// ───────── اپ ─────────
class App extends StatelessWidget {
  const App({super.key});
  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: store,
      builder: (_, __) => MaterialApp(
        title: 'اهداف من',
        debugShowCheckedModeBanner: false,
        locale: const Locale('fa'),
        supportedLocales: const [Locale('fa'), Locale('en')],
        localizationsDelegates: const [
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        theme: ThemeData(useMaterial3: true, colorSchemeSeed: Colors.indigo),
        darkTheme: ThemeData(useMaterial3: true, colorSchemeSeed: Colors.indigo, brightness: Brightness.dark),
        themeMode: ThemeMode.dark,
        builder: (c, child) => Directionality(textDirection: TextDirection.rtl, child: child!),
        home: const Home(),
      ),
    );
  }
}

String fa(Object n) {
  const e = '0123456789', f = '۰۱۲۳۴۵۶۷۸۹';
  var s = n.toString();
  for (var i = 0; i < 10; i++) s = s.replaceAll(e[i], f[i]);
  return s;
}

class Home extends StatefulWidget {
  const Home({super.key});
  @override
  State<Home> createState() => _HomeState();
}

class _HomeState extends State<Home> {
  int tab = 0;
  @override
  void initState() {
    super.initState();
    store.load();
  }

  @override
  Widget build(BuildContext context) {
    final pages = [const Dashboard(), const TasksPage(), const TutorialsPage(), const GoalsPage(), const ReportPage()];
    return Scaffold(
      body: SafeArea(child: pages[tab]),
      bottomNavigationBar: NavigationBar(
        selectedIndex: tab,
        onDestinationSelected: (i) => setState(() => tab = i),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.dashboard_outlined), selectedIcon: Icon(Icons.dashboard), label: 'داشبورد'),
          NavigationDestination(icon: Icon(Icons.checklist), label: 'کارها'),
          NavigationDestination(icon: Icon(Icons.play_circle_outline), selectedIcon: Icon(Icons.play_circle), label: 'آموزش‌ها'),
          NavigationDestination(icon: Icon(Icons.flag_outlined), selectedIcon: Icon(Icons.flag), label: 'اهداف'),
          NavigationDestination(icon: Icon(Icons.assessment_outlined), selectedIcon: Icon(Icons.assessment), label: 'گزارش'),
        ],
      ),
    );
  }
}

// ───────── ابزار فرم ─────────
Future<String?> pickTime(BuildContext c) async {
  final t = await showTimePicker(context: c, initialTime: TimeOfDay.now());
  if (t == null) return null;
  return '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';
}

Widget goalDropdown(String? value, ValueChanged<String?> on) => DropdownButtonFormField<String>(
      value: value,
      decoration: const InputDecoration(labelText: 'هدف مرتبط'),
      items: store.goals.map((g) => DropdownMenuItem(value: g.id, child: Text(g.title))).toList(),
      onChanged: on,
    );

String goalName(String id) => store.goals.where((g) => g.id == id).map((g) => g.title).firstOrNull ?? '—';

void needGoal(BuildContext c) => ScaffoldMessenger.of(c)
    .showSnackBar(const SnackBar(content: Text('اول از تب «اهداف» یک هدف بساز')));

// ───────── داشبورد ─────────
class Dashboard extends StatelessWidget {
  const Dashboard({super.key});
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final today = store.today;
    final days = List.generate(7, (i) => DateTime.now().subtract(Duration(days: 6 - i)));
    final counts = days.map(store.doneOn).toList();
    final maxC = counts.fold<int>(1, (a, b) => b > a ? b : a);
    const names = ['دو', 'سه', 'چهار', 'پنج', 'جمعه', 'شنبه', 'یک'];
    return ListView(padding: const EdgeInsets.all(16), children: [
      Text('داشبورد', style: Theme.of(context).textTheme.headlineMedium),
      const SizedBox(height: 12),
      Card(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Row(children: [
            SizedBox(
              width: 110, height: 110,
              child: Stack(alignment: Alignment.center, children: [
                SizedBox.expand(child: CircularProgressIndicator(value: store.overall, strokeWidth: 10, backgroundColor: cs.surfaceContainerHighest)),
                Text('${fa((store.overall * 100).round())}٪', style: Theme.of(context).textTheme.titleLarge),
              ]),
            ),
            const SizedBox(width: 20),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('پیشرفت کلی', style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 6),
              Text('${fa(store.tasks.where((t) => t.done).length)} کار از ${fa(store.tasks.length)} انجام شده'),
              Text('${fa(store.tutorials.where((t) => t.practiced).length)} آموزش از ${fa(store.tutorials.length)} تمرین شده'),
            ])),
          ]),
        ),
      ),
      const SizedBox(height: 8),
      Text('پیشرفت اهداف', style: Theme.of(context).textTheme.titleMedium),
      if (store.goals.isEmpty) const Padding(padding: EdgeInsets.all(12), child: Text('هنوز هدفی نساخته‌ای.')),
      for (final g in store.goals)
        Card(
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Expanded(child: Text(g.title, style: Theme.of(context).textTheme.titleSmall)),
                Text('${fa((store.progress(g.id) * 100).round())}٪'),
              ]),
              const SizedBox(height: 8),
              LinearProgressIndicator(value: store.progress(g.id), minHeight: 8, borderRadius: BorderRadius.circular(8)),
            ]),
          ),
        ),
      const SizedBox(height: 8),
      Text('کارهای انجام‌شده در ۷ روز اخیر', style: Theme.of(context).textTheme.titleMedium),
      Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: SizedBox(
            height: 140,
            child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
              for (var i = 0; i < 7; i++)
                Expanded(
                  child: Column(mainAxisAlignment: MainAxisAlignment.end, children: [
                    Text(fa(counts[i]), style: const TextStyle(fontSize: 11)),
                    Container(
                      margin: const EdgeInsets.symmetric(horizontal: 6),
                      height: 6 + 80 * counts[i] / maxC,
                      decoration: BoxDecoration(color: cs.primary, borderRadius: BorderRadius.circular(6)),
                    ),
                    const SizedBox(height: 4),
                    Text(names[days[i].weekday - 1], style: const TextStyle(fontSize: 11)),
                  ]),
                ),
            ]),
          ),
        ),
      ),
      const SizedBox(height: 8),
      Text('کارهای امروز', style: Theme.of(context).textTheme.titleMedium),
      if (today.isEmpty) const Padding(padding: EdgeInsets.all(12), child: Text('برای امروز کاری ثبت نشده.')),
      for (final t in today)
        CheckboxListTile(
          value: t.done,
          title: Text(t.title, style: TextStyle(decoration: t.done ? TextDecoration.lineThrough : null)),
          subtitle: Text('ساعت ${fa(t.time)} • ${goalName(t.goalId)}'),
          secondary: prioChip(t.priority),
          onChanged: (v) => store.setDone(t, v!),
        ),
    ]);
  }
}

// ───────── کارها ─────────
class TasksPage extends StatelessWidget {
  const TasksPage({super.key});

  void add(BuildContext c) {
    if (store.goals.isEmpty) return needGoal(c);
    final title = TextEditingController();
    String? goal = store.goals.first.id;
    String time = '09:00';
    int prio = 1;
    bool remind = true;
    DateTime date = DateTime.now();
    showModalBottomSheet(
      context: c, isScrollControlled: true,
      builder: (_) => StatefulBuilder(
        builder: (ctx, set) => Padding(
          padding: EdgeInsets.fromLTRB(16, 16, 16, MediaQuery.of(ctx).viewInsets.bottom + 16),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            TextField(controller: title, decoration: const InputDecoration(labelText: 'عنوان کار')),
            goalDropdown(goal, (v) => goal = v),
            const SizedBox(height: 8),
            Wrap(spacing: 6, children: [
              for (var i = 0; i < 4; i++)
                ChoiceChip(label: Text(prioNames[i]), selected: prio == i, onSelected: (_) => set(() => prio = i)),
            ]),
            const SizedBox(height: 8),
            Row(children: [
              Expanded(child: OutlinedButton.icon(
                icon: const Icon(Icons.access_time),
                label: Text('ساعت ${fa(time)}'),
                onPressed: () async { final t = await pickTime(ctx); if (t != null) set(() => time = t); })),
              const SizedBox(width: 8),
              Expanded(child: OutlinedButton.icon(
                icon: const Icon(Icons.event),
                label: Text(fmtDate(date)),
                onPressed: () async {
                  final d = await pickJalali(ctx, date);
                  if (d != null) set(() => date = d);
                })),
            ]),
            SwitchListTile(contentPadding: EdgeInsets.zero, title: const Text('یادآوری با اعلان و آلارم'), secondary: const Icon(Icons.alarm), value: remind, onChanged: (v) => set(() => remind = v)),
            FilledButton(
              onPressed: () {
                if (title.text.trim().isEmpty || goal == null) return;
                store.tasks.add(Task(store.newId(), title.text.trim(), goal!, time, date, false, prio, null, remind));
                store.save();
                Navigator.pop(ctx);
              },
              child: const Text('ثبت کار')),
          ]),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final list = [...store.tasks]..sort((a, b) {
        final p = a.priority.compareTo(b.priority);
        if (p != 0) return p;
        final d = b.date.compareTo(a.date);
        return d != 0 ? d : a.time.compareTo(b.time);
      });
    return Scaffold(
      appBar: AppBar(title: const Text('کارهای روزمره')),
      floatingActionButton: FloatingActionButton.extended(onPressed: () => add(context), icon: const Icon(Icons.add), label: const Text('کار جدید')),
      body: list.isEmpty
          ? const Center(child: Text('کاری ثبت نشده'))
          : ListView(children: [
              for (final t in list)
                Dismissible(
                  key: ValueKey(t.id),
                  background: Container(color: Colors.red, alignment: Alignment.centerLeft, padding: const EdgeInsets.all(16), child: const Icon(Icons.delete, color: Colors.white)),
                  onDismissed: (_) { store.tasks.remove(t); store.save(); },
                  child: CheckboxListTile(
                    value: t.done,
                    title: Text(t.title, style: TextStyle(decoration: t.done ? TextDecoration.lineThrough : null)),
                    subtitle: Text('${fmtDate(t.date)} • ${fa(t.time)} • ${goalName(t.goalId)}'),
                    secondary: prioChip(t.priority),
                    onChanged: (v) => store.setDone(t, v!),
                  ),
                ),
              const SizedBox(height: 80),
            ]),
    );
  }
}

// ───────── آموزش‌ها ─────────
class TutorialsPage extends StatelessWidget {
  const TutorialsPage({super.key});

  void add(BuildContext c) {
    if (store.goals.isEmpty) return needGoal(c);
    final title = TextEditingController(), url = TextEditingController();
    String? goal = store.goals.first.id;
    String time = '20:00';
    showModalBottomSheet(
      context: c, isScrollControlled: true,
      builder: (_) => StatefulBuilder(
        builder: (ctx, set) => Padding(
          padding: EdgeInsets.fromLTRB(16, 16, 16, MediaQuery.of(ctx).viewInsets.bottom + 16),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            TextField(controller: title, decoration: const InputDecoration(labelText: 'عنوان آموزش')),
            TextField(controller: url, keyboardType: TextInputType.url, textDirection: TextDirection.ltr, decoration: const InputDecoration(labelText: 'لینک (یوتیوب یا سایت)')),
            goalDropdown(goal, (v) => goal = v),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              icon: const Icon(Icons.access_time),
              label: Text('ساعت مطالعه: ${fa(time)}'),
              onPressed: () async { final t = await pickTime(ctx); if (t != null) set(() => time = t); }),
            const SizedBox(height: 12),
            FilledButton(
              onPressed: () {
                if (title.text.trim().isEmpty || goal == null) return;
                store.tutorials.add(Tutorial(store.newId(), title.text.trim(), url.text.trim(), time, goal!));
                store.save();
                Navigator.pop(ctx);
              },
              child: const Text('افزودن آموزش')),
          ]),
        ),
      ),
    );
  }

  Future<void> open(BuildContext c, String u) async {
    var s = u;
    if (!s.startsWith('http')) s = 'https://$s';
    final ok = await launchUrl(Uri.parse(s), mode: LaunchMode.externalApplication);
    if (!ok && c.mounted) ScaffoldMessenger.of(c).showSnackBar(const SnackBar(content: Text('لینک باز نشد')));
  }

  @override
  Widget build(BuildContext context) {
    final list = [...store.tutorials]..sort((a, b) => a.time.compareTo(b.time));
    return Scaffold(
      appBar: AppBar(title: const Text('آموزش‌ها')),
      floatingActionButton: FloatingActionButton.extended(onPressed: () => add(context), icon: const Icon(Icons.add), label: const Text('آموزش جدید')),
      body: list.isEmpty
          ? const Center(child: Text('آموزشی اضافه نشده'))
          : ListView(padding: const EdgeInsets.all(12), children: [
              for (final t in list)
                Dismissible(
                  key: ValueKey(t.id),
                  background: Container(color: Colors.red, alignment: Alignment.centerLeft, padding: const EdgeInsets.all(16), child: const Icon(Icons.delete, color: Colors.white)),
                  onDismissed: (_) { store.tutorials.remove(t); store.save(); },
                  child: Card(
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(t.title, style: Theme.of(context).textTheme.titleMedium),
                        const SizedBox(height: 4),
                        Text('ساعت ${fa(t.time)} • ${goalName(t.goalId)}'),
                        const SizedBox(height: 8),
                        Row(children: [
                          FilledButton.tonalIcon(
                            icon: const Icon(Icons.play_arrow),
                            label: const Text('دیدن'),
                            onPressed: t.url.isEmpty ? null : () => open(context, t.url)),
                          const SizedBox(width: 8),
                          const Spacer(),
                          const Text('تمرین شد'),
                          Switch(value: t.practiced, onChanged: (v) { t.practiced = v; store.save(); }),
                        ]),
                      ]),
                    ),
                  ),
                ),
              const SizedBox(height: 80),
            ]),
    );
  }
}

// ───────── اهداف ─────────
class GoalsPage extends StatelessWidget {
  const GoalsPage({super.key});

  void add(BuildContext c) {
    final title = TextEditingController();
    showDialog(
      context: c,
      builder: (ctx) => AlertDialog(
        title: const Text('هدف جدید'),
        content: TextField(controller: title, autofocus: true, decoration: const InputDecoration(labelText: 'مثلاً یادگیری فلاتر')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('لغو')),
          FilledButton(
            onPressed: () {
              if (title.text.trim().isEmpty) return;
              store.goals.add(Goal(store.newId(), title.text.trim()));
              store.save();
              Navigator.pop(ctx);
            },
            child: const Text('ثبت')),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('اهداف')),
      floatingActionButton: FloatingActionButton.extended(onPressed: () => add(context), icon: const Icon(Icons.add), label: const Text('هدف جدید')),
      body: store.goals.isEmpty
          ? const Center(child: Text('اولین هدفت را بساز'))
          : ListView(children: [
              for (final g in store.goals)
                Dismissible(
                  key: ValueKey(g.id),
                  background: Container(color: Colors.red, alignment: Alignment.centerLeft, padding: const EdgeInsets.all(16), child: const Icon(Icons.delete, color: Colors.white)),
                  onDismissed: (_) {
                    store.goals.remove(g);
                    store.tasks.removeWhere((t) => t.goalId == g.id);
                    store.tutorials.removeWhere((t) => t.goalId == g.id);
                    store.save();
                  },
                  child: ListTile(
                    leading: const Icon(Icons.flag),
                    title: Text(g.title),
                    subtitle: Text('${fa((store.progress(g.id) * 100).round())}٪ پیشرفت'),
                  ),
                ),
            ]),
    );
  }
}

// ───────── گزارش کار ─────────
class ReportPage extends StatefulWidget {
  const ReportPage({super.key});
  @override
  State<ReportPage> createState() => _ReportPageState();
}

class _ReportPageState extends State<ReportPage> {
  DateTimeRange range = DateTimeRange(start: DateTime.now().subtract(const Duration(days: 6)), end: DateTime.now());
  bool onlyDone = false;

  List<Task> get items {
    final s = DateTime(range.start.year, range.start.month, range.start.day);
    final e = DateTime(range.end.year, range.end.month, range.end.day, 23, 59, 59);
    return store.tasks.where((t) => !t.date.isBefore(s) && !t.date.isAfter(e) && (!onlyDone || t.done)).toList()
      ..sort((a, b) {
        final d = a.date.compareTo(b.date);
        return d != 0 ? d : byPrio(a, b);
      });
  }

  String text(List<Task> l) {
    final b = StringBuffer('گزارش کار از ${fmtDate(range.start)} تا ${fmtDate(range.end)}\n');
    b.writeln('انجام‌شده: ${fa(l.where((t) => t.done).length)} از ${fa(l.length)}\n');
    for (final t in l) {
      b.writeln('${t.done ? '✅' : '⬜'} ${fmtDate(t.date)} ${fa(t.time)} | ${prioNames[t.priority]} | ${t.title} | ${goalName(t.goalId)}');
    }
    return b.toString();
  }

  @override
  Widget build(BuildContext context) {
    final l = items;
    return Scaffold(
      appBar: AppBar(title: const Text('گزارش کار'), actions: [
        IconButton(
          tooltip: 'کپی گزارش',
          icon: const Icon(Icons.copy),
          onPressed: () {
            Clipboard.setData(ClipboardData(text: text(l)));
            ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('گزارش کپی شد')));
          }),
      ]),
      body: ListView(padding: const EdgeInsets.all(12), children: [
        Row(children: [
          Expanded(child: OutlinedButton.icon(
            icon: const Icon(Icons.event),
            label: Text('از ${fmtDate(range.start)}'),
            onPressed: () async {
              final d = await pickJalali(context, range.start);
              if (d != null) setState(() => range = DateTimeRange(start: d, end: d.isAfter(range.end) ? d : range.end));
            })),
          const SizedBox(width: 8),
          Expanded(child: OutlinedButton.icon(
            icon: const Icon(Icons.event),
            label: Text('تا ${fmtDate(range.end)}'),
            onPressed: () async {
              final d = await pickJalali(context, range.end);
              if (d != null) setState(() => range = DateTimeRange(start: d.isBefore(range.start) ? d : range.start, end: d));
            })),
        ]),
        SwitchListTile(title: const Text('فقط کارهای انجام‌شده'), value: onlyDone, onChanged: (v) => setState(() => onlyDone = v)),
        Card(child: Padding(
          padding: const EdgeInsets.all(12),
          child: Text('انجام‌شده: ${fa(l.where((t) => t.done).length)} از ${fa(l.length)} کار'),
        )),
        if (l.isEmpty) const Padding(padding: EdgeInsets.all(24), child: Center(child: Text('کاری در این بازه نیست'))),
        for (final t in l)
          ListTile(
            leading: Icon(t.done ? Icons.check_circle : Icons.radio_button_unchecked, color: t.done ? Colors.green : null),
            title: Text(t.title),
            subtitle: Text('${fmtDate(t.date)} • ${fa(t.time)} • ${goalName(t.goalId)}'
                '${t.doneAt != null ? '\nانجام: ${fmtDate(t.doneAt!)}' : ''}'),
            trailing: prioChip(t.priority),
          ),
      ]),
    );
  }
}
