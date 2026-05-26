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
import 'widgets/monthly_bar_chart.dart';
import '../../data/remote/api_logger.dart';
import '../../data/models/demo_data.dart';
import '../../data/models/monthly_energy.dart';
import '../../data/local/credentials_storage.dart';
import '../alarm/alarm_history_screen.dart';

// ─── Dashboard sections ────────────────────────────────────────────────────

enum DashboardSection {
  liveOutput,
  energyGeneration,
  earnings,
  monthlyPerformance,
  lifetimeImpact,
  environmental,
  forecast,
  inverterDetails,
}

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen>
    with TickerProviderStateMixin {
  StationMonitor? _monitor;
  String    _stationId     = CredentialsStorage.defaultStationId;
  DateTime? _lastRefreshed;
  List<DashboardSection> _sectionOrder = DashboardSection.values;

  // ── Intra-day power curve state ──────────────────────────────────────────
  List<PacSample> _pacSamples = [];
  String          _pacDateLabel  = 'Today';
  DateTime        _selectedPacDate = DateTime.now();
  bool            _isPacLoading  = false;

  // ── Annual energy bar chart state ────────────────────────────────────────
  List<DailyEnergy> _monthlyEnergy    = [];
  int               _selectedYear     = DateTime.now().year;
  bool              _isMonthlyLoading = false;

  bool _isLoading = true;
  SemsError? _error;
  double? _earningsRate;

  late final AnimationController _staggerCtrl;

  @override
  void initState() {
    super.initState();
    _selectedPacDate = DateTime.now();
    _selectedYear    = DateTime.now().year;
    _staggerCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    );
    _loadStationId().then((_) => _fetchData());
    _loadEarningsRate();
    _loadSectionOrder();
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
          final now = DateTime.now();
          setState(() {
            _monitor         = DemoData.stationMonitor();
            _pacSamples      = DemoData.pacSamples();
            _pacDateLabel    = 'Today';
            _selectedPacDate = now;
            _monthlyEnergy   = DemoData.monthlyEnergy(now.year);
            _selectedYear    = now.year;
            _lastRefreshed   = now;
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

      final now = DateTime.now();

      // Fetch intra-day PAC chart (non-critical)
      List<PacSample> pacSamples = [];
      try {
        pacSamples = await stationRepo.fetchPacByDay(
            auth.currentSession!, _stationId, now);
      } catch (_) {
        // Silently swallow — the power curve card is supplemental
      }

      // Fetch annual energy bar chart — pass today so the trailing-12 response
      // covers the full current year (Jan → now); filter to current year only.
      List<DailyEnergy> monthlyEnergy = [];
      try {
        final raw = await stationRepo.fetchPacByMonth(
            auth.currentSession!, _stationId, now);
        monthlyEnergy = _filterToYear(raw, now.year);
      } catch (_) {}

      if (mounted) {
        setState(() {
          _monitor         = monitor;
          _pacSamples      = pacSamples;
          _pacDateLabel    = 'Today';
          _selectedPacDate = now;
          _monthlyEnergy   = _filterToYear(monthlyEnergy, now.year);
          _selectedYear    = now.year;
          _lastRefreshed   = now;
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

  Future<void> _loadStationId() async {
    final id = await context.read<CredentialsStorage>().loadStationId();
    if (mounted) setState(() => _stationId = id);
  }

  Future<void> _loadEarningsRate() async {
    final storage = context.read<SettingsStorage>();
    final rate = await storage.loadEarningsRate();
    if (mounted) setState(() => _earningsRate = rate);
  }

  Future<void> _loadSectionOrder() async {
    final stored = await context.read<SettingsStorage>().loadCardOrder();
    if (!mounted || stored == null) return;
    final nameMap = {for (final s in DashboardSection.values) s.name: s};
    final parsed = stored
        .map((n) => nameMap[n])
        .whereType<DashboardSection>()
        .toList();
    // Append any new sections not present in the saved list (app updates).
    for (final s in DashboardSection.values) {
      if (!parsed.contains(s)) parsed.add(s);
    }
    setState(() => _sectionOrder = parsed);
  }

  Future<void> _saveSectionOrder() async {
    await context
        .read<SettingsStorage>()
        .saveCardOrder(_sectionOrder.map((s) => s.name).toList());
  }

  Future<void> _openCustomize() async {
    final result = await showModalBottomSheet<List<DashboardSection>>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _CustomizeOrderSheet(current: _sectionOrder),
    );
    if (result == null || !mounted) return;
    setState(() => _sectionOrder = result);
    await _saveSectionOrder();
  }

  // ── Session helper ────────────────────────────────────────────────────────

  /// Ensures a live session exists, attempting a silent re-login if the
  /// session is missing.  Returns false (and leaves loading state to the
  /// caller to clean up) if recovery fails.
  Future<bool> _ensureSession(AuthRepository auth) async {
    if (auth.currentSession != null) return true;
    final ok = await auth.tryRelogin();
    if (!mounted) return false;
    if (!ok) {
      // Credentials gone or network down — give up silently
      return false;
    }
    return true;
  }

  // ── Intra-day PAC navigation ──────────────────────────────────────────────

  String _formatRefreshTime(DateTime t) {
    String p(int n) => n.toString().padLeft(2, '0');
    return '${t.year}-${p(t.month)}-${p(t.day)} ${p(t.hour)}:${p(t.minute)}:${p(t.second)}';
  }

  String _formatPacDate(DateTime date) {
    final now = DateTime.now();
    if (date.year == now.year &&
        date.month == now.month &&
        date.day == now.day) { return 'Today'; }
    final yesterday = now.subtract(const Duration(days: 1));
    if (date.year == yesterday.year &&
        date.month == yesterday.month &&
        date.day == yesterday.day) { return 'Yesterday'; }
    const m = ['Jan','Feb','Mar','Apr','May','Jun',
                'Jul','Aug','Sep','Oct','Nov','Dec'];
    return '${date.day} ${m[date.month - 1]}';
  }

  bool get _isPacToday {
    final now = DateTime.now();
    return _selectedPacDate.year == now.year &&
        _selectedPacDate.month == now.month &&
        _selectedPacDate.day == now.day;
  }

  Future<void> _fetchPacForDate(DateTime date) async {
    setState(() => _isPacLoading = true);
    final auth = context.read<AuthRepository>();

    if (auth.isDemoMode) {
      await Future.delayed(const Duration(milliseconds: 350));
      if (!mounted) return;
      setState(() {
        _pacSamples      = DemoData.pacSamples(date: date);
        _selectedPacDate = date;
        _pacDateLabel    = _formatPacDate(date);
        _isPacLoading    = false;
      });
      return;
    }

    if (!await _ensureSession(auth)) {
      if (mounted) setState(() => _isPacLoading = false);
      return;
    }

    try {
      final stationRepo = context.read<StationRepository>();
      final samples = await stationRepo.fetchPacByDay(
          auth.currentSession!, _stationId, date);
      if (mounted) {
        setState(() {
          _pacSamples      = samples;
          _selectedPacDate = date;
          _pacDateLabel    = _formatPacDate(date);
          _isPacLoading    = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _isPacLoading = false);
    }
  }

  void _onPrevDay() {
    final prev = _selectedPacDate.subtract(const Duration(days: 1));
    _fetchPacForDate(prev);
  }

  void _onNextDay() {
    final next = _selectedPacDate.add(const Duration(days: 1));
    _fetchPacForDate(next);
  }

  Future<void> _onPickDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: now.subtract(const Duration(days: 1)),
      firstDate: DateTime(2020),
      lastDate: now,
      helpText: 'Select a date',
    );
    if (picked == null || !mounted) return;
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _DateCurveSheet(date: picked, stationId: _stationId),
    );
  }

  // ── Annual energy navigation ──────────────────────────────────────────────

  bool get _isCurrentYear => _selectedYear == DateTime.now().year;

  /// Filter a list of monthly entries to only those belonging to [year].
  static List<DailyEnergy> _filterToYear(List<DailyEnergy> all, int year) =>
      all.where((e) => e.date.year == year).toList()
        ..sort((a, b) => a.date.compareTo(b.date));

  Future<void> _fetchMonthlyForYear(int year) async {
    setState(() {
      _isMonthlyLoading = true;
      _monthlyEnergy    = [];
    });
    final auth = context.read<AuthRepository>();

    if (auth.isDemoMode) {
      await Future.delayed(const Duration(milliseconds: 350));
      if (!mounted) return;
      setState(() {
        _monthlyEnergy    = DemoData.monthlyEnergy(year);
        _selectedYear     = year;
        _isMonthlyLoading = false;
      });
      return;
    }

    if (!await _ensureSession(auth)) {
      if (mounted) {
        setState(() {
          _selectedYear     = year;
          _isMonthlyLoading = false;
        });
      }
      return;
    }

    try {
      final now         = DateTime.now();
      final isThisYear  = year == now.year;
      // For current year pass today so the trailing-12 response covers Jan→now.
      // For past years pass Dec 1 of that year so it covers the full Jan–Dec range.
      final refDate     = isThisYear ? now : DateTime(year, 12, 1);
      final stationRepo = context.read<StationRepository>();
      final raw         = await stationRepo.fetchPacByMonth(
          auth.currentSession!, _stationId, refDate);
      if (mounted) {
        setState(() {
          _monthlyEnergy    = _filterToYear(raw, year);
          _selectedYear     = year;
          _isMonthlyLoading = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _selectedYear     = year;
          _isMonthlyLoading = false;
        });
      }
    }
  }

  void _onPrevYear() => _fetchMonthlyForYear(_selectedYear - 1);
  void _onNextYear() => _fetchMonthlyForYear(_selectedYear + 1);

  // ── Alarm history ─────────────────────────────────────────────────────────

  void _openAlarmHistory() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => AlarmHistoryScreen(stationId: _stationId),
      ),
    );
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

    // Build section widgets in the user's chosen order.
    final items = <Widget>[];
    for (int i = 0; i < _sectionOrder.length; i++) {
      final w = _buildSectionWidget(_sectionOrder[i], m, inverter, now);
      if (w == null) continue;
      if (items.isNotEmpty) items.add(const SizedBox(height: 16));
      items.add(_Staggered(ctrl: _staggerCtrl, index: i, child: w));
    }

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
                ...items,
                const SizedBox(height: 16),
                // Timestamps footer
                Center(
                  child: Column(
                    children: [
                      Text(
                        'Inverter data: ${inverter?.lastRefreshTime ?? m.info.time}',
                        style: const TextStyle(
                            color: AppColors.textSecondary, fontSize: 11),
                      ),
                      if (_lastRefreshed != null) ...[
                        const SizedBox(height: 2),
                        Text(
                          'App refreshed: ${_formatRefreshTime(_lastRefreshed!)}',
                          style: TextStyle(
                            color: AppColors.textSecondary.withValues(alpha: 0.6),
                            fontSize: 10,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ]),
            ),
          ),
        ],
      ),
    );
  }

  Widget? _buildSectionWidget(
    DashboardSection section,
    StationMonitor m,
    InverterData? inverter,
    DateTime now,
  ) {
    switch (section) {
      case DashboardSection.liveOutput:
        return LivePowerCard(
          pac: m.kpi.pac,
          status: m.info.status,
          workMode: inverter?.workMode ?? '',
          capacityKw: m.info.capacity,
        );
      case DashboardSection.energyGeneration:
        return _buildEnergyGenerationSection(m);
      case DashboardSection.earnings:
        return _buildEarningsSection(m);
      case DashboardSection.monthlyPerformance:
        return MonthlyPerformanceCard(
          monthKwh: m.kpi.monthKwh,
          capacityKw: m.info.capacity,
          dayOfMonth: now.day,
          forecast: m.forecast,
        );
      case DashboardSection.lifetimeImpact:
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TodayInsightsCard(todayKwh: m.kpi.todayKwh),
            const SizedBox(height: 16),
            Co2InsightsCard(
              co2Tonnes: m.environmental.co2Tonnes,
              totalKwh: m.kpi.totalKwh,
              totalIncome: m.kpi.totalIncome,
            ),
          ],
        );
      case DashboardSection.environmental:
        return EnvironmentalCard(data: m.environmental);
      case DashboardSection.forecast:
        return WeatherSection(forecast: m.forecast);
      case DashboardSection.inverterDetails:
        return inverter != null
            ? InverterCard(
                inverter: inverter,
                onAlarmHistoryTap: _openAlarmHistory,
              )
            : null;
    }
  }

  Widget _buildEnergyGenerationSection(StationMonitor m) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        const _SectionLabel(label: 'Energy Generation'),
        const SizedBox(height: 10),
        Row(children: [
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
        const SizedBox(height: 16),
        // Intra-day power curve
        PowerCurveCard(
          samples: _pacSamples,
          dateLabel: _pacDateLabel,
          isLoading: _isPacLoading,
          onPrevDay: _onPrevDay,
          onNextDay: _isPacToday ? null : _onNextDay,
          onPickDate: _onPickDate,
        ),
        if (!_isLoading) ...[
          const SizedBox(height: 16),
          // Annual energy bar chart
          MonthlyEnergyBarChartCard(
            entries:    _monthlyEnergy,
            year:       _selectedYear,
            isLoading:  _isMonthlyLoading,
            onPrevYear: _onPrevYear,
            onNextYear: _isCurrentYear ? null : _onNextYear,
          ),
        ],
      ],
    );
  }

  Widget _buildEarningsSection(StationMonitor m) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            _SectionLabel(label: 'Earnings (${m.kpi.currency})'),
            const SizedBox(width: 8),
            if (_earningsRate != null) ...[
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
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
        const SizedBox(height: 10),
        Row(children: [
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
      ],
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
          icon: const Icon(Icons.tune_rounded, color: AppColors.textSecondary, size: 22),
          tooltip: 'Customise layout',
          onPressed: _openCustomize,
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

// ─── Dashboard customise-order sheet ──────────────────────────────────────────

class _CustomizeOrderSheet extends StatefulWidget {
  final List<DashboardSection> current;
  const _CustomizeOrderSheet({required this.current});

  @override
  State<_CustomizeOrderSheet> createState() => _CustomizeOrderSheetState();
}

class _CustomizeOrderSheetState extends State<_CustomizeOrderSheet> {
  late List<DashboardSection> _order;

  @override
  void initState() {
    super.initState();
    _order = List.from(widget.current);
  }

  static String _label(DashboardSection s) => switch (s) {
        DashboardSection.liveOutput        => 'Live Output',
        DashboardSection.energyGeneration  => 'Energy Generation',
        DashboardSection.earnings          => 'Earnings',
        DashboardSection.monthlyPerformance => 'Monthly Performance',
        DashboardSection.lifetimeImpact    => 'Your Lifetime Impact',
        DashboardSection.environmental     => 'Environmental Impact',
        DashboardSection.forecast          => '7-Day Forecast',
        DashboardSection.inverterDetails   => 'Inverter Details',
      };

  static String _subtitle(DashboardSection s) => switch (s) {
        DashboardSection.liveOutput        => 'Current power output',
        DashboardSection.energyGeneration  => 'KPIs · Power curve · Annual chart',
        DashboardSection.earnings          => 'Today & lifetime income',
        DashboardSection.monthlyPerformance => 'PR ratio & monthly outlook',
        DashboardSection.lifetimeImpact    => 'Insights & CO₂ savings',
        DashboardSection.environmental     => 'Trees, coal & CO₂ equivalents',
        DashboardSection.forecast          => 'Next 7 days of weather',
        DashboardSection.inverterDetails   => 'Technical inverter data',
      };

  static IconData _icon(DashboardSection s) => switch (s) {
        DashboardSection.liveOutput        => Icons.bolt_rounded,
        DashboardSection.energyGeneration  => Icons.show_chart_rounded,
        DashboardSection.earnings          => Icons.currency_rupee,
        DashboardSection.monthlyPerformance => Icons.bar_chart_rounded,
        DashboardSection.lifetimeImpact    => Icons.auto_awesome_rounded,
        DashboardSection.environmental     => Icons.eco_rounded,
        DashboardSection.forecast          => Icons.wb_cloudy_outlined,
        DashboardSection.inverterDetails   => Icons.memory_rounded,
      };

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: AppColors.background,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Drag handle
            Center(
              child: Container(
                margin: const EdgeInsets.only(top: 12, bottom: 4),
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: AppColors.divider,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            // Header
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 8, 4),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(7),
                    decoration: BoxDecoration(
                      color: AppColors.accent.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(Icons.tune_rounded,
                        color: AppColors.accent, size: 16),
                  ),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Customise Dashboard',
                          style: TextStyle(
                            color: AppColors.textPrimary,
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        Text(
                          'Drag to reorder sections',
                          style: TextStyle(
                            color: AppColors.textSecondary,
                            fontSize: 11,
                          ),
                        ),
                      ],
                    ),
                  ),
                  TextButton(
                    onPressed: () => Navigator.pop(context, _order),
                    child: const Text(
                      'Done',
                      style: TextStyle(
                        color: AppColors.accent,
                        fontWeight: FontWeight.w700,
                        fontSize: 14,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const Divider(color: AppColors.divider, height: 1),
            // Reorderable list
            Flexible(
              child: ReorderableListView.builder(
                shrinkWrap: true,
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                itemCount: _order.length,
                proxyDecorator: (child, index, animation) {
                  return AnimatedBuilder(
                    animation: animation,
                    builder: (_, innerChild) {
                      final t = Curves.easeOut.transform(animation.value);
                      return Transform.scale(
                        scale: 1.0 + 0.02 * t,
                        child: Material(
                          color: Colors.transparent,
                          child: Container(
                            decoration: BoxDecoration(
                              color: AppColors.card,
                              borderRadius: BorderRadius.circular(14),
                              border: Border.all(
                                color: AppColors.accent.withValues(alpha: 0.55 * t),
                                width: 1.5,
                              ),
                              boxShadow: [
                                BoxShadow(
                                  color: AppColors.accent.withValues(alpha: 0.18 * t),
                                  blurRadius: 18 * t,
                                  spreadRadius: 1 * t,
                                  offset: const Offset(0, 4),
                                ),
                              ],
                            ),
                            child: innerChild,
                          ),
                        ),
                      );
                    },
                    child: child,
                  );
                },
                onReorder: (oldIdx, newIdx) {
                  setState(() {
                    if (newIdx > oldIdx) newIdx--;
                    final item = _order.removeAt(oldIdx);
                    _order.insert(newIdx, item);
                  });
                },
                itemBuilder: (ctx, idx) {
                  final section = _order[idx];
                  return ListTile(
                    key: ValueKey(section),
                    contentPadding:
                        const EdgeInsets.symmetric(horizontal: 20, vertical: 2),
                    leading: Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: AppColors.cardAlt,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Icon(_icon(section),
                          color: AppColors.textSecondary, size: 18),
                    ),
                    title: Text(
                      _label(section),
                      style: const TextStyle(
                        color: AppColors.textPrimary,
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    subtitle: Text(
                      _subtitle(section),
                      style: const TextStyle(
                        color: AppColors.textSecondary,
                        fontSize: 11,
                      ),
                    ),
                    trailing: const Icon(Icons.drag_handle_rounded,
                        color: AppColors.textSecondary, size: 22),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Date-picker power curve sheet ────────────────────────────────────────────
// Opens via the calendar icon on the main Power Curve card.
// Shows the chart for a single chosen date with no day navigation.

class _DateCurveSheet extends StatefulWidget {
  final DateTime date;
  final String stationId;

  const _DateCurveSheet({required this.date, required this.stationId});

  @override
  State<_DateCurveSheet> createState() => _DateCurveSheetState();
}

class _DateCurveSheetState extends State<_DateCurveSheet> {
  List<PacSample> _samples = [];
  bool _isLoading = true;

  static const _months = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
  ];

  String get _label =>
      '${widget.date.day} ${_months[widget.date.month - 1]} ${widget.date.year}';

  @override
  void initState() {
    super.initState();
    _fetch();
  }

  Future<void> _fetch() async {
    final auth = context.read<AuthRepository>();
    try {
      if (auth.isDemoMode) {
        await Future.delayed(const Duration(milliseconds: 500));
        if (!mounted) return;
        setState(() {
          _samples   = DemoData.pacSamples(date: widget.date);
          _isLoading = false;
        });
        return;
      }
      if (auth.currentSession == null) {
        final ok = await auth.tryRelogin();
        if (!mounted) return;
        if (!ok) {
          setState(() => _isLoading = false);
          return;
        }
      }
      final samples = await context.read<StationRepository>().fetchPacByDay(
          auth.currentSession!, widget.stationId, widget.date);
      if (mounted) setState(() { _samples = samples; _isLoading = false; });
    } catch (_) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: AppColors.background,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Drag handle
            Center(
              child: Container(
                margin: const EdgeInsets.only(top: 12, bottom: 4),
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: AppColors.divider,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            // Sheet header
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 8, 4),
              child: Row(
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
                  const SizedBox(width: 10),
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: AppColors.accent.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      _label,
                      style: const TextStyle(
                        color: AppColors.accent,
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  const Spacer(),
                  IconButton(
                    icon: const Icon(Icons.close_rounded,
                        color: AppColors.textSecondary, size: 20),
                    onPressed: () => Navigator.of(context).pop(),
                    padding: EdgeInsets.zero,
                    visualDensity: VisualDensity.compact,
                  ),
                ],
              ),
            ),
            // Chart — no navigation arrows in this view
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
              child: PowerCurveCard(
                samples:   _samples,
                dateLabel: _label,
                isLoading: _isLoading,
                // onPrevDay / onNextDay intentionally omitted → nav hidden
              ),
            ),
          ],
        ),
      ),
    );
  }
}
