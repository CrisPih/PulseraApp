import 'package:flutter/material.dart';
import 'package:heart_guard/models.dart';
import 'package:heart_guard/storage.dart';
import 'package:fl_chart/fl_chart.dart';

class HistoryPage extends StatefulWidget {
  const HistoryPage({super.key});

  @override
  State<HistoryPage> createState() => _HistoryPageState();
}

class _HistoryPageState extends State<HistoryPage> {
  List<HeartData> data = [];
  Map<DateTime, double> dailyAvg = {};
  double weeklyAvg = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    data = await Storage.loadReadings();
    data.sort((a, b) => a.ts.compareTo(b.ts));

    // Promedio por día
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

    // Últimos 7 días
    final now = DateTime.now();
    final sevenAgo = now.subtract(const Duration(days: 7));
    final lastWeek = data.where(
      (d) => DateTime.fromMillisecondsSinceEpoch(d.ts).isAfter(sevenAgo),
    );
    final list = lastWeek.map((e) => e.hr).toList();
    weeklyAvg = list.isEmpty ? 0 : list.reduce((a, b) => a + b) / list.length;

    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final points = dailyAvg.entries.toList()
      ..sort((a, b) => a.key.compareTo(b.key));

    // Genera spots y calcula min/max con colchón para series planas
    final spots = List.generate(
      points.length,
      (i) => FlSpot(i.toDouble(), points[i].value),
    );

    double? minY;
    double? maxY;
    if (spots.isNotEmpty) {
      // calcula min/max sin importar dart:math
      minY = spots.first.y;
      maxY = spots.first.y;
      for (final s in spots) {
        if (s.y < minY!) minY = s.y;
        if (s.y > maxY!) maxY = s.y;
      }
      // evita rango cero (serie plana) y añade un pequeño padding
      if ((maxY! - minY!).abs() < 1e-6) {
        minY = minY! - 5;
        maxY = maxY! + 5;
      } else {
        minY = minY! - 3;
        maxY = maxY! + 3;
      }
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Historial')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
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
                  child: points.isEmpty
                      ? const Center(child: Text('Sin datos suficientes'))
                      : LineChart(
                          LineChartData(
                            minX: 0,
                            maxX: (spots.length - 1).toDouble(),
                            minY: minY,
                            maxY: maxY,
                            gridData: FlGridData(show: true),
                            titlesData: FlTitlesData(
                              bottomTitles: AxisTitles(
                                sideTitles: SideTitles(
                                  showTitles: true,
                                  interval: 1,
                                  getTitlesWidget: (v, meta) {
                                    final i = v.toInt();
                                    if (i < 0 || i >= points.length) {
                                      return const SizedBox.shrink();
                                    }
                                    final dt = points[i].key;
                                    return Text(
                                      '${dt.month}/${dt.day}',
                                      style: const TextStyle(fontSize: 10),
                                    );
                                  },
                                ),
                              ),
                              leftTitles: const AxisTitles(
                                sideTitles: SideTitles(
                                  showTitles: true,
                                  reservedSize: 32,
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
                                dotData:
                                    FlDotData(show: spots.length <= 2), // puntos si hay pocos
                                barWidth: 3,
                              ),
                            ],
                          ),
                        ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
