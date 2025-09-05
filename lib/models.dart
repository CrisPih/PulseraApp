import 'dart:convert';

class HeartData {
  final int hr;
  final double batt;
  final int ts;
  HeartData({required this.hr, required this.batt, required this.ts});

  factory HeartData.fromJsonStr(String jsonStr) {
    final map = jsonDecode(jsonStr) as Map<String, dynamic>;
    return HeartData(
      hr: (map['hr'] as num?)?.toInt() ?? 0,
      batt: (map['batt'] as num?)?.toDouble() ?? 0.0,
      ts: (map['ts'] as num?)?.toInt() ?? 0,
    );
  }

  Map<String, dynamic> toMap() => {'hr': hr, 'batt': batt, 'ts': ts};
}

class EmergencyContact {
  final String name;
  final String phone;
  EmergencyContact({required this.name, required this.phone});

  Map<String, dynamic> toMap() => {'name': name, 'phone': phone};
  factory EmergencyContact.fromMap(Map<String, dynamic> m) =>
      EmergencyContact(name: m['name'] ?? '', phone: m['phone'] ?? '');
}

class Settings {
  final int tachyThreshold;
  final int spikeDelta;
  final int sustainSeconds;
  Settings({
    required this.tachyThreshold,
    required this.spikeDelta,
    required this.sustainSeconds,
  });

  Map<String, dynamic> toMap() => {
        'tachy': tachyThreshold,
        'spike': spikeDelta,
        'sustain': sustainSeconds,
      };

  factory Settings.fromMap(Map<String, dynamic> m) => Settings(
        tachyThreshold: m['tachy'] ?? 130,
        spikeDelta: m['spike'] ?? 35,
        sustainSeconds: m['sustain'] ?? 5,
      );

  static Settings defaults() =>
      Settings(tachyThreshold: 130, spikeDelta: 35, sustainSeconds: 5);
}
