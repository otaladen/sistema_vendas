import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../services/configuracoes_service.dart';
import '../../data/sync/lan_sync_scheduler.dart';
import '../../data/sync/sync_api_client.dart';
import '../../data/sync/sync_conflict_log.dart';
import '../../data/sync/sync_conflict_resolver.dart';
import '../../data/sync/sync_log.dart';
import '../../data/sync/sync_priority.dart';
import '../../data/sync/sync_teste_conexao.dart';
import '../../domain/sync_rede_ajuda.dart';
import '../../domain/sync_token_util.dart';
import '../../services/lan_api_server.dart';
import '../../services/lan_rede_helper.dart';
import '../../services/lan_servidor_bootstrap.dart';
import '../../services/windows_app_startup_helper.dart';
import '../../data/api/lan_api_url.dart';
import '../../ui/shell/main_menu_deps.dart';

/// Assistente de rede local: servidor neste PC ou cliente apontando para outro.
class RedeSincronizacaoCard extends StatefulWidget {
  const RedeSincronizacaoCard({
    super.key,
    required this.configuracoesService,
    this.lanSyncScheduler,
    this.forcarModoCliente = false,
  });

  final ConfiguracoesService configuracoesService;
  final LanSyncScheduler? lanSyncScheduler;

  /// Terminal leve: trava papel cliente (sem banco local neste PC).
  final bool forcarModoCliente;

  @override
  State<RedeSincronizacaoCard> createState() => _RedeSincronizacaoCardState();
}

class _RedeSincronizacaoCardState extends State<RedeSincronizacaoCard> {
  final _urlController = TextEditingController();
  final _tokenController = TextEditingController();

  bool _modoServidor = false;
  bool _syncAtiva = false;
  bool _modoImplantacao = false;
  String? _ipLocal;
  bool _servidorOnline = false;
  bool _carregando = true;
  bool _salvando = false;
  bool _testandoRede = false;
  bool _sincronizando = false;
  bool _enviandoFotos = false;
  bool _tokenVisivel = false;
  bool? _tokenAceitoPeloServidor;
  bool _erroAjudaExpandido = false;
  bool _iniciarComWindows = false;

  int? _estacoesAtivas;
  List<Map<String, dynamic>> _estacoesLista = [];
  String _presencaErro = '';
  bool _carregandoPresenca = false;

  /// API de terminais (:8788) ativa neste PC (Windows servidor).
  bool _apiAtiva = false;

  @override
  void initState() {
    super.initState();
    unawaited(SyncConflictLog.limparAvisosDeAceiteRemoto());
    _carregar();
  }

  @override
  void dispose() {
    _urlController.dispose();
    _tokenController.dispose();
    super.dispose();
  }

  String get _tokenAtual => _tokenController.text.trim();

  bool get _tokenPreenchido => _tokenAtual.isNotEmpty;

  Future<void> _carregar() async {
    setState(() => _carregando = true);
    final config = await widget.configuracoesService.carregarEfetiva();
    final modoImplantacao =
        await widget.configuracoesService.repository.carregarModoImplantacaoLocal();
    final ip = await LanRedeHelper.obterIpv4Local();
    var url = config.redeServidorUrl.trim();
    if (config.redeModoServidor && ip != null && url.isEmpty) {
      url = LanRedeHelper.montarUrlServidor(ip);
    }
    final online = await LanRedeHelper.apiRespondendo(
      baseUrl: url,
      syncToken: config.redeSyncToken,
    );
    final iniciarWin = Platform.isWindows
        ? await WindowsAppStartupHelper.estaAtivo()
        : false;

    if (!mounted) return;
    setState(() {
      _modoServidor = widget.forcarModoCliente ? false : config.redeModoServidor;
      _syncAtiva = config.redeSincronizacaoAtiva;
      _modoImplantacao = modoImplantacao;
      _ipLocal = ip;
      _urlController.text = url;
      _tokenController.text = config.redeSyncToken;
      _servidorOnline = online;
      _iniciarComWindows = iniciarWin;
      _carregando = false;
    });
  }

