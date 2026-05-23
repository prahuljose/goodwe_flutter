import '../data/remote/sems_api.dart';
import '../data/models/session.dart';
import '../data/models/station_monitor.dart';

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
}
