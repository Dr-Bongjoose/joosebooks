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
  final db = await openDatabase(p.join(dir.path, 'joosebooks.db'), version: 1,
      onCreate: (db, v) => db.execute('''
        CREATE TABLE IF NOT EXISTS entries (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          ts INTEGER NOT NULL,
          amount_cents INTEGER NOT NULL,
          kind TEXT NOT NULL,
          category TEXT NOT NULL DEFAULT 'Other',
          note TEXT DEFAULT ''
        )'''));
  runApp(JooseBooksApp(db: db));
}

class JooseBooksApp extends StatelessWidget {
  final Database db;
  const JooseBooksApp({super.key, required this.db});

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
      home: DashboardPage(db: db),
      debugShowCheckedModeBanner: false,
    );
  }
}

class DashboardPage extends StatefulWidget {
  final Database db;
  const DashboardPage({super.key, required this.db});
  @override
  State<DashboardPage> createState() => _DashboardPageState();
}

class _DashboardPageState extends State<DashboardPage> {
  late int year = DateTime.now().year;
  Map<String, double>? summary;
  String? monthLine;
  List<Map<String, Object?>> entries = [];

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    final startY = DateTime(year).millisecondsSinceEpoch ~/ 1000;
    final endY = DateTime(year + 1).millisecondsSinceEpoch ~/ 1000;
    final rows = await widget.db.query('entries',
        where: 'ts >= ? AND ts < ?', whereArgs: [startY, endY], orderBy: 'ts DESC');
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

  Future<void> _delete(int id) async {
    await widget.db.delete('entries', where: 'id = ?', whereArgs: [id]);
    _refresh();
  }

  Future<void> _exportCsv() async {
    final rows = await widget.db.query('entries',
        where: 'ts >= ? AND ts < ?',
        whereArgs: [DateTime(year).millisecondsSinceEpoch ~/ 1000,
                    DateTime(year + 1).millisecondsSinceEpoch ~/ 1000],
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
    final file = File(p.join(dir.path, 'joosebooks_$year.csv'));
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
      builder: (_) => AddEntrySheet(db: widget.db),
    );
    _refresh();
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
                    style: TextStyle(fontSize: 22, color: kGold, fontWeight: FontWeight.bold)),
                const Spacer(),
                IconButton(onPressed: () { year--; _refresh(); }, icon: const Icon(Icons.chevron_left)),
                Text('$year', style: const TextStyle(fontSize: 22, color: kText)),
                IconButton(onPressed: () { year++; _refresh(); }, icon: const Icon(Icons.chevron_right)),
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
  const AddEntrySheet({super.key, required this.db});
  @override
  State<AddEntrySheet> createState() => _AddEntrySheetState();
}

class _AddEntrySheetState extends State<AddEntrySheet> {
  String kind = 'in';
  String amountText = '';
  String category = 'Other';
  final noteCtrl = TextEditingController();

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