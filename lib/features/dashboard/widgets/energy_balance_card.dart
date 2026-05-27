import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../core/theme.dart';
import '../../../data/models/energy_balance.dart';
import '../../../data/models/tapo_reading.dart';
import '../../consumption/consumption_provider.dart';
import '../../consumption/tapo_devices_screen.dart';

/// Consumption color (no blue in AppColors, so defined here).
const _consumptionColor = Color(0xFF38BDF8);

void _openDevices(BuildContext context) {
  Navigator.of(context).push(
    MaterialPageRoute(builder: (_) => const TapoDevicesScreen()),
  );
}

class EnergyBalanceCard extends StatelessWidget {
  const EnergyBalanceCard({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<ConsumptionProvider>(
      builder: (context, provider, _) {
        return Container(
          width: double.infinity,
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: AppColors.card,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: AppColors.divider),
          ),
          child: switch (provider.status) {
            ConsumptionStatus.noAccount => const _Cta(
                body: 'Connect a Tapo P110 smart plug to track how much power '
                    'your home uses and compare it against your solar '
                    'production in real time.',
                button: 'Connect Tapo account',
              ),
            ConsumptionStatus.noDevices => const _Cta(
                body: 'Account connected. Add one or more Tapo plugs to start '
                    'tracking consumption.',
                button: 'Add a plug',
              ),
            ConsumptionStatus.loading => const _Loading(),
            ConsumptionStatus.error =>
              _ErrorState(message: provider.errorMessage),
            ConsumptionStatus.live => _Balance(
                balance: provider.balance!,
                readings: provider.readings,
              ),
          },
        );
      },
    );
  }
}

// ── Header shared across states ───────────────────────────────────────────────

class _Header extends StatelessWidget {
  final Widget? trailing;
  const _Header({this.trailing});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Row(
          children: [
            Container(
              padding: const EdgeInsets.all(7),
              decoration: BoxDecoration(
                color: _consumptionColor.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(9),
              ),
              child: const Icon(Icons.swap_vert_rounded,
                  color: _consumptionColor, size: 16),
            ),
            const SizedBox(width: 10),
            const Text('Energy Balance',
                style: TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 15,
                    fontWeight: FontWeight.w600)),
          ],
        ),
        ?trailing,
      ],
    );
  }
}

// ── CTA: connect account / add plug ───────────────────────────────────────────

class _Cta extends StatelessWidget {
  final String body;
  final String button;
  const _Cta({required this.body, required this.button});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _Header(),
        const SizedBox(height: 16),
        Text(
          body,
          style: const TextStyle(
              color: AppColors.textSecondary, fontSize: 13, height: 1.5),
        ),
        const SizedBox(height: 16),
        SizedBox(
          width: double.infinity,
          child: OutlinedButton.icon(
            onPressed: () => _openDevices(context),
            icon: const Icon(Icons.electrical_services_rounded, size: 18),
            style: OutlinedButton.styleFrom(
              foregroundColor: _consumptionColor,
              side: BorderSide(color: _consumptionColor.withValues(alpha: 0.4)),
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
            ),
            label: Text(button,
                style: const TextStyle(fontWeight: FontWeight.w600)),
          ),
        ),
      ],
    );
  }
}

// ── Loading ───────────────────────────────────────────────────────────────────

class _Loading extends StatelessWidget {
  const _Loading();
  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _Header(),
        const SizedBox(height: 24),
        Center(
          child: Column(
            children: const [
              SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(
                    strokeWidth: 2, color: _consumptionColor),
              ),
              SizedBox(height: 12),
              Text('Reading plug…',
                  style: TextStyle(
                      color: AppColors.textSecondary, fontSize: 12)),
            ],
          ),
        ),
        const SizedBox(height: 8),
      ],
    );
  }
}

// ── Error ───────────────────────────────────────────────────────────────────

class _ErrorState extends StatelessWidget {
  final String? message;
  const _ErrorState({this.message});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _Header(
          trailing: TextButton(
            onPressed: () => _openDevices(context),
            child: const Text('Manage',
                style: TextStyle(color: _consumptionColor, fontSize: 12)),
          ),
        ),
        const SizedBox(height: 14),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: AppColors.red.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: AppColors.red.withValues(alpha: 0.25)),
          ),
          child: Row(
            children: [
              const Icon(Icons.wifi_off_rounded, color: AppColors.red, size: 16),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  message ?? 'Could not reach the plug.',
                  style: const TextStyle(color: AppColors.red, fontSize: 12),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        const Text(
          'Make sure you\'re on the same Wi-Fi as the plug.',
          style: TextStyle(color: AppColors.textSecondary, fontSize: 11),
        ),
      ],
    );
  }
}

// ── Live balance ──────────────────────────────────────────────────────────────

class _Balance extends StatelessWidget {
  final EnergyBalance balance;
  final List<TapoReading> readings;
  const _Balance({required this.balance, required this.readings});

