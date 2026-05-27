/// A configured Tapo plug. Identified by its stable KLAP `device_id`
/// (survives IP changes — we can re-probe to update the IP).
class TapoDevice {
  final String id;     // KLAP device_id — stable unique key
  final String ip;     // current LAN IP
  final String name;   // custom name, or the auto-fetched nickname
  final String model;  // e.g. "P110"

  const TapoDevice({
    required this.id,
    required this.ip,
    required this.name,
    this.model = 'P110',
  });

  TapoDevice copyWith({String? ip, String? name}) => TapoDevice(
        id: id,
        ip: ip ?? this.ip,
        name: name ?? this.name,
        model: model,
      );

  Map<String, dynamic> toJson() =>
      {'id': id, 'ip': ip, 'name': name, 'model': model};

  factory TapoDevice.fromJson(Map<String, dynamic> j) => TapoDevice(
        id: j['id'] as String,
        ip: j['ip'] as String,
        name: j['name'] as String,
        model: j['model'] as String? ?? 'P110',
      );
}
