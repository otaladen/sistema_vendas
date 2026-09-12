import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../config/focus_nfe_runtime.dart';
import '../../data/api/lan_api_event_hub.dart';
import '../../data/api/venda_api_repository.dart';
import '../../services/configuracoes_service.dart';
import '../../data/cliente_repository.dart';
import '../../data/sync/sync_refresh_hub.dart';
import '../../data/venda_repository.dart';
import '../../domain/fiscal/fiscal_erro_dica_helper.dart';
import '../../domain/fiscal/venda_nfce_obrigatoria_helper.dart';
import '../../domain/item_venda_produto_orfao.dart';
import '../../domain/venda_documento_rotulo_helper.dart';
import '../../domain/venda_finalizacao_caixa_helper.dart';
import '../../model/usuario_sistema.dart';
import '../../model/venda.dart';
import '../../services/focus_nfe_service.dart';
import '../../services/nfce_reconciliacao_service.dart';
import '../shell/main_menu_deps.dart';
import '../widgets/lan_api_feedback.dart';
import 'nfce_emissao_pendente_flow.dart';
import 'nfe_gerenciamento_page.dart';
import 'revincular_produto_item_venda_flow.dart';
import 'widgets/fiscal_rejeicao_detalhe_dialog.dart';

/// Central de pendencias NFC-e (reconsulta) e atalho para NF-e 55.
/// Terminal Leve: listagem/emissao/reconsulta 100% via API :8788.
class PendenciasFiscaisPage extends StatefulWidget {
  const PendenciasFiscaisPage({
    super.key,
    required this.vendaRepository,
    required this.clienteRepository,
    required this.configuracoesService,
    required this.usuarioLogado,
  });

  final dynamic vendaRepository;
  final dynamic clienteRepository;
  final ConfiguracoesService configuracoesService;
  final UsuarioSistema usuarioLogado;

  @override
  State<PendenciasFiscaisPage> createState() => _PendenciasFiscaisPageState();
}

class _PendenciasFiscaisPageState extends State<PendenciasFiscaisPage> {
  FocusNfeService? _focusNfe;
  NfceReconciliacaoService? _reconciliacao;
  List<Venda> _pendentesSefaz = const [];
  List<Venda> _pendentesEmissao = const [];
  bool _carregando = true;
  bool _reconsultando = false;
  bool _emitindo = false;
  bool _permitirVendaSemEstoque = true;
  VoidCallback? _syncHubListener;
  bool? _apiOnlineAnterior;
  Timer? _wsDebounce;

  bool get _terminalApi => widget.vendaRepository is VendaApiRepository;

  static final _data = DateFormat('dd/MM/yyyy HH:mm');
  static final _moeda = NumberFormat('#,##0.00', 'pt_BR');

  @override
  void initState() {
    super.initState();
    if (!_terminalApi) {
      _focusNfe = FocusNfeService(config: criarFocusNfeConfigPadrao());
      _reconciliacao = NfceReconciliacaoService(
        vendaRepository: widget.vendaRepository as VendaRepository,
        focusNfe: _focusNfe!,
      );
      _syncHubListener = () {
        if (mounted) unawaited(_recarregar(silencioso: true));
      };
      SyncRefreshHub.instance.addListener(_syncHubListener!);
    } else {
      _apiOnlineAnterior = LanApiEventHub.instance.online;
      LanApiEventHub.instance.addListener(_onLanApiEvento);
    }
    _carregarConfig();
    unawaited(_recarregar());
  }

  @override
  void dispose() {
    _wsDebounce?.cancel();
    LanApiEventHub.instance.removeListener(_onLanApiEvento);
    if (_syncHubListener != null) {
      SyncRefreshHub.instance.removeListener(_syncHubListener!);
      _syncHubListener = null;
    }
    super.dispose();
  }

  void _onLanApiEvento() {
    if (!_terminalApi) return;
    final hub = LanApiEventHub.instance;
    final online = hub.online;
    final ficouOnline = online && _apiOnlineAnterior == false;
    _apiOnlineAnterior = online;
    if (hub.deveBloquearOperacoes) return;
    final ent = hub.ultimaEntidade;
    if (!ficouOnline &&
        ent != 'venda' &&
        ent != 'produto' &&
        ent != 'fiscal' &&
        ent != 'nfe_saida') {
      return;
    }
    _wsDebounce?.cancel();
    _wsDebounce = Timer(const Duration(milliseconds: 400), () {
      if (mounted) unawaited(_recarregar(silencioso: true));
    });
  }

