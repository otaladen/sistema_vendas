import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../data/app_config_repository.dart';
import '../../data/sync/sync_api_client.dart';
import 'seletor_menu_modo_app.dart';
import 'seletor_tema_app.dart';

/// Barra inferior com Temas, usuario e data/hora (referencia ao ERP legado).
class AppRodapeStatusBar extends StatefulWidget {
  const AppRodapeStatusBar({
    super.key,
    this.usuarioLogin,
    this.usuarioNome,
  });

  final String? usuarioLogin;
  final String? usuarioNome;

  @override
  State<AppRodapeStatusBar> createState() => _AppRodapeStatusBarState();
}

class _AppRodapeStatusBarState extends State<AppRodapeStatusBar> {
  static final _dataHora = DateFormat('dd/MM/yyyy · HH:mm', 'pt_BR');
  final AppConfigRepository _configRepo = AppConfigRepository();

  String _agora = '';
  Timer? _relogioTimer;
  Timer? _presencaTimer;

  bool _syncAtiva = false;
  String _syncUrl = '';
  String _syncToken = '';
  int? _estacoesOnline;
  List<String> _rotulosEstacoes = [];
  bool _consultandoPresenca = false;

  @override
  void initState() {
    super.initState();
    _atualizarRelogio();
    _relogioTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      _atualizarRelogio();
    });
    unawaited(_iniciarMonitorSync());
  }

  @override
  void dispose() {
    _relogioTimer?.cancel();
    _presencaTimer?.cancel();
    super.dispose();
  }

  Future<void> _iniciarMonitorSync() async {
    final config = await _configRepo.carregarEmpresaConfig();
    if (!mounted) return;
    final ativa = config.redeSincronizacaoAtiva &&
        config.redeServidorUrl.trim().isNotEmpty;
    setState(() {
      _syncAtiva = ativa;
      _syncUrl = config.redeServidorUrl.trim();
      _syncToken = config.redeSyncToken;
    });
    _presencaTimer?.cancel();
    if (!ativa) return;
    await _atualizarPresenca();
    _presencaTimer = Timer.periodic(
      const Duration(seconds: 45),
      (_) => unawaited(_atualizarPresenca()),
    );
  }

  Future<void> _atualizarPresenca() async {
    if (!_syncAtiva || _syncUrl.isEmpty) return;
    if (mounted) setState(() => _consultandoPresenca = true);
    final client = SyncApiClient(
      baseUrl: _syncUrl,
      syncToken: _syncToken,
    );
    try {
      final map = await client.obterPresenca();
      if (!mounted) return;
      if (map == null) {
        setState(() {
          _consultandoPresenca = false;
          _estacoesOnline = null;
          _rotulosEstacoes = [];
        });
        return;
      }
      final n = (map['activeCount'] as num?)?.toInt() ?? 0;
      final raw = map['stations'];
      final rotulos = <String>[];
      if (raw is List) {
        for (final e in raw) {
          final m = e is Map<String, dynamic>
              ? e
              : e is Map
                  ? Map<String, dynamic>.from(e)
                  : null;
          if (m == null) continue;
          final lab = (m['label'] ?? '').toString().trim();
          rotulos.add(lab.isEmpty ? 'PC' : lab);
        }
      }
      setState(() {
        _consultandoPresenca = false;
        _estacoesOnline = n;
        _rotulosEstacoes = rotulos;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _consultandoPresenca = false;
        _estacoesOnline = null;
        _rotulosEstacoes = [];
      });
    }
  }

  Widget _buildIndicadorSync(ThemeData tema) {
    final onVar = tema.colorScheme.onSurfaceVariant;
    final offline = _estacoesOnline == null && !_consultandoPresenca;
    final cor = offline
        ? tema.colorScheme.error
        : Colors.green.shade700;
    final texto = _consultandoPresenca && _estacoesOnline == null
        ? 'Sync · …'
        : offline
            ? 'Sync · offline'
            : 'Sync · ${_estacoesOnline!} online';

    final tooltip = offline
        ? 'Servidor de sincronizacao indisponivel'
        : _rotulosEstacoes.isEmpty
            ? texto
            : '${_rotulosEstacoes.length} estacao(oes):\n${_rotulosEstacoes.map((l) => '• $l').join('\n')}';

    return Tooltip(
      message: tooltip,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 7,
            height: 7,
            decoration: BoxDecoration(
              color: _consultandoPresenca && _estacoesOnline == null
                  ? onVar
                  : cor,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 6),
          Text(
            texto,
            style: tema.textTheme.labelSmall?.copyWith(color: onVar),
          ),
        ],
      ),
    );
  }

  void _atualizarRelogio() {
    final novo = _dataHora.format(DateTime.now());
    if (!mounted || novo == _agora) return;
    setState(() => _agora = novo);
  }

  @override
  Widget build(BuildContext context) {
    final tema = Theme.of(context);
    final login = widget.usuarioLogin?.trim();
    final nome = widget.usuarioNome?.trim();

    return Material(
      color: tema.colorScheme.surfaceContainerHighest.withValues(
        alpha: tema.brightness == Brightness.dark ? 0.55 : 0.75,
      ),
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: 32,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10),
            child: Row(
              children: [
                const SeletorMenuModoApp(compacto: true),
                const SizedBox(width: 2),
                const SeletorTemaApp(compacto: true),
                if (_syncAtiva) ...[
                  const SizedBox(width: 12),
                  _buildIndicadorSync(tema),
                ],
                const Spacer(),
                if (login != null && login.isNotEmpty)
                  Flexible(
                    child: Text(
                      nome != null && nome.isNotEmpty ? '$nome ($login)' : login,
                      style: tema.textTheme.labelSmall?.copyWith(
                        color: tema.colorScheme.onSurfaceVariant,
                      ),
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.end,
                    ),
                  ),
                if (login != null && login.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 10),
                    child: Text(
                      '|',
                      style: tema.textTheme.labelSmall?.copyWith(
                        color: tema.colorScheme.outline,
                      ),
                    ),
                  ),
                Text(
                  _agora,
                  style: tema.textTheme.labelSmall?.copyWith(
                    color: tema.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
