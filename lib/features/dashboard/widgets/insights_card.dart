import 'dart:math';
import 'package:flutter/material.dart';
import '../../../core/theme.dart';
import '../../../data/models/station_monitor.dart';
import 'animated_value.dart';

// ─── Energy equivalents for today's generation ───────────────────────────

class TodayInsightsCard extends StatelessWidget {
  final double todayKwh;

  const TodayInsightsCard({super.key, required this.todayKwh});

  @override
  Widget build(BuildContext context) {
    if (todayKwh <= 0) return const SizedBox.shrink();

    final phones = (todayKwh * 1000 / 15).round();        // 15 Wh per charge
    final fanHours = (todayKwh * 1000 / 50).round();      // 50W ceiling fan
    final tvHours = (todayKwh * 1000 / 150).round();      // 150W LED TV
    final acHours = (todayKwh * 1000 / 1500).round();     // 1.5kW AC

    return _InsightSection(
      title: "Today's ${todayKwh.toStringAsFixed(1)} kWh powered...",
      icon: Icons.wb_sunny_rounded,
      iconColor: AppColors.accent,
      items: [
        _InsightItem(emoji: '📱', value: phones.toDouble(),
            label: 'smartphone charges', color: const Color(0xFF818CF8)),
        _InsightItem(emoji: '🌀', value: fanHours.toDouble(),
            label: 'hours of ceiling fan', color: const Color(0xFF34D399)),
        _InsightItem(emoji: '📺', value: tvHours.toDouble(),
            label: 'hours of TV', color: const Color(0xFF60A5FA)),
        _InsightItem(emoji: '❄️', value: acHours.toDouble(),
            label: 'hours of AC', color: const Color(0xFFA78BFA)),
      ],
    );
  }
}

// ─── India domestic flight routes with CO2 per passenger (one-way) ──────
// Source: distance × 0.133 kg CO2/passenger-km (ICAO economy, no RF)

class _FlightRoute {
  final String from;
  final String to;
  final double co2Tonnes;

  const _FlightRoute(this.from, this.to, this.co2Tonnes);

  String get label => '$from → $to';
}

const _indiaFlightRoutes = [
  _FlightRoute('Mumbai', 'Delhi', 0.153),
  _FlightRoute('Mumbai', 'Bangalore', 0.131),
  _FlightRoute('Mumbai', 'Chennai', 0.138),
  _FlightRoute('Mumbai', 'Hyderabad', 0.095),
  _FlightRoute('Mumbai', 'Kochi', 0.162),
  _FlightRoute('Mumbai', 'Goa', 0.065),
  _FlightRoute('Mumbai', 'Ahmedabad', 0.070),
  _FlightRoute('Mumbai', 'Kolkata', 0.179),
  _FlightRoute('Mumbai', 'Lucknow', 0.166),
  _FlightRoute('Delhi', 'Bangalore', 0.232),
  _FlightRoute('Delhi', 'Kolkata', 0.174),
  _FlightRoute('Delhi', 'Hyderabad', 0.168),
  _FlightRoute('Delhi', 'Chennai', 0.290),
  _FlightRoute('Delhi', 'Kochi', 0.280),
  _FlightRoute('Delhi', 'Jaipur', 0.036),
  _FlightRoute('Delhi', 'Amritsar', 0.060),
  _FlightRoute('Delhi', 'Varanasi', 0.104),
  _FlightRoute('Delhi', 'Guwahati', 0.248),
  _FlightRoute('Bangalore', 'Hyderabad', 0.076),
  _FlightRoute('Bangalore', 'Chennai', 0.039),
  _FlightRoute('Bangalore', 'Kolkata', 0.249),
  _FlightRoute('Chennai', 'Kolkata', 0.183),
  _FlightRoute('Chennai', 'Hyderabad', 0.055),
  _FlightRoute('Hyderabad', 'Kolkata', 0.178),
  _FlightRoute('Kochi', 'Delhi', 0.280),
  _FlightRoute('Kochi', 'Mumbai', 0.162),
  _FlightRoute('Kochi', 'Bangalore', 0.095),
  _FlightRoute('Kochi', 'Kolkata', 0.240),
];

// ─── Impact fact pool ─────────────────────────────────────────────────────

typedef _FactBuilder = _InsightItem Function(
    double co2Tonnes, double totalKwh, double totalIncome);

