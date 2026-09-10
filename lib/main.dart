import 'dart:io';
import 'package:flutter/material.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;
import 'package:intl/intl.dart';
import 'package:csv/csv.dart';
import 'db.dart';
import 'overview.dart';

/// JooseBooks — bookkeeping for people who hate bookkeeping (Flutter edition).
/// Money in, money out, profit. Same one-screen philosophy as the Godot build.

const kBg = Color(0xFF0D0D10);
const kSurface = Color(0xFF17171D);
const kSurface2 = Color(0xFF212129);
const kGold = Color(0xFFD4A843);
const kText = Color(0xFFEBEBF0);
const kTextDim = Color(0xFF8C8C99);
const kGreen = Color(0xFF4CD964);
const kRed = Color(0xFFE65959);

const categories = ['Server costs', 'Equipment', 'Software/tools', 'Revenue', 'Other'];

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;
  final dir = await getApplicationSupportDirectory();
  // v3: Personal is a real profile row (renameable); entries semantics unchanged.
  final db = await openAppDatabase(p.join(dir.path, 'joosebooks.db'));
  final debugAddSheet = Platform.environment['JOOSBOOKS_DEBUG'] == 'add-sheet';
  // JOOSBOOKS_DEMO=1: demo DB + dashboard auto-opens the edit sheet on the
  // first entry. JOOSBOOKS_DEMO=2: demo DB, dashboard stays on the list
  // (screenshot the rows + swipe/undo flow). Both use a THROWAWAY demo DB;
  // real books untouched.
  final demoMode = Platform.environment['JOOSBOOKS_DEMO'];
  final demo = demoMode == '1' || demoMode == '2';
  final Database demoDb;
  if (demo) {
    await db.close();
    demoDb = await openAppDatabase(p.join(dir.path, 'joosebooks-demo.db'));
    final n = (await demoDb.rawQuery(
            'SELECT COUNT(*) c FROM entries')) //
        .first['c'] as int? ?? 0;
    if (n == 0) {
      final now = DateTime.now();
      int ts(DateTime d) => DateTime(d.year, d.month, d.day, 12)
          .millisecondsSinceEpoch ~/ 1000;
      await demoDb.insert('entries', {
        'ts': ts(DateTime(now.year, now.month, now.day)),
        'amount_cents': 2550, 'kind': 'out', 'category': 'Equipment',
        'note': 'USB-C hub (edit me)', 'profile_id': 0});
      await demoDb.insert('entries', {
        'ts': ts(DateTime(now.year, now.month, now.day - 1)),
        'amount_cents': 120000, 'kind': 'in', 'category': 'Revenue',
        'note': 'Invoice #104', 'profile_id': 0});
      await demoDb.insert('entries', {
        'ts': ts(DateTime(now.year, now.month, now.day - 2)),
        'amount_cents': 3000, 'kind': 'out', 'category': 'Software/tools',
        'note': 'Domain renewal', 'profile_id': 0});
    }
  } else {
    demoDb = db;
  }
  runApp(JooseBooksApp(db: demoDb, debugAddSheet: debugAddSheet, demoAutoEdit: demo));
}

class JooseBooksApp extends StatelessWidget {
  final Database db;
  final bool debugAddSheet;
  final Widget? home; // test/overview override; default = OverviewPage
  final bool demoAutoEdit;
  const JooseBooksApp({super.key, required this.db, this.debugAddSheet = false, this.home, this.demoAutoEdit = false});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'JooseBooks',
      theme: ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: kBg,
        colorScheme: const ColorScheme.dark(primary: kGold, secondary: kGold),
        fontFamily: 'Roboto',
      ),
      // Demo mode lands straight on a dashboard (auto-edit); normal launch
      // opens the Overview as always.
      home: home ??
          (demoAutoEdit
              ? DashboardPage(db: db, demoAutoEdit: true)
              : OverviewPage(db: db)),
      debugShowCheckedModeBanner: false,
    );
  }
}

class DashboardPage extends StatefulWidget {
  final Database db;
  final bool debugAddSheet;
  final int initialProfileId; // which pile was tapped on the Overview
  /// Demo mode (JOOSBOOKS_DEMO=1): auto-open the edit sheet on the first
  /// entry ~800ms after load, so screenshots can capture it without
  /// synthetic clicks (which never land in Flutter from the driver).
  final bool demoAutoEdit;
  const DashboardPage({super.key, required this.db, this.debugAddSheet = false, this.initialProfileId = 0, this.demoAutoEdit = false});
  @override
  State<DashboardPage> createState() => _DashboardPageState();
}

