import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/exceptions.dart';
import '../../core/theme.dart';
import '../../data/local/settings_storage.dart';
import '../../data/models/station_monitor.dart';
import '../../repositories/auth_repository.dart';
import '../../repositories/station_repository.dart';
import 'widgets/animated_value.dart';
import 'widgets/kpi_card.dart';
import 'widgets/weather_card.dart';
import 'widgets/environmental_card.dart';
import 'widgets/inverter_card.dart';
import 'widgets/insights_card.dart';
import 'widgets/api_log_sheet.dart';
import 'widgets/power_chart.dart';
import '../../data/remote/api_logger.dart';
import '../../data/models/demo_data.dart';

const _stationId = 'e3c2c54c-c872-4fdb-8147-99381e685cff';

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen>
    with TickerProviderStateMixin {
  StationMonitor? _monitor;
  List<PacSample> _pacSamples = [];
  String _pacDateLabel = 'Today';
  bool _isLoading = true;
  SemsError? _error;
  double? _earningsRate;

  late final AnimationController _staggerCtrl;

  @override
  void initState() {
    super.initState();
    _staggerCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    );
    _fetchData();
    _loadEarningsRate();
  }

  @override
  void dispose() {
    _staggerCtrl.dispose();
    super.dispose();
  }

  Future<void> _fetchData() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });
    _staggerCtrl.reset();

    // Capture context-dependent objects before any async gap
    final auth = context.read<AuthRepository>();
    final stationRepo = context.read<StationRepository>();

    try {
      // ── Demo mode — no API calls, no session needed ────────────────
      if (auth.isDemoMode) {
        await Future.delayed(const Duration(milliseconds: 800));
        if (mounted) {
          setState(() {
            _monitor = DemoData.stationMonitor();
            _pacSamples = DemoData.pacSamples();
            _pacDateLabel = 'Today';
          });
          _staggerCtrl.forward();
        }
        return;
      }

      // ── Ensure we have a live session ─────────────────────────────
      // currentSession is null when the app starts cold OR after a
      // previous invalidateSession() call (e.g. token expired on last
      // refresh). Try a silent re-login before giving up.
      if (auth.currentSession == null) {
        final reloggedIn = await auth.tryRelogin();
        if (!mounted) return;
        if (!reloggedIn) {
          _redirectToLogin();
          return;
        }
      }

      // ── Fetch monitor data ─────────────────────────────────────────
      StationMonitor monitor;
      try {
        monitor = await stationRepo.fetchMonitor(
            auth.currentSession!, _stationId);
      } on SemsAuthError {
        // Token expired mid-session — invalidate and try once more
        await auth.invalidateSession();
        if (!mounted) return;

        final reloggedIn = await auth.tryRelogin();
        if (!mounted) return;

        if (!reloggedIn) {
          // No saved creds or password changed — fall back gracefully
          _monitor != null
              ? _showSessionExpiredBanner()
              : _redirectToLogin();
          return;
        }

        // Got a fresh session — retry the fetch transparently
        monitor = await stationRepo.fetchMonitor(
            auth.currentSession!, _stationId);
      }

      // Fetch intra-day PAC chart (non-critical — chart simply won't show on error)
      List<PacSample> pacSamples = [];
      try {
        pacSamples = await stationRepo.fetchPacByDay(
            auth.currentSession!, _stationId, DateTime.now());
      } catch (_) {
        // Silently swallow — the power curve card is supplemental
      }

      if (mounted) {
        setState(() {
          _monitor = monitor;
          _pacSamples = pacSamples;
          _pacDateLabel = 'Today';
        });
        _staggerCtrl.forward();
      }
    } on SemsAuthError {
      // Retry also failed with auth error (password changed, account
      // disabled, etc.) — nothing more we can do silently.
      await auth.invalidateSession();
      if (!mounted) return;
      _monitor != null ? _showSessionExpiredBanner() : _redirectToLogin();
    } on SemsNetworkError catch (e) {
      if (mounted) setState(() => _error = e);
    } on SemsServerError catch (e) {
      if (mounted) setState(() => _error = e);
    } on SemsApiError catch (e) {
      if (mounted) setState(() => _error = e);
    } catch (e) {
      if (mounted) setState(() => _error = SemsApiError(e.toString()));
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _loadEarningsRate() async {
    final storage = context.read<SettingsStorage>();
    final rate = await storage.loadEarningsRate();
    if (mounted) setState(() => _earningsRate = rate);
  }

  Future<void> _showEarningsDialog() async {
    final result = await showDialog<double>(
      context: context,
      builder: (ctx) => _EarningsRateDialog(currentRate: _earningsRate),
    );
    if (result == null || !mounted) return;

    final storage = context.read<SettingsStorage>();
    if (result <= 0) {
      await storage.clearEarningsRate();
      if (mounted) setState(() => _earningsRate = null);
    } else {
      await storage.saveEarningsRate(result);
      if (mounted) setState(() => _earningsRate = result);
    }
  }

  void _redirectToLogin() {
    Navigator.of(context).pushReplacementNamed('/login');
  }

  void _showSessionExpiredBanner() {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showMaterialBanner(
      MaterialBanner(
        backgroundColor: AppColors.card,
        leading: const Icon(Icons.lock_outline_rounded, color: AppColors.accent),
        content: const Text(
          'Session expired — data may be stale.',
          style: TextStyle(color: AppColors.textPrimary),
        ),
        actions: [
          TextButton(
            onPressed: () =>
                ScaffoldMessenger.of(context).hideCurrentMaterialBanner(),
            child: const Text('Dismiss',
                style: TextStyle(color: AppColors.textSecondary)),
          ),
          TextButton(
            onPressed: () {
              ScaffoldMessenger.of(context).hideCurrentMaterialBanner();
              _redirectToLogin();
            },
            child: const Text('Sign In',
                style: TextStyle(
                    color: AppColors.accent, fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );
  }

  Future<void> _logout() async {
    await context.read<AuthRepository>().logout();
    if (!mounted) return;
    Navigator.of(context).pushReplacementNamed('/login');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_isLoading) return _buildSkeleton();
    if (_error != null) return _buildError(_error!);
    if (_monitor == null) return const SizedBox.shrink();
    return _buildContent(_monitor!);
  }

  // ── Shimmer skeleton ─────────────────────────────────────────────────────

  Widget _buildSkeleton() {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const ShimmerBox(width: 180, height: 24),
            const SizedBox(height: 24),
            const ShimmerBox(width: double.infinity, height: 220, borderRadius: 24),
            const SizedBox(height: 16),
            Row(children: const [
              Expanded(child: ShimmerBox(width: double.infinity, height: 100)),
              SizedBox(width: 10),
              Expanded(child: ShimmerBox(width: double.infinity, height: 100)),
              SizedBox(width: 10),
              Expanded(child: ShimmerBox(width: double.infinity, height: 100)),
            ]),
            const SizedBox(height: 16),
            const ShimmerBox(width: double.infinity, height: 160, borderRadius: 20),
          ],
        ),
      ),
    );
  }

  // ── Error state ───────────────────────────────────────────────────────────

  Widget _buildError(SemsError error) {
    final config = _errorConfig(error);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: config.color.withValues(alpha: 0.1),
                shape: BoxShape.circle,
              ),
              child: Icon(config.icon, size: 40, color: config.color),
            ),
            const SizedBox(height: 20),
            Text(
              config.title,
              style: const TextStyle(
                color: AppColors.textPrimary,
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              error.message,
              style: const TextStyle(
                  color: AppColors.textSecondary, fontSize: 13),
              textAlign: TextAlign.center,
            ),
            if (error is SemsApiError && error.code != null) ...[
              const SizedBox(height: 6),
              Text(
                'Error code: ${error.code}',
                style: const TextStyle(
                    color: AppColors.textSecondary, fontSize: 11),
              ),
            ],
            const SizedBox(height: 28),
            ElevatedButton.icon(
              onPressed: _fetchData,
              icon: const Icon(Icons.refresh_rounded, size: 18),
              label: const Text('Try Again'),
            ),
          ],
        ),
      ),
    );
  }

  _ErrorConfig _errorConfig(SemsError error) {
    return switch (error) {
      SemsNetworkError() => const _ErrorConfig(
          icon: Icons.wifi_off_rounded,
          title: 'No Connection',
          color: Color(0xFF60A5FA),
        ),
      SemsServerError() => const _ErrorConfig(
          icon: Icons.dns_rounded,
          title: 'Server Error',
          color: Color(0xFFF87171),
        ),
      SemsAuthError() => const _ErrorConfig(
          icon: Icons.lock_outline_rounded,
          title: 'Session Expired',
          color: AppColors.accent,
        ),
      SemsApiError() => const _ErrorConfig(
          icon: Icons.cloud_off_rounded,
          title: 'Could Not Load Data',
          color: AppColors.textSecondary,
        ),
    };
  }

  // ── Main content ──────────────────────────────────────────────────────────

  Widget _buildContent(StationMonitor m) {
    final inverter = m.primaryInverter;
    final now = DateTime.now();

    return RefreshIndicator(
      color: AppColors.accent,
      backgroundColor: AppColors.card,
      onRefresh: _fetchData,
      child: CustomScrollView(
        slivers: [
          _buildAppBar(m),
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 32),
            sliver: SliverList(
              delegate: SliverChildListDelegate([
                // Live power hero
                _Staggered(
                  ctrl: _staggerCtrl,
                  index: 0,
                  child: LivePowerCard(
                    pac: m.kpi.pac,
                    status: m.info.status,
                    workMode: inverter?.workMode ?? '',
                    capacityKw: m.info.capacity,
                  ),
                ),
                const SizedBox(height: 16),

                // Energy KPIs
                _Staggered(
                  ctrl: _staggerCtrl,
                  index: 1,
                  child: _SectionLabel(label: 'Energy Generation'),
                ),
                const SizedBox(height: 10),
                _Staggered(
                  ctrl: _staggerCtrl,
                  index: 1,
                  child: Row(children: [
                    Expanded(
                      child: KpiCard(
                        label: 'Today',
                        value: m.kpi.todayKwh,
                        unit: 'kWh',
                        icon: Icons.wb_sunny_outlined,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: KpiCard(
                        label: 'This Month',
                        value: m.kpi.monthKwh,
                        unit: 'kWh',
                        icon: Icons.calendar_month_outlined,
                        iconColor: const Color(0xFF818CF8),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: KpiCard(
                        label: 'Total',
                        value: m.kpi.totalKwh >= 1000
                            ? m.kpi.totalKwh / 1000
                            : m.kpi.totalKwh,
                        unit: m.kpi.totalKwh >= 1000 ? 'MWh' : 'kWh',
                        icon: Icons.bolt_outlined,
                        iconColor: AppColors.green,
                        formatter: (v) => v.toStringAsFixed(2),
                      ),
                    ),
                  ]),
                ),
                const SizedBox(height: 16),

                // Intra-day power curve
                if (_pacSamples.isNotEmpty)
                  _Staggered(
                    ctrl: _staggerCtrl,
                    index: 2,
                    child: PowerCurveCard(
                      samples: _pacSamples,
                      dateLabel: _pacDateLabel,
                    ),
                  ),
                if (_pacSamples.isNotEmpty) const SizedBox(height: 16),

                // Income KPIs
                _Staggered(
                  ctrl: _staggerCtrl,
                  index: 3,
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      _SectionLabel(label: 'Earnings (${m.kpi.currency})'),
                      const SizedBox(width: 8),
                      if (_earningsRate != null) ...[
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 7, vertical: 2),
                          decoration: BoxDecoration(
                            color: AppColors.accent.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(
                                color: AppColors.accent.withValues(alpha: 0.35)),
                          ),
                          child: Text(
                            '₹${_earningsRate!.toStringAsFixed(2).replaceAll(RegExp(r'\.?0+$'), '')}/kWh',
                            style: const TextStyle(
                              color: AppColors.accent,
                              fontSize: 10,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        const SizedBox(width: 6),
                      ],
                      GestureDetector(
                        onTap: _showEarningsDialog,
                        child: Icon(
                          _earningsRate != null
                              ? Icons.edit_rounded
                              : Icons.edit_outlined,
                          color: _earningsRate != null
                              ? AppColors.accent
                              : AppColors.textSecondary,
                          size: 15,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 10),
                _Staggered(
                  ctrl: _staggerCtrl,
                  index: 3,
                  child: Row(children: [
                    Expanded(
                      child: KpiCard(
                        label: 'Today',
                        value: _earningsRate != null
                            ? m.kpi.todayKwh * _earningsRate!
                            : m.kpi.todayIncome,
                        unit: '₹ earned',
                        icon: Icons.currency_rupee,
                        iconColor: AppColors.green,
                        formatter: (v) => '₹${v.toStringAsFixed(1)}',
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: KpiCard(
                        label: 'Total',
                        value: _earningsRate != null
                            ? m.kpi.totalKwh * _earningsRate!
                            : m.kpi.totalIncome,
                        unit: '₹ lifetime',
                        icon: Icons.account_balance_wallet_outlined,
                        iconColor: AppColors.green,
                        formatter: (v) => v >= 1000
                            ? '₹${(v / 1000).toStringAsFixed(1)}k'
                            : '₹${v.toStringAsFixed(0)}',
                      ),
                    ),
                  ]),
                ),
                const SizedBox(height: 16),

                // Monthly performance
                _Staggered(
                  ctrl: _staggerCtrl,
                  index: 4,
                  child: MonthlyPerformanceCard(
                    monthKwh: m.kpi.monthKwh,
                    capacityKw: m.info.capacity,
                    dayOfMonth: now.day,
                    forecast: m.forecast,
                  ),
                ),
                const SizedBox(height: 16),

                // Today's energy insights
                _Staggered(
                  ctrl: _staggerCtrl,
                  index: 5,
                  child: TodayInsightsCard(todayKwh: m.kpi.todayKwh),
                ),
                const SizedBox(height: 16),

                // CO2 & lifetime insights
                _Staggered(
                  ctrl: _staggerCtrl,
                  index: 6,
                  child: Co2InsightsCard(
                    co2Tonnes: m.environmental.co2Tonnes,
                    totalKwh: m.kpi.totalKwh,
                    totalIncome: m.kpi.totalIncome,
                  ),
                ),
                const SizedBox(height: 16),

                // Environmental impact
                _Staggered(
                  ctrl: _staggerCtrl,
                  index: 7,
                  child: EnvironmentalCard(data: m.environmental),
                ),
                const SizedBox(height: 16),

                // Weather forecast
                _Staggered(
                  ctrl: _staggerCtrl,
                  index: 8,
                  child: WeatherSection(forecast: m.forecast),
                ),
                const SizedBox(height: 16),

                // Inverter details
                if (inverter != null)
                  _Staggered(
                    ctrl: _staggerCtrl,
                    index: 9,
                    child: InverterCard(inverter: inverter),
                  ),
                const SizedBox(height: 16),

                // Last updated
                Center(
                  child: Text(
                    'Last updated: ${inverter?.lastRefreshTime ?? m.info.time}',
                    style: const TextStyle(
                        color: AppColors.textSecondary, fontSize: 11),
                  ),
                ),
              ]),
            ),
          ),
        ],
      ),
    );
  }

  // ── Custom SliverAppBar ───────────────────────────────────────────────────

  Widget _buildAppBar(StationMonitor m) {
    return SliverAppBar(
      backgroundColor: AppColors.background,
      floating: true,
      snap: true,
      elevation: 0,
      title: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            m.info.name,
            style: const TextStyle(
              color: AppColors.textPrimary,
              fontSize: 16,
              fontWeight: FontWeight.w700,
            ),
          ),
          Text(
            'Thrissur, Kerala',
            style: const TextStyle(
              color: AppColors.textSecondary,
              fontSize: 11,
            ),
          ),
        ],
      ),
      actions: [
        IconButton(
          icon: const Icon(Icons.refresh_rounded, color: AppColors.textSecondary, size: 22),
          onPressed: _isLoading ? null : _fetchData,
        ),
        IconButton(
          icon: const Icon(Icons.terminal_rounded, color: AppColors.textSecondary, size: 20),
          tooltip: 'API Logs',
          onPressed: () => ApiLogSheet.show(
            context,
            context.read<ApiCallLogger>(),
          ),
        ),
        IconButton(
          icon: const Icon(Icons.logout_rounded, color: AppColors.textSecondary, size: 22),
          onPressed: _logout,
        ),
        const SizedBox(width: 4),
      ],
    );
  }
}