  Future<void> _carregarConfig() async {
    final config = await widget.configuracoesService.carregarEfetiva();
    if (!mounted) return;
    setState(() => _permitirVendaSemEstoque = config.permitirVendaSemEstoque);
  }

  Future<void> _recarregar({bool silencioso = false}) async {
    if (_terminalApi &&
        !LanApiEventHub.instance.garantirOnlineOuAvisar(context)) {
      if (mounted && !silencioso) setState(() => _carregando = false);
      return;
    }
    if (!silencioso && mounted) setState(() => _carregando = true);
    try {
      if (_terminalApi) {
        await (widget.vendaRepository as VendaApiRepository)
            .hidratarPendenciasFiscais();
        if (!mounted) return;
        final api = widget.vendaRepository as VendaApiRepository;
        setState(() {
          _pendentesSefaz = api.listarComNfcePendenteFocus();
          _pendentesEmissao = api.listarComNfcePendenteEmissao();
          _carregando = false;
        });
        return;
      }
      if (!mounted) return;
      setState(() {
        _pendentesSefaz = _reconciliacao!.listarPendentes();
        _pendentesEmissao =
            widget.vendaRepository.listarComNfcePendenteEmissao();
        _carregando = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _carregando = false);
      if (!silencioso) {
        LanApiFeedback.snackErro(
          context,
          e,
          prefixo: 'Falha ao carregar pendencias fiscais',
        );
      }
    }
  }

  Future<void> _reconsultarTodas() async {
    if (_reconsultando) return;
    if (_terminalApi &&
        !LanApiEventHub.instance.garantirOnlineOuAvisar(context)) {
      return;
    }
    setState(() => _reconsultando = true);
    try {
      if (_terminalApi) {
        final api = widget.vendaRepository as VendaApiRepository;
        final lote = await api.reconsultarTodasNfceRemoto();
        if (!mounted) return;
        await _recarregar(silencioso: true);
        final total = (lote['total'] as num?)?.toInt() ?? 0;
        final autorizadas = (lote['autorizadas'] as num?)?.toInt() ?? 0;
        final ainda = (lote['aindaProcessando'] as num?)?.toInt() ?? 0;
        final msg = lote['ok'] != true
            ? (lote['error'] ?? 'Falha na reconsulta.').toString()
            : total == 0
                ? 'Nenhuma NFC-e pendente na SEFAZ.'
                : autorizadas > 0
                    ? '$autorizadas autorizada(s); $ainda ainda aguardando.'
                    : ainda > 0
                        ? '$ainda ainda aguardando a SEFAZ.'
                        : 'Reconsulta concluida. Verifique a lista.';
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
        return;
      }
      if (_reconciliacao == null || _focusNfe == null) return;
      try {
        _focusNfe!.validarConfiguracao();
      } catch (e) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('$e')),
        );
        return;
      }
      final lote = await _reconciliacao!.reconsultarTodasPendentes();
      if (!mounted) return;
      await _recarregar(silencioso: true);
      final msg = lote.total == 0
          ? 'Nenhuma NFC-e pendente na SEFAZ.'
          : lote.autorizadas > 0
              ? '${lote.autorizadas} autorizada(s); '
                  '${lote.aindaProcessando} ainda aguardando.'
              : lote.aindaProcessando > 0
                  ? '${lote.aindaProcessando} ainda aguardando a SEFAZ.'
                  : 'Reconsulta concluida. Verifique a lista.';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(msg)),
      );
    } catch (e) {
      if (!mounted) return;
      LanApiFeedback.snackErro(context, e, prefixo: 'Falha na reconsulta');
    } finally {
      if (mounted) setState(() => _reconsultando = false);
    }
  }

  Future<void> _reconsultarUma(Venda venda) async {
    if (_reconsultando) return;
    if (_terminalApi &&
        !LanApiEventHub.instance.garantirOnlineOuAvisar(context)) {
      return;
    }
    setState(() => _reconsultando = true);
    try {
      if (_terminalApi) {
        final api = widget.vendaRepository as VendaApiRepository;
        final r = await api.reconsultarNfceRemoto(venda.id);
        if (!mounted) return;
        await _recarregar(silencioso: true);
        final tipo = (r['tipo'] ?? '').toString();
        final mensagem = (r['mensagem'] ?? '').toString();
        final cupomOk = r['cupomInternoRegistrado'] != false;
        final msg = switch (tipo) {
          'autorizada' => cupomOk
              ? 'NFC-e autorizada e estoque atualizado.'
              : (mensagem.isEmpty
                  ? 'NFC-e autorizada, mas falhou ao salvar venda/estoque.'
                  : mensagem),
          'processando' => 'Ainda aguardando a SEFAZ.',
          'erro' => mensagem.isEmpty ? 'NFC-e rejeitada ou erro.' : mensagem,
          'semAlteracao' => 'Sem alteracao de status.',
          _ => r['ok'] == true
              ? (mensagem.isEmpty ? 'Reconsulta concluida.' : mensagem)
              : (r['error'] ?? mensagem).toString(),
        };
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
        return;
      }
      if (_reconciliacao == null) return;
      final r = await _reconciliacao!.reconsultarVenda(venda);
      if (!mounted) return;
      await _recarregar(silencioso: true);
      final msg = switch (r.tipo) {
        NfceReconciliacaoTipo.autorizada =>
          r.cupomInternoRegistrado
              ? 'NFC-e autorizada e estoque atualizado.'
              : (r.mensagem.isEmpty
                  ? 'NFC-e autorizada, mas falhou ao salvar venda/estoque.'
                  : r.mensagem),
        NfceReconciliacaoTipo.processando => 'Ainda aguardando a SEFAZ.',
        NfceReconciliacaoTipo.erro =>
          r.mensagem.isEmpty ? 'NFC-e rejeitada ou erro.' : r.mensagem,
        NfceReconciliacaoTipo.semAlteracao => 'Sem alteracao de status.',
      };
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(msg)),
      );
    } catch (e) {
      if (!mounted) return;
      LanApiFeedback.snackErro(context, e, prefixo: 'Falha na reconsulta');
    } finally {
      if (mounted) setState(() => _reconsultando = false);
    }
  }

  Future<void> _emitirNfce(Venda venda) async {
    if (_emitindo) return;
    setState(() => _emitindo = true);
    try {
      final api = widget.vendaRepository;
      if (api is VendaApiRepository) {
        await _emitirNfceViaApi(venda);
        return;
      }
      final produtoRepo = _produtoRepository(context);
      final ok = await NfceEmissaoPendenteFlow.emitir(
        context,
        venda: venda,
        vendaRepository: widget.vendaRepository as VendaRepository,
        clienteRepository: widget.clienteRepository as ClienteRepository,
        permitirVendaSemEstoque: _permitirVendaSemEstoque,
        produtoRepository: produtoRepo,
      );
      if (mounted) await _recarregar(silencioso: true);
    } catch (e) {
      if (mounted) {
        LanApiFeedback.snackErro(context, e, prefixo: 'Falha ao emitir');
      }
    } finally {
      if (mounted) setState(() => _emitindo = false);
    }
  }

  dynamic _produtoRepository(BuildContext context) {
    return MainMenuDeps.maybeOf(context)?.produtoRepository;
  }

  Future<void> _emitirNfceViaApi(Venda venda) async {
    if (!LanApiEventHub.instance.garantirOnlineOuAvisar(context)) {
      return;
    }
    final client = MainMenuDeps.maybeOf(context)?.lanApiClient;
    final produtoRepo = _produtoRepository(context);
    if (client == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('API do servidor indisponivel para emitir NFC-e.'),
          ),
        );
      }
      return;
    }

    for (var tentativa = 0; tentativa < 2; tentativa++) {
      if (!mounted) return;
      final api = widget.vendaRepository as VendaApiRepository;

      if (produtoRepo != null && tentativa == 0) {
        final itens = await api.carregarItensRemoto(venda.id);
        final orfaos = ItemVendaProdutoOrfaoHelper.filtrarOrfaos(
          itens,
          obterProduto: (id) {
            try {
              return produtoRepo.obterPorId(id);
            } catch (_) {
              return null;
            }
          },
        );
        if (orfaos.isNotEmpty) {
          final resolvido = await RevincularProdutoItemVendaFlow.resolverOrfaosDaVenda(
            context,
            vendaId: venda.id,
            vendaRepository: api,
            produtoRepository: produtoRepo,
          );
          if (!resolvido) return;
        }
      }

      final r = await client.emitirNfce(
        venda.id,
        permitirVendaSemEstoque: _permitirVendaSemEstoque,
      );
      if (!mounted) return;
      if (r['ok'] == true) {
        await api.hidratarPendenciasFiscais();
        await _recarregar(silencioso: true);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              r['autorizada'] == true
                  ? 'NFC-e ${(r['numero'] ?? '').toString()} autorizada no servidor.'
                  : (r['mensagem'] ?? 'NFC-e em processamento no servidor.')
                      .toString(),
            ),
          ),
        );
        return;
      }

      final erro = '${r['error'] ?? 'Falha ao emitir NFC-e'}';
      if (produtoRepo != null &&
          ItemVendaProdutoOrfaoHelper.pareceErroSemProdutoVinculado(erro)) {
        final resolvido = await RevincularProdutoItemVendaFlow.resolverOrfaosDaVenda(
          context,
          vendaId: venda.id,
          vendaRepository: api,
          produtoRepository: produtoRepo,
          mensagemErro: erro,
        );
        if (!resolvido) return;
        continue;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(erro)),
      );
      await _recarregar(silencioso: true);
      return;
    }
  }

  void _abrirNfePendencias() {
    Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => NfeGerenciamentoPage(
          vendaRepository: widget.vendaRepository,
          clienteRepository: widget.clienteRepository,
          configuracoesService: widget.configuracoesService,
          usuarioLogado: widget.usuarioLogado,
          abaInicial: 1,
        ),
      ),
    );
  }

  Future<void> _mostrarDetalhesErro(Venda venda) async {
    final erro = VendaNfceObrigatoriaHelper.mensagemErroExibicao(venda);
    if (erro.isEmpty) return;
    await FiscalRejeicaoDetalheDialog.show(
      context,
      titulo: 'Detalhes da Rejeicao Fiscal',
      numeroControle: VendaDocumentoRotuloHelper.rotuloControleInterno(venda),
      statusFiscal: VendaNfceObrigatoriaHelper.rotuloStatusFiscal(venda),
      mensagemErro: erro,
    );
  }

  Widget _cardPendenciaEmissao(Venda v, ThemeData theme, ColorScheme scheme) {
    final motivo = VendaNfceObrigatoriaHelper.motivoPendenciaEmissao(v);
    final erro = VendaNfceObrigatoriaHelper.mensagemErroExibicao(v);
    final resumoErro =
        erro.isNotEmpty ? FiscalErroDicaHelper.rotuloResumoLista(erro) : '';
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Icon(
                Icons.receipt_long_outlined,
                color: scheme.error,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    VendaDocumentoRotuloHelper.rotuloControleInterno(v),
                    style: theme.textTheme.titleMedium,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${_dataExibicao(v)} · '
                    'R\$ ${_moeda.format(v.total)} · '
                    '${VendaNfceObrigatoriaHelper.rotuloFormaPagamento(v)}',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    motivo,
                    style: theme.textTheme.bodySmall,
                  ),
                  if (resumoErro.isNotEmpty) ...[
                    const SizedBox(height: 6),
                    Text(
                      resumoErro,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: scheme.error,
                        fontWeight: FontWeight.w600,
                        height: 1.3,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            if (erro.isNotEmpty)
              IconButton(
                tooltip: 'Ver detalhes do erro',
                onPressed: () => unawaited(_mostrarDetalhesErro(v)),
                icon: Icon(Icons.info_outline, color: scheme.error),
              ),
            Padding(
              padding: const EdgeInsets.only(left: 4, top: 4),
              child: FilledButton(
                onPressed: _emitindo ? null : () => unawaited(_emitirNfce(v)),
                child: const Text('Emitir'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _cardPendenciaSefaz(Venda v, ThemeData theme, ColorScheme scheme) {
    final erro = VendaNfceObrigatoriaHelper.mensagemErroExibicao(v);
    final resumoErro =
        erro.isNotEmpty ? FiscalErroDicaHelper.rotuloResumoLista(erro) : '';
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Icon(
                Icons.hourglass_top_outlined,
                color: scheme.primary,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    VendaDocumentoRotuloHelper.rotuloControleInterno(v),
                    style: theme.textTheme.titleMedium,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${_dataExibicao(v)} · R\$ ${_moeda.format(v.total)}',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                  Text(
                    VendaNfceObrigatoriaHelper.rotuloStatusFiscal(v),
                    style: theme.textTheme.bodySmall,
                  ),
                  if (resumoErro.isNotEmpty) ...[
                    const SizedBox(height: 6),
                    Text(
                      resumoErro,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: scheme.error,
                        fontWeight: FontWeight.w600,
                        height: 1.3,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            if (erro.isNotEmpty)
              IconButton(
                tooltip: 'Ver detalhes do erro',
                onPressed: () => unawaited(_mostrarDetalhesErro(v)),
                icon: Icon(Icons.info_outline, color: scheme.error),
              ),
            Padding(
              padding: const EdgeInsets.only(left: 4, top: 4),
              child: OutlinedButton(
                onPressed: _reconsultando
                    ? null
                    : () => unawaited(_reconsultarUma(v)),
                child: const Text('Reconsultar'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _dataExibicao(Venda v) {
    final ref = VendaFinalizacaoCaixaHelper.momentoFinalizacao(v);
    return _data.format(ref.toLocal());
  }

  String get _subtituloNfe55 {
    if (!_terminalApi) {
      return 'Processando, rejeitadas e vendas sem faturamento.';
    }
    final api = widget.vendaRepository as VendaApiRepository;
    final proc = api.metaNfeProcessando;
    final rej = api.metaNfeRejeitadas;
    if (proc == 0 && rej == 0) {
      return 'Processando, rejeitadas e vendas sem faturamento.';
    }
    return 'Processando: $proc · Rejeitadas recentes: $rej';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final totalEmissao = VendaNfceObrigatoriaHelper.somaTotal(_pendentesEmissao);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Pendencias fiscais'),
        actions: [
          IconButton(
            tooltip: 'Atualizar lista',
            onPressed:
                _carregando ? null : () => unawaited(_recarregar()),
            icon: const Icon(Icons.sync),
          ),
          IconButton(
            tooltip: 'Reconsultar NFC-e na SEFAZ',
            onPressed: _reconsultando || _pendentesSefaz.isEmpty
                ? null
                : () => unawaited(_reconsultarTodas()),
            icon: _reconsultando
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.refresh),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () => _recarregar(),
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(16),
          children: [
            Card(
              color: _pendentesEmissao.isNotEmpty
                  ? scheme.errorContainer.withValues(alpha: 0.35)
                  : null,
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(
                          Icons.warning_amber_rounded,
                          color: _pendentesEmissao.isNotEmpty
                              ? scheme.error
                              : scheme.onSurfaceVariant,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'NFC-e a emitir (PIX / cartao)',
                            style: theme.textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                        if (_pendentesEmissao.isNotEmpty)
                          Chip(
                            label: Text('${_pendentesEmissao.length}'),
                            visualDensity: VisualDensity.compact,
                            backgroundColor: scheme.errorContainer,
                          ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text(
                      _pendentesEmissao.isEmpty
                          ? 'Nenhuma venda paga no cartao ou PIX sem NFC-e autorizada.'
                          : '${_pendentesEmissao.length} venda(s) · '
                              'R\$ ${_moeda.format(totalEmissao)} sem documento fiscal.',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                        height: 1.35,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
            if (_carregando)
              const Padding(
                padding: EdgeInsets.all(24),
                child: Center(child: CircularProgressIndicator()),
              )
            else if (_pendentesEmissao.isEmpty)
              const Card(
                child: Padding(
                  padding: EdgeInsets.all(16),
                  child: Text('Nenhuma NFC-e pendente de emissao.'),
                ),
              )
            else
              ..._pendentesEmissao.map(
                (v) => _cardPendenciaEmissao(v, theme, scheme),
              ),
            const SizedBox(height: 20),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            'NFC-e aguardando SEFAZ',
                            style: theme.textTheme.titleMedium,
                          ),
                        ),
                        if (_pendentesSefaz.isNotEmpty)
                          Chip(
                            label: Text('${_pendentesSefaz.length}'),
                            visualDensity: VisualDensity.compact,
                          ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text(
                      _terminalApi
                          ? 'Notas ja enviadas que aguardam retorno. '
                              'Reconsulte pelo botao ou aguarde o servidor.'
                          : 'Notas ja enviadas que aguardam retorno. O caixa '
                              'reconsulta automaticamente a cada 45 s.',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                        height: 1.35,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
            if (!_carregando && _pendentesSefaz.isEmpty)
              const Card(
                child: Padding(
                  padding: EdgeInsets.all(16),
                  child: Text('Nenhuma NFC-e aguardando a SEFAZ.'),
                ),
              )
            else if (!_carregando)
              ..._pendentesSefaz.map(
                (v) => _cardPendenciaSefaz(v, theme, scheme),
              ),
            const SizedBox(height: 16),
            Card(
              child: ListTile(
                leading: const Icon(Icons.receipt_long_outlined),
                title: const Text('NF-e modelo 55'),
                subtitle: Text(_subtituloNfe55),
                trailing: const Icon(Icons.chevron_right),
                onTap: _abrirNfePendencias,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
