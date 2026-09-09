import 'package:flutter/material.dart';
import 'package:joosebooks_flutter/main.dart' show kTextDim;

/// P0 design tokens (imported values — keep in sync with main.dart until a
/// shared theme file exists; both read from one place at refactor time).
const kGoldChart = Color(0xFFD4A843);
const kGreenChart = Color(0xFF4CD964);
const kRedChart = Color(0xFFE65959);
const kDimChart = Color(0xFF3A3A44);

/// 12-month income/expense mini bar chart. Green bars grow UP from the
/// midline, red bars grow DOWN; months with nothing show a dim baseline tick.
/// Hand-painted (CustomPainter) — zero dependencies, P0 colors, scales to any
/// card width. Month initials (J F M A M J J A S O N D) render under the
/// bars as 12 Expanded cells in one Row — each cell is exactly one bar slot
/// wide, so letters are centered on their bars by construction (a single
/// letterSpacing string drifted off the slot geometry).
class MiniBarChart extends StatelessWidget {
  final List<Map<String, double>> buckets; // from monthlyByProfile()
  const MiniBarChart({super.key, required this.buckets});

  static const monthLetters = [
    'J', 'F', 'M', 'A', 'M', 'J', 'J', 'A', 'S', 'O', 'N', 'D'];

  @override
  Widget build(BuildContext context) {
    return Column(children: [
      Expanded(
        child: CustomPaint(
          painter: MiniBarChartPainter(buckets: buckets),
          size: Size.infinite,
        ),
      ),
      const SizedBox(height: 5),
      Row(children: [
        for (var m = 0; m < 12; m++)
          Expanded(
            child: Text(monthLetters[m],
                key: ValueKey('month-label-$m'),
                textAlign: TextAlign.center,
                style: const TextStyle(
                    fontSize: 9, color: kTextDim)),
          ),
      ]),
    ]);
  }
}

class MiniBarChartPainter extends CustomPainter {
  final List<Map<String, double>> buckets;
  MiniBarChartPainter({required this.buckets});

  /// Largest value across income+expenses — the chart's scale ceiling.
  double get maxVal {
    var m = 0.0;
    for (final b in buckets) {
      final i = b['income'] ?? 0.0;
      final e = b['expenses'] ?? 0.0;
      if (i > m) m = i;
      if (e > m) m = e;
    }
    return m;
  }

  @override
  void paint(Canvas canvas, Size size) {
    final scaleMax = maxVal;

    final n = buckets.length;
    final slot = size.width / n;
    final barW = slot * 0.55;
    final mid = size.height * 0.5;
    final maxBar = size.height * 0.42; // half-height available per direction

    // Dim midline baseline.
    final basePaint = Paint()
      ..color = kDimChart
      ..strokeWidth = 1;
    canvas.drawLine(Offset(0, mid), Offset(size.width, mid), basePaint);

    for (var m = 0; m < n; m++) {
      final cx = slot * m + slot / 2;
      final income = buckets[m]['income'] ?? 0.0;
      final expenses = buckets[m]['expenses'] ?? 0.0;
      if (income <= 0 && expenses <= 0) {
        // Empty month: dim tick on the baseline.
        canvas.drawLine(Offset(cx - 2, mid), Offset(cx + 2, mid),
            basePaint..strokeWidth = 2);
        continue;
      }
      if (income > 0) {
        final h = scaleMax == 0 ? 0.0 : (income / scaleMax) * maxBar;
        final rect = Rect.fromLTWH(cx - barW / 2, mid - h, barW, h);
        canvas.drawRRect(
            RRect.fromRectAndRadius(rect, const Radius.circular(2)),
            Paint()..color = kGreenChart);
      }
      if (expenses > 0) {
        final h = scaleMax == 0 ? 0.0 : (expenses / scaleMax) * maxBar;
        final rect = Rect.fromLTWH(cx - barW / 2, mid, barW, h);
        canvas.drawRRect(
            RRect.fromRectAndRadius(rect, const Radius.circular(2)),
            Paint()..color = kRedChart);
      }
    }
  }

  @override
  bool shouldRepaint(covariant MiniBarChartPainter old) =>
      old.buckets != buckets;
}

/// Chart card header total (used by Overview cards).
String money(double v) =>
    '\$${v.abs().toStringAsFixed(v.abs() >= 1000 ? 0 : 2)}';