import 'package:flutter/material.dart';
import '../../../core/theme.dart';
import '../../../data/models/station_monitor.dart';

void _showInfoSheet(BuildContext context, InverterData inverter) {
  showModalBottomSheet(
    context: context,
    backgroundColor: AppColors.card,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
    ),
    isScrollControlled: true,
    builder: (_) => SingleChildScrollView(
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
                'Inverter Diagnostics',
                style: TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 17,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),

          // ── Live status block ────────────────────────────────────────────
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
                const Text('Current readings',
                    style: TextStyle(
                        color: AppColors.textSecondary,
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        letterSpacing: 1.0)),
                const SizedBox(height: 12),
                _DiagRow(label: 'Status',
                    value: inverter.statusLabel,
                    valueColor: inverter.hasFault
                        ? const Color(0xFFF87171)
                        : inverter.hasWarning
                            ? const Color(0xFFFBBF24)
                            : AppColors.green),
                _DiagRow(
                    label: 'Error code',
                    value: inverter.errorCode == 0
                        ? '0  (none)'
                        : '${inverter.errorCode}',
                    valueColor: inverter.errorCode != 0
                        ? const Color(0xFFF87171)
                        : AppColors.textSecondary),
                _DiagRow(
                    label: 'Warning code',
                    value: inverter.warningCode == 0
                        ? '0  (none)'
                        : '${inverter.warningCode}',
                    valueColor: inverter.warningCode != 0
                        ? const Color(0xFFFBBF24)
                        : AppColors.textSecondary),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // ── Error code reference ─────────────────────────────────────────
          const Text('GoodWe error code reference',
              style: TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 14,
                  fontWeight: FontWeight.w600)),
          const SizedBox(height: 6),
          const Text(
            'These are sequential numeric codes reported by the inverter. '
            'A value of 0 means no fault. If you see a non-zero code, '
            'the description below identifies the likely cause.',
            style: TextStyle(
                color: AppColors.textSecondary, fontSize: 12, height: 1.5),
          ),
          const SizedBox(height: 12),
          ..._errorCodeRows(),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppColors.accent.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                  color: AppColors.accent.withValues(alpha: 0.25)),
            ),
            child: const Row(
              children: [
                Icon(Icons.link_rounded, color: AppColors.accent, size: 15),
                SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Full fault documentation: GoodWe inverter manual '
                    'or semsportal.com → Alarms tab.',
                    style: TextStyle(
                        color: AppColors.textSecondary,
                        fontSize: 11,
                        height: 1.4),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    ),
  );
}

List<Widget> _errorCodeRows() {
  const codes = <int, String>{
    1:  'SPI failure — internal communication error',
    2:  'Memory (EEPROM) read/write failure',
    3:  'Grid frequency out of range',
    7:  'Relay self-check failure',
    12: 'DSP ↔ LCD communication failure',
    13: 'DC injection too high',
    14: 'Isolation failure — insulation resistance too low',
    15: 'Grid voltage out of range',
    16: 'External cooling fan failure',
    17: 'PV array over-voltage',
    19: 'Over-temperature — check ventilation',
    20: 'Internal fan failure',
    21: 'DC bus over-voltage',
    22: 'Residual current (ground fault) detected',
    23: 'Grid disconnection / utility loss',
    24: 'AC current sensor failure',
    25: 'Relay check failure',
    26: 'GFCI — leakage current exceeds safe limit',
    30: 'Reference voltage fault (1.5 V rail)',
    31: 'AC current sensor failure',
    32: 'GFCI detection circuit failure',
  };
  return codes.entries.map((e) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 4),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 30,
          child: Text(
            '${e.key}',
            style: const TextStyle(
                color: AppColors.accent,
                fontSize: 12,
                fontWeight: FontWeight.w600),
          ),
        ),
        Expanded(
          child: Text(
            e.value,
            style: const TextStyle(
                color: AppColors.textSecondary, fontSize: 12, height: 1.4),
          ),
        ),
      ],
    ),
  )).toList();
}

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
          if (inverter.hasFault || inverter.hasWarning) ...[
            _FaultBanner(inverter: inverter),
            const SizedBox(height: 12),
          ],
          Row(
            children: [
              const Expanded(
                child: Text(
                  'Inverter',
                  style: TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              Text(
                inverter.model,
                style: const TextStyle(color: AppColors.accent, fontSize: 12),
              ),
              const SizedBox(width: 10),
              GestureDetector(
                onTap: () => _showInfoSheet(context, inverter),
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

class _FaultBanner extends StatelessWidget {
  final InverterData inverter;
  const _FaultBanner({required this.inverter});

  @override
  Widget build(BuildContext context) {
    final isError = inverter.hasFault;
    final color   = isError ? const Color(0xFFF87171) : const Color(0xFFFBBF24);
    final icon    = isError ? Icons.error_outline_rounded : Icons.warning_amber_rounded;
    final title   = isError ? 'Inverter Fault Detected' : 'Inverter Warning';
    final body    = inverter.faultLabel.isNotEmpty
        ? inverter.faultLabel
        : isError
            ? 'The inverter has reported an error. Check the inverter display.'
            : 'The inverter has reported a warning.';

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: color, size: 18),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    color: color,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  body,
                  style: const TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 12,
                    height: 1.4,
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

class _DiagRow extends StatelessWidget {
  final String label;
  final String value;
  final Color valueColor;

  const _DiagRow({
    required this.label,
    required this.value,
    required this.valueColor,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label,
              style: const TextStyle(
                  color: AppColors.textSecondary, fontSize: 13)),
          Text(value,
              style: TextStyle(
                  color: valueColor,
                  fontSize: 13,
                  fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }
}