/// 16 diverse facts — 4 are randomly chosen each shuffle.
/// Covers CO₂ offset, energy equivalents, and income equivalents.
final List<_FactBuilder> _impactFactPool = [
  // ── CO₂ based ────────────────────────────────────────────────────────────
  (co2, kwh, inc) {
    final route =
        _indiaFlightRoutes[Random().nextInt(_indiaFlightRoutes.length)];
    return _InsightItem(
      emoji: '✈️',
      value: (co2 / route.co2Tonnes).roundToDouble(),
      label: '${route.label} flights worth of CO₂ saved',
      color: const Color(0xFF60A5FA),
    );
  },
  (co2, kwh, inc) => _InsightItem(
    emoji: '🚗',
    value: (co2 * 1000 / 0.12 / 1000).roundToDouble(),
    label: 'thousand km of car driving avoided',
    color: const Color(0xFFFBBF24),
    decimals: 1,
  ),
  (co2, kwh, inc) => _InsightItem(
    emoji: '🌳',
    // 1 mature tree absorbs ≈ 21 kg CO₂ per year
    value: (co2 * 1000 / 21).roundToDouble(),
    label: 'years of CO₂ absorbed by a single tree',
    color: AppColors.green,
  ),
  (co2, kwh, inc) => _InsightItem(
    emoji: '⛏️',
    // 1 tonne CO₂ ≈ from burning 0.4 tonnes of coal
    value: (co2 / 0.4 * 1000).roundToDouble(),
    label: 'kg of coal that stayed in the ground',
    color: const Color(0xFF9CA3AF),
  ),
  // ── Energy based ─────────────────────────────────────────────────────────
  (co2, kwh, inc) => _InsightItem(
    emoji: '🏠',
    value: (kwh / 4.5).roundToDouble(),
    label: 'days of average Indian home electricity',
    color: AppColors.green,
  ),
  (co2, kwh, inc) => _InsightItem(
    emoji: '⚡',
    // Average Indian EV: ~6 km/kWh
    value: (kwh * 6 / 1000).roundToDouble(),
    label: 'thousand km driven in an electric vehicle',
    color: const Color(0xFF818CF8),
    decimals: 1,
  ),
  (co2, kwh, inc) => _InsightItem(
    emoji: '📱',
    // 15 Wh per full smartphone charge
    value: (kwh * 1000 / 15 / 1000).roundToDouble(),
    label: 'thousand smartphone charges',
    color: const Color(0xFF34D399),
    decimals: 1,
  ),
  (co2, kwh, inc) => _InsightItem(
    emoji: '❄️',
    // 1.5-tonne split AC ≈ 1.5 kW
    value: (kwh / 1.5).roundToDouble(),
    label: 'hours of 1.5-tonne AC running',
    color: const Color(0xFFA78BFA),
  ),
  (co2, kwh, inc) => _InsightItem(
    emoji: '🍚',
    // Rice cooker ≈ 0.4 kWh per cook
    value: (kwh / 0.4).roundToDouble(),
    label: 'pots of rice cooked',
    color: const Color(0xFFFCA5A5),
  ),
  (co2, kwh, inc) => _InsightItem(
    emoji: '💡',
    // 10 W LED bulb: kwh / 0.01 kW → hours → ÷ 8760 → years
    value: (kwh * 1000 / 10 / 8760).roundToDouble(),
    label: 'years of continuous LED lighting',
    color: const Color(0xFFFDE68A),
    decimals: 1,
  ),
  (co2, kwh, inc) => _InsightItem(
    emoji: '🚿',
    // 2 kW electric geyser running 20 min ≈ 0.667 kWh per shower
    value: (kwh / 0.667).roundToDouble(),
    label: 'hot showers powered',
    color: const Color(0xFF67E8F9),
  ),
  (co2, kwh, inc) => _InsightItem(
    emoji: '🏏',
    // Floodlit cricket ground ≈ 400 kW · 4 h match = 1 600 kWh per game
    value: (kwh / 1600).roundToDouble(),
    label: 'evening cricket matches worth of floodlight',
    color: const Color(0xFF86EFAC),
    decimals: 1,
  ),
  (co2, kwh, inc) => _InsightItem(
    emoji: '🚂',
    // Indian Railways ≈ 0.04 kWh / passenger-km; Mumbai–Delhi ≈ 1 384 km
    value: (kwh / 55).roundToDouble(),
    label: 'Mumbai–Delhi train journeys per passenger',
    color: const Color(0xFFFDA4AF),
  ),
  // ── Income based ─────────────────────────────────────────────────────────
  (co2, kwh, inc) => _InsightItem(
    emoji: '🛒',
    // Average Indian monthly grocery spend ≈ ₹5 000
    value: (inc / 5000).roundToDouble(),
    label: 'months of grocery shopping',
    color: const Color(0xFF34D399),
  ),
  (co2, kwh, inc) => _InsightItem(
    emoji: '☕',
    // Roadside chai ≈ ₹20 per cup
    value: (inc / 20).roundToDouble(),
    label: 'cups of chai',
    color: const Color(0xFFD97706),
  ),
  (co2, kwh, inc) => _InsightItem(
    emoji: '🎬',
    // Two multiplex tickets ≈ ₹600
    value: (inc / 600).roundToDouble(),
    label: 'movie nights for two',
    color: const Color(0xFFA78BFA),
  ),
];

