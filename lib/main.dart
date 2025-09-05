import 'dart:async';
import 'dart:io' show Platform;
import 'package:flutter/material.dart';
import 'package:mqtt_client/mqtt_client.dart';
import 'package:mqtt_client/mqtt_server_client.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:flutter/services.dart';

import 'models.dart';
import 'storage.dart';
import 'contacts_page.dart';
import 'history_page.dart';
import 'settings_page.dart';

class MqttService {
  final String server;
  final int port;
  final String topic;

  late final MqttServerClient _client;
  final _controller = StreamController<HeartData>.broadcast();
  Stream<HeartData> get stream => _controller.stream;

  MqttService({required this.server, required this.port, required this.topic}) {
    final clientId = 'flutter-${DateTime.now().microsecondsSinceEpoch}';
    _client = MqttServerClient(server, clientId)
      ..port = port
      ..logging(on: false)
      ..keepAlivePeriod = 30
      ..autoReconnect = true;

    _client.onConnected = () => debugPrint('MQTT conectado');
    _client.onDisconnected = () => debugPrint('MQTT desconectado');
    _client.onSubscribed = (t) => debugPrint('Suscrito a $t');
  }

  Future<void> connect() async {
    _client.connectionMessage = MqttConnectMessage()
        .startClean()
        .withWillQos(MqttQos.atLeastOnce)
        .keepAliveFor(30);

    try {
      await _client.connect();
    } catch (e) {
      _client.disconnect();
      rethrow;
    }

    _client.subscribe(topic, MqttQos.atMostOnce);
    _client.updates?.listen((events) {
      final rec = events.first;
      final recMess = rec.payload as MqttPublishMessage;
      final payload =
          MqttPublishPayload.bytesToStringAsString(recMess.payload.message);
      try {
        final data = HeartData.fromJsonStr(payload);
        _controller.add(data);
      } catch (e) {
        debugPrint('Error parseando JSON: $e | payload=$payload');
      }
    });
  }

  void dispose() {
    _controller.close();
    _client.disconnect();
  }
}

void main() => runApp(const HeartGuardApp());

class HeartGuardApp extends StatefulWidget {
  const HeartGuardApp({super.key});
  @override
  State<HeartGuardApp> createState() => _HeartGuardAppState();
}

class _HeartGuardAppState extends State<HeartGuardApp> {
  int _idx = 0;
  final pages = const [MonitorPage(), HistoryPage(), ContactsPage(), SettingsPage()];
  final titles = const ['Monitor', 'Historial', 'Contactos', 'Ajustes'];

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'HeartGuard',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.red),
        useMaterial3: true,
      ),
      home: Scaffold(
        appBar: AppBar(title: Text('HeartGuard — ${titles[_idx]}')),
        body: pages[_idx],
        bottomNavigationBar: NavigationBar(
          selectedIndex: _idx,
          destinations: const [
            NavigationDestination(icon: Icon(Icons.monitor_heart_outlined), label: 'Monitor'),
            NavigationDestination(icon: Icon(Icons.show_chart), label: 'Historial'),
            NavigationDestination(icon: Icon(Icons.group_outlined), label: 'Contactos'),
            NavigationDestination(icon: Icon(Icons.settings), label: 'Ajustes'),
          ],
          onDestinationSelected: (i) => setState(() => _idx = i),
        ),
      ),
      debugShowCheckedModeBanner: false,
    );
  }
}

class MonitorPage extends StatefulWidget {
  const MonitorPage({super.key});
  @override
  State<MonitorPage> createState() => _MonitorPageState();
}

class _MonitorPageState extends State<MonitorPage> {
  // Ajusta a tu broker/topic de Wokwi
  final String broker = 'test.mosquitto.org';
  final int port = 1883;
  final String topic = 'bracelet/demo2/hr';

  late final MqttService mqtt;
  StreamSubscription<HeartData>? sub;

  HeartData? last;
  String status = 'Conectando...';

  // Detección
  Settings s = Settings.defaults();
  int sustain = 0;
  double? ema;            // baseline con media móvil exponencial
  final alpha = 0.1;      // suavizado EMA
  bool simulateCrisis = false;

  @override
  void initState() {
    super.initState();
    mqtt = MqttService(server: broker, port: port, topic: topic);
    mqtt.connect().then((_) {
      setState(() => status = 'Conectado');
      sub = mqtt.stream.listen(_onData);
    }).catchError((e) {
      setState(() => status = 'Error de conexión: $e');
    });
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    s = await Storage.loadSettings();
    setState(() {});
  }

