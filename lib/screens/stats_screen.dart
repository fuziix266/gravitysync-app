import 'package:flutter/material.dart';
import '../theme/app_colors.dart';
import '../services/socket_service.dart';

class StatsScreen extends StatefulWidget {
  const StatsScreen({super.key});

  @override
  State<StatsScreen> createState() => _StatsScreenState();
}

class _StatsScreenState extends State<StatsScreen> {
  final SocketService _socket = SocketService();

  int sessionAutoAccepts = 0;
  int totalAutoAccepts = 0;
  int commandsInjected = 0;
  int uptime = 0;
  bool cdpConnected = false;
  int? cdpPort;
  bool autoAcceptEnabled = false;
  bool patchActive = false;

  @override
  void initState() {
    super.initState();
    _socket.onStatsReceived = (data) {
      if (mounted) {
        setState(() {
          sessionAutoAccepts = data['sessionAutoAccepts'] ?? 0;
          totalAutoAccepts = data['totalAutoAccepts'] ?? 0;
          commandsInjected = data['commandsInjected'] ?? 0;
          uptime = data['uptime'] ?? 0;
          cdpPort = data['cdpPort'];
          cdpConnected = cdpPort != null;
          autoAcceptEnabled = data['autoAcceptEnabled'] ?? false;
          patchActive = data['patchStatus'] ?? false;
        });
      }
    };
    // Pedir stats al Agente
    _socket.requestStats();
  }

  @override
  Widget build(BuildContext context) {
    final timeSavedMin = (sessionAutoAccepts * 5 / 60).round();

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Estadísticas'),
        centerTitle: true,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded),
            onPressed: () => _socket.requestStats(),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Header
          ShaderMask(
            shaderCallback: (bounds) => const LinearGradient(
              colors: [Color(0xFFF59E0B), Color(0xFFEF4444), Color(0xFFA855F7)],
            ).createShader(Rect.fromLTWH(0, 0, bounds.width, bounds.height)),
            child: const Text(
              '⚡ Turbo Accept',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 28,
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
            ),
          ),
          const SizedBox(height: 4),
          const Text(
            'Estadísticas de automatización',
            textAlign: TextAlign.center,
            style: TextStyle(color: AppColors.textMuted, fontSize: 14),
          ),
          const SizedBox(height: 24),

          // Esta Sesión
          _sectionTitle('Esta Sesión', const Color(0xFFF59E0B)),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: _buildStatCard(
                  'Auto-accepts',
                  '$sessionAutoAccepts',
                  'clicks ahorrados',
                  const Color(0xFFF59E0B),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _buildStatCard(
                  'Tiempo ahorrado',
                  '~$timeSavedMin',
                  'minutos',
                  const Color(0xFF4ADE80),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _buildStatCard(
                  'Duración',
                  '$uptime',
                  'minutos activo',
                  const Color(0xFF58A6FF),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _buildStatCard(
                  'Comandos',
                  '$commandsInjected',
                  'inyectados',
                  const Color(0xFFA855F7),
                ),
              ),
            ],
          ),

          const SizedBox(height: 24),

          // Totales
          _sectionTitle('Totales', const Color(0xFF4ADE80)),
          const SizedBox(height: 8),
          _buildStatCard(
            'Total Auto-accepts',
            '$totalAutoAccepts',
            'de todos los tiempos',
            const Color(0xFFA855F7),
          ),

          const SizedBox(height: 24),

          // Status CDP
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppColors.border),
            ),
            child: Row(
              children: [
                Container(
                  width: 12,
                  height: 12,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: cdpConnected
                        ? const Color(0xFF4ADE80)
                        : const Color(0xFFF87171),
                    boxShadow: [
                      BoxShadow(
                        color:
                            (cdpConnected
                                    ? const Color(0xFF4ADE80)
                                    : const Color(0xFFF87171))
                                .withOpacity(0.5),
                        blurRadius: 8,
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                Text(
                  cdpConnected
                      ? 'CDP: Conectado — Puerto $cdpPort'
                      : 'CDP: No conectado',
                  style: const TextStyle(
                    fontWeight: FontWeight.w500,
                    fontSize: 14,
                  ),
                ),
                const Spacer(),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: autoAcceptEnabled
                        ? const Color(0xFF4ADE80).withOpacity(0.15)
                        : const Color(0xFFF87171).withOpacity(0.15),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    autoAcceptEnabled ? 'TURBO ON' : 'TURBO OFF',
                    style: TextStyle(
                      color: autoAcceptEnabled
                          ? const Color(0xFF4ADE80)
                          : const Color(0xFFF87171),
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _sectionTitle(String text, Color dotColor) {
    return Row(
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(shape: BoxShape.circle, color: dotColor),
        ),
        const SizedBox(width: 8),
        Text(
          text,
          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
        ),
      ],
    );
  }

  Widget _buildStatCard(
    String label,
    String value,
    String sub,
    Color accentColor,
  ) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label.toUpperCase(),
            style: const TextStyle(
              fontSize: 11,
              color: AppColors.textMuted,
              letterSpacing: 1.0,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            value,
            style: TextStyle(
              fontSize: 36,
              fontWeight: FontWeight.bold,
              color: accentColor,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            sub,
            style: const TextStyle(fontSize: 13, color: AppColors.textMuted),
          ),
        ],
      ),
    );
  }
}
