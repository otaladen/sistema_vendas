import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../data/app_config_repository.dart';
import '../../data/sync/lan_sync_scheduler.dart';
import '../../data/sync/sync_api_client.dart';
import '../../data/sync/sync_conflict_log.dart';
import '../../data/sync/sync_conflict_resolver.dart';
import '../../data/sync/sync_log.dart';
import '../../data/sync/sync_priority.dart';
import '../../data/sync/sync_teste_conexao.dart';
import '../../domain/sync_rede_ajuda.dart';
import '../../domain/sync_token_util.dart';
import '../../services/lan_sync_server_manager.dart';

/// Assistente de rede local: servidor neste PC ou cliente apontando para outro.
class RedeSincronizacaoCard extends StatefulWidget {
  const RedeSincronizacaoCard({
    super.key,
    required this.configRepository,
    this.lanSyncScheduler,
  });

  final AppConfigRepository configRepository;
  final LanSyncScheduler? lanSyncScheduler;

  @override
  State<RedeSincronizacaoCard> createState() => _RedeSincronizacaoCardState();
}

class _RedeSincronizacaoCardState extends State<RedeSincronizacaoCard> {
  final _urlController = TextEditingController();
  final _portaController = TextEditingController();
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
  bool _iniciandoServidor = false;
  bool _parandoServidor = false;
  bool _tokenVisivel = false;
  bool? _tokenAceitoPeloServidor;
  bool _erroAjudaExpandido = false;

  int? _estacoesAtivas;
  List<Map<String, dynamic>> _estacoesLista = [];
  String _presencaErro = '';
  bool _carregandoPresenca = false;

  @override
  void initState() {
    super.initState();
    unawaited(SyncConflictLog.limparAvisosDeAceiteRemoto());
    _carregar();
  }

  @override
  void dispose() {
    _urlController.dispose();
    _portaController.dispose();
    _tokenController.dispose();
    super.dispose();
  }

  int get _porta {
    final p = int.tryParse(_portaController.text.trim());
    if (p == null || p < 1024 || p > 65535) {
      return LanSyncServerManager.portaPadrao;
    }
    return p;
  }

  String get _tokenAtual => _tokenController.text.trim();

  bool get _tokenPreenchido => _tokenAtual.isNotEmpty;

  Future<void> _carregar() async {
    setState(() => _carregando = true);
    final config = await widget.configRepository.carregarEmpresaConfig();
    final modoImplantacao =
        await widget.configRepository.carregarModoImplantacaoLocal();
    final ip = await LanSyncServerManager.obterIpv4Local();
    final porta = config.redePortaServidor;
    var url = config.redeServidorUrl.trim();
    if (config.redeModoServidor && ip != null && url.isEmpty) {
      url = LanSyncServerManager.montarUrlServidor(ip, porta);
    }
    final online = url.isNotEmpty
        ? await LanSyncServerManager.servidorRespondendo(url)
        : await LanSyncServerManager.servidorRespondendoNaPorta(porta);

    if (!mounted) return;
    setState(() {
      _modoServidor = config.redeModoServidor;
      _syncAtiva = config.redeSincronizacaoAtiva;
      _modoImplantacao = modoImplantacao;
      _ipLocal = ip;
      _portaController.text = '$porta';
      _urlController.text = url;
      _tokenController.text = config.redeSyncToken;
      _servidorOnline = online;
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
    setState(() {
      _modoServidor = servidor;
      _tokenAceitoPeloServidor = null;
      if (servidor && _ipLocal != null) {
        _urlController.text =
            LanSyncServerManager.montarUrlServidor(_ipLocal!, _porta);
      }
    });
    _atualizarStatusServidor();
  }

  void _preencherUrlServidorLocal() {
    final ip = _ipLocal;
    if (ip == null || ip.isEmpty) return;
    _urlController.text = LanSyncServerManager.montarUrlServidor(ip, _porta);
  }

  Future<void> _atualizarStatusServidor() async {
    final url = _urlController.text.trim();
    final online = url.isNotEmpty
        ? await LanSyncServerManager.servidorRespondendo(url)
        : await LanSyncServerManager.servidorRespondendoNaPorta(_porta);
    if (mounted) setState(() => _servidorOnline = online);
  }

  Future<void> _alternarModoImplantacao(bool ativo) async {
    setState(() => _modoImplantacao = ativo);
    await widget.configRepository.salvarModoImplantacaoLocal(ativo);
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
      if (_modoServidor) {
        _preencherUrlServidorLocal();
      }
      final atual = await widget.configRepository.carregarEmpresaConfig();
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
        redeModoServidor: _modoServidor,
        redePortaServidor: _porta,
        redeServidorUrl: _urlController.text.trim(),
        redeSyncToken: token,
      );
      await widget.configRepository.salvarEmpresaConfig(config);

      if (_modoServidor && iniciarServidorSeModoServidor && Platform.isWindows) {
        final err = await LanSyncServerManager.iniciarServidor(
          porta: _porta,
          syncToken: token,
          productImagesPath:
              await LanSyncServerManager.caminhoPadraoProductImages(),
        );
        if (err != null && mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(err)),
          );
        }
      }