// ─── CO2 comparisons for lifetime savings ────────────────────────────────

class Co2InsightsCard extends StatefulWidget {
  final double co2Tonnes;
  final double totalKwh;
  final double totalIncome;

  const Co2InsightsCard({
    super.key,
    required this.co2Tonnes,
    required this.totalKwh,
    required this.totalIncome,
  });

  @override
  State<Co2InsightsCard> createState() => _Co2InsightsCardState();
}

class _Co2InsightsCardState extends State<Co2InsightsCard> {
  List<_InsightItem> _items = const [];

  @override
  void initState() {
    super.initState();
    _pickItems();
  }

  @override
  void didUpdateWidget(Co2InsightsCard old) {
    super.didUpdateWidget(old);
    if (old.co2Tonnes != widget.co2Tonnes) setState(_pickItems);
  }

  void _pickItems() {
    final pool = List<_FactBuilder>.from(_impactFactPool)..shuffle(Random());
    _items = pool
        .take(4)
        .map((f) => f(widget.co2Tonnes, widget.totalKwh, widget.totalIncome))
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    return _InsightSection(
      title: 'Your lifetime impact',
      icon: Icons.eco_rounded,
      iconColor: AppColors.green,
      headerAction: _RefreshRouteButton(onTap: () => setState(_pickItems)),
      items: _items,
    );
  }
}

// ─── Monthly performance card ─────────────────────────────────────────────

class MonthlyPerformanceCard extends StatelessWidget {
  final double monthKwh;
  final double capacityKw;
  final int dayOfMonth;
  final List<WeatherForecast> forecast;

  const MonthlyPerformanceCard({
    super.key,
    required this.monthKwh,
    required this.capacityKw,
    required this.dayOfMonth,
    required this.forecast,
  });

  /// Average UV index from the forecast, fallback to 8 if no data
  double get _avgUvIndex {
    if (forecast.isEmpty) return 8.0;
    final total = forecast.fold<int>(0, (sum, d) => sum + d.uvIndex);
    return total / forecast.length;
  }

  /// Peak sun hours estimated from UV index (UV 10 ≈ 5.5 hrs, UV 8 ≈ 4.4 hrs)
  double get _estimatedSunHours => (_avgUvIndex * 0.55).clamp(1.0, 8.0);

  double get _theoretical => capacityKw * _estimatedSunHours * dayOfMonth;

  double get _performance =>
      _theoretical > 0 ? (monthKwh / _theoretical).clamp(0.0, 1.0) : 0.0;

  Color _performanceColor(double p) {
    if (p >= 0.75) return AppColors.green;
    if (p >= 0.5) return AppColors.accent;
    return const Color(0xFFF87171);
  }

