import 'package:flutter/material.dart';
import 'package:heart_guard/models.dart';
import 'package:heart_guard/storage.dart';

class ContactsPage extends StatefulWidget {
  const ContactsPage({super.key});

  @override
  State<ContactsPage> createState() => _ContactsPageState();
}

class _ContactsPageState extends State<ContactsPage> {
  List<EmergencyContact> contacts = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    contacts = await Storage.loadContacts();
    setState(() {});
  }

  Future<void> _addOrEdit({EmergencyContact? existing, int? index}) async {
    final nameCtrl = TextEditingController(text: existing?.name);
    final phoneCtrl = TextEditingController(text: existing?.phone);
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(existing == null ? 'Nuevo contacto' : 'Editar contacto'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(controller: nameCtrl, decoration: const InputDecoration(labelText: 'Nombre')),
            TextField(controller: phoneCtrl, decoration: const InputDecoration(labelText: 'Teléfono')),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancelar')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Guardar')),
        ],
      ),
    );
    if (ok != true) return;

    final c = EmergencyContact(name: nameCtrl.text.trim(), phone: phoneCtrl.text.trim());
    if (existing != null && index != null) {
      contacts[index] = c;
    } else {
      contacts.add(c);
    }
    await Storage.saveContacts(contacts);
    setState(() {});
  }

  Future<void> _delete(int index) async {
    contacts.removeAt(index);
    await Storage.saveContacts(contacts);
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Contactos de emergencia')),
      body: ListView.separated(
        itemCount: contacts.length,
        separatorBuilder: (_, __) => const Divider(height: 0),
        itemBuilder: (_, i) {
          final c = contacts[i];
          return ListTile(
            title: Text(c.name),
            subtitle: Text(c.phone),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(icon: const Icon(Icons.edit), onPressed: () => _addOrEdit(existing: c, index: i)),
                IconButton(icon: const Icon(Icons.delete), onPressed: () => _delete(i)),
              ],
            ),
          );
        },
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _addOrEdit(),
        icon: const Icon(Icons.add),
        label: const Text('Agregar'),
      ),
    );
  }
}
