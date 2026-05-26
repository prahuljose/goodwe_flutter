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

  static const lp = 36.0; // left pad (y-axis labels)
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

  @override
  void paint(Canvas canvas, Size size) {
    if (entries.isEmpty) return;
    final chart = Rect.fromLTRB(lp, tp, size.width - rp, size.height - bp);

    // Compute the extrapolated estimate for the current partial month so the
    // projection block always fits inside the chart area.
    double estForScale(DailyEnergy e) {
      if (e.date.year != today.year || e.date.month != today.month) return e.kwh;
      final days = DateTime(today.year, today.month + 1, 0).day;
      final frac = today.day / days;
      return (frac < 0.95 && e.kwh > 0 && today.day >= 3) ? e.kwh / frac : e.kwh;
    }

    final maxKwh = entries.map((e) => math.max(e.kwh, estForScale(e))).reduce(math.max).clamp(1.0, double.infinity);
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

      // ── Projected-remainder block drawn FIRST (behind the orange bar) ─────────
      // Extends from estTop all the way to chart.bottom so the orange bar sits
      // flush on top — no gap, looks like a single two-tone bar.
      if (isCurrent) {
        final daysInMonth = DateTime(today.year, today.month + 1, 0).day;
        final fraction    = today.day / daysInMonth;
        if (fraction < 0.95 && kwh > 0 && today.day >= 3) {
          final estKwh = kwh / fraction;
          final estH   = (estKwh / scaledMax) * chart.height;
          final estTop = math.max(chart.top, chart.bottom - estH);
          if (estTop < (barH < 1.5 ? chart.bottom - 2.0 : barTop) - 2) {
            final blockRect = RRect.fromRectAndCorners(
              Rect.fromLTRB(barLeft, estTop, barRight, chart.bottom),
              topLeft:  Radius.circular(radius),
              topRight: Radius.circular(radius),
            );

            // Solid fill
            canvas.drawRRect(
              blockRect,
              Paint()..color = const Color(0xFF818CF8).withValues(alpha: 0.22),
            );

            // Diagonal hatch lines — only over the VISIBLE purple portion
            // (estTop → solidTop). The orange bar covers everything below
            // solidTop, so hatching there would bleed through its alpha.
            final solidTop  = barH < 1.5 ? chart.bottom - 2.0 : barTop;
            final hatchRect = RRect.fromRectAndCorners(
              Rect.fromLTRB(barLeft, estTop, barRight, solidTop),
              topLeft:  Radius.circular(radius),
              topRight: Radius.circular(radius),
            );
            canvas.save();
            canvas.clipRRect(hatchRect);
            final hatchPaint = Paint()
              ..color       = const Color(0xFF818CF8).withValues(alpha: 0.45)
              ..strokeWidth = 0.8
              ..style       = PaintingStyle.stroke;
            const spacing = 4.0;
            final hatchH  = solidTop - estTop;
            for (double d = -hatchH; d < (barRight - barLeft); d += spacing) {
              canvas.drawLine(
                Offset(barLeft + d, estTop),
                Offset(barLeft + d + hatchH, solidTop),
                hatchPaint,
              );
            }
            canvas.restore();
          }
        }
      }

      // ── Draw solid bar (or zero-stub) on top ────────────────────────────────
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

      // ── Estimate label (current partial month only) ──────────────────────────
      if (isCurrent) {
        final daysInMonth = DateTime(today.year, today.month + 1, 0).day;
        final fraction    = today.day / daysInMonth;
        if (fraction < 0.95 && kwh > 0 && today.day >= 3) {
          final estKwh = kwh / fraction;
          final estTop = math.max(chart.top, chart.bottom - (estKwh / scaledMax) * chart.height);

          // Estimate label — measure real text width first, then pin centre
          // exactly on the bar centre so it's always properly aligned.
          final estLabel = estKwh >= 1000
              ? '~${(estKwh / 1000).toStringAsFixed(1)}M'
              : '~${estKwh.toStringAsFixed(0)}';
          final tp2 = TextPainter(
            text: TextSpan(
              text: estLabel,
              style: const TextStyle(
                color: Color(0xFF818CF8),
                fontSize: 9,
                fontFamily: 'Outfit',
                fontWeight: FontWeight.w600,
              ),
            ),
            textDirection: TextDirection.ltr,
          )..layout();
          final barCenter = barLeft + barW / 2;
          final labelY    = math.max(tp + 1.0, estTop - 11.0);
          tp2.paint(canvas, Offset(barCenter - tp2.width / 2, labelY));
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
      final e    = entries[i];
      final cx   = chart.left + i * slotW + slotW / 2;
      final tp   = TextPainter(
        text: TextSpan(
          text: _monthAbbr[e.date.month - 1],
          style: const TextStyle(
            color: Color(0xFF4B5E7A),
            fontSize: 9,
            fontFamily: 'Outfit',
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, Offset(cx - tp.width / 2, chart.bottom + 5));
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