  Future<void> _copiarToken() async {
    if (_tokenAtual.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Nenhum token para copiar.')),
      );
      return;
    }
    await Clipboard.setData(ClipboardData(text: _tokenAtual));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Token copiado para a area de transferencia.')),
    );
  }

  Future<bool> _confirmarSubstituirToken() async {
    if (_tokenAtual.isEmpty) return true;
    if (!mounted) return false;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Gerar novo token?'),
        content: const Text(
          'Os outros PCs deixarao de sincronizar ate voce configurar o '
          'mesmo token novo em cada um deles. Deseja continuar?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Gerar novo'),
          ),
        ],
      ),
    );
    return ok == true;
  }

  Future<void> _gerarNovoToken() async {
    if (!await _confirmarSubstituirToken()) return;
    setState(() {
      _tokenController.text = gerarTokenSyncLan();
      _tokenVisivel = true;
      _tokenAceitoPeloServidor = null;
    });
  }

  Future<void> _colarEnderecoServidor() async {
    final data = await Clipboard.getData('text/plain');
    final texto = data?.text?.trim() ?? '';
    if (texto.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Nada na area de transferencia para colar.')),
      );
      return;
    }
    setState(() => _urlController.text = texto);
  }

  void _aoMudarModo(bool servidor) {
    if (widget.forcarModoCliente && servidor) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Este PC e terminal leve: o banco fica so no PC servidor.',
          ),
        ),
      );
      return;
    }
    setState(() {
      _modoServidor = servidor;
      _tokenAceitoPeloServidor = null;
      if (servidor && _ipLocal != null) {
        _urlController.text = LanRedeHelper.montarUrlServidor(_ipLocal!);
      }
    });
    _atualizarStatusServidor();
  }

  void _preencherUrlServidorLocal() {
    final ip = _ipLocal;
    if (ip == null || ip.isEmpty) return;
    _urlController.text = LanRedeHelper.montarUrlServidor(ip);
  }

  String get _enderecoApiTerminais {
    final ip = _ipLocal?.trim();
    if (ip == null || ip.isEmpty) {
      return '—:${LanApiUrl.portaPadrao}';
    }
    return '$ip:${LanApiUrl.portaPadrao}';
  }

  Future<void> _atualizarStatusServidor() async {
    final url = _urlController.text.trim();
    final apiOnline = await LanRedeHelper.apiRespondendo(
      baseUrl: url.isNotEmpty ? url : null,
      syncToken: _tokenAtual,
    );
    if (mounted) {
      setState(() {
        _servidorOnline = apiOnline;
        _apiAtiva = _ehWindows && LanApiServerHub.instance.ativo;
      });
    }
  }

  void _copiarEnderecoApiTerminais() {
    final ip = _ipLocal;
    if (ip == null || ip.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('IP local nao detectado. Atualize o IP.')),
      );
      return;
    }
    final txt = '$ip:${LanApiUrl.portaPadrao}';
    Clipboard.setData(ClipboardData(text: txt));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Copiado para Terminais Windows (API): $txt'),
      ),
    );
  }

  Future<void> _alternarModoImplantacao(bool ativo) async {
    setState(() => _modoImplantacao = ativo);
    await widget.configuracoesService.repository.salvarModoImplantacaoLocal(ativo);
    await widget.lanSyncScheduler?.iniciar();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          ativo
              ? 'Modo implantacao ativo: sync menos agressiva neste PC (60s / 3s).'
              : 'Modo implantacao desativado neste PC.',
        ),
      ),
    );
  }

  Future<void> _salvar({bool iniciarServidorSeModoServidor = false}) async {
    setState(() => _salvando = true);
    try {
      final modoServidor =
          widget.forcarModoCliente ? false : _modoServidor;
      if (modoServidor) {
        _preencherUrlServidorLocal();
      }
      final atual = await widget.configuracoesService.carregarEfetiva();
      var token = _tokenAtual;
      var tokenGeradoAgora = false;
      if (_syncAtiva && token.isEmpty) {
        token = gerarTokenSyncLan();
        _tokenController.text = token;
        _tokenVisivel = true;
        tokenGeradoAgora = true;
      }
      final config = atual.copyWith(
        redeSincronizacaoAtiva: _syncAtiva,
        redeModoServidor: modoServidor,
        redeServidorUrl: _urlController.text.trim(),
        redeSyncToken: token,
      );
      await widget.configuracoesService.salvarEfetiva(config);

      if (modoServidor && Platform.isWindows) {
        // Terminais devem funcionar so de ligar este PC (sem abrir a UI).
        final errStartup = await WindowsAppStartupHelper.definir(true);
        if (errStartup != null && mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(errStartup)),
          );
        } else if (mounted) {
          setState(() => _iniciarComWindows = true);
        }
      } else if (!modoServidor && Platform.isWindows) {
        await WindowsAppStartupHelper.definir(false);
        if (mounted) setState(() => _iniciarComWindows = false);
      }

      if (modoServidor && iniciarServidorSeModoServidor && Platform.isWindows) {
        if (!mounted) return;
        final ob = MainMenuDeps.maybeOf(context)?.objectBox;
        if (ob != null) {
          await LanServidorBootstrap.garantirAtivo(
            objectBox: ob,
            configRepository: widget.configuracoesService.repository,
          );
        }
        await widget.lanSyncScheduler?.iniciar();
      } else if (!_modoServidor && Platform.isWindows) {
        // Windows cliente = Terminal Leve no proximo boot (API direta).
        // Nao inicia pull/push ObjectBox aqui — isso travava o PC.
        await widget.lanSyncScheduler?.parar();
      } else {
        await widget.lanSyncScheduler?.iniciar();
      }
      await _atualizarStatusServidor();
      if (!mounted) return;
      if (tokenGeradoAgora) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Token gerado automaticamente. Copie e configure nos outros PCs.',
            ),
            duration: Duration(seconds: 5),
          ),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Configuracao de rede salva.')),
        );
      }
    } finally {
      if (mounted) setState(() => _salvando = false);
    }
  }

  Future<void> _configurarRedeCompleta() async {
    if (_modoServidor) {
      final ip = _ipLocal ?? await LanRedeHelper.obterIpv4Local();
      if (ip == null) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Nao foi possivel detectar o IP deste PC na rede. '
              'Verifique Wi-Fi/cabo.',
            ),
          ),
        );
        return;
      }
      setState(() => _ipLocal = ip);
      _urlController.text = LanRedeHelper.montarUrlServidor(ip);
    } else if (_urlController.text.trim().isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Informe o endereco do servidor antes de conectar.'),
        ),
      );
      return;
    }

    setState(() => _syncAtiva = true);
    await _salvar(iniciarServidorSeModoServidor: _modoServidor);
    if (!mounted) return;

    await _testarConexao(silencioso: false);
    if (!mounted) return;

    final testeOk = _servidorOnline && (_tokenAceitoPeloServidor ?? true);
    if (!testeOk) return;

    if (!mounted) return;
    if (_modoServidor) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Servidor ativo. Este PC guarda o banco e atende os terminais. '
            'O inicio automatico com o Windows foi ativado: apos reiniciar, '
            'os terminais funcionam so de ligar este PC (sem abrir o programa).',
          ),
          duration: Duration(seconds: 7),
        ),
      );
      return;
    }

    // Cliente Windows/Android/iOS: Terminal Leve no proximo boot (API :8788).
    if (!kIsWeb &&
        (Platform.isWindows || Platform.isAndroid || Platform.isIOS)) {
      await _avisarReinicioTerminalLeve();
      return;
    }

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text(
          'Conectado ao servidor. Baixando/enviando dados em segundo plano… '
          'Pode sair desta tela; o rodape mostrara quando estiver online.',
        ),
        duration: Duration(seconds: 6),
      ),
    );
    unawaited(_sincronizarAgora(avisarConclusao: true));
  }

  Future<void> _avisarReinicioTerminalLeve() async {
    if (!mounted) return;
    final ehMobile = Platform.isAndroid || Platform.isIOS;
    final fechar = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Cliente configurado'),
        content: Text(
          ehMobile
              ? 'Neste celular o Terminal Leve le e grava direto na API do '
                  'PC servidor (porta ${LanApiUrl.portaPadrao}), sem banco local.\n\n'
                  'Se o servidor cair, o app para.\n\n'
                  'Feche e abra o app de novo para ativar esse modo.'
              : 'Neste PC Windows o Terminal Leve le e grava direto na API do '
                  'servidor.\n\n'
                  'Feche e abra o sistema de novo para ativar esse modo.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Depois'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(
              ehMobile ? 'Fechar o app agora' : 'Fechar o sistema agora',
            ),
          ),
        ],
      ),
    );
    if (fechar == true && !kIsWeb) {
      if (Platform.isWindows) {
        exit(0);
      } else if (Platform.isAndroid || Platform.isIOS) {
        await SystemNavigator.pop();
      }
    }
  }

  Future<void> _testarConexao({bool silencioso = false}) async {
    setState(() => _testandoRede = true);
    try {
      final resultado = await testarConexaoSyncLan(
        baseUrl: _urlController.text,
        syncToken: _tokenAtual,
      ).timeout(
        const Duration(seconds: 8),
        onTimeout: () => const SyncTesteResultado(
          servidorAlcancavel: false,
          servicoSyncAtivo: false,
          tokenValido: false,
          mensagem: 'Tempo esgotado ao testar o servidor (8s). '
              'Confira IP, Wi-Fi e se o sync esta ligado no PC.',
        ),
      );
      if (!mounted) return;
      setState(() {
        _servidorOnline =
            resultado.servidorAlcancavel && resultado.servicoSyncAtivo;
        _tokenAceitoPeloServidor = resultado.tokenValido;
      });
      if (!silencioso && resultado.mensagem != null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(resultado.mensagem!),
            backgroundColor: resultado.sucesso ? null : Colors.red.shade700,
          ),
        );
      }
    } catch (e) {
      if (!silencioso && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erro ao testar: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _testandoRede = false);
    }
  }

  Future<void> _liberarFirewall() async {
    final errApi = await LanRedeHelper.tentarLiberarFirewall();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          errApi ??
              'Regra de firewall criada para a porta '
                  '${LanApiUrl.portaPadrao} (API dos terminais), '
                  'se permitido pelo Windows.',
        ),
      ),
    );
  }

  Future<void> _alternarIniciarComWindows(bool value) async {
    final err = await WindowsAppStartupHelper.definir(value);
    if (!mounted) return;
    if (err != null) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(err)));
      return;
    }
    setState(() => _iniciarComWindows = value);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          value
              ? 'Servidor em segundo plano ativado. Apos reiniciar o Windows, '
                  'os terminais funcionam so de ligar este PC.'
              : 'Inicio automatico com o Windows desativado.',
        ),
      ),
    );
  }

  Future<void> _sincronizarAgora({bool avisarConclusao = true}) async {
    if (_modoServidor) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'No PC servidor nao ha sync de cliente. '
            'Os outros PCs e terminais e que baixam/enviam dados.',
          ),
        ),
      );
      return;
    }
    if (!kIsWeb &&
        (Platform.isWindows || Platform.isAndroid || Platform.isIOS)) {
      if (!mounted) return;
      await _avisarReinicioTerminalLeve();
      return;
    }
    final agendador = widget.lanSyncScheduler;
    if (agendador == null) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Agendador de sync indisponivel.')),
      );
      return;
    }
    if (!_syncAtiva || _urlController.text.trim().isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Ative a sincronizacao, salve o endereco e tente de novo.'),
        ),
      );
      return;
    }
    if (_sincronizando) return;
    setState(() => _sincronizando = true);
    try {
      final erro = await agendador.sincronizarAgora(
        forcar: true,
        modo: SyncModo.completo,
      );
      if (!mounted || !avisarConclusao) return;
      if (erro != null && erro.trim().isNotEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Sync: $erro'), backgroundColor: Colors.red),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Sincronizacao concluida.')),
        );
      }
    } finally {
      if (mounted) setState(() => _sincronizando = false);
    }
  }

  Future<void> _enviarFotosAoServidor() async {
    final agendador = widget.lanSyncScheduler;
    if (agendador == null) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Agendador de sync indisponivel.')),
      );
      return;
    }
    setState(() => _enviandoFotos = true);
    try {
      final r = await agendador.enviarFotosProdutosAgora();
      if (!mounted) return;
      final msg = (r.detalhe != null && r.detalhe!.trim().isNotEmpty)
          ? r.detalhe!
          : 'Fotos: ${r.enviados} enviada(s), ${r.ignorados} ja ok, '
              '${r.falhas} falha(s).';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(msg),
          duration: const Duration(seconds: 6),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Falha ao enviar fotos: $e'),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      if (mounted) setState(() => _enviandoFotos = false);
    }
  }

  Future<void> _atualizarPresenca() async {
    if (_modoServidor && LanApiServerHub.instance.ativo) {
      setState(() {
        _carregandoPresenca = true;
        _presencaErro = '';
      });
      LanApiServerHub.instance.publicarPresencaNoHub();
      final snap = LanApiServerHub.instance.presencaSnapshot;
      if (!mounted) return;
      if (snap == null) {
        setState(() {
          _carregandoPresenca = false;
          _presencaErro = 'API de terminais nao respondeu.';
        });
        return;
      }
      final n = (snap['activeCount'] as num?)?.toInt();
      final raw = snap['stations'];
      final lista = <Map<String, dynamic>>[];
      if (raw is List) {
        for (final e in raw) {
          if (e is Map<String, dynamic>) {
            lista.add(e);
          } else if (e is Map) {
            lista.add(Map<String, dynamic>.from(e));
          }
        }
      }
      setState(() {
        _carregandoPresenca = false;
        _estacoesAtivas = n;
        _estacoesLista = lista;
      });
      return;
    }

    final uri = _urlController.text.trim();
    if (uri.isEmpty) {
      setState(() {
        _estacoesAtivas = null;
        _estacoesLista = [];
        _presencaErro = 'Salve o endereco do servidor antes.';
      });
      return;
    }
    setState(() {
      _carregandoPresenca = true;
      _presencaErro = '';
    });
    final client = SyncApiClient(
      baseUrl: uri,
      syncToken: _tokenAtual,
    );
    try {
      final map = await client.obterPresenca();
      if (!mounted) return;
      if (map == null) {
        setState(() {
          _carregandoPresenca = false;
          _presencaErro = 'Servidor nao respondeu. Inicie o servidor neste PC.';
        });
        return;
      }
      final n = (map['activeCount'] as num?)?.toInt();
      final raw = map['stations'];
      final lista = <Map<String, dynamic>>[];
      if (raw is List) {
        for (final e in raw) {
          if (e is Map<String, dynamic>) {
            lista.add(e);
          } else if (e is Map) {
            lista.add(Map<String, dynamic>.from(e));
          }
        }
      }
      setState(() {
        _carregandoPresenca = false;
        _estacoesAtivas = n;
        _estacoesLista = lista;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _carregandoPresenca = false;
        _presencaErro = 'Erro: $e';
      });
    }
  }

  bool get _ehWindows => !kIsWeb && Platform.isWindows;

  /// Cliente Windows = Terminal Leve (API). Sem sync ObjectBox legado.
  bool get _clienteWindows => _ehWindows && !_modoServidor;

  /// Celular / outros: ainda usam pull/push do hub.
  bool get _usaSyncCatalogo => !_ehWindows && !_modoServidor;

  bool get _servidorRedePronto {
    if (!_syncAtiva) return false;
    if (_modoServidor) {
      return _ehWindows ? (_apiAtiva || _servidorOnline) : _servidorOnline;
    }
    return _servidorOnline || _apiAtiva;
  }

  Widget _cardOperador({required ThemeData tema, required Widget child}) {
    return Card(
      elevation: 0,
      color: tema.colorScheme.surfaceContainerLow,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(
          color: tema.colorScheme.outlineVariant.withValues(alpha: 0.55),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: child,
      ),
    );
  }

  Widget _badgeStatus({
    required String rotulo,
    required Color cor,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: cor.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        rotulo,
        style: TextStyle(
          color: cor,
          fontWeight: FontWeight.w700,
          fontSize: 12.5,
        ),
      ),
    );
  }

  Widget _buildStatusCard(ThemeData tema) {
    final onVar = tema.colorScheme.onSurfaceVariant;
    final erro = tema.colorScheme.error;

    late final IconData icone;
    late final String titulo;
    late final String badge;
    late final Color corBadge;
    late final String subtitulo;

    if (!_syncAtiva) {
      icone = Icons.wifi_tethering_error_rounded;
      titulo = 'Rede da loja';
      badge = 'Rede desligada';
      corBadge = erro;
      subtitulo = 'Ative a rede para conectar terminais e celulares.';
    } else if (_modoServidor) {
      icone = Icons.dns_rounded;
      titulo = 'Servidor da loja';
      if (_servidorRedePronto) {
        badge = 'Servidor Ativo';
        corBadge = Colors.green.shade700;
        subtitulo = _estacoesAtivas != null
            ? '$_estacoesAtivas terminais online'
            : 'Pronto para receber terminais.';
      } else {
        badge = 'Aguardando conexão';
        corBadge = Colors.orange.shade800;
        subtitulo = 'Ative a rede abaixo para liberar o servidor.';
      }
    } else if (_servidorRedePronto) {
      icone = Icons.cloud_done_rounded;
      titulo = _clienteWindows ? 'Terminal da loja' : 'Cliente da rede';
      badge = 'Conectado à Rede';
      corBadge = Colors.green.shade700;
      subtitulo = _clienteWindows
          ? 'Conectado ao servidor da loja.'
          : 'Sincronizando com o servidor da loja.';
    } else {
      icone = Icons.wifi_tethering;
      titulo = _clienteWindows ? 'Terminal da loja' : 'Cliente da rede';
      badge = 'Aguardando conexão';
      corBadge = Colors.orange.shade800;
      subtitulo = 'Informe o endereço do servidor e conecte.';
    }

    return _cardOperador(
      tema: tema,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icone, size: 36, color: tema.colorScheme.primary),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  titulo,
                  style: tema.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 8),
                _badgeStatus(rotulo: badge, cor: corBadge),
                const SizedBox(height: 8),
                Text(
                  subtitulo,
                  style: tema.textTheme.bodySmall?.copyWith(color: onVar),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildConnectionCard(ThemeData tema) {
    final onVar = tema.colorScheme.onSurfaceVariant;
    final ocupado = _salvando || _testandoRede || _sincronizando;

    if (_modoServidor) {
      final precisaAtivar = !_syncAtiva || !_servidorRedePronto;
      return _cardOperador(
        tema: tema,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Endereço do servidor',
              style: tema.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: Text(
                    _ipLocal == null ? 'IP não detectado' : _enderecoApiTerminais,
                    style: tema.textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.w800,
                      letterSpacing: -0.3,
                    ),
                  ),
                ),
                IconButton(
                  tooltip: 'Atualizar IP',
                  onPressed: () async {
                    final ip = await LanRedeHelper.obterIpv4Local();
                    setState(() => _ipLocal = ip);
                    if (ip != null) _preencherUrlServidorLocal();
                    await _atualizarStatusServidor();
                  },
                  icon: const Icon(Icons.refresh_rounded),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              'Use este endereço nos terminais da loja.',
              style: tema.textTheme.bodySmall?.copyWith(color: onVar),
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: _ipLocal == null ? null : _copiarEnderecoApiTerminais,
              icon: const Icon(Icons.copy_rounded),
              label: const Text('Copiar Endereço para os Terminais'),
            ),
            if (precisaAtivar) ...[
              const SizedBox(height: 10),
              FilledButton.tonalIcon(
                onPressed: ocupado ? null : _configurarRedeCompleta,
                icon: ocupado
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.power_settings_new_rounded),
                label: Text(
                  ocupado ? 'Ativando...' : 'Ativar Rede da Loja',
                ),
              ),
            ],
          ],
        ),
      );
    }

    return _cardOperador(
      tema: tema,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Conectar ao servidor',
            style: tema.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _urlController,
            decoration: InputDecoration(
              labelText: 'Endereço do servidor',
              hintText: 'Ex.: 192.168.0.15:${LanApiUrl.portaPadrao}',
              border: const OutlineInputBorder(),
              isDense: true,
              suffixIcon: IconButton(
                tooltip: 'Colar',
                icon: const Icon(Icons.content_paste_outlined),
                onPressed: _colarEnderecoServidor,
              ),
            ),
            keyboardType: TextInputType.url,
            autocorrect: false,
            onChanged: (_) => setState(() {
              _servidorOnline = false;
              _tokenAceitoPeloServidor = null;
            }),
          ),
          const SizedBox(height: 12),
          _buildCampoToken(),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: ocupado ? null : _configurarRedeCompleta,
            icon: ocupado
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : const Icon(Icons.link_rounded),
            label: Text(
              ocupado ? 'Conectando...' : 'Salvar e Conectar',
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTerminaisConectados(ThemeData tema) {
    final onVar = tema.colorScheme.onSurfaceVariant;
    final erro = tema.colorScheme.error;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Terminais conectados a API',
          style: tema.textTheme.titleSmall?.copyWith(
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          'Quem esta no WebSocket :${LanApiUrl.portaPadrao} '
          '(terminais Windows e celular).',
          style: tema.textTheme.bodySmall?.copyWith(color: onVar),
        ),
        const SizedBox(height: 8),
        OutlinedButton.icon(
          onPressed: _carregandoPresenca ? null : _atualizarPresenca,
          icon: _carregandoPresenca
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.devices_outlined),
          label: Text(
            _carregandoPresenca ? 'Consultando...' : 'Atualizar terminais',
          ),
        ),
        if (_presencaErro.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
              _presencaErro,
              style: TextStyle(color: erro, fontSize: 13),
            ),
          ),
        if (_estacoesAtivas != null && _presencaErro.isEmpty) ...[
          const SizedBox(height: 8),
          Text('Total ativo: $_estacoesAtivas'),
          ..._estacoesLista.map((s) {
            final lab = (s['label'] ?? '').toString();
            return Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text('• ${lab.isEmpty ? "Terminal" : lab}'),
            );
          }),
        ],
      ],
    );
  }

  Widget _buildOpcoesAvancadasRede(ThemeData tema) {
    final onVar = tema.colorScheme.onSurfaceVariant;
    return ExpansionTile(
      tilePadding: EdgeInsets.zero,
      childrenPadding: const EdgeInsets.only(bottom: 8),
      leading: Icon(
        Icons.settings_suggest_outlined,
        color: tema.colorScheme.onSurfaceVariant,
      ),
      title: Text(
        'Opções Avançadas / Suporte',
        style: tema.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
      ),
      subtitle: Text(
        'Papel, token, firewall e diagnóstico',
        style: tema.textTheme.bodySmall?.copyWith(color: onVar),
      ),
      children: [
        if (!widget.forcarModoCliente) ...[
          SegmentedButton<bool>(
            segments: const [
              ButtonSegment(
                value: true,
                label: Text('Servidor neste PC'),
                icon: Icon(Icons.dns_outlined),
              ),
              ButtonSegment(
                value: false,
                label: Text('Cliente (outro PC)'),
                icon: Icon(Icons.devices_outlined),
              ),
            ],
            selected: {_modoServidor},
            onSelectionChanged: (s) => _aoMudarModo(s.first),
          ),
          const SizedBox(height: 8),
        ],
        SwitchListTile.adaptive(
          contentPadding: EdgeInsets.zero,
          value: _syncAtiva,
          onChanged: (v) => setState(() => _syncAtiva = v),
          title: const Text('Usar rede local'),
          subtitle: Text(
            _modoServidor
                ? 'Liga o servidor neste PC para terminais.'
                : 'Conecta este aparelho ao servidor da loja.',
            style: TextStyle(color: onVar),
          ),
        ),
        const SizedBox(height: 8),
        if (_modoServidor) ...[
          _buildCampoToken(),
          const SizedBox(height: 4),
          Text(
            'Gere o token neste PC e use o mesmo em todos os clientes.',
            style: tema.textTheme.bodySmall?.copyWith(color: onVar),
          ),
          const SizedBox(height: 12),
        ],
        OutlinedButton.icon(
          onPressed: (_salvando || _testandoRede) ? null : () => _testarConexao(),
          icon: _testandoRede
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.wifi_tethering_outlined),
          label: Text(_testandoRede ? 'Testando...' : 'Testar conexão'),
        ),
        if (Platform.isWindows) ...[
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: _liberarFirewall,
            icon: const Icon(Icons.security_outlined, size: 18),
            label: const Text('Liberar portas no firewall'),
          ),
        ],
        if (_modoServidor) ...[
          const SizedBox(height: 16),
          _buildControlesServidorAvancado(),
          const SizedBox(height: 12),
          _buildTerminaisConectados(tema),
        ],
        if (_usaSyncCatalogo) ...[
          const SizedBox(height: 12),
          SwitchListTile.adaptive(
            contentPadding: EdgeInsets.zero,
            value: _modoImplantacao,
            onChanged: _alternarModoImplantacao,
            title: const Text('Modo implantação (este aparelho)'),
            subtitle: const Text(
              'Intervalo maior entre sincronizações (celular/loja nova).',
            ),
          ),
          const SizedBox(height: 8),
          ValueListenableBuilder<SyncLogEntry?>(
            valueListenable: SyncLog.ultimo,
            builder: (context, ultimoLog, _) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _buildChecklist(tema, ultimoLog),
                  if (ultimoLog != null && !ultimoLog.sucesso)
                    _buildErroComAjuda(tema, ultimoLog),
                ],
              );
            },
          ),
          _buildPainelConflitos(tema),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _salvando ? null : () => _salvar(),
                  icon: const Icon(Icons.save_outlined, size: 18),
                  label: Text(_salvando ? 'Salvando...' : 'Salvar'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: (_sincronizando || _salvando)
                      ? null
                      : _sincronizarAgora,
                  icon: _sincronizando
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.cloud_sync_outlined, size: 18),
                  label: Text(
                    _sincronizando ? 'Sync...' : 'Sincronizar',
                  ),
                ),
              ),
            ],
          ),
          if (!kIsWeb &&
              (Platform.isAndroid || Platform.isIOS) &&
              !_modoServidor) ...[
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed:
                  (_enviandoFotos || _salvando) ? null : _enviarFotosAoServidor,
              icon: _enviandoFotos
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.photo_library_outlined, size: 18),
              label: Text(
                _enviandoFotos
                    ? 'Enviando fotos...'
                    : 'Reenviar fotos (opcional)',
              ),
            ),
          ],
        ] else if (!_modoServidor) ...[
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: _salvando ? null : () => _salvar(),
            icon: const Icon(Icons.save_outlined, size: 18),
            label: Text(_salvando ? 'Salvando...' : 'Salvar configuração'),
          ),
        ],
        const SizedBox(height: 12),
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            onPressed: () => SyncRedeAjuda.mostrarDialogPrimeiraSync(context),
            icon: const Icon(Icons.help_outline, size: 18),
            label: const Text('Como configurar a rede?'),
          ),
        ),
      ],
    );
  }

  Widget _buildControlesServidorAvancado() {
    if (!Platform.isWindows) return const SizedBox.shrink();
    return SwitchListTile.adaptive(
      contentPadding: EdgeInsets.zero,
      value: _iniciarComWindows,
      onChanged: _alternarIniciarComWindows,
      title: const Text('Servidor ao ligar o PC'),
      subtitle: const Text(
        'Recomendado: sobe a API em segundo plano ao ligar o Windows '
        '(sem abrir o programa). Terminais passam a funcionar so de '
        'ligar este PC. Ativado automaticamente ao salvar como servidor.',
      ),
    );
  }

  Widget _buildPainelConflitos(ThemeData tema) {
    return ValueListenableBuilder<List<SyncConflictEntry>>(
      valueListenable: SyncConflictLog.recentes,
      builder: (context, lista, _) {
        if (lista.isEmpty) return const SizedBox.shrink();
        final visiveis = lista.take(5).toList();
        return Padding(
          padding: const EdgeInsets.only(top: 12),
          child: Card(
            color: tema.colorScheme.tertiaryContainer.withValues(alpha: 0.35),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    'Conflitos recentes na sync',
                    style: tema.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 8),
                  for (final c in visiveis)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Text(
                            '${c.rotuloTipo} · ${c.entity}'
                            '${c.entityId > 0 ? ' #${c.entityId}' : ''}\n'
                            '${c.detalhe}',
                            style: tema.textTheme.bodySmall,
                          ),
                          const SizedBox(height: 4),
                          Wrap(
                            spacing: 8,
                            children: [
                              if (c.tipo == SyncConflictTipo.editEdit ||
                                  c.tipo == SyncConflictTipo.configMerge)
                                TextButton(
                                  onPressed: () async {
                                    await SyncConflictResolver.manterLocal(c);
                                    if (mounted) setState(() {});
                                  },
                                  child: const Text('Manter local'),
                                ),
                              if (c.tipo == SyncConflictTipo.editEdit ||
                                  c.tipo == SyncConflictTipo.configMerge)
                                TextButton(
                                  onPressed: () async {
                                    await SyncConflictResolver.aceitarRemoto(c);
                                    if (mounted) setState(() {});
                                  },
                                  child: const Text('Aceitar remoto'),
                                ),
                              TextButton(
                                onPressed: () async {
                                  await SyncConflictResolver.dispensar(c);
                                  if (mounted) setState(() {});
                                },
                                child: const Text('Dispensar'),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  if (lista.length > visiveis.length)
                    Text(
                      '+ ${lista.length - visiveis.length} registro(s) anterior(es)',
                      style: tema.textTheme.labelSmall,
                    ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildChecklist(ThemeData tema, SyncLogEntry? ultimoLog) {
    final ultimaSyncOk = ultimoLog?.sucesso == true;
    final tokenOk = _tokenAceitoPeloServidor == true ||
        (_tokenAceitoPeloServidor == null &&
            _tokenPreenchido &&
            _servidorOnline);
    final tokenPendente = _tokenAceitoPeloServidor == false;

    return Column(
      children: [
        _CheckItem(
          ok: _servidorOnline,
          titulo: 'Servidor alcancavel na rede',
          subtitulo: _servidorOnline
              ? 'Teste de conexao OK'
              : 'Servidor local nao encontrado — Testar conexao / conferir IP',
        ),
        _CheckItem(
          ok: _tokenPreenchido && !tokenPendente,
          titulo: 'Token configurado',
          subtitulo: _tokenPreenchido
              ? (tokenPendente
                  ? 'Token recusado — confira no PC servidor'
                  : (_tokenAceitoPeloServidor == true
                      ? 'Token aceito pelo servidor'
                      : 'Teste a conexao para validar'))
              : 'Preencha ou gere um token',
        ),
        _CheckItem(
          ok: tokenOk && _servidorOnline,
          titulo: 'Autenticacao no servidor',
          subtitulo: tokenOk
              ? 'Pronto para conectar'
              : 'Corrija endereco e token',
        ),
        _CheckItem(
          ok: ultimaSyncOk,
          titulo: 'Ultima sincronizacao',
          subtitulo: ultimaSyncOk
              ? 'Dados atualizados'
              : (ultimoLog == null
                  ? 'Ainda nao sincronizou'
                  : 'Falhou — veja como resolver abaixo'),
        ),
      ],
    );
  }

  Widget _buildCampoToken() {
    return TextField(
      controller: _tokenController,
      decoration: InputDecoration(
        labelText: 'Token da rede',
        hintText: 'Gerado ao salvar se vazio',
        border: const OutlineInputBorder(),
        isDense: true,
        suffixIcon: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              tooltip: _tokenVisivel ? 'Ocultar token' : 'Mostrar token',
              icon: Icon(
                _tokenVisivel
                    ? Icons.visibility_off_outlined
                    : Icons.visibility_outlined,
              ),
              onPressed: () {
                setState(() => _tokenVisivel = !_tokenVisivel);
              },
            ),
            IconButton(
              tooltip: 'Copiar token',
              icon: const Icon(Icons.content_copy_outlined),
              onPressed: _copiarToken,
            ),
            IconButton(
              tooltip: 'Gerar novo token',
              icon: const Icon(Icons.vpn_key_outlined),
              onPressed: _gerarNovoToken,
            ),
          ],
        ),
      ),
      obscureText: !_tokenVisivel,
      autocorrect: false,
      enableSuggestions: false,
      onChanged: (_) => setState(() => _tokenAceitoPeloServidor = null),
    );
  }

  Widget _buildErroComAjuda(ThemeData tema, SyncLogEntry entry) {
    final dicas = SyncRedeAjuda.dicasParaErro(entry.mensagem);
    final erro = tema.colorScheme.error;
    return Card(
      margin: const EdgeInsets.only(top: 8),
      color: erro.withValues(alpha: 0.06),
      child: ExpansionTile(
        initiallyExpanded: _erroAjudaExpandido,
        onExpansionChanged: (v) => setState(() => _erroAjudaExpandido = v),
        title: Text(
          'Como resolver o ultimo erro',
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w600,
            color: erro,
          ),
        ),
        subtitle: Text(
          entry.mensagem.split('\n').first,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontSize: 12),
        ),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (final d in dicas)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('• ', style: TextStyle(color: erro)),
                        Expanded(child: Text(d, style: const TextStyle(fontSize: 13))),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final tema = Theme.of(context);

    if (_carregando) {
      return const Padding(
        padding: EdgeInsets.all(24),
        child: Center(child: CircularProgressIndicator()),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildStatusCard(tema),
        const SizedBox(height: 16),
        _buildConnectionCard(tema),
        const SizedBox(height: 16),
        _buildOpcoesAvancadasRede(tema),
      ],
    );
  }
}

class _CheckItem extends StatelessWidget {
  const _CheckItem({
    required this.ok,
    required this.titulo,
    required this.subtitulo,
  });

  final bool ok;
  final String titulo;
  final String subtitulo;

  @override
  Widget build(BuildContext context) {
    final cor = ok ? Colors.green.shade700 : Theme.of(context).colorScheme.outline;
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            ok ? Icons.check_circle_outline : Icons.radio_button_unchecked,
            size: 20,
            color: cor,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  titulo,
                  style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
                ),
                Text(subtitulo, style: Theme.of(context).textTheme.bodySmall),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
