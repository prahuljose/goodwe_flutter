class StationMonitor {
  final StationInfo info;
  final StationKpi kpi;
  final List<InverterData> inverters;
  final Environmental environmental;
  final Powerflow powerflow;
  final EnergyStats energyStats;
  final List<WeatherForecast> forecast;

  const StationMonitor({
    required this.info,
    required this.kpi,
    required this.inverters,
    required this.environmental,
    required this.powerflow,
    required this.energyStats,
    required this.forecast,
  });

  InverterData? get primaryInverter =>
      inverters.isNotEmpty ? inverters.first : null;

  factory StationMonitor.fromJson(Map<String, dynamic> json) {
    final data = json['data'] as Map<String, dynamic>;

    final rawForecast = (data['weather']?['HeWeather6'] as List?)
            ?.first['daily_forecast'] as List? ??
        [];

    return StationMonitor(
      info: StationInfo.fromJson(data['info'] as Map<String, dynamic>),
      kpi: StationKpi.fromJson(data['kpi'] as Map<String, dynamic>),
      inverters: (data['inverter'] as List)
          .map((e) => InverterData.fromJson(e as Map<String, dynamic>))
          .toList(),
      environmental:
          Environmental.fromJson(data['hjgx'] as Map<String, dynamic>),
      powerflow:
          Powerflow.fromJson(data['powerflow'] as Map<String, dynamic>),
      energyStats: EnergyStats.fromJson(
          data['energeStatisticsCharts'] as Map<String, dynamic>),
      forecast: rawForecast
          .map((e) => WeatherForecast.fromJson(e as Map<String, dynamic>))
          .toList(),
    );
  }
}

// ─── Station Info ──────────────────────────────────────────────────────────

class StationInfo {
  final String id;
  final String name;
  final String address;
  final double capacity;
  final int status;
  final String time;

  const StationInfo({
    required this.id,
    required this.name,
    required this.address,
    required this.capacity,
    required this.status,
    required this.time,
  });

  factory StationInfo.fromJson(Map<String, dynamic> json) => StationInfo(
        id: json['powerstation_id'] as String,
        name: json['stationname'] as String,
        address: json['address'] as String,
        capacity: (json['capacity'] as num).toDouble(),
        status: json['status'] as int,
        time: json['time'] as String,
      );

  String get statusLabel {
    switch (status) {
      case 1:
        return 'Online';
      case 0:
        return 'Normal';
      case -1:
        return 'Wait Mode';
      default:
        return 'Unknown';
    }
  }
}

// ─── KPI ──────────────────────────────────────────────────────────────────

class StationKpi {
  final double pac;
  final double todayKwh;
  final double monthKwh;
  final double totalKwh;
  final double todayIncome;
  final double totalIncome;
  final String currency;

  const StationKpi({
    required this.pac,
    required this.todayKwh,
    required this.monthKwh,
    required this.totalKwh,
    required this.todayIncome,
    required this.totalIncome,
    required this.currency,
  });

  factory StationKpi.fromJson(Map<String, dynamic> json) => StationKpi(
        pac: (json['pac'] as num?)?.toDouble() ?? 0,
        todayKwh: (json['power'] as num?)?.toDouble() ?? 0,
        monthKwh: (json['month_generation'] as num?)?.toDouble() ?? 0,
        totalKwh: (json['total_power'] as num?)?.toDouble() ?? 0,
        todayIncome: (json['day_income'] as num?)?.toDouble() ?? 0,
        totalIncome: (json['total_income'] as num?)?.toDouble() ?? 0,
        currency: json['currency'] as String? ?? 'INR',
      );
}

// ─── Inverter ────────────────────────────────────────────────────────────