class _DashboardPageState extends State<DashboardPage> {
  late int year = DateTime.now().year;
  late int profileId = widget.initialProfileId; // selected business profile (0 = Personal)
  List<Map<String, Object?>> profiles = [];
  Map<String, double>? summary;
  String? monthLine;
  List<Map<String, Object?>> entries = [];
  bool _demoFired = false;

  @override
  void initState() {
    super.initState();
    _refresh();
    if (widget.debugAddSheet) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        Future.delayed(const Duration(milliseconds: 600), _openAdd);
      });
    }
    if (widget.demoAutoEdit) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        final demoMode = Platform.environment['JOOSBOOKS_DEMO'];
        // DEMO=2 → stay on the list (no auto-edit) so the row chrome can be
        // screenshotted. DEMO=3 → auto-swipe the first row to capture the
        // delete + undo snackbar flow without synthetic clicks.
        if (demoMode == '2') return;
        if (demoMode == '3') {
          Future.delayed(const Duration(milliseconds: 1200), () async {
            await _refresh();
            if (!mounted || entries.isEmpty || _demoFired) return;
            _demoFired = true;
            _deleteWithUndo(Map<String, Object?>.from(entries.first));
          });
          return;
        }
        Future.delayed(const Duration(milliseconds: 800), () async {
          await _refresh();
          if (!mounted || entries.isEmpty || _demoFired) return;
          _demoFired = true;
          _openEdit(Map<String, Object?>.from(entries.first));
        });
      });
    }
  }

  Future<void> _refresh() async {
    // Load profiles + all queries scoped to the selected profile (per-pile numbers).
    profiles = await widget.db.query('profiles', orderBy: 'id');
    final startY = DateTime(year).millisecondsSinceEpoch ~/ 1000;
    final endY = DateTime(year + 1).millisecondsSinceEpoch ~/ 1000;
    final rows = await widget.db.query('entries',
        where: 'ts >= ? AND ts < ? AND profile_id = ?',
        whereArgs: [startY, endY, profileId], orderBy: 'ts DESC');
    double income = 0, expenses = 0;
    for (final r in rows) {
      final cents = r['amount_cents'] as int;
      if (r['kind'] == 'in') { income += cents / 100; } else { expenses += cents / 100; }
    }
    final profit = income - expenses;
    // Mounted guard: _refresh can complete after the page is disposed
    // (e.g. undo-callback firing late, or the user popping the page while a
    // query is in flight). setState on a defunct State throws.
    if (!mounted) return;
    setState(() {
      summary = {
        'income': income, 'expenses': expenses,
        'profit': profit, 'tax': profit < 0 ? 0 : profit * 0.28,
      };
      entries = rows;
      final now = DateTime.now();
      if (now.year == year) {
        final mStart = DateTime(now.year, now.month).millisecondsSinceEpoch ~/ 1000;
        final mEnd = DateTime(now.year, now.month + 1).millisecondsSinceEpoch ~/ 1000;
        double mIn = 0, mOut = 0;
        for (final r in rows) {
          final ts = r['ts'] as int;
          if (ts >= mStart && ts < mEnd) {
            final v = (r['amount_cents'] as int) / 100;
            if (r['kind'] == 'in') { mIn += v; } else { mOut += v; }
          }
        }
        monthLine = 'This month: in \$${mIn.toStringAsFixed(2)} · out \$${mOut.toStringAsFixed(2)} · profit \$${(mIn - mOut).toStringAsFixed(2)}';
      } else {
        monthLine = '(past year)';
      }
    });
  }

  String _profileName(int pid) {
    for (final pr in profiles) {
      if (pr['id'] == pid) return pr['name'] as String;
    }
    return 'Personal';
  }

  Future<void> _renameProfile(int pid) async {
    final current = _profileName(pid);
    final nameCtrl = TextEditingController(text: current);
    final ok = await showDialog<bool>(
        context: context,
        builder: (dCtx) => AlertDialog(
            backgroundColor: kSurface,
            title: const Text('Rename pile', style: TextStyle(color: kGold)),
            content: TextField(
              controller: nameCtrl,
              autofocus: true,
              style: const TextStyle(color: kText),
              decoration: InputDecoration(
                  filled: true, fillColor: kSurface2,
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none)),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(dCtx, false),
                  child: const Text('Cancel', style: TextStyle(color: kTextDim))),
              FilledButton(
                  style: FilledButton.styleFrom(backgroundColor: kGold, foregroundColor: const Color(0xFF141210)),
                  onPressed: () => Navigator.pop(dCtx, true),
                  child: const Text('Save')),
            ]));
    final name = nameCtrl.text.trim();
    if (ok == true && name.isNotEmpty && name != current) {
      await renameProfile(widget.db, pid, name);
      await _refresh(); // fresh names before reopening, or the popover shows stale data
      if (!mounted) return;
      // Reopen the popover so the CEO sees the rename landed, still in context.
      await _openProfilePopover();
    }
  }

  Future<void> _deleteProfile(int pid) async {
    // Spec rule: entries fall back to Personal — no data is ever deleted.
    await widget.db.execute(
        'UPDATE entries SET profile_id = 0 WHERE profile_id = ?', [pid]);
    await widget.db.delete('profiles', where: 'id = ?', whereArgs: [pid]);
    if (profileId == pid) profileId = 0;
    _refresh();
  }

  Future<void> _exportCsv() async {
    final rows = await widget.db.query('entries',
        where: 'ts >= ? AND ts < ? AND profile_id = ?',
        whereArgs: [DateTime(year).millisecondsSinceEpoch ~/ 1000,
                    DateTime(year + 1).millisecondsSinceEpoch ~/ 1000,
                    profileId],
        orderBy: 'ts');
    final data = [
      ['date', 'kind', 'category', 'amount', 'note'],
      for (final r in rows)
        [
          DateFormat('yyyy-MM-dd').format(DateTime.fromMillisecondsSinceEpoch((r['ts'] as int) * 1000)),
          r['kind'], r['category'],
          ((r['amount_cents'] as int) / 100).toStringAsFixed(2),
          r['note'] ?? '',
        ],
    ];
    final csv = const CsvEncoder().convert(data);
    final dir = await getApplicationDocumentsDirectory();
    // Business piles export under their own filename: hand "the LLC file" to
    // the accountant literally (spec: joosebooks_2026_my-llc.csv).
    var fname = 'joosebooks_$year.csv';
    if (profileId != 0) {
      final slug = _profileName(profileId).toLowerCase().replaceAll(' ', '-');
      fname = 'joosebooks_${year}_$slug.csv';
    }
    final file = File(p.join(dir.path, fname));
    await file.writeAsString(csv);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('CSV saved to ${file.path}')));
  }

  Future<void> _openAdd() async {
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: kSurface,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => AddEntrySheet(db: widget.db, profileId: profileId),
    );
    _refresh();
  }

  /// Tap an entry row → the same sheet in edit mode (prefilled, saves in
  /// place). One sheet for add + edit keeps the entry form in one place.
  Future<void> _openEdit(Map<String, Object?> entry) async {
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: kSurface,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => AddEntrySheet(db: widget.db, entry: entry),
    );
    _refresh();
  }

  /// Delete with undo: the row leaves the UI synchronously (Dismissible's
  /// contract — onDismissed requires the item gone from the tree immediately,
  /// or the framework throws), then the DB delete + summary refresh run in
  /// the background. UNDO re-inserts the identical row (id included).
  void _deleteWithUndo(Map<String, Object?> entry) {
    final id = entry['id'] as int;
    if (!mounted) return;
    // entries comes from db.query (unmodifiable) — rebind a filtered copy
    // instead of removeWhere (read-only list throws).
    setState(() =>
        entries = entries.where((e) => e['id'] != id).toList());
    // No hideCurrentSnackBar here: ScaffoldMessenger QUEUES snackbars, so
    // rapid multi-deletes keep every row's UNDO reachable (forced replace
    // would orphan earlier deletes permanently — QA4).
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: const Text('Entry deleted',
            style: TextStyle(color: kText)),
        backgroundColor: kSurface2,
        duration: const Duration(seconds: 5),
        action: SnackBarAction(
          label: 'UNDO',
          textColor: kGold,
          onPressed: () async {
            await widget.db.insert('entries', entry);
            if (mounted) _refresh();
          },
        ),
      ));
    () async {
      await widget.db.delete('entries', where: 'id = ?', whereArgs: [id]);
      _refresh();
    }();
  }

  Future<void> _openProfilePopover() async {
    // Popover: piles from the DB (Personal is a real row now, always first by
    // id). Rename via the pencil; long-press a business to delete (entries
    // fall back to the Personal pile — nothing is lost).
    await showModalBottomSheet(
      context: context,
      backgroundColor: kSurface,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (sheetCtx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('Your piles', style: TextStyle(fontSize: 13, color: kTextDim)),
            const SizedBox(height: 8),
            for (final pr in profiles)
              ListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                leading: Text(pr['id'] == 0 ? '👤' : '🏢',
                    style: const TextStyle(fontSize: 18)),
                title: Text(pr['name'] as String,
                    style: TextStyle(
                        color: pr['id'] == profileId ? kGold : kText,
                        fontWeight: pr['id'] == profileId ? FontWeight.bold : FontWeight.normal)),
                trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                  IconButton(
                      tooltip: 'Rename',
                      visualDensity: VisualDensity.compact,
                      icon: const Icon(Icons.edit_outlined, size: 18, color: kTextDim),
                      onPressed: () {
                        Navigator.pop(sheetCtx);
                        _renameProfile(pr['id'] as int);
                      }),
                  if (pr['id'] != 0)
                    GestureDetector(
                        onLongPress: () async {
                          final pid = pr['id'] as int;
                          Navigator.pop(sheetCtx);
                          final ok = await showDialog<bool>(
                              context: context,
                              builder: (dCtx) => AlertDialog(
                                  backgroundColor: kSurface,
                                  title: const Text('Delete pile?', style: TextStyle(color: kText)),
                                  content: Text(
                                      'Entries in "${pr['name']}" move back to Personal. Nothing is deleted.',
                                      style: const TextStyle(color: kTextDim)),
                                  actions: [
                                    TextButton(onPressed: () => Navigator.pop(dCtx, false),
                                        child: const Text('Cancel', style: TextStyle(color: kTextDim))),
                                    TextButton(onPressed: () => Navigator.pop(dCtx, true),
                                        child: const Text('Move to Personal', style: TextStyle(color: kRed))),
                                  ]));
                          if (ok == true) _deleteProfile(pid);
                        },
                        child: const Padding(
                            padding: EdgeInsets.all(8),
                            child: Icon(Icons.delete_outline, size: 20, color: kTextDim))),
                ]),
                onTap: () {
                  setState(() => profileId = pr['id'] as int);
                  Navigator.pop(sheetCtx);
                  _refresh();
                },
              ),
            const SizedBox(height: 4),
            OutlinedButton.icon(
              onPressed: () {
                Navigator.pop(sheetCtx);
                _openAddProfile();
              },
              icon: const Icon(Icons.add_business, color: kGold, size: 20),
              label: const Text('Add a business', style: TextStyle(color: kGold)),
              style: OutlinedButton.styleFrom(
                  side: const BorderSide(color: kGold),
                  minimumSize: const Size(0, 44)),
            ),
          ]),
        ),
      ),
    );
  }

  Future<void> _openAddProfile() async {
    // Two fields, ten seconds (spec): name + entity chips.
    final nameCtrl = TextEditingController();
    String entity = '';
    final ok = await showDialog<bool>(
        context: context,
        builder: (dCtx) => AlertDialog(
            backgroundColor: kSurface,
            title: const Text('Add a business', style: TextStyle(color: kGold)),
            content: StatefulBuilder(builder: (bCtx, setDState) => Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  TextField(
                    controller: nameCtrl,
                    autofocus: true,
                    style: const TextStyle(color: kText),
                    decoration: InputDecoration(
                        hintText: 'Business name (e.g. Bong Media)',
                        hintStyle: const TextStyle(color: kTextDim),
                        filled: true, fillColor: kSurface2,
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none)),
                  ),
                  const SizedBox(height: 12),
                  Wrap(
                      spacing: 6, runSpacing: 6,
                      children: [
                        for (final e in ['Sole Prop', 'LLC', 'S-Corp', 'C-Corp', 'Partnership', 'Other'])
                          ChoiceChip(
                              label: Text(e, style: const TextStyle(fontSize: 12)),
                              selected: entity == e,
                              selectedColor: kGold.withValues(alpha: 0.25),
                              backgroundColor: kSurface2,
                              labelStyle: TextStyle(color: entity == e ? kGold : kText),
                              side: BorderSide(color: entity == e ? kGold : Colors.white12),
                              onSelected: (_) => setDState(() => entity = e)),
                      ]),
                ])),
            actions: [
              TextButton(onPressed: () => Navigator.pop(dCtx, false),
                  child: const Text('Cancel', style: TextStyle(color: kTextDim))),
              FilledButton(
                  style: FilledButton.styleFrom(backgroundColor: kGold, foregroundColor: const Color(0xFF141210)),
                  onPressed: () => Navigator.pop(dCtx, true),
                  child: const Text('Save')),
            ]));
    final name = nameCtrl.text.trim();
    if (ok == true && name.isNotEmpty) {
      await widget.db.insert('profiles',
          {'name': name, 'entity': entity, 'created_ts': DateTime.now().millisecondsSinceEpoch ~/ 1000});
      setState(() => profileId = 0);
      _refresh();
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = summary;
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Shrink-to-fit header: back button + title + pile chip + year
              // nav can exceed narrow windows. FittedBox triggered a Flutter
              // framework semantics assertion crash-loop (!semantics.parent-
              // DataDirty, 3.47) — so instead: OverflowBar-free layout using
              // Flexible chip + compact spacing. The title is the only piece
              // allowed to shrink (ellipsis).
              Row(children: [
                // Back to Overview when the dashboard was pushed onto the
                // navigator (home = OverviewPage). Absent when it IS the home.
                if (Navigator.of(context).canPop())
                  const BackButton(color: kText),
                const Text('💼', style: TextStyle(fontSize: 18)),
                const SizedBox(width: 4),
                Flexible(child: Text('JooseBooks',
                    maxLines: 1, overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 20, color: kGold, fontWeight: FontWeight.bold))),
                const SizedBox(width: 6),
                // Quiet door (spec): small dim chip, ignorable. Gold only when a
                // business exists — the feature announces itself only when looked for.
                // Natural width (NOT Flexible — a Spacer would steal its share).
                GestureDetector(
                  onTap: _openProfilePopover,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                    decoration: BoxDecoration(
                        color: profiles.length > 1 ? kGold.withValues(alpha: 0.15) : kSurface,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                            color: profiles.length > 1 ? kGold : Colors.white12)),
                    child: Text('${_profileName(profileId)} ▾',
                        maxLines: 1, overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                            fontSize: 12,
                            color: profiles.length > 1 ? kGold : kTextDim)),
                  ),
                ),
                const Spacer(),
                Text('$year', style: const TextStyle(fontSize: 20, color: kText)),
                IconButton(
                    onPressed: () { year--; _refresh(); },
                    icon: const Icon(Icons.chevron_left),
                    visualDensity: VisualDensity.compact,
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(minWidth: 24, minHeight: 32)),
                IconButton(
                    onPressed: () { year++; _refresh(); },
                    icon: const Icon(Icons.chevron_right),
                    visualDensity: VisualDensity.compact,
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(minWidth: 24, minHeight: 32)),
              ]),
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                    color: kSurface, borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.white10)),
                child: s == null
                    ? const Center(child: CircularProgressIndicator(color: kGold))
                    : Column(children: [
                        _stat('Income', s['income']!, kGreen),
                        _stat('Expenses', s['expenses']!, kRed),
                        _stat('Profit (this year)', s['profit']!, kGold, big: true),
                        _stat('Set aside for taxes (~28%)', s['tax']!, kTextDim),
                      ]),
              ),
              const SizedBox(height: 8),
              Text(monthLine ?? '',
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 13, color: kTextDim)),
              const SizedBox(height: 8),
              Expanded(
                child: Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                      color: kSurface, borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.white10)),
                  child: entries.isEmpty
                      ? const Center(
                          child: Text('No entries yet.\nTap + to record money in or out.',
                              textAlign: TextAlign.center, style: TextStyle(color: kTextDim)))
                      : ListView.builder(
                          itemCount: entries.length,
                          itemBuilder: (_, i) {
                            final r = entries[i];
                            final t = DateTime.fromMillisecondsSinceEpoch((r['ts'] as int) * 1000);
                            final isIn = r['kind'] == 'in';
                            final v = (r['amount_cents'] as int) / 100;
                            // Swipe left to delete (undoable); tap to edit.
                            return Dismissible(
                              key: ValueKey('entry-${r['id']}'),
                              direction: DismissDirection.endToStart,
                              onDismissed: (_) =>
                                  _deleteWithUndo(Map<String, Object?>.from(r)),
                              background: Container(
                                alignment: Alignment.centerRight,
                                padding: const EdgeInsets.only(right: 16),
                                color: kRed.withValues(alpha: 0.25),
                                child: const Icon(Icons.delete_outline,
                                    color: kRed),
                              ),
                              // Own Material so ink splashes paint above the
                              // decorated container's background (assertion).
                              child: Material(
                                type: MaterialType.transparency,
                                child: ListTile(
                              dense: true,
                              onTap: () =>
                                  _openEdit(Map<String, Object?>.from(r)),
                              leading: Text(DateFormat('MMM d').format(t),
                                  style: const TextStyle(color: kTextDim)),
                              title: Text('${isIn ? "🟢" : "🔴"} ${r['category']}',
                                  style: const TextStyle(color: kText)),
                              subtitle: (r['note'] as String? ?? '').isEmpty
                                  ? null
                                  : Text('"${r['note']}"',
                                      style: const TextStyle(fontSize: 12, color: kTextDim)),
                              trailing: Text(isIn ? '+\$${v.toStringAsFixed(2)}' : '-\$${v.toStringAsFixed(2)}',
                                  style: TextStyle(color: isIn ? kGreen : kRed, fontWeight: FontWeight.bold)),
                            ),
                            ),
                            );
                          }),
                ),
              ),
              const SizedBox(height: 8),
              OutlinedButton.icon(
                onPressed: _exportCsv,
                icon: const Icon(Icons.download, color: kText),
                label: const Text('Export CSV (for your accountant)',
                    style: TextStyle(color: kText)),
                style: OutlinedButton.styleFrom(
                    side: const BorderSide(color: Colors.white10),
                    backgroundColor: kSurface2,
                    minimumSize: const Size(0, 44)),
              ),
            ],
          ),
        ),
      ),
      floatingActionButton: FloatingActionButton(
        backgroundColor: kGold,
        foregroundColor: const Color(0xFF141210),
        onPressed: _openAdd,
        child: const Icon(Icons.add, size: 36),
      ),
    );
  }

  Widget _stat(String label, double v, Color color, {bool big = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(children: [
        Text(label, style: TextStyle(fontSize: big ? 15 : 13, color: color)),
        const Spacer(),
        Text('\$${v.toStringAsFixed(2)}',
            style: TextStyle(
                fontSize: big ? 24 : 20, color: color, fontWeight: FontWeight.bold)),
      ]),
    );
  }
}

