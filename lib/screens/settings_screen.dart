import 'package:flutter/material.dart';
import '../theme/app_colors.dart';
import '../services/socket_service.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final SocketService _socket = SocketService();

  bool autoAcceptEnabled = false;
  bool patchActive = false;
  bool cdpConnected = false;
  int? cdpPort;
  Map<String, bool> options = {
    'autoRun': true,
    'autoAcceptAll': true,
    'autoSave': true,
    'autoRetry': true,
    'autoAllow': false,
  };

  @override
  void initState() {
    super.initState();
    // Escuchar stats para actualizar estado de patch/CDP
    _socket.onStatsReceived = (data) {
      if (mounted) {
        setState(() {
          patchActive = data['patchStatus'] ?? false;
          cdpPort = data['cdpPort'];
          cdpConnected = cdpPort != null;
          autoAcceptEnabled = data['autoAcceptEnabled'] ?? false;
          if (data['autoAcceptConfig'] != null) {
            final cfg = Map<String, dynamic>.from(data['autoAcceptConfig']);
            cfg.forEach((k, v) {
              if (v is bool) options[k] = v;
            });
          }
        });
      }
    };
    _socket.requestStats();
  }

  final List<Map<String, dynamic>> _optionsMeta = [
    {
      'key': 'autoRun',
      'icon': Icons.play_arrow_rounded,
      'title': 'Comandos de Terminal',
      'trigger': 'Run Alt+⏎',
      'desc':
          'Auto-acepta la ejecución de comandos que el agente necesita correr.',
      'risk': 'bajo',
      'riskColor': const Color(0xFF4ADE80),
    },
    {
      'key': 'autoAcceptAll',
      'icon': Icons.edit_rounded,
      'title': 'Ediciones de Archivo',
      'trigger': 'Accept All',
      'desc':
          'Auto-acepta cambios y ediciones de código propuestos por el agente.',
      'risk': 'medio',
      'riskColor': const Color(0xFFF59E0B),
    },
    {
      'key': 'autoSave',
      'icon': Icons.save_rounded,
      'title': 'Guardar en Disco',
      'trigger': 'Save to Disk',
      'desc': 'Auto-acepta guardar archivos nuevos o modificados al disco.',
      'risk': 'bajo',
      'riskColor': const Color(0xFF4ADE80),
    },
    {
      'key': 'autoRetry',
      'icon': Icons.refresh_rounded,
      'title': 'Reintentos',
      'trigger': 'Retry / Try Again',
      'desc': 'Auto-acepta reintentos cuando una operación falla.',
      'risk': 'bajo',
      'riskColor': const Color(0xFF4ADE80),
    },
    {
      'key': 'autoAllow',
      'icon': Icons.lock_open_rounded,
      'title': 'Permisos del Sistema',
      'trigger': 'Allow Once',
      'desc':
          'Auto-acepta solicitudes de permisos del sistema. Deshabilitado por defecto.',
      'risk': 'alto',
      'riskColor': const Color(0xFFF87171),
    },
  ];

  void _toggleOption(String key) {
    setState(() {
      options[key] = !(options[key] ?? false);
    });
    _pushConfig();
  }

  void _toggleGlobal() {
    setState(() {
      autoAcceptEnabled = !autoAcceptEnabled;
    });
    _pushConfig();
  }

  void _pushConfig() {
    _socket.sendAutoAcceptConfig(autoAcceptEnabled, options);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(title: const Text('Auto-Accept'), centerTitle: true),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Toggle Global
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              gradient: autoAcceptEnabled ? AppColors.senderGradient : null,
              color: autoAcceptEnabled ? null : AppColors.surface,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Row(
              children: [
                Icon(
                  autoAcceptEnabled ? Icons.bolt_rounded : Icons.bolt_outlined,
                  color: Colors.white,
                  size: 32,
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        autoAcceptEnabled
                            ? 'Turbo Accept: ON'
                            : 'Turbo Accept: OFF',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Text(
                        autoAcceptEnabled
                            ? 'Los diálogos se auto-aceptan silenciosamente'
                            : 'Toca para activar la auto-aceptación',
                        style: TextStyle(
                          color: Colors.white.withOpacity(0.7),
                          fontSize: 13,
                        ),
                      ),
                    ],
                  ),
                ),
                Switch(
                  value: autoAcceptEnabled,
                  onChanged: (_) => _toggleGlobal(),
                  activeColor: const Color(0xFF4ADE80),
                ),
              ],
            ),
          ),

          const SizedBox(height: 24),

          // Título de sección
          const Text(
            'OPCIONES',
            style: TextStyle(
              color: AppColors.textMuted,
              fontSize: 12,
              fontWeight: FontWeight.bold,
              letterSpacing: 1.0,
            ),
          ),
          const SizedBox(height: 12),

          // Tarjetas de opciones
          ..._optionsMeta.map((opt) {
            final enabled = options[opt['key']] ?? false;
            return _buildOptionCard(opt, enabled);
          }),

          const SizedBox(height: 16),
          // Info box
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppColors.border),
            ),
            child: const Row(
              children: [
                Icon(Icons.info_outline, color: AppColors.textMuted, size: 18),
                SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'El plugin detecta botones de confirmación vía CDP y simula Alt+Enter automáticamente.',
                    style: TextStyle(
                      color: AppColors.textMuted,
                      fontSize: 12,
                      height: 1.5,
                    ),
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 20),

          // ─── Sección Mantenimiento (v1.1.0) ─────────────────────
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: const Color(0xFF1C1210),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: const Color(0xFFF87171).withOpacity(0.2),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  '🔧 Mantenimiento',
                  style: TextStyle(fontWeight: FontWeight.w600, fontSize: 15),
                ),
                const SizedBox(height: 12),
                // Status indicators
                Wrap(
                  spacing: 16,
                  runSpacing: 8,
                  children: [
                    _buildStatusBadge('Parche Shortcut', patchActive),
                    _buildStatusBadge(
                      'CDP',
                      cdpConnected,
                      extra: cdpConnected ? 'Puerto $cdpPort' : null,
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                // Action buttons
                Wrap(
                  spacing: 10,
                  runSpacing: 8,
                  children: [
                    _buildDangerButton('🗑️ Deshacer Parche', () {
                      _socket.unpatch();
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Deshacer parche enviado al agente...'),
                        ),
                      );
                    }),
                    _buildDangerButton('🔌 Desconectar CDP', () {
                      _socket.disconnectCDP();
                      setState(() {
                        cdpConnected = false;
                        cdpPort = null;
                      });
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('CDP desconectado')),
                      );
                    }),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  'El parche agrega --remote-debugging-port a los accesos directos. Se re-aplica automáticamente si Antigravity se actualiza.',
                  style: TextStyle(
                    color: AppColors.textMuted.withOpacity(0.7),
                    fontSize: 11,
                    height: 1.5,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildOptionCard(Map<String, dynamic> opt, bool enabled) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border(
          left: BorderSide(
            color: enabled ? const Color(0xFF4ADE80) : AppColors.border,
            width: 3,
          ),
        ),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => _toggleOption(opt['key']),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(opt['icon'], color: AppColors.textPrimary, size: 22),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          opt['title'],
                          style: const TextStyle(
                            fontWeight: FontWeight.w600,
                            fontSize: 15,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 1,
                          ),
                          decoration: BoxDecoration(
                            color: AppColors.surfaceVariant,
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            opt['trigger'],
                            style: const TextStyle(
                              fontSize: 11,
                              color: AppColors.textMuted,
                              fontFamily: 'monospace',
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  // Toggle
                  Container(
                    width: 44,
                    height: 24,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(12),
                      color: enabled
                          ? const Color(0xFF4ADE80)
                          : AppColors.border,
                    ),
                    child: AnimatedAlign(
                      duration: const Duration(milliseconds: 200),
                      alignment: enabled
                          ? Alignment.centerRight
                          : Alignment.centerLeft,
                      child: Container(
                        width: 18,
                        height: 18,
                        margin: const EdgeInsets.symmetric(horizontal: 3),
                        decoration: const BoxDecoration(
                          color: Colors.white,
                          shape: BoxShape.circle,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                opt['desc'],
                style: const TextStyle(
                  color: AppColors.textMuted,
                  fontSize: 13,
                  height: 1.4,
                ),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: (opt['riskColor'] as Color).withOpacity(0.15),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      'Riesgo: ${opt['risk']}',
                      style: TextStyle(
                        color: opt['riskColor'],
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: enabled
                          ? const Color(0xFF4ADE80).withOpacity(0.15)
                          : const Color(0xFFF87171).withOpacity(0.15),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      enabled ? '✓ Activo' : '✗ Inactivo',
                      style: TextStyle(
                        color: enabled
                            ? const Color(0xFF4ADE80)
                            : const Color(0xFFF87171),
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStatusBadge(String label, bool active, {String? extra}) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          '$label: ',
          style: const TextStyle(color: AppColors.textMuted, fontSize: 13),
        ),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
          decoration: BoxDecoration(
            color: (active ? const Color(0xFF4ADE80) : const Color(0xFFF87171))
                .withOpacity(0.15),
            borderRadius: BorderRadius.circular(20),
          ),
          child: Text(
            active ? (extra != null ? '✅ $extra' : '✅ Activo') : '❌ Inactivo',
            style: TextStyle(
              color: active ? const Color(0xFF4ADE80) : const Color(0xFFF87171),
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildDangerButton(String label, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: const Color(0xFFF87171).withOpacity(0.1),
          border: Border.all(color: const Color(0xFFF87171).withOpacity(0.25)),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Text(
          label,
          style: const TextStyle(
            color: Color(0xFFF87171),
            fontSize: 13,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }
}
