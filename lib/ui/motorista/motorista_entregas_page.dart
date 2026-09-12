import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../services/configuracoes_service.dart';
import '../../data/api/cliente_api_repository.dart';
import '../../data/api/lan_api_client.dart';
import '../../data/api/lan_api_event_hub.dart';
import '../../data/api/venda_api_repository.dart';
import '../../data/sync/entrega_local_refresh_hub.dart';
import '../../services/entrega_pod_finalizacao.dart';
import '../../domain/entrega_baixa_motorista_visao.dart';
import '../../domain/entrega_baixa_pendente.dart';
import '../../domain/entrega_filtro_util.dart';
import '../../domain/entregas/loja_origem_mercadoria.dart';
import '../../domain/entregas/buscar_na_loja.dart';
import '../../domain/entregas/rota_motorista_sequencia.dart';
import '../../domain/motorista_lista_safe.dart';
import '../../domain/motorista_usuario_resolver.dart';
import '../../domain/entrega_nao_entregue.dart';
import '../../domain/usuario_permissao_helper.dart';
import '../../domain/venda_relacao_safe.dart';
import '../../model/item_venda.dart';
import '../../model/usuario_sistema.dart';
import '../../model/venda.dart';
import '../../services/entrega_baixa_sync_service.dart';
import '../../services/entrega_fluxo_service.dart';
import '../entregas/montagem_mapa_rota.dart';
import '../entregas/pod_entrega_dialog.dart';
import '../entregas/romaneio_pdf.dart';
import '../../model/historico_entrega.dart';
import '../shell/main_menu_deps.dart';
import '../widgets/lan_api_feedback.dart';
import 'nao_entregue_dialog.dart';

/// Painel do motorista: entregas do dia atribuidas ao usuario logado.
class MotoristaEntregasPage extends StatefulWidget {
  const MotoristaEntregasPage({
    super.key,
    required this.vendaRepository,
    required this.motoristaRepository,
    required this.usuarioLogado,
    this.configuracoesService,
  });

  final dynamic vendaRepository;
  final dynamic motoristaRepository;
  final UsuarioSistema usuarioLogado;
  final ConfiguracoesService? configuracoesService;

  @override
  State<MotoristaEntregasPage> createState() => _MotoristaEntregasPageState();
}

class _MotoristaEntregasPageState extends State<MotoristaEntregasPage> {
  List<Venda> _entregas = [];
  late String _nomeMotorista;
  bool _carregando = true;
  Timer? _refreshDebounce;
  bool _refreshViaApi = false;
  int _falhasGeracaoVisto = 0;
  bool _busyBuscar = false;
  bool _busyLiberar = false;

  bool get _usaVendaApi => widget.vendaRepository is VendaApiRepository;

  @override
  void initState() {
    super.initState();
    _nomeMotorista = MotoristaUsuarioResolver.nomeMotoristaLogistica(
      widget.usuarioLogado,
      MotoristaListaSafe.listarAtivos(widget.motoristaRepository),
    );
    LanApiEventHub.instance.addListener(_onLanApiChanged);
    EntregaLocalRefreshHub.instance.addListener(_onLocalRefresh);
    EntregaBaixaSyncService.instance.addListener(_onBaixaSync);
    unawaited(_carregarAsync());
  }

  @override
  void dispose() {
    _refreshDebounce?.cancel();
    LanApiEventHub.instance.removeListener(_onLanApiChanged);
    EntregaLocalRefreshHub.instance.removeListener(_onLocalRefresh);
    EntregaBaixaSyncService.instance.removeListener(_onBaixaSync);
    super.dispose();
  }

  void _onLanApiChanged() {
    if (!mounted) return;
    final ent = LanApiEventHub.instance.ultimaEntidade;
    if (ent != 'entrega' && ent != 'venda') return;
    _agendarRefresh(viaApi: true);
  }

  void _onLocalRefresh() {
    if (!mounted) return;
    _agendarRefresh(viaApi: false);
  }

  void _agendarRefresh({required bool viaApi}) {
    if (viaApi) _refreshViaApi = true;
    _refreshDebounce?.cancel();
    _refreshDebounce = Timer(const Duration(milliseconds: 250), () {
      final hidratar = _refreshViaApi;
      _refreshViaApi = false;
      if (!mounted) return;
      unawaited(_carregarAsync(hidratarApi: hidratar));
    });
  }

