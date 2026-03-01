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
  Function(Map<String, dynamic>)? onChatHistory;
  Function(Map<String, dynamic>)? onNewMessage;
  Function(Map<String, dynamic>)? onMessageUpdate; // Streaming parcial
  Function(Map<String, dynamic>)? onAgentWorking;
  Function(Map<String, dynamic>)? onAgentIdle;
  Function(Map<String, dynamic>)? onAgentTyping; // Nuevo unificado
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

    // ─── Eventos v2.0 (Mattermost-inspired) ────────────────────

    // Mensaje nuevo guardado (ya dedup server-side)
    _socket!.on('new_message', (data) {
      onNewMessage?.call(Map<String, dynamic>.from(data));
    });

    // Streaming: texto parcial de turno activo
    _socket!.on('message_update', (data) {
      onMessageUpdate?.call(Map<String, dynamic>.from(data));
    });

    // Typing indicator (unificado: status working/idle)
    _socket!.on('agent_typing', (data) {
      onAgentTyping?.call(Map<String, dynamic>.from(data));
    });

    // Legacy typing events → redirect al unificado
    _socket!.on('agent_working', (data) {
      final d = Map<String, dynamic>.from(data);
      d['status'] = 'working';
      onAgentTyping?.call(d);
      onAgentWorking?.call(d);
    });

    _socket!.on('agent_idle', (data) {
      final d = Map<String, dynamic>.from(data);
      d['status'] = 'idle';
      onAgentTyping?.call(d);
      onAgentIdle?.call(d);
    });

    // ─── Eventos legacy (mantenidos para compatibilidad) ──────────
    _socket!.on('chat_messages', (data) {
      onChatMessages?.call(Map<String, dynamic>.from(data));
    });

    _socket!.on('chat_history_response', (data) {
      onChatHistory?.call(Map<String, dynamic>.from(data));
    });

    _socket!.on('available_actions', (data) {
      onAvailableActions?.call(Map<String, dynamic>.from(data));
    });

    _socket!.on('action_result', (data) {
      onActionResult?.call(Map<String, dynamic>.from(data));
    });

    // Confirmación de mensaje del usuario guardado
    _socket!.on('message_saved', (data) {
      onNewMessage?.call(Map<String, dynamic>.from(data));
    });
  }

  // Enviar comando al chat
  void sendCommand(String command, {String? sessionId, String? targetWindow}) {
    _socket?.emit('mobile_command', {
      'command': command,
      'sessionId': sessionId,
      'targetWindow': targetWindow,
      'timestamp': DateTime.now().toIso8601String(),
    });
  }

  // Pedir historial paginado (PostgreSQL via VPS)
  void requestChatHistory(
    String sessionId, {
    int offset = 0,
    int limit = 15,
    bool includeThinking = false,
  }) {
    _socket?.emit('request_chat_history', {
      'sessionId': sessionId,
      'offset': offset,
      'limit': limit,
      'includeThinking': includeThinking,
    });
  }

  // Sync por seq (Mattermost pattern)
  void sync(String sessionId, {int lastSeq = 0}) {
    _socket?.emit('sync', {'sessionId': sessionId, 'lastSeq': lastSeq});
  }

  // Detener generación del agente
  void stopGeneration({String? sessionId}) {
    _socket?.emit('stop_generation', {
      'sessionId': sessionId,
      'timestamp': DateTime.now().toIso8601String(),
    });
  }

  // Legacy
  void requestChat(
    String sessionId, {
    int offset = 0,
    int limit = 15,
    bool includeThinking = false,
  }) {
    _socket?.emit('request_chat', {
      'sessionId': sessionId,
      'offset': offset,
      'limit': limit,
      'includeThinking': includeThinking,
    });
  }

  void requestActions(String sessionId) {
    _socket?.emit('request_actions', {'sessionId': sessionId});
  }

  void sendRemoteAction(String sessionId, String action) {
    _socket?.emit('remote_action', {'sessionId': sessionId, 'action': action});
  }

  void dispose() {
    _socket?.disconnect();
    _socket?.dispose();
    _socket = null;
  }
}
