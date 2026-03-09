import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:flutter_widget_from_html/flutter_widget_from_html.dart';
import 'package:google_fonts/google_fonts.dart';
import '../services/socket_service.dart';
import '../theme/app_colors.dart';

class ChatScreen extends StatefulWidget {
  final String sessionId;
  final String sessionTitle;

  const ChatScreen({
    super.key,
    required this.sessionId,
    required this.sessionTitle,
  });

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final SocketService _socket = SocketService();
  final TextEditingController _controller = TextEditingController();
  final ScrollController _scrollController = ScrollController();

  // Suscripciones a streams (reemplazan callbacks singleton)
  StreamSubscription? _chatHistorySub;
  StreamSubscription? _newMessageSub;
  StreamSubscription? _messageUpdateSub;
  StreamSubscription? _agentTypingSub;

  List<Map<String, dynamic>> _messages = [];
  final Set<String> _knownUuids = {}; // Dedup client-side (patrón Mattermost)
  Map<String, dynamic>? _streamingMessage; // Mensaje parcial en streaming
  bool _isLoading = true;
  bool _isLoadingMore = false;
  bool _hasMore = false;
  bool _showThinking = false;
  bool _showCode = true;
  bool _showResponses = true;
  bool _isAgentWorking = false;
  int _currentOffset = 0;
  int _total = 0;
  static const int _pageSize = 15;

  @override
  void initState() {
    super.initState();
    _setupListeners();
    _loadInitialMessages();
    _scrollController.addListener(_onScroll);
  }

