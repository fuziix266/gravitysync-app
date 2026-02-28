import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import '../theme/app_colors.dart';
import '../theme/app_typography.dart';
import '../services/socket_service.dart';

class ChatScreen extends StatefulWidget {
  final String sessionId;
  final String projectName;
  const ChatScreen({
    super.key,
    required this.sessionId,
    required this.projectName,
  });

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final TextEditingController _controller = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final SocketService _socketService = SocketService();
  final List<Map<String, dynamic>> _messages = [];
  List<Map<String, dynamic>> _availableActions = [];
  Timer? _chatPollTimer;
  bool isTyping = false;

  @override
  void initState() {
    super.initState();

    // Escuchar mensajes leídos del chat vía CDP
    _socketService.onChatMessages = (data) {
      if (!mounted) return;
      if (data['sessionId'] != widget.sessionId) return;

      final messages = data['messages'] as List<dynamic>? ?? [];
      setState(() {
        _messages.clear();
        for (final msg in messages) {
          _messages.add({
            'sender': msg['role'] == 'user' ? 'me' : 'bot',
            'content': msg['text'] ?? '',
            'timestamp': DateTime.now(),
          });
        }
        isTyping = false;
      });
      _scrollToBottom();
    };

    // Escuchar botones de acción detectados
    _socketService.onAvailableActions = (data) {
      if (!mounted) return;
      if (data['sessionId'] != widget.sessionId) return;

      final actions = data['actions'] as List<dynamic>? ?? [];
      setState(() {
        _availableActions = actions
            .map((a) => Map<String, dynamic>.from(a))
            .toList();
      });
    };

    // Escuchar resultados de acciones remotas
    _socketService.onActionResult = (data) {
      if (!mounted) return;
      if (data['sessionId'] != widget.sessionId) return;

      final success = data['success'] == true;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            success ? '✓ Acción ejecutada' : '✗ Error: ${data['error']}',
          ),
          backgroundColor: success ? const Color(0xFF22C55E) : Colors.red,
          duration: const Duration(seconds: 2),
        ),
      );
    };

    // Escuchar respuestas de Antigravity vía file watcher (legacy)
    _socketService.onMessageReceived = (data) {
      if (mounted) {
        setState(() {
          _messages.add({
            'sender': 'bot',
            'content': data['content'],
            'timestamp': DateTime.now(),
          });
          isTyping = false;
        });
        _scrollToBottom();
      }
    };

    // Hacer la primera lectura del chat y detectar botones
    _requestChatUpdate();
    _requestActionsUpdate();

    // Polling de mensajes del chat cada 2 segundos
    _chatPollTimer = Timer.periodic(const Duration(seconds: 2), (_) {
      _requestChatUpdate();
      _requestActionsUpdate();
    });
  }

  void _requestChatUpdate() {
    _socketService.requestChat(widget.sessionId);
  }

  void _requestActionsUpdate() {
    _socketService.requestActions(widget.sessionId);
  }

  void _sendMessage() {
    final text = _controller.text.trim();
    if (text.isEmpty) return;

    setState(() {
      _messages.add({
        'sender': 'me',
        'content': text,
        'timestamp': DateTime.now(),
      });
      isTyping = true;
    });

    _socketService.sendCommand(text, sessionId: widget.sessionId);
    _controller.clear();
    _scrollToBottom();
  }

  void _executeRemoteAction(String action) {
    _socketService.sendRemoteAction(widget.sessionId, action);
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

  @override
  void dispose() {
    _chatPollTimer?.cancel();
    _controller.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Widget _buildActionBar() {
    if (_availableActions.isEmpty) return const SizedBox.shrink();

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: AppColors.surface,
        border: Border(
          top: BorderSide(color: AppColors.border.withOpacity(0.3)),
        ),
      ),
      child: Row(
        children: [
          const Icon(Icons.touch_app, color: AppColors.textMuted, size: 16),
          const SizedBox(width: 8),
          const Text(
            'Acciones:',
            style: TextStyle(color: AppColors.textMuted, fontSize: 12),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: _availableActions.map((action) {
                  final type = action['type'] ?? 'unknown';
                  final label = action['label'] ?? type;
                  Color btnColor;
                  IconData btnIcon;
                  switch (type) {
                    case 'run':
                      btnColor = const Color(0xFF22C55E);
                      btnIcon = Icons.play_arrow;
                      break;
                    case 'accept':
                      btnColor = const Color(0xFF3B82F6);
                      btnIcon = Icons.check;
                      break;
                    case 'save':
                      btnColor = const Color(0xFFF59E0B);
                      btnIcon = Icons.save;
                      break;
                    case 'retry':
                      btnColor = const Color(0xFFF97316);
                      btnIcon = Icons.refresh;
                      break;
                    case 'allow':
                      btnColor = const Color(0xFF8B5CF6);
                      btnIcon = Icons.shield;
                      break;
                    default:
                      btnColor = const Color(0xFF6B7280);
                      btnIcon = Icons.touch_app;
                  }

                  return Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: ElevatedButton.icon(
                      onPressed: () => _executeRemoteAction(type),
                      icon: Icon(btnIcon, size: 16),
                      label: Text(label, style: const TextStyle(fontSize: 12)),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: btnColor,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 6,
                        ),
                        minimumSize: Size.zero,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(20),
                        ),
                      ),
                    ),
                  );
                }).toList(),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMessageBubble(Map<String, dynamic> msg) {
    final isMe = msg['sender'] == 'me';

    return Align(
      alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(bottom: 12, left: 16, right: 16),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: isMe ? null : AppColors.surfaceVariant,
          gradient: isMe ? AppColors.senderGradient : null,
          boxShadow: isMe
              ? [
                  BoxShadow(
                    color: const Color(0xFF0D0DF2).withOpacity(0.4),
                    blurRadius: 15,
                    offset: const Offset(0, 5),
                  ),
                ]
              : null,
          borderRadius: BorderRadius.circular(20).copyWith(
            bottomRight: isMe
                ? const Radius.circular(4)
                : const Radius.circular(20),
            bottomLeft: !isMe
                ? const Radius.circular(4)
                : const Radius.circular(20),
          ),
        ),
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.85,
        ),
        child: isMe
            ? Text(
                msg['content'],
                style: const TextStyle(color: Colors.white, fontSize: 16),
              )
            : MarkdownBody(
                data: msg['content'],
                styleSheet: MarkdownStyleSheet(
                  p: const TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 15,
                    height: 1.4,
                  ),
                  code: AppTypography.codeStyle,
                  codeblockDecoration: BoxDecoration(
                    color: AppColors.background,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: AppColors.border),
                  ),
                ),
              ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(widget.projectName, style: const TextStyle(fontSize: 16)),
            Row(
              children: [
                Icon(
                  Icons.circle,
                  color: _socketService.isConnected
                      ? AppColors.statusOnline
                      : AppColors.textMuted,
                  size: 10,
                ),
                const SizedBox(width: 6),
                Text(
                  _socketService.isConnected ? 'CDP Conectado' : 'Sin conexión',
                  style: Theme.of(context).textTheme.labelSmall,
                ),
              ],
            ),
          ],
        ),
      ),
      body: Column(
        children: [
          // Barra de acciones remotas (accept, run, etc.)
          _buildActionBar(),

          // Mensajes del chat
          Expanded(
            child: _messages.isEmpty
                ? const Center(
                    child: Text(
                      'Leyendo chat de Antigravity...',
                      style: TextStyle(color: AppColors.textMuted),
                    ),
                  )
                : ListView.builder(
                    controller: _scrollController,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    itemCount: _messages.length,
                    itemBuilder: (context, index) {
                      return _buildMessageBubble(_messages[index]);
                    },
                  ),
          ),

          if (isTyping)
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 24, vertical: 8),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'Antigravity está escribiendo...',
                  style: TextStyle(
                    color: AppColors.textMuted,
                    fontSize: 13,
                    fontStyle: FontStyle.italic,
                  ),
                ),
              ),
            ),

          // Área de tipeo
          Container(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
            decoration: const BoxDecoration(color: AppColors.background),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Expanded(
                  child: TextField(
                    controller: _controller,
                    minLines: 1,
                    maxLines: 4,
                    textInputAction: TextInputAction.send,
                    decoration: InputDecoration(
                      hintText: 'Comando...',
                      filled: true,
                      fillColor: AppColors.surface,
                      prefixIcon: const Icon(
                        Icons.add,
                        color: AppColors.primaryBase,
                      ),
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 12,
                      ),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(24),
                        borderSide: BorderSide.none,
                      ),
                    ),
                    onSubmitted: (_) => _sendMessage(),
                  ),
                ),
                const SizedBox(width: 12),
                Container(
                  decoration: BoxDecoration(
                    gradient: AppColors.senderGradient,
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: const Color(0xFF6200EA).withOpacity(0.4),
                        blurRadius: 10,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: IconButton(
                    onPressed: _sendMessage,
                    icon: const Icon(Icons.send_rounded, color: Colors.white),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
