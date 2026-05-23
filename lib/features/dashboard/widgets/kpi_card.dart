import 'package:flutter/material.dart';
import '../../../core/theme.dart';
import 'animated_value.dart';

class KpiCard extends StatelessWidget {
  final String label;
  final double value;
  final String unit;
  final IconData icon;
  final Color? iconColor;
  final String Function(double)? formatter;

  const KpiCard({
    super.key,
    required this.label,
    required this.value,
    required this.unit,
    required this.icon,
    this.iconColor,
    this.formatter,
  });

  @override
  Widget build(BuildContext context) {
    final color = iconColor ?? AppColors.accent;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.divider),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(7),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(9),
            ),
            child: Icon(icon, color: color, size: 16),
          ),
          const SizedBox(height: 12),
          AnimatedValue(
            value: value,
            formatter: formatter ?? (v) => v.toStringAsFixed(1),
            style: const TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: AppColors.textPrimary,
            ),
          ),
          const SizedBox(height: 2),
          Text(unit,
              style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.w500)),
          const SizedBox(height: 3),
          Text(label,
              style: const TextStyle(color: AppColors.textSecondary, fontSize: 11)),
        ],
      ),
    );
  }
}

// ─── Hero live power card ─────────────────────────────────────────────────

class LivePowerCard extends StatelessWidget {
  final double pac;
  final int status;
  final String workMode;
  final double capacityKw;

  const LivePowerCard({
    super.key,
    required this.pac,
    required this.status,
    required this.workMode,
    this.capacityKw = 5.0,
  });

  @override
  Widget build(BuildContext context) {
    final isGenerating = pac > 0;
    final loadPct = capacityKw > 0 ? (pac / (capacityKw * 1000)).clamp(0.0, 1.0) : 0.0;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(24, 24, 24, 28),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: isGenerating
              ? [const Color(0xFF78350F), const Color(0xFF0D1117)]
              : [const Color(0xFF0F172A), const Color(0xFF0D1117)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
          color: isGenerating
              ? AppColors.accent.withValues(alpha: 0.35)
              : AppColors.divider,
          width: 1.5,
        ),
      ),
      child: Column(
        children: [
          // Top row: label + status
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Live Output',
                style: TextStyle(color: AppColors.textSecondary, fontSize: 13),
              ),
              _StatusBadge(status: status, workMode: workMode),
            ],
          ),
          const SizedBox(height: 24),

          // Solar icon with glow
          if (isGenerating)
            _GlowingIcon(color: AppColors.accent)
          else
            const Icon(Icons.nightlight_round,
                size: 52, color: AppColors.textSecondary),

          const SizedBox(height: 20),

          // Animated watt value
          AnimatedValue(
            value: pac,
            formatter: (v) => '${v.toStringAsFixed(0)} W',
            style: TextStyle(
              fontSize: 46,
              fontWeight: FontWeight.bold,
              color: isGenerating ? AppColors.accent : AppColors.textSecondary,
              letterSpacing: -1,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            isGenerating ? 'Currently generating' : (workMode.isNotEmpty ? workMode : 'Waiting for sunrise'),
            style: const TextStyle(color: AppColors.textSecondary, fontSize: 13),
          ),

          // Load bar — only show when generating
          if (isGenerating) ...[
            const SizedBox(height: 20),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('Capacity used',
                    style: TextStyle(color: AppColors.textSecondary, fontSize: 11)),
                Text('${(loadPct * 100).toStringAsFixed(0)}%',
                    style: const TextStyle(
                        color: AppColors.accent,
                        fontSize: 11,
                        fontWeight: FontWeight.w600)),
              ],
            ),
            const SizedBox(height: 6),
            TweenAnimationBuilder<double>(
              tween: Tween(begin: 0, end: loadPct),
              duration: const Duration(milliseconds: 1400),
              curve: Curves.easeOutCubic,
              builder: (context, v, child) => ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  value: v,
                  minHeight: 5,
                  backgroundColor: AppColors.divider,
                  valueColor: const AlwaysStoppedAnimation(AppColors.accent),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _GlowingIcon extends StatefulWidget {
  final Color color;
  const _GlowingIcon({required this.color});

  @override
  State<_GlowingIcon> createState() => _GlowingIconState();
}

class _GlowingIconState extends State<_GlowingIcon>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _glow;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 2000))
      ..repeat(reverse: true);
    _glow = Tween<double>(begin: 6, end: 22).animate(
        CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut));
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _glow,
      builder: (context, child) => Container(
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          boxShadow: [
            BoxShadow(
              color: widget.color.withValues(alpha: 0.4),
              blurRadius: _glow.value,
              spreadRadius: _glow.value / 4,
            ),
          ],
        ),
        child: Icon(Icons.solar_power, size: 52, color: widget.color),
      ),
    );
  }
}

class _StatusBadge extends StatelessWidget {
  final int status;
  final String workMode;

  const _StatusBadge({required this.status, required this.workMode});

  @override
  Widget build(BuildContext context) {
    Color color;
    String label;

    switch (status) {
      case 1:
      case 0:
        color = AppColors.green;
        label = 'Online';
        break;
      case -1:
        color = AppColors.textSecondary;
        label = 'Wait Mode';
        break;
      default:
        color = AppColors.red;
        label = 'Fault';
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          PulsingDot(color: color, size: 6),
          const SizedBox(width: 6),
          Text(label, style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.w500)),
        ],
      ),
    );
  }
}
