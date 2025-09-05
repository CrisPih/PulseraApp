import 'package:flutter/material.dart';
import 'package:vibration/vibration.dart';
import 'package:heart_guard/models.dart';
import 'package:heart_guard/storage.dart';


class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  Settings s = Settings.defaults();

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    s = await Storage.loadSettings();
    setState(() {});
  }

  Future<void> _save() async {
    await Storage.saveSettings(s);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Ajustes guardados')));
  }

  Future<void> _vibeCalm() async {
    // Patrón 4-4-4 (inhalar-sostener-exhalar) con vibración breve al inicio
    if (await Vibration.hasVibrator()) {
      await Vibration.vibrate(duration: 200);
    }
  }

  @override
  Widget build(BuildContext context) {
    final tachyCtrl = TextEditingController(text: s.tachyThreshold.toString());
    final spikeCtrl = TextEditingController(text: s.spikeDelta.toString());
    final sustainCtrl = TextEditingController(text: s.sustainSeconds.toString());
    return Scaffold(
      appBar: AppBar(title: const Text('Ajustes & Calma')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Text('Umbrales de detección', style: TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          TextField(controller: tachyCtrl, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Tachicardia (≥ bpm)')),
          TextField(controller: spikeCtrl, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Spike súbito (+ bpm vs baseline)')),
          TextField(controller: sustainCtrl, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Segundos sostenidos antes de alerta')),
          const SizedBox(height: 12),
          FilledButton(onPressed: () {
            s = Settings(
              tachyThreshold: int.tryParse(tachyCtrl.text) ?? s.tachyThreshold,
              spikeDelta: int.tryParse(spikeCtrl.text) ?? s.spikeDelta,
              sustainSeconds: int.tryParse(sustainCtrl.text) ?? s.sustainSeconds,
            );
            _save();
          }, child: const Text('Guardar')),
          const SizedBox(height: 24),
          const Text('Respuesta calmante', style: TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          Text('Guía de respiración 4-4-4 con vibración breve para marcar el ritmo.'),
          const SizedBox(height: 8),
          FilledButton.icon(
            onPressed: _vibeCalm,
            icon: const Icon(Icons.spa_outlined),
            label: const Text('Iniciar vibración breve'),
          ),
        ],
      ),
    );
  }
}
