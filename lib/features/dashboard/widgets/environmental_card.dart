import 'package:flutter/material.dart';
import '../../../core/theme.dart';
import '../../../data/models/station_monitor.dart';
import 'animated_value.dart';

class EnvironmentalCard extends StatelessWidget {
  final Environmental data;

  const EnvironmentalCard({super.key, required this.data});

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
                  color: AppColors.green.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(Icons.eco_rounded,
                    color: AppColors.green, size: 18),
              ),
              const SizedBox(width: 12),
              const Text(
                'Environmental Impact',
                style: TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          Row(
            children: [
              Expanded(
                child: _EnvStat(
                  emoji: '🌿',
                  value: data.co2Tonnes,
                  unit: 'tonnes',
                  label: 'CO₂ saved',
                  comparison: '≈ ${(data.co2Tonnes / 0.147).round()} MUM→DEL flights',
                  color: AppColors.green,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _EnvStat(
                  emoji: '🌳',
                  value: data.treesEquivalent,
                  unit: 'trees',
                  label: 'equivalent',
                  comparison: 'absorbing CO₂ for a year',
                  color: const Color(0xFF34D399),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _EnvStat(
                  emoji: '⛏️',
                  value: data.coalKg,
                  unit: 'tonnes',
                  label: 'coal saved',
                  comparison: '≈ ${(data.coalKg / 0.0028).round()} kg coal',
                  color: const Color(0xFF94A3B8),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _EnvStat extends StatelessWidget {
  final String emoji;
  final double value;
  final String unit;
  final String label;
  final String comparison;
  final Color color;

  const _EnvStat({
    required this.emoji,
    required this.value,
    required this.unit,
    required this.label,
    required this.comparison,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.cardAlt,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(emoji, style: const TextStyle(fontSize: 22)),
          const SizedBox(height: 8),
          AnimatedValue(
            value: value,
            formatter: (v) => v.toStringAsFixed(2),
            style: TextStyle(
              color: color,
              fontSize: 15,
              fontWeight: FontWeight.bold,
            ),
          ),
          Text(unit,
              style: const TextStyle(
                  color: AppColors.textSecondary, fontSize: 10)),
          const SizedBox(height: 2),
          Text(label,
              style: const TextStyle(
                  color: AppColors.textPrimary, fontSize: 11, fontWeight: FontWeight.w500)),
          const SizedBox(height: 6),
          Text(
            comparison,
            style: TextStyle(
              color: color.withValues(alpha: 0.8),
              fontSize: 10,
            ),
          ),
        ],
      ),
    );
  }
}