  @override
  Widget build(BuildContext context) {
    final surplus = balance.isSurplus;
    final netColor = surplus ? AppColors.green : AppColors.red;
    final netAbs = balance.netKwh.abs();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _Header(
          trailing: GestureDetector(
            onTap: () => _openDevices(context),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 6,
                  height: 6,
                  decoration: const BoxDecoration(
                      color: AppColors.green, shape: BoxShape.circle),
                ),
                const SizedBox(width: 6),
                Text('${readings.where((r) => r.online).length} live',
                    style: const TextStyle(
                        color: AppColors.textSecondary, fontSize: 11)),
                const SizedBox(width: 4),
                const Icon(Icons.chevron_right_rounded,
                    color: AppColors.textSecondary, size: 14),
              ],
            ),
          ),
        ),
        const SizedBox(height: 18),

        // Net headline
        Row(
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          children: [
            Text(
              '${surplus ? '+' : '−'}${netAbs.toStringAsFixed(2)}',
              style: TextStyle(
                  color: netColor,
                  fontSize: 34,
                  fontWeight: FontWeight.bold,
                  letterSpacing: -1),
            ),
            const SizedBox(width: 6),
            const Padding(
              padding: EdgeInsets.only(bottom: 4),
              child: Text('kWh',
                  style: TextStyle(
                      color: AppColors.textSecondary, fontSize: 14)),
            ),
          ],
        ),
        Text(
          surplus
              ? 'Surplus today — you generated more than you used'
              : 'Deficit today — you used more than you generated',
          style: const TextStyle(color: AppColors.textSecondary, fontSize: 12),
        ),
        const SizedBox(height: 20),

        // Comparison bars
        _Bar(
          label: 'Produced',
          valueKwh: balance.productionKwh,
          maxKwh: _max,
          color: AppColors.accent,
          icon: Icons.wb_sunny_rounded,
        ),
        const SizedBox(height: 12),
        _Bar(
          label: 'Consumed',
          valueKwh: balance.consumptionKwh,
          maxKwh: _max,
          color: _consumptionColor,
          icon: Icons.power_rounded,
        ),
        const SizedBox(height: 18),

        // Live now row
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color: AppColors.cardAlt,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _LiveStat(
                icon: Icons.wb_sunny_rounded,
                color: AppColors.accent,
                value: '${balance.liveProductionW.toStringAsFixed(0)} W',
                label: 'Generating',
              ),
              Container(width: 1, height: 30, color: AppColors.divider),
              _LiveStat(
                icon: Icons.power_rounded,
                color: _consumptionColor,
                value: '${balance.liveConsumptionW.toStringAsFixed(0)} W',
                label: 'Using',
              ),
            ],
          ),
        ),

        // Per-device breakdown (only when more than one plug)
        if (readings.length > 1) ...[
          const SizedBox(height: 16),
          const Divider(color: AppColors.divider, height: 1),
          const SizedBox(height: 14),
          ...readings.map((r) => _DeviceRow(reading: r)),
        ],
      ],
    );
  }

  double get _max {
    final m = balance.productionKwh > balance.consumptionKwh
        ? balance.productionKwh
        : balance.consumptionKwh;
    return m <= 0 ? 1 : m;
  }
}

class _DeviceRow extends StatelessWidget {
  final TapoReading reading;
  const _DeviceRow({required this.reading});

  @override
  Widget build(BuildContext context) {
    final online = reading.online;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        children: [
          Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(
              color: online ? AppColors.green : AppColors.textSecondary,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              reading.device.name,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                  color: AppColors.textPrimary, fontSize: 12),
            ),
          ),
          if (online) ...[
            Text('${reading.liveW.toStringAsFixed(0)} W',
                style: const TextStyle(
                    color: _consumptionColor,
                    fontSize: 12,
                    fontWeight: FontWeight.w600)),
            const SizedBox(width: 10),
            Text('${reading.todayKwh.toStringAsFixed(2)} kWh',
                style: const TextStyle(
                    color: AppColors.textSecondary, fontSize: 11)),
          ] else
            const Text('offline',
                style: TextStyle(
                    color: AppColors.textSecondary, fontSize: 11)),
        ],
      ),
    );
  }
}

class _Bar extends StatelessWidget {
  final String label;
  final double valueKwh;
  final double maxKwh;
  final Color color;
  final IconData icon;

  const _Bar({
    required this.label,
    required this.valueKwh,
    required this.maxKwh,
    required this.color,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    final fraction = (valueKwh / maxKwh).clamp(0.0, 1.0);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(icon, color: color, size: 13),
            const SizedBox(width: 6),
            Text(label,
                style: const TextStyle(
                    color: AppColors.textSecondary, fontSize: 12)),
            const Spacer(),
            Text('${valueKwh.toStringAsFixed(2)} kWh',
                style: TextStyle(
                    color: color, fontSize: 12, fontWeight: FontWeight.w600)),
          ],
        ),
        const SizedBox(height: 6),
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: TweenAnimationBuilder<double>(
            tween: Tween(begin: 0, end: fraction),
            duration: const Duration(milliseconds: 900),
            curve: Curves.easeOutCubic,
            builder: (context, v, _) => LinearProgressIndicator(
              value: v,
              minHeight: 8,
              backgroundColor: AppColors.divider,
              valueColor: AlwaysStoppedAnimation(color),
            ),
          ),
        ),
      ],
    );
  }
}

class _LiveStat extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String value;
  final String label;

  const _LiveStat({
    required this.icon,
    required this.color,
    required this.value,
    required this.label,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, color: color, size: 18),
        const SizedBox(width: 8),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(value,
                style: TextStyle(
                    color: color, fontSize: 15, fontWeight: FontWeight.bold)),
            Text(label,
                style: const TextStyle(
                    color: AppColors.textSecondary, fontSize: 10)),
          ],
        ),
      ],
    );
  }
}
