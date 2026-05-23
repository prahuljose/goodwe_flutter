import 'package:flutter/material.dart';
import '../../../core/theme.dart';
import '../../../data/models/station_monitor.dart';

class InverterCard extends StatelessWidget {
  final InverterData inverter;

  const InverterCard({super.key, required this.inverter});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Inverter',
                style: TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
              Text(
                inverter.model,
                style: const TextStyle(color: AppColors.accent, fontSize: 12),
              ),
            ],
          ),
          const SizedBox(height: 16),
          _Row(label: 'Serial No.', value: inverter.sn),
          _Row(label: 'Work Mode', value: inverter.workMode),
          _Row(label: 'Last Refresh', value: inverter.lastRefreshTime),
          _Row(label: 'Total Hours', value: '${inverter.hTotal.toStringAsFixed(0)} h'),
          _Row(label: 'Temperature', value: '${inverter.temperature.toStringAsFixed(1)} °C'),
          const Divider(color: AppColors.divider, height: 24),
          const Text(
            'DC Inputs',
            style: TextStyle(color: AppColors.textSecondary, fontSize: 13),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: _InputChip(
                  label: 'String 1',
                  voltage: inverter.vpv1,
                  current: inverter.ipv1,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _InputChip(
                  label: 'String 2',
                  voltage: inverter.vpv2,
                  current: inverter.ipv2,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          const Text(
            'AC Output',
            style: TextStyle(color: AppColors.textSecondary, fontSize: 13),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(child: _AcPhase(phase: 'L1', v: inverter.vac1, a: inverter.iac1)),
              const SizedBox(width: 8),
              Expanded(child: _AcPhase(phase: 'L2', v: inverter.vac2, a: inverter.iac2)),
              const SizedBox(width: 8),
              Expanded(child: _AcPhase(phase: 'L3', v: inverter.vac3, a: inverter.iac3)),
            ],
          ),
        ],
      ),
    );
  }
}

class _Row extends StatelessWidget {
  final String label;
  final String value;

  const _Row({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(color: AppColors.textSecondary, fontSize: 13)),
          Text(value, style: const TextStyle(color: AppColors.textPrimary, fontSize: 13)),
        ],
      ),
    );
  }
}

class _InputChip extends StatelessWidget {
  final String label;
  final double voltage;
  final double current;

  const _InputChip({
    required this.label,
    required this.voltage,
    required this.current,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: AppColors.cardAlt,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: const TextStyle(color: AppColors.textSecondary, fontSize: 11)),
          const SizedBox(height: 4),
          Text('${voltage.toStringAsFixed(1)} V',
              style: const TextStyle(color: AppColors.textPrimary, fontSize: 13)),
          Text('${current.toStringAsFixed(2)} A',
              style: const TextStyle(color: AppColors.accent, fontSize: 12)),
        ],
      ),
    );
  }
}

class _AcPhase extends StatelessWidget {
  final String phase;
  final double v;
  final double a;

  const _AcPhase({required this.phase, required this.v, required this.a});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: AppColors.cardAlt,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        children: [
          Text(phase, style: const TextStyle(color: AppColors.textSecondary, fontSize: 11)),
          const SizedBox(height: 4),
          Text('${v.toStringAsFixed(0)}V',
              style: const TextStyle(color: AppColors.textPrimary, fontSize: 12)),
          Text('${a.toStringAsFixed(1)}A',
              style: const TextStyle(color: AppColors.green, fontSize: 11)),
        ],
      ),
    );
  }
}