class AddEntrySheet extends StatefulWidget {
  final Database db;
  final int profileId; // preset from the dashboard's selected pile
  /// Existing entry being edited (tap-a-row-to-edit). Null = new-entry mode.
  /// When set, all fields prefill from the row and Save UPDATEs in place.
  final Map<String, Object?>? entry;
  const AddEntrySheet({super.key, required this.db, this.profileId = 0, this.entry});
  bool get isEdit => entry != null;
  @override
  State<AddEntrySheet> createState() => _AddEntrySheetState();
}

class _AddEntrySheetState extends State<AddEntrySheet> {
  String kind = 'in';
  String amountText = '';
  String category = 'Other';
  int profileId = 0;
  List<Map<String, Object?>> profiles = [];
  final noteCtrl = TextEditingController();
  // Edit mode: the first digit tap REPLACES the prefilled amount instead of
  // appending (the 2-decimal guard would otherwise swallow every digit of a
  // prefilled "25.50"). Standard keypad/POS behavior; cleared by ⌫ or '.'.
  bool _replaceOnFirstDigit = false;
  // Date of the transaction — defaults to today, tappable to change. Stored
  // at LOCAL NOON so year/month bucketing never shifts a day across midnight
  // or DST edges.
  DateTime entryDate = DateTime.now();

