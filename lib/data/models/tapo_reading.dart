import 'tapo_device.dart';

/// A live reading from one Tapo plug.
class TapoReading {
  final TapoDevice device;
  final double liveW;     // current power draw, watts
  final double todayKwh;  // energy consumed today
  final double monthKwh;  // energy consumed this month
  final bool online;      // false if the plug couldn't be reached
  final String? error;    // populated when online == false

  const TapoReading({
    required this.device,
    this.liveW = 0,
    this.todayKwh = 0,
    this.monthKwh = 0,
    this.online = false,
    this.error,
  });

  factory TapoReading.offline(TapoDevice device, String error) =>
      TapoReading(device: device, online: false, error: error);
}
