import 'dart:async';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:url_launcher/url_launcher.dart';

import '../data/conferencia_carga_repository.dart';
import '../data/motorista_repository.dart';
import '../data/produto_repository.dart';
import '../data/venda_repository.dart';
import '../domain/entrega_filtro_util.dart';
import '../domain/entrega_venda_helper.dart';
import '../domain/filtro_listagem_entregas.dart';
import '../domain/complemento_entrega_codec.dart';
import '../model/historico_entrega.dart';
import '../model/item_venda.dart';
import '../model/venda.dart';
import 'entregas/entregas_barra_compacta.dart';
import 'entregas/filtros_entrega_sheet.dart';
import 'entregas/logistica_entregas.dart';
import 'entregas/planejamento_entrega_dia.dart';
import 'entregas/agrupar_viagem_dialog.dart';
import 'entregas/entregas_montagem_callbacks.dart';
import 'entregas/montagem_entrega_viagem.dart';
import 'entregas/painel_montagem_entregas.dart';
import 'entregas/selecionar_motorista_dialog.dart';
import 'entregas/conferencia_carga_consolidada_lista.dart';
import 'entregas/romaneio_carga_consolidada.dart';
import 'entregas/romaneio_pdf.dart';
import 'entregas/romaneio_relatorios.dart';
import '../data/app_config_repository.dart';
import '../data/sync/sync_refresh_hub.dart';
import '../domain/entrega_pod_regra.dart';
import '../services/entrega_pod_finalizacao.dart';
import '../services/entrega_pod_prefetch_service.dart';
import 'entregas/entrega_pod_chip.dart';
import 'entregas/entrega_pod_foto_panel.dart';
import 'entregas/pod_entrega_dialog.dart';
import 'registrar_devolucao_troca_page.dart';

/// Filtro rapido pelos contadores de resumo (atrasadas / pendentes hoje).
enum _FiltroResumoEntregas { nenhum, atrasadas, pendentesHoje }

const _kMenuMarcarDataEntrega = '__acao_marcar_data_entrega__';
const _kMenuLimparDataEntrega = '__acao_limpar_data_entrega__';
const _kMenuDevolucaoPosCarreto = '__acao_devolucao_pos_carreto__';
const _kMenuRetiradaLojaCarreto = '__acao_retirada_loja_carreto__';

class EntregasPage extends StatefulWidget {
  const EntregasPage({
    super.key,
    required this.vendaRepository,
    required this.produtoRepository,
    required this.motoristaRepository,
    required this.usuarioAtual,
    required this.podeGerenciarStatusEntrega,
    required this.podeRegistrarPodEntrega,
    required this.podeRegistrarDevolucaoTrocaSemSenha,
    this.appConfigRepository,
  });

  final VendaRepository vendaRepository;
  final ProdutoRepository produtoRepository;
  final MotoristaRepository motoristaRepository;
  final AppConfigRepository? appConfigRepository;
  final String usuarioAtual;
  final bool podeGerenciarStatusEntrega;
  final bool podeRegistrarPodEntrega;
  /// Mesmo criterio da listagem de vendas (admin / financeiro / auditoria de caixa).
  final bool podeRegistrarDevolucaoTrocaSemSenha;

  @override
  State<EntregasPage> createState() => _EntregasPageState();
}

class _EntregasPageState extends State<EntregasPage> {
  late final ConferenciaCargaRepository _conferenciaCargaRepository =
      ConferenciaCargaRepository(widget.vendaRepository.objectBox);

  final NumberFormat _currency = NumberFormat('#,##0.00', 'pt_BR');
  final _bairroController = TextEditingController();
  final _numeroNotaController = TextEditingController();
  final _statuses = const [
    'todos',
    'pendente',
    'roteirizada',
    'saiu_entrega',
    'entregue_complemento_pendente',
    'entregue',
    'reagendada',
    'cancelada',
  ];

  List<Venda> _entregas = [];
  int _contagemAtrasadasCache = 0;
  int _contagemPendentesHojeCache = 0;
  String _statusSelecionado = 'todos';
  String _filtroMotorista = 'todos';
  String _filtroVendedor = 'todos';
  List<String> _vendedoresDisponiveis = const [];
  String _agrupamento = 'bairro'; // bairro | motorista
  String _filtroDataMarcada = 'todos'; // todos | hoje | amanha | sem_data
  DateTime? _inicio;
  DateTime? _fim;
  bool _modoAgruparMesmoCarro = false;
  final Set<int> _idsEntregasSelecionadas = {};

  /// Incrementado ao usar "Limpar tudo" para remontar dropdowns (initialValue vale apenas no primeiro build).
  int _filtrosDropdownNonce = 0;
  _FiltroResumoEntregas _filtroResumoLista = _FiltroResumoEntregas.nenhum;

  /// Chave igual a [resumoPorDia] (`dd/MM/yyyy` ou `Sem data marcada`); filtra so a lista.
  String? _chaveDiaPlanejamentoSelecionado;

  bool _proximosDiasPlanejamentoExpandido = false;

  final ScrollController _kanbanHScrollController = ScrollController();

  void _selecionarDiaPlanejamento(String? chave) {
    setState(() => _chaveDiaPlanejamentoSelecionado = chave);
  }

  int _contagemFiltrosAtivos() {
    return contarFiltrosEntregaAtivos(
      status: _statusSelecionado,
      motorista: _filtroMotorista,
      vendedor: _filtroVendedor,
      agrupamento: _agrupamento,
      dataMarcada: _filtroDataMarcada,
      bairro: _bairroController.text,
      numeroNota: _numeroNotaController.text,
      inicio: _inicio,
      fim: _fim,
    );
  }

  String _nomeMotoristaFiltroExibicao() {
    if (_filtroMotorista == 'todos') return 'Todos';
    final m = widget.motoristaRepository.listarAtivos().where(
          (x) => x.nome.trim().toLowerCase() == _filtroMotorista,
        );
    return m.isNotEmpty ? m.first.nome : _filtroMotorista;
  }

  String _nomeVendedorFiltroExibicao() {
    if (_filtroVendedor == 'todos') return 'Todos';
    final v = _vendedoresDisponiveis.where(
      (n) => n.toLowerCase() == _filtroVendedor,
    );
    return v.isNotEmpty ? v.first : _filtroVendedor;
  }

  Future<void> _abrirFiltrosEntrega() async {
    final resumos = resumosFiltrosEntregaAtivos(
      status: _statusSelecionado,
      rotuloStatus: _rotuloStatusFiltro,
      motorista: _filtroMotorista,
      nomeMotoristaExibicao: _nomeMotoristaFiltroExibicao(),
      vendedor: _filtroVendedor,
      nomeVendedorExibicao: _nomeVendedorFiltroExibicao(),
      agrupamento: _agrupamento,
      dataMarcada: _filtroDataMarcada,
      bairro: _bairroController.text,
      numeroNota: _numeroNotaController.text,
      rotuloPeriodo: _rotuloPeriodoSelecionado(),
    );
    if (!mounted) return;
    await showFiltrosEntregaSheet(
      context: context,
      filtrosDropdownNonce: _filtrosDropdownNonce,
      statuses: _statuses,
      rotuloStatus: _rotuloStatusFiltro,
      statusSelecionado: _statusSelecionado,
      onStatus: (v) {
        setState(() => _statusSelecionado = v);
        _carregarEntregas();
      },
      filtroMotorista: _filtroMotorista,
      motoristasAtivos: widget.motoristaRepository.listarAtivos(),
      onMotorista: (v) {
        setState(() => _filtroMotorista = v);
        _carregarEntregas();
      },
      filtroVendedor: _filtroVendedor,
      vendedoresDisponiveis: _vendedoresDisponiveis,
      onVendedor: (v) {
        setState(() => _filtroVendedor = v);
        _carregarEntregas();
      },
      agrupamento: _agrupamento,
      onAgrupamento: (v) => setState(() => _agrupamento = v),
      filtroDataMarcada: _filtroDataMarcada,
      onDataMarcada: (v) {
        setState(() => _filtroDataMarcada = v);
        _carregarEntregas();
      },
      numeroNotaController: _numeroNotaController,
      bairroController: _bairroController,
      onAplicarTexto: _carregarEntregas,
      onLimparTudo: _redefinirFiltrosPadrao,
      onPeriodoHoje: _aplicarPeriodoMarcadasParaHoje,
      onPeriodoPersonalizado: _selecionarPeriodoPersonalizado,
      rotuloPeriodo: _rotuloPeriodoSelecionado(),
      resumosAtivos: resumos,
    );
  }

  Future<void> _abrirSeletorPlanejamentoDia(
    Map<String, int> resumoPorDia,
  ) async {
    final escolha = await showSeletorPlanejamentoEntregaDia(
      context: context,
      resumoPorDia: resumoPorDia,
      chaveInicial: _chaveDiaPlanejamentoSelecionado,
    );
    if (!mounted || escolha == null) return;
    _selecionarDiaPlanejamento(escolha.isEmpty ? null : escolha);
  }

  @override
  void initState() {
    super.initState();
    _inicio = null;
    _fim = null;
    _chaveDiaPlanejamentoSelecionado =
        PlanejamentoEntregaDia.chaveDeDateTime(DateTime.now());
    SyncRefreshHub.instance.addListener(_onSyncHubNotificado);
    _carregarEntregas();
    unawaited(_prefetchPodFotos());
  }

  void _onSyncHubNotificado() {
    if (!mounted) return;
    _carregarEntregas();
    unawaited(_prefetchPodFotos());
  }

  Future<void> _prefetchPodFotos() async {
    final repo = widget.appConfigRepository;
    if (repo == null || _entregas.isEmpty) return;
    await EntregaPodPrefetchService(configRepository: repo)
        .prefetchLista(_entregas);
  }

  void _copiarCamposPod(Venda destino, Venda origem) {
    destino.podRecebidoPor = origem.podRecebidoPor;
    destino.podRegistradoPor = origem.podRegistradoPor;
    destino.podRegistradoEm = origem.podRegistradoEm;
    destino.podFotoPath = origem.podFotoPath;
    destino.podFotoPathServidor = origem.podFotoPathServidor;
  }