  void _onBaixaSync() {
    if (!mounted) return;
    final sync = EntregaBaixaSyncService.instance;
    if (sync.falhasGeracao != _falhasGeracaoVisto && sync.falhas.isNotEmpty) {
      _falhasGeracaoVisto = sync.falhasGeracao;
      final falha = sync.falhas.last;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Pedido ${falha.numeroOrcamento}: ${falha.mensagem}',
            ),
            backgroundColor: Colors.red.shade800,
            duration: const Duration(seconds: 8),
          ),
        );
      });
    }
    setState(() {});
  }

  Future<void> _carregarAsync({bool hidratarApi = true}) async {
    if (!mounted) return;
    final mostrarSpinner = _entregas.isEmpty &&
        EntregaBaixaSyncService.instance.pendentes.isEmpty;
    if (mostrarSpinner) {
      setState(() => _carregando = true);
    }
    if (_usaVendaApi && hidratarApi) {
      try {
        await (widget.vendaRepository as VendaApiRepository)
            .hidratarEntregas(limit: 500);
      } on LanApiException catch (e) {
        if (mounted &&
            EntregaBaixaSyncService.instance.pendentes.isEmpty &&
            _entregas.isEmpty) {
          if (LanApiFeedback.ehFalhaRede(e)) {
            LanApiFeedback.snackRedeMotorista(context, e);
          } else {
            LanApiFeedback.snackAviso(context, e, prefixo: 'Entregas');
          }
        }
      } catch (e) {
        if (mounted &&
            LanApiFeedback.ehFalhaRede(e) &&
            EntregaBaixaSyncService.instance.pendentes.isEmpty &&
            _entregas.isEmpty) {
          LanApiFeedback.snackRedeMotorista(context, e);
        }
      }
    }
    if (!mounted) return;
    final lista = (widget.vendaRepository.listarEntregasModoMotorista(
      _nomeMotorista,
    ) as List)
        .whereType<Venda>()
        .toList();
    if (_usaVendaApi) {
      await _hidratarNomesClientes(lista);
    }
    if (!mounted) return;
    setState(() {
      _entregas = lista;
      _carregando = false;
    });
  }

  void _carregar() {
    unawaited(_carregarAsync(hidratarApi: _usaVendaApi));
  }

  /// No celular o ToOne do cliente nao vem preenchido; busca o cadastro pelo id.
  Future<void> _hidratarNomesClientes(List<Venda> entregas) async {
    final repo = MainMenuDeps.maybeOf(context)?.clienteRepository;
    if (repo is! ClienteApiRepository) return;
    for (final v in entregas) {
      final id = VendaRelacaoSafe.clienteId(v);
      if (id <= 0) continue;
      final jaTem = VendaRelacaoSafe.cliente(v, clienteRepository: repo);
      if (jaTem != null && jaTem.nomeRazao.trim().isNotEmpty) continue;
      try {
        await repo.obterPorIdRemoto(id);
      } catch (_) {}
    }
  }

  int _progressoCarga(Venda v) {
    var n = 0;
    if (v.cargaSeparada) n++;
    if (v.cargaCarregada) n++;
    if (v.cargaSaiu) n++;
    return n;
  }

  Future<void> _navegar(Venda v) async {
    final endereco = enderecoExibicaoRomaneio(v).trim();
    if (endereco.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Nao ha endereco de entrega para abrir no mapa.'),
        ),
      );
      return;
    }
    final ok = await abrirNavegacaoEndereco(endereco);
    if (!mounted) return;
    if (!ok) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Nao foi possivel abrir o mapa. Tente de novo.'),
        ),
      );
    }
  }

  Future<void> _liberarSaida(Venda venda) async {
    if (_busyLiberar) return;
    if (!EntregaFluxoService.podeLiberarSaida(venda)) return;
    final irmaos = EntregaFluxoService.vendasMesmoDespacho(venda, _entregas)
        .where(EntregaFluxoService.podeLiberarSaida)
        .toList();
    final n = irmaos.length;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          title: const Text('Sair para entrega'),
          content: Text(
            n > 1
                ? 'Confirma que a carga já saiu e você está em rota com '
                    '$n pedidos desta viagem?'
                : 'Confirma que a carga do pedido ${venda.numeroOrcamento} '
                    'já saiu e você está em rota?',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancelar'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Sair para entrega'),
            ),
          ],
        );
      },
    );
    if (ok != true || !mounted) return;
    setState(() => _busyLiberar = true);
    try {
      if (_usaVendaApi) {
        await (widget.vendaRepository as VendaApiRepository)
            .liberarSaidaCarretoRemoto(
          vendaId: venda.id,
          usuario: widget.usuarioLogado.login,
        );
      } else {
        widget.vendaRepository.liberarSaidaCarreto(
          venda.id,
          usuario: widget.usuarioLogado.login,
        );
      }
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            n > 1
                ? 'Saída liberada — $n pedidos em rota.'
                : 'Saída liberada — pedido ${venda.numeroOrcamento} em rota.',
          ),
        ),
      );
      await _carregarAsync(hidratarApi: _usaVendaApi);
    } catch (e) {
      if (!mounted) return;
      LanApiFeedback.snackErro(context, e, prefixo: 'Liberar saída');
    } finally {
      if (mounted) setState(() => _busyLiberar = false);
    }
  }

  Future<void> _marcarEntregue(Venda venda) async {
    if (!UsuarioPermissaoHelper.podeRegistrarPodEntrega(widget.usuarioLogado)) {
      return;
    }
    if (_progressoCarga(venda) < 3) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Toque em "Sair para entrega" quando a carga sair da loja, '
            'antes de marcar entregue.',
          ),
        ),
      );
      return;
    }
    if (venda.statusEntrega != 'saiu_entrega' &&
        venda.statusEntrega != 'roteirizada') {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Esta entrega nao esta pronta para baixa no modo motorista.'),
        ),
      );
      return;
    }

    final pod = await showPodEntregaDialog(
      context: context,
      vendaId: venda.id,
      origemMercadoriaRotulo: LojaOrigemMercadoria.rotulo(
        venda.lojaOrigemMercadoria,
      ),
    );
    if (pod == null || !mounted) return;

    if (_usaVendaApi) {
      await _enfileirarBaixaTerminal(venda, pod);
      return;
    }

    try {
      final podFinal = EntregaPodFinalizacao(
        configRepository: widget.configuracoesService?.repository,
      );
      final motivoPod =
          'Recebido por: ${pod.recebidoPor}${pod.fotoPathLocal != null ? ' (com foto no servidor)' : ''}';
      await podFinal.registrarPod(
        vendaRepository: widget.vendaRepository,
        vendaId: venda.id,
        recebidoPor: pod.recebidoPor,
        usuarioLogin: widget.usuarioLogado.login,
        fotoPathLocal: pod.fotoPathLocal ?? '',
        fotoPathServidor: pod.fotoPathServidor ?? '',
        ocorrenciaMotivo: '',
      );
      final statusAnterior = venda.statusEntrega;
      widget.vendaRepository.atualizarStatusEntrega(venda.id, 'entregue');
      widget.vendaRepository.registrarHistoricoStatusEntrega(
        vendaId: venda.id,
        statusAnterior: statusAnterior,
        statusNovo: 'entregue',
        usuario: widget.usuarioLogado.login,
      );
      widget.vendaRepository.registrarOcorrenciaEntrega(
        vendaId: venda.id,
        status: HistoricoEntregaEventos.podEntrega,
        motivo: motivoPod,
        usuario: widget.usuarioLogado.login,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Entrega ${venda.numeroOrcamento} concluida.')),
      );
      _carregar();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Erro: $e'), backgroundColor: Colors.red),
      );
    }
  }

  Future<void> _enfileirarBaixaTerminal(
    Venda venda,
    PodEntregaFormResult pod,
  ) async {
    final item = EntregaBaixaPendente.deVenda(
      venda: venda,
      recebidoPor: pod.recebidoPor,
      usuarioLogin: widget.usuarioLogado.login,
      fotoPathLocal: pod.fotoPathLocal ?? '',
      fotoPathServidor: pod.fotoPathServidor ?? '',
      clienteNome: VendaRelacaoSafe.nomeCliente(venda, fallback: ''),
    );
    try {
      EntregaBaixaSyncService.instance.dispensarFalha(venda.id);
      await EntregaBaixaSyncService.instance.enfileirarETentar(item);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Entrega ${venda.numeroOrcamento} gravada. '
            'Aguardando Sync com o PC servidor.',
          ),
        ),
      );
      setState(() {});
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Erro: $e'), backgroundColor: Colors.red),
      );
    }
  }

  Future<void> _marcarNaoEntregue(Venda venda) async {
    if (!UsuarioPermissaoHelper.podeRegistrarPodEntrega(widget.usuarioLogado)) {
      return;
    }
    if (venda.statusEntrega != 'saiu_entrega' &&
        venda.statusEntrega != 'roteirizada') {
      return;
    }
    final form = await showNaoEntregueDialog(context: context);
    if (form == null || !mounted) return;

    final nomeCliente = VendaRelacaoSafe.nomeCliente(
      venda,
      clienteRepository: MainMenuDeps.maybeOf(context)?.clienteRepository,
      fallback: '',
    );

    if (_usaVendaApi) {
      final item = EntregaBaixaPendente.deNaoEntregue(
        venda: venda,
        usuarioLogin: widget.usuarioLogado.login,
        motivoCodigo: form.motivoCodigo,
        motivoDetalhe: form.detalhe,
        clienteNome: nomeCliente,
        retornouParaLoja: form.retornouParaLoja,
      );
      try {
        EntregaBaixaSyncService.instance.dispensarFalha(venda.id);
        await EntregaBaixaSyncService.instance.enfileirarETentar(item);
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Pedido ${venda.numeroOrcamento}: '
              '${EntregaNaoEntregueMotivo.rotulo(form.motivoCodigo)}. '
              'Aguardando Sync com o PC servidor.',
            ),
          ),
        );
        setState(() {});
      } catch (e) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erro: $e'), backgroundColor: Colors.red),
        );
      }
      return;
    }

    try {
      widget.vendaRepository.registrarNaoEntregueMotorista(
        vendaId: venda.id,
        motivoCodigo: form.motivoCodigo,
        motivoDetalhe: form.detalhe,
        usuarioLogin: widget.usuarioLogado.login,
        statusAnterior: venda.statusEntrega,
        retornouParaLoja: form.retornouParaLoja,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Pedido ${venda.numeroOrcamento}: '
            '${EntregaNaoEntregueMotivo.rotulo(form.motivoCodigo)}.',
          ),
        ),
      );
      _carregar();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Erro: $e'), backgroundColor: Colors.red),
      );
    }
  }

  List<ItemVenda> _itensDaVenda(Venda v) {
    try {
      final raw = widget.vendaRepository.listarItensPorVenda(v.id);
      if (raw is List<ItemVenda>) return raw;
      if (raw is List) {
        return raw.whereType<ItemVenda>().toList();
      }
    } catch (_) {}
    try {
      return List<ItemVenda>.from(v.itens);
    } catch (_) {
      return const [];
    }
  }

  int _qtdItem(ItemVenda item) {
    if (item.quantidadeNoCarreto > 0) return item.quantidadeNoCarreto;
    return item.quantidade;
  }

  Future<int?> _perguntarQtdBuscarNaLoja(Venda venda, ItemVenda item) async {
    final total = BuscarNaLoja.qtdCarga(venda, item);
    if (total <= 0) return null;
    if (total == 1) return 1;
    var escolhido = BuscarNaLoja.clampQuantidade(
      venda,
      item,
      item.quantidadeBuscarNaLoja > 0
          ? item.quantidadeBuscarNaLoja
          : total,
    );
    return showDialog<int>(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          title: const Text('Buscar na nossa loja'),
          content: StatefulBuilder(
            builder: (ctx, setLocal) {
              return Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    'A outra loja não tem a quantidade toda. '
                    'De $total, quantos buscar nesta loja?',
                  ),
                  const SizedBox(height: 12),
                  DropdownButton<int>(
                    isExpanded: true,
                    value: escolhido,
                    items: [
                      for (var n = 1; n <= total; n++)
                        DropdownMenuItem(
                          value: n,
                          child: Text(
                            n >= total ? 'Todos ($total)' : '$n de $total',
                          ),
                        ),
                    ],
                    onChanged: (v) {
                      if (v == null) return;
                      setLocal(() => escolhido = v);
                    },
                  ),
                ],
              );
            },
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancelar'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, escolhido),
              child: const Text('Avisar pátio'),
            ),
          ],
        );
      },
    );
  }

  Future<void> _pedirBuscarNaLoja({
    required Venda venda,
    required ItemVenda item,
  }) async {
    final q = await _perguntarQtdBuscarNaLoja(venda, item);
    if (q == null || q <= 0) return;
    await _atualizarBuscarNaLoja(
      venda: venda,
      item: item,
      acao: BuscarNaLoja.solicitar,
      quantidade: q,
    );
  }

  Future<void> _cancelarBuscarNaLoja({
    required Venda venda,
    required ItemVenda item,
  }) async {
    final separado = BuscarNaLoja.ehSeparado(item.buscarNaLojaStatus);
    if (separado) {
      final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Chegou na outra loja?'),
          content: const Text(
            'O pátio já aceitou separar neste estoque. '
            'Desistir volta a origem para a outra loja. '
            'Se o carro já tiver saído, o físico desta loja é devolvido. '
            'Deixe o material de volta na prateleira.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Manter separado'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Desistir'),
            ),
          ],
        ),
      );
      if (ok != true) return;
    }
    await _atualizarBuscarNaLoja(
      venda: venda,
      item: item,
      acao: BuscarNaLoja.cancelar,
    );
  }

  Future<void> _atualizarBuscarNaLoja({
    required Venda venda,
    required ItemVenda item,
    required String acao,
    int? quantidade,
  }) async {
    if (_busyBuscar) return;
    setState(() => _busyBuscar = true);
    try {
      final eraSeparado = BuscarNaLoja.ehSeparado(item.buscarNaLojaStatus);
      final qPorItem = acao == BuscarNaLoja.solicitar && quantidade != null
          ? {item.id: quantidade}
          : null;
      if (_usaVendaApi) {
        await (widget.vendaRepository as VendaApiRepository)
            .atualizarBuscarNaLojaRemoto(
          vendaId: venda.id,
          acao: acao,
          itemIds: [item.id],
          usuario: widget.usuarioLogado.login,
          quantidadePorItem: qPorItem,
        );
      } else {
        widget.vendaRepository.atualizarBuscarNaLoja(
          venda.id,
          acao: acao,
          itemIds: [item.id],
          usuario: widget.usuarioLogado.login,
          quantidadePorItem: qPorItem,
        );
      }
      if (!mounted) return;
      final total = BuscarNaLoja.qtdCarga(venda, item);
      final rotuloQtd = quantidade == null || quantidade >= total
          ? item.nomeProduto
          : '$quantidade de $total ${item.nomeProduto}';
      final msg = acao == BuscarNaLoja.solicitar
          ? 'Pátio avisado: buscar $rotuloQtd nesta loja.'
          : eraSeparado
              ? 'Desistiu de buscar nesta loja. Devolva o material à prateleira.'
              : 'Pedido de busca cancelado.';
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
      await _carregarAsync(hidratarApi: _usaVendaApi);
    } catch (e) {
      if (!mounted) return;
      LanApiFeedback.snackErro(context, e, prefixo: 'Buscar na loja');
    } finally {
      if (mounted) setState(() => _busyBuscar = false);
    }
  }

  Widget _linhaItemCarga(Venda venda, ItemVenda item) {
    final solicitado = BuscarNaLoja.ehSolicitado(item.buscarNaLojaStatus);
    final separado = BuscarNaLoja.ehSeparado(item.buscarNaLojaStatus);
    final podePedir = BuscarNaLoja.podeSolicitarItem(venda, item);
    final podeCancelar = BuscarNaLoja.podeCancelarItem(venda, item);
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: 36,
                child: Text(
                  '${_qtdItem(item)}x',
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
              ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      item.nomeProduto,
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                    if (solicitado)
                      Text(
                        'Aguardando o pátio: buscar '
                        '${BuscarNaLoja.rotuloQuantidade(venda, item)} nesta loja',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: Colors.orange.shade800,
                              fontWeight: FontWeight.w700,
                            ),
                      ),
                    if (separado)
                      Text(
                        BuscarNaLoja.quantidadeEfetiva(venda, item) <
                                BuscarNaLoja.qtdCarga(venda, item)
                            ? 'Pátio separa ${BuscarNaLoja.rotuloQuantidade(venda, item)} nesta loja'
                            : 'Pátio vai separar / já separado nesta loja',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: Colors.green.shade800,
                              fontWeight: FontWeight.w600,
                            ),
                      ),
                  ],
                ),
              ),
            ],
          ),
          if (podePedir)
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton(
                onPressed: _busyBuscar
                    ? null
                    : () => _pedirBuscarNaLoja(venda: venda, item: item),
                child: Text(
                  solicitado
                      ? 'Alterar quantidade — buscar na nossa loja'
                      : 'Não tem lá — buscar na nossa loja',
                ),
              ),
            ),
          if (podeCancelar)
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton(
                onPressed: _busyBuscar
                    ? null
                    : () => _cancelarBuscarNaLoja(venda: venda, item: item),
                child: Text(
                  separado
                      ? 'Chegou lá — não preciso desta loja'
                      : 'Cancelar busca nesta loja',
                ),
              ),
            ),
        ],
      ),
    );
  }

  Future<void> _abrirUri(String uri) async {
    final ok = await abrirUrlExterna(uri);
    if (!mounted) return;
    if (!ok) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Nao foi possivel abrir o aplicativo.')),
      );
    }
  }

  Future<void> _abrirRotaCompleta(List<Venda> paradas) async {
    final ok = await abrirMapaRotaParadas(paradas);
    if (!mounted) return;
    if (!ok) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Nao foi possivel abrir o mapa da rota.')),
      );
    }
  }

  String _rotuloStatus(String s) {
    switch (s) {
      case 'roteirizada':
        return 'No patio';
      case 'saiu_entrega':
        return 'Saiu para entrega';
      case 'entregue_complemento_pendente':
        return 'Complemento pendente';
      default:
        return s;
    }
  }

  @override
  Widget build(BuildContext context) {
    final fmt = DateFormat('dd/MM/yyyy HH:mm');
    final sync = EntregaBaixaSyncService.instance;
    final linhas = EntregaBaixaMotoristaVisao.montar(
      entregasAtivas: _entregas,
      pendentes: sync.pendentes,
      sincronizadasRecentes: sync.sincronizadasRecentes,
      recusadas: sync.falhas,
    );
    final paradas = RotaMotorista.montar(linhas);
    final qtdRota = RotaMotorista.totalPendentes(paradas);
    final vendasRota = RotaMotorista.vendasParaMapa(paradas);
    final clienteRepo = MainMenuDeps.maybeOf(context)?.clienteRepository;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Modo motorista'),
        actions: [
          IconButton(
            tooltip: 'Atualizar',
            onPressed: _carregar,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: _carregando
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: () async {
                unawaited(EntregaBaixaSyncService.instance.processarFila());
                await _carregarAsync();
              },
              child: ListView(
                padding: const EdgeInsets.all(12),
                children: [
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            widget.usuarioLogado.nome,
                            style: Theme.of(context)
                                .textTheme
                                .titleMedium
                                ?.copyWith(fontWeight: FontWeight.bold),
                          ),
                          Text('Motorista: $_nomeMotorista'),
                          Text(
                            '$qtdRota entrega(s) em rota',
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                          if (vendasRota.length > 1) ...[
                            const SizedBox(height: 8),
                            Align(
                              alignment: Alignment.centerLeft,
                              child: FilledButton.tonalIcon(
                                onPressed: () => _abrirRotaCompleta(vendasRota),
                                icon: const Icon(Icons.alt_route, size: 18),
                                label: Text(
                                  'Ver rota das ${vendasRota.length} paradas',
                                ),
                              ),
                            ),
                          ],
                          if (sync.pendentes.isNotEmpty)
                            Text(
                              '${sync.pendentes.length} aguardando sync',
                              style: Theme.of(context)
                                  .textTheme
                                  .bodySmall
                                  ?.copyWith(
                                    color: Colors.orange.shade800,
                                    fontWeight: FontWeight.w600,
                                  ),
                            ),
                          if (sync.falhas.isNotEmpty)
                            Text(
                              '${sync.falhas.length} baixa(s) recusada(s) pela loja',
                              style: Theme.of(context)
                                  .textTheme
                                  .bodySmall
                                  ?.copyWith(
                                    color: Colors.red.shade800,
                                    fontWeight: FontWeight.w700,
                                  ),
                            ),
                        ],
                      ),
                    ),
                  ),
                  if (linhas.isEmpty)
                    const Padding(
                      padding: EdgeInsets.all(32),
                      child: Center(
                        child: Text(
                          'Nenhuma entrega ativa para voce no momento.',
                        ),
                      ),
                    ),
                  ...paradas.map((parada) {
                    final linha = parada.linha;
                    final v = linha.venda;
                    final prog = _progressoCarga(v);
                    final atrasada = EntregaFiltroUtil.ehAtrasada(v);
                    final pendenteOuSync =
                        linha.aguardandoSync || linha.sincronizada;
                    final nomeCliente = linha.clienteNome.trim().isNotEmpty
                        ? linha.clienteNome.trim()
                        : VendaRelacaoSafe.nomeCliente(
                            v,
                            clienteRepository: clienteRepo,
                            fallback: 'Cliente',
                          );
                    final cliente = VendaRelacaoSafe.cliente(
                      v,
                      clienteRepository: clienteRepo,
                    );
                    final telUri = EntregaContatoMotorista.uriTelefone(
                      cliente?.telefone ?? '',
                    );
                    final waUri = EntregaContatoMotorista.uriWhatsApp(
                      (cliente?.whatsapp.trim().isNotEmpty == true)
                          ? cliente!.whatsapp
                          : (cliente?.telefone ?? ''),
                    );
                    final obs = EntregaObservacaoMotorista.visivel(
                      v.observacaoEntrega,
                    );
                    final itens = _itensDaVenda(v)
                        .where((i) => _qtdItem(i) > 0)
                        .toList();
                    final podeAgir = !pendenteOuSync &&
                        prog >= 3 &&
                        (v.statusEntrega == 'saiu_entrega' ||
                            v.statusEntrega == 'roteirizada');
                    final podeLiberar = !pendenteOuSync &&
                        !_busyLiberar &&
                        EntregaFluxoService.podeLiberarSaida(v);
                    final scheme = Theme.of(context).colorScheme;
                    return Card(
                      margin: const EdgeInsets.only(bottom: 10),
                      shape: parada.destacarProxima
                          ? RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                              side: BorderSide(
                                color: scheme.primary,
                                width: 2,
                              ),
                            )
                          : null,
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            if (parada.mostrarSequencia)
                              Padding(
                                padding: const EdgeInsets.only(bottom: 8),
                                child: Row(
                                  children: [
                                    _NumeroParada(
                                      numero: parada.posicao,
                                      proxima: parada.destacarProxima,
                                    ),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: Text(
                                        parada.rotulo,
                                        style: Theme.of(context)
                                            .textTheme
                                            .labelLarge
                                            ?.copyWith(
                                              color: scheme.onSurfaceVariant,
                                              fontWeight: FontWeight.w600,
                                            ),
                                      ),
                                    ),
                                    if (parada.destacarProxima)
                                      Container(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 10,
                                          vertical: 4,
                                        ),
                                        decoration: BoxDecoration(
                                          color: scheme.primary,
                                          borderRadius:
                                              BorderRadius.circular(999),
                                        ),
                                        child: Text(
                                          'PROXIMA',
                                          style: TextStyle(
                                            color: scheme.onPrimary,
                                            fontWeight: FontWeight.w800,
                                            fontSize: 11,
                                            letterSpacing: 0.5,
                                          ),
                                        ),
                                      ),
                                  ],
                                ),
                              ),
                            Text(
                              'Pedido ${v.numeroOrcamento}',
                              style: const TextStyle(
                                fontWeight: FontWeight.w700,
                                fontSize: 16,
                              ),
                            ),
                            Text(nomeCliente),
                            const SizedBox(height: 4),
                            Text(v.enderecoEntrega),
                            if (telUri != null || waUri != null) ...[
                              const SizedBox(height: 4),
                              Wrap(
                                spacing: 8,
                                children: [
                                  if (telUri != null)
                                    TextButton.icon(
                                      onPressed: () => _abrirUri(telUri),
                                      icon: const Icon(Icons.phone_outlined, size: 18),
                                      label: const Text('Ligar'),
                                    ),
                                  if (waUri != null)
                                    TextButton.icon(
                                      onPressed: () => _abrirUri(waUri),
                                      icon: const Icon(Icons.chat_outlined, size: 18),
                                      label: const Text('WhatsApp'),
                                    ),
                                ],
                              ),
                            ],
                            if (obs.isNotEmpty) ...[
                              const SizedBox(height: 4),
                              Text(
                                obs,
                                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                                      fontStyle: FontStyle.italic,
                                    ),
                              ),
                            ],
                            if (itens.isNotEmpty)
                              ExpansionTile(
                                tilePadding: EdgeInsets.zero,
                                dense: true,
                                initiallyExpanded: itens.any(
                                  (i) =>
                                      BuscarNaLoja.podeSolicitarItem(v, i) ||
                                      BuscarNaLoja.ehSolicitado(
                                        i.buscarNaLojaStatus,
                                      ),
                                ),
                                title: Text(
                                  'Itens (${itens.length})',
                                  style: Theme.of(context).textTheme.titleSmall,
                                ),
                                children: [
                                  for (final item in itens)
                                    _linhaItemCarga(v, item),
                                ],
                              ),
                            Wrap(
                              spacing: 8,
                              runSpacing: 4,
                              children: [
                                if (linha.rotuloStatusSync.isNotEmpty)
                                  Chip(
                                    label: Text(linha.rotuloStatusSync),
                                    visualDensity: VisualDensity.compact,
                                    backgroundColor: linha.sincronizada
                                        ? Colors.green.shade50
                                        : linha.recusada
                                            ? Colors.red.shade50
                                            : Colors.orange.shade50,
                                  )
                                else
                                  Chip(
                                    label: Text(_rotuloStatus(v.statusEntrega)),
                                    visualDensity: VisualDensity.compact,
                                  ),
                                Chip(
                                  label: Text('Carga $prog/3'),
                                  visualDensity: VisualDensity.compact,
                                ),
                                if (atrasada && !pendenteOuSync)
                                  Chip(
                                    label: const Text('Atrasada'),
                                    backgroundColor: Colors.red.shade50,
                                    visualDensity: VisualDensity.compact,
                                  ),
                              ],
                            ),
                            if (linha.recusada)
                              Align(
                                alignment: Alignment.centerLeft,
                                child: TextButton(
                                  onPressed: () => EntregaBaixaSyncService
                                      .instance
                                      .dispensarFalha(v.id),
                                  child: const Text('Entendi'),
                                ),
                              ),
                            if (v.dataEntregaMarcada != null)
                              Text(
                                'Data marcada: ${fmt.format(v.dataEntregaMarcada!.toLocal())}',
                                style: Theme.of(context).textTheme.bodySmall,
                              ),
                            if (v.lojaOrigemMercadoria.trim().isNotEmpty &&
                                !LojaOrigemMercadoria.ehLocal(
                                  v.lojaOrigemMercadoria,
                                ))
                              Padding(
                                padding: const EdgeInsets.only(top: 4),
                                child: Text(
                                  'Origem da mercadoria: ${LojaOrigemMercadoria.rotulo(v.lojaOrigemMercadoria)}',
                                  style: Theme.of(context).textTheme.bodySmall,
                                ),
                              ),
                            const SizedBox(height: 8),
                            if (podeLiberar) ...[
                              FilledButton.icon(
                                onPressed: () => _liberarSaida(v),
                                icon: const Icon(Icons.logout),
                                label: const Text('Sair para entrega'),
                              ),
                              const SizedBox(height: 8),
                            ],
                            Row(
                              children: [
                                Expanded(
                                  child: OutlinedButton.icon(
                                    onPressed: () => _navegar(v),
                                    icon: const Icon(Icons.directions_outlined),
                                    label: const Text('Navegar'),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: FilledButton.icon(
                                    onPressed: podeAgir
                                        ? () => _marcarEntregue(v)
                                        : null,
                                    icon: const Icon(
                                      Icons.check_circle_outline,
                                    ),
                                    label: Text(
                                      linha.aguardandoSync
                                          ? 'Aguardando'
                                          : linha.sincronizada
                                              ? (linha.naoEntregue
                                                  ? 'Nao entregue'
                                                  : 'Sincronizada')
                                              : 'Entregue',
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            if (!pendenteOuSync) ...[
                              const SizedBox(height: 8),
                              OutlinedButton.icon(
                                onPressed: podeAgir
                                    ? () => _marcarNaoEntregue(v)
                                    : null,
                                icon: const Icon(Icons.report_problem_outlined),
                                label: const Text('Nao entregue'),
                              ),
                            ],
                          ],
                        ),
                      ),
                    );
                  }),
                ],
              ),
            ),
    );
  }
}

class _NumeroParada extends StatelessWidget {
  const _NumeroParada({required this.numero, required this.proxima});

  final int numero;
  final bool proxima;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      width: 30,
      height: 30,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: proxima ? scheme.primary : scheme.surfaceContainerHighest,
        border: Border.all(
          color: proxima
              ? scheme.primary
              : scheme.outlineVariant.withValues(alpha: 0.8),
        ),
      ),
      child: Text(
        '$numero',
        style: TextStyle(
          fontWeight: FontWeight.w800,
          color: proxima ? scheme.onPrimary : scheme.onSurfaceVariant,
        ),
      ),
    );
  }
}
