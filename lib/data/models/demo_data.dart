import 'dart:math' as math;
import 'station_monitor.dart';
import 'monthly_energy.dart';

/// Realistic mock data for a 10 kW rooftop system in Kerala.
/// Numbers are plausible for a system ~2 years into operation.
class DemoData {
  DemoData._();

  static StationMonitor stationMonitor() {
    final now = DateTime.now();
    final ts = _fmt(now);

    return StationMonitor(
      info: StationInfo(
        id: 'demo-station-001',
        name: 'Sunridge Home Solar',
        address: 'Thrissur, Kerala, India',
        capacity: 10.0,
        status: 1,
        time: ts,
      ),
      kpi: const StationKpi(
        pac: 3240.0,        // 3.24 kW live — good mid-morning output
        todayKwh: 12.4,
        monthKwh: 287.6,
        totalKwh: 18754.3,  // ~1.875 MWh lifetime
        todayIncome: 55.80,
        totalIncome: 84391.35,
        currency: 'INR',
      ),
      inverters: [
        InverterData(
          sn: 'DM2024GW10K001',
          model: 'GW10K-ET',
          eday: 12.4,
          emonth: 287.6,
          etotal: 18754.3,
          status: 1,
          pac: 3240.0,
          temperature: 38.5,
          hTotal: 16820.0,   // ~2 years of operating hours
          lastRefreshTime: ts,
          workMode: 'Selling Power',
          errorCode: 0,
          warningCode: 0,
          vpv1: 382.4,
          vpv2: 378.8,
          ipv1: 4.92,
          ipv2: 4.63,
          vac1: 241.6,
          vac2: 0.0,
          vac3: 0.0,
          iac1: 13.42,
          iac2: 0.0,
          iac3: 0.0,
          fac1: 50.01,
        ),
      ],
      environmental: const Environmental(
        co2Tonnes: 8.44,
        treesEquivalent: 464.0,
        coalKg: 7520.0,
      ),
      powerflow: const Powerflow(
        pv: '3.24 kW',
        pvStatus: 1,
        grid: '-2.14 kW',
        gridStatus: -1,
        load: '1.10 kW',
        loadStatus: 1,
        soc: 0,
      ),
      energyStats: const EnergyStats(
        totalPvToday: 12.4,
        gridBuy: 1.2,
        gridSell: 9.8,
        selfUse: 2.6,
        consumptionOfLoad: 3.8,
      ),
      forecast: List.generate(7, (i) {
        final day = now.add(Duration(days: i));
        return _forecast('${day.year}-${_p(day.month)}-${_p(day.day)}', i);
      }),
    );
  }

  // 7-day Kerala May forecast: starts sunny, dips to rain mid-week, recovers
  static WeatherForecast _forecast(String date, int i) {
    const codes = ['100', '101', '101', '103', '306', '101', '100'];
    const texts = [
      'Clear', 'Partly Cloudy', 'Partly Cloudy',
      'Overcast', 'Light Rain', 'Partly Cloudy', 'Clear',
    ];
    const maxT = [35, 34, 33, 31, 30, 32, 35];
    const minT = [26, 26, 25, 25, 24, 25, 26];
    const uv   = [10,  8,  7,  5,  3,  7, 10];
    const pop  = [ 5, 15, 30, 60, 80, 25,  5];
    final j = i % 7;
    return WeatherForecast(
      date: date,
      condTextDay: texts[j],
      condCodeDay: codes[j],
      humidity: 68 + j * 3,
      tmpMax: maxT[j],
      tmpMin: minT[j],
      uvIndex: uv[j],
      pop: pop[j],
    );
  }

