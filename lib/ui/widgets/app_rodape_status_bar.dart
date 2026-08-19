import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../data/app_config_repository.dart';
import '../../data/api/lan_api_event_hub.dart';
import '../../data/sync/sync_api_client.dart';
import '../../data/sync/sync_presence_hub.dart';
import '../../domain/modo_terminal_leve.dart';
import '../../services/lan_api_server.dart';
import 'chat/chat_interno_drawer.dart';
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
  bool _modoServidor = false;
  bool _terminalLeve = false;
  bool? _apiOk;


  @override
  void initState() {
    super.initState();
    _atualizarRelogio();
    _relogioTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      _atualizarRelogio();
    });
    SyncPresenceHub.instance.addListener(_onPresencaHub);
    LanApiEventHub.instance.addListener(_onApiHub);
    _terminalLeve = LanApiEventHub.instance.modoTerminal;
    _aplicarHubSeDisponivel();
    _aplicarApiHub();
    unawaited(_iniciarMonitorSync());
  }

  @override
  void dispose() {
    SyncPresenceHub.instance.removeListener(_onPresencaHub);
    LanApiEventHub.instance.removeListener(_onApiHub);
    _relogioTimer?.cancel();
    _presencaTimer?.cancel();
    super.dispose();
  }

  void _onPresencaHub() {
    if (!mounted) return;
    final hub = SyncPresenceHub.instance;
    setState(() {
      _consultandoPresenca = false;
      _estacoesOnline = hub.activeCount;
      _rotulosEstacoes = List<String>.from(hub.labels);
    });
  }

  void _onApiHub() {
    if (!mounted) return;
    if (!_terminalLeve && !LanApiEventHub.instance.modoTerminal) return;
    _aplicarApiHub();
  }

  void _aplicarApiHub() {
    final hub = LanApiEventHub.instance;
    if (!_terminalLeve && !hub.modoTerminal) return;
    final online = hub.modoTerminal ? hub.online : (_apiOk ?? false);
    setState(() {
      _apiOk = online;
      _consultandoPresenca = false;
      if (!online) {
        _estacoesOnline = null;
        _rotulosEstacoes = [];
      } else if (hub.activeCount != null) {
        _estacoesOnline = hub.activeCount;
        _rotulosEstacoes = List<String>.from(hub.labels);
      }
    });
  }

  void _aplicarHubSeDisponivel() {
    final hub = SyncPresenceHub.instance;
    if (!hub.temLeitura) return;
    setState(() {
      _consultandoPresenca = false;
      _estacoesOnline = hub.activeCount;
      _rotulosEstacoes = List<String>.from(hub.labels);
    });
  }

  Future<void> _iniciarMonitorSync() async {
    final config = await _configRepo.carregarEmpresaConfig();
    if (!mounted) return;
    final terminalLeve = modoTerminalLeveAtivo(config);
    final modoServidor = config.redeSincronizacaoAtiva && config.redeModoServidor;
    final ativa = config.redeSincronizacaoAtiva &&
        (config.redeServidorUrl.trim().isNotEmpty || modoServidor);
    setState(() {
      _syncAtiva = ativa;
      _syncUrl = config.redeServidorUrl.trim();
      _syncToken = config.redeSyncToken;
      _terminalLeve = terminalLeve;
      _modoServidor = modoServidor;
    });
    _presencaTimer?.cancel();
    if (!ativa) return;
    if (terminalLeve) {
      _aplicarApiHub();
      unawaited(LanApiEventHub.instance.atualizarPresencaAgora());
      _presencaTimer = Timer.periodic(
        const Duration(seconds: 15),
        (_) {
          _aplicarApiHub();
          unawaited(LanApiEventHub.instance.atualizarPresencaAgora());
        },
      );
      return;
    }
    if (modoServidor) {
      // PC1: conta terminais no WebSocket da API :8788 (nao no hub :8787).
      _aplicarPresencaServidorLocal();
      _presencaTimer = Timer.periodic(
        const Duration(seconds: 30),
        (_) => _aplicarPresencaServidorLocal(),
      );
      return;
    }
    _aplicarHubSeDisponivel();
    await _atualizarPresenca();
    final celular = !kIsWeb && (Platform.isAndroid || Platform.isIOS);
    _presencaTimer = Timer.periodic(
      Duration(seconds: celular ? 30 : 15),
      (_) => unawaited(_atualizarPresenca()),
    );
  }

  /// Presenca local dos terminais leves conectados a [LanApiServer].
  void _aplicarPresencaServidorLocal() {
    if (!mounted) return;
    final hubApi = LanApiServerHub.instance;
    if (!hubApi.ativo) {
      // API ainda nao subiu: tenta hub de sync (celulares) como fallback.
      unawaited(_atualizarPresenca());
      return;
    }
    hubApi.publicarPresencaNoHub();
    final snap = hubApi.presencaSnapshot;
    if (snap == null) return;
    final n = (snap['activeCount'] as num?)?.toInt() ?? 0;
    final raw = snap['stations'];
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
        rotulos.add(lab.isEmpty ? 'Terminal' : lab);
      }
    }
    setState(() {
      _consultandoPresenca = false;
      _estacoesOnline = n;
      _rotulosEstacoes = rotulos;
    });
  }

  Future<void> _atualizarPresenca() async {
    if (!_syncAtiva || _syncUrl.isEmpty) return;
    if (mounted && _estacoesOnline == null) {
      setState(() => _consultandoPresenca = true);
    }
    final client = SyncApiClient(
      baseUrl: _syncUrl,
      syncToken: _syncToken,
    );
    try {
      final map = await client.obterPresenca();
      if (!mounted) return;
      if (map == null) {
        SyncPresenceHub.instance.marcarIndisponivel();
        setState(() {
          _consultandoPresenca = false;
          _estacoesOnline = null;
          _rotulosEstacoes = [];
        });
        return;
      }
      SyncPresenceHub.instance.aplicarMap(map);
      // Hub listener ja atualiza; reforca caso o valor seja identico.
      _aplicarHubSeDisponivel();
      if (mounted) setState(() => _consultandoPresenca = false);
    } catch (_) {
      if (!mounted) return;
      SyncPresenceHub.instance.marcarIndisponivel();
      setState(() {
        _consultandoPresenca = false;
        _estacoesOnline = null;
        _rotulosEstacoes = [];
      });
    }
  }

  String get _syncTooltip {
    if (_terminalLeve) {
      if (_apiOk != true) {
        return 'Terminal: API do servidor indisponivel. '
            'Abra o app no PC servidor (modo servidor).';
      }
      if (_rotulosEstacoes.isEmpty) {
        return _estacoesOnline == null
            ? 'Terminal leve conectado a API do PC servidor (porta 8788).'
            : 'Terminal · ${_estacoesOnline!} conectado(s) na API (8788)';
      }
      return '${_rotulosEstacoes.length} conectado(s) na API:\n'
          '${_rotulosEstacoes.map((l) => '• $l').join('\n')}';
    }
    if (_modoServidor) {
      if (_rotulosEstacoes.isEmpty) {
        return _estacoesOnline == null
            ? 'API de terminais'
            : 'Servidor · ${_estacoesOnline!} conectado(s) na API (8788)';
      }
      return '${_rotulosEstacoes.length} conectado(s) na API:\n'
          '${_rotulosEstacoes.map((l) => '• $l').join('\n')}';
    }
    final offline = _estacoesOnline == null && !_consultandoPresenca;
    if (offline) {
      return 'Servidor local nao encontrado. '
          'Verifique se o PC servidor esta ligado, o IP nao mudou '
          'e Configuracoes > Rede > Testar conexao.';
    }
    if (_rotulosEstacoes.isEmpty) {
      return _estacoesOnline == null
          ? 'Sync'
          : 'Sync · ${_estacoesOnline!} online';
    }
    return '${_rotulosEstacoes.length} estacao(oes):\n'
        '${_rotulosEstacoes.map((l) => '• $l').join('\n')}';
  }

  Widget _buildIndicadorSync(ThemeData tema) {
    final onVar = tema.colorScheme.onSurfaceVariant;
    if (_terminalLeve) {
      final offline = _apiOk != true;
      final cor = offline ? tema.colorScheme.error : Colors.green.shade700;
      final texto = _apiOk == null
          ? 'Terminal · …'
          : offline
              ? 'Terminal · servidor offline'
              : _estacoesOnline == null
                  ? 'Terminal · …'
                  : 'Terminal · ${_estacoesOnline!} conectado(s)';
      return Tooltip(
        message: _syncTooltip,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 7,
              height: 7,
              decoration: BoxDecoration(color: cor, shape: BoxShape.circle),
            ),
            const SizedBox(width: 6),
            Text(texto, style: tema.textTheme.labelSmall?.copyWith(color: onVar)),
          ],
        ),
      );
    }
    if (_modoServidor) {
      final offline = _estacoesOnline == null && !_consultandoPresenca;
      final cor = offline
          ? tema.colorScheme.error
          : Colors.green.shade700;
      final texto = _consultandoPresenca && _estacoesOnline == null
          ? 'Servidor · …'
          : offline
              ? 'Servidor · API offline'
              : 'Servidor · ${_estacoesOnline!} conectado(s)';
      return Tooltip(
        message: _syncTooltip,
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
    final offline = _estacoesOnline == null && !_consultandoPresenca;
    final cor = offline
        ? tema.colorScheme.error
        : Colors.green.shade700;
    final texto = _consultandoPresenca && _estacoesOnline == null
        ? 'Sync · …'
        : offline
            ? 'Sync · servidor nao encontrado'
            : 'Sync · ${_estacoesOnline!} online';

    return Tooltip(
      message: _syncTooltip,
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

  /// Indicador compacto no celular: ponto + contagem (ex.: "2 conectado(s)").
  Widget _buildIndicadorSyncCompacto(ThemeData tema) {
    final onVar = tema.colorScheme.onSurfaceVariant;
    final offline = _terminalLeve
        ? _apiOk != true
        : (_estacoesOnline == null && !_consultandoPresenca);
    final cor = offline
        ? tema.colorScheme.error
        : Colors.green.shade700;
    final texto = _consultandoPresenca && _estacoesOnline == null
        ? '…'
        : offline
            ? 'off'
            : _estacoesOnline == null
                ? '…'
                : '${_estacoesOnline!} conectado(s)';

    return Tooltip(
      message: _syncTooltip,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(
              color: _consultandoPresenca && _estacoesOnline == null
                  ? onVar
                  : cor,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 5),
          Text(
            texto,
            style: tema.textTheme.labelSmall?.copyWith(
              color: offline ? tema.colorScheme.error : onVar,
              fontWeight: FontWeight.w700,
              fontSize: 11,
            ),
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
    final celular = !kIsWeb && (Platform.isAndroid || Platform.isIOS);
    final altura = celular ? 52.0 : 32.0;

    return Material(
      color: tema.colorScheme.surfaceContainerHighest.withValues(
        alpha: tema.brightness == Brightness.dark ? 0.55 : 0.75,
      ),
      child: SafeArea(
        top: false,
        minimum: EdgeInsets.zero,
        child: SizedBox(
          height: altura,
          child: Padding(
            padding: EdgeInsets.symmetric(horizontal: celular ? 4 : 10),
            child: Row(
              children: [
                const SeletorMenuModoApp(compacto: true),
                const SeletorTemaApp(compacto: true),
                const ChatInternoTopBarButton(),
                if (_syncAtiva && !celular) ...[
                  const SizedBox(width: 8),
                  Flexible(child: _buildIndicadorSync(tema)),
                ],
                if (_syncAtiva && celular) ...[
                  const SizedBox(width: 6),
                  Flexible(
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: _buildIndicadorSyncCompacto(tema),
                    ),
                  ),
                ],
                const Spacer(),
                if (login != null && login.isNotEmpty && !celular)
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
                if (login != null && login.isNotEmpty && !celular)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 10),
                    child: Text(
                      '|',
                      style: tema.textTheme.labelSmall?.copyWith(
                        color: tema.colorScheme.outline,
                      ),
                    ),
                  ),
                if (!celular)
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
