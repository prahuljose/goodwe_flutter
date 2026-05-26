import 'package:shared_preferences/shared_preferences.dart';

class SettingsStorage {
  static const _earningsRateKey  = 'custom_earnings_rate';
  static const _cardOrderKey     = 'dashboard_section_order';

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

  // ── Dashboard section order ───────────────────────────────────────────────

  Future<void> saveCardOrder(List<String> order) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_cardOrderKey, order);
  }

  Future<List<String>?> loadCardOrder() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getStringList(_cardOrderKey);
  }

  // ── Hidden dashboard sections ─────────────────────────────────────────────

  static const _hiddenSectionsKey = 'dashboard_hidden_sections';

  Future<void> saveHiddenSections(Set<String> hidden) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_hiddenSectionsKey, hidden.toList());
  }

  Future<Set<String>?> loadHiddenSections() async {
    final prefs = await SharedPreferences.getInstance();
    final list = prefs.getStringList(_hiddenSectionsKey);
    return list?.toSet();
  }
}
