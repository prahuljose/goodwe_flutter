import '../data/remote/sems_api.dart';
import '../data/models/session.dart';
import '../data/models/station_monitor.dart';
import '../data/models/monthly_energy.dart';

class StationRepository {
  final SemsApi _api;

  StationRepository(this._api);

  Future<StationMonitor> fetchMonitor(
    SemsSession session,
    String powerStationId,
  ) async {
    return _api.getMonitorDetail(session, powerStationId);
  }

  Future<List<PacSample>> fetchPacByDay(
    SemsSession session,
    String powerStationId,
    DateTime date,
  ) async {
    return _api.getPacByDay(session, powerStationId, date);
  }

  Future<List<DailyEnergy>> fetchPacByMonth(
    SemsSession session,
    String powerStationId,
    DateTime month,
  ) async {
    return _api.getPacByMonth(session, powerStationId, month);
  }

  Future<List<AlarmRecord>> fetchAlarms(
    SemsSession session,
    String powerStationId, {
    int pageIndex = 0,
    int pageSize  = 50,
  }) async {
    return _api.getAlarmList(session, powerStationId,
        pageIndex: pageIndex, pageSize: pageSize);
  }
}
