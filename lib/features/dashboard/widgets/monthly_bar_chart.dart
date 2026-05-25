import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../../../core/theme.dart';
import '../../../data/models/monthly_energy.dart';

// ─── Public widget ─────────────────────────────────────────────────────────

/// Bar chart showing monthly kWh totals for a calendar year.
/// For the current year only elapsed months are shown; past years show all 12.
/// Data comes from GetChartByPlant (range "3"), filtered to [year].
class MonthlyEnergyBarChartCard extends StatefulWidget {
  final List<DailyEnergy> entries;

  /// The calendar year being displayed.
  final int year;
  final bool isLoading;
  final VoidCallback onPrevYear;

  /// null when [year] is the current calendar year.
  final VoidCallback? onNextYear;

  const MonthlyEnergyBarChartCard({
    super.key,
    required this.entries,
    required this.year,
    required this.isLoading,
    required this.onPrevYear,
    this.onNextYear,
  });

  @override
  State<MonthlyEnergyBarChartCard> createState() =>
      _MonthlyEnergyBarChartCardState();
}

class _MonthlyEnergyBarChartCardState
    extends State<MonthlyEnergyBarChartCard> {
  int? _selectedIdx;

  // ── Derived stats ─────────────────────────────────────────────────────────

  double get _total => widget.entries.fold(0, (s, e) => s + e.kwh);

  double get _average {
    final filled = widget.entries.where((e) => e.kwh > 0).toList();
    if (filled.isEmpty) return 0;
    return _total / filled.length;
  }

  DailyEnergy? get _best => widget.entries.isEmpty
      ? null
      : widget.entries.reduce((a, b) => a.kwh > b.kwh ? a : b);

  int get _bestIdx {
    if (widget.entries.isEmpty) return -1;
    int best = 0;
    for (int i = 1; i < widget.entries.length; i++) {
      if (widget.entries[i].kwh > widget.entries[best].kwh) best = i;
    }
    return best;
  }

  // ── Helpers ───────────────────────────────────────────────────────────────

  static const _monthAbbr = [
    'Jan','Feb','Mar','Apr','May','Jun',
    'Jul','Aug','Sep','Oct','Nov','Dec',
  ];

  void _onTap(double dx, double totalWidth) {
    const lp = _BarChartPainter.lp;
    const rp = _BarChartPainter.rp;
    final chartW = totalWidth - lp - rp;
    if (chartW <= 0 || widget.entries.isEmpty) return;

    final n     = widget.entries.length;
    final slotW = chartW / n;
    final relX  = dx - lp;
    if (relX < 0 || relX > chartW) {
      setState(() => _selectedIdx = null);
      return;
    }
    final idx = (relX / slotW).floor().clamp(0, n - 1);
    setState(() => _selectedIdx = idx);
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.divider),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildHeader(),
          if (widget.isLoading)
            const SizedBox(
              height: 160,
              child: Center(
                child: CircularProgressIndicator(
                  color: AppColors.accent,
                  strokeWidth: 2,
                ),
              ),
            )
          else if (widget.entries.isEmpty)
            const SizedBox(
              height: 160,
              child: Center(
                child: Text(
                  'No data available',
                  style: TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 12,
                  ),
                ),
              ),
            )
          else ...[
            _buildSummaryRow(),
            _buildChart(),
            _buildSelectedTooltip(),
          ],
          const SizedBox(height: 14),
        ],
      ),
    );
  }

  Widget _buildHeader() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 12, 0),
      child: Row(
        children: [
          const Icon(Icons.bar_chart_rounded, color: AppColors.accent, size: 16),
          const SizedBox(width: 8),
          const Text(
            'Annual Generation',
            style: TextStyle(
              color: AppColors.textPrimary,
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
          ),
          const Spacer(),
          // Year navigation
          _NavArrow(
            icon: Icons.chevron_left_rounded,
            onTap: widget.isLoading ? null : widget.onPrevYear,
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 6),
            child: Text(
              widget.year.toString(),
              style: const TextStyle(
                color: AppColors.textSecondary,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          _NavArrow(
            icon: Icons.chevron_right_rounded,
            onTap: widget.isLoading ? null : widget.onNextYear,
          ),
        ],
      ),
    );
  }

  Widget _buildSummaryRow() {
    final best = _best;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      child: Row(
        children: [
          _StatChip(
            label: 'Total',
            value: _total >= 1000
                ? '${(_total / 1000).toStringAsFixed(2)} MWh'
                : '${_total.toStringAsFixed(0)} kWh',
            color: AppColors.accent,
          ),
          const SizedBox(width: 8),
          _StatChip(
            label: 'Avg/mo',
            value: '${_average.toStringAsFixed(0)} kWh',
            color: AppColors.green,
          ),
          const SizedBox(width: 8),
          if (best != null)
            _StatChip(
              label: 'Best',
              value: '${_monthAbbr[best.date.month - 1]}  ·  ${best.kwh.toStringAsFixed(0)} kWh',
              color: const Color(0xFF818CF8),
            ),
        ],
      ),
    );
  }

  Widget _buildChart() {
    final today = DateTime.now();

    return Padding(
      // Left padding gives breathing room between y-axis labels and card edge.
      // Top padding leaves space for the extrapolation label drawn above bars.
      padding: const EdgeInsets.fromLTRB(8, 8, 0, 0),
      child: LayoutBuilder(builder: (ctx, constraints) {
        return GestureDetector(
          onTapDown:  (d) => _onTap(d.localPosition.dx, constraints.maxWidth),
          onPanUpdate: (d) => _onTap(d.localPosition.dx, constraints.maxWidth),
          onTapUp:    (_) => setState(() => _selectedIdx = null),
          onPanEnd:   (_) => setState(() => _selectedIdx = null),
          child: SizedBox(
            height: 155,
            width: double.infinity,
            child: CustomPaint(
              painter: _BarChartPainter(
                entries:     widget.entries,
                today:       today,
                selectedIdx: _selectedIdx,
                average:     _average,
                bestIdx:     _bestIdx,
              ),
            ),
          ),
        );
      }),
    );
  }

  Widget _buildSelectedTooltip() {
    if (_selectedIdx == null ||
        _selectedIdx! >= widget.entries.length) {
      return const SizedBox.shrink();
    }
    final entry = widget.entries[_selectedIdx!];
    final isCurrent = entry.date.year == DateTime.now().year &&
        entry.date.month == DateTime.now().month;

    final label =
        '${_monthAbbr[entry.date.month - 1]} ${entry.date.year}';
    final kwhStr = isCurrent
        ? '${entry.kwh.toStringAsFixed(1)} kWh  (partial)'
        : '${entry.kwh.toStringAsFixed(1)} kWh';

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 6, 16, 0),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 8, height: 8,
            decoration: BoxDecoration(
              color: isCurrent ? AppColors.accent : AppColors.green,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 7),
          Text(
            '$label  ·  $kwhStr',
            style: const TextStyle(
              color: AppColors.textSecondary,
              fontSize: 11,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}

// ─── CustomPainter ─────────────────────────────────────────────────────────

class _BarChartPainter extends CustomPainter {
  final List<DailyEnergy> entries;
  final DateTime today;
  final int? selectedIdx;
  final double average;
  final int bestIdx;

  static const lp = 44.0; // left pad (y-axis labels)
  static const rp = 8.0;
  static const tp = 20.0; // extra headroom for the extrapolation label
  static const bp = 22.0; // bottom pad (x-axis month labels)

  static const _monthAbbr = [
    'Jan','Feb','Mar','Apr','May','Jun',
    'Jul','Aug','Sep','Oct','Nov','Dec',
  ];

  const _BarChartPainter({
    required this.entries,
    required this.today,
    required this.selectedIdx,
    required this.average,
    required this.bestIdx,
  });

  // ── Helpers ───────────────────────────────────────────────────────────────

  /// Full-month extrapolated kWh for the current (partial) month.
  /// Returns [e.kwh] unchanged for every other entry or if ≥ 95 % through.
  double _estKwh(DailyEnergy e) {
    if (e.date.year != today.year || e.date.month != today.month) return e.kwh;
    final daysInMonth = DateTime(today.year, today.month + 1, 0).day;
    final fraction    = today.day / daysInMonth;
    if (fraction >= 0.95 || e.kwh <= 0) return e.kwh;
    return e.kwh / fraction;
  }

  @override
  void paint(Canvas canvas, Size size) {
    if (entries.isEmpty) return;
    final chart = Rect.fromLTRB(lp, tp, size.width - rp, size.height - bp);

    final maxKwh = entries.map((e) => e.kwh).reduce(math.max).clamp(1.0, double.infinity);
    final scaledMax = maxKwh * 1.15; // 15 % headroom

    _drawGridAndYLabels(canvas, chart, scaledMax);
    _drawBars(canvas, chart, scaledMax);
    if (average > 0) _drawAverageLine(canvas, chart, scaledMax);
    _drawXLabels(canvas, chart);
  }

  void _drawGridAndYLabels(Canvas canvas, Rect chart, double scaledMax) {
    final gridPaint = Paint()
      ..color = AppColors.divider.withValues(alpha: 0.45)
      ..strokeWidth = 0.5;

    for (int g = 1; g <= 3; g++) {
      final y = chart.bottom - (g / 3) * chart.height;
      canvas.drawLine(Offset(chart.left, y), Offset(chart.right, y), gridPaint);

      final kwh = scaledMax / 3 * g;
      // Show as MWh when ≥ 1000
      final label = kwh >= 1000
          ? '${(kwh / 1000).toStringAsFixed(1)}M'
          : kwh.toStringAsFixed(0);
      _label(canvas, label, Offset(2, y - 6), maxWidth: lp - 6);
    }
  }

  void _drawBars(Canvas canvas, Rect chart, double scaledMax) {
    final n     = entries.length;
    final slotW = chart.width / n;
    final barW  = (slotW * 0.65).clamp(4.0, 20.0);
    final gap   = (slotW - barW) / 2;

    for (int i = 0; i < n; i++) {
      final e          = entries[i];
      final isCurrent  = e.date.year == today.year && e.date.month == today.month;
      // Best-month highlight only applies to completed (non-current) months
      final isBest     = !isCurrent && i == bestIdx;
      final isSelected = i == selectedIdx;
      final kwh        = e.kwh;
      final barH       = (kwh / scaledMax) * chart.height;

      final barLeft  = chart.left + i * slotW + gap;
      final barRight = barLeft + barW;
      final barTop   = chart.bottom - barH;
      final radius   = math.min(barW / 2, 4.0);

      // ── Bar colour ──────────────────────────────────────────────────────────
      final Color baseColor = isCurrent
          ? AppColors.accent
          : isBest
              ? const Color(0xFF818CF8) // purple for best past month
              : AppColors.green;
      final color = baseColor.withValues(alpha: isSelected ? 1.0 : 0.80);

      // ── Draw solid bar (or zero-stub) ───────────────────────────────────────
      if (barH < 1.5) {
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromLTRB(barLeft, chart.bottom - 2, barRight, chart.bottom),
            const Radius.circular(1),
          ),
          Paint()..color = AppColors.divider.withValues(alpha: 0.3),
        );
      } else {
        canvas.drawRRect(
          RRect.fromRectAndCorners(
            Rect.fromLTRB(barLeft, barTop, barRight, chart.bottom),
            topLeft:  Radius.circular(radius),
            topRight: Radius.circular(radius),
          ),
          Paint()..color = color,
        );

        if (isSelected) {
          canvas.drawRRect(
            RRect.fromRectAndCorners(
              Rect.fromLTRB(barLeft - 0.75, barTop - 0.75,
                  barRight + 0.75, chart.bottom + 0.75),
              topLeft:  Radius.circular(radius + 0.75),
              topRight: Radius.circular(radius + 0.75),
            ),
            Paint()
              ..color       = color
              ..style       = PaintingStyle.stroke
              ..strokeWidth = 1.0,
          );
        }
      }

      // ── Estimate label (current partial month only) ─────────────────────────
      // Shows the projected full-month total above the bar in purple so it
      // reads as a forecast value, distinct from the solid orange bar.
      if (isCurrent) {
        final daysInMonth = DateTime(today.year, today.month + 1, 0).day;
        final fraction    = today.day / daysInMonth;
        if (fraction < 0.95 && kwh > 0) {
          final estKwh  = kwh / fraction;
          final estLabel = estKwh >= 1000
              ? '~${(estKwh / 1000).toStringAsFixed(1)}M'
              : '~${estKwh.toStringAsFixed(0)}';

          // Centre the label horizontally over the bar
          const labelW = 44.0;
          final labelX = barLeft + barW / 2 - labelW / 2;
          final labelY = math.max(tp + 1.0, (barH < 1.5 ? chart.bottom - 2.0 : barTop) - 12.0);

          _label(
            canvas,
            estLabel,
            Offset(labelX, labelY),
            maxWidth: labelW,
            align: TextAlign.center,
            color: const Color(0xFF818CF8), // purple — distinct from the orange bar
          );
        }
      }
    }
  }

  void _drawAverageLine(Canvas canvas, Rect chart, double scaledMax) {
    if (average <= 0 || average > scaledMax) return;
    final y = chart.bottom - (average / scaledMax) * chart.height;
    final p = Paint()
      ..color = AppColors.accent.withValues(alpha: 0.35)
      ..strokeWidth = 0.8;

    double x = chart.left;
    while (x < chart.right) {
      canvas.drawLine(Offset(x, y), Offset(math.min(x + 4, chart.right), y), p);
      x += 8;
    }
  }

  void _drawXLabels(Canvas canvas, Rect chart) {
    final n     = entries.length;
    final slotW = chart.width / n;

    // Show every label when ≤ 6 bars; otherwise every other label to avoid overlap
    final step = n <= 6 ? 1 : 2;

    for (int i = 0; i < n; i++) {
      if (i % step != 0) continue;
      final e   = entries[i];
      final cx  = chart.left + i * slotW + slotW / 2;
      _label(
        canvas,
        _monthAbbr[e.date.month - 1],
        Offset(cx - 10, chart.bottom + 5),
        maxWidth: 22,
        align: TextAlign.center,
      );
    }
  }

  void _label(Canvas canvas, String text, Offset offset,
      {double maxWidth = 40, TextAlign align = TextAlign.right, Color? color}) {
    (TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(
          color: color ?? const Color(0xFF4B5E7A),
          fontSize: 9,
          fontFamily: 'Outfit',
        ),
      ),
      textDirection: TextDirection.ltr,
      textAlign: align,
    )..layout(maxWidth: maxWidth))
        .paint(canvas, offset);
  }

  @override
  bool shouldRepaint(_BarChartPainter old) =>
      old.entries != entries ||
      old.selectedIdx != selectedIdx ||
      old.average != average ||
      old.bestIdx != bestIdx;
}

// ─── Helper widgets ────────────────────────────────────────────────────────

class _StatChip extends StatelessWidget {
  final String label;
  final String value;
  final Color color;

  const _StatChip({
    required this.label,
    required this.value,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.25)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label.toUpperCase(),
            style: TextStyle(
              color: color.withValues(alpha: 0.7),
              fontSize: 9,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.8,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            value,
            style: TextStyle(
              color: color,
              fontSize: 12,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class _NavArrow extends StatelessWidget {
  final IconData icon;
  final VoidCallback? onTap;

  const _NavArrow({required this.icon, this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.all(4),
        child: Icon(
          icon,
          size: 18,
          color: onTap != null ? AppColors.textSecondary : AppColors.divider,
        ),
      ),
    );
  }
}