  void _showInfoSheet(BuildContext context) {
    final theoretical = _theoretical;
    final performance = _performance;
    final sunHours = _estimatedSunHours;
    final avgUv = _avgUvIndex;
    final perfColor = _performanceColor(performance);

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
            // Handle bar
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

            // Title
            const Row(
              children: [
                Icon(Icons.info_outline_rounded,
                    color: AppColors.accent, size: 20),
                SizedBox(width: 10),
                Text(
                  'How is this calculated?',
                  style: TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 17,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),

            // Formula block
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: AppColors.cardAlt,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: AppColors.divider),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Formula',
                      style: TextStyle(
                          color: AppColors.textSecondary, fontSize: 11,
                          fontWeight: FontWeight.w600, letterSpacing: 1)),
                  const SizedBox(height: 10),
                  const Text(
                    'Performance = Generated ÷ Theoretical Max',
                    style: TextStyle(
                      color: AppColors.textPrimary,
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 12),
                  _FormulaRow(
                    label: 'Theoretical Max',
                    formula:
                        '${capacityKw.toStringAsFixed(2)} kW  ×  ${sunHours.toStringAsFixed(1)} hrs  ×  $dayOfMonth days',
                    result: '${theoretical.toStringAsFixed(0)} kWh',
                    color: AppColors.accent,
                  ),
                  const SizedBox(height: 8),
                  _FormulaRow(
                    label: 'Actual Generated',
                    formula: 'from your inverter this month',
                    result: '${monthKwh.toStringAsFixed(1)} kWh',
                    color: AppColors.green,
                  ),
                  const SizedBox(height: 8),
                  _FormulaRow(
                    label: 'Performance',
                    formula:
                        '${monthKwh.toStringAsFixed(1)} ÷ ${theoretical.toStringAsFixed(0)}',
                    result: '${(performance * 100).toStringAsFixed(0)}%',
                    color: perfColor,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),

            // UV explanation
            _InfoBlock(
              icon: Icons.wb_sunny_outlined,
              iconColor: AppColors.accent,
              title: 'Why UV Index instead of a fixed number?',
              body:
                  'Most solar calculators assume a fixed 5 "peak sun hours" per day for India. '
                  'But Kerala in May gets fewer effective hours due to cloud cover and monsoon onset. '
                  'Your 7-day forecast shows an average UV Index of ${avgUv.toStringAsFixed(1)}, '
                  'which translates to ~${sunHours.toStringAsFixed(1)} peak sun hours per day — '
                  'a more accurate estimate for your actual location and season.',
            ),
            const SizedBox(height: 14),

            // What "theoretical max" means
            _InfoBlock(
              icon: Icons.lightbulb_outline_rounded,
              iconColor: const Color(0xFF818CF8),
              title: 'What is the theoretical maximum?',
              body:
                  'If your ${capacityKw.toStringAsFixed(2)} kW system ran at full capacity during '
                  'every peak sun hour for all $dayOfMonth days this month, it would produce '
                  '${theoretical.toStringAsFixed(0)} kWh. In practice, panels never hit 100% '
                  'due to heat, dust, cable losses, and partial cloud cover.',
            ),
            const SizedBox(height: 14),

            // Colour coding
            _InfoBlock(
              icon: Icons.palette_outlined,
              iconColor: const Color(0xFF34D399),
              title: 'Colour guide',
              body: '🟢  ≥ 75% — Great. System performing well for the conditions.\n'
                  '🟡  50–74% — Acceptable. Likely weather-related losses.\n'
                  '🔴  < 50% — Low. Worth checking for shading, dirt, or a fault.',
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theoretical = _theoretical;
    final performance = _performance;
    final avgDaily = dayOfMonth > 0 ? monthKwh / dayOfMonth : 0.0;

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.divider),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header row with info button
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: AppColors.accent.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(Icons.bar_chart_rounded,
                    color: AppColors.accent, size: 18),
              ),
              const SizedBox(width: 12),
              const Expanded(
                child: Text(
                  'Monthly Performance',
                  style: TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              GestureDetector(
                onTap: () => _showInfoSheet(context),
                child: Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: AppColors.cardAlt,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: AppColors.divider),
                  ),
                  child: const Icon(Icons.info_outline_rounded,
                      color: AppColors.textSecondary, size: 15),
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),

          // UV source badge
          Row(
            children: [
              const Icon(Icons.wb_sunny_outlined,
                  color: AppColors.accent, size: 12),
              const SizedBox(width: 4),
              Text(
                'Using avg UV ${_avgUvIndex.toStringAsFixed(1)} → '
                '${_estimatedSunHours.toStringAsFixed(1)} peak sun hrs/day',
                style: const TextStyle(
                    color: AppColors.textSecondary, fontSize: 11),
              ),
            ],
          ),
          const SizedBox(height: 12),

          // Performance ratio bar
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('System Efficiency',
                  style: TextStyle(
                      color: AppColors.textSecondary, fontSize: 12)),
              Text(
                '${(performance * 100).toStringAsFixed(0)}%',
                style: TextStyle(
                  color: _performanceColor(performance),
                  fontSize: 13,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          _AnimatedProgressBar(value: performance),
          const SizedBox(height: 4),
          Text(
            '${monthKwh.toStringAsFixed(1)} kWh of '
            '${theoretical.toStringAsFixed(0)} kWh theoretical max',
            style: const TextStyle(
                color: AppColors.textSecondary, fontSize: 11),
          ),

          const SizedBox(height: 16),
          const Divider(color: AppColors.divider, height: 1),
          const SizedBox(height: 16),

          // Daily average + system size
          Row(
            children: [
              Expanded(
                child: _StatBox(
                  label: 'Daily Average',
                  value: '${avgDaily.toStringAsFixed(1)} kWh',
                  sub: 'this month',
                  color: AppColors.accent,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _StatBox(
                  label: 'System Size',
                  value: '${capacityKw.toStringAsFixed(2)} kW',
                  sub: 'installed capacity',
                  color: const Color(0xFF818CF8),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ─── Info sheet sub-widgets ──────────────────────────────────────────────

class _FormulaRow extends StatelessWidget {
  final String label;
  final String formula;
  final String result;
  final Color color;

  const _FormulaRow({
    required this.label,
    required this.formula,
    required this.result,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label,
                  style: const TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 11,
                      fontWeight: FontWeight.w500)),
              Text(formula,
                  style: const TextStyle(
                      color: AppColors.textPrimary, fontSize: 12)),
            ],
          ),
        ),
        const SizedBox(width: 12),
        Text(result,
            style: TextStyle(
                color: color,
                fontSize: 13,
                fontWeight: FontWeight.bold)),
      ],
    );
  }
}

class _InfoBlock extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final String title;
  final String body;

  const _InfoBlock({
    required this.icon,
    required this.iconColor,
    required this.title,
    required this.body,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.cardAlt,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.divider),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: iconColor, size: 18),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    style: const TextStyle(
                      color: AppColors.textPrimary,
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

// ─── Shared components ────────────────────────────────────────────────────

class _InsightSection extends StatelessWidget {
  final String title;
  final IconData icon;
  final Color iconColor;
  final List<_InsightItem> items;
  final Widget? headerAction;

  const _InsightSection({
    required this.title,
    required this.icon,
    required this.iconColor,
    required this.items,
    this.headerAction,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.divider),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: iconColor.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(icon, color: iconColor, size: 18),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              ?headerAction,
            ],
          ),
          const SizedBox(height: 16),
          ...items.map((item) => _buildItem(item)),
        ],
      ),
    );
  }

  Widget _buildItem(_InsightItem item) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          Text(item.emoji, style: const TextStyle(fontSize: 22)),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                AnimatedValue(
                  value: item.value,
                  formatter: (v) => item.decimals > 0
                      ? v.toStringAsFixed(item.decimals)
                      : v.toInt().toString(),
                  style: TextStyle(
                    color: item.color,
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                  duration: const Duration(milliseconds: 1600),
                ),
                Text(
                  item.label,
                  style: const TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _InsightItem {
  final String emoji;
  final double value;
  final String label;
  final Color color;
  final int decimals;

  const _InsightItem({
    required this.emoji,
    required this.value,
    required this.label,
    required this.color,
    this.decimals = 0,
  });
}

class _AnimatedProgressBar extends StatelessWidget {
  final double value;

  const _AnimatedProgressBar({required this.value});

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: value),
      duration: const Duration(milliseconds: 1200),
      curve: Curves.easeOutCubic,
      builder: (context, v, child) => ClipRRect(
        borderRadius: BorderRadius.circular(6),
        child: LinearProgressIndicator(
          value: v,
          minHeight: 8,
          backgroundColor: AppColors.divider,
          valueColor: AlwaysStoppedAnimation(
            v >= 0.75
                ? AppColors.green
                : v >= 0.5
                    ? AppColors.accent
                    : const Color(0xFFF87171),
          ),
        ),
      ),
    );
  }
}

