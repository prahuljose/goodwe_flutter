import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/theme.dart';
import '../../data/models/monthly_energy.dart';
import '../../data/models/demo_data.dart';
import '../../repositories/auth_repository.dart';
import '../../repositories/station_repository.dart';

class AlarmHistoryScreen extends StatefulWidget {
  final String stationId;

  const AlarmHistoryScreen({super.key, required this.stationId});

  @override
  State<AlarmHistoryScreen> createState() => _AlarmHistoryScreenState();
}

class _AlarmHistoryScreenState extends State<AlarmHistoryScreen> {
  List<AlarmRecord> _alarms = [];
  bool _isLoading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _fetch();
  }

  Future<void> _fetch() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    final auth = context.read<AuthRepository>();

    try {
      if (auth.isDemoMode) {
        await Future.delayed(const Duration(milliseconds: 600));
        if (mounted) {
          setState(() {
            _alarms = DemoData.alarmHistory();
            _isLoading = false;
          });
        }
        return;
      }

      // Ensure a live session exists
      if (auth.currentSession == null) {
        final ok = await auth.tryRelogin();
        if (!mounted) return;
        if (!ok) {
          setState(() {
            _error = 'Session expired. Please sign in again.';
            _isLoading = false;
          });
          return;
        }
      }

      final repo = context.read<StationRepository>();
      final alarms = await repo.fetchAlarms(
          auth.currentSession!, widget.stationId);

      if (mounted) {
        setState(() {
          _alarms = alarms;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded,
              color: AppColors.textSecondary),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: const Text(
          'Alarm History',
          style: TextStyle(
            color: AppColors.textPrimary,
            fontSize: 16,
            fontWeight: FontWeight.w700,
          ),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded,
                color: AppColors.textSecondary, size: 20),
            onPressed: _isLoading ? null : _fetch,
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: _buildBody(),
    );
  }

  static String _errorHint(String raw) {
    final lower = raw.toLowerCase();
    if (lower.contains('ver is not') || lower.contains('not fund') ||
        lower.contains('not found')) {
      return 'The alarm history endpoint is not available on this account\'s '
          'SEMS server. This feature requires the correct API path — check the '
          'API Logs to see the URL that was tried, then confirm the path from '
          'the SEMS web portal (semsportal.com → Alarms tab, DevTools → Network).';
    }
    return raw;
  }

  Widget _buildBody() {
    if (_isLoading) {
      return const Center(
        child: CircularProgressIndicator(
          color: AppColors.accent,
          strokeWidth: 2,
        ),
      );
    }

    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  color: AppColors.red.withValues(alpha: 0.1),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.error_outline_rounded,
                    color: AppColors.red, size: 36),
              ),
              const SizedBox(height: 16),
              const Text(
                'Could not load alarms',
                style: TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                _errorHint(_error!),
                style: const TextStyle(
                    color: AppColors.textSecondary, fontSize: 12),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 24),
              ElevatedButton.icon(
                onPressed: _fetch,
                icon: const Icon(Icons.refresh_rounded, size: 16),
                label: const Text('Try Again'),
              ),
            ],
          ),
        ),
      );
    }

    if (_alarms.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                color: AppColors.green.withValues(alpha: 0.1),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.check_circle_outline_rounded,
                  color: AppColors.green, size: 36),
            ),
            const SizedBox(height: 16),
            const Text(
              'No alarms on record',
              style: TextStyle(
                color: AppColors.textPrimary,
                fontSize: 16,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 6),
            const Text(
              'Your inverter has been running without any\nreported faults or warnings.',
              style:
                  TextStyle(color: AppColors.textSecondary, fontSize: 12),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      );
    }

    final active   = _alarms.where((a) => a.isActive).toList();
    final resolved = _alarms.where((a) => !a.isActive).toList();

    return RefreshIndicator(
      color: AppColors.accent,
      backgroundColor: AppColors.card,
      onRefresh: _fetch,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: [
          if (active.isNotEmpty) ...[
            _sectionHeader('Active', active.length, const Color(0xFFF87171)),
            const SizedBox(height: 8),
            ...active.map((a) => _AlarmCard(alarm: a)),
            const SizedBox(height: 16),
          ],
          if (resolved.isNotEmpty) ...[
            _sectionHeader('Resolved', resolved.length, AppColors.green),
            const SizedBox(height: 8),
            ...resolved.map((a) => _AlarmCard(alarm: a)),
          ],
        ],
      ),
    );
  }

  Widget _sectionHeader(String label, int count, Color color) {
    return Row(
      children: [
        Text(
          label.toUpperCase(),
          style: const TextStyle(
            color: AppColors.textSecondary,
            fontSize: 11,
            fontWeight: FontWeight.w600,
            letterSpacing: 1.2,
          ),
        ),
        const SizedBox(width: 8),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Text(
            '$count',
            style: TextStyle(
              color: color,
              fontSize: 11,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ],
    );
  }
}

// ─── Alarm card ────────────────────────────────────────────────────────────

class _AlarmCard extends StatelessWidget {
  final AlarmRecord alarm;

  const _AlarmCard({required this.alarm});

  @override
  Widget build(BuildContext context) {
    final isFault = alarm.isFault;
    final color   = isFault ? const Color(0xFFF87171) : const Color(0xFFFBBF24);
    final icon    = isFault
        ? Icons.error_outline_rounded
        : Icons.warning_amber_rounded;

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AppColors.card,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppColors.divider),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Title row
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(icon, color: color, size: 14),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    isFault ? 'Fault' : 'Warning',
                    style: TextStyle(
                      color: color,
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                // Status badge
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: alarm.isActive
                        ? color.withValues(alpha: 0.12)
                        : AppColors.green.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    alarm.isActive ? 'Active' : 'Resolved',
                    style: TextStyle(
                      color: alarm.isActive ? color : AppColors.green,
                      fontSize: 10,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),

            // Code + message
            const SizedBox(height: 10),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: AppColors.cardAlt,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(
                        'Code ${alarm.alarmCode}',
                        style: TextStyle(
                          color: color,
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          alarm.message.isNotEmpty
                              ? alarm.message
                              : 'Refer to inverter manual',
                          style: const TextStyle(
                            color: AppColors.textSecondary,
                            fontSize: 11,
                            height: 1.4,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),

            // Timestamps
            const SizedBox(height: 10),
            _TimeRow(
              icon: Icons.schedule_outlined,
              label: 'Happened',
              value: _fmtTime(alarm.happenTime),
            ),
            if (alarm.recoverTime != null) ...[
              const SizedBox(height: 4),
              _TimeRow(
                icon: Icons.check_circle_outline_rounded,
                label: 'Resolved',
                value: _fmtTime(alarm.recoverTime!),
                valueColor: AppColors.green,
              ),
            ],
            if (alarm.duration != null) ...[
              const SizedBox(height: 4),
              _TimeRow(
                icon: Icons.timelapse_rounded,
                label: 'Duration',
                value: _fmtDuration(alarm.duration!),
              ),
            ],
            if (alarm.sn.isNotEmpty) ...[
              const SizedBox(height: 4),
              _TimeRow(
                icon: Icons.memory_rounded,
                label: 'Inverter',
                value: alarm.sn,
              ),
            ],
          ],
        ),
      ),
    );
  }

  static String _fmtTime(DateTime t) {
    String p(int n) => n.toString().padLeft(2, '0');
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
    ];
    return '${t.day} ${months[t.month - 1]} ${t.year}  '
        '${p(t.hour)}:${p(t.minute)}';
  }

  static String _fmtDuration(Duration d) {
    if (d.inMinutes < 60) return '${d.inMinutes} min';
    final h = d.inHours;
    final m = d.inMinutes % 60;
    return m > 0 ? '${h}h ${m}m' : '${h}h';
  }
}

class _TimeRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final Color valueColor;

  const _TimeRow({
    required this.icon,
    required this.label,
    required this.value,
    this.valueColor = AppColors.textSecondary,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, color: AppColors.textSecondary, size: 12),
        const SizedBox(width: 6),
        Text(
          '$label:  ',
          style: const TextStyle(
              color: AppColors.textSecondary, fontSize: 11),
        ),
        Expanded(
          child: Text(
            value,
            style: TextStyle(
              color: valueColor,
              fontSize: 11,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
      ],
    );
  }
}