  @override
  void initState() {
    super.initState();
    profileId = widget.profileId;
    // Edit mode: prefill every field from the existing row.
    final e = widget.entry;
    if (e != null) {
      kind = e['kind'] as String? ?? 'in';
      category = e['category'] as String? ?? 'Other';
      profileId = e['profile_id'] as int? ?? 0;
      final ts = e['ts'] as int;
      // Rows are stored at local noon; strip to the date for the picker.
      final t = DateTime.fromMillisecondsSinceEpoch(ts * 1000);
      entryDate = DateTime(t.year, t.month, t.day, 12);
      final cents = e['amount_cents'] as int;
      amountText = (cents % 100 == 0)
          ? (cents ~/ 100).toString()
          : (cents / 100).toStringAsFixed(2);
      noteCtrl.text = e['note'] as String? ?? '';
      _replaceOnFirstDigit = true;
    }
    _loadProfiles();
  }

  Future<void> _loadProfiles() async {
    final rows = await widget.db.query('profiles', orderBy: 'id');
    if (mounted) setState(() => profiles = rows);
  }

  void _key(String k) {
    setState(() {
      if (k == '⌫') {
        if (amountText.isNotEmpty) amountText = amountText.substring(0, amountText.length - 1);
        _replaceOnFirstDigit = false;
      } else if (k == '.') {
        if (!amountText.contains('.')) amountText += '.';
        _replaceOnFirstDigit = false;
      } else if (amountText.length < 9) {
        // First digit on a prefilled amount starts a fresh number — must run
        // BEFORE the 2-decimal guard, which would otherwise swallow every
        // digit typed over a prefilled "25.50" (3 chars after the dot).
        if (_replaceOnFirstDigit) {
          _replaceOnFirstDigit = false;
          amountText = k;
          return;
        }
        if (amountText.contains('.') && amountText.length - amountText.indexOf('.') > 2) return;
        amountText += k;
      }
    });
  }

