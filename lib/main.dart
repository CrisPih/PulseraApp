import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:mqtt_client/mqtt_client.dart';
import 'package:mqtt_client/mqtt_server_client.dart';
import 'package:url_launcher/url_launcher.dart';

/// Modelo para el JSON recibido del ESP32 (simulado en Wokwi)
class HeartData {
  final int hr;
  final double batt;
  final int ts;
  HeartData({required this.hr, required this.batt, required this.ts});

  factory HeartData.fromJson(String jsonStr) {
    final map = jsonDecode(jsonStr) as Map<String, dynamic>;
    return HeartData(
      hr: (map['hr'] as num?)?.toInt() ?? 0,
      batt: (map['batt'] as num?)?.toDouble() ?? 0.0,
      ts: (map['ts'] as num?)?.toInt() ?? 0,
    );
  }
}

/// Servicio MQTT simple
class MqttService {
  final String server;
  final int port;
  final String topic;

  late final MqttServerClient _client;
  final _controller = StreamController<HeartData>.broadcast();
  Stream<HeartData> get stream => _controller.stream;

  MqttService({
    required this.server,
    required this.port,
    required this.topic,
  }) {
    final clientId =
        'flutter-${DateTime.now().millisecondsSinceEpoch}-${DateTime.now().microsecondsSinceEpoch}';

    _client = MqttServerClient(server, clientId);
    _client.port = port;
    _client.logging(on: false);
    _client.keepAlivePeriod = 30;
    _client.autoReconnect = true;

    // Callbacks (asignados fuera de la cascada)
    _client.onConnected = _onConnected;
    _client.onDisconnected = _onDisconnected;
    _client.onSubscribed = _onSubscribed;
  }

  void _onConnected() => debugPrint('MQTT conectado');
  void _onDisconnected() => debugPrint('MQTT desconectado');
  void _onSubscribed(String topic) => debugPrint('Suscrito a $topic');


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
        final data = HeartData.fromJson(payload);
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

void main() {
  runApp(const HeartGuardApp());
}

class HeartGuardApp extends StatelessWidget {
  const HeartGuardApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'HeartGuard',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.red),
        useMaterial3: true,
      ),
      home: const MonitorPage(),
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
  // Ajusta estos para que coincidan con tu simulación Wokwi
  final String broker = 'test.mosquitto.org';
  final int port = 1883;
  final String topic = 'bracelet/demo2/hr';

  late final MqttService mqtt;
  StreamSubscription<HeartData>? sub;

  HeartData? last;
  String status = 'Conectando...';
  int sustainedHighSeconds = 0;
  int? baseline; // se fija con el 1er dato (simple para demo)
  final int tachyThreshold = 130; // umbral alto
  final int spikeDelta = 35; // salto súbito (vs baseline) que dispara alerta

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
  }

  void _onData(HeartData data) {
    setState(() {
      last = data;
      baseline ??= data.hr;

      final isTachy = data.hr >= tachyThreshold;
      final isSpike = (baseline != null) && (data.hr - baseline! >= spikeDelta);

      if (isTachy || isSpike) {
        sustainedHighSeconds += 1; // publicas cada 1 s en Wokwi
        if (sustainedHighSeconds >= 5) {
          _sendAlert(hr: data.hr);
          sustainedHighSeconds = 0; // evita spam
        }
      } else {
        sustainedHighSeconds = 0;
      }
    });
  }

  Future<void> _sendAlert({required int hr}) async {
    final message =
        'ALERTA: pulso alto ($hr bpm). Necesito ayuda. (Prototipo)';
    final smsUri = Uri.parse('sms:?body=${Uri.encodeComponent(message)}');
    if (await canLaunchUrl(smsUri)) {
      await launchUrl(smsUri);
    }
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Alerta: se abrió SMS con el mensaje.')),
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
    } else if (hr >= tachyThreshold) {
      hrColor = Colors.red;
    } else if (hr >= 100) {
      hrColor = Colors.orange;
    } else {
      hrColor = Colors.green;
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('HeartGuard – Demo MQTT'),
        actions: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Chip(
              label: Text(
                connected ? 'Conectado' : status,
                style: const TextStyle(color: Colors.white),
              ),
              backgroundColor: connected ? Colors.green : Colors.grey,
            ),
          )
        ],
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                Card(
                  elevation: 2,
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      children: [
                        Text(
                          'Frecuencia cardiaca',
                          style: Theme.of(context).textTheme.titleLarge,
                        ),
                        const SizedBox(height: 8),
                        Text(
                          hr == null ? '--' : '$hr bpm',
                          style: Theme.of(context)
                              .textTheme
                              .displayMedium
                              ?.copyWith(color: hrColor, fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(height: 12),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Icon(Icons.battery_full),
                            const SizedBox(width: 8),
                            Text('Batería (simulada): ${batt == null ? '--' : '${(batt * 100).toStringAsFixed(0)}%'}'),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Umbral alto: ≥ $tachyThreshold bpm · Spike: +$spikeDelta bpm vs. baseline',
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
                        onPressed: hr == null ? null : () => _sendAlert(hr: hr),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Text(
                      'Tip: deja tu simulación Wokwi publicando en $topic hacia $broker:$port.\n'
                      'Esta app se suscribe y procesa JSON como {"hr":78,"batt":0.72,"ts":123456}.',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