  /// Realistic bell-curve PAC samples for a 10 kW system on a sunny Kerala day.
  /// 288 entries at 5-minute intervals covering the full 24 h period.
  /// Pass [date] to generate reproducible data for a specific historical day.
  static List<PacSample> pacSamples({DateTime? date}) {
    final today = date ?? DateTime.now();
    final base = DateTime(today.year, today.month, today.day);

    return List.generate(288, (i) {
      final time = base.add(Duration(minutes: i * 5));
      final hour = time.hour + time.minute / 60.0;

      // Generation window: 06:00 → 18:30
      if (hour < 6.0 || hour > 18.5) {
        return PacSample(time: time, pac: 0);
      }

      // ── Simulated power cut: 08:00 – 08:20 (indices 96 – 100) ────────────
      // index = minutes-from-midnight / 5  →  8:00 = 96, 8:20 = 100
      if (i >= 96 && i <= 100) {
        return PacSample(time: time, pac: 0);
      }

      // Vary peak slightly per date for realistic-looking historical data
      final dateSeed = (today.day * 17 + today.month * 7) % 21;
      final peakW = 9500.0 * (0.80 + dateSeed / 100.0); // 80–100 % of max
      const mu = 12.5;
      const sigma = 3.0;
      final z = (hour - mu) / sigma;
      final raw = peakW * math.exp(-0.5 * z * z);

      // ── Simulated cloud shadow: 13:00 – 13:30 (indices 156 – 162) ─────────
      // Drop output to ~18 % of the gaussian baseline for those 30 min
      if (i >= 156 && i <= 162) {
        return PacSample(time: time, pac: (raw * 0.18).clamp(0.0, peakW));
      }

      // Light cloud flutter — ±8 % jitter
      final jitter = 1.0 + 0.08 * math.sin(i * 7.3 + 1.1) * math.cos(i * 3.1);

      return PacSample(time: time, pac: (raw * jitter).clamp(0.0, peakW));
    });
  }

  /// Monthly generation totals for [year], Jan → current month (for the
  /// current year) or Jan → Dec (for past years).
  /// Mirrors GetChartByPlant shape: each entry has date.day == 1.
  static List<DailyEnergy> monthlyEnergy(int year) {
    final today      = DateTime.now();
    final isThisYear = year == today.year;
    final lastMonth  = isThisYear ? today.month : 12;
    final result     = <DailyEnergy>[];

    for (int m = 1; m <= lastMonth; m++) {
      final date = DateTime(year, m, 1);

      // Seed-based monthly production (Kerala: dip Jun–Sep monsoon)
      final monsoon = m >= 6 && m <= 9;
      final s       = (m * 17 + year * 3) % 20; // 0–19, reproducible
      final base    = monsoon ? 350.0 + s * 8 : 520.0 + s * 14;

      // Current month: partial
      final isCurrent = isThisYear && m == today.month;
      final kwh = isCurrent ? base * (today.day / 30.0) : base;

      result.add(DailyEnergy(date: date, kwh: double.parse(kwh.toStringAsFixed(1))));
    }
    return result;
  }

  /// A handful of realistic past alarm records for the demo station.
  static List<AlarmRecord> alarmHistory() {
    final now = DateTime.now();
    return [
      AlarmRecord(
        sn:         'DM2024GW10K001',
        alarmType:  1,
        alarmCode:  19,
        message:    'Over-temperature — check ventilation around inverter',
        happenTime:  now.subtract(const Duration(days: 3, hours: 2, minutes: 10)),
        recoverTime: now.subtract(const Duration(days: 3, hours: 0, minutes: 45)),
      ),
      AlarmRecord(
        sn:         'DM2024GW10K001',
        alarmType:  2,
        alarmCode:  3,
        message:    'Grid frequency out of range',
        happenTime:  now.subtract(const Duration(days: 8, hours: 5)),
        recoverTime: now.subtract(const Duration(days: 8, hours: 4, minutes: 38)),
      ),
      AlarmRecord(
        sn:         'DM2024GW10K001',
        alarmType:  1,
        alarmCode:  23,
        message:    'Grid disconnection / utility loss',
        happenTime:  now.subtract(const Duration(days: 14, hours: 7)),
        recoverTime: now.subtract(const Duration(days: 14, hours: 5, minutes: 50)),
      ),
      AlarmRecord(
        sn:         'DM2024GW10K001',
        alarmType:  2,
        alarmCode:  15,
        message:    'Grid voltage out of range',
        happenTime:  now.subtract(const Duration(days: 21, hours: 3, minutes: 30)),
        recoverTime: now.subtract(const Duration(days: 21, hours: 3, minutes: 12)),
      ),
    ];
  }

  static String _fmt(DateTime d) =>
      '${d.year}-${_p(d.month)}-${_p(d.day)} ${_p(d.hour)}:${_p(d.minute)}:${_p(d.second)}';

  static String _p(int n) => n.toString().padLeft(2, '0');
}
