import 'package:flutter/material.dart';
import 'package:heart_guard/models.dart';
import 'package:heart_guard/storage.dart';
import 'package:fl_chart/fl_chart.dart';

enum ViewMode { daily, buckets }

class HistoryPage extends StatefulWidget {
  const HistoryPage({super.key});

  @override
  State<HistoryPage> createState() => _HistoryPageState();
}

class _HistoryPageState extends State<HistoryPage> {
  List<HeartData> data = [];
  Map<DateTime, double> dailyAvg = {};
  double weeklyAvg = 0;

  // Modo demo por buckets
  ViewMode mode = ViewMode.daily;
  final int bucketSize = 5;   // 5 lecturas = 1 “día” demo
  final int maxBuckets = 30;  // límite de puntos para no saturar

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    data = await Storage.loadReadings();
    data.sort((a, b) => a.ts.compareTo(b.ts));

    // Promedio por día (real)
    final map = <DateTime, List<int>>{};
    for (final d in data) {
      final day = DateTime.fromMillisecondsSinceEpoch(d.ts).toLocal();
      final key = DateTime(day.year, day.month, day.day);
      map.putIfAbsent(key, () => []).add(d.hr);
    }
    dailyAvg = {
      for (final e in map.entries)
        e.key: (e.value.reduce((a, b) => a + b) / e.value.length)
    };

    // Últimos 7 días (para tarjeta “Promedio semanal”)
    final now = DateTime.now();
    final sevenAgo = now.subtract(const Duration(days: 7));
    final lastWeek = data.where(
      (d) => DateTime.fromMillisecondsSinceEpoch(d.ts).isAfter(sevenAgo),
    );
    final list = lastWeek.map((e) => e.hr).toList();
    weeklyAvg = list.isEmpty ? 0 : list.reduce((a, b) => a + b) / list.length;

    setState(() {});
  }

  // Serie para graficar según el modo
  List<MapEntry<String, double>> _buildSeries() {
    if (mode == ViewMode.daily) {
      final entries = dailyAvg.entries.toList()
        ..sort((a, b) => a.key.compareTo(b.key));
      return entries
          .map((e) => MapEntry('${e.key.month}/${e.key.day}', e.value))
          .toList();
    }

    if (data.isEmpty) return const <MapEntry<String, double>>[];
    // Buckets (cada N lecturas = 1 punto)
    final vals = data.map((e) => e.hr.toDouble()).toList();
    final buckets = <double>[];
    for (int i = 0; i < vals.length; i += bucketSize) {
      final end = (i + bucketSize < vals.length) ? i + bucketSize : vals.length;
      final slice = vals.sublist(i, end);
      final avg = slice.reduce((a, b) => a + b) / slice.length;
      buckets.add(avg);
    }
    // Mantén los últimos maxBuckets
    final start = buckets.length > maxBuckets ? buckets.length - maxBuckets : 0;
    final trimmed = buckets.sublist(start);

    return List.generate(
      trimmed.length,
      (i) => MapEntry('D${i + 1}', trimmed[i]),
    );
  }

  @override
  Widget build(BuildContext context) {
    final series = _buildSeries();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Historial'),
        actions: [
          IconButton(
            tooltip: 'Borrar historial',
            icon: const Icon(Icons.delete_sweep_outlined),
            onPressed: () async {
              final ok = await showDialog<bool>(
                context: context,
                builder: (_) => AlertDialog(
                  title: const Text('Borrar historial'),
                  content: const Text('Esto eliminará todas las lecturas guardadas. ¿Continuar?'),
                  actions: [
                    TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancelar')),
                    FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Borrar')),
                  ],
                ),
              );
              if (ok == true) {
                await Storage.clearReadings();
                setState(() {
                  data = [];
                  dailyAvg = {};
                  weeklyAvg = 0;
                });
                if (!mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Historial borrado')),
                );
              }
            },
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            // Selector de vista (compacto, adaptable y desplazable)
            SizedBox(
              height: 36,
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    const Text('Vista:'),
                    const SizedBox(width: 8),
                    ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 320),
                      child: SizedBox(
                        height: 30,
                        child: SegmentedButton<ViewMode>(
                          segments: const [
                            ButtonSegment(value: ViewMode.daily, label: Text('Diario')),
                            ButtonSegment(value: ViewMode.buckets, label: Text('Demo')),
                          ],
                          selected: {mode},
                          onSelectionChanged: (s) => setState(() => mode = s.first),
                          style: ButtonStyle(
                            visualDensity: const VisualDensity(horizontal: -4, vertical: -4),
                            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                            padding: const MaterialStatePropertyAll(
                              EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            ),
                            minimumSize: const MaterialStatePropertyAll(Size(0, 26)),
                            textStyle: const MaterialStatePropertyAll(TextStyle(fontSize: 11)),
                            shape: MaterialStatePropertyAll(
                              RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),

            Card(
              child: ListTile(
                title: const Text('Promedio semanal (últimos 7 días)'),
                subtitle: Text(
                  weeklyAvg == 0 ? '--' : '${weeklyAvg.toStringAsFixed(1)} bpm',
                ),
              ),
            ),
            const SizedBox(height: 12),

            Expanded(
              child: Card(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: series.isEmpty
                      ? const Center(child: Text('Sin datos suficientes'))
                      : _buildChart(series),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildChart(List<MapEntry<String, double>> series) {
    final spots = List.generate(
      series.length,
      (i) => FlSpot(i.toDouble(), series[i].value),
    );

    // min/max con padding y redondeo a múltiplos de 5
    late double minY;
    late double maxY;
    minY = spots.first.y;
    maxY = spots.first.y;
    for (final s in spots) {
      if (s.y < minY) minY = s.y;
      if (s.y > maxY) maxY = s.y;
    }
    if ((maxY - minY).abs() < 1e-6) {
      minY -= 5;
      maxY += 5;
    } else {
      minY -= 3;
      maxY += 3;
    }
    double _down5(double x) => (x / 5).floor() * 5;
    double _up5(double x) => (x / 5).ceil() * 5;
    minY = _down5(minY);
    maxY = _up5(maxY);

    return LineChart(
      LineChartData(
        minX: 0,
        maxX: (spots.length - 1).toDouble(),
        minY: minY,
        maxY: maxY,
        gridData: FlGridData(show: true, drawVerticalLine: false),
        titlesData: FlTitlesData(
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              interval: 1,
              getTitlesWidget: (v, meta) {
                final i = v.toInt();
                if (i < 0 || i >= series.length) return const SizedBox.shrink();
                return Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(series[i].key, style: const TextStyle(fontSize: 10)),
                );
              },
            ),
          ),
          leftTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 32,
              interval: 5, // ticks cada 5 bpm
            ),
          ),
          rightTitles: const AxisTitles(
            sideTitles: SideTitles(showTitles: false),
          ),
          topTitles: const AxisTitles(
            sideTitles: SideTitles(showTitles: false),
          ),
        ),
        lineBarsData: [
          LineChartBarData(
            isCurved: true,
            spots: spots,
            barWidth: 3,
            dotData: FlDotData(show: spots.length <= 20), // puntos si la serie es corta
          ),
        ],
      ),
    );
  }
}
