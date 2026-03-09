import 'dart:async';
import 'package:socket_io_client/socket_io_client.dart' as IO;
import 'package:flutter/foundation.dart';

class SocketService {
  static final SocketService _instance = SocketService._internal();
  factory SocketService() => _instance;
  SocketService._internal();

  IO.Socket? _socket;

  // ─── Callbacks simples (sin conflicto de routing) ────────────────
  Function(bool)? onConnectionStatusChanged;
  Function(List<dynamic>)? onSessionsUpdated;

  // ─── Streams broadcast (múltiples listeners simultáneos) ─────────
  final _chatHistoryController =
      StreamController<Map<String, dynamic>>.broadcast();
  final _newMessageController =
      StreamController<Map<String, dynamic>>.broadcast();
  final _messageUpdateController =
      StreamController<Map<String, dynamic>>.broadcast();
  final _agentTypingController =
      StreamController<Map<String, dynamic>>.broadcast();
  final _availableActionsController =
      StreamController<Map<String, dynamic>>.broadcast();
  final _actionResultController =
      StreamController<Map<String, dynamic>>.broadcast();

  // ─── Streams públicos ────────────────────────────────────────────
  Stream<Map<String, dynamic>> get chatHistoryStream =>
      _chatHistoryController.stream;
  Stream<Map<String, dynamic>> get newMessageStream =>
      _newMessageController.stream;
  Stream<Map<String, dynamic>> get messageUpdateStream =>
      _messageUpdateController.stream;
  Stream<Map<String, dynamic>> get agentTypingStream =>
      _agentTypingController.stream;
  Stream<Map<String, dynamic>> get availableActionsStream =>
      _availableActionsController.stream;
  Stream<Map<String, dynamic>> get actionResultStream =>
      _actionResultController.stream;

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

    // Sesiones CDP del agente (callback simple — solo HomeScreen lo usa)
    _socket!.on('sessions_list', (data) {
      if (data['sessions'] != null) {
        onSessionsUpdated?.call(data['sessions'] as List<dynamic>);
      }
    });

    // ─── Eventos v2.0 (Mattermost-inspired) → Streams ─────────────

    // Mensaje nuevo guardado (ya dedup server-side)
    _socket!.on('new_message', (data) {
      _newMessageController.add(Map<String, dynamic>.from(data));
    });

    // Streaming: texto parcial de turno activo
    _socket!.on('message_update', (data) {
      _messageUpdateController.add(Map<String, dynamic>.from(data));
    });

    // Typing indicator (unificado: status working/idle)
    _socket!.on('agent_typing', (data) {
      _agentTypingController.add(Map<String, dynamic>.from(data));
    });

    // Legacy typing events → redirect al stream unificado
    _socket!.on('agent_working', (data) {
      final d = Map<String, dynamic>.from(data);
      d['status'] = 'working';
      _agentTypingController.add(d);
    });

    _socket!.on('agent_idle', (data) {
      final d = Map<String, dynamic>.from(data);
      d['status'] = 'idle';
      _agentTypingController.add(d);
    });

    _socket!.on('chat_history_response', (data) {
      _chatHistoryController.add(Map<String, dynamic>.from(data));
    });

    _socket!.on('available_actions', (data) {
      _availableActionsController.add(Map<String, dynamic>.from(data));
    });

    _socket!.on('action_result', (data) {
      _actionResultController.add(Map<String, dynamic>.from(data));
    });

    // Confirmación de mensaje del usuario guardado → mismo stream que new_message
    _socket!.on('message_saved', (data) {
      _newMessageController.add(Map<String, dynamic>.from(data));
    });
  }

  // Enviar comando al chat
  void sendCommand(String command, {String? sessionId, String? targetWindow}) {
    _socket?.emit('send_command', {
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

  // Solicitar lista de sesiones al VPS (pull activo)
  void requestSessions() {
    _socket?.emit('request_sessions', {});
  }

  // Detener generación del agente
  void stopGeneration({String? sessionId}) {
    _socket?.emit('stop_generation', {
      'sessionId': sessionId,
      'timestamp': DateTime.now().toIso8601String(),
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
    // No cerrar los StreamControllers — el singleton persiste
    // y otros widgets pueden suscribirse después
  }
}