// ─── Staggered animation wrapper ──────────────────────────────────────────

class _Staggered extends StatelessWidget {
  final AnimationController ctrl;
  final int index;
  final Widget child;

  // Each card takes 0.4 of the total timeline, staggered by 0.1 per index
  static const _duration = 0.4;
  static const _step = 0.08;

  const _Staggered({
    required this.ctrl,
    required this.index,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    final start = (index * _step).clamp(0.0, 1.0 - _duration);
    final end = (start + _duration).clamp(0.0, 1.0);

    final opacity = CurvedAnimation(
      parent: ctrl,
      curve: Interval(start, end, curve: Curves.easeOut),
    );

    final slide = Tween<Offset>(
      begin: const Offset(0, 0.15),
      end: Offset.zero,
    ).animate(CurvedAnimation(
      parent: ctrl,
      curve: Interval(start, end, curve: Curves.easeOutCubic),
    ));

    return FadeTransition(
      opacity: opacity,
      child: SlideTransition(position: slide, child: child),
    );
  }
}

// ─── Section label ─────────────────────────────────────────────────────────

class _SectionLabel extends StatelessWidget {
  final String label;
  const _SectionLabel({required this.label});

  @override
  Widget build(BuildContext context) {
    return Text(
      label.toUpperCase(),
      style: const TextStyle(
        color: AppColors.textSecondary,
        fontSize: 11,
        fontWeight: FontWeight.w600,
        letterSpacing: 1.2,
      ),
    );
  }
}

// ─── Error display config ──────────────────────────────────────────────────

class _ErrorConfig {
  final IconData icon;
  final String title;
  final Color color;
  const _ErrorConfig({
    required this.icon,
    required this.title,
    required this.color,
  });
}

// ─── Earnings rate override dialog ────────────────────────────────────────────

class _EarningsRateDialog extends StatefulWidget {
  final double? currentRate;
  const _EarningsRateDialog({this.currentRate});

