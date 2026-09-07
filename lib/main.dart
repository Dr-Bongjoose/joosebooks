import 'dart:io';
import 'package:flutter/material.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;
import 'package:intl/intl.dart';
import 'package:csv/csv.dart';

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
  final db = await openDatabase(p.join(dir.path, 'joosebooks.db'), version: 2,
      onCreate: (db, v) async {
        await db.execute('''
          CREATE TABLE IF NOT EXISTS entries (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            ts INTEGER NOT NULL,
            amount_cents INTEGER NOT NULL,
            kind TEXT NOT NULL,
            category TEXT NOT NULL DEFAULT 'Other',
            note TEXT DEFAULT '',
            profile_id INTEGER DEFAULT 0
          )''');
        await db.execute('''
          CREATE TABLE IF NOT EXISTS profiles (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            name TEXT NOT NULL,
            entity TEXT DEFAULT '',
            created_ts INTEGER NOT NULL
          )''');
        await db.execute(
            'CREATE INDEX IF NOT EXISTS idx_entries_profile ON entries(profile_id, ts)');
      },
      onUpgrade: (db, oldV, newV) async {
        if (oldV < 2) {
          // Guarded ALTER: pre-profile installs add the column; old entries stay
          // Personal (0). Never moves or deletes anyone's data.
          try {
            await db.execute('ALTER TABLE entries ADD COLUMN profile_id INTEGER DEFAULT 0');
          } catch (_) {}
          await db.execute('''
            CREATE TABLE IF NOT EXISTS profiles (
              id INTEGER PRIMARY KEY AUTOINCREMENT,
              name TEXT NOT NULL,
              entity TEXT DEFAULT '',
              created_ts INTEGER NOT NULL
            )''');
          await db.execute(
              'CREATE INDEX IF NOT EXISTS idx_entries_profile ON entries(profile_id, ts)');
        }
      });
  final debugAddSheet = Platform.environment['JOOSBOOKS_DEBUG'] == 'add-sheet';
  runApp(JooseBooksApp(db: db, debugAddSheet: debugAddSheet));
}

class JooseBooksApp extends StatelessWidget {
  final Database db;
  final bool debugAddSheet;
  const JooseBooksApp({super.key, required this.db, this.debugAddSheet = false});

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
      home: DashboardPage(db: db, debugAddSheet: debugAddSheet),
      debugShowCheckedModeBanner: false,
    );
  }
}

class DashboardPage extends StatefulWidget {
  final Database db;
  final bool debugAddSheet;
  const DashboardPage({super.key, required this.db, this.debugAddSheet = false});
  @override
  State<DashboardPage> createState() => _DashboardPageState();
}

class _DashboardPageState extends State<DashboardPage> {
  late int year = DateTime.now().year;
  int profileId = 0; // selected business profile (0 = Personal)
  List<Map<String, Object?>> profiles = [];
  Map<String, double>? summary;
  String? monthLine;
  List<Map<String, Object?>> entries = [];

  @override
  void initState() {
    super.initState();
    _refresh();
    if (widget.debugAddSheet) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        Future.delayed(const Duration(milliseconds: 600), _openAdd);
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
    if (pid == 0) return 'Personal';
    for (final pr in profiles) {
      if (pr['id'] == pid) return pr['name'] as String;
    }
    return 'Personal';
  }

  Future<void> _delete(int id) async {
    await widget.db.delete('entries', where: 'id = ?', whereArgs: [id]);
    _refresh();
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

  Future<void> _openProfilePopover() async {
    // Popover: profiles (Personal always on top) + add button. Long-press a
    // business to delete (entries fall back to Personal — nothing is lost).
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
            for (final pr in [
              {'id': 0, 'name': 'Personal', 'entity': ''},
              ...profiles,
            ])
              ListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                leading: Text(pr['id'] == 0 ? '👤' : '🏢',
                    style: const TextStyle(fontSize: 18)),
                title: Text(pr['name'] as String,
                    style: TextStyle(
                        color: pr['id'] == profileId ? kGold : kText,
                        fontWeight: pr['id'] == profileId ? FontWeight.bold : FontWeight.normal)),
                trailing: pr['id'] == 0
                    ? null
                    : GestureDetector(
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
              Row(children: [
                const Text('💼 JooseBooks',
                    style: TextStyle(fontSize: 20, color: kGold, fontWeight: FontWeight.bold)),
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
                IconButton(
                    onPressed: () { year--; _refresh(); },
                    icon: const Icon(Icons.chevron_left),
                    visualDensity: VisualDensity.compact,
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(minWidth: 28, minHeight: 32)),
                Text('$year', style: const TextStyle(fontSize: 22, color: kText)),
                IconButton(
                    onPressed: () { year++; _refresh(); },
                    icon: const Icon(Icons.chevron_right),
                    visualDensity: VisualDensity.compact,
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(minWidth: 28, minHeight: 32)),
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
                            return ListTile(
                              dense: true,
                              contentPadding: EdgeInsets.zero,
                              leading: Text(
                                  '${t.month.toString().padLeft(2, '0')}/${t.day.toString().padLeft(2, '0')}',
                                  style: const TextStyle(color: kTextDim)),
                              title: Text('${isIn ? "🟢" : "🔴"} ${r['category']}',
                                  style: const TextStyle(color: kText)),
                              subtitle: (r['note'] as String? ?? '').isEmpty
                                  ? null
                                  : Text('"${r['note']}"',
                                      style: const TextStyle(fontSize: 12, color: kTextDim)),
                              trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                                Text(isIn ? '+\$${v.toStringAsFixed(2)}' : '-\$${v.toStringAsFixed(2)}',
                                    style: TextStyle(color: isIn ? kGreen : kRed, fontWeight: FontWeight.bold)),
                                IconButton(
                                    icon: const Icon(Icons.close, size: 16, color: kTextDim),
                                    onPressed: () => _delete(r['id'] as int)),
                              ]),
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
  const AddEntrySheet({super.key, required this.db, this.profileId = 0});
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

  @override
  void initState() {
    super.initState();
    profileId = widget.profileId;
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
      } else if (k == '.') {
        if (!amountText.contains('.')) amountText += '.';
      } else if (amountText.length < 9) {
        if (amountText.contains('.') && amountText.length - amountText.indexOf('.') > 2) return;
        amountText += k;
      }
    });
  }

  Future<void> _save() async {
    final amount = double.tryParse(amountText) ?? 0;
    if (amount <= 0) return;
    await widget.db.insert('entries', {
      'ts': DateTime.now().millisecondsSinceEpoch ~/ 1000,
      'amount_cents': (amount * 100).round(),
      'kind': kind, 'category': category, 'note': noteCtrl.text,
      'profile_id': profileId,
    });
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
        if (profiles.isNotEmpty) ...[
          Align(alignment: Alignment.centerLeft,
              child: Text('Pile:',
                  style: TextStyle(fontSize: 12, color: kTextDim))),
          const SizedBox(height: 6),
          Wrap(
            spacing: 6, runSpacing: 6,
            children: [
              for (final pr in [
                {'id': 0, 'name': 'Personal'},
                ...profiles,
              ])
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
            child: const Text('Save entry', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
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