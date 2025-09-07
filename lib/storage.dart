import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:heart_guard/models.dart';


class Storage {
  static const _kContacts = 'contacts';
  static const _kReadings = 'readings'; // lista de HeartData (json)
  static const _kSettings = 'settings';

  static Future<List<EmergencyContact>> loadContacts() async {
    final sp = await SharedPreferences.getInstance();
    final raw = sp.getStringList(_kContacts) ?? [];
    return raw.map((s) => EmergencyContact.fromMap(jsonDecode(s))).toList();
  }

  static Future<void> saveContacts(List<EmergencyContact> list) async {
    final sp = await SharedPreferences.getInstance();
    final raw = list.map((c) => jsonEncode(c.toMap())).toList();
    await sp.setStringList(_kContacts, raw);
  }

  static Future<void> appendReading(HeartData d) async {
    final sp = await SharedPreferences.getInstance();
    final raw = sp.getStringList(_kReadings) ?? [];
    raw.add(jsonEncode(d.toMap()));
    // Mantén sólo las últimas 5000 lecturas para no crecer infinito
    final keep = raw.length > 5000 ? raw.sublist(raw.length - 5000) : raw;
    await sp.setStringList(_kReadings, keep);
  }

  static Future<List<HeartData>> loadReadings() async {
    final sp = await SharedPreferences.getInstance();
    final raw = sp.getStringList(_kReadings) ?? [];
    return raw.map((s) {
      final m = jsonDecode(s) as Map<String, dynamic>;
      return HeartData(
        hr: (m['hr'] as num).toInt(),
        batt: (m['batt'] as num).toDouble(),
        ts: (m['ts'] as num).toInt(),
      );
    }).toList();
  }

  static Future<Settings> loadSettings() async {
    final sp = await SharedPreferences.getInstance();
    final raw = sp.getString(_kSettings);
    if (raw == null) return Settings.defaults();
    return Settings.fromMap(jsonDecode(raw));
  }

  static Future<void> clearReadings() async {
    final sp = await SharedPreferences.getInstance();
    await sp.remove(_kReadings);
  }


  static Future<void> saveSettings(Settings s) async {
    final sp = await SharedPreferences.getInstance();
    await sp.setString(_kSettings, jsonEncode(s.toMap()));
  }
}
