import 'package:telephony/telephony.dart';

class SmsSender {
  final Telephony _telephony = Telephony.instance;

  /// Pide permiso al usuario para poder enviar SMS
  Future<bool> ensurePermission() async {
    final granted = await _telephony.requestSmsPermissions ?? false;
    return granted;
  }

  /// Envío silencioso básico (usa la SIM por defecto del sistema)
  Future<void> sendSilent({
    required String to,
    required String body,
  }) async {
    await _telephony.sendSms(
      to: to,
      message: body,
      statusListener: (SendStatus status) {
        // Opcional: ver en consola el estado (SENT / DELIVERED / FAILED)
        // debugPrint("SMS to $to => $status");
      },
    );
  }
}
