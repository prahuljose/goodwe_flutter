/// Snapshot of today's production vs consumption.
class EnergyBalance {
  /// Solar production today in kWh (from GoodWe).
  final double productionKwh;

  /// Total consumption today in kWh (from Tapo P110).
  final double consumptionKwh;

  /// Current live consumption in watts.
  final double liveConsumptionW;

  /// Current live solar output in watts (PAC).
  final double liveProductionW;

  const EnergyBalance({
    required this.productionKwh,
    required this.consumptionKwh,
    required this.liveConsumptionW,
    required this.liveProductionW,
  });

  /// Positive = surplus (exporting to grid). Negative = deficit (importing).
  double get netKwh => productionKwh - consumptionKwh;

  /// Positive = solar covering more than consumption right now.
  double get liveNetW => liveProductionW - liveConsumptionW;

  /// 0.0–1.0+ (>1 means consuming more than produced).
  double get coverageRatio =>
      productionKwh > 0 ? (consumptionKwh / productionKwh).clamp(0.0, 9.9) : 0.0;

  bool get isSurplus => netKwh >= 0;
}
