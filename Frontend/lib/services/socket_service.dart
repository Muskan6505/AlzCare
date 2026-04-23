// flutter-app/lib/services/socket_service.dart
// socket_io_client works on Flutter Web natively — no changes needed.
// The package automatically selects websocket transport on web.

import 'dart:async';
import 'package:socket_io_client/socket_io_client.dart' as sio;
import '../services/app_config.dart';
import '../../../../models/models.dart';

class SocketService {
  SocketService._();
  static final SocketService instance = SocketService._();

  sio.Socket? _socket;
  final _eventController = StreamController<SocketEvent>.broadcast();

  Stream<SocketEvent> get eventStream => _eventController.stream;
  bool get isConnected => _socket?.connected ?? false;

  void connectAsPatient(String patientId) {
    _connect();
    _socket?.onConnect((_) {
      _socket?.emit('join_patient', {'patientId': patientId});
    });
  }

  void connectAsCaregiver(String caregiverId, String patientId) {
    _connect();
    _socket?.onConnect((_) {
      _socket?.emit('join_caregiver', {'caregiverId': caregiverId, 'patientId': patientId});
    });
  }

  void _connect() {
    if (_socket != null && _socket!.connected) return;
    _socket = sio.io(
      AppConfig.socketUrl,
      sio.OptionBuilder()
          .setTransports(['websocket'])
          .enableAutoConnect()
          .enableReconnection()
          .setReconnectionDelay(3000)
          .setReconnectionAttempts(999)
          .build(),
    );
    _socket!
      ..on('play_audio',      (d) => _emit(SocketEventType.playAudio,      d))
      ..on('reminder_alert',  (d) => _emit(SocketEventType.reminderAlert,  d))
      ..on('distress_alert',  (d) => _emit(SocketEventType.distressAlert,  d))
      ..on('reminder_ack',    (d) => _emit(SocketEventType.reminderAck,    d))
      ..connect();
  }

  void _emit(SocketEventType type, dynamic raw) {
    final data = raw is Map ? Map<String, dynamic>.from(raw) : <String, dynamic>{};
    _eventController.add(SocketEvent(type: type, data: data));
  }

  void emitReminderAck(String patientId, String reminderId) {
    _socket?.emit('ack_reminder', {'patientId': patientId, 'reminderId': reminderId});
  }

  void dispose() {
    _socket?.disconnect();
    _socket?.dispose();
    _eventController.close();
  }
}
