import 'package:flutter/material.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:joosebooks_flutter/overview_content.dart' show OverviewContent;
import 'package:joosebooks_flutter/main.dart' show kGold, kSurface,
    DashboardPage, AddEntrySheet;
import 'db.dart';

/// Overview — the app's home. OverviewContent (overview_content.dart) is the
/// pure presentation (widget-testable, no db); this page loads data and wires
/// navigation. One card per pile (Personal first): the year's mini bar chart
/// + income/expenses/profit, so the CEO sees the SHAPE of the money before
/// drilling into the numbers. Tap a card → DashboardPage for that pile.
class OverviewPage extends StatefulWidget {
  final Database db;
  const OverviewPage({super.key, required this.db});
  @override
  State<OverviewPage> createState() => _OverviewPageState();
}

class _OverviewPageState extends State<OverviewPage> {
  late int year = DateTime.now().year;
  List<Map<String, Object?>> profiles = [];
  Map<int, List<Map<String, double>>> monthly = {}; // pid → 12 buckets
  Map<int, Map<String, double>> totals = {}; // pid → income/expenses/profit
  bool loading = true;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    profiles = await widget.db.query('profiles', orderBy: 'id');
    final out = <int, List<Map<String, double>>>{};
    final tot = <int, Map<String, double>>{};
    for (final pr in profiles) {
      final pid = pr['id'] as int;
      final buckets = await monthlyByProfile(widget.db, year, pid);
      out[pid] = buckets;
      double income = 0, expenses = 0;
      for (final b in buckets) {
        income += b['income']!;
        expenses += b['expenses']!;
      }
      tot[pid] = {
        'income': income, 'expenses': expenses, 'profit': income - expenses};
    }
    if (!mounted) return;
    setState(() {
      monthly = out;
      totals = tot;
      loading = false;
    });
  }

  Future<void> _openDashboard(int pid) async {
    await Navigator.push(context, MaterialPageRoute(
        builder: (_) => DashboardPage(db: widget.db, initialProfileId: pid)));
    _refresh(); // money may have changed while inside
  }

  @override
  Widget build(BuildContext context) {
    if (loading) {
      return const Scaffold(
          body: Center(child: CircularProgressIndicator(color: kGold)));
    }
    return OverviewContent(
      year: year,
      profiles: profiles,
      monthly: monthly,
      totals: totals,
      onOpenPile: (pid) => _openDashboard(pid),
      onQuickAdd: () => _openAddEntry(0),
      onPrevYear: () { year--; _refresh(); },
      onNextYear: () { year++; _refresh(); },
    );
  }

  Future<void> _openAddEntry(int pid) async {
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: kSurface,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => AddEntrySheet(db: widget.db, profileId: pid),
    );
    _refresh();
  }
}