  Future<void> _onData(HeartData data) async {
    // 1) Timestamp real
    final nowTs = DateTime.now().millisecondsSinceEpoch;

    // 2) Simulación de crisis para la lógica
    final hrAdj = simulateCrisis ? (data.hr + 40) : data.hr;

    // 3) Guarda lo que ves en pantalla (hr ajustado) con timestamp real
    await Storage.appendReading(
      HeartData(hr: hrAdj, batt: data.batt, ts: nowTs),
    );

    // 4) EMA/baseline con el valor que estás mostrando
    ema = (ema == null) ? hrAdj.toDouble() : (alpha * hrAdj + (1 - alpha) * ema!);

    final isTachy = hrAdj >= s.tachyThreshold;
    final isSpike = (ema != null) && ((hrAdj - ema!) >= s.spikeDelta);

    if (isTachy || isSpike) {
      sustain += 1; // asumiendo 1 lectura/seg
      if (sustain >= s.sustainSeconds) {
        await _sendAlert(hr: hrAdj);
        sustain = 0;
      }
    } else {
      sustain = 0;
    }

    setState(() => last = HeartData(hr: hrAdj, batt: data.batt, ts: nowTs));
  }
  
  Future<void> _sendAlert({required int hr}) async {
    final contacts = await Storage.loadContacts();
    final body = 'ALERTA HeartGuard: pulso alto ($hr bpm). Necesito ayuda. (Demo)';

    // Construir destinatarios (Android usa coma, iOS suele aceptar ';')
    final phones = contacts.map((c) => c.phone.trim()).where((p) => p.isNotEmpty).toList();
    final recipients = phones.join(',');

    final uri = Uri.parse(
      recipients.isEmpty
        ? 'sms:?body=${Uri.encodeComponent(body)}'
        : 'sms:$recipients?body=${Uri.encodeComponent(body)}',
    );

    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Se abrió Mensajes con la alerta.')),
      );
      return;
    }

    // Fallback si no hay app de SMS (emulador)
    await Clipboard.setData(ClipboardData(text: body));
    if (!mounted) return;
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('No hay app de SMS'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Copié el texto de alerta al portapapeles.'),
            const SizedBox(height: 8),
            Text(body, style: const TextStyle(fontStyle: FontStyle.italic)),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    sub?.cancel();
    mqtt.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final hr = last?.hr;
    final batt = last?.batt;
    final connected = status == 'Conectado';

    Color hrColor;
    if (hr == null) {
      hrColor = Colors.grey;
    } else if (hr >= s.tachyThreshold) {
      hrColor = Colors.red;
    } else if (hr >= 100) {
      hrColor = Colors.orange;
    } else {
      hrColor = Colors.green;
    }

    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              Row(
                children: [
                  Chip(
                    label: Text(
                      connected ? 'Conectado' : status,
                      style: const TextStyle(color: Colors.white),
                    ),
                    backgroundColor: connected ? Colors.green : Colors.grey,
                  ),
                  const Spacer(),
                  // Opción A: Text + Switch (evita "infinite width" en Row)
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Text('Simular crisis'),
                      const SizedBox(width: 8),
                      Switch.adaptive(
                        value: simulateCrisis,
                        onChanged: (v) => setState(() => simulateCrisis = v),
                      ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Card(
                elevation: 2,
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    children: [
                      Text('Frecuencia cardiaca',
                          style: Theme.of(context).textTheme.titleLarge),
                      const SizedBox(height: 8),
                      Text(
                        hr == null ? '--' : '$hr bpm',
                        style: Theme.of(context)
                            .textTheme
                            .displayMedium
                            ?.copyWith(
                                color: hrColor, fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 12),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(Icons.battery_full),
                          const SizedBox(width: 8),
                          Text('Batería (sim.): '
                              '${batt == null ? '--' : '${(batt * 100).toStringAsFixed(0)}%'}'),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Umbral: ≥ ${s.tachyThreshold} bpm · '
                        'Spike: +${s.spikeDelta} bpm vs baseline · '
                        'Sostenido ${s.sustainSeconds}s',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: FilledButton.icon(
                      icon: const Icon(Icons.sms_failed_outlined),
                      label: const Text('Enviar alerta ahora'),
                      onPressed:
                          hr == null ? null : () => _sendAlert(hr: hr),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Text(
                    'Tip: publica JSON {"hr":78,"batt":0.72,"ts":${DateTime.now().millisecondsSinceEpoch}} '
                    'en $topic vía $broker:$port.\n'
                    'La app guarda historial y calcula promedio diario/semanal.',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