  @override
  State<_EarningsRateDialog> createState() => _EarningsRateDialogState();
}

class _EarningsRateDialogState extends State<_EarningsRateDialog> {
  late final TextEditingController _ctrl;
  String? _validationError;

  @override
  void initState() {
    super.initState();
    final existing = widget.currentRate;
    _ctrl = TextEditingController(
      text: existing != null
          ? existing.toStringAsFixed(2).replaceAll(RegExp(r'\.?0+$'), '')
          : '',
    );
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  void _onSave() {
    final text = _ctrl.text.trim();
    if (text.isEmpty) {
      // Blank → clear override, fall back to API values
      Navigator.pop(context, 0.0);
      return;
    }
    final rate = double.tryParse(text);
    if (rate == null || rate <= 0) {
      setState(() => _validationError = 'Enter a valid rate greater than 0');
      return;
    }
    Navigator.pop(context, rate);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: AppColors.card,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      title: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: AppColors.accent.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(Icons.currency_rupee,
                color: AppColors.accent, size: 18),
          ),
          const SizedBox(width: 12),
          const Text(
            'Earnings Rate',
            style: TextStyle(
              color: AppColors.textPrimary,
              fontSize: 16,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Enter your feed-in tariff or the rate you receive per unit sold to the grid.',
            style: TextStyle(
              color: AppColors.textSecondary,
              fontSize: 13,
              height: 1.5,
            ),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _ctrl,
            keyboardType:
                const TextInputType.numberWithOptions(decimal: true),
            autofocus: true,
            onChanged: (_) {
              if (_validationError != null) {
                setState(() => _validationError = null);
              }
            },
            style: const TextStyle(
              color: AppColors.textPrimary,
              fontSize: 18,
              fontWeight: FontWeight.w600,
            ),
            decoration: InputDecoration(
              prefixText: '₹  ',
              prefixStyle: const TextStyle(
                color: AppColors.accent,
                fontSize: 16,
                fontWeight: FontWeight.w600,
              ),
              suffixText: '/ kWh',
              suffixStyle: const TextStyle(
                color: AppColors.textSecondary,
                fontSize: 12,
              ),
              hintText: 'e.g. 4.50',
              errorText: _validationError,
              errorStyle:
                  const TextStyle(color: AppColors.red, fontSize: 11),
            ),
          ),
          if (widget.currentRate != null) ...[
            const SizedBox(height: 12),
            GestureDetector(
              onTap: () => Navigator.pop(context, 0.0),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: const [
                  Icon(Icons.restart_alt_rounded,
                      color: AppColors.textSecondary, size: 13),
                  SizedBox(width: 4),
                  Text(
                    'Reset to API values',
                    style: TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 12,
                      decoration: TextDecoration.underline,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text(
            'Cancel',
            style: TextStyle(color: AppColors.textSecondary),
          ),
        ),
        TextButton(
          onPressed: _onSave,
          child: const Text(
            'Save',
            style: TextStyle(
              color: AppColors.accent,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ],
    );
  }
}
