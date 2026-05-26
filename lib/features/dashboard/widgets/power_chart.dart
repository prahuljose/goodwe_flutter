import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../../../core/theme.dart';
import '../../../data/models/station_monitor.dart';

// ─── Anomaly model ─────────────────────────────────────────────────────────

enum _AnomalyKind { outage, cloudShadow }

class _AnomalyEvent {
  final _AnomalyKind kind;
  final DateTime start;
  final DateTime end;
  final int dropPct; // only meaningful for cloudShadow

  const _AnomalyEvent({
    required this.kind,
    required this.start,
    required this.end,
    this.dropPct = 0,
  });

  int get durationMinutes => end.difference(start).inMinutes;
}

// ─── Public widget ─────────────────────────────────────────────────────────────

class PowerCurveCard extends StatefulWidget {
  final List<PacSample> samples;
  final String dateLabel;

  /// Called when the user taps the left (previous day) arrow.
  /// When null the nav arrows are hidden entirely (e.g. in the date-picker sheet).
  final VoidCallback? onPrevDay;

  /// null when showing today — disables the right (next day) arrow.
  final VoidCallback? onNextDay;

  /// Shows a loading spinner in place of the chart while fetching a new day.
  final bool isLoading;

  /// When provided, a calendar icon appears in the header to open a date picker.
  final VoidCallback? onPickDate;

  const PowerCurveCard({
    super.key,
    required this.samples,
    required this.dateLabel,
    this.onPrevDay,
    this.onNextDay,
    this.isLoading = false,
    this.onPickDate,
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

  List<_AnomalyEvent> get _anomalies {
    final s = widget.samples;
    if (s.isEmpty) return const [];

    final first = s.indexWhere((x) => x.pac > 0);
    final last  = s.lastIndexWhere((x) => x.pac > 0);
    if (first == -1 || last <= first) return const [];

    final window = s.sublist(first, last + 1);
    final events  = <_AnomalyEvent>[];
    const nearZero = 50.0; // < 50 W treated as off

    // ── Outages: zero-pac runs inside the generation window ──────────────────
    int? gapStart;
    for (int i = 0; i < window.length; i++) {
      if (window[i].pac < nearZero && gapStart == null) {
        gapStart = i;
      } else if (window[i].pac >= nearZero && gapStart != null) {
        // Use window[i].time (resumption) as end so the range is always
        // non-zero even for a single-sample gap (5-min resolution).
        final start = window[gapStart].time;
        final end   = window[i].time;
        final dur   = end.difference(start).inMinutes;
        if (dur >= 5) {
          events.add(_AnomalyEvent(
            kind: _AnomalyKind.outage,
            start: start,
            end: end,
          ));
        }
        gapStart = null;
      }
    }

    // ── Cloud shadows: pac < 30 % of recent 2-h max, lasts ≥ 15 min ─────────
    final dayPeak =
        window.map((x) => x.pac).reduce(math.max);
    const rollSamples = 24; // 2-hour look-back at 5-min intervals
    int? shadowStart;
    for (int i = rollSamples; i < window.length; i++) {
      double recentMax = 0;
      for (int j = i - rollSamples; j < i; j++) {
        if (window[j].pac > recentMax) recentMax = window[j].pac;
      }
      // Only flag when context is meaningful (recent high ≥ 15 % of day peak)
      if (recentMax < dayPeak * 0.15) continue;

      final isLow = window[i].pac > nearZero &&
          window[i].pac < recentMax * 0.30;

      if (isLow && shadowStart == null) {
        shadowStart = i;
      } else if (!isLow && shadowStart != null) {
        final dur =
            window[i].time.difference(window[shadowStart].time).inMinutes;
        if (dur >= 15) {
          final minPac = window
              .sublist(shadowStart, i)
              .map((x) => x.pac)
              .reduce(math.min);
          final drop =
              ((1 - minPac / recentMax) * 100).round().clamp(0, 99);
          events.add(_AnomalyEvent(
            kind: _AnomalyKind.cloudShadow,
            start: window[shadowStart].time,
            end: window[i - 1].time,
            dropPct: drop,
          ));
        }
        shadowStart = null;
      }
    }

    events.sort((a, b) => a.start.compareTo(b.start));
    return events;
  }

  @override
  Widget build(BuildContext context) {
    final visible = _visible;
    final peak    = widget.isLoading ? null : _peak;

    final isEmpty = !widget.isLoading &&
        (visible.isEmpty || peak == null || peak.pac == 0);

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
          if (widget.isLoading)
            const SizedBox(
              height: 200,
              child: Center(
                child: CircularProgressIndicator(
                  color: AppColors.accent,
                  strokeWidth: 2,
                ),
              ),
            )
          else if (isEmpty)
            const SizedBox(
              height: 160,
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.nights_stay_outlined,
                        color: AppColors.textSecondary, size: 28),
                    SizedBox(height: 8),
                    Text(
                      'No generation data for this day',
                      style: TextStyle(
                        color: AppColors.textSecondary,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
            )
          else ...[
            Padding(
              padding: const EdgeInsets.only(left: 8),
              child: LayoutBuilder(builder: (ctx, constraints) {
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
                      peak: peak!,
                      anomalies: _anomalies,
                    ),
                  ),
                ),
              );
            }),
            ),
            _buildFooter(visible),
            _buildAnomalyInsights(_anomalies),
          ],
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