      await widget.lanSyncScheduler?.iniciar();
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
      final ip = _ipLocal ?? await LanSyncServerManager.obterIpv4Local();
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
      _urlController.text = LanSyncServerManager.montarUrlServidor(ip, _porta);
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

    // Nao espera o pull completo aqui: no celular (banco vazio) isso pode
    // travar a tela por minutos. Conexao ja esta ok; sync sobe em background.
    if (!mounted) return;
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

  Future<void> _iniciarServidor() async {
    setState(() => _iniciandoServidor = true);
    try {
        final err = await LanSyncServerManager.iniciarServidor(
          porta: _porta,
          syncToken: _tokenAtual,
          productImagesPath: await LanSyncServerManager.caminhoPadraoProductImages(),
        );
      if (!mounted) return;
      if (err != null) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(err)));
      } else {
        _preencherUrlServidorLocal();
        setState(() => _servidorOnline = true);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Servidor de sincronizacao iniciado.')),
        );
      }
    } finally {
      if (mounted) setState(() => _iniciandoServidor = false);
    }
  }

  Future<void> _pararServidor() async {
    setState(() => _parandoServidor = true);
    try {
      await LanSyncServerManager.pararServidor();
      await _atualizarStatusServidor();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Comando de parada enviado ao servidor.')),
      );
    } finally {
      if (mounted) setState(() => _parandoServidor = false);
    }
  }

  Future<void> _liberarFirewall() async {
    final err = await LanSyncServerManager.tentarLiberarFirewall(_porta);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          err ??
              'Regra de firewall criada para a porta $_porta (se permitido pelo Windows).',
        ),
      ),
    );
  }

  Future<void> _sincronizarAgora({bool avisarConclusao = true}) async {
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

  String _formatarHora(DateTime dt) {
    final l = dt.toLocal();
    return '${l.hour.toString().padLeft(2, '0')}:${l.minute.toString().padLeft(2, '0')}';
  }

  void _copiarEnderecoClientes() {
    final ip = _ipLocal;
    if (ip == null) return;
    final txt = '$ip:$_porta';
    Clipboard.setData(ClipboardData(text: txt));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Copiado para os outros PCs: $txt')),
    );
  }

  String _rotuloBotaoPrincipal() {
    if (_salvando || _testandoRede) {
      return _modoServidor ? 'Ativando servidor...' : 'Conectando...';
    }
    if (_sincronizando) {
      return 'Sincronizando em segundo plano...';
    }
    return _modoServidor
        ? 'Ativar como servidor e sincronizar'
        : 'Conectar a este servidor e sincronizar';
  }

  Widget _buildPainelStatus(ThemeData tema, SyncLogEntry? ultimoLog) {
    final erro = tema.colorScheme.error;
    final onVar = tema.colorScheme.onSurfaceVariant;

    final syncLigada = _syncAtiva;
    final papel = _modoServidor ? 'Servidor' : 'Cliente';

    late final Color corSemaforo;
    late final String rotuloSemaforo;

    if (!syncLigada) {
      corSemaforo = tema.colorScheme.outline;
      rotuloSemaforo = 'Sync desligada';
    } else if (!_servidorOnline) {
      corSemaforo = erro;
      rotuloSemaforo = 'Servidor local nao encontrado';
    } else if (ultimoLog != null && !ultimoLog.sucesso) {
      corSemaforo = Colors.orange.shade800;
      rotuloSemaforo = 'Sync com falha';
    } else if (ultimoLog?.sucesso == true) {
      corSemaforo = Colors.green.shade700;
      rotuloSemaforo = 'Sincronizado';
    } else {
      corSemaforo = Colors.orange.shade800;
      rotuloSemaforo = 'Aguardando sync';
    }

    String syncTxt = 'Nenhuma sincronizacao ainda';
    if (ultimoLog != null) {
      syncTxt = ultimoLog.sucesso
          ? 'Ultima sync OK as ${_formatarHora(ultimoLog.em)}'
          : 'Ultima sync falhou as ${_formatarHora(ultimoLog.em)}';
    }

    final endereco = _modoServidor
        ? (_urlController.text.trim().isEmpty
            ? (_ipLocal ?? 'IP nao detectado')
            : _urlController.text.trim())
        : (_urlController.text.trim().isEmpty
            ? 'Informe o endereco do servidor'
            : _urlController.text.trim());

    return Card(
      color: corSemaforo.withValues(alpha: 0.08),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 14,
                  height: 14,
                  margin: const EdgeInsets.only(top: 4),
                  decoration: BoxDecoration(
                    color: corSemaforo,
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: corSemaforo.withValues(alpha: 0.45),
                        blurRadius: 6,
                        spreadRadius: 1,
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        rotuloSemaforo,
                        style: tema.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w800,
                          color: corSemaforo,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '$papel · $syncTxt',
                        style: tema.textTheme.bodySmall?.copyWith(color: onVar),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Text(
              'Endereco: $endereco',
              style: tema.textTheme.bodySmall,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAssistenteSimplificado(ThemeData tema) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (_modoServidor) _buildModoServidor(tema) else _buildModoCliente(),
        const SizedBox(height: 8),
        _buildCampoToken(),
        const SizedBox(height: 4),
        Text(
          'Mesmo token no servidor e em todos os clientes.',
          style: tema.textTheme.bodySmall?.copyWith(
            color: tema.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 14),
        SizedBox(
          width: double.infinity,
          child: FilledButton.icon(
            onPressed: (_salvando || _testandoRede) ? null : _configurarRedeCompleta,
            icon: (_salvando || _testandoRede || _sincronizando)
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : const Icon(Icons.link_outlined),
            label: Text(_rotuloBotaoPrincipal()),
          ),
        ),
        const SizedBox(height: 8),
        SizedBox(
          width: double.infinity,
          child: OutlinedButton.icon(
            onPressed: (_salvando || _testandoRede)
                ? null
                : () => _testarConexao(),
            icon: _testandoRede
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.wifi_tethering_outlined),
            label: Text(_testandoRede ? 'Testando...' : 'Testar conexao'),
          ),
        ),
        ValueListenableBuilder<SyncLogEntry?>(
          valueListenable: SyncLog.ultimo,
          builder: (context, ultimoLog, _) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _buildPainelConflitos(tema),
                if (ultimoLog != null && !ultimoLog.sucesso)
                  _buildErroComAjuda(tema, ultimoLog),
              ],
            );
          },
        ),
      ],
    );
  }

  Widget _buildOpcoesAvancadasRede(ThemeData tema) {
    return ExpansionTile(
      tilePadding: EdgeInsets.zero,
      childrenPadding: const EdgeInsets.only(bottom: 8),
      title: Text(
        'Opcoes avancadas',
        style: tema.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
      ),
      subtitle: Text(
        'Implantacao, salvar manual, sync e servidor',
        style: tema.textTheme.bodySmall?.copyWith(
          color: tema.colorScheme.onSurfaceVariant,
        ),
      ),
      children: [
        SwitchListTile.adaptive(
          contentPadding: EdgeInsets.zero,
          value: _modoImplantacao,
          onChanged: _alternarModoImplantacao,
          title: const Text('Modo implantacao (este PC)'),
          subtitle: const Text(
            'Intervalo 60s e espera 3s antes de sync apos varias gravacoes.',
          ),
        ),
        const SizedBox(height: 8),
        ValueListenableBuilder<SyncLogEntry?>(
          valueListenable: SyncLog.ultimo,
          builder: (context, ultimoLog, _) {
            return _buildChecklist(tema, ultimoLog);
          },
        ),
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
                label: Text(_sincronizando ? 'Sync...' : 'Sync agora'),
              ),
            ),
          ],
        ),
        if (!kIsWeb && Platform.isWindows) ...[
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
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              'No PC servidor as fotos ja ficam no disco. So use isto se o '
              'celular ainda mostrar "foto indisponivel" (servidor antigo '
              'aberto fora do app).',
              style: tema.textTheme.bodySmall?.copyWith(
                color: tema.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        ],
        const SizedBox(height: 8),
        _buildControlesServidorAvancado(tema),
      ],
    );
  }

  Widget _buildControlesServidorAvancado(ThemeData tema) {
    final onVar = tema.colorScheme.onSurfaceVariant;
    final erro = tema.colorScheme.error;

    if (_modoServidor) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              FilledButton.icon(
                onPressed: (_iniciandoServidor || _servidorOnline)
                    ? null
                    : _iniciarServidor,
                icon: _iniciandoServidor
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.play_arrow_outlined, size: 20),
                label: const Text('Iniciar servidor'),
              ),
              OutlinedButton.icon(
                onPressed: _parandoServidor || !_servidorOnline
                    ? null
                    : _pararServidor,
                icon: const Icon(Icons.stop_outlined, size: 20),
                label: const Text('Parar'),
              ),
              if (Platform.isWindows)
                OutlinedButton(
                  onPressed: _liberarFirewall,
                  child: const Text('Liberar porta no firewall'),
                ),
            ],
          ),
          if (_ipLocal != null) ...[
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: _copiarEnderecoClientes,
              icon: const Icon(Icons.copy_outlined, size: 18),
              label: Text(
                'Copiar endereco para outros PCs (${_ipLocal!}:$_porta)',
              ),
            ),
          ],
          const Divider(height: 24),
          Text(
            'Estacoes conectadas',
            style: tema.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'PCs com o app aberto e sincronizacao ativa.',
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
              _carregandoPresenca ? 'Consultando...' : 'Ver estacoes online',
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
                child: Text('• ${lab.isEmpty ? "PC" : lab}'),
              );
            }),
          ],
        ],
      );
    }

    return Text(
      'No modo cliente, o servidor principal controla as estacoes.',
      style: tema.textTheme.bodySmall?.copyWith(color: onVar),
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
              ? 'Pronto para sincronizar'
              : 'Corrija endereco e token',
        ),
        _CheckItem(
          ok: ultimaSyncOk,
          titulo: 'Ultima sincronizacao de dados',
          subtitulo: ultimaSyncOk
              ? 'Dados replicados com sucesso'
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
        labelText: 'Token de sincronizacao (LAN)',
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

  Widget _buildModoServidor(ThemeData tema) {
    final erro = tema.colorScheme.error;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _InfoLinha(
          rotulo: 'IP deste PC na rede',
          valor: _ipLocal ?? 'Nao detectado',
          trailing: IconButton(
            tooltip: 'Atualizar IP',
            onPressed: () async {
              final ip = await LanSyncServerManager.obterIpv4Local();
              setState(() => _ipLocal = ip);
              if (ip != null) _preencherUrlServidorLocal();
            },
            icon: const Icon(Icons.refresh, size: 20),
          ),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: _portaController,
          decoration: const InputDecoration(
            labelText: 'Porta do servidor',
            border: OutlineInputBorder(),
            isDense: true,
          ),
          keyboardType: TextInputType.number,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          onChanged: (_) => _preencherUrlServidorLocal(),
        ),
        const SizedBox(height: 8),
        _InfoLinha(
          rotulo: 'Endereco local do servico',
          valor: _urlController.text.isEmpty ? '—' : _urlController.text,
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Icon(
              _servidorOnline ? Icons.check_circle : Icons.error_outline,
              size: 18,
              color: _servidorOnline ? Colors.green.shade700 : erro,
            ),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                _servidorOnline
                    ? 'Servidor de sync respondendo neste PC'
                    : 'Servidor parado ou inacessivel',
                style: tema.textTheme.bodySmall?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildModoCliente() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Cole o endereco que o servidor copiou (ex.: 192.168.0.3:8787).',
          style: Theme.of(context).textTheme.bodySmall,
        ),
        const SizedBox(height: 8),
        TextField(
          controller: _urlController,
          decoration: InputDecoration(
            labelText: 'Endereco do servidor na rede',
            hintText: 'Ex.: 192.168.0.15:8787',
            border: const OutlineInputBorder(),
            isDense: true,
            suffixIcon: IconButton(
              tooltip: 'Colar da area de transferencia',
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
      ],
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
        Text(
          'Escolha o papel deste computador. O servidor concentra os dados; '
          'os outros PCs conectam ao IP dele na mesma rede Wi-Fi/cabo.',
          style: tema.textTheme.bodySmall?.copyWith(
            color: tema.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 12),
        ValueListenableBuilder<SyncLogEntry?>(
          valueListenable: SyncLog.ultimo,
          builder: (context, ultimoLog, _) {
            return _buildPainelStatus(tema, ultimoLog);
          },
        ),
        const SizedBox(height: 12),
        SegmentedButton<bool>(
          segments: const [
            ButtonSegment(
              value: true,
              label: Text('Servidor neste PC'),
              icon: Icon(Icons.dns_outlined),
            ),
            ButtonSegment(
              value: false,
              label: Text('Outro PC e o servidor'),
              icon: Icon(Icons.lan_outlined),
            ),
          ],
          selected: {_modoServidor},
          onSelectionChanged: (s) => _aoMudarModo(s.first),
        ),
        const SizedBox(height: 8),
        SwitchListTile.adaptive(
          contentPadding: EdgeInsets.zero,
          value: _syncAtiva,
          onChanged: (v) => setState(() => _syncAtiva = v),
          title: const Text('Usar sincronizacao na rede local'),
          subtitle: const Text(
            'Cadastros, estoque, vendas, NF-e e configuracoes entre PCs.',
          ),
        ),
        if (!_syncAtiva) ...[
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: tema.colorScheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              'Com a sincronizacao desligada, este PC trabalha apenas com '
              'dados locais. Ative o switch acima para conectar outros '
              'computadores da loja.',
              style: tema.textTheme.bodySmall,
            ),
          ),
        ] else ...[
          const SizedBox(height: 8),
          _buildAssistenteSimplificado(tema),
          const SizedBox(height: 4),
          _buildOpcoesAvancadasRede(tema),
        ],
        const SizedBox(height: 12),
        Center(
          child: TextButton.icon(
            onPressed: () => SyncRedeAjuda.mostrarDialogPrimeiraSync(context),
            icon: const Icon(Icons.help_outline, size: 18),
            label: const Text('Problemas na primeira sincronizacao?'),
          ),
        ),
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

class _InfoLinha extends StatelessWidget {
  const _InfoLinha({
    required this.rotulo,
    required this.valor,
    this.trailing,
  });

  final String rotulo;
  final String valor;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(rotulo, style: Theme.of(context).textTheme.labelSmall),
              const SizedBox(height: 2),
              Text(
                valor,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
              ),
            ],
          ),
        ),
        ?trailing,
      ],
    );
  }
}