class _StatBox extends StatelessWidget {
  final String label;
  final String value;
  final String sub;
  final Color color;

  const _StatBox({
    required this.label,
    required this.value,
    required this.sub,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.cardAlt,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label,
              style: const TextStyle(
                  color: AppColors.textSecondary, fontSize: 11)),
          const SizedBox(height: 4),
          Text(value,
              style: TextStyle(
                  color: color,
                  fontSize: 15,
                  fontWeight: FontWeight.bold)),
          Text(sub,
              style: const TextStyle(
                  color: AppColors.textSecondary, fontSize: 10)),
        ],
      ),
    );
  }
}

// ─── Shuffle button for the flight route ─────────────────────────────────

class _RefreshRouteButton extends StatefulWidget {
  final VoidCallback onTap;
  const _RefreshRouteButton({required this.onTap});

  @override
  State<_RefreshRouteButton> createState() => _RefreshRouteButtonState();
}

class _RefreshRouteButtonState extends State<_RefreshRouteButton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _spin;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 500));
    _spin = Tween<double>(begin: 0, end: 1).animate(
        CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut));
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  void _handleTap() {
    _ctrl.forward(from: 0);
    widget.onTap();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: _handleTap,
      child: Container(
        padding: const EdgeInsets.all(6),
        decoration: BoxDecoration(
          color: AppColors.cardAlt,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: AppColors.divider),
        ),
        child: AnimatedBuilder(
          animation: _spin,
          builder: (context, child) => Transform.rotate(
            angle: _spin.value * 2 * pi,
            child: const Icon(
              Icons.shuffle_rounded,
              color: AppColors.textSecondary,
              size: 15,
            ),
          ),
        ),
      ),
    );
  }
}