  void _showInfoSheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.card,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      isScrollControlled: true,
      builder: (_) => Padding(
        padding: const EdgeInsets.fromLTRB(24, 20, 24, 40),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Handle
            Center(
              child: Container(
                width: 40, height: 4,
                decoration: BoxDecoration(
                  color: AppColors.divider,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 20),
            const Row(
              children: [
                Icon(Icons.info_outline_rounded,
                    color: AppColors.accent, size: 20),
                SizedBox(width: 10),
                Text(
                  'How anomalies are detected',
                  style: TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 17,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),
            _AnomalyInfoBlock(
              color: const Color(0xFFF87171),
              icon: Icons.bolt_rounded,
              title: 'Power Outage  (red band)',
              body: 'Flagged when output drops to near-zero (< 50 W) for '
                  '5 or more consecutive minutes inside the normal generation '
                  'window. Common causes: grid disconnection, a tripped '
                  'breaker, or the inverter entering protection mode.',
            ),
            const SizedBox(height: 12),
            _AnomalyInfoBlock(
              color: const Color(0xFF93C5FD),
              icon: Icons.cloud_outlined,
              title: 'Cloud Shadow  (blue band)',
              body: 'Flagged when output falls below 30 % of the highest '
                  'output seen in the preceding 2 hours, and stays low for '
                  '15 or more minutes. The rolling look-back means natural '
                  'morning ramp-up is never falsely flagged — it only fires '
                  'when there is a meaningful mid-generation drop.',
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: AppColors.cardAlt,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: AppColors.divider),
              ),
              child: const Row(
                children: [
                  _ColorDot(color: Color(0xFFF87171)),
                  SizedBox(width: 8),
                  Text('Power outage',
                      style: TextStyle(
                          color: AppColors.textPrimary, fontSize: 12)),
                  SizedBox(width: 20),
                  _ColorDot(color: Color(0xFF93C5FD)),
                  SizedBox(width: 8),
                  Text('Cloud shadow',
                      style: TextStyle(
                          color: AppColors.textPrimary, fontSize: 12)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(PacSample? peak) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 12, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Row 1: title · info button · peak badge ─────────────────────
          Row(
            children: [
              const Icon(Icons.show_chart_rounded,
                  color: AppColors.accent, size: 16),
              const SizedBox(width: 8),
              const Text(
                'Power Curve',
                style: TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const Spacer(),
              // Peak badge
              if (peak != null) ...[
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 8, vertical: 3),
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
                const SizedBox(width: 8),
              ],
              // Info button
              GestureDetector(
                onTap: () => _showInfoSheet(context),
                child: Container(
                  padding: const EdgeInsets.all(5),
                  decoration: BoxDecoration(
                    color: AppColors.cardAlt,
                    borderRadius: BorderRadius.circular(7),
                    border: Border.all(color: AppColors.divider),
                  ),
                  child: const Icon(Icons.info_outline_rounded,
                      color: AppColors.textSecondary, size: 13),
                ),
              ),
            ],
          ),

          // ── Row 2: date navigation · calendar picker ─────────────────────
          const SizedBox(height: 8),
          Row(
            children: [
              if (widget.onPrevDay != null) ...[
                _NavArrow(
                  icon: Icons.chevron_left_rounded,
                  onTap: widget.isLoading ? null : widget.onPrevDay,
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: Text(
                    widget.dateLabel,
                    style: const TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
                _NavArrow(
                  icon: Icons.chevron_right_rounded,
                  onTap: widget.isLoading ? null : widget.onNextDay,
                ),
              ] else
                Text(
                  widget.dateLabel,
                  style: const TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              const Spacer(),
              // Calendar date-picker button
              if (widget.onPickDate != null)
                GestureDetector(
                  onTap: widget.isLoading ? null : widget.onPickDate,
                  child: Container(
                    padding: const EdgeInsets.all(5),
                    decoration: BoxDecoration(
                      color: AppColors.cardAlt,
                      borderRadius: BorderRadius.circular(7),
                      border: Border.all(color: AppColors.divider),
                    ),
                    child: Icon(
                      Icons.calendar_month_outlined,
                      color: widget.isLoading
                          ? AppColors.divider
                          : AppColors.textSecondary,
                      size: 13,
                    ),
                  ),
                ),
            ],
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

  Widget _buildAnomalyInsights(List<_AnomalyEvent> anomalies) {
    if (anomalies.isEmpty) return const SizedBox.shrink();

    String t(DateTime dt) =>
        '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Divider(color: Color(0xFF1E2D3F), height: 1),
          const SizedBox(height: 10),
          ...anomalies.map((a) {
            final isOutage = a.kind == _AnomalyKind.outage;
            final color = isOutage
                ? const Color(0xFFF87171)  // red
                : const Color(0xFF93C5FD); // blue
            final icon  = isOutage
                ? Icons.bolt_rounded
                : Icons.cloud_outlined;
            final dur = a.durationMinutes;
            final durStr = dur >= 60
                ? '${(dur / 60).toStringAsFixed(1)} hr'
                : '$dur min';
            final label = isOutage
                ? 'Power outage  ·  ${t(a.start)} – ${t(a.end)}  ($durStr)'
                : 'Cloud shadow  ·  ${t(a.start)} – ${t(a.end)}'
                  '  (output dropped ~${a.dropPct}%)';

            return Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(4),
                    decoration: BoxDecoration(
                      color: color.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Icon(icon, color: color, size: 12),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      label,
                      style: TextStyle(
                        color: color,
                        fontSize: 11,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ],
              ),
            );
          }),
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
  final List<_AnomalyEvent> anomalies;

  // Exposed as constants so the parent widget can use them for hit-testing
  static const lp = 52.0; // left pad  (y-axis labels)
  static const rp = 12.0; // right pad
  static const tp = 14.0; // top pad
  static const bp = 28.0; // bottom pad (x-axis labels)

  const _ChartPainter({
    required this.samples,
    required this.hoverIdx,
    required this.peak,
    required this.anomalies,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (samples.length < 2) return;

    final chart = Rect.fromLTRB(lp, tp, size.width - rp, size.height - bp);
    final maxPac = samples.map((s) => s.pac).reduce(math.max);
    if (maxPac == 0) return;

    // Add 12 % headroom so the peak curve never touches the top of the chart
    final scaledMax = maxPac * 1.12;

    // Map sample index → canvas Offset
    Offset pt(int i) => Offset(
          chart.left + (i / (samples.length - 1)) * chart.width,
          chart.bottom - (samples[i].pac / scaledMax) * chart.height,
        );

    final pts = List.generate(samples.length, pt);

    _drawGridAndLabels(canvas, chart, scaledMax);
    _drawXLabels(canvas, chart);
    _drawAnomalyBands(canvas, chart);
    _drawArea(canvas, chart, pts);
    _drawLine(canvas, pts);
    _drawPeakMarker(canvas, chart, pts);
    if (hoverIdx != null) _drawHover(canvas, chart, pts);
  }

  // ── Outage / cloud-shadow shading behind the curve ────────────────────────

  void _drawAnomalyBands(Canvas canvas, Rect chart) {
    if (anomalies.isEmpty) return;

    final tStart   = samples.first.time;
    final tEnd     = samples.last.time;
    final totalMins =
        tEnd.difference(tStart).inMinutes.toDouble();
    if (totalMins == 0) return;

    for (final a in anomalies) {
      final x1 = chart.left +
          a.start.difference(tStart).inMinutes / totalMins * chart.width;
      final x2 = chart.left +
          a.end.difference(tStart).inMinutes / totalMins * chart.width;

      final color = a.kind == _AnomalyKind.outage
          ? const Color(0xFFF87171)
          : const Color(0xFF93C5FD);

      canvas.drawRect(
        Rect.fromLTRB(
            x1.clamp(chart.left, chart.right),
            chart.top,
            (x2 + 1).clamp(chart.left, chart.right),
            chart.bottom),
        Paint()..color = color.withValues(alpha: 0.10),
      );
    }
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
      _label(canvas, label, Offset(6, y - 6), maxWidth: lp - 14,
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

  // ── Peak dot + dashed horizontal peak-line ────────────────────────────────

  void _drawPeakMarker(Canvas canvas, Rect chart, List<Offset> pts) {
    final idx = samples.indexWhere((s) => s.pac == peak.pac);
    if (idx < 0) return;
    final pp = pts[idx];

    // Dashed horizontal line across the full chart width at peak height
    final dashPaint = Paint()
      ..color = AppColors.accent.withValues(alpha: 0.30)
      ..strokeWidth = 1;

    double x = chart.left;
    while (x < chart.right) {
      canvas.drawLine(
        Offset(x, pp.dy),
        Offset(math.min(x + 4, chart.right), pp.dy),
        dashPaint,
      );
      x += 8;
    }

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
              fontWeight: FontWeight.w500,
              fontFamily: 'Outfit',
            ),
          ),
          TextSpan(
            text: valStr,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 10,
              fontWeight: FontWeight.w700,
              fontFamily: 'Outfit',
            ),
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
        style: const TextStyle(
          color: Color(0xFF4B5E7A),
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
  bool shouldRepaint(_ChartPainter old) =>
      old.samples != samples ||
      old.hoverIdx != hoverIdx ||
      old.peak != peak ||
      old.anomalies != anomalies;
}

// ─── Info sheet helpers ────────────────────────────────────────────────────

class _AnomalyInfoBlock extends StatelessWidget {
  final Color color;
  final IconData icon;
  final String title;
  final String body;

  const _AnomalyInfoBlock({
    required this.color,
    required this.icon,
    required this.title,
    required this.body,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withValues(alpha: 0.30)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: color, size: 18),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    style: TextStyle(
                      color: color,
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    )),
                const SizedBox(height: 5),
                Text(body,
                    style: const TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 12,
                      height: 1.5,
                    )),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ColorDot extends StatelessWidget {
  final Color color;
  const _ColorDot({required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 10,
      height: 10,
      decoration: BoxDecoration(color: color, shape: BoxShape.circle),
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
        padding: const EdgeInsets.all(3),
        child: Icon(
          icon,
          size: 18,
          color: onTap != null
              ? AppColors.textSecondary
              : AppColors.divider,
        ),
      ),
    );
  }
}
