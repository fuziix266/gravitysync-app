import 'package:socket_io_client/socket_io_client.dart' as IO;
import 'package:flutter/foundation.dart';

class SocketService {
  static final SocketService _instance = SocketService._internal();
  factory SocketService() => _instance;
  SocketService._internal();

  IO.Socket? _socket;

  // Callbacks reactivos
  Function(bool)? onConnectionStatusChanged;
  Function(List<dynamic>)? onSessionsUpdated;
  Function(Map<String, dynamic>)? onMessageReceived;
  Function(Map<String, dynamic>)? onChatMessages;
  Function(Map<String, dynamic>)? onAvailableActions;
  Function(Map<String, dynamic>)? onActionResult;

  final String myEmail = "admin@mavoo.cl";
  final String vpsUrl = "http://62.146.181.70:3001";
  bool isConnected = false;

  void init() {
    if (_socket != null) return;

    _socket = IO.io(vpsUrl, <String, dynamic>{
      'transports': ['websocket'],
      'autoConnect': true,
      'auth': {'email': myEmail},
    });

    _socket!.onConnect((_) {
      debugPrint('Conectado al VPS desde SocketService');
      isConnected = true;
      onConnectionStatusChanged?.call(true);
    });

    _socket!.onDisconnect((_) {
      debugPrint('Desconectado del VPS');
      isConnected = false;
      onConnectionStatusChanged?.call(false);
    });

    // Sesiones CDP del agente
    _socket!.on('sessions_list', (data) {
      if (data['sessions'] != null) {
        onSessionsUpdated?.call(data['sessions'] as List<dynamic>);
      }
    });

    // Respuestas de Antigravity (file watcher)
    _socket!.on('mobile_receive', (data) {
      onMessageReceived?.call(Map<String, dynamic>.from(data));
    });

    // ─── CDP Chat Events ─────────────────────────────────────────
    _socket!.on('chat_messages', (data) {
      onChatMessages?.call(Map<String, dynamic>.from(data));
    });

    _socket!.on('available_actions', (data) {
      onAvailableActions?.call(Map<String, dynamic>.from(data));
    });

    _socket!.on('action_result', (data) {
      onActionResult?.call(Map<String, dynamic>.from(data));
    });
  }

  // Enviar comando al chat de una sesión específica
  void sendCommand(String command, {String? sessionId, String? targetWindow}) {
    _socket?.emit('mobile_command', {
      'command': command,
      'sessionId': sessionId,
      'targetWindow': targetWindow,
      'timestamp': DateTime.now().toIso8601String(),
    });
  }

  // Pedir lectura del chat de una sesión
  void requestChat(String sessionId) {
    _socket?.emit('request_chat', {'sessionId': sessionId});
  }

  // Pedir botones de acción visibles de una sesión
  void requestActions(String sessionId) {
    _socket?.emit('request_actions', {'sessionId': sessionId});
  }

  // Ejecutar acción remota (accept, run, etc.)
  void sendRemoteAction(String sessionId, String action) {
    _socket?.emit('remote_action', {'sessionId': sessionId, 'action': action});
  }

  void dispose() {
    _socket?.disconnect();
    _socket?.dispose();
    _socket = null;
  }
}
