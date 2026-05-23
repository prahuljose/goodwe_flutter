import 'dart:math' as math;
import 'station_monitor.dart';

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
  static List<PacSample> pacSamples() {
    final today = DateTime.now();
    final base = DateTime(today.year, today.month, today.day);

    return List.generate(288, (i) {
      final time = base.add(Duration(minutes: i * 5));
      final hour = time.hour + time.minute / 60.0;

      // Generation window: 06:00 → 18:30
      if (hour < 6.0 || hour > 18.5) {
        return PacSample(time: time, pac: 0);
      }

      // Gaussian centred at 12:30, σ = 3 h, peak ≈ 9 500 W
      const peakW = 9500.0;
      const mu = 12.5;
      const sigma = 3.0;
      final z = (hour - mu) / sigma;
      final raw = peakW * math.exp(-0.5 * z * z);

      // Light cloud flutter — ±8 % jitter using a deterministic pseudo-random
      final jitter = 1.0 + 0.08 * math.sin(i * 7.3 + 1.1) * math.cos(i * 3.1);

      return PacSample(time: time, pac: (raw * jitter).clamp(0.0, peakW));
    });
  }

  static String _fmt(DateTime d) =>
      '${d.year}-${_p(d.month)}-${_p(d.day)} ${_p(d.hour)}:${_p(d.minute)}:${_p(d.second)}';

  static String _p(int n) => n.toString().padLeft(2, '0');
}
