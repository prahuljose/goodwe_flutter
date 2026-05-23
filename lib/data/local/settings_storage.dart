import 'package:shared_preferences/shared_preferences.dart';

class SettingsStorage {
  static const _earningsRateKey = 'custom_earnings_rate';

  Future<void> saveEarningsRate(double ratePerUnit) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(_earningsRateKey, ratePerUnit);
  }

  Future<double?> loadEarningsRate() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getDouble(_earningsRateKey);
  }

  Future<void> clearEarningsRate() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_earningsRateKey);
  }
}
