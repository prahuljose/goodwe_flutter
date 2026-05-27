import 'package:flutter/foundation.dart';
import '../../data/models/energy_balance.dart';
import '../../data/models/tapo_reading.dart';
import '../../data/repositories/tapo_local_repository.dart';

enum ConsumptionStatus { noAccount, noDevices, loading, live, error }

class ConsumptionProvider extends ChangeNotifier {
  final TapoLocalRepository _repo;

  ConsumptionStatus _status = ConsumptionStatus.noAccount;
  EnergyBalance? _balance;
  List<TapoReading> _readings = [];
  String? _errorMessage;

  // Last known solar figures (so a reload can rebuild the balance)
  double _lastProductionW = 0;
  double _lastProductionKwh = 0;

  ConsumptionProvider(this._repo);

  ConsumptionStatus get status => _status;
  EnergyBalance? get balance => _balance;
  List<TapoReading> get readings => List.unmodifiable(_readings);
  String? get errorMessage => _errorMessage;
  bool get isLive => _status == ConsumptionStatus.live;

  int get onlineCount => _readings.where((r) => r.online).length;
  int get deviceCount => _readings.length;

  TapoLocalRepository get repo => _repo;

  /// Refresh consumption and rebuild the energy balance against the supplied
  bool _refreshing = false;

  /// solar figures. Call after each GoodWe fetch.
  Future<void> refresh({
    required double liveProductionW,
    required double productionKwh,
  }) async {
    _lastProductionW = liveProductionW;
    _lastProductionKwh = productionKwh;

    // Prevent overlapping refreshes (e.g. a poll firing during a pull-to-
    // refresh) — concurrent reads on the same plug socket would corrupt the
    // KLAP sequence/connection.
    if (_refreshing) return;

    if (!await _repo.hasAccount()) {
      _set(ConsumptionStatus.noAccount);
      return;
    }
    if (_repo.devices.isEmpty) {
      _set(ConsumptionStatus.noDevices);
      return;
    }

    if (_status == ConsumptionStatus.noAccount ||
        _status == ConsumptionStatus.noDevices) {
      _set(ConsumptionStatus.loading);
    }

    _refreshing = true;
    try {
      final readings = await _repo.readAll();
      _readings = readings;

      // Aggregate across all reachable plugs
      final totalLiveW = readings
          .where((r) => r.online)
          .fold<double>(0, (sum, r) => sum + r.liveW);
      final totalTodayKwh = readings
          .where((r) => r.online)
          .fold<double>(0, (sum, r) => sum + r.todayKwh);

      _balance = EnergyBalance(
        productionKwh: productionKwh,
        consumptionKwh: totalTodayKwh,
        liveConsumptionW: totalLiveW,
        liveProductionW: liveProductionW,
      );

      // If every device is offline, surface an error instead of zeros
      if (readings.isNotEmpty && readings.every((r) => !r.online)) {
        _errorMessage = readings.first.error ?? 'All plugs unreachable.';
        _set(ConsumptionStatus.error);
      } else {
        _errorMessage = null;
        _set(ConsumptionStatus.live);
      }
    } catch (e) {
      _errorMessage = e.toString();
      _set(ConsumptionStatus.error);
    } finally {
      _refreshing = false;
    }
  }

  /// Re-evaluate after the device list / account changes (e.g. from setup).
  /// Live polling is driven by the dashboard (one timer for solar + plugs).
  Future<void> reload() => refresh(
        liveProductionW: _lastProductionW,
        productionKwh: _lastProductionKwh,
      );

  void _set(ConsumptionStatus s) {
    _status = s;
    notifyListeners();
  }
}