class InverterData {
  final String sn;
  final String model;
  final double eday;
  final double emonth;
  final double etotal;
  final int status;
  final double pac;
  final double temperature;
  final double hTotal;
  final String lastRefreshTime;
  final String workMode;
  final double vpv1;
  final double vpv2;
  final double ipv1;
  final double ipv2;
  final double vac1;
  final double vac2;
  final double vac3;
  final double iac1;
  final double iac2;
  final double iac3;
  final double fac1;

  const InverterData({
    required this.sn,
    required this.model,
    required this.eday,
    required this.emonth,
    required this.etotal,
    required this.status,
    required this.pac,
    required this.temperature,
    required this.hTotal,
    required this.lastRefreshTime,
    required this.workMode,
    required this.vpv1,
    required this.vpv2,
    required this.ipv1,
    required this.ipv2,
    required this.vac1,
    required this.vac2,
    required this.vac3,
    required this.iac1,
    required this.iac2,
    required this.iac3,
    required this.fac1,
  });

  factory InverterData.fromJson(Map<String, dynamic> json) {
    final d = json['d'] as Map<String, dynamic>? ?? {};
    final full = json['invert_full'] as Map<String, dynamic>? ?? {};
    return InverterData(
      sn: json['sn'] as String? ?? '',
      model: json['type'] as String? ?? '',
      eday: (json['eday'] as num?)?.toDouble() ?? 0,
      emonth: (json['emonth'] as num?)?.toDouble() ?? 0,
      etotal: (json['etotal'] as num?)?.toDouble() ?? 0,
      status: json['status'] as int? ?? -1,
      pac: (full['pac'] as num?)?.toDouble() ?? 0,
      temperature: (json['tempperature'] as num?)?.toDouble() ?? 0,
      hTotal: (full['hour_total'] as num?)?.toDouble() ?? 0,
      lastRefreshTime: d['last_refresh_time'] as String? ?? '',
      workMode: d['work_mode'] as String? ?? '',
      vpv1: (full['vpv1'] as num?)?.toDouble() ?? 0,
      vpv2: (full['vpv2'] as num?)?.toDouble() ?? 0,
      ipv1: (full['ipv1'] as num?)?.toDouble() ?? 0,
      ipv2: (full['ipv2'] as num?)?.toDouble() ?? 0,
      vac1: (full['vac1'] as num?)?.toDouble() ?? 0,
      vac2: (full['vac2'] as num?)?.toDouble() ?? 0,
      vac3: (full['vac3'] as num?)?.toDouble() ?? 0,
      iac1: (full['iac1'] as num?)?.toDouble() ?? 0,
      iac2: (full['iac2'] as num?)?.toDouble() ?? 0,
      iac3: (full['iac3'] as num?)?.toDouble() ?? 0,
      fac1: (full['fac1'] as num?)?.toDouble() ?? 0,
    );
  }
}

// ─── Environmental ────────────────────────────────────────────────────────

class Environmental {
  final double co2Tonnes;
  final double treesEquivalent;
  final double coalKg;

  const Environmental({
    required this.co2Tonnes,
    required this.treesEquivalent,
    required this.coalKg,
  });

  factory Environmental.fromJson(Map<String, dynamic> json) => Environmental(
        co2Tonnes: (json['co2'] as num?)?.toDouble() ?? 0,
        treesEquivalent: (json['tree'] as num?)?.toDouble() ?? 0,
        coalKg: (json['coal'] as num?)?.toDouble() ?? 0,
      );
}

// ─── Powerflow ────────────────────────────────────────────────────────────

class Powerflow {
  final String pv;
  final int pvStatus;
  final String grid;
  final int gridStatus;
  final String load;
  final int loadStatus;
  final int soc;

  const Powerflow({
    required this.pv,
    required this.pvStatus,
    required this.grid,
    required this.gridStatus,
    required this.load,
    required this.loadStatus,
    required this.soc,
  });

