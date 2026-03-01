import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
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

  List<Map<String, dynamic>> _messages = [];
  bool _isLoading = true;
  bool _isLoadingMore = false;
  bool _hasMore = false;
  bool _showThinking = false; // Toggle para mostrar pensamientos
  bool _isAgentWorking = false; // Typing indicator
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
    // Historial paginado desde PostgreSQL (carga inicial y paginación)
    _socket.onChatHistory = (data) {
      if (data['sessionId'] != widget.sessionId) return;
      _handleMessages(data, isInitial: _isLoading);
    };

    // Mensaje nuevo individual (dedup server-side, ya filtrado por VPS)
    _socket.onNewMessage = (data) {
      if (data['sessionId'] != widget.sessionId) return;
      if (!mounted) return;

      final msg = data['message'] as Map<String, dynamic>?;
      if (msg == null) return;

      final type = msg['sectionType'] ?? 'response';

      // Filtrar thinking si el toggle no está activo
      if (type == 'thinking' && !_showThinking) return;
      // Filtrar status siempre
      if (type == 'status') return;

      setState(() {
        // Si llega un mensaje de usuario real, eliminar el temporal
        if (type == 'user') {
          _messages.removeWhere((m) => m['id'] == -1);
        }
        _messages.add(msg);
        _isAgentWorking =
            false; // Si llegó un mensaje, el agente ya no está "trabajando"
      });

      // Auto-scroll al final
      _scrollToBottom();
    };

    // Typing indicator: agente trabajando
    _socket.onAgentWorking = (data) {
      if (data['sessionId'] != widget.sessionId) return;
      if (!mounted) return;
      setState(() => _isAgentWorking = true);
      _scrollToBottom();
    };

    // Typing indicator: agente terminó
    _socket.onAgentIdle = (data) {
      if (data['sessionId'] != widget.sessionId) return;
      if (!mounted) return;
      setState(() => _isAgentWorking = false);
    };

    // Legacy: respuesta a request_chat (para compatibilidad)
    _socket.onChatMessages = (data) {
      if (data['sessionId'] != widget.sessionId) return;
      _handleMessages(data, isInitial: true);
    };
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
        _isLoading = false;
      } else {
        final existingIds = _messages.map((m) => m['id']).toSet();
        final unique = newMessages
            .where((m) => !existingIds.contains(m['id']))
            .map((m) => Map<String, dynamic>.from(m))
            .toList();
        _messages.insertAll(0, unique);
        _isLoadingMore = false;
      }
      _hasMore = hasMore;
      _total = total;
    });

    if (isInitial && _messages.isNotEmpty) {
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
  }

  void _loadInitialMessages() {
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

  void _toggleThinking() {
    setState(() {
      _showThinking = !_showThinking;
      _isLoading = true;
      _messages.clear();
      _currentOffset = 0;
    });
    _loadInitialMessages();
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
      _isAgentWorking = true; // Mostrar "trabajando..." inmediatamente
    });

    _controller.clear();
    _socket.sendCommand(text, sessionId: widget.sessionId);
    _scrollToBottom();
    // NO recarga delayed: VPS pushea new_message cuando esté listo
  }

  @override
  void dispose() {
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    _controller.dispose();
    _socket.onChatMessages = null;
    _socket.onChatHistory = null;
    _socket.onNewMessage = null;
    _socket.onAgentWorking = null;
    _socket.onAgentIdle = null;
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
          // Toggle thinking
          IconButton(
            icon: Icon(
              _showThinking ? Icons.psychology : Icons.psychology_outlined,
              color: _showThinking
                  ? Colors.purple.shade300
                  : AppColors.textSecondary,
            ),
            tooltip: _showThinking
                ? 'Ocultar pensamientos'
                : 'Mostrar pensamientos',
            onPressed: _toggleThinking,
          ),
          IconButton(
            icon: const Icon(Icons.refresh, color: AppColors.textSecondary),
            onPressed: () {
              setState(() {
                _isLoading = true;
                _currentOffset = 0;
              });
              _loadInitialMessages();
            },
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
                    itemCount: _messages.length + (_isLoadingMore ? 1 : 0),
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
                      final msg = _messages[msgIndex];
                      return _buildMessageBubble(msg);
                    },
                  ),
          ),
          // Typing indicator
          if (_isAgentWorking)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              color: AppColors.surface,
              child: Row(
                children: [
                  SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.green.shade400,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Text(
                    '🤖 Antigravity está trabajando...',
                    style: GoogleFonts.inter(
                      fontSize: 13,
                      color: Colors.green.shade300,
                      fontStyle: FontStyle.italic,
                    ),
                  ),
                ],
              ),
            ),
          _buildInputBar(),
        ],
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
              // Content
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 6, 12, 8),
                child: MarkdownBody(
                  data: text.length > 2000
                      ? '${text.substring(0, 2000)}...'
                      : text,
                  selectable: true,
                  styleSheet: MarkdownStyleSheet(
                    p: GoogleFonts.inter(
                      fontSize: 13,
                      color: isThinking
                          ? Colors.purple.shade200
                          : AppColors.textPrimary,
                      height: 1.5,
                    ),
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
                ),
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
                  hintText: 'Escribe un mensaje...',
                  hintStyle: GoogleFonts.inter(
                    color: AppColors.textSecondary,
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
            Material(
              color: AppColors.primaryBase,
              borderRadius: BorderRadius.circular(24),
              child: InkWell(
                borderRadius: BorderRadius.circular(24),
                onTap: _sendMessage,
                child: const Padding(
                  padding: EdgeInsets.all(10),
                  child: Icon(Icons.send, color: Colors.white, size: 20),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