  Future<void> _save() async {
    final amount = double.tryParse(amountText) ?? 0;
    if (amount <= 0) return;
    final ts = DateTime(entryDate.year, entryDate.month, entryDate.day, 12)
        .millisecondsSinceEpoch ~/ 1000;
    final values = {
      'ts': ts,
      'amount_cents': (amount * 100).round(),
      'kind': kind, 'category': category, 'note': noteCtrl.text,
      'profile_id': profileId,
    };
    if (widget.isEdit) {
      // Update in place — the entry keeps its row id.
      await widget.db.update('entries', values,
          where: 'id = ?', whereArgs: [widget.entry!['id'] as int]);
    } else {
      await widget.db.insert('entries', values);
    }
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
          left: 20, right: 20, top: 16,
          bottom: MediaQuery.of(context).viewInsets.bottom + 16),
      child: SingleChildScrollView(
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        // Edit mode gets a title; new-entry mode stays visually identical
        // to before (no heading).
        if (widget.isEdit) ...[
          Align(alignment: Alignment.centerLeft,
              child: Text('Edit entry',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: kGold))),
          const SizedBox(height: 10),
        ],
        // Date row: default today, tap to change (click-driven; no keyboard).
        Align(alignment: Alignment.centerLeft,
            child: Text('Date:',
                style: TextStyle(fontSize: 12, color: kTextDim))),
        const SizedBox(height: 6),
        GestureDetector(
          onTap: () async {
            final picked = await showDatePicker(
                context: context,
                initialDate: entryDate,
                firstDate: DateTime(2000),
                lastDate: DateTime(2100));
            if (picked != null) setState(() => entryDate = picked);
          },
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            decoration: BoxDecoration(
                color: kSurface2,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.white12)),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              const Icon(Icons.calendar_today, size: 14, color: kGold),
              const SizedBox(width: 6),
              Text(DateFormat('EEE, MMM d, yyyy').format(entryDate),
                  style: const TextStyle(fontSize: 13, color: kText)),
              const SizedBox(width: 4),
              const Icon(Icons.edit, size: 12, color: kTextDim),
            ]),
          ),
        ),
        const SizedBox(height: 12),
        Row(children: [
          Expanded(child: _kindButton('⬆ Money IN', 'in', kGreen)),
          const SizedBox(width: 10),
          Expanded(child: _kindButton('⬇ Money OUT', 'out', kRed)),
        ]),
        const SizedBox(height: 12),
        Container(
          alignment: Alignment.center,
          padding: const EdgeInsets.symmetric(vertical: 14),
          decoration: BoxDecoration(
              color: kSurface2, borderRadius: BorderRadius.circular(12)),
          child: Text(amountText.isEmpty ? '\$0.00' : '\$$amountText',
              style: const TextStyle(fontSize: 40, color: kText)),
        ),
        const SizedBox(height: 12),
        GridView.count(
          crossAxisCount: 3,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          mainAxisSpacing: 8, crossAxisSpacing: 8,
          childAspectRatio: 2.6,
          children: [
            for (final k in ['1','2','3','4','5','6','7','8','9','.','0','⌫'])
              OutlinedButton(
                onPressed: () => _key(k),
                style: OutlinedButton.styleFrom(
                    backgroundColor: kSurface2,
                    side: BorderSide.none,
                    foregroundColor: kText,
                    textStyle: const TextStyle(fontSize: 20)),
                child: Text(k),
              ),
          ],
        ),
        const SizedBox(height: 10),
        Align(alignment: Alignment.centerLeft,
            child: Text('Category:',
                style: TextStyle(fontSize: 12, color: kTextDim))),
        const SizedBox(height: 6),
        Wrap(
          spacing: 6, runSpacing: 6,
          children: [
            for (final c in categories)
              ChoiceChip(
                label: Text(c, style: const TextStyle(fontSize: 12)),
                selected: category == c,
                selectedColor: kGold.withValues(alpha: 0.25),
                backgroundColor: kSurface2,
                labelStyle: TextStyle(color: category == c ? kGold : kText),
                side: BorderSide(color: category == c ? kGold : Colors.white12),
                onSelected: (_) => setState(() => category = c),
              ),
          ],
        ),
        const SizedBox(height: 10),
        // Profile chips: rendered ONLY when ≥1 business exists (spec) —
        // zero-business users see a visually identical sheet as before.
        // Personal is a real row now; its name comes from the DB (renameable).
        if (profiles.length > 1) ...[
          Align(alignment: Alignment.centerLeft,
              child: Text('Pile:',
                  style: TextStyle(fontSize: 12, color: kTextDim))),
          const SizedBox(height: 6),
          Wrap(
            spacing: 6, runSpacing: 6,
            children: [
              for (final pr in profiles)
                ChoiceChip(
                  label: Text(
                      '${pr['id'] == 0 ? '👤' : '🏢'} ${pr['name']}',
                      style: const TextStyle(fontSize: 12)),
                  selected: profileId == pr['id'],
                  selectedColor: kGold.withValues(alpha: 0.25),
                  backgroundColor: kSurface2,
                  labelStyle: TextStyle(
                      color: profileId == pr['id'] ? kGold : kText),
                  side: BorderSide(
                      color: profileId == pr['id'] ? kGold : Colors.white12),
                  onSelected: (_) =>
                      setState(() => profileId = pr['id'] as int),
                ),
            ],
          ),
          const SizedBox(height: 10),
        ],
        TextField(
          controller: noteCtrl,
          decoration: InputDecoration(
              hintText: 'Note (optional)', filled: true, fillColor: kSurface2,
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none)),
        ),
        const SizedBox(height: 12),
        SizedBox(
          width: double.infinity, height: 52,
          child: FilledButton(
            style: FilledButton.styleFrom(backgroundColor: kGold, foregroundColor: const Color(0xFF141210)),
            onPressed: _save,
            child: Text(widget.isEdit ? 'Save changes' : 'Save entry',
                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
          ),
        ),
        const SizedBox(height: 6),
        TextButton(onPressed: () => Navigator.pop(context),
            child: const Text('Cancel', style: TextStyle(color: kTextDim))),
      ]),
      ),
    );
  }

  Widget _kindButton(String label, String k, Color color) {
    final active = kind == k;
    return FilledButton(
      onPressed: () => setState(() => kind = k),
      style: FilledButton.styleFrom(
        backgroundColor: active ? color.withValues(alpha: 0.25) : kSurface2,
        foregroundColor: active ? color : kTextDim,
        side: BorderSide(color: active ? color : Colors.white10),
        minimumSize: const Size(0, 52),
      ),
      child: Text(label),
    );
  }
}