  factory Powerflow.fromJson(Map<String, dynamic> json) => Powerflow(
        pv: json['pv'] as String? ?? '',
        pvStatus: json['pvStatus'] as int? ?? 0,
        grid: json['grid'] as String? ?? '',
        gridStatus: json['gridStatus'] as int? ?? 0,
        load: json['load'] as String? ?? '',
        loadStatus: json['loadStatus'] as int? ?? 0,
        soc: json['soc'] as int? ?? 0,
      );
}

// ─── Energy Stats ─────────────────────────────────────────────────────────

class EnergyStats {
  final double totalPvToday;
  final double gridBuy;
  final double gridSell;
  final double selfUse;
  final double consumptionOfLoad;

  const EnergyStats({
    required this.totalPvToday,
    required this.gridBuy,
    required this.gridSell,
    required this.selfUse,
    required this.consumptionOfLoad,
  });

  factory EnergyStats.fromJson(Map<String, dynamic> json) => EnergyStats(
        totalPvToday: (json['sum'] as num?)?.toDouble() ?? 0,
        gridBuy: (json['buy'] as num?)?.toDouble() ?? 0,
        gridSell: (json['sell'] as num?)?.toDouble() ?? 0,
        selfUse: (json['selfUseOfPv'] as num?)?.toDouble() ?? 0,
        consumptionOfLoad:
            (json['consumptionOfLoad'] as num?)?.toDouble() ?? 0,
      );
}

// ─── Weather ──────────────────────────────────────────────────────────────

class WeatherForecast {
  final String date;
  final String condTextDay;
  final String condCodeDay;
  final int humidity;
  final int tmpMax;
  final int tmpMin;
  final int uvIndex;
  final int pop;

  const WeatherForecast({
    required this.date,
    required this.condTextDay,
    required this.condCodeDay,
    required this.humidity,
    required this.tmpMax,
    required this.tmpMin,
    required this.uvIndex,
    required this.pop,
  });

  factory WeatherForecast.fromJson(Map<String, dynamic> json) =>
      WeatherForecast(
        date: json['date'] as String? ?? '',
        condTextDay: json['cond_txt_d'] as String? ?? '',
        condCodeDay: json['cond_code_d'] as String? ?? '',
        humidity: int.tryParse(json['hum'] as String? ?? '0') ?? 0,
        tmpMax: int.tryParse(json['tmp_max'] as String? ?? '0') ?? 0,
        tmpMin: int.tryParse(json['tmp_min'] as String? ?? '0') ?? 0,
        uvIndex: int.tryParse(json['uv_index'] as String? ?? '0') ?? 0,
        pop: int.tryParse(json['pop'] as String? ?? '0') ?? 0,
      );

  String get weatherIcon {
    final code = int.tryParse(condCodeDay) ?? 0;
    if (code == 100) return '☀️';
    if (code >= 101 && code <= 103) return '⛅';
    if (code == 104 || code == 200) return '☁️';
    if (code >= 300 && code <= 304) return '🌦️';
    if (code >= 305 && code <= 309) return '🌧️';
    if (code >= 350 && code <= 351) return '🌧️';
    if (code >= 400 && code <= 410) return '❄️';
    if (code >= 500 && code <= 502) return '🌫️';
    return '🌤️';
  }
}

// ─── PAC samples (intra-day power curve) ─────────────────────────────────────

class PacSample {
  final DateTime time;
  final double pac; // watts

  const PacSample({required this.time, required this.pac});

  factory PacSample.fromJson(Map<String, dynamic> json) {
    // API format: "MM/DD/YYYY HH:mm:ss"
    DateTime t;
    try {
      final parts = (json['date'] as String).split(' ');
      final d = parts[0].split('/');
      final h = parts[1].split(':');
      t = DateTime(
        int.parse(d[2]), int.parse(d[0]), int.parse(d[1]),
        int.parse(h[0]), int.parse(h[1]), int.parse(h[2]),
      );
    } catch (_) {
      t = DateTime.now();
    }
    return PacSample(
      time: t,
      pac: (json['pac'] as num?)?.toDouble() ?? 0,
    );
  }
}
