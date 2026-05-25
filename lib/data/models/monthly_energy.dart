// ─── Daily energy sample (one entry per day, returned by monthly chart API) ──

class DailyEnergy {
  final DateTime date;
  final double kwh;

  const DailyEnergy({required this.date, required this.kwh});

  factory DailyEnergy.fromJson(Map<String, dynamic> json) {
    DateTime date;
    try {
      final raw = json['date'] as String;
      final parts = raw.split('/');
      if (parts.length == 3) {
        // MM/DD/YYYY (same format SEMS uses for PacSample)
        date = DateTime(
          int.parse(parts[2]),
          int.parse(parts[0]),
          int.parse(parts[1]),
        );
      } else {
        date = DateTime.parse(raw);
      }
    } catch (_) {
      date = DateTime.now();
    }
    // SEMS may return kWh as 'power', 'energy', or 'pac' depending on endpoint version
    final kwh = (json['power'] as num?)?.toDouble() ??
        (json['energy'] as num?)?.toDouble() ??
        (json['pac'] as num?)?.toDouble() ??
        0.0;
    return DailyEnergy(date: date, kwh: kwh);
  }
}

// ─── Alarm / fault record ─────────────────────────────────────────────────────

class AlarmRecord {
  final String sn;

  /// 1 = fault/error, 2 = warning
  final int alarmType;
  final int alarmCode;
  final String message;
  final DateTime happenTime;
  final DateTime? recoverTime;

  const AlarmRecord({
    required this.sn,
    required this.alarmType,
    required this.alarmCode,
    required this.message,
    required this.happenTime,
    this.recoverTime,
  });

  bool get isActive => recoverTime == null;
  bool get isFault  => alarmType == 1;

  Duration? get duration =>
      recoverTime?.difference(happenTime);

  factory AlarmRecord.fromJson(Map<String, dynamic> json) {
    DateTime parseTime(String? s) {
      if (s == null || s.isEmpty) return DateTime.now();
      try {
        return DateTime.parse(s.replaceFirst(' ', 'T'));
      } catch (_) {
        return DateTime.now();
      }
    }

    final recoverStr = json['recover_time'] as String? ??
        json['recovery_time'] as String?;
    final hasRecover = recoverStr != null && recoverStr.isNotEmpty;

    return AlarmRecord(
      sn:          json['sn']            as String? ?? '',
      alarmType:  (json['alarm_type']   as num?)?.toInt() ?? 1,
      alarmCode:  (json['alarm_code']   as num?)?.toInt() ??
                  (json['error_code']   as num?)?.toInt() ?? 0,
      message:    json['alarm_message'] as String? ??
                  json['message']       as String? ?? '',
      happenTime:  parseTime(json['happen_time']  as String? ??
                             json['start_time']   as String?),
      recoverTime: hasRecover ? parseTime(recoverStr) : null,
    );
  }
}
