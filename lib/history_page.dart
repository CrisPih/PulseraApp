import 'package:flutter/material.dart';
import 'storage.dart';
import 'models.dart';

class HistoryPage extends StatefulWidget {
  const HistoryPage({super.key});
  @override
  State<HistoryPage> createState() => _HistoryPageState();
}

class _HistoryPageState extends State<HistoryPage> {
  List<HeartData> data = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    data = await Storage.loadReadings();
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Historial')),
      body: ListView.builder(
        itemCount: data.length,
        itemBuilder: (_, i) {
          final d = data[i];
          final dt = DateTime.fromMillisecondsSinceEpoch(d.ts).toLocal();
          return ListTile(
            leading: const Icon(Icons.monitor_heart_outlined),
            title: Text('${d.hr} bpm'),
            subtitle: Text('${dt.year}-${dt.month.toString().padLeft(2,'0')}-${dt.day.toString().padLeft(2,'0')} '
                '${dt.hour.toString().padLeft(2,'0')}:${dt.minute.toString().padLeft(2,'0')}'),
          );
        },
      ),
    );
  }
}
