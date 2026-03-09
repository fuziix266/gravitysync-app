import 'package:flutter/material.dart';
import '../theme/app_colors.dart';
import '../services/socket_service.dart';
import 'chat_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final SocketService _socketService = SocketService();
  bool _isConnected = false;
  List<dynamic> _sessions = [];

  @override
  void initState() {
    super.initState();
    _initSocket();
  }

  void _initSocket() {
    _socketService.init();

    _socketService.onConnectionStatusChanged = (status) {
      if (mounted) {
        setState(() => _isConnected = status);
        if (status) {
          _socketService.requestSessions();
        }
      }
    };

    _socketService.onSessionsUpdated = (list) {
      if (mounted) {
        setState(() {
          _sessions = list;
        });
      }
    };

    if (_socketService.isConnected) {
      _socketService.requestSessions();
    }
  }

  Future<void> _refreshSessions() async {
    _socketService.requestSessions();
    await Future.delayed(const Duration(milliseconds: 1500));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text(
          'GravitySync',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        centerTitle: true,
        actions: [
          // Indicador de conexión
          Container(
            margin: const EdgeInsets.only(right: 16),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: _isConnected ? const Color(0xFF22C55E) : Colors.red,
                  ),
                ),
                const SizedBox(width: 6),
                Text(
                  _isConnected ? 'Online' : 'Offline',
                  style: TextStyle(
                    color: _isConnected ? const Color(0xFF22C55E) : Colors.red,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
        ],
        leading: IconButton(
          icon: const Icon(Icons.chevron_left),
          onPressed: () {},
        ),
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Search Bar
          Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: 16.0,
              vertical: 8.0,
            ),
            child: TextField(
              decoration: InputDecoration(
                hintText: 'Buscar sesiones...',
                prefixIcon: const Icon(
                  Icons.search,
                  color: AppColors.textMuted,
                ),
                filled: true,
                fillColor: AppColors.surface,
                contentPadding: const EdgeInsets.symmetric(vertical: 0),
                enabledBorder: OutlineInputBorder(
                  borderSide: BorderSide.none,
                  borderRadius: BorderRadius.circular(24.0),
                ),
                focusedBorder: OutlineInputBorder(
                  borderSide: const BorderSide(color: AppColors.primaryBase),
                  borderRadius: BorderRadius.circular(24.0),
                ),
              ),
            ),
          ),

          const SizedBox(height: 16),

          // Header
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16.0),
            child: Row(
              children: [
                const Text(
                  'SESIONES CDP',
                  style: TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 1.0,
                  ),
                ),
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: AppColors.primaryBase.withAlpha(26),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    '${_sessions.length}',
                    style: const TextStyle(
                      color: AppColors.primaryBase,
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 8),

          // Lista de Sesiones CDP con pull-to-refresh
          Expanded(
            child: _sessions.isEmpty
                ? RefreshIndicator(
                    onRefresh: _refreshSessions,
                    color: AppColors.primaryBase,
                    child: ListView(
                      children: [
                        SizedBox(
                          height: MediaQuery.of(context).size.height * 0.55,
                          child: Center(
                            child: _isConnected
                                ? _buildNoSessionsState()
                                : _buildDisconnectedState(),
                          ),
                        ),
                      ],
                    ),
                  )
                : RefreshIndicator(
                    onRefresh: _refreshSessions,
                    color: AppColors.primaryBase,
                    child: ListView.builder(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      itemCount: _sessions.length,
                      itemBuilder: (context, index) {
                        final session = _sessions[index];
                        return _buildSessionCard(
                          sessionId: session['id'] ?? '',
                          project: session['project'] ?? 'Unknown',
                          ide: session['ide'] ?? 'Unknown',
                          title: session['title'] ?? '',
                          messageCount: session['messageCount'] ?? 0,
                          lastMessage: session['lastMessage'] ?? '',
                        );
                      },
                    ),
                  ),
          ),
        ],
      ),
    );
  }

  /// Estado vacío: conectado pero sin sesiones CDP activas
  Widget _buildNoSessionsState() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Ícono con efecto glassmorphism
          Container(
            width: 88,
            height: 88,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  AppColors.primaryBase.withAlpha(40),
                  Colors.purple.withAlpha(30),
                ],
              ),
              border: Border.all(
                color: AppColors.primaryBase.withAlpha(60),
                width: 1.5,
              ),
            ),
            child: Icon(
              Icons.desktop_access_disabled_rounded,
              size: 40,
              color: AppColors.primaryBase.withAlpha(180),
            ),
          ),
          const SizedBox(height: 24),
          const Text(
            'No hay instancias de Antigravity\nabiertas en tu equipo',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: AppColors.textPrimary,
              fontSize: 16,
              fontWeight: FontWeight.w600,
              height: 1.4,
            ),
          ),
          const SizedBox(height: 12),
          Text(
            'Abre Antigravity en tu computador\npara ver las sesiones de chat aquí.',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: AppColors.textMuted.withAlpha(200),
              fontSize: 13,
              height: 1.5,
            ),
          ),
          const SizedBox(height: 24),
          OutlinedButton.icon(
            onPressed: () => _socketService.requestSessions(),
            icon: const Icon(Icons.refresh, size: 16),
            label: const Text('Buscar sesiones'),
            style: OutlinedButton.styleFrom(
              foregroundColor: AppColors.primaryBase,
              side: BorderSide(color: AppColors.primaryBase.withAlpha(100)),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
            ),
          ),
        ],
      ),
    );
  }

  /// Estado vacío: desconectado del VPS
  Widget _buildDisconnectedState() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 88,
            height: 88,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: Colors.red.withAlpha(20),
              border: Border.all(color: Colors.red.withAlpha(60), width: 1.5),
            ),
            child: const Stack(
              alignment: Alignment.center,
              children: [
                Icon(Icons.cloud_off_rounded, size: 36, color: Colors.red),
              ],
            ),
          ),
          const SizedBox(height: 24),
          const Text(
            'Conectando con el servidor...',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: AppColors.textPrimary,
              fontSize: 16,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 12),
          Text(
            'Verificando conexión con el VPS.\nEsto puede tomar unos segundos.',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: AppColors.textMuted.withAlpha(200),
              fontSize: 13,
              height: 1.5,
            ),
          ),
          const SizedBox(height: 24),
          const SizedBox(
            width: 24,
            height: 24,
            child: CircularProgressIndicator(
              strokeWidth: 2.5,
              color: AppColors.primaryBase,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSessionCard({
    required String sessionId,
    required String project,
    required String ide,
    required String title,
    int messageCount = 0,
    String lastMessage = '',
  }) {
    // Color del ícono según IDE
    Color ideColor;
    IconData ideIcon;
    switch (ide) {
      case 'Cursor':
        ideColor = const Color(0xFF8B5CF6); // purple
        ideIcon = Icons.code;
        break;
      case 'VSCode':
        ideColor = const Color(0xFF3B82F6); // blue
        ideIcon = Icons.code;
        break;
      case 'Antigravity':
        ideColor = const Color(0xFF4ADE80); // green
        ideIcon = Icons.change_history;
        break;
      default:
        ideColor = const Color(0xFF6B7280); // gray
        ideIcon = Icons.web;
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: ideColor.withOpacity(0.2)),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          hoverColor: AppColors.surfaceVariant.withOpacity(0.5),
          onTap: () {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) => ChatScreen(
                  sessionId: sessionId,
                  sessionTitle: '$project - $ide',
                ),
              ),
            );
          },
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Row(
              children: [
                // Icono IDE con gradiente
                Container(
                  width: 52,
                  height: 52,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(12),
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [ideColor, ideColor.withOpacity(0.6)],
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: ideColor.withOpacity(0.3),
                        blurRadius: 12,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: Icon(ideIcon, color: Colors.white, size: 26),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Expanded(
                            child: Text(
                              project,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: AppColors.textPrimary,
                                fontSize: 16,
                                fontWeight: FontWeight.w600,
                                letterSpacing: -0.5,
                              ),
                            ),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: ideColor.withOpacity(0.1),
                              borderRadius: BorderRadius.circular(4),
                              border: Border.all(
                                color: ideColor.withOpacity(0.2),
                              ),
                            ),
                            child: Text(
                              ide.toUpperCase(),
                              style: TextStyle(
                                color: ideColor,
                                fontSize: 9,
                                fontWeight: FontWeight.bold,
                                letterSpacing: 1.0,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 2),
                      Text(
                        messageCount > 0
                            ? '$messageCount mensajes'
                            : (title.length > 50
                                  ? '${title.substring(0, 50)}...'
                                  : title),
                        style: const TextStyle(
                          color: AppColors.textMuted,
                          fontSize: 11,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                const Icon(
                  Icons.chevron_right,
                  color: AppColors.textMuted,
                  size: 20,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