  void _setupListeners() {
    // Historial paginado desde PostgreSQL (filtrado por sessionId)
    _chatHistorySub = _socket.chatHistoryStream
        .where((data) => data['sessionId'] == widget.sessionId)
        .listen((data) {
          if (!mounted) return;
          _handleMessages(data, isInitial: _isLoading);
        });

    // Mensaje nuevo (dedup por UUID client-side + server-side)
    _newMessageSub = _socket.newMessageStream
        .where((data) => data['sessionId'] == widget.sessionId)
        .listen((data) {
          if (!mounted) return;

          final msg = data['message'] as Map<String, dynamic>?;
          if (msg == null) return;

          final uuid = msg['uuid']?.toString() ?? '';
          final type = msg['sectionType'] ?? 'response';

          // DEDUP CLIENT-SIDE: si ya tenemos este UUID, ignorar
          if (uuid.isNotEmpty && _knownUuids.contains(uuid)) return;

          // Filtrar thinking/status
          if (type == 'thinking' && !_showThinking) return;
          if (type == 'status') return;

          setState(() {
            if (uuid.isNotEmpty) _knownUuids.add(uuid);
            // Si llega un mensaje de usuario real, eliminar el temporal
            if (type == 'user') {
              _messages.removeWhere((m) => m['id'] == -1);
            }
            // Si tenemos un streaming message con el mismo UUID, reemplazarlo
            if (_streamingMessage != null &&
                _streamingMessage!['uuid'] == uuid) {
              _streamingMessage = null;
            }
            _messages.add(msg);
            _isAgentWorking = false;
          });
          _scrollToBottom();
        });

    // STREAMING: texto parcial de turno activo
    _messageUpdateSub = _socket.messageUpdateStream
        .where((data) => data['sessionId'] == widget.sessionId)
        .listen((data) {
          if (!mounted) return;

          final type = data['sectionType'] ?? 'response';
          if (type == 'thinking' && !_showThinking) return;
          if (type == 'status') return;

          setState(() {
            _streamingMessage = {
              'uuid': data['uuid'],
              'sectionType': type,
              'text': data['text'] ?? '',
              'hasCode': data['hasCode'] ?? false,
              'buttons': data['buttons'] ?? [],
              'isStreaming': true,
            };
            _isAgentWorking = true;
          });
          _scrollToBottom();
        });

    // Typing indicator unificado
    _agentTypingSub = _socket.agentTypingStream
        .where((data) => data['sessionId'] == widget.sessionId)
        .listen((data) {
          if (!mounted) return;
          final status = data['status'] ?? 'idle';
          setState(() {
            _isAgentWorking = status == 'working';
            if (!_isAgentWorking && _streamingMessage != null) {
              _streamingMessage = null;
            }
          });
          if (_isAgentWorking) _scrollToBottom();
        });
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  void _handleMessages(Map<String, dynamic> data, {required bool isInitial}) {
    final List<dynamic> newMessages = data['messages'] ?? [];
    final hasMore = data['hasMore'] ?? false;
    final total = data['total'] ?? 0;

    if (!mounted) return;

    setState(() {
      if (isInitial) {
        _messages = newMessages
            .map((m) => Map<String, dynamic>.from(m))
            .toList();
        // Poblar Set de UUIDs conocidos (dedup)
        _knownUuids.clear();
        for (final m in _messages) {
          final uuid = m['uuid']?.toString() ?? '';
          if (uuid.isNotEmpty) _knownUuids.add(uuid);
        }
        _isLoading = false;
      } else {
        final existingUuids = _messages
            .map((m) => m['uuid']?.toString() ?? '')
            .toSet();
        final unique = newMessages
            .where((m) {
              final uuid = m['uuid']?.toString() ?? '';
              return uuid.isEmpty || !existingUuids.contains(uuid);
            })
            .map((m) => Map<String, dynamic>.from(m))
            .toList();
        for (final m in unique) {
          final uuid = m['uuid']?.toString() ?? '';
          if (uuid.isNotEmpty) _knownUuids.add(uuid);
        }
        _messages.insertAll(0, unique);
        _isLoadingMore = false;
      }
      _hasMore = hasMore;
      _total = total;
    });

    if (isInitial && _messages.isNotEmpty) _scrollToBottom();
  }

  void _loadInitialMessages() {
    print(
      '[FLUTTER-DBG] _loadInitialMessages pidiendo historial para sessionId=${widget.sessionId}',
    );
    // Cargar desde PostgreSQL via VPS
    _socket.requestChatHistory(
      widget.sessionId,
      offset: 0,
      limit: _pageSize,
      includeThinking: _showThinking,
    );
  }

  void _loadMoreMessages() {
    if (_isLoadingMore || !_hasMore) return;
    setState(() => _isLoadingMore = true);
    _currentOffset += _pageSize;
    _socket.requestChatHistory(
      widget.sessionId,
      offset: _currentOffset,
      limit: _pageSize,
      includeThinking: _showThinking,
    );
  }

  /// Filtrar mensajes según toggles activos
  List<Map<String, dynamic>> get _filteredMessages {
    return _messages.where((msg) {
      final type = msg['sectionType'] ?? 'response';
      final hasCode = msg['hasCode'] == true;
      if (type == 'thinking' && !_showThinking) return false;
      if (type == 'status') return false;
      if (type == 'response' && hasCode && !_showCode) return false;
      if (type == 'response' && !hasCode && !_showResponses) return false;
      return true;
    }).toList();
  }

  void _onScroll() {
    if (_scrollController.position.pixels <=
            _scrollController.position.minScrollExtent + 100 &&
        !_isLoadingMore &&
        _hasMore) {
      _loadMoreMessages();
    }
  }

  void _sendMessage() {
    final text = _controller.text.trim();
    if (text.isEmpty) return;

    // Agregar mensaje temporal local (se reemplazará al recargar de BD)
    setState(() {
      _messages.add({
        'id': -1, // ID temporal, será reemplazado por la BD
        'sectionType': 'user',
        'text': text,
        'hasCode': false,
        'buttons': <String>[],
        'turnIndex': 99999,
        'timestamp': DateTime.now().toIso8601String(),
      });
      // NO marcar _isAgentWorking aquí — solo cuando el agente REALMENTE empiece
    });

    _controller.clear();
    _socket.sendCommand(text, sessionId: widget.sessionId);
    _scrollToBottom();
    // NO recarga delayed: VPS pushea new_message cuando esté listo
  }

  @override
  void dispose() {
    // Cancelar suscripciones a streams (cada ChatScreen limpia las suyas)
    _chatHistorySub?.cancel();
    _newMessageSub?.cancel();
    _messageUpdateSub?.cancel();
    _agentTypingSub?.cancel();

    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.surface,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: AppColors.textPrimary),
          onPressed: () => Navigator.pop(context),
        ),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              widget.sessionTitle,
              style: GoogleFonts.inter(
                color: AppColors.textPrimary,
                fontSize: 16,
                fontWeight: FontWeight.w600,
              ),
            ),
            Text(
              '$_total mensajes${_hasMore ? " (más disponibles)" : ""}',
              style: GoogleFonts.inter(
                color: AppColors.textSecondary,
                fontSize: 12,
              ),
            ),
          ],
        ),
        actions: [
          PopupMenuButton<String>(
            icon: const Icon(Icons.menu, color: AppColors.textSecondary),
            color: AppColors.surface,
            onSelected: (value) {
              setState(() {
                switch (value) {
                  case 'thinking':
                    _showThinking = !_showThinking;
                    _isLoading = true;
                    _currentOffset = 0;
                    _loadInitialMessages();
                    break;
                  case 'code':
                    _showCode = !_showCode;
                    break;
                  case 'responses':
                    _showResponses = !_showResponses;
                    break;
                  case 'refresh':
                    _isLoading = true;
                    _currentOffset = 0;
                    _loadInitialMessages();
                    break;
                }
              });
            },
            itemBuilder: (context) => [
              PopupMenuItem(
                value: 'thinking',
                child: Row(
                  children: [
                    Icon(
                      _showThinking
                          ? Icons.check_box
                          : Icons.check_box_outline_blank,
                      color: Colors.purple.shade300,
                      size: 20,
                    ),
                    const SizedBox(width: 10),
                    Text(
                      'Pensamiento',
                      style: TextStyle(color: AppColors.textPrimary),
                    ),
                  ],
                ),
              ),
              PopupMenuItem(
                value: 'code',
                child: Row(
                  children: [
                    Icon(
                      _showCode
                          ? Icons.check_box
                          : Icons.check_box_outline_blank,
                      color: Colors.orange,
                      size: 20,
                    ),
                    const SizedBox(width: 10),
                    Text(
                      'Código / Comandos',
                      style: TextStyle(color: AppColors.textPrimary),
                    ),
                  ],
                ),
              ),
              PopupMenuItem(
                value: 'responses',
                child: Row(
                  children: [
                    Icon(
                      _showResponses
                          ? Icons.check_box
                          : Icons.check_box_outline_blank,
                      color: AppColors.statusOnline,
                      size: 20,
                    ),
                    const SizedBox(width: 10),
                    Text(
                      'Respuestas',
                      style: TextStyle(color: AppColors.textPrimary),
                    ),
                  ],
                ),
              ),
              const PopupMenuDivider(),
              PopupMenuItem(
                value: 'refresh',
                child: Row(
                  children: [
                    const Icon(
                      Icons.refresh,
                      color: AppColors.textSecondary,
                      size: 20,
                    ),
                    const SizedBox(width: 10),
                    Text(
                      'Recargar mensajes',
                      style: TextStyle(color: AppColors.textPrimary),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
      body: Column(
        children: [
          // Thinking mode banner
          if (_showThinking)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              color: Colors.purple.shade900.withAlpha(80),
              child: Row(
                children: [
                  Icon(
                    Icons.psychology,
                    size: 16,
                    color: Colors.purple.shade300,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    'Modo razonamiento activado — viendo pensamientos del asistente',
                    style: GoogleFonts.inter(
                      fontSize: 11,
                      color: Colors.purple.shade200,
                    ),
                  ),
                ],
              ),
            ),
          // Chat messages area
          Expanded(
            child: _isLoading
                ? Center(
                    child: CircularProgressIndicator(
                      color: AppColors.primaryBase,
                    ),
                  )
                : _messages.isEmpty
                ? Center(
                    child: Text(
                      'No hay mensajes aún',
                      style: GoogleFonts.inter(
                        color: AppColors.textSecondary,
                        fontSize: 14,
                      ),
                    ),
                  )
                : ListView.builder(
                    controller: _scrollController,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 8,
                    ),
                    itemCount:
                        _filteredMessages.length +
                        (_isLoadingMore ? 1 : 0) +
                        (_streamingMessage != null ? 1 : 0) +
                        (_isAgentWorking ? 1 : 0),
                    itemBuilder: (context, index) {
                      if (_isLoadingMore && index == 0) {
                        return const Padding(
                          padding: EdgeInsets.all(16),
                          child: Center(
                            child: SizedBox(
                              width: 24,
                              height: 24,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            ),
                          ),
                        );
                      }

                      final msgIndex = _isLoadingMore ? index - 1 : index;
                      final filtered = _filteredMessages;

                      // Streaming message
                      if (_streamingMessage != null &&
                          msgIndex == filtered.length) {
                        return _buildMessageBubble(_streamingMessage!);
                      }

                      // Typing indicator
                      if (msgIndex >=
                          filtered.length +
                              (_streamingMessage != null ? 1 : 0)) {
                        return Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 8,
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              SizedBox(
                                width: 14,
                                height: 14,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.green.shade400,
                                ),
                              ),
                              const SizedBox(width: 8),
                              Text(
                                '🤖 Antigravity está trabajando...',
                                style: GoogleFonts.inter(
                                  fontSize: 12,
                                  color: Colors.green.shade300,
                                  fontStyle: FontStyle.italic,
                                ),
                              ),
                            ],
                          ),
                        );
                      }

                      final msg = filtered[msgIndex];
                      return _buildMessageBubble(msg);
                    },
                  ),
          ),
          _buildInputBar(),
        ],
      ),
    );
  }

  /// Construir contenido del mensaje: HTML si disponible, Markdown como fallback
  Widget _buildMessageContent(Map<String, dynamic> msg, bool isThinking) {
    final text = msg['text'] ?? '';
    final html = msg['html'] ?? '';
    final textColor = isThinking
        ? Colors.purple.shade200
        : AppColors.textPrimary;

    // Si hay HTML limpio del DOM, renderizar con HtmlWidget
    if (html.toString().isNotEmpty && html.toString().length > 10) {
      // Envolver en un div con estilos base para tema oscuro
      final styledHtml =
          '''
        <style>
          body { color: #E0E0E0; font-family: Inter, sans-serif; font-size: 13px; line-height: 1.6; }
          h1, h2, h3, h4 { color: #F5F5F5; margin: 8px 0 4px 0; }
          h1 { font-size: 18px; } h2 { font-size: 16px; } h3 { font-size: 14px; }
          p { margin: 4px 0; }
          code { background: rgba(0,0,0,0.3); color: #FFB74D; padding: 2px 4px; border-radius: 3px; font-family: 'Fira Code', monospace; font-size: 12px; }
          pre { background: rgba(0,0,0,0.4); padding: 12px; border-radius: 8px; overflow-x: auto; }
          pre code { background: none; padding: 0; }
          table { border-collapse: collapse; width: 100%; margin: 8px 0; }
          th, td { border: 1px solid #555; padding: 6px 10px; text-align: left; font-size: 12px; }
          th { background: rgba(255,255,255,0.1); color: #F5F5F5; font-weight: 600; }
          tr:nth-child(even) { background: rgba(255,255,255,0.03); }
          blockquote { border-left: 3px solid #888; padding-left: 12px; color: #AAAAAA; font-style: italic; }
          a { color: #64B5F6; }
          ul, ol { padding-left: 20px; }
          li { margin: 2px 0; }
          strong { color: #F5F5F5; }
          em { color: #BDBDBD; }
          hr { border: none; border-top: 1px solid #555; margin: 12px 0; }
          .diff-add { color: #81C784; } .diff-del { color: #E57373; }
        </style>
        <div>${html.toString()}</div>
      ''';

      return HtmlWidget(
        styledHtml,
        textStyle: GoogleFonts.inter(
          fontSize: 13,
          color: textColor,
          height: 1.5,
        ),
        customStylesBuilder: (element) {
          // Aplicar fondo oscuro a bloques de código
          if (element.localName == 'pre') {
            return {
              'background-color': 'rgba(0,0,0,0.35)',
              'border-radius': '8px',
              'padding': '12px',
            };
          }
          return null;
        },
      );
    }

    // Fallback: Markdown para mensajes legacy sin HTML
    return MarkdownBody(
      data: text.length > 2000 ? '${text.substring(0, 2000)}...' : text,
      selectable: true,
      styleSheet: MarkdownStyleSheet(
        p: GoogleFonts.inter(fontSize: 13, color: textColor, height: 1.5),
        code: GoogleFonts.firaCode(
          fontSize: 12,
          color: Colors.orange.shade300,
          backgroundColor: Colors.black26,
        ),
        codeblockDecoration: BoxDecoration(
          color: Colors.black26,
          borderRadius: BorderRadius.circular(8),
        ),
        h1: GoogleFonts.inter(
          fontSize: 18,
          fontWeight: FontWeight.bold,
          color: AppColors.textPrimary,
        ),
        h2: GoogleFonts.inter(
          fontSize: 16,
          fontWeight: FontWeight.bold,
          color: AppColors.textPrimary,
        ),
        h3: GoogleFonts.inter(
          fontSize: 14,
          fontWeight: FontWeight.w600,
          color: AppColors.textPrimary,
        ),
        listBullet: GoogleFonts.inter(
          fontSize: 13,
          color: AppColors.textSecondary,
        ),
        blockquote: GoogleFonts.inter(
          fontSize: 13,
          fontStyle: FontStyle.italic,
          color: AppColors.textSecondary,
        ),
      ),
    );
  }

  Widget _buildMessageBubble(Map<String, dynamic> msg) {
    final sectionType = msg['sectionType'] ?? 'response';
    final isUser = sectionType == 'user';
    final isThinking = sectionType == 'thinking';
    final text = msg['text'] ?? '';
    final hasCode = msg['hasCode'] == true;
    final buttons = (msg['buttons'] as List<dynamic>?) ?? [];

    // Colores por tipo de sección
    Color bgColor;
    Color borderColor;
    Color labelColor;
    IconData labelIcon;
    String labelText;

    if (isUser) {
      bgColor = AppColors.primaryBase.withAlpha(38);
      borderColor = AppColors.primaryBase.withAlpha(77);
      labelColor = AppColors.primaryBase;
      labelIcon = Icons.person;
      labelText = 'Tú';
    } else if (isThinking) {
      bgColor = Colors.purple.shade900.withAlpha(40);
      borderColor = Colors.purple.shade700.withAlpha(60);
      labelColor = Colors.purple.shade300;
      labelIcon = Icons.psychology;
      labelText = 'Razonamiento';
    } else {
      bgColor = AppColors.surface;
      borderColor = AppColors.surfaceVariant.withAlpha(128);
      labelColor = AppColors.statusOnline;
      labelIcon = Icons.smart_toy;
      labelText = 'Antigravity';
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Align(
        alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
        child: Container(
          constraints: BoxConstraints(
            maxWidth: MediaQuery.of(context).size.width * 0.85,
          ),
          decoration: BoxDecoration(
            color: bgColor,
            borderRadius: BorderRadius.circular(16).copyWith(
              bottomRight: isUser ? const Radius.circular(4) : null,
              bottomLeft: !isUser ? const Radius.circular(4) : null,
            ),
            border: Border.all(color: borderColor, width: 1),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(labelIcon, size: 14, color: labelColor),
                    const SizedBox(width: 6),
                    Text(
                      labelText,
                      style: GoogleFonts.inter(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: labelColor,
                      ),
                    ),
                    if (hasCode) ...[
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.orange.withAlpha(51),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          'code',
                          style: GoogleFonts.firaCode(
                            fontSize: 9,
                            color: Colors.orange,
                          ),
                        ),
                      ),
                    ],
                    if (isThinking) ...[
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.purple.withAlpha(51),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          'thinking',
                          style: GoogleFonts.firaCode(
                            fontSize: 9,
                            color: Colors.purple.shade300,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              // Content — usa HTML si disponible, Markdown como fallback
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 6, 12, 8),
                child: _buildMessageContent(msg, isThinking),
              ),
              // Action buttons
              if (buttons.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
                  child: Wrap(
                    spacing: 6,
                    runSpacing: 4,
                    children: buttons.map<Widget>((btn) {
                      return OutlinedButton(
                        onPressed: () {
                          _socket.sendRemoteAction(
                            widget.sessionId,
                            btn.toString(),
                          );
                        },
                        style: OutlinedButton.styleFrom(
                          foregroundColor: AppColors.primaryBase,
                          side: BorderSide(
                            color: AppColors.primaryBase.withAlpha(102),
                          ),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 4,
                          ),
                          minimumSize: const Size(0, 28),
                          textStyle: GoogleFonts.inter(fontSize: 11),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                        ),
                        child: Text(btn.toString()),
                      );
                    }).toList(),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  void _stopGeneration() {
    _socket.stopGeneration(sessionId: widget.sessionId);
    setState(() {
      _isAgentWorking = false;
      _streamingMessage = null;
    });
  }

  Widget _buildInputBar() {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
      decoration: BoxDecoration(
        color: AppColors.surface,
        border: Border(
          top: BorderSide(color: AppColors.surfaceVariant.withAlpha(77)),
        ),
      ),
      child: SafeArea(
        child: Row(
          children: [
            Expanded(
              child: TextField(
                controller: _controller,
                style: GoogleFonts.inter(
                  color: AppColors.textPrimary,
                  fontSize: 14,
                ),
                decoration: InputDecoration(
                  hintText: _isAgentWorking
                      ? 'Antigravity trabajando...'
                      : 'Escribe un mensaje...',
                  hintStyle: GoogleFonts.inter(
                    color: _isAgentWorking
                        ? Colors.orange.shade300
                        : AppColors.textSecondary,
                    fontSize: 14,
                  ),
                  filled: true,
                  fillColor: AppColors.background,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(24),
                    borderSide: BorderSide.none,
                  ),
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 10,
                  ),
                ),
                onSubmitted: (_) => _sendMessage(),
              ),
            ),
            const SizedBox(width: 8),
            // Botón dinámico: SEND o STOP
            Material(
              color: _isAgentWorking
                  ? Colors.red.shade600
                  : AppColors.primaryBase,
              borderRadius: BorderRadius.circular(24),
              child: InkWell(
                borderRadius: BorderRadius.circular(24),
                onTap: _isAgentWorking ? _stopGeneration : _sendMessage,
                child: Padding(
                  padding: const EdgeInsets.all(10),
                  child: Icon(
                    _isAgentWorking ? Icons.stop : Icons.send,
                    color: Colors.white,
                    size: 20,
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
