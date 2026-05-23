import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../../../core/theme.dart';
import '../../../data/models/station_monitor.dart';

// ─── Public widget ─────────────────────────────────────────────────────────────

class PowerCurveCard extends StatefulWidget {
  final List<PacSample> samples;
  final String dateLabel;

  const PowerCurveCard({
    super.key,
    required this.samples,
    required this.dateLabel,
  });

  @override
  State<PowerCurveCard> createState() => _PowerCurveCardState();
}

class _PowerCurveCardState extends State<PowerCurveCard> {
  int? _hoverIdx;

  // Trim the full 288-entry day down to just the generation window
  // (first non-zero → last non-zero, plus a small buffer either side)
  List<PacSample> get _visible {
    final s = widget.samples;
    if (s.isEmpty) return s;
    final first = s.indexWhere((x) => x.pac > 0);
    final last = s.lastIndexWhere((x) => x.pac > 0);
    if (first == -1) return const []; // all zeros — nothing to draw
    return s.sublist(
      math.max(0, first - 3),
      math.min(s.length - 1, last + 3) + 1,
    );
  }

  PacSample? get _peak => widget.samples.isEmpty
      ? null
      : widget.samples.reduce((a, b) => a.pac > b.pac ? a : b);

  @override
  Widget build(BuildContext context) {
    final visible = _visible;
    final peak = _peak;

    if (visible.isEmpty || peak == null || peak.pac == 0) {
      return const SizedBox.shrink();
    }

    return Container(
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.divider),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildHeader(peak),
          LayoutBuilder(builder: (ctx, constraints) {
            return GestureDetector(
              onTapDown: (d) =>
                  _setHover(d.localPosition.dx, constraints.maxWidth, visible),
              onPanUpdate: (d) =>
                  _setHover(d.localPosition.dx, constraints.maxWidth, visible),
              onPanEnd: (_) => setState(() => _hoverIdx = null),
              onTapUp: (_) => setState(() => _hoverIdx = null),
              child: SizedBox(
                height: 200,
                width: double.infinity,
                child: CustomPaint(
                  painter: _ChartPainter(
                    samples: visible,
                    hoverIdx: _hoverIdx,
                    peak: peak,
                  ),
                ),
              ),
            );
          }),
          _buildFooter(visible),
          const SizedBox(height: 14),
        ],
      ),
    );
  }

  void _setHover(double dx, double totalWidth, List<PacSample> samples) {
    const lp = _ChartPainter.lp;
    const rp = _ChartPainter.rp;
    final w = totalWidth - lp - rp;
    if (w <= 0 || samples.length < 2) return;
    final clamped = (dx - lp).clamp(0.0, w);
    final idx = ((clamped / w) * (samples.length - 1))
        .round()
        .clamp(0, samples.length - 1);
    setState(() => _hoverIdx = idx);
  }

  Widget _buildHeader(PacSample peak) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
      child: Row(
        children: [
          const Icon(Icons.show_chart_rounded,
              color: AppColors.accent, size: 16),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'Power Curve  ·  ${widget.dateLabel}',
              style: const TextStyle(
                color: AppColors.textPrimary,
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: AppColors.accent.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text(
              'Peak  ${(peak.pac / 1000).toStringAsFixed(2)} kW',
              style: const TextStyle(
                color: AppColors.accent,
                fontSize: 10,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFooter(List<PacSample> visible) {
    final nonZero = visible.where((s) => s.pac > 0).toList();
    if (nonZero.isEmpty) return const SizedBox.shrink();

    final start = nonZero.first.time;
    final end = nonZero.last.time;
    final hrs = end.difference(start).inMinutes / 60.0;

    String p(int n) => n.toString().padLeft(2, '0');

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 6, 16, 0),
      child: Row(
        children: [
          const Icon(Icons.schedule_outlined,
              color: AppColors.textSecondary, size: 12),
          const SizedBox(width: 5),
          Text(
            '${p(start.hour)}:${p(start.minute)} → '
            '${p(end.hour)}:${p(end.minute)}  '
            '(${hrs.toStringAsFixed(1)} hrs generating)',
            style: const TextStyle(
                color: AppColors.textSecondary, fontSize: 11),
          ),
        ],
      ),
    );
  }
}

// ─── CustomPainter ─────────────────────────────────────────────────────────────

class _ChartPainter extends CustomPainter {
  final List<PacSample> samples;
  final int? hoverIdx;
  final PacSample peak;

  // Exposed as constants so the parent widget can use them for hit-testing
  static const lp = 44.0; // left pad  (y-axis labels)
  static const rp = 12.0; // right pad
  static const tp = 14.0; // top pad
  static const bp = 28.0; // bottom pad (x-axis labels)

  const _ChartPainter({
    required this.samples,
    required this.hoverIdx,
    required this.peak,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (samples.length < 2) return;

    final chart = Rect.fromLTRB(lp, tp, size.width - rp, size.height - bp);
    final maxPac = samples.map((s) => s.pac).reduce(math.max);
    if (maxPac == 0) return;

    // Map sample index → canvas Offset
    Offset pt(int i) => Offset(
          chart.left + (i / (samples.length - 1)) * chart.width,
          chart.bottom - (samples[i].pac / maxPac) * chart.height,
        );

    final pts = List.generate(samples.length, pt);

    _drawGridAndLabels(canvas, chart, maxPac);
    _drawXLabels(canvas, chart);
    _drawArea(canvas, chart, pts);
    _drawLine(canvas, pts);
    _drawPeakMarker(canvas, pts);
    if (hoverIdx != null) _drawHover(canvas, chart, pts);
  }

  // ── Grid lines + Y-axis labels ─────────────────────────────────────────────

  void _drawGridAndLabels(Canvas canvas, Rect chart, double maxPac) {
    final gridPaint = Paint()
      ..color = AppColors.divider.withValues(alpha: 0.45)
      ..strokeWidth = 0.5;

    for (int g = 1; g <= 4; g++) {
      final y = chart.bottom - (g / 4) * chart.height;
      canvas.drawLine(Offset(chart.left, y), Offset(chart.right, y), gridPaint);

      final kw = maxPac / 4 * g / 1000;
      final label = kw >= 1.0
          ? '${kw.toStringAsFixed(1)}kW'
          : '${(kw * 1000).toStringAsFixed(0)}W';
      _label(canvas, label, Offset(0, y - 6), maxWidth: lp - 4,
          align: TextAlign.right);
    }
  }

  // ── X-axis time labels (every 2 h) ────────────────────────────────────────

  void _drawXLabels(Canvas canvas, Rect chart) {
    final tStart = samples.first.time;
    final tEnd = samples.last.time;
    final totalMins = tEnd.difference(tStart).inMinutes;
    if (totalMins == 0) return;

    final gridPaint = Paint()
      ..color = AppColors.divider.withValues(alpha: 0.45)
      ..strokeWidth = 0.5;

    for (int h = 0; h <= 24; h += 2) {
      final tick =
          DateTime(tStart.year, tStart.month, tStart.day, h);
      if (tick.isBefore(tStart) || tick.isAfter(tEnd)) continue;

      final frac = tick.difference(tStart).inMinutes / totalMins;
      final x = chart.left + frac * chart.width;

      canvas.drawLine(Offset(x, chart.bottom),
          Offset(x, chart.bottom + 4), gridPaint);
      _label(
        canvas,
        '${h.toString().padLeft(2, '0')}:00',
        Offset(x - 14, chart.bottom + 6),
        maxWidth: 30,
        align: TextAlign.center,
      );
    }
  }

  // ── Gradient area fill ─────────────────────────────────────────────────────

  void _drawArea(Canvas canvas, Rect chart, List<Offset> pts) {
    final fill = Path()
      ..moveTo(pts.first.dx, chart.bottom)
      ..lineTo(pts.first.dx, pts.first.dy);

    for (int i = 0; i < pts.length - 1; i++) {
      final mid = Offset(
        (pts[i].dx + pts[i + 1].dx) / 2,
        (pts[i].dy + pts[i + 1].dy) / 2,
      );
      fill.quadraticBezierTo(pts[i].dx, pts[i].dy, mid.dx, mid.dy);
    }
    fill
      ..lineTo(pts.last.dx, pts.last.dy)
      ..lineTo(pts.last.dx, chart.bottom)
      ..close();

    canvas.drawPath(
      fill,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            AppColors.accent.withValues(alpha: 0.28),
            AppColors.accent.withValues(alpha: 0.02),
          ],
        ).createShader(chart),
    );
  }

  // ── Smooth line ────────────────────────────────────────────────────────────

  void _drawLine(Canvas canvas, List<Offset> pts) {
    final line = Path()..moveTo(pts.first.dx, pts.first.dy);
    for (int i = 0; i < pts.length - 1; i++) {
      final mid = Offset(
        (pts[i].dx + pts[i + 1].dx) / 2,
        (pts[i].dy + pts[i + 1].dy) / 2,
      );
      line.quadraticBezierTo(pts[i].dx, pts[i].dy, mid.dx, mid.dy);
    }
    line.lineTo(pts.last.dx, pts.last.dy);

    canvas.drawPath(
      line,
      Paint()
        ..color = AppColors.accent
        ..strokeWidth = 2.0
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );
  }

  // ── Peak dot + dashed drop-line ────────────────────────────────────────────

  void _drawPeakMarker(Canvas canvas, List<Offset> pts) {
    final idx = samples.indexWhere((s) => s.pac == peak.pac);
    if (idx < 0) return;
    final pp = pts[idx];

    // Dashed vertical drop
    final dashPaint = Paint()
      ..color = AppColors.accent.withValues(alpha: 0.25)
      ..strokeWidth = 1;
    double y = pp.dy + 8;
    while (y < pts.first.dy.clamp(pp.dy, double.infinity) ||
        y < canvas.getSaveCount().toDouble()) {
      // Simple vertical dashes from peak down to bottom of last point area
      break; // handled below
    }
    // Re-implement cleanly
    y = pp.dy + 8;
    final bottom =
        pts.reduce((a, b) => a.dy > b.dy ? a : b).dy + 20;
    while (y < bottom) {
      canvas.drawLine(
          Offset(pp.dx, y), Offset(pp.dx, math.min(y + 4, bottom)), dashPaint);
      y += 8;
    }

    canvas.drawCircle(pp, 5.5, Paint()..color = AppColors.accent);
    canvas.drawCircle(pp, 3, Paint()..color = Colors.white);
  }

  // ── Hover crosshair + tooltip ──────────────────────────────────────────────

  void _drawHover(Canvas canvas, Rect chart, List<Offset> pts) {
    final idx = hoverIdx!.clamp(0, pts.length - 1);
    final hp = pts[idx];
    final hs = samples[idx];

    // Vertical rule
    canvas.drawLine(
      Offset(hp.dx, chart.top),
      Offset(hp.dx, chart.bottom),
      Paint()
        ..color = Colors.white.withValues(alpha: 0.1)
        ..strokeWidth = 1,
    );

    // Dot rings
    canvas.drawCircle(hp, 8, Paint()..color = AppColors.card);
    canvas.drawCircle(hp, 6, Paint()..color = AppColors.accent);
    canvas.drawCircle(hp, 3, Paint()..color = Colors.white);

    // Tooltip
    final kw = hs.pac / 1000;
    final t = hs.time;
    final timeStr =
        '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';
    final valStr =
        kw >= 1 ? '${kw.toStringAsFixed(2)} kW' : '${hs.pac.toStringAsFixed(0)} W';

    const hPad = 8.0;
    const vPad = 5.0;

    final tp = TextPainter(
      text: TextSpan(
        children: [
          TextSpan(
            text: '$timeStr  ',
            style: const TextStyle(
                color: AppColors.textSecondary,
                fontSize: 10,
                fontWeight: FontWeight.w500),
          ),
          TextSpan(
            text: valStr,
            style: const TextStyle(
                color: Colors.white,
                fontSize: 10,
                fontWeight: FontWeight.w700),
          ),
        ],
      ),
      textDirection: TextDirection.ltr,
    )..layout(maxWidth: 180);

    final tw = tp.width;
    final th = tp.height;

    double tx = hp.dx - tw / 2 - hPad;
    tx = tx.clamp(chart.left, chart.right - tw - hPad * 2);
    final ty = math.max(chart.top + 2, hp.dy - th - vPad * 2 - 14);

    final bgRect = RRect.fromRectAndRadius(
      Rect.fromLTWH(tx, ty, tw + hPad * 2, th + vPad * 2),
      const Radius.circular(7),
    );

    canvas.drawRRect(bgRect,
        Paint()..color = const Color(0xFF1A2535));
    canvas.drawRRect(
      bgRect,
      Paint()
        ..color = AppColors.accent.withValues(alpha: 0.4)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 0.75,
    );
    tp.paint(canvas, Offset(tx + hPad, ty + vPad));
  }

  // ── Text helper ───────────────────────────────────────────────────────────

  void _label(Canvas canvas, String text, Offset offset,
      {double maxWidth = 100, TextAlign align = TextAlign.left}) {
    (TextPainter(
      text: TextSpan(
        text: text,
        style: const TextStyle(color: Color(0xFF4B5E7A), fontSize: 9),
      ),
      textDirection: TextDirection.ltr,
      textAlign: align,
    )..layout(maxWidth: maxWidth))
        .paint(canvas, offset);
  }

  @override
  bool shouldRepaint(_ChartPainter old) =>
      old.samples != samples ||
      old.hoverIdx != hoverIdx ||
      old.peak != peak;
}