  Future<bool> _editarPodEntrega(Venda venda) async {
    if (!widget.podeRegistrarPodEntrega) return false;
    final anterior = venda.podRecebidoPor.trim();
    final pod = await showPodEntregaDialog(
      context: context,
      vendaId: venda.id,
      recebidoPorInicial: anterior,
      modoEdicao: true,
    );
    if (pod == null) return false;
    try {
      final podFinal = EntregaPodFinalizacao(
        configRepository: widget.appConfigRepository,
      );
      await podFinal.registrarPod(
        vendaRepository: widget.vendaRepository,
        vendaId: venda.id,
        recebidoPor: pod.recebidoPor,
        usuarioLogin: widget.usuarioAtual,
        fotoPathLocal: pod.fotoPathLocal ?? venda.podFotoPath,
        fotoPathServidor: pod.fotoPathServidor ?? venda.podFotoPathServidor,
      );
      final atualizada = widget.vendaRepository.obterPorId(venda.id);
      if (atualizada != null) _copiarCamposPod(venda, atualizada);
      widget.vendaRepository.registrarOcorrenciaEntrega(
        vendaId: venda.id,
        status: HistoricoEntregaEventos.podEntrega,
        motivo: anterior.isEmpty
            ? 'POD registrado — recebido por: ${pod.recebidoPor}'
            : 'POD alterado — recebido por: ${pod.recebidoPor} (antes: $anterior)',
        usuario: widget.usuarioAtual,
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Prova de entrega atualizada.')),
        );
      }
      return true;
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erro ao alterar POD: $e')),
        );
      }
      return false;
    }
  }

  @override
  void dispose() {
    SyncRefreshHub.instance.removeListener(_onSyncHubNotificado);
    _kanbanHScrollController.dispose();
    _bairroController.dispose();
    _numeroNotaController.dispose();
    super.dispose();
  }

  String _formatarMoeda(double valor) => 'R\$ ${_currency.format(valor)}';

  bool _vendaUsaItensCarretoMigrado(Venda v) {
    return EntregaVendaHelper.vendaTemItensMigradosRetiradaParaCarreto(v);
  }

  /// Carreto nativo (reserva ate a saida), nao migrado de retirada futura.
  bool _vendaCarretoReservaNativaSemMigracao(Venda v) {
    return EntregaVendaHelper.vendaTemItensCarreto(v) &&
        v.carretoReservaAteSaida &&
        !_vendaUsaItensCarretoMigrado(v);
  }

  bool _podeRegistrarRetiradaLojaAntesSaidaCarreto(Venda v) {
    return EntregaVendaHelper.vendaPermiteRetiradaLojaCarretoAntesSaida(v) &&
        _vendaCarretoReservaNativaSemMigracao(v);
  }

  int _quantidadeExibicaoEntrega(Venda v, ItemVenda item) {
    if (!EntregaVendaHelper.itemEntraNaCargaEntrega(v, item)) {
      return 0;
    }
    if (_vendaUsaItensCarretoMigrado(v)) {
      return item.quantidadeParaExibicaoEntrega(true);
    }
    if (_vendaCarretoReservaNativaSemMigracao(v)) {
      return item.quantidadeParaExibicaoEntrega(
        false,
        carretoReservaNativoAntesSaida: true,
      );
    }
    return item.quantidadeParaExibicaoEntrega(false);
  }

  double _subtotalExibicaoEntrega(Venda v, ItemVenda item) {
    return _quantidadeExibicaoEntrega(v, item) * item.precoUnitario;
  }

  /// Mesma base da listagem de vendas (venda finalizada, itens ainda devolviveis).
  bool _podeRegistrarDevolucaoTrocaBase(Venda v) {
    if (v.cancelada || v.status != 'finalizada') return false;
    if (v.vendaOrigemFreteRetiradaId > 0) return false;
    return v.itens.any((i) => i.quantidade - i.quantidadeDevolvida > 0);
  }

  /// Carreto com checklist "Saiu" e entrega em andamento ou concluida (mercadoria pode voltar).
  bool _podeDevolucaoPosCarretoNaEntrega(Venda v) {
    if (!_podeRegistrarDevolucaoTrocaBase(v)) return false;
    if (!EntregaVendaHelper.vendaTemItensCarreto(v)) return false;
    if (!v.cargaSaiu) return false;
    return v.statusEntrega == 'saiu_entrega' ||
        v.statusEntrega == 'entregue' ||
        v.statusEntrega == 'entregue_complemento_pendente';
  }

  Future<void> _abrirRegistrarDevolucaoPosCarreto(Venda vIn) async {
    final v = widget.vendaRepository.obterPorId(vIn.id) ?? vIn;
    if (!_podeDevolucaoPosCarretoNaEntrega(v)) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Neste atalho: carreto com carga que ja saiu e quantidade ainda '
            'devolvivel. Nos demais casos use Vendas > Listagem > Devolucao / troca.',
          ),
        ),
      );
      return;
    }
    final ok = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => RegistrarDevolucaoTrocaPage(
          vendaRepository: widget.vendaRepository,
          produtoRepository: widget.produtoRepository,
          vendaId: v.id,
          usuarioAtual: widget.usuarioAtual,
          podeRegistrarSemSenha: widget.podeRegistrarDevolucaoTrocaSemSenha,
        ),
      ),
    );
    if (!mounted) return;
    if (ok == true) {
      _carregarEntregas();
    }
  }

  Future<void> _abrirRegistrarRetiradaLojaCarretoAntesSaida(Venda vIn) async {
    if (!widget.podeGerenciarStatusEntrega) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(_mensagemSemPermissaoStatus())));
      return;
    }
    final v = widget.vendaRepository.obterPorId(vIn.id) ?? vIn;
    if (!_podeRegistrarRetiradaLojaAntesSaidaCarreto(v)) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Disponivel somente para carreto com reserva ate a saida, '
            'sem migracao de retirada futura, com checklist "Saiu" ainda desmarcado '
            'e com quantidade restante para o carro.',
          ),
        ),
      );
      return;
    }
    if (!mounted) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => _DialogRetiradaLojaCarretoAntesSaida(
        venda: v,
        vendaRepository: widget.vendaRepository,
        usuario: widget.usuarioAtual,
      ),
    );
    if (!mounted) return;
    if (ok == true) {
      _carregarEntregas();
    }
  }

  String _rotuloStatusEntrega(String status) {
    switch (status) {
      case HistoricoEntregaEventos.devolucao:
        return 'Devolucao registrada';
      case HistoricoEntregaEventos.troca:
        return 'Troca registrada';
      case HistoricoEntregaEventos.retiradaFutura:
        return 'Retirada futura';
      case HistoricoEntregaEventos.retiradaLojaPreSaida:
        return 'Retirada na loja (pre-saida)';
      case HistoricoEntregaEventos.complementoPendente:
        return 'Complemento pendente';
      case 'pendente':
        return 'Pendente';
      case 'roteirizada':
        return 'Roteirizada';
      case 'saiu_entrega':
        return 'Saiu para entrega';
      case 'entregue_complemento_pendente':
        return 'Complemento pendente';
      case 'entregue':
        return 'Entregue';
      case 'reagendada':
        return 'Reagendada';
      case 'cancelada':
        return 'Cancelada';
      default:
        return 'Nao aplicavel';
    }
  }

  String _rotuloStatusFiltro(String status) {
    if (status == 'todos') return 'Todos';
    if (status == 'entregue_complemento_pendente') {
      return 'Compl. pendente';
    }
    return _rotuloStatusEntrega(status);
  }

  Color _corStatus(ColorScheme scheme, String status) {
    switch (status) {
      case 'entregue':
        return Colors.green.shade700;
      case 'entregue_complemento_pendente':
        return Colors.deepOrange.shade800;
      case 'saiu_entrega':
        return Colors.blue.shade700;
      case 'reagendada':
        return Colors.orange.shade700;
      case 'cancelada':
        return scheme.error;
      case 'roteirizada':
        return Colors.purple.shade700;
      case 'pendente':
      default:
        return scheme.primary;
    }
  }

  int _progressoCarga(Venda venda) {
    var total = 0;
    if (venda.cargaSeparada) total++;
    if (venda.cargaCarregada) total++;
    if (venda.cargaSaiu) total++;
    return total;
  }

  Color _corProgressoCarga(BuildContext context, int progresso) {
    final scheme = Theme.of(context).colorScheme;
    if (progresso >= 3) return Colors.green.shade700;
    if (progresso >= 1) return Colors.amber.shade800;
    return scheme.outline;
  }

  bool _vendaNaChaveDiaPlanejamento(
    Venda venda,
    String chaveDia,
    DateFormat dataMarcadaFmt,
  ) {
    if (chaveDia == 'Sem data marcada') {
      return venda.dataEntregaMarcada == null;
    }
    final marcada = venda.dataEntregaMarcada?.toLocal();
    if (marcada == null) return false;
    return dataMarcadaFmt.format(marcada) == chaveDia;
  }

  FiltroListagemEntregas _montarFiltroEntregas({
    required bool usarPeriodoVendaNaLista,
    bool paraContagemResumo = false,
  }) {
    final usarPeriodo = paraContagemResumo
        ? false
        : (_filtroResumoLista == _FiltroResumoEntregas.nenhum &&
            usarPeriodoVendaNaLista);
    return FiltroListagemEntregas(
      statusEntrega: _statusSelecionado,
      bairroTermo: _bairroController.text,
      inicio: usarPeriodo ? _inicio : null,
      fim: usarPeriodo ? _fim : null,
      filtroDataMarcada: _filtroDataMarcada,
      filtroMotorista: _filtroMotorista,
      filtroVendedor: _filtroVendedor,
      numeroNota: _numeroNotaController.text,
      apenasAtrasadas:
          !paraContagemResumo &&
          _filtroResumoLista == _FiltroResumoEntregas.atrasadas,
      apenasPendentesHoje:
          !paraContagemResumo &&
          _filtroResumoLista == _FiltroResumoEntregas.pendentesHoje,
    );
  }

  void _carregarEntregas() {
    final filtroLista = _montarFiltroEntregas(usarPeriodoVendaNaLista: true);
    final filtroContagem = _montarFiltroEntregas(
      usarPeriodoVendaNaLista: false,
      paraContagemResumo: true,
    );
    final resultado = widget.vendaRepository.carregarListagemEntregasComResumo(
      filtroLista: filtroLista,
      filtroContagem: filtroContagem,
    );
    final entregas = resultado.entregas;
    final vendedoresDisponiveis =
        (entregas
            .map(_nomeVendedor)
            .map((n) => n.trim())
            .where((n) => n.isNotEmpty)
            .toSet()
            .toList()
          ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase())));
    setState(() {
      _entregas = entregas;
      _contagemAtrasadasCache = resultado.atrasadas;
      _contagemPendentesHojeCache = resultado.pendentesHoje;
      _vendedoresDisponiveis = vendedoresDisponiveis;
      if (_chaveDiaPlanejamentoSelecionado != null) {
        final fmtPlanej = DateFormat('dd/MM/yyyy');
        final aindaExiste = entregas.any(
          (v) => _vendaNaChaveDiaPlanejamento(
            v,
            _chaveDiaPlanejamentoSelecionado!,
            fmtPlanej,
          ),
        );
        if (!aindaExiste) _chaveDiaPlanejamentoSelecionado = null;
      }
    });
    unawaited(_prefetchPodFotos());
  }

  Future<void> _atualizarListaEntregas() async {
    _carregarEntregas();
    await Future<void>.delayed(const Duration(milliseconds: 280));
  }

  void _alternarSelecaoEntrega(int vendaId) {
    setState(() {
      if (_idsEntregasSelecionadas.contains(vendaId)) {
        _idsEntregasSelecionadas.remove(vendaId);
      } else {
        _idsEntregasSelecionadas.add(vendaId);
      }
    });
  }

  Future<void> _confirmarAgrupamentoMesmoCarro() async {
    await _confirmarAgrupamentoIds(Set<int>.from(_idsEntregasSelecionadas));
  }

  Future<void> _confirmarAgrupamentoIds(Set<int> ids) async {
    if (ids.length < 2) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Selecione ao menos duas entregas do mesmo cliente.'),
        ),
      );
      return;
    }
    final selecionadas = _entregas.where((v) => ids.contains(v.id)).toList();
    final nomesNasSelecionadas = selecionadas
        .map(nomeMotoristaEntrega)
        .where((n) => n != 'Nao definido')
        .toSet();
    final motoristaSugerido = nomesNasSelecionadas.length == 1
        ? nomesNasSelecionadas.first
        : null;
    if (!mounted) return;
    final motorista = await showAgruparViagemMotoristaDialog(
      context,
      widget.motoristaRepository,
      motoristaSugerido: motoristaSugerido,
    );
    if (motorista == null || motorista.isEmpty || !mounted) return;
    try {
      widget.vendaRepository.definirGrupoEntregaLogistica(
        ids,
        motoristaEntrega: motorista,
      );
      await _carregarEntregasSyncState();
      if (!mounted) return;
      setState(() {
        _idsEntregasSelecionadas.clear();
        _modoAgruparMesmoCarro = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Pedidos marcados para o mesmo carro. A lista foi atualizada.',
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
    }
  }

  Future<void> _removerAgrupamentoSelecionadas() async {
    await _removerAgrupamentoIds(Set<int>.from(_idsEntregasSelecionadas));
  }

  Future<void> _removerAgrupamentoIds(Set<int> ids) async {
    if (ids.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Selecione as entregas para tirar do grupo.'),
        ),
      );
      return;
    }
    try {
      widget.vendaRepository.limparGrupoEntregaLogisticaEm(ids);
      await _carregarEntregasSyncState();
      if (!mounted) return;
      setState(() => _idsEntregasSelecionadas.clear());
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Agrupamento removido das selecionadas.')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
    }
  }

  /// Mesma logica de [_carregarEntregas] sem segundo setState no fim (evita piscar).
  Future<void> _carregarEntregasSyncState() async {
    final filtroLista = _montarFiltroEntregas(usarPeriodoVendaNaLista: true);
    final filtroContagem = _montarFiltroEntregas(
      usarPeriodoVendaNaLista: false,
      paraContagemResumo: true,
    );
    final resultado = widget.vendaRepository.carregarListagemEntregasComResumo(
      filtroLista: filtroLista,
      filtroContagem: filtroContagem,
    );
    final entregas = resultado.entregas;
    final vendedoresDisponiveis =
        (entregas
            .map(_nomeVendedor)
            .map((n) => n.trim())
            .where((n) => n.isNotEmpty)
            .toSet()
            .toList()
          ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase())));
    if (!mounted) return;
    setState(() {
      _entregas = entregas;
      _contagemAtrasadasCache = resultado.atrasadas;
      _contagemPendentesHojeCache = resultado.pendentesHoje;
      _vendedoresDisponiveis = vendedoresDisponiveis;
      if (_chaveDiaPlanejamentoSelecionado != null) {
        final fmtPlanej = DateFormat('dd/MM/yyyy');
        final aindaExiste = entregas.any(
          (v) => _vendaNaChaveDiaPlanejamento(
            v,
            _chaveDiaPlanejamentoSelecionado!,
            fmtPlanej,
          ),
        );
        if (!aindaExiste) _chaveDiaPlanejamentoSelecionado = null;
      }
    });
  }

  Widget _conteudoRomaneioUmaVenda(
    BuildContext context,
    Venda venda,
    StateSetter setDialogState,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '${venda.numeroOrcamento} · ${venda.cliente.target?.nomeRazao ?? 'Sem cliente'}',
          style: Theme.of(context).textTheme.titleSmall,
        ),
        const SizedBox(height: 2),
        Text(
          'Bairro: ${_extrairBairro(venda)} · Janela: ${_rotuloJanelaEntrega(venda.janelaEntrega)} · '
          'Prioridade: ${_rotuloPrioridade(venda.prioridadeEntrega)}',
        ),
        Text('Motorista: ${_nomeMotorista(venda)}'),
        Text('Endereco: ${venda.enderecoEntrega}'),
        const SizedBox(height: 4),
        Text(
          'Itens:',
          style: Theme.of(
            context,
          ).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 2),
        ..._linhasItensEntrega(venda).map(
          (linha) => Padding(
            padding: const EdgeInsets.only(bottom: 1),
            child: Text(
              '• $linha',
              style: Theme.of(
                context,
              ).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
            ),
          ),
        ),
        const SizedBox(height: 4),
        Wrap(
          spacing: 12,
          runSpacing: 6,
          children: [
            FilterChip(
              label: const Text('Separado'),
              selected: venda.cargaSeparada,
              onSelected: (v) {
                _atualizarChecklistCarga(venda, separado: v);
                setDialogState(() {
                  venda.cargaSeparada = v;
                });
              },
            ),
            FilterChip(
              label: const Text('Carregado'),
              selected: venda.cargaCarregada,
              onSelected: (v) {
                _atualizarChecklistCarga(venda, carregado: v);
                setDialogState(() {
                  venda.cargaCarregada = v;
                });
              },
            ),
            FilterChip(
              label: const Text('Saiu'),
              selected: venda.cargaSaiu,
              onSelected: (v) {
                _atualizarChecklistCarga(venda, saiu: v);
                setDialogState(() {
                  venda.cargaSaiu = v;
                });
              },
            ),
          ],
        ),
      ],
    );
  }

  Widget _blocoRomaneioDoDia(
    BuildContext context,
    List<Venda> bloco,
    StateSetter setDialogState,
  ) {
    if (bloco.length >= 2 && bloco.first.grupoEntregaFreteId > 0) {
      return _PainelRomaneioGrupoMesmoCarro(
        bloco: bloco,
        setDialogStateRomaneio: setDialogState,
        quantidadeItemEntrega: _quantidadeExibicaoEntrega,
        conteudoRomaneioUmaVenda: _conteudoRomaneioUmaVenda,
        escopoViagem: escopoViagemLogistica(bloco),
        conferenciaRepository: _conferenciaCargaRepository,
        usuarioAtual: widget.usuarioAtual,
      );
    }
    return _conteudoRomaneioUmaVenda(context, bloco.single, setDialogState);
  }

  Future<void> _abrirRomaneioVisual() async {
    final doDia = _entregasParaRomaneio();
    final blocosRom = blocosEntregaComCarretoAgrupado(doDia);
    final titulo = _rotuloPeriodoRomaneio();
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: Text('Romaneio — $titulo'),
              content: SizedBox(
                width: 700,
                child: doDia.isEmpty
                    ? Text(_mensagemRomaneioVazio())
                    : ListView.separated(
                        shrinkWrap: true,
                        itemCount: blocosRom.length,
                        separatorBuilder: (_, _) => const Divider(height: 16),
                        itemBuilder: (context, index) {
                          return _blocoRomaneioDoDia(
                            context,
                            blocosRom[index],
                            setDialogState,
                          );
                        },
                      ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Fechar'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  List<Venda> _entregasDoDia(DateTime base) {
    return _entregas.where((v) {
      final d = v.dataEntregaMarcada?.toLocal();
      if (d == null) return false;
      return DateTime(d.year, d.month, d.day) == base;
    }).toList()..sort((a, b) {
      final pa = _pesoPrioridade(a.prioridadeEntrega);
      final pb = _pesoPrioridade(b.prioridadeEntrega);
      final byP = pb.compareTo(pa);
      if (byP != 0) return byP;
      return (a.janelaEntrega).compareTo(b.janelaEntrega);
    });
  }

  String _rotuloPeriodoRomaneio() {
    final chave = _chaveDiaPlanejamentoSelecionado;
    if (chave == 'Sem data marcada') return 'Sem data marcada';
    if (chave == null) {
      final n = DateTime.now();
      return DateFormat('dd/MM/yyyy').format(DateTime(n.year, n.month, n.day));
    }
    return chave;
  }

  List<Venda> _entregasParaRomaneio() {
    final chave = _chaveDiaPlanejamentoSelecionado;
    if (chave == 'Sem data marcada') {
      final lista = _entregas
          .where((v) => v.dataEntregaMarcada == null)
          .toList();
      lista.sort((a, b) {
        final pa = _pesoPrioridade(a.prioridadeEntrega);
        final pb = _pesoPrioridade(b.prioridadeEntrega);
        final byP = pb.compareTo(pa);
        if (byP != 0) return byP;
        return (a.janelaEntrega).compareTo(b.janelaEntrega);
      });
      return lista;
    }
    DateTime base;
    if (chave == null) {
      final n = DateTime.now();
      base = DateTime(n.year, n.month, n.day);
    } else {
      try {
        base = DateFormat('dd/MM/yyyy').parse(chave);
      } catch (_) {
        final n = DateTime.now();
        base = DateTime(n.year, n.month, n.day);
      }
    }
    return _entregasDoDia(base);
  }

  String _mensagemRomaneioVazio() {
    final chave = _chaveDiaPlanejamentoSelecionado;
    if (chave == 'Sem data marcada') {
      return 'Nao ha entregas sem data marcada na lista atual.';
    }
    if (chave == null) {
      return 'Nao ha entregas marcadas para hoje na lista atual.';
    }
    return 'Nao ha entregas marcadas para esta data na lista atual.';
  }

  List<String> _linhasItensEntrega(Venda venda) {
    if (venda.itens.isEmpty) return const ['Sem itens cadastrados'];
    final linhas = venda.itens
        .map((item) {
          final q = _quantidadeExibicaoEntrega(venda, item);
          if (q <= 0) return null;
          final tag = EntregaVendaHelper.abreviacaoTipoItem(item.tipoEntregaItem);
          return '${q}x ${item.nomeProduto} ($tag)';
        })
        .whereType<String>()
        .toList();
    return linhas.isEmpty ? const ['Sem itens para esta entrega'] : linhas;
  }

  pw.TextStyle _estiloPdfRomaneio({double fontSize = 10, bool negrito = false}) {
    final f = pw.Font.courier();
    return pw.TextStyle(
      font: f,
      fontSize: fontSize,
      fontWeight: negrito ? pw.FontWeight.bold : pw.FontWeight.normal,
    );
  }

  pw.Widget _pdfRomaneioUmaEntrega(Venda venda, {int? parada}) {
    final cliente = venda.cliente.target?.nomeRazao ?? 'Sem cliente';
    final dataMarcada = venda.dataEntregaMarcada == null
        ? 'Sem data'
        : DateFormat('dd/MM/yyyy').format(venda.dataEntregaMarcada!.toLocal());
    final endereco = enderecoExibicaoRomaneio(venda);
    final estilo = _estiloPdfRomaneio();
    final tituloPedido = parada != null && parada > 0
        ? 'Parada #$parada — ${venda.numeroOrcamento} - $cliente'
        : '${venda.numeroOrcamento} - $cliente';
    return pw.Container(
      margin: const pw.EdgeInsets.only(bottom: 8),
      padding: const pw.EdgeInsets.only(bottom: 6),
      decoration: const pw.BoxDecoration(
        border: pw.Border(bottom: pw.BorderSide(width: 0.5)),
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text(
            tituloPedido,
            style: _estiloPdfRomaneio(fontSize: 10, negrito: true),
          ),
          pw.Text(
            'Bairro: ${_extrairBairro(venda)} | Janela: ${_rotuloJanelaEntrega(venda.janelaEntrega)} | Prioridade: ${_rotuloPrioridade(venda.prioridadeEntrega)}',
            style: estilo,
          ),
          pw.Text('Motorista: ${_nomeMotorista(venda)}', style: estilo),
          pw.Text('Vendedor: ${_nomeVendedor(venda)}', style: estilo),
          pw.Text('Data marcada: $dataMarcada', style: estilo),
          pw.Text(
            endereco.isEmpty ? 'Endereco: (nao informado)' : 'Endereco: $endereco',
            style: estilo,
          ),
          if (_observacaoSemMotorista(venda).trim().isNotEmpty)
            pw.Text('Obs: ${_observacaoSemMotorista(venda)}', style: estilo),
          if (_textoResumoComplementoNaVenda(venda) case final pend?)
            pw.Padding(
              padding: const pw.EdgeInsets.only(top: 2),
              child: pw.Text(
                pend,
                style: _estiloPdfRomaneio(fontSize: 10, negrito: true),
              ),
            ),
          pw.SizedBox(height: 3),
          pw.Text(
            'Itens:',
            style: _estiloPdfRomaneio(fontSize: 11, negrito: true),
          ),
          pw.SizedBox(height: 2),
          ..._linhasItensEntrega(venda).map(
            (linha) => pw.Padding(
              padding: const pw.EdgeInsets.only(bottom: 1),
              child: pw.Text(
                '• $linha',
                style: _estiloPdfRomaneio(fontSize: 10.5, negrito: true),
              ),
            ),
          ),
          pw.SizedBox(height: 4),
          pw.Text(
            '[${venda.cargaSeparada ? 'x' : ' '}] Separado    '
            '[${venda.cargaCarregada ? 'x' : ' '}] Carregado    '
            '[${venda.cargaSaiu ? 'x' : ' '}] Saiu',
            style: estilo.copyWith(fontSize: 10),
          ),
        ],
      ),
    );
  }

  pw.Widget _pdfRomaneioUmaEntregaBobina(Venda venda, {int? parada}) {
    final cliente = venda.cliente.target?.nomeRazao ?? 'Sem cliente';
    final dataMarcada = venda.dataEntregaMarcada == null
        ? 'Sem data'
        : DateFormat('dd/MM/yyyy').format(venda.dataEntregaMarcada!.toLocal());
    final endereco = enderecoExibicaoRomaneio(venda);
    const fsCorpo = 7.0;
    const fsTituloPedido = 8.0;
    const fsItens = 6.5;
    final estiloCorpo = _estiloPdfRomaneio(fontSize: fsCorpo);
    final tituloPedido = parada != null && parada > 0
        ? 'P#$parada ${venda.numeroOrcamento} $cliente'
        : '${venda.numeroOrcamento} $cliente';
    return pw.Container(
      margin: const pw.EdgeInsets.only(bottom: 5),
      padding: const pw.EdgeInsets.only(bottom: 4),
      decoration: const pw.BoxDecoration(
        border: pw.Border(bottom: pw.BorderSide(width: 0.4)),
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text(
            tituloPedido,
            style: _estiloPdfRomaneio(fontSize: fsTituloPedido, negrito: true),
          ),
          pw.Text(
            '${_extrairBairro(venda)} · ${_rotuloJanelaEntrega(venda.janelaEntrega)} · ${_rotuloPrioridade(venda.prioridadeEntrega)}',
            style: estiloCorpo,
          ),
          pw.Text(
            'Mot: ${_nomeMotorista(venda)} · Vend: ${_nomeVendedor(venda)}',
            style: estiloCorpo,
          ),
          pw.Text(
            'Data: $dataMarcada',
            style: estiloCorpo,
          ),
          pw.Text(
            endereco.isEmpty ? 'End: (nao informado)' : 'End: $endereco',
            style: estiloCorpo,
          ),
          if (_observacaoSemMotorista(venda).trim().isNotEmpty)
            pw.Text(
              'Obs: ${_observacaoSemMotorista(venda)}',
              style: estiloCorpo,
            ),
          if (_textoResumoComplementoNaVenda(venda) case final pendBob?)
            pw.Text(
              pendBob,
              style: _estiloPdfRomaneio(fontSize: fsCorpo, negrito: true),
            ),
          pw.SizedBox(height: 2),
          pw.Text(
            'Itens',
            style: _estiloPdfRomaneio(fontSize: fsCorpo + 0.5, negrito: true),
          ),
          ..._linhasItensEntrega(venda).map(
            (linha) => pw.Padding(
              padding: const pw.EdgeInsets.only(bottom: 0.5),
              child: pw.Text(
                '- $linha',
                style: _estiloPdfRomaneio(fontSize: fsItens, negrito: true),
              ),
            ),
          ),
          pw.SizedBox(height: 2),
          pw.Text(
            '[${venda.cargaSeparada ? 'x' : ' '}]Sep [${venda.cargaCarregada ? 'x' : ' '}]Carr [${venda.cargaSaiu ? 'x' : ' '}]Sai',
            style: estiloCorpo.copyWith(fontSize: 6.5),
          ),
        ],
      ),
    );
  }

  List<Venda> _entregasParaRomaneioComRelacoes() {
    return _entregasParaRomaneio().map((v) {
      final fresca = widget.vendaRepository.obterPorId(v.id) ?? v;
      fresca.cliente.target;
      fresca.itens.length;
      return fresca;
    }).toList();
  }

  Future<void> _abrirRelatoriosEntrega() async {
    final entregasDia = _entregasParaRomaneioComRelacoes();
    if (entregasDia.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(_mensagemRomaneioVazio())));
      return;
    }
    final titulo = _rotuloPeriodoRomaneio();
    final motoristas = motoristasDistintosNasEntregas(entregasDia);
    final viagens = viagensAgrupadasNoDia(entregasDia);

    if (!mounted) return;
    var tipo = RelatorioEntregaTipo.romaneioMotoristaDia;
    var layoutEscolhido = RomaneioPdfLayout.a4;
    String? motoristaSel = motoristas.isNotEmpty ? motoristas.first : null;
    List<Venda>? viagemSel = viagens.isNotEmpty ? viagens.first : null;

    final escolha =
        await showDialog<
            ({
              RelatorioEntregaTipo tipo,
              RomaneioPdfLayout layout,
              String acao,
              String? motorista,
              List<Venda>? viagem,
            })?>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setLocal) {
          return AlertDialog(
            title: Text('Relatorios — $titulo'),
            content: SizedBox(
              width: 520,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Tipo de relatorio',
                      style: Theme.of(context).textTheme.titleSmall,
                    ),
                    const SizedBox(height: 8),
                    ...RelatorioEntregaTipo.values.map(
                      (t) => RadioListTile<RelatorioEntregaTipo>(
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        title: Text(t.rotulo),
                        value: t,
                        groupValue: tipo,
                        onChanged: (v) {
                          if (v == null) return;
                          setLocal(() => tipo = v);
                        },
                      ),
                    ),
                    if (tipo.exigeMotorista) ...[
                      const SizedBox(height: 8),
                      if (motoristas.isEmpty)
                        Text(
                          'Nenhum motorista nas entregas. Defina ao agrupar ou no botao Motorista.',
                          style: TextStyle(
                            color: Theme.of(context).colorScheme.error,
                          ),
                        )
                      else
                        DropdownButtonFormField<String>(
                          initialValue: motoristaSel,
                          decoration: const InputDecoration(
                            labelText: 'Motorista',
                          ),
                          items: motoristas
                              .map(
                                (m) => DropdownMenuItem(
                                  value: m,
                                  child: Text(m),
                                ),
                              )
                              .toList(),
                          onChanged: (v) => setLocal(() => motoristaSel = v),
                        ),
                    ],
                    if (tipo.exigeViagem) ...[
                      const SizedBox(height: 8),
                      if (viagens.isEmpty)
                        const Text(
                          'Nenhuma viagem agrupada no periodo. Use "Agrupar mesmo carro".',
                        )
                      else
                        DropdownButtonFormField<int>(
                          initialValue: viagemSel?.first.grupoEntregaFreteId,
                          decoration: const InputDecoration(
                            labelText: 'Viagem (mesmo carro)',
                          ),
                          items: viagens
                              .map(
                                (bloco) => DropdownMenuItem(
                                  value: bloco.first.grupoEntregaFreteId,
                                  child: Text(rotuloGrupoLogistica(bloco)),
                                ),
                              )
                              .toList(),
                          onChanged: (g) {
                            if (g == null) return;
                            setLocal(() {
                              viagemSel = viagens.firstWhere(
                                (b) => b.first.grupoEntregaFreteId == g,
                              );
                            });
                          },
                        ),
                    ],
                    const Divider(height: 20),
                    Text(
                      'Formato do papel',
                      style: Theme.of(context).textTheme.titleSmall,
                    ),
                    const SizedBox(height: 8),
                    SegmentedButton<RomaneioPdfLayout>(
                      segments: const [
                        ButtonSegment(
                          value: RomaneioPdfLayout.a4,
                          label: Text('A4'),
                        ),
                        ButtonSegment(
                          value: RomaneioPdfLayout.bobina80mm,
                          label: Text('80 mm'),
                        ),
                      ],
                      selected: {layoutEscolhido},
                      onSelectionChanged: (next) {
                        setLocal(() => layoutEscolhido = next.single);
                      },
                    ),
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext, null),
                child: const Text('Fechar'),
              ),
              TextButton.icon(
                onPressed: () {
                  Navigator.pop(dialogContext);
                  _abrirRomaneioVisual();
                },
                icon: const Icon(Icons.visibility_outlined),
                label: const Text('Visualizar na tela'),
              ),
              OutlinedButton.icon(
                onPressed: () {
                  if (tipo.exigeMotorista &&
                      (motoristaSel == null || motoristaSel!.isEmpty)) {
                    return;
                  }
                  if (tipo.exigeViagem && viagemSel == null) {
                    return;
                  }
                  Navigator.pop(
                    dialogContext,
                    (
                      tipo: tipo,
                      layout: layoutEscolhido,
                      acao: 'pdf',
                      motorista: motoristaSel,
                      viagem: viagemSel,
                    ),
                  );
                },
                icon: const Icon(Icons.picture_as_pdf_outlined),
                label: const Text('Exportar PDF'),
              ),
              ElevatedButton.icon(
                onPressed: () {
                  if (tipo.exigeMotorista &&
                      (motoristaSel == null || motoristaSel!.isEmpty)) {
                    return;
                  }
                  if (tipo.exigeViagem && viagemSel == null) {
                    return;
                  }
                  Navigator.pop(
                    dialogContext,
                    (
                      tipo: tipo,
                      layout: layoutEscolhido,
                      acao: 'imprimir',
                      motorista: motoristaSel,
                      viagem: viagemSel,
                    ),
                  );
                },
                icon: const Icon(Icons.print_outlined),
                label: const Text('Imprimir'),
              ),
            ],
          );
        },
      ),
    );
    if (!mounted || escolha == null) return;
    if (escolha.tipo.exigeMotorista &&
        (escolha.motorista == null || escolha.motorista!.isEmpty)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Defina o motorista nas entregas ou selecione outro relatorio.',
          ),
        ),
      );
      return;
    }
    if (escolha.tipo.exigeViagem && escolha.viagem == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Nenhuma viagem agrupada para este relatorio.'),
        ),
      );
      return;
    }

    await _emitirRelatorioEntrega(
      tipo: escolha.tipo,
      motorista: escolha.motorista,
      viagem: escolha.viagem,
      layout: escolha.layout,
      salvarPdf: escolha.acao == 'pdf',
    );
  }

  Future<void> _emitirRelatorioEntrega({
    required RelatorioEntregaTipo tipo,
    String? motorista,
    List<Venda>? viagem,
    RomaneioPdfLayout layout = RomaneioPdfLayout.a4,
    required bool salvarPdf,
  }) async {
    final entregasDia = _entregasParaRomaneioComRelacoes();
    if (entregasDia.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(_mensagemRomaneioVazio())));
      return;
    }
    final titulo = _rotuloPeriodoRomaneio();
    final emissao = DateTime.now();
    final bobina = layout == RomaneioPdfLayout.bobina80mm;
    final pdfBytes = await gerarRelatorioEntregaPdfBytes(
      tipo: tipo,
      entregasPeriodo: entregasDia,
      tituloPeriodo: titulo,
      emissao: emissao,
      layout: layout,
      motorista: motorista,
      viagem: viagem,
      pdfUmaEntrega: (v, {parada}) => bobina
          ? _pdfRomaneioUmaEntregaBobina(v, parada: parada)
          : _pdfRomaneioUmaEntrega(v, parada: parada),
      quantidadeEntrega: _quantidadeExibicaoEntrega,
    );
    if (!mounted) return;
    if (!salvarPdf) {
      await Printing.layoutPdf(onLayout: (_) async => pdfBytes);
      return;
    }
    final arquivo = await FilePicker.platform.saveFile(
      dialogTitle: 'Salvar relatorio em PDF',
      fileName: nomeArquivoRelatorioEntrega(
        tipo: tipo,
        tituloPeriodo: titulo,
        motorista: motorista,
        bobina80: bobina,
      ),
      type: FileType.custom,
      allowedExtensions: const ['pdf'],
    );
    if (arquivo == null) return;
    final path = arquivo.toLowerCase().endsWith('.pdf')
        ? arquivo
        : '$arquivo.pdf';
    await File(path).writeAsBytes(pdfBytes, flush: true);
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text('Relatorio salvo em: $path')));
  }

  Future<void> _editarMotoristaGrupo(int grupoId, String atual) async {
    final motoristas = widget.motoristaRepository.listarAtivos();
    var escolhido = atual == 'Nao definido' || atual.isEmpty
        ? (motoristas.isNotEmpty ? motoristas.first.nome : null)
        : atual;
    if (!mounted) return;
    final novo = await showDialog<String>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setLocal) {
          return AlertDialog(
            title: const Text('Motorista da viagem'),
            content: motoristas.isEmpty
                ? const Text(
                    'Nenhum motorista ativo. Cadastre em Cadastros > Motoristas.',
                  )
                : DropdownButtonFormField<String>(
                    initialValue: escolhido,
                    decoration: const InputDecoration(labelText: 'Motorista'),
                    items: motoristas
                        .map(
                          (m) => DropdownMenuItem(
                            value: m.nome,
                            child: Text(m.nome),
                          ),
                        )
                        .toList(),
                    onChanged: (v) => setLocal(() => escolhido = v),
                  ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Cancelar'),
              ),
              ElevatedButton(
                onPressed: motoristas.isEmpty || escolhido == null
                    ? null
                    : () => Navigator.pop(ctx, escolhido),
                child: const Text('Salvar'),
              ),
            ],
          );
        },
      ),
    );
    if (novo == null || novo.isEmpty || !mounted) return;
    try {
      widget.vendaRepository.definirMotoristaEntregaNoGrupo(grupoId, novo);
      await _carregarEntregasSyncState();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
    }
  }

  int _pesoPrioridade(String prioridade) {
    switch (prioridade) {
      case 'urgente':
        return 3;
      case 'agendada':
        return 2;
      case 'normal':
      default:
        return 1;
    }
  }

  String _rotuloPrioridade(String prioridade) {
    switch (prioridade) {
      case 'urgente':
        return 'Urgente';
      case 'agendada':
        return 'Agendada';
      case 'normal':
      default:
        return 'Normal';
    }
  }

  String _rotuloJanelaEntrega(String janela) {
    switch (janela) {
      case 'manha':
        return 'Manha';
      case 'tarde':
        return 'Tarde';
      case 'nao_definida':
      default:
        return 'Nao definida';
    }
  }

  String _extrairBairro(Venda venda) {
    final endereco = venda.enderecoEntrega.trim();
    if (endereco.isEmpty) return 'Sem bairro';
    final partesPipe = endereco
        .split('|')
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toList();
    if (partesPipe.length >= 2) return partesPipe[1];
    final partesVirgula = endereco
        .split(',')
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toList();
    if (partesVirgula.length >= 2) return partesVirgula[1];
    return partesPipe.isNotEmpty ? partesPipe.first : 'Sem bairro';
  }

  String _nomeMotorista(Venda venda) => nomeMotoristaEntrega(venda);

  String _nomeVendedor(Venda venda) {
    final vendedor = venda.vendedor.target;
    final nome = vendedor?.apelido.trim().isNotEmpty == true
        ? vendedor!.apelido.trim()
        : (vendedor?.nomeCompleto.trim() ?? '');
    if (nome.isNotEmpty) return nome;
    return 'Nao definido';
  }

  String _enderecoCompletoParaNavegacao(Venda venda) =>
      enderecoExibicaoRomaneio(venda);

  Future<void> _abrirNavegacaoParaEntrega(Venda venda) async {
    final endereco = _enderecoCompletoParaNavegacao(venda);
    if (endereco.trim().isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Nao ha endereco de entrega para abrir no mapa.'),
        ),
      );
      return;
    }
    final uri = Uri.parse(
      'https://www.google.com/maps/search/?api=1&query=${Uri.encodeComponent(endereco)}',
    );
    final url = uri.toString();

    // No Windows, url_launcher_windows ainda pode lancar PlatformException
    // em alguns builds. Abrir via rundll32 usa o navegador padrao sem o plugin.
    if (Platform.isWindows) {
      try {
        final r = await Process.run(
          'rundll32',
          ['url.dll,FileProtocolHandler', url],
        );
        if (r.exitCode == 0) return;
      } catch (_) {
        // segue para launchUrl
      }
    }

    try {
      var ok = await launchUrl(uri, mode: LaunchMode.platformDefault);
      if (!ok) {
        ok = await launchUrl(uri);
      }
      if (!mounted) return;
      if (!ok) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Nao foi possivel abrir o mapa no navegador padrao.'),
          ),
        );
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Erro ao abrir mapa: $e')),
      );
    }
  }

  Future<void> _swapParadasMesmoCarro(
    int grupoId,
    List<Venda> ordenado,
    int indiceA,
    int indiceB,
  ) async {
    if (indiceA == indiceB) return;
    if (indiceA < 0 ||
        indiceB < 0 ||
        indiceA >= ordenado.length ||
        indiceB >= ordenado.length) {
      return;
    }
    final nova = List<Venda>.from(ordenado);
    final tmp = nova[indiceA];
    nova[indiceA] = nova[indiceB];
    nova[indiceB] = tmp;
    try {
      widget.vendaRepository.atualizarSequenciaEntregaNoGrupo(
        grupoId,
        nova.map((x) => x.id).toList(),
      );
      await _carregarEntregasSyncState();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
    }
  }

  String _observacaoSemMotorista(Venda venda) {
    if (venda.motoristaEntrega.trim().isNotEmpty) {
      return venda.observacaoEntrega.trim();
    }
    final linhas = venda.observacaoEntrega
        .split('\n')
        .map((linha) => linha.trimRight())
        .where((linha) => linha.trim().isNotEmpty)
        .where((linha) => !linha.trimLeft().startsWith('Motorista:'))
        .toList();
    return linhas.join('\n');
  }

  Future<void> _atualizarPrioridade(Venda venda, String novaPrioridade) async {
    widget.vendaRepository.atualizarPrioridadeEntrega(venda.id, novaPrioridade);
    _carregarEntregas();
  }

  Future<void> _definirMotoristaEmLoteIds(Set<int> ids) async {
    if (ids.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Nenhuma entrega selecionada.')),
      );
      return;
    }
    final motorista = await showSelecionarMotoristaDialog(
      context,
      widget.motoristaRepository,
      titulo: 'Motorista das entregas',
      rotuloConfirmar: 'Aplicar',
      textoAuxiliar:
          'O mesmo motorista sera gravado em ${ids.length} pedido(s).',
    );
    if (motorista == null || motorista.isEmpty || !mounted) return;
    try {
      final n = widget.vendaRepository.atualizarMotoristaEntregaEmLote(
        ids,
        motorista,
      );
      await _carregarEntregasSyncState();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Motorista definido em $n entrega(s).')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Erro ao definir motorista: $e')),
      );
    }
  }

  Future<void> _editarMotoristaEntrega(Venda venda) async {
    if (!mounted) return;
    final motoristas = widget.motoristaRepository.listarAtivos();
    final atual = venda.motoristaEntrega.trim();
    String selecionado = atual;
    final nome = await showDialog<String>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text('Motorista ${venda.numeroOrcamento}'),
          content: motoristas.isEmpty
              ? const Text(
                  'Nenhum motorista ativo cadastrado. Cadastre em Cadastros > Motoristas.',
                )
              : DropdownButtonFormField<String>(
                  initialValue: selecionado.isEmpty ? null : selecionado,
                  decoration: const InputDecoration(labelText: 'Motorista'),
                  items: motoristas
                      .map(
                        (m) => DropdownMenuItem<String>(
                          value: m.nome.trim(),
                          child: Text(
                            m.telefone.trim().isEmpty
                                ? m.nome
                                : '${m.nome} · ${m.telefone}',
                          ),
                        ),
                      )
                      .toList(),
                  onChanged: (v) => setDialogState(() => selecionado = v ?? ''),
                ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancelar'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, ''),
              child: const Text('Limpar'),
            ),
            ElevatedButton(
              onPressed: motoristas.isEmpty
                  ? null
                  : () => Navigator.pop(context, selecionado.trim()),
              child: const Text('Salvar'),
            ),
          ],
        ),
      ),
    );
    if (nome == null) return;
    try {
      widget.vendaRepository.atualizarMotoristaEntrega(venda.id, nome);
      _carregarEntregas();
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Motorista atualizado.')));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Erro ao atualizar motorista: $e')),
      );
    }
  }

  Future<void> _marcarOuAlterarDataEntrega(Venda venda) async {
    if (!widget.podeGerenciarStatusEntrega) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(_mensagemSemPermissaoStatus())));
      return;
    }
    final agora = DateTime.now();
    final hoje = DateTime(agora.year, agora.month, agora.day);
    final marcada = venda.dataEntregaMarcada?.toLocal();
    final inicial = marcada != null
        ? DateTime(marcada.year, marcada.month, marcada.day)
        : hoje;
    final escolhido = await showDatePicker(
      context: context,
      initialDate: inicial.isBefore(hoje) ? hoje : inicial,
      firstDate: DateTime(agora.year - 1, 1, 1),
      lastDate: DateTime(agora.year + 3, 12, 31),
    );
    if (!mounted || escolhido == null) return;
    try {
      widget.vendaRepository.atualizarDataEntregaMarcada(venda.id, escolhido);
      _carregarEntregas();
      if (!mounted) return;
      final fmt = DateFormat('dd/MM/yyyy');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Data da entrega definida: ${fmt.format(escolhido)}.',
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Erro ao salvar data: $e')),
      );
    }
  }

  Future<void> _limparDataEntregaMarcada(Venda venda) async {
    if (!widget.podeGerenciarStatusEntrega) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(_mensagemSemPermissaoStatus())));
      return;
    }
    if (venda.dataEntregaMarcada == null) return;
    final confirmar = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Limpar data de entrega'),
        content: Text(
          'Remover a data marcada da venda ${venda.numeroOrcamento}?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Limpar'),
          ),
        ],
      ),
    );
    if (!mounted || confirmar != true) return;
    try {
      widget.vendaRepository.atualizarDataEntregaMarcada(venda.id, null);
      _carregarEntregas();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Data da entrega removida.')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Erro ao limpar data: $e')),
      );
    }
  }

  void _aplicarPeriodoMarcadasParaHoje() {
    setState(() {
      _filtrosDropdownNonce++;
      _inicio = null;
      _fim = null;
      _filtroDataMarcada = 'hoje';
    });
    _carregarEntregas();
  }

  /// Volta filtros, periodo e texto de busca ao padrao amplo ("Todos" em tudo aplicavel).
  void _redefinirFiltrosPadrao() {
    setState(() {
      _filtrosDropdownNonce++;
      _filtroResumoLista = _FiltroResumoEntregas.nenhum;
      _chaveDiaPlanejamentoSelecionado = null;
      _statusSelecionado = 'todos';
      _filtroMotorista = 'todos';
      _filtroVendedor = 'todos';
      _agrupamento = 'bairro';
      _filtroDataMarcada = 'todos';
      _bairroController.clear();
      _numeroNotaController.clear();
      _modoAgruparMesmoCarro = false;
      _idsEntregasSelecionadas.clear();
      _inicio = null;
      _fim = null;
    });
    _carregarEntregas();
  }

  Future<void> _selecionarPeriodoPersonalizado() async {
    final agora = DateTime.now();
    final inicioAtual = _inicio ?? DateTime(agora.year, agora.month, agora.day);
    final fimAtual = _fim ?? agora;
    final intervalo = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
      initialDateRange: DateTimeRange(
        start: DateTime(inicioAtual.year, inicioAtual.month, inicioAtual.day),
        end: DateTime(fimAtual.year, fimAtual.month, fimAtual.day),
      ),
      helpText: 'Periodo personalizado',
      saveText: 'Aplicar',
    );
    if (intervalo == null) return;
    setState(() {
      _filtrosDropdownNonce++;
      _filtroDataMarcada = 'todos';
      _inicio = DateTime(
        intervalo.start.year,
        intervalo.start.month,
        intervalo.start.day,
      );
      _fim = DateTime(
        intervalo.end.year,
        intervalo.end.month,
        intervalo.end.day,
        23,
        59,
        59,
        999,
      );
    });
    _carregarEntregas();
  }

  String _rotuloPeriodoSelecionado() {
    if (_inicio == null && _fim == null) {
      if (_filtroDataMarcada == 'hoje') {
        return 'Marcadas para hoje';
      }
      return 'Periodo: todos';
    }
    final fmt = DateFormat('dd/MM/yyyy');
    return 'Periodo: ${fmt.format(_inicio!.toLocal())} ate ${fmt.format(_fim!.toLocal())}';
  }

  bool _transicaoStatusPermitida(String atual, String novo) {
    if (atual == novo) return true;
    if (atual == 'entregue' || atual == 'cancelada') return false;

    if (atual == 'entregue_complemento_pendente') {
      if (novo == 'entregue') return true;
      if (novo == 'reagendada' || novo == 'cancelada') return true;
      if (novo == 'pendente') return true;
      return false;
    }

    if (novo == 'entregue_complemento_pendente') {
      return atual == 'saiu_entrega';
    }

    if (novo == 'reagendada' || novo == 'cancelada') return true;
    const ordem = {
      'pendente': 0,
      'roteirizada': 1,
      'saiu_entrega': 2,
      'entregue': 3,
    };
    final iAtual = ordem[atual];
    final iNovo = ordem[novo];
    if (iAtual == null || iNovo == null) return true;
    return iNovo == iAtual + 1 || (iNovo == 0 && atual == 'reagendada');
  }

  String _mensagemBloqueioTransicao(String atual, String novo) {
    return 'Nao foi possivel mudar de "${_rotuloStatusEntrega(atual)}" para '
        '"${_rotuloStatusEntrega(novo)}". Fluxo normal: Pendente -> Roteirizada -> '
        'Saiu -> Entregue. Com falta na ida: em "Saiu" use "Faltou item" para registrar '
        'complemento pendente; depois "Concluir complemento" ou reabrir rota (Pendente).';
  }

  bool _checklistPodeAtualizar(
    Venda venda, {
    bool? separado,
    bool? carregado,
    bool? saiu,
  }) {
    final novoSeparado = separado ?? venda.cargaSeparada;
    final novoCarregado = carregado ?? venda.cargaCarregada;
    final novoSaiu = saiu ?? venda.cargaSaiu;
    if (novoCarregado && !novoSeparado) return false;
    if (novoSaiu && (!novoSeparado || !novoCarregado)) return false;
    return true;
  }

  String _mensagemChecklistInvalido() {
    return 'Siga a sequencia do checklist: Separado -> Carregado -> Saiu.';
  }

  String _mensagemSemPermissaoStatus() {
    return 'Seu perfil nao possui permissao para alterar status de entrega.';
  }

  Future<void> _abrirHistoricoEntrega(Venda venda) async {
    final historico = widget.vendaRepository.listarHistoricoEntrega(venda.id);
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text('Historico da entrega ${venda.numeroOrcamento}'),
          content: SizedBox(
            width: 620,
            child: historico.isEmpty
                ? const Text('Sem movimentacoes registradas.')
                : ListView.separated(
                    shrinkWrap: true,
                    itemCount: historico.length,
                    separatorBuilder: (_, _) => const Divider(height: 8),
                    itemBuilder: (context, index) {
                      final item = historico[index];
                      final evento = HistoricoEntregaEventos.ehEventoOcorrencia(
                        item.statusNovo,
                      );
                      final quando =
                          '${DateFormat('dd/MM/yyyy HH:mm').format(item.dataHora.toLocal())} · ${item.usuario}';
                      return ListTile(
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        title: Text(
                          evento
                              ? _rotuloStatusEntrega(item.statusNovo)
                              : '${_rotuloStatusEntrega(item.statusAnterior)} -> ${_rotuloStatusEntrega(item.statusNovo)}',
                        ),
                        subtitle: Text(
                          evento && item.statusAnterior.trim().isNotEmpty
                              ? '$quando\n${item.statusAnterior}'
                              : quando,
                        ),
                      );
                    },
                  ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Fechar'),
            ),
          ],
        );
      },
    );
  }

  String? _textoResumoComplementoNaVenda(Venda venda, [String? jsonBruto]) {
    final linhas = ComplementoEntregaCodec.decode(
      jsonBruto ?? venda.complementoEntregaJson,
    );
    if (linhas.isEmpty) return null;
    final partes = linhas
        .map((l) => '${l.quantidade}x ${l.nomeProduto}')
        .toList();
    return 'Falta na ida: ${partes.join('; ')}';
  }

  Future<bool> _atualizarStatusEntrega(
    Venda venda,
    String novoStatus, {
    String? complementoEntregaJson,
    String? notaComplementoExtra,
    bool mostrarSnackSucesso = true,
  }) async {
    try {
      if (!widget.podeGerenciarStatusEntrega) {
        if (!mounted) return false;
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(_mensagemSemPermissaoStatus())));
        return false;
      }
      final statusAnterior = venda.statusEntrega;
      if (!_transicaoStatusPermitida(statusAnterior, novoStatus)) {
        if (!mounted) return false;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              _mensagemBloqueioTransicao(statusAnterior, novoStatus),
            ),
          ),
        );
        return false;
      }
      if ((novoStatus == 'entregue' || novoStatus == 'entregue_complemento_pendente') &&
          _progressoCarga(venda) < 3) {
        if (!mounted) return false;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Checklist de carga incompleto. Finalize Separado, Carregado e Saiu antes de entregar.',
            ),
          ),
        );
        return false;
      }
      if (novoStatus == 'entregue_complemento_pendente') {
        final j = complementoEntregaJson?.trim() ?? '';
        if (j.isEmpty) {
          if (!mounted) return false;
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'Informe pelo menos um item em falta para registrar complemento pendente.',
              ),
            ),
          );
          return false;
        }
      }
      String? motivo;
      if (novoStatus == 'reagendada' || novoStatus == 'cancelada') {
        motivo = await _solicitarMotivoMudancaStatus(novoStatus);
        if (motivo == null) return false;
      }
      final podComplemento =
          statusAnterior == 'entregue_complemento_pendente';
      if (EntregaPodRegra.deveSolicitarPod(
        novoStatus: novoStatus,
        statusAnterior: statusAnterior,
        podRecebidoPorAtual: venda.podRecebidoPor,
      )) {
        final pod = await showPodEntregaDialog(
          context: context,
          vendaId: venda.id,
          recebidoPorInicial: podComplemento ? '' : venda.podRecebidoPor.trim(),
          podComplemento: podComplemento,
        );
        if (pod == null) return false;
        final podFinal = EntregaPodFinalizacao(
          configRepository: widget.appConfigRepository,
        );
        await podFinal.registrarPod(
          vendaRepository: widget.vendaRepository,
          vendaId: venda.id,
          recebidoPor: pod.recebidoPor,
          usuarioLogin: widget.usuarioAtual,
          fotoPathLocal: pod.fotoPathLocal ?? '',
          fotoPathServidor: pod.fotoPathServidor ?? '',
        );
        final atualizada = widget.vendaRepository.obterPorId(venda.id);
        venda.podRecebidoPor = pod.recebidoPor;
        venda.podFotoPath =
            atualizada?.podFotoPath ?? pod.fotoPathLocal ?? '';
        venda.podFotoPathServidor =
            atualizada?.podFotoPathServidor ?? pod.fotoPathServidor ?? '';
      }
      widget.vendaRepository.atualizarStatusEntrega(
        venda.id,
        novoStatus,
        complementoEntregaJson: complementoEntregaJson,
      );
      widget.vendaRepository.registrarHistoricoStatusEntrega(
        vendaId: venda.id,
        statusAnterior: statusAnterior,
        statusNovo: novoStatus,
        usuario: widget.usuarioAtual,
      );
      if (novoStatus == 'entregue' && venda.podRecebidoPor.trim().isNotEmpty) {
        final comFoto = EntregaPodRegra.temReferenciaFoto(
          podFotoPath: venda.podFotoPath,
          podFotoPathServidor: venda.podFotoPathServidor,
        );
        final prefixo = podComplemento ? 'Complemento — ' : '';
        widget.vendaRepository.registrarOcorrenciaEntrega(
          vendaId: venda.id,
          status: HistoricoEntregaEventos.podEntrega,
          motivo:
              '${prefixo}Recebido por: ${venda.podRecebidoPor.trim()}${comFoto ? ' (com foto)' : ''}',
          usuario: widget.usuarioAtual,
        );
      }
      if (motivo != null) {
        widget.vendaRepository.registrarOcorrenciaEntrega(
          vendaId: venda.id,
          status: novoStatus,
          motivo: motivo,
          usuario: widget.usuarioAtual,
        );
      }
      if (novoStatus == 'entregue_complemento_pendente' &&
          complementoEntregaJson != null) {
        var resumo = _textoResumoComplementoNaVenda(
          venda,
          complementoEntregaJson.trim(),
        );
        if (notaComplementoExtra != null &&
            notaComplementoExtra.trim().isNotEmpty) {
          final extra = notaComplementoExtra.trim();
          resumo = resumo == null
              ? 'Obs: $extra'
              : '$resumo | Obs: $extra';
        }
        if (resumo != null) {
          widget.vendaRepository.registrarOcorrenciaEntrega(
            vendaId: venda.id,
            status: HistoricoEntregaEventos.complementoPendente,
            motivo: resumo,
            usuario: widget.usuarioAtual,
          );
        }
      }
      _carregarEntregas();
      if (!mounted) return false;
      if (mostrarSnackSucesso) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Status de entrega atualizado.')),
        );
      }
      return true;
    } catch (e) {
      if (!mounted) return false;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Erro ao atualizar status: $e')));
      return false;
    }
  }

  Future<String?> _solicitarMotivoMudancaStatus(String novoStatus) async {
    if (!mounted) return null;
    final controller = TextEditingController();
    final motivo = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(
          'Motivo da ${_rotuloStatusEntrega(novoStatus).toLowerCase()}',
        ),
        content: TextField(
          controller: controller,
          autofocus: true,
          minLines: 2,
          maxLines: 4,
          decoration: const InputDecoration(
            labelText: 'Motivo (obrigatorio)',
            hintText: 'Descreva o motivo desta alteracao',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            onPressed: () {
              final texto = controller.text.trim();
              if (texto.isEmpty) return;
              Navigator.pop(context, texto);
            },
            child: const Text('Confirmar'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (motivo == null || motivo.trim().isEmpty) {
      if (!mounted) return null;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Motivo obrigatorio para reagendar ou cancelar entrega.',
          ),
        ),
      );
      return null;
    }
    return motivo.trim();
  }

  Future<void> _confirmarConcluirComplemento(Venda venda) async {
    if (!mounted) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Concluir complemento ${venda.numeroOrcamento}'),
        content: const Text(
          'Confirma que os itens em falta ja foram entregues ao cliente? '
          'O status passara para Entregue e o registro de complemento sera limpo. '
          'No carreto com reserva ate a saida, o estoque baixa de novo pelas '
          'quantidades do complemento (segunda viagem).',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Confirmar'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    await _atualizarStatusEntrega(venda, 'entregue');
  }

  Future<void> _abrirDialogRegistrarComplemento(Venda venda) async {
    if (!widget.podeGerenciarStatusEntrega) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(_mensagemSemPermissaoStatus())));
      return;
    }
    if (venda.statusEntrega != 'saiu_entrega') return;
    if (_progressoCarga(venda) < 3) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Checklist de carga incompleto. Finalize Separado, Carregado e Saiu antes.',
          ),
        ),
      );
      return;
    }
    final itens = venda.itens
        .where((i) => _quantidadeExibicaoEntrega(venda, i) > 0)
        .toList();
    if (itens.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Nao ha itens de entrega neste pedido.'),
        ),
      );
      return;
    }
    final controllers = <int, TextEditingController>{
      for (final i in itens) i.id: TextEditingController(text: '0'),
    };
    final obsCtrl = TextEditingController();
    if (!mounted) return;
    final jsonResult = await showDialog<String>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: Text('Faltou item na ida — ${venda.numeroOrcamento}'),
          content: SizedBox(
            width: 520,
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text(
                    'Informe quantas unidades faltaram na ida para cada linha. '
                    'Pelo menos um item deve ter falta maior que zero. '
                    'No carreto com reserva ate a saida, o estoque fisico e reservado '
                    'serao ajustados (volta o que nao saiu na ida).',
                  ),
                  const SizedBox(height: 10),
                  for (final item in itens) ...[
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Text(
                            '${_quantidadeExibicaoEntrega(venda, item)}x ${item.nomeProduto}',
                          ),
                        ),
                        SizedBox(
                          width: 76,
                          child: TextField(
                            controller: controllers[item.id],
                            keyboardType: TextInputType.number,
                            decoration: const InputDecoration(
                              labelText: 'Falta',
                              isDense: true,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                  ],
                  TextField(
                    controller: obsCtrl,
                    maxLines: 2,
                    decoration: const InputDecoration(
                      labelText: 'Observacao (opcional)',
                      hintText: 'Ex.: cliente aceitou aguardar segunda ida',
                    ),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Cancelar'),
            ),
            ElevatedButton(
              onPressed: () {
                final linhas = <LinhaComplementoEntrega>[];
                for (final item in itens) {
                  final raw =
                      controllers[item.id]?.text.trim() ?? '';
                  final f = int.tryParse(raw) ?? 0;
                  final max = _quantidadeExibicaoEntrega(venda, item);
                  if (f < 0 || f > max) {
                    ScaffoldMessenger.of(dialogContext).showSnackBar(
                      SnackBar(
                        content: Text(
                          'Quantidade invalida para "${item.nomeProduto}" '
                          '(maximo $max).',
                        ),
                      ),
                    );
                    return;
                  }
                  if (f > 0) {
                    linhas.add(
                      LinhaComplementoEntrega(
                        itemVendaId: item.id,
                        quantidade: f,
                        nomeProduto: item.nomeProduto,
                      ),
                    );
                  }
                }
                if (linhas.isEmpty) {
                  ScaffoldMessenger.of(dialogContext).showSnackBar(
                    const SnackBar(
                      content: Text(
                        'Informe falta em pelo menos um item (valor maior que zero).',
                      ),
                    ),
                  );
                  return;
                }
                Navigator.pop(
                  dialogContext,
                  ComplementoEntregaCodec.encode(linhas),
                );
              },
              child: const Text('Registrar complemento pendente'),
            ),
          ],
        );
      },
    );
    for (final c in controllers.values) {
      c.dispose();
    }
    final obsExtra = obsCtrl.text.trim();
    obsCtrl.dispose();
    if (jsonResult == null || jsonResult.trim().isEmpty || !mounted) return;
    await _atualizarStatusEntrega(
      venda,
      'entregue_complemento_pendente',
      complementoEntregaJson: jsonResult,
      notaComplementoExtra: obsExtra.isEmpty ? null : obsExtra,
    );
  }

  void _atualizarChecklistCarga(
    Venda venda, {
    bool? separado,
    bool? carregado,
    bool? saiu,
  }) {
    try {
      if (!_checklistPodeAtualizar(
        venda,
        separado: separado,
        carregado: carregado,
        saiu: saiu,
      )) {
        if (!mounted) return;
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(_mensagemChecklistInvalido())));
        return;
      }
      widget.vendaRepository.atualizarChecklistCargaEntrega(
        venda.id,
        separado: separado,
        carregado: carregado,
        saiu: saiu,
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Erro ao atualizar checklist: $e')),
      );
    }
  }

  Future<void> _abrirDetalhesItensVenda(Venda venda) async {
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (dialogContext, setDialogState) {
            final exibir =
                widget.vendaRepository.obterPorId(venda.id) ?? venda;
            final usaMigrado = _vendaUsaItensCarretoMigrado(exibir);
            final itensLista = exibir.itens
                .where((i) => _quantidadeExibicaoEntrega(exibir, i) > 0)
                .toList();
            return AlertDialog(
              title: Text(
                usaMigrado
                    ? 'Itens para entrega ${exibir.numeroOrcamento}'
                    : 'Itens do pedido ${exibir.numeroOrcamento}',
              ),
              content: SizedBox(
                width: 620,
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      EntregaPodFotoPanel(
                        key: ValueKey(
                          '${exibir.podRecebidoPor}|${exibir.podRegistradoEm}|'
                          '${exibir.podFotoPathServidor}',
                        ),
                        venda: exibir,
                        configRepository: widget.appConfigRepository,
                        podeEditar: widget.podeRegistrarPodEntrega,
                        onEditar: () async {
                          final ok = await _editarPodEntrega(exibir);
                          if (ok) {
                            final ref =
                                widget.vendaRepository.obterPorId(venda.id);
                            if (ref != null) {
                              _copiarCamposPod(venda, ref);
                              _copiarCamposPod(exibir, ref);
                            }
                            setDialogState(() {});
                            _carregarEntregas();
                          }
                        },
                      ),
                      if (itensLista.isEmpty)
                        const Text('Nenhum item encontrado para esta entrega.')
                      else ...[
                        Text(
                          'Cliente: ${exibir.cliente.target?.nomeRazao ?? 'Sem cliente'}',
                        ),
                      Text('Vendedor: ${_nomeVendedor(exibir)}'),
                      if (usaMigrado) ...[
                        const SizedBox(height: 6),
                        Text(
                          'Somente o que segue no carreto (cliente ja pode ter retirado parte na loja).',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ],
                      if (!usaMigrado &&
                          _vendaCarretoReservaNativaSemMigracao(exibir) &&
                          exibir.itens.any((i) => i.quantidadeJaRetirada > 0)) ...[
                        const SizedBox(height: 6),
                        Text(
                          'Parte dos itens ja foi retirada na loja antes da saida do carro; '
                          'abaixo consta o que ainda segue para entrega.',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ],
                      const SizedBox(height: 8),
                      ListView.separated(
                          shrinkWrap: true,
                          physics: const NeverScrollableScrollPhysics(),
                          itemCount: itensLista.length,
                          separatorBuilder: (_, _) => const Divider(height: 10),
                          itemBuilder: (context, index) {
                            final item = itensLista[index];
                            final q = _quantidadeExibicaoEntrega(exibir, item);
                            final sub = _subtotalExibicaoEntrega(exibir, item);
                            return Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                SizedBox(
                                  width: 52,
                                  child: Text(
                                    '${q}x',
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        item.nomeProduto,
                                        style: const TextStyle(
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                      Text(
                                        EntregaVendaHelper.rotuloTipoItem(
                                          item.tipoEntregaItem,
                                        ),
                                        style: Theme.of(context)
                                            .textTheme
                                            .labelSmall,
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(width: 12),
                                SizedBox(
                                  width: 170,
                                  child: Text(
                                    '${_formatarMoeda(item.precoUnitario)} / un',
                                    textAlign: TextAlign.right,
                                  ),
                                ),
                                const SizedBox(width: 12),
                                SizedBox(
                                  width: 130,
                                  child: Text(
                                    _formatarMoeda(sub),
                                    textAlign: TextAlign.right,
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ),
                              ],
                            );
                          },
                        ),
                      const SizedBox(height: 10),
                      Text(
                        'Total na carga: ${_formatarMoeda(itensLista.fold<double>(0, (s, i) => s + _subtotalExibicaoEntrega(exibir, i)))}',
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                      if (usaMigrado)
                        Text(
                          'Total da venda (produtos): ${_formatarMoeda(exibir.total)}',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                  ],
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Fechar'),
            ),
          ],
            );
          },
        );
      },
    );
  }

  Future<void> _abrirChecklistCargaEntrega(Venda venda) async {
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: Text('Checklist de carga ${venda.numeroOrcamento}'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Cliente: ${venda.cliente.target?.nomeRazao ?? 'Sem cliente'}',
                  ),
                  Text('Vendedor: ${_nomeVendedor(venda)}'),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      FilterChip(
                        label: const Text('Separado'),
                        selected: venda.cargaSeparada,
                        onSelected: (v) {
                          _atualizarChecklistCarga(venda, separado: v);
                          setDialogState(() {
                            venda.cargaSeparada = v;
                          });
                          _carregarEntregas();
                        },
                      ),
                      FilterChip(
                        label: const Text('Carregado'),
                        selected: venda.cargaCarregada,
                        onSelected: (v) {
                          _atualizarChecklistCarga(venda, carregado: v);
                          setDialogState(() {
                            venda.cargaCarregada = v;
                          });
                          _carregarEntregas();
                        },
                      ),
                      FilterChip(
                        label: const Text('Saiu'),
                        selected: venda.cargaSaiu,
                        onSelected: (v) {
                          _atualizarChecklistCarga(venda, saiu: v);
                          setDialogState(() {
                            venda.cargaSaiu = v;
                          });
                          _carregarEntregas();
                        },
                      ),
                    ],
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Fechar'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Widget _buildCardEntrega(
    Venda venda,
    DateFormat dateFormat,
    DateFormat dataMarcadaFmt, {
    bool dentroDeGrupoCarreto = false,
    bool modoSelecao = false,
    bool selecionada = false,
    int? paradaNoMesmoCarro,
  }) {
    final statusCor = _corStatus(
      Theme.of(context).colorScheme,
      venda.statusEntrega,
    );
    final progressoCarga = _progressoCarga(venda);
    final corCarga = _corProgressoCarga(context, progressoCarga);
    final prioridade = venda.prioridadeEntrega;
    final historico = widget.vendaRepository.listarHistoricoEntrega(venda.id);
    final ultimoEvento = historico.isEmpty ? null : historico.last;
    return Card(
      elevation: dentroDeGrupoCarreto ? 0 : null,
      margin: dentroDeGrupoCarreto
          ? EdgeInsets.zero
          : const EdgeInsets.only(bottom: 8),
      color: dentroDeGrupoCarreto
          ? Theme.of(context).colorScheme.surface
          : null,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: modoSelecao
            ? () => _alternarSelecaoEntrega(venda.id)
            : () => _abrirDetalhesItensVenda(venda),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (modoSelecao)
                    Padding(
                      padding: const EdgeInsets.only(right: 4, top: 2),
                      child: Checkbox(
                        value: selecionada,
                        onChanged: (_) => _alternarSelecaoEntrega(venda.id),
                        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        visualDensity: VisualDensity.compact,
                      ),
                    ),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                'Venda ${venda.numeroOrcamento} - ${_formatarMoeda(venda.total)}',
                                style: Theme.of(context)
                                    .textTheme
                                    .titleMedium
                                    ?.copyWith(
                                      fontWeight: FontWeight.w700,
                                    ),
                              ),
                            ),
                            if (venda.tipoEntrega ==
                                EntregaVendaHelper.tipoMisto)
                              Chip(
                                label: const Text('Mista'),
                                visualDensity: VisualDensity.compact,
                                backgroundColor: Theme.of(context)
                                    .colorScheme
                                    .tertiaryContainer,
                              ),
                          ],
                        ),
                        if (venda.tipoEntrega == EntregaVendaHelper.tipoMisto)
                          Padding(
                            padding: const EdgeInsets.only(top: 4),
                            child: Text(
                              EntregaVendaHelper.resumoContagem(
                                venda.itens.map((i) => i.tipoEntregaItem),
                              ),
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                          ),
                        const SizedBox(height: 6),
            if (paradaNoMesmoCarro != null) ...[
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Material(
                  color: Theme.of(context).colorScheme.primary,
                  borderRadius: BorderRadius.circular(8),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 7,
                    ),
                    child: Text(
                      'Parada #$paradaNoMesmoCarro',
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.onPrimary,
                        fontWeight: FontWeight.w800,
                        fontSize: 15,
                      ),
                    ),
                  ),
                ),
              ),
            ],
            const SizedBox(height: 4),
            Text(
              'Cliente: ${venda.cliente.target?.nomeRazao ?? 'Sem cliente'}',
            ),
            Text('Vendedor: ${_nomeVendedor(venda)}'),
            Text('Endereco: ${venda.enderecoEntrega}'),
            Text('Frete: ${_formatarMoeda(venda.valorFrete)}'),
            Text('Criado em: ${dateFormat.format(venda.data.toLocal())}'),
            Wrap(
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: 6,
              runSpacing: 2,
              children: [
                Text(
                  venda.dataEntregaMarcada == null
                      ? 'Entrega marcada: Sem data definida.'
                      : 'Entrega marcada: ${dataMarcadaFmt.format(venda.dataEntregaMarcada!.toLocal())}.',
                ),
                if (widget.podeGerenciarStatusEntrega)
                  TextButton(
                    style: TextButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      minimumSize: Size.zero,
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                    onPressed: () => _marcarOuAlterarDataEntrega(venda),
                    child: Text(
                      venda.dataEntregaMarcada == null
                          ? 'Definir data'
                          : 'Alterar data',
                    ),
                  ),
              ],
            ),
            Text('Motorista: ${_nomeMotorista(venda)}'),
            if (ultimoEvento != null)
              Text(
                'Ultima mudanca: ${dateFormat.format(ultimoEvento.dataHora.toLocal())} por ${ultimoEvento.usuario}',
              ),
            if (_observacaoSemMotorista(venda).trim().isNotEmpty)
              Text('Obs: ${_observacaoSemMotorista(venda)}'),
            if (_textoResumoComplementoNaVenda(venda) case final resumoComp?)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  resumoComp,
                  style: TextStyle(
                    color: Colors.deepOrange.shade900,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            const SizedBox(height: 4),
            const Text('Clique no pedido para ver os itens comprados'),
            const SizedBox(height: 6),
            Wrap(
              spacing: 8,
              runSpacing: 6,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(99),
                    color: statusCor.withValues(alpha: 0.12),
                    border: Border.all(color: statusCor.withValues(alpha: 0.4)),
                  ),
                  child: Text(
                    _rotuloStatusEntrega(venda.statusEntrega),
                    style: TextStyle(
                      color: statusCor,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(99),
                    color: Theme.of(context).colorScheme.primaryContainer,
                  ),
                  child: Text('Prioridade: ${_rotuloPrioridade(prioridade)}'),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(99),
                    color: Theme.of(
                      context,
                    ).colorScheme.surfaceContainerHighest,
                  ),
                  child: Text(
                    'Janela: ${_rotuloJanelaEntrega(venda.janelaEntrega)}',
                  ),
                ),
                InkWell(
                  borderRadius: BorderRadius.circular(99),
                  onTap: () => _abrirChecklistCargaEntrega(venda),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(99),
                      color: corCarga.withValues(alpha: 0.12),
                      border: Border.all(
                        color: corCarga.withValues(alpha: 0.4),
                      ),
                    ),
                    child: Text(
                      'Carga: $progressoCarga/3',
                      style: TextStyle(
                        color: corCarga,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
                EntregaPodChip(venda: venda),
              ],
            ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      visualDensity: VisualDensity.compact,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 6,
                      ),
                    ),
                    onPressed: () => _abrirNavegacaoParaEntrega(venda),
                    icon: const Icon(Icons.directions_rounded, size: 18),
                    label: const Text('Navegar'),
                  ),
                  OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      visualDensity: VisualDensity.compact,
                    ),
                    onPressed: () => _abrirDetalhesItensVenda(venda),
                    icon: const Icon(Icons.receipt_long, size: 18),
                    label: const Text('Ver itens'),
                  ),
                  OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      visualDensity: VisualDensity.compact,
                    ),
                    onPressed: () => _abrirHistoricoEntrega(venda),
                    icon: const Icon(Icons.history, size: 18),
                    label: const Text('Historico'),
                  ),
                  if (_podeDevolucaoPosCarretoNaEntrega(venda))
                    Tooltip(
                      message:
                          'Cliente devolveu ou avaria: devolve estoque (carreto com carga ja saida). '
                          'Se faltou item na ida, use "Faltou item".',
                      child: OutlinedButton.icon(
                        style: OutlinedButton.styleFrom(
                          visualDensity: VisualDensity.compact,
                        ),
                        onPressed: () =>
                            _abrirRegistrarDevolucaoPosCarreto(venda),
                        icon: const Icon(
                          Icons.assignment_return_outlined,
                          size: 18,
                        ),
                        label: const Text('Devolucao'),
                      ),
                    ),
                  OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      visualDensity: VisualDensity.compact,
                    ),
                    onPressed: () => _editarMotoristaEntrega(venda),
                    icon: const Icon(Icons.person_outline, size: 18),
                    label: const Text('Motorista'),
                  ),
                  if (venda.statusEntrega == 'saiu_entrega') ...[
                    TextButton.icon(
                      style: TextButton.styleFrom(
                        visualDensity: VisualDensity.compact,
                      ),
                      onPressed: widget.podeGerenciarStatusEntrega
                          ? () => _abrirDialogRegistrarComplemento(venda)
                          : null,
                      icon: const Icon(Icons.inventory_2_outlined, size: 18),
                      label: const Text('Faltou item'),
                    ),
                    TextButton.icon(
                      style: TextButton.styleFrom(
                        visualDensity: VisualDensity.compact,
                      ),
                      onPressed: widget.podeGerenciarStatusEntrega
                          ? () => _atualizarStatusEntrega(venda, 'entregue')
                          : null,
                      icon: const Icon(Icons.check_circle_outline, size: 18),
                      label: const Text('Marcar entregue'),
                    ),
                  ],
                  if (venda.statusEntrega == 'entregue_complemento_pendente')
                    TextButton.icon(
                      style: TextButton.styleFrom(
                        visualDensity: VisualDensity.compact,
                      ),
                      onPressed: widget.podeGerenciarStatusEntrega
                          ? () => _confirmarConcluirComplemento(venda)
                          : null,
                      icon: const Icon(Icons.task_alt_outlined, size: 18),
                      label: const Text('Concluir complemento'),
                    ),
                  PopupMenuButton<String>(
                    tooltip: 'Mais acoes',
                    onSelected: (value) {
                if (value == _kMenuMarcarDataEntrega) {
                  _marcarOuAlterarDataEntrega(venda);
                  return;
                }
                if (value == _kMenuLimparDataEntrega) {
                  _limparDataEntregaMarcada(venda);
                  return;
                }
                if (value == _kMenuDevolucaoPosCarreto) {
                  _abrirRegistrarDevolucaoPosCarreto(venda);
                  return;
                }
                if (value == _kMenuRetiradaLojaCarreto) {
                  _abrirRegistrarRetiradaLojaCarretoAntesSaida(venda);
                  return;
                }
                if (value.startsWith('prioridade:')) {
                  final p = value.split(':').last;
                  _atualizarPrioridade(venda, p);
                  return;
                }
                _atualizarStatusEntrega(venda, value);
              },
              itemBuilder: (context) => [
                if (_podeRegistrarRetiradaLojaAntesSaidaCarreto(venda))
                  PopupMenuItem(
                    enabled: widget.podeGerenciarStatusEntrega,
                    value: _kMenuRetiradaLojaCarreto,
                    child: const Text(
                      'Retirada na loja (antes do carro sair)',
                    ),
                  ),
                PopupMenuItem(
                  enabled: widget.podeGerenciarStatusEntrega,
                  value: _kMenuMarcarDataEntrega,
                  child: Text(
                    venda.dataEntregaMarcada == null
                        ? 'Marcar data de entrega'
                        : 'Alterar data de entrega',
                  ),
                ),
                if (venda.dataEntregaMarcada != null)
                  PopupMenuItem(
                    enabled: widget.podeGerenciarStatusEntrega,
                    value: _kMenuLimparDataEntrega,
                    child: const Text('Limpar data de entrega'),
                  ),
                const PopupMenuDivider(),
                PopupMenuItem(
                  enabled: widget.podeGerenciarStatusEntrega,
                  value: 'pendente',
                  child: const Text('Status: Pendente'),
                ),
                PopupMenuItem(
                  enabled: widget.podeGerenciarStatusEntrega,
                  value: 'roteirizada',
                  child: const Text('Status: Roteirizada'),
                ),
                PopupMenuItem(
                  enabled: widget.podeGerenciarStatusEntrega,
                  value: 'saiu_entrega',
                  child: const Text('Status: Saiu para entrega'),
                ),
                if (venda.statusEntrega != 'saiu_entrega' &&
                    venda.statusEntrega != 'entregue_complemento_pendente')
                  PopupMenuItem(
                    enabled: widget.podeGerenciarStatusEntrega,
                    value: 'entregue',
                    child: const Text('Status: Entregue'),
                  ),
                PopupMenuItem(
                  enabled: widget.podeGerenciarStatusEntrega,
                  value: 'reagendada',
                  child: const Text('Status: Reagendada'),
                ),
                PopupMenuItem(
                  enabled: widget.podeGerenciarStatusEntrega,
                  value: 'cancelada',
                  child: const Text('Status: Cancelada'),
                ),
                if (_podeDevolucaoPosCarretoNaEntrega(venda)) ...[
                  const PopupMenuDivider(),
                  PopupMenuItem(
                    value: _kMenuDevolucaoPosCarreto,
                    child: const Text('Devolucao / troca (mercadoria voltou)'),
                  ),
                ],
                const PopupMenuDivider(),
                const PopupMenuItem(
                  value: 'prioridade:normal',
                  child: Text('Prioridade: Normal'),
                ),
                const PopupMenuItem(
                  value: 'prioridade:urgente',
                  child: Text('Prioridade: Urgente'),
                ),
                const PopupMenuItem(
                  value: 'prioridade:agendada',
                  child: Text('Prioridade: Agendada'),
                ),
              ],
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPainelGrupoCarretoLista(
    List<Venda> bloco,
    DateFormat dateFormat,
    DateFormat dataMarcadaFmt,
  ) {
    final scheme = Theme.of(context).colorScheme;
    final ordenado = ordenarBlocoMesmoCarro(bloco);
    final grupoId = ordenado.first.grupoEntregaFreteId;
    final motorista = _nomeMotorista(ordenado.first);
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: scheme.tertiary.withValues(alpha: 0.55)),
      ),
      color: scheme.tertiaryContainer.withValues(alpha: 0.22),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ListTile(
            dense: true,
            isThreeLine: true,
            leading: Icon(
              Icons.local_shipping_outlined,
              color: scheme.tertiary,
            ),
            title: Text(
              rotuloGrupoLogistica(ordenado),
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
            subtitle: Text(
              '${ordenado.length} pedidos no mesmo veiculo · use as setas para '
              'a ordem de paradas (salva no banco).',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            trailing: IconButton(
              tooltip: 'Alterar motorista da viagem',
              icon: const Icon(Icons.person_outline),
              onPressed: () => _editarMotoristaGrupo(grupoId, motorista),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
            child: Row(
              children: [
                TextButton.icon(
                  onPressed: () => _emitirRelatorioEntrega(
                    tipo: RelatorioEntregaTipo.separacaoViagem,
                    viagem: ordenado,
                    salvarPdf: false,
                  ),
                  icon: const Icon(Icons.inventory_2_outlined, size: 18),
                  label: const Text('Separacao viagem'),
                ),
                if (motorista != 'Nao definido')
                  TextButton.icon(
                    onPressed: () => _emitirRelatorioEntrega(
                      tipo: RelatorioEntregaTipo.romaneioMotoristaDia,
                      motorista: motorista,
                      salvarPdf: false,
                    ),
                    icon: const Icon(Icons.assignment_outlined, size: 18),
                    label: const Text('Romaneio do motorista'),
                  ),
              ],
            ),
          ),
          const Divider(height: 1),
          Padding(
            padding: const EdgeInsets.fromLTRB(10, 8, 10, 10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (var i = 0; i < ordenado.length; i++) ...[
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Padding(
                        padding: const EdgeInsets.only(top: 4, right: 2),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              tooltip: 'Subir na rota',
                              visualDensity: VisualDensity.compact,
                              padding: EdgeInsets.zero,
                              constraints: const BoxConstraints(
                                minWidth: 30,
                                minHeight: 26,
                              ),
                              onPressed: i == 0
                                  ? null
                                  : () => _swapParadasMesmoCarro(
                                        grupoId,
                                        ordenado,
                                        i,
                                        i - 1,
                                      ),
                              icon: Icon(
                                Icons.arrow_upward_rounded,
                                size: 20,
                                color: scheme.onSurfaceVariant,
                              ),
                            ),
                            IconButton(
                              tooltip: 'Descer na rota',
                              visualDensity: VisualDensity.compact,
                              padding: EdgeInsets.zero,
                              constraints: const BoxConstraints(
                                minWidth: 30,
                                minHeight: 26,
                              ),
                              onPressed: i == ordenado.length - 1
                                  ? null
                                  : () => _swapParadasMesmoCarro(
                                        grupoId,
                                        ordenado,
                                        i,
                                        i + 1,
                                      ),
                              icon: Icon(
                                Icons.arrow_downward_rounded,
                                size: 20,
                                color: scheme.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Expanded(
                        child: _buildCardEntrega(
                          ordenado[i],
                          dateFormat,
                          dataMarcadaFmt,
                          dentroDeGrupoCarreto: true,
                          modoSelecao: _modoAgruparMesmoCarro,
                          selecionada: _idsEntregasSelecionadas.contains(
                            ordenado[i].id,
                          ),
                          paradaNoMesmoCarro: i + 1,
                        ),
                      ),
                    ],
                  ),
                  if (i < ordenado.length - 1) const SizedBox(height: 10),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  List<Venda> _listaEntregasPlanejadasExibicao() {
    final dataMarcadaFmt = DateFormat('dd/MM/yyyy');
    if (_chaveDiaPlanejamentoSelecionado == null) {
      return List<Venda>.from(_entregas);
    }
    return _entregas
        .where(
          (v) => _vendaNaChaveDiaPlanejamento(
            v,
            _chaveDiaPlanejamentoSelecionado!,
            dataMarcadaFmt,
          ),
        )
        .toList();
  }

  bool _vendaKanbanColunaPendentesHoje(Venda v) {
    final s = v.statusEntrega;
    return s == 'pendente' || s == 'reagendada';
  }

  int? _kanbanIndiceOrdenacaoStatus(String status) {
    switch (status) {
      case 'pendente':
      case 'reagendada':
        return 0;
      case 'roteirizada':
        return 1;
      case 'saiu_entrega':
      case 'entregue_complemento_pendente':
        return 2;
      case 'entregue':
        return 3;
      default:
        return null;
    }
  }

  /// Status alvo da coluna (0..3) no fluxo operacional principal.
  String? _statusEntregaColunaKanban(int coluna) {
    const statuses = ['pendente', 'roteirizada', 'saiu_entrega', 'entregue'];
    if (coluna < 0 || coluna >= statuses.length) return null;
    return statuses[coluna];
  }

  String? _proximoPassoKanbanEmDirecao(String atual, String destino) {
    if (atual == destino) return null;
    if (atual == 'reagendada' && destino == 'pendente') return 'pendente';
    if (atual == 'entregue_complemento_pendente' && destino == 'entregue') {
      return 'entregue';
    }
    final ia = _kanbanIndiceOrdenacaoStatus(atual);
    final ib = _kanbanIndiceOrdenacaoStatus(destino);
    if (ia == null || ib == null) return null;
    const seq = ['pendente', 'roteirizada', 'saiu_entrega', 'entregue'];
    if (ib > ia) return seq[ia + 1];
    if (ib < ia) {
      if (ia <= 0) return null;
      return seq[ia - 1];
    }
    return null;
  }

  bool _kanbanCaminhoInteiroValido(Venda vRef, String destino) {
    var s = vRef.statusEntrega;
    final v = vRef;
    var guard = 0;
    while (s != destino && guard++ < 8) {
      final next = _proximoPassoKanbanEmDirecao(s, destino);
      if (next == null) return false;
      if (!_transicaoStatusPermitida(s, next)) return false;
      if ((next == 'entregue' || next == 'entregue_complemento_pendente') &&
          _progressoCarga(v) < 3) {
        return false;
      }
      s = next;
    }
    return s == destino;
  }

  List<Venda> _filtrarKanban(List<Venda> fonte) {
    return fonte.where((v) => v.statusEntrega != 'cancelada').toList();
  }

  List<Venda> _entregasColunaKanban(List<Venda> visiveis, int col) {
    final base = _filtrarKanban(visiveis);
    switch (col) {
      case 0:
        return base.where(_vendaKanbanColunaPendentesHoje).toList();
      case 1:
        return base.where((v) => v.statusEntrega == 'roteirizada').toList();
      case 2:
        return base
            .where(
              (v) =>
                  v.statusEntrega == 'saiu_entrega' ||
                  v.statusEntrega == 'entregue_complemento_pendente',
            )
            .toList();
      case 3:
        return base.where((v) => v.statusEntrega == 'entregue').toList();
      default:
        return const [];
    }
  }

  bool _kanbanPodeSoltarNaColuna(int vendaId, int colDestino) {
    if (!widget.podeGerenciarStatusEntrega) return false;
    final v = widget.vendaRepository.obterPorId(vendaId);
    if (v == null || v.statusEntrega == 'cancelada') return false;
    final destino = _statusEntregaColunaKanban(colDestino);
    if (destino == null) return false;
    if (v.statusEntrega == destino) return false;
    if (destino == 'entregue' &&
        v.statusEntrega == 'entregue_complemento_pendente') {
      return true;
    }
    if (!_kanbanCaminhoInteiroValido(v, destino)) return false;
    return true;
  }

  Future<void> _onKanbanAceitarSoltar(int vendaId, int colDestino) async {
    if (!_kanbanPodeSoltarNaColuna(vendaId, colDestino)) return;

    var v = widget.vendaRepository.obterPorId(vendaId);
    if (v == null || !mounted) return;

    final destino = _statusEntregaColunaKanban(colDestino)!;

    if (destino == 'entregue' &&
        v.statusEntrega == 'entregue_complemento_pendente') {
      await _confirmarConcluirComplemento(v);
      return;
    }

    if (v.statusEntrega == destino) return;

    var passos = 0;
    var algumPasso = false;
    while (mounted && passos < 8) {
      passos++;
      v = widget.vendaRepository.obterPorId(vendaId);
      if (v == null) return;
      if (v.statusEntrega == destino) break;
      final prox = _proximoPassoKanbanEmDirecao(v.statusEntrega, destino);
      if (prox == null) break;
      final ok = await _atualizarStatusEntrega(
        v,
        prox,
        mostrarSnackSucesso: false,
      );
      if (!ok) break;
      algumPasso = true;
    }

    v = widget.vendaRepository.obterPorId(vendaId);
    if (!mounted) return;
    if (algumPasso && v != null && v.statusEntrega == destino) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Status de entrega atualizado (Kanban).'),
        ),
      );
    }
  }

  static const _titulosKanban = [
    'Pendentes hoje (fila)',
    'Roteirizadas',
    'Saiu para entrega',
    'Entregue',
  ];

  Widget _kanbanCardMosaico(Venda venda, DateFormat dataFmt) {
    final scheme = Theme.of(context).colorScheme;
    final statusCor = _corStatus(scheme, venda.statusEntrega);
    final subtitulo = venda.cliente.target?.nomeRazao ?? 'Sem cliente';
    return Card(
      elevation: 1,
      margin: const EdgeInsets.only(bottom: 8),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => _abrirDetalhesItensVenda(venda),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(10, 10, 10, 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Text(
                      'Venda ${venda.numeroOrcamento}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                  ),
                  Icon(Icons.drag_indicator, size: 18, color: scheme.outline),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                subtitulo,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const SizedBox(height: 6),
              Wrap(
                spacing: 6,
                runSpacing: 4,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(99),
                      color: statusCor.withValues(alpha: 0.14),
                      border: Border.all(
                        color: statusCor.withValues(alpha: 0.4),
                      ),
                    ),
                    child: Text(
                      _rotuloStatusEntrega(venda.statusEntrega),
                      style: TextStyle(
                        fontSize: 11,
                        color: statusCor,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  EntregaPodChip(venda: venda, compacto: true),
                  Text(
                    venda.dataEntregaMarcada == null
                        ? 'Sem data'
                        : dataFmt.format(venda.dataEntregaMarcada!.toLocal()),
                    style: Theme.of(context).textTheme.labelSmall,
                  ),
                  TextButton.icon(
                    style: TextButton.styleFrom(
                      visualDensity: VisualDensity.compact,
                      padding: const EdgeInsets.symmetric(horizontal: 6),
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                    onPressed: () => _abrirNavegacaoParaEntrega(venda),
                    icon: const Icon(Icons.directions_rounded, size: 18),
                    label: const Text('Navegar'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildKanbanCompactCard(
    Venda venda,
    DateFormat dataFmt,
  ) {
    if (!widget.podeGerenciarStatusEntrega) {
      return _kanbanCardMosaico(venda, dataFmt);
    }
    return Draggable<int>(
      data: venda.id,
      feedback: Material(
        elevation: 6,
        borderRadius: BorderRadius.circular(8),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 260),
          child: Opacity(
            opacity: 0.92,
            child: _kanbanCardMosaico(venda, dataFmt),
          ),
        ),
      ),
      childWhenDragging: Opacity(
        opacity: 0.35,
        child: _kanbanCardMosaico(venda, dataFmt),
      ),
      child: _kanbanCardMosaico(venda, dataFmt),
    );
  }

  Widget _colunaKanban(
    BuildContext context, {
    required int coluna,
    required List<Venda> itens,
    required DateFormat dataMarcadaFmt,
  }) {
    final scheme = Theme.of(context).colorScheme;
    const largura = 286.0;
    return DragTarget<int>(
      onWillAcceptWithDetails: (details) =>
          _kanbanPodeSoltarNaColuna(details.data, coluna),
      onAcceptWithDetails: (details) =>
          _onKanbanAceitarSoltar(details.data, coluna),
      builder: (context, candidateData, rejectedData) {
        final highlight = candidateData.isNotEmpty;
        return SizedBox(
          width: largura,
          child: Card(
            elevation: highlight ? 2 : 0,
            margin: const EdgeInsets.only(right: 10),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
              side: BorderSide(
                color: highlight
                    ? scheme.primary
                    : scheme.outlineVariant.withValues(alpha: 0.7),
                width: highlight ? 2 : 1,
              ),
            ),
            clipBehavior: Clip.antiAlias,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Material(
                  color: scheme.surfaceContainerHighest.withValues(alpha: 0.45),
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            _titulosKanban[coluna],
                            style: Theme.of(context).textTheme.titleSmall
                                ?.copyWith(fontWeight: FontWeight.w700),
                          ),
                        ),
                        Chip(
                          visualDensity: VisualDensity.compact,
                          padding: EdgeInsets.zero,
                          label: Text('${itens.length}'),
                          materialTapTargetSize:
                              MaterialTapTargetSize.shrinkWrap,
                        ),
                      ],
                    ),
                  ),
                ),
                Expanded(
                  child: itens.isEmpty
                      ? Center(
                          child: Padding(
                            padding: const EdgeInsets.all(16),
                            child: Text(
                              'Nenhum pedido',
                              textAlign: TextAlign.center,
                              style: Theme.of(context).textTheme.bodySmall
                                  ?.copyWith(color: scheme.outline),
                            ),
                          ),
                        )
                      : ListView.builder(
                          padding: const EdgeInsets.fromLTRB(8, 10, 8, 12),
                          itemCount: itens.length,
                          itemBuilder: (context, i) => _buildKanbanCompactCard(
                            itens[i],
                            dataMarcadaFmt,
                          ),
                        ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _corpoQuadroKanban(
    BuildContext context, {
    required List<Venda> listaVisivel,
    required DateFormat dataMarcadaFmt,
    required double altura,
  }) {
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      children: [
        if (!widget.podeGerenciarStatusEntrega)
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
            child: Text(
              _mensagemSemPermissaoStatus(),
              style: TextStyle(
                color: Theme.of(context).colorScheme.error,
                fontSize: 13,
              ),
            ),
          ),
        SizedBox(
          height: altura,
          child: SingleChildScrollView(
            controller: _kanbanHScrollController,
            scrollDirection: Axis.horizontal,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (var c = 0; c < 4; c++)
                  _colunaKanban(
                    context,
                    coluna: c,
                    itens: _entregasColunaKanban(listaVisivel, c),
                    dataMarcadaFmt: dataMarcadaFmt,
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  EntregasMontagemCallbacks get _callbacksMontagem => EntregasMontagemCallbacks(
        atualizarChecklist: (v, {separado, carregado, saiu}) =>
            _atualizarChecklistCarga(
          v,
          separado: separado,
          carregado: carregado,
          saiu: saiu,
        ),
        atualizarStatus: _atualizarStatusEntrega,
        emitirRelatorio: ({
          required tipo,
          motorista,
          viagem,
          required salvarPdf,
        }) =>
            _emitirRelatorioEntrega(
          tipo: tipo,
          motorista: motorista,
          viagem: viagem,
          salvarPdf: salvarPdf,
        ),
        trocarParada: _swapParadasMesmoCarro,
        editarMotoristaGrupo: _editarMotoristaGrupo,
        abrirDetalheItens: _abrirDetalhesItensVenda,
        abrirNavegacao: _abrirNavegacaoParaEntrega,
        recarregar: _carregarEntregas,
        confirmarAgrupamento: _confirmarAgrupamentoIds,
        removerAgrupamento: _removerAgrupamentoIds,
        editarMotoristaPedido: _editarMotoristaEntrega,
        definirMotoristaEmLote: _definirMotoristaEmLoteIds,
      );

  Widget _buildAbaMontagem(List<Venda> listaExibicao) {
    return PainelMontagemEntregas(
      entregas: listaExibicao,
      quantidadeItemEntrega: _quantidadeExibicaoEntrega,
      callbacks: _callbacksMontagem,
      podeGerenciarStatus: widget.podeGerenciarStatusEntrega,
      conferenciaRepository: _conferenciaCargaRepository,
      usuarioAtual: widget.usuarioAtual,
    );
  }

  Widget _buildAbaLista(
    List<Venda> listaExibicao,
    DateFormat dateFormat,
    DateFormat dataMarcadaFmt,
    List<String> gruposLista,
    Map<String, List<Venda>> groupedLista,
  ) {
    return Column(
      children: [
        if (_modoAgruparMesmoCarro) ...[
          EntregasBarraAgrupamentoMesmoCarro(
            selecionadas: _idsEntregasSelecionadas.length,
            onConfirmar: _idsEntregasSelecionadas.length >= 2
                ? _confirmarAgrupamentoMesmoCarro
                : null,
            onLimparSelecao: () => setState(_idsEntregasSelecionadas.clear),
            onRemoverAgrupamento: _removerAgrupamentoSelecionadas,
          ),
          const SizedBox(height: 6),
        ],
        Expanded(
          child: listaExibicao.isEmpty
              ? ListView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  children: [
                    SizedBox(height: 48),
                    Center(
                      child: Text(
                        _chaveDiaPlanejamentoSelecionado == null
                            ? 'Nenhuma entrega encontrada para os filtros.'
                            : 'Nenhuma entrega para o dia selecionado no planejamento.',
                      ),
                    ),
                  ],
                )
              : ListView.builder(
                  physics: const AlwaysScrollableScrollPhysics(),
                  itemCount: gruposLista.length,
                  itemBuilder: (context, bairroIndex) {
                    final grupo = gruposLista[bairroIndex];
                    final vendasBairro =
                        groupedLista[grupo] ?? const <Venda>[];
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Padding(
                          padding: const EdgeInsets.fromLTRB(4, 10, 4, 6),
                          child: Text(
                            '${_agrupamento == 'motorista' ? 'Motorista' : 'Bairro'}: $grupo (${vendasBairro.length})',
                            style: Theme.of(context).textTheme.titleSmall,
                          ),
                        ),
                        for (final bloco
                            in blocosEntregaComCarretoAgrupado(vendasBairro))
                          if (bloco.length >= 2 &&
                              bloco.first.grupoEntregaFreteId > 0)
                            _buildPainelGrupoCarretoLista(
                              bloco,
                              dateFormat,
                              dataMarcadaFmt,
                            )
                          else
                            ...bloco.map(
                              (v) => _buildCardEntrega(
                                v,
                                dateFormat,
                                dataMarcadaFmt,
                                modoSelecao: _modoAgruparMesmoCarro,
                                selecionada:
                                    _idsEntregasSelecionadas.contains(v.id),
                              ),
                            ),
                      ],
                    );
                  },
                ),
        ),
      ],
    );
  }

  Widget _buildAbaKanban(
    List<Venda> listaExibicao,
    DateFormat dataMarcadaFmt,
    double alturaKanban,
  ) {
    return _corpoQuadroKanban(
      context,
      listaVisivel: listaExibicao,
      dataMarcadaFmt: dataMarcadaFmt,
      altura: alturaKanban,
    );
  }

  @override
  Widget build(BuildContext context) {
    final dateFormat = DateFormat('dd/MM/yyyy HH:mm');
    final dataMarcadaFmt = DateFormat('dd/MM/yyyy');
    final atrasadas = _contagemAtrasadasCache;
    final pendentesHoje = _contagemPendentesHojeCache;
    final resumoPorDia = PlanejamentoEntregaDia.resumoDeEntregas(_entregas);
    final temProximosDias =
        PlanejamentoEntregaDia.proximosDiasComEntrega(resumoPorDia).isNotEmpty;
    final listaExibicao = _listaEntregasPlanejadasExibicao();
    final groupedLista = <String, List<Venda>>{};
    for (final venda in listaExibicao) {
      final chaveGrupo = _agrupamento == 'motorista'
          ? _nomeMotorista(venda)
          : _extrairBairro(venda);
      groupedLista.putIfAbsent(chaveGrupo, () => <Venda>[]).add(venda);
    }
    final gruposLista = groupedLista.keys.toList()
      ..sort((a, b) => a.compareTo(b));
    return DefaultTabController(
      length: 3,
      initialIndex: 0,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Entregas'),
          bottom: const TabBar(
            tabs: [
              Tab(
                icon: Icon(Icons.local_shipping_outlined),
                text: 'Montagem',
              ),
              Tab(
                icon: Icon(Icons.view_list_outlined),
                text: 'Lista',
              ),
              Tab(
                icon: Icon(Icons.view_kanban_outlined),
                text: 'Kanban',
              ),
            ],
          ),
          actions: [
            IconButton(
              tooltip: 'Atualizar',
              icon: const Icon(Icons.refresh),
              onPressed: _atualizarListaEntregas,
            ),
          ],
        ),
        body: Padding(
          padding: const EdgeInsets.fromLTRB(8, 8, 8, 8),
          child: Column(
            children: [
              EntregasBarraCompacta(
              atrasadas: atrasadas,
              pendentesHoje: pendentesHoje,
              filtroAtrasadasAtivo:
                  _filtroResumoLista == _FiltroResumoEntregas.atrasadas,
              filtroPendentesHojeAtivo:
                  _filtroResumoLista == _FiltroResumoEntregas.pendentesHoje,
              onFiltroAtrasadas: (ligar) {
                setState(() {
                  _filtroResumoLista = ligar
                      ? _FiltroResumoEntregas.atrasadas
                      : _FiltroResumoEntregas.nenhum;
                });
                _carregarEntregas();
              },
              onFiltroPendentesHoje: (ligar) {
                setState(() {
                  _filtroResumoLista = ligar
                      ? _FiltroResumoEntregas.pendentesHoje
                      : _FiltroResumoEntregas.nenhum;
                });
                _carregarEntregas();
              },
              mostrarPlanejamento: _entregas.isNotEmpty,
              resumoPorDia: resumoPorDia,
              chaveDiaSelecionada: _chaveDiaPlanejamentoSelecionado,
              onSelecionarDia: _selecionarDiaPlanejamento,
              onAbrirSeletorDia: () => _abrirSeletorPlanejamentoDia(resumoPorDia),
              filtrosAtivos: _contagemFiltrosAtivos(),
              onAbrirFiltros: _abrirFiltrosEntrega,
              mostrarRelatorios: _entregas.isNotEmpty,
              onRelatorios: _abrirRelatoriosEntrega,
              mostrarProximosDias: _entregas.isNotEmpty && temProximosDias,
              proximosDiasExpandido: _proximosDiasPlanejamentoExpandido,
              onAlternarProximosDias: () {
                setState(() {
                  _proximosDiasPlanejamentoExpandido =
                      !_proximosDiasPlanejamentoExpandido;
                });
              },
            ),
            if (!widget.podeGerenciarStatusEntrega) ...[
              const SizedBox(height: 8),
              MaterialBanner(
                padding: const EdgeInsets.all(12),
                leading: const Icon(Icons.visibility_outlined),
                content: const Text(
                  'Modo somente leitura — voce pode acompanhar entregas, '
                  'mas nao alterar status, motorista ou montagem de carga.',
                ),
                actions: const [SizedBox.shrink()],
              ),
            ],
            const SizedBox(height: 6),
            Expanded(
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final alturaKanban =
                      (constraints.maxHeight - 4).clamp(280.0, 4000.0);
                  return RefreshIndicator(
                    onRefresh: _atualizarListaEntregas,
                    child: _entregas.isEmpty
                        ? ListView(
                            physics: const AlwaysScrollableScrollPhysics(),
                            children: const [
                              SizedBox(height: 48),
                              Center(
                                child: Text(
                                  'Nenhuma entrega encontrada para os filtros.',
                                ),
                              ),
                            ],
                          )
                        : TabBarView(
                            children: [
                              _buildAbaMontagem(listaExibicao),
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  Align(
                                    alignment: Alignment.centerRight,
                                    child: TextButton.icon(
                                      onPressed: () {
                                        setState(() {
                                          _modoAgruparMesmoCarro =
                                              !_modoAgruparMesmoCarro;
                                          if (!_modoAgruparMesmoCarro) {
                                            _idsEntregasSelecionadas.clear();
                                          }
                                        });
                                      },
                                      icon: Icon(
                                        Icons.merge_type_outlined,
                                        color: _modoAgruparMesmoCarro
                                            ? Theme.of(context)
                                                .colorScheme
                                                .primary
                                            : null,
                                      ),
                                      label: Text(
                                        _modoAgruparMesmoCarro
                                            ? 'Sair do modo agrupar viagens'
                                            : 'Agrupar mesmo carro (lista)',
                                      ),
                                    ),
                                  ),
                                  Expanded(
                                    child: _buildAbaLista(
                                      listaExibicao,
                                      dateFormat,
                                      dataMarcadaFmt,
                                      gruposLista,
                                      groupedLista,
                                    ),
                                  ),
                                ],
                              ),
                              _buildAbaKanban(
                                listaExibicao,
                                dataMarcadaFmt,
                                alturaKanban,
                              ),
                            ],
                          ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
      ),
    );
  }
}

/// Romaneio (dialogo): bloco "mesmo carro" com [Por pedido] ou [Carga consolidada].
class _PainelRomaneioGrupoMesmoCarro extends StatefulWidget {
  const _PainelRomaneioGrupoMesmoCarro({
    required this.bloco,
    required this.setDialogStateRomaneio,
    required this.quantidadeItemEntrega,
    required this.conteudoRomaneioUmaVenda,
    required this.escopoViagem,
    required this.conferenciaRepository,
    required this.usuarioAtual,
  });

  final List<Venda> bloco;
  final StateSetter setDialogStateRomaneio;
  final int Function(Venda venda, ItemVenda item) quantidadeItemEntrega;
  final Widget Function(
    BuildContext context,
    Venda venda,
    StateSetter setDialogStateRomaneio,
  ) conteudoRomaneioUmaVenda;
  final String escopoViagem;
  final ConferenciaCargaRepository conferenciaRepository;
  final String usuarioAtual;

  @override
  State<_PainelRomaneioGrupoMesmoCarro> createState() =>
      _PainelRomaneioGrupoMesmoCarroState();
}

class _PainelRomaneioGrupoMesmoCarroState
    extends State<_PainelRomaneioGrupoMesmoCarro> {
  static const int _abaPorPedido = 0;
  static const int _abaConsolidada = 1;

  int _abaRomaneioGrupo = _abaPorPedido;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final linhas = romaneioMergeCargaGrupo(
      widget.bloco,
      widget.quantidadeItemEntrega,
    );
    return Container(
      decoration: BoxDecoration(
        color: scheme.tertiaryContainer.withValues(alpha: 0.22),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: scheme.tertiary.withValues(alpha: 0.45)),
      ),
      padding: const EdgeInsets.all(10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            rotuloGrupoLogistica(widget.bloco),
            style: Theme.of(context).textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
          ),
          Text('${widget.bloco.length} pedidos no mesmo veiculo'),
          const SizedBox(height: 8),
          SizedBox(
            width: double.infinity,
            child: SegmentedButton<int>(
              segments: const [
                ButtonSegment<int>(
                  value: _abaPorPedido,
                  label: Text('Por pedido'),
                  icon: Icon(Icons.list_alt_outlined),
                ),
                ButtonSegment<int>(
                  value: _abaConsolidada,
                  label: Text('Carga consolidada (total do carro)'),
                  icon: Icon(Icons.inventory_2_outlined),
                ),
              ],
              selected: {_abaRomaneioGrupo},
              onSelectionChanged: (Set<int> s) {
                setState(() => _abaRomaneioGrupo = s.first);
              },
            ),
          ),
          const Divider(height: 16),
          if (_abaRomaneioGrupo == _abaPorPedido)
            ...[
              for (var i = 0; i < widget.bloco.length; i++) ...[
                widget.conteudoRomaneioUmaVenda(
                  context,
                  widget.bloco[i],
                  widget.setDialogStateRomaneio,
                ),
                if (i < widget.bloco.length - 1) const Divider(height: 12),
              ],
            ]
          else
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Quantidades somadas de todos os pedidos deste veiculo. '
                  'Marque ao conferir a separacao no patio.',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                const SizedBox(height: 6),
                ConferenciaCargaConsolidadaLista(
                  linhas: linhas,
                  escopoViagem: widget.escopoViagem,
                  conferenciaRepository: widget.conferenciaRepository,
                  usuarioAtual: widget.usuarioAtual,
                  vendasGrupo: widget.bloco,
                  quantidadeEntrega: widget.quantidadeItemEntrega,
                ),
              ],
            ),
        ],
      ),
    );
  }
}

class _DialogRetiradaLojaCarretoAntesSaida extends StatefulWidget {
  const _DialogRetiradaLojaCarretoAntesSaida({
    required this.venda,
    required this.vendaRepository,
    required this.usuario,
  });

  final Venda venda;
  final VendaRepository vendaRepository;
  final String usuario;

  @override
  State<_DialogRetiradaLojaCarretoAntesSaida> createState() =>
      _DialogRetiradaLojaCarretoAntesSaidaState();
}

class _DialogRetiradaLojaCarretoAntesSaidaState
    extends State<_DialogRetiradaLojaCarretoAntesSaida> {
  late final Map<int, TextEditingController> _controllers;
  late final TextEditingController _quemRetirouController;

  List<ItemVenda> get _itensCarretoPendentes => widget.venda.itens
      .where((i) => i.quantidadeAindaNoCarretoAntesSaida > 0)
      .toList();

  @override
  void initState() {
    super.initState();
    _quemRetirouController = TextEditingController();
    _controllers = {
      for (final it in _itensCarretoPendentes)
        it.id: TextEditingController(text: ''),
    };
  }

  @override
  void dispose() {
    _quemRetirouController.dispose();
    for (final c in _controllers.values) {
      c.dispose();
    }
    super.dispose();
  }

  void _preencherPendente() {
    for (final it in _itensCarretoPendentes) {
      final c = _controllers[it.id];
      if (c != null) {
        c.text = '${it.quantidadeAindaNoCarretoAntesSaida}';
      }
    }
    setState(() {});
  }

  Future<void> _confirmar() async {
    final map = <int, int>{};
    for (final it in _itensCarretoPendentes) {
      final c = _controllers[it.id];
      if (c == null) continue;
      final q = int.tryParse(c.text.trim()) ?? 0;
      if (q > 0) {
        map[it.id] = q;
      }
    }
    if (map.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Informe ao menos uma quantidade maior que zero.'),
        ),
      );
      return;
    }
    try {
      final quem = _quemRetirouController.text.trim();
      widget.vendaRepository.registrarRetiradaParcialLojaCarretoAntesSaida(
        widget.venda.id,
        map,
        usuario: widget.usuario,
        retiradoPor: quem.isEmpty ? null : quem,
      );
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Nao foi possivel registrar: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AlertDialog(
      title: const Text('Retirada na loja (antes do carro sair)'),
      content: SizedBox(
        width: 440,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Informe quantas unidades o cliente esta retirando agora na loja. '
                'So e permitido ate o checklist marcar "Saiu". O romaneio e a carga '
                'passam a mostrar apenas o que ainda segue no carro.',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 12),
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton(
                  onPressed: _preencherPendente,
                  child: const Text(
                    'Preencher com toda a quantidade ainda destinada ao carro',
                  ),
                ),
              ),
              TextField(
                controller: _quemRetirouController,
                textCapitalization: TextCapitalization.words,
                decoration: const InputDecoration(
                  labelText: 'Quem retirou (opcional)',
                  hintText: 'Nome de quem leva a mercadoria',
                  isDense: true,
                ),
              ),
              const SizedBox(height: 12),
              for (final it in _itensCarretoPendentes)
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              it.nomeProduto,
                              style: theme.textTheme.titleSmall?.copyWith(
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            Text(
                              'Ainda para o carro: '
                              '${it.quantidadeAindaNoCarretoAntesSaida} un.',
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: theme.colorScheme.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ),
                      ),
                      SizedBox(
                        width: 88,
                        child: TextField(
                          controller: _controllers[it.id],
                          enabled: it.quantidadeAindaNoCarretoAntesSaida > 0,
                          keyboardType: TextInputType.number,
                          textAlign: TextAlign.right,
                          decoration: const InputDecoration(
                            labelText: 'Qtd',
                            isDense: true,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          onPressed: _confirmar,
          child: const Text('Registrar retirada'),
        ),
      ],
    );
  }
}
