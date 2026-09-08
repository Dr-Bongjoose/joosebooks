import 'package:flutter/material.dart';
import 'package:joosebooks_flutter/charts.dart';
import 'package:joosebooks_flutter/main.dart' show kSurface, kSurface2,
    kGold, kText, kTextDim;

/// Pure presentation for the Overview home — one card per pile (Personal
/// first): the year's mini bar chart + income/expenses/profit. No database
/// access, so widget tests render it directly without the fake-async/ffi
/// wedge. Data comes in precomputed; callbacks bubble up to the owner page.
class OverviewContent extends StatelessWidget {
  final int year;
  final List<Map<String, Object?>> profiles;
  final Map<int, List<Map<String, double>>> monthly;
  final Map<int, Map<String, double>> totals;
  final ValueChanged<int> onOpenPile;
  final VoidCallback onQuickAdd;
  final VoidCallback onPrevYear;
  final VoidCallback onNextYear;

  const OverviewContent({
    super.key,
    required this.year,
    required this.profiles,
    required this.monthly,
    required this.totals,
    required this.onOpenPile,
    required this.onQuickAdd,
    required this.onPrevYear,
    required this.onNextYear,
  });

  @override
  Widget build(BuildContext context) {
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
                const Spacer(),
                IconButton(
                    onPressed: onPrevYear, icon: const Icon(Icons.chevron_left)),
                Text('$year', style: const TextStyle(fontSize: 22, color: kText)),
                IconButton(
                    onPressed: onNextYear, icon: const Icon(Icons.chevron_right)),
              ]),
              const SizedBox(height: 4),
              Text('The year at a glance — tap a pile to see its numbers',
                  style: const TextStyle(fontSize: 12, color: kTextDim)),
              const SizedBox(height: 10),
              Expanded(
                child: profiles.isEmpty
                    ? const Center(child: Text('No piles yet.',
                        style: TextStyle(color: kTextDim)))
                    : ListView.builder(
                        itemCount: profiles.length,
                        itemBuilder: (_, i) {
                          final pr = profiles[i];
                          final pid = pr['id'] as int;
                          return ProfileCard(
                            name: pr['name'] as String,
                            isPersonal: pid == 0,
                            buckets: monthly[pid]!,
                            totals: totals[pid]!,
                            onTap: () => onOpenPile(pid),
                          );
                        }),
              ),
              const SizedBox(height: 8),
              // Quick add is the FAB's label twin; FAB sits bottom-right, so
              // pad the button clear of it instead of fighting for the corner.
              Padding(
                padding: const EdgeInsets.only(right: 72),
                child: OutlinedButton.icon(
                  onPressed: onQuickAdd,
                  icon: const Icon(Icons.add, color: kGold),
                  label: const Text('Quick add', style: TextStyle(color: kGold)),
                  style: OutlinedButton.styleFrom(
                      side: const BorderSide(color: kGold),
                      backgroundColor: kSurface2,
                      minimumSize: const Size(0, 44)),
                ),
              ),
            ],
          ),
        ),
      ),
      floatingActionButton: FloatingActionButton(
        backgroundColor: kGold,
        foregroundColor: const Color(0xFF141210),
        onPressed: onQuickAdd,
        child: const Icon(Icons.add, size: 36),
      ),
    );
  }
}

/// One pile's year card: name, profit, 12-month chart, in/out totals.
class ProfileCard extends StatelessWidget {
  final String name;
  final bool isPersonal;
  final List<Map<String, double>> buckets;
  final Map<String, double> totals;
  final VoidCallback onTap;
  const ProfileCard({
    super.key,
    required this.name,
    required this.isPersonal,
    required this.buckets,
    required this.totals,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final income = totals['income']!;
    final expenses = totals['expenses']!;
    final profit = totals['profit']!;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
            color: kSurface,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.white10)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Text(isPersonal ? '👤' : '🏢', style: const TextStyle(fontSize: 15)),
            const SizedBox(width: 6),
            Text(name,
                style: TextStyle(
                    fontSize: 15,
                    color: isPersonal ? kText : kGold,
                    fontWeight: FontWeight.bold)),
            const Spacer(),
            Text('profit ${profit < 0 ? '-' : ''}\$${profit.abs().toStringAsFixed(2)}',
                style: TextStyle(
                    fontSize: 13,
                    color: profit >= 0 ? const Color(0xFF4CD964) : const Color(0xFFE65959),
                    fontWeight: FontWeight.bold)),
            const SizedBox(width: 4),
            const Icon(Icons.chevron_right, size: 16, color: kTextDim),
          ]),
          const SizedBox(height: 10),
          SizedBox(height: 64, width: double.infinity,
              child: MiniBarChart(buckets: buckets)),
          const SizedBox(height: 10),
          Row(children: [
            Text('in \$${income.toStringAsFixed(2)}',
                style: const TextStyle(fontSize: 12, color: Color(0xFF4CD964))),
            const SizedBox(width: 14),
            Text('out \$${expenses.toStringAsFixed(2)}',
                style: const TextStyle(fontSize: 12, color: Color(0xFFE65959))),
          ]),
          const SizedBox(height: 6),
          // Month initials on their own centered line — inside a tight Row
          // they overflowed (seen in screenshot, analyzer can't catch layout).
          Text('J F M A M J J A S O N D',
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 9, letterSpacing: 6, color: kTextDim)),
        ]),
      ),
    );
  }
}