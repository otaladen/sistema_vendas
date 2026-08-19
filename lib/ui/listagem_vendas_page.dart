import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import '../data/app_config_repository.dart';
import '../data/api/lan_api_client.dart';
import '../data/api/venda_api_repository.dart';
import '../data/sync/lan_sync_scheduler.dart';
import '../data/venda_repository.dart';
import 'shell/main_menu_deps.dart';
import '../domain/entrega_venda_helper.dart';
import '../domain/venda_documento_rotulo_helper.dart';
import '../domain/pagamento_orcamento.dart';
import '../model/cliente.dart';
import '../model/item_venda.dart';
import '../model/usuario_sistema.dart';
import '../model/venda.dart';
import '../model/vendedor.dart';
import '../services/cupom_nao_fiscal_venda_pdf.dart';
import '../services/print_service.dart';
import 'clientes_page.dart';
import 'cupom_venda_impressao_helper.dart';
import '../services/esc_pos_cupom_builder.dart';
import 'segunda_via_cupom_autorizacao.dart';
import '../services/venda_fiscal_service.dart';
import 'vendas/cancelar_venda_ui.dart';
import 'vendas/listagem_venda_item_ui.dart';
import 'vendas/listagem_vendas_cabecalho.dart';
import 'vendas/listagem_vendas_filtros_panel.dart';
import 'vendas/listagem_vendas_layout.dart';
import 'vendas/listagem_vendas_lista_cards.dart';
import 'vendas/listagem_vendas_ordenacao.dart';
import 'vendas/listagem_vendas_tabela.dart';
import '../config/focus_nfe_runtime.dart';
import 'widgets/lan_api_feedback.dart';
import '../domain/fiscal/abrir_danfe_focus.dart';
import '../services/focus_nfe_service.dart';
import 'fiscal/abrir_documento_fiscal.dart';
import 'fiscal/emitir_nfce_venda_flow.dart';
import 'fiscal/widgets/devolucao_fiscal_historico_panel.dart';
import 'pdv_vendedor_bloqueio.dart';
import 'registrar_devolucao_troca_page.dart';

/// Lista vendas já finalizadas no Caixa (`status == finalizada`), com filtros e busca.
class ListagemVendasPage extends StatefulWidget {
  const ListagemVendasPage({
    super.key,
    required this.vendaRepository,
    required this.clienteRepository,
    required this.vendedorRepository,
    required this.produtoRepository,
    required this.appConfigRepository,
    required this.printService,
    required this.usuarioAtual,
    required this.podeCancelarVendas,
    required this.usuarioLogado,
    this.periodoPresetInicial,
  });

  final dynamic vendaRepository;
  final dynamic clienteRepository;
  final dynamic vendedorRepository;
  final dynamic produtoRepository;
  final AppConfigRepository appConfigRepository;
  final PrintService printService;
  final String usuarioAtual;
  final bool podeCancelarVendas;
  final UsuarioSistema usuarioLogado;

  /// Preset inicial (`hoje`, `ultimos_30`, …). Usado pelo KPI "Vendas hoje".
  final String? periodoPresetInicial;

  @override
  State<ListagemVendasPage> createState() => _ListagemVendasPageState();
}

/// Filtro pendente ao abrir a listagem pelo KPI do Inicio.
abstract final class ListagemVendasAbertura {
  static String? _periodoPresetPendente;

  static bool get temPeriodoPendente =>
      (_periodoPresetPendente ?? '').trim().isNotEmpty;

  static void agendarPeriodo(String preset) {
    _periodoPresetPendente = preset;
  }

  static String? consumirPeriodo() {
    final v = _periodoPresetPendente;
    _periodoPresetPendente = null;
    return v;
  }
}

class _ListagemVendasPageState extends State<ListagemVendasPage> {
  static const int _tamPaginaListagem = 20;

  final NumberFormat _currency = NumberFormat('#,##0.00', 'pt_BR');
  final DateFormat _dataHora = DateFormat('dd/MM/yyyy HH:mm');
  final DateFormat _dataDia = DateFormat('dd/MM/yyyy');
  final _buscaController = TextEditingController();
  late dynamic _usuarioRepository;
  late final FocusNfeService _focusNfeService = FocusNfeService(
    config: criarFocusNfeConfigPadrao(),
  );

  String _periodoPreset = 'ultimos_30';
  DateTime? _dataPersonalizadaInicio;
  DateTime? _dataPersonalizadaFim;
  String _formaPagamento = 'todos';
  String _tipoEntrega = 'todos';
  String _entregaPendente = 'todos';
  String _filtroFiscal = 'todos';
  String _filtroCancelamento = 'ativas';
  String _canceladaPorFiltro = 'todos';

  List<Venda> _resultados = [];

  /// Itens ja resolvidos (sem query no build).
  List<ListagemVendaItemUi> _itensUi = [];
  List<String> _distintosCanceladaPor = [];
  int _offsetListagem = 0;
  int _totalListagemVendas = 0;
  double _valorTotalFiltro = 0;
  bool _carregandoListagem = false;
  int _pesquisaSeq = 0;
  Timer? _debounceFiltros;
  ListagemVendasColuna _colunaOrdenacao = ListagemVendasColuna.data;
  bool _ordenacaoAscendente = false;

  @override
  void initState() {
    super.initState();
    final periodo =
        widget.periodoPresetInicial ?? ListagemVendasAbertura.consumirPeriodo();
    if (periodo != null && periodo.trim().isNotEmpty) {
      _periodoPreset = periodo.trim();
    }
    _usuarioRepository =
        MainMenuDeps.resolverUsuarioRepository(context);
    try {
      _distintosCanceladaPor = (widget.vendaRepository
                  .listarDistintosCanceladaPor() as List?)
              ?.whereType<String>()
              .toList() ??
          const [];
    } catch (e) {
      debugPrint('ListagemVendas.initState: $e');
      _distintosCanceladaPor = const [];
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) unawaited(_pesquisar());
    });
  }

  @override
  void dispose() {
    _debounceFiltros?.cancel();
    _buscaController.dispose();
    super.dispose();
  }

  void _agendarPesquisa() {
    _debounceFiltros?.cancel();
    _debounceFiltros = Timer(const Duration(milliseconds: 300), () {
      if (mounted) unawaited(_pesquisar());
    });
  }

  String _formatarMoeda(double valor) => 'R\$ ${_currency.format(valor)}';

  /// Resolve NF-e 55 uma vez (preferindo campos ja na venda).
  VendaDocumentoNfe55Resumo? _nfe55ResumoDeVenda(Venda v) {
    try {
      if (v.nfe55Autorizada) {
        return VendaDocumentoNfe55Resumo(numero: v.nfeNumero, autorizada: true);
      }
      final nfe55 = widget.vendaRepository.obterNfe55AutorizadaPorVenda(v.id);
      if (nfe55 == null) return null;
      final numero = (nfe55.numero ?? '').toString();
      final autorizada = nfe55.autorizada == true;
      if (!autorizada) return null;
      return VendaDocumentoNfe55Resumo(numero: numero, autorizada: true);
    } catch (_) {
      return null;
    }
  }

  String _rotuloCupomFiscalLista(Venda v, {VendaDocumentoNfe55Resumo? nfe55}) {
    return VendaDocumentoRotuloHelper.rotuloIdentificacaoLista(
      v,
      nfe55: nfe55 ?? _nfe55ResumoDeVenda(v),
    );
  }

  String _statusOperacionalLista(Venda v, {VendaDocumentoNfe55Resumo? nfe55}) {
    return VendaDocumentoRotuloHelper.statusOperacionalLista(
      v,
      nfe55: nfe55 ?? _nfe55ResumoDeVenda(v),
    );
  }

  String _statusOperacionalResumidoLista(
    Venda v, {
    VendaDocumentoNfe55Resumo? nfe55,
  }) {
    return VendaDocumentoRotuloHelper.statusOperacionalResumidoLista(
      v,
      nfe55: nfe55 ?? _nfe55ResumoDeVenda(v),
    );
  }

  Color _corStatusOperacionalLista(Venda v, ColorScheme scheme) {
    return VendaDocumentoRotuloHelper.corStatusLista(v, scheme);
  }

  Future<void> _verDanfeNfce(Venda v) async {
    await abrirDanfeFocus(
      context,
      focusNfe: _focusNfeService,
      urlSalva: v.nfceUrlDanfe,
      venda: v,
    );
  }

  EmitirNfceVendaDeps get _emitirNfceDeps => EmitirNfceVendaDeps(
    vendaRepository: widget.vendaRepository,
    clienteRepository: widget.clienteRepository,
    vendedorRepository: widget.vendedorRepository,
    produtoRepository: widget.produtoRepository,
    appConfigRepository: widget.appConfigRepository,
    printService: widget.printService,
    focusNfeService: _focusNfeService,
  );

  Future<void> _emitirNfce(Venda v) async {
    // Terminal leve: Focus/SEFAZ so no PC servidor (mesmo padrao do caixa).
    if (widget.vendaRepository is VendaApiRepository) {
      final client = MainMenuDeps.maybeOf(context)?.lanApiClient;
      if (client == null) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'API do servidor indisponivel para emitir NFC-e.',
            ),
          ),
        );
        return;
      }
      try {
        final r = await client.emitirNfce(v.id);
        if (!mounted) return;
        if (r['ok'] == true) {
          try {
            await (widget.vendaRepository as VendaApiRepository)
                .atualizarVendaFinalizadaNoCache(v.id);
          } catch (_) {}
          if (mounted) setState(_pesquisar);
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                r['autorizada'] == true
                    ? 'NFC-e ${(r['numero'] ?? '').toString()} autorizada no servidor.'
                    : 'NFC-e em processamento no servidor.',
              ),
            ),
          );
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('${r['error'] ?? 'Falha ao emitir NFC-e'}'),
            ),
          );
        }
      } catch (e) {
        if (!mounted) return;
        LanApiFeedback.snackErro(context, e, prefixo: 'Falha ao emitir NFC-e');
      }
      return;
    }
    await EmitirNfceVendaFlow.executar(
      context,
      deps: _emitirNfceDeps,
      venda: v,
      onConcluidoComSucesso: () {
        if (mounted) {
          setState(_pesquisar);
        }
      },
    );
  }

  Future<void> _verNfe55(Venda v) async {
    final reg = widget.vendaRepository.obterNfe55AutorizadaPorVenda(v.id);
    if (reg == null) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Nenhuma NF-e modelo 55 autorizada para esta venda.'),
        ),
      );
      return;
    }
    final url = reg.urlDanfe.trim().isNotEmpty ? reg.urlDanfe : reg.urlXml;
    await abrirUrlDocumentoFiscal(
      context,
      url,
      mensagemSeVazio: 'NF-e autorizada, mas sem link de DANFE/XML salvo.',
    );
  }

  double _parseValorMonetario(String valor) {
    final normalizado = valor.trim().replaceAll('.', '').replaceAll(',', '.');
    if (normalizado.isEmpty) return 0;
    return double.tryParse(normalizado) ?? 0;
  }

  bool _podeRegistrarDevolucaoTroca(Venda v) {
    if (v.cancelada || v.status != 'finalizada') return false;
    if (v.vendaOrigemFreteRetiradaId > 0) return false;
    return _itensDaVendaSync(v)
        .any((i) => i.quantidade - i.quantidadeDevolvida > 0);
  }

  Future<void> _abrirDevolucoesFiscais(Venda v) async {
    if (widget.vendaRepository is! VendaRepository) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Consulta de devolucoes fiscais disponivel no PC servidor.',
          ),
        ),
      );
      return;
    }
    final fiscalSvc = VendaFiscalService(
      vendaRepository: widget.vendaRepository as VendaRepository,
      clienteRepository: widget.clienteRepository,
    );
    final fiscais = fiscalSvc.listarDevolucoesFiscaisPorVenda(v.id);
    if (fiscais.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Nenhuma NF-e de devolucao vinculada a esta venda.'),
        ),
      );
      return;
    }
    await mostrarDialogoListaDevolucoesFiscais(context, fiscais: fiscais);
  }

  bool _temDevolucaoFiscal(Venda v) {
    if (widget.vendaRepository is! VendaRepository) return false;
    final fiscalSvc = VendaFiscalService(
      vendaRepository: widget.vendaRepository as VendaRepository,
      clienteRepository: widget.clienteRepository,
    );
    return fiscalSvc.listarDevolucoesFiscaisPorVenda(v.id).isNotEmpty;
  }

  Future<void> _abrirRegistrarDevolucaoTroca(Venda v) async {
    if (!_podeRegistrarDevolucaoTroca(v)) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Devolucao/troca nao disponivel para esta venda.'),
        ),
      );
      return;
    }
    final ok = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => RegistrarDevolucaoTrocaPage(
          vendaRepository: widget.vendaRepository,
          clienteRepository: widget.clienteRepository,
          produtoRepository: widget.produtoRepository,
          vendaId: v.id,
          usuarioAtual: widget.usuarioAtual,
          podeRegistrarSemSenha: widget.podeCancelarVendas,
          usuarioLogado: widget.usuarioLogado,
          vendedorRepository: widget.vendedorRepository,
          appConfigRepository: widget.appConfigRepository,
          printService: widget.printService,
        ),
      ),
    );
    if (ok == true && mounted) {
      _pesquisar();
    }
  }

  bool _podePagarFreteCarreto(Venda v) {
    if (v.cancelada || v.status != 'finalizada') return false;
    if (v.tipoEntrega != 'retirada_futura' || !v.entregaPendente) return false;
    if (v.idOrcamentoFreteRetiradaAberto != 0) return false;
    return _itensDaVendaSync(v).any((i) => i.quantidadePendenteRetirada > 0);
  }

  String _montarEnderecoEntregaClienteListagem(Cliente cliente) {
    final partes = <String>[];
    final endereco = cliente.endereco.trim();
    final numero = cliente.numero.trim();
    final bairro = cliente.bairro.trim();
    final cidade = cliente.cidade.trim();
    final uf = cliente.uf.trim();
    final cep = cliente.cep.trim();
    if (endereco.isNotEmpty) {
      partes.add(numero.isNotEmpty ? '$endereco, $numero' : endereco);
    }
    if (bairro.isNotEmpty) {
      partes.add(bairro);
    }
    final cidadeUf = [cidade, uf].where((p) => p.isNotEmpty).join(' - ');
    if (cidadeUf.isNotEmpty) {
      partes.add(cidadeUf);
    }
    if (cep.isNotEmpty) {
      partes.add('CEP: $cep');
    }
    return partes.join(' | ');
  }

  Future<void> _abrirPagarFreteCarreto(Venda vIn) async {
    var v = widget.vendaRepository.obterPorId(vIn.id) ?? vIn;
    if (!_podePagarFreteCarreto(v)) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Nao e possivel gerar frete agora (verifique retirada futura, pendencia e se ja existe orcamento de frete).',
          ),
        ),
      );
      return;
    }

    if (_clienteDaVenda(v) == null) {
      if (!mounted) return;
      final c = await Navigator.push<Cliente>(
        context,
        MaterialPageRoute(
          builder: (_) => ClientesPage(
            clienteRepository: widget.clienteRepository,
            vendaRepository: widget.vendaRepository,
            retornarClienteAoSalvar: true,
          ),
        ),
      );
      if (!mounted || c == null) return;
      final repo = widget.vendaRepository;
      try {
        if (repo is VendaApiRepository) {
          await repo.vincularClienteVendaFinalizadaRemoto(v.id, c.id);
        } else {
          repo.vincularClienteVendaFinalizada(v.id, c.id);
        }
      } catch (e) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(LanApiFeedback.mensagem(e))),
        );
        return;
      }
      v = widget.vendaRepository.obterPorId(v.id) ?? v;
    }

    final cliente = _clienteDaVenda(v);
    if (cliente == null) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Cadastre e vincule o cliente primeiro.')),
      );
      return;
    }

    if (!mounted) return;
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        return _DialogoFreteCarretoRetiradaFutura(
          vendaMae: v,
          cliente: cliente,
          enderecoInicial: _montarEnderecoEntregaClienteListagem(cliente),
          observacaoInicial: cliente.referencia.trim(),
          vendaRepository: widget.vendaRepository,
          formatarMoeda: _formatarMoeda,
          parseValor: _parseValorMonetario,
          onSucesso: () {
            _pesquisar();
          },
        );
      },
    );
  }

  String _rotuloVendaUsuario(Venda v) =>
      VendaDocumentoRotuloHelper.rotuloTituloLista(v);

  String _badgeNumeroVenda(Venda v) =>
      VendaDocumentoRotuloHelper.badgeNumeroCurto(v);

  Cliente? _clienteDaVenda(Venda venda) {
    // Entidade detached (API): .target pode lancar; preferir targetId + repo.
    try {
      final ligado = venda.cliente.target;
      if (ligado != null) return ligado;
    } catch (_) {}
    final id = venda.cliente.targetId;
    if (id == 0) return null;
    try {
      return widget.clienteRepository.obterPorId(id) as Cliente?;
    } catch (_) {
      return null;
    }
  }

  Vendedor? _vendedorDaVenda(Venda venda) {
    try {
      final ligado = venda.vendedor.target;
      if (ligado != null) return ligado;
    } catch (_) {}
    final id = venda.vendedor.targetId;
    if (id == 0) return null;
    try {
      return widget.vendedorRepository.obterPorId(id) as Vendedor?;
    } catch (_) {
      return null;
    }
  }

  String _rotuloVendedorUmLinha(Venda venda) {
    final v = _vendedorDaVenda(venda);
    if (v == null) return 'Sem vendedor';
    final nome = v.apelido.trim().isNotEmpty
        ? v.apelido.trim()
        : v.nomeCompleto.trim();
    final codigo = v.codigoInterno.trim();
    return codigo.isEmpty ? nome : '$codigo · $nome';
  }

  (DateTime?, DateTime?) _limitesPeriodo() {
    final now = DateTime.now();
    final fimDia = DateTime(now.year, now.month, now.day, 23, 59, 59, 999);
    switch (_periodoPreset) {
      case 'hoje':
        final inicio = DateTime(now.year, now.month, now.day);
        return (inicio, fimDia);
      case 'ultimos_7':
        final inicio = DateTime(
          now.year,
          now.month,
          now.day,
        ).subtract(const Duration(days: 6));
        return (inicio, fimDia);
      case 'ultimos_30':
        final inicio = DateTime(
          now.year,
          now.month,
          now.day,
        ).subtract(const Duration(days: 29));
        return (inicio, fimDia);
      case 'mes_atual':
        return (DateTime(now.year, now.month, 1), fimDia);
      case 'mes_anterior':
        final inicio = DateTime(now.year, now.month - 1, 1);
        final fim = DateTime(now.year, now.month, 0, 23, 59, 59, 999);
        return (inicio, fim);
      case 'ano_atual':
        return (DateTime(now.year, 1, 1), fimDia);
      case 'personalizado':
        final di = _dataPersonalizadaInicio;
        final df = _dataPersonalizadaFim;
        if (di == null || df == null) {
          return (null, null);
        }
        var inicio = DateTime(di.year, di.month, di.day);
        var fim = DateTime(df.year, df.month, df.day, 23, 59, 59, 999);
        if (inicio.isAfter(fim)) {
          final t = inicio;
          inicio = DateTime(df.year, df.month, df.day);
          fim = DateTime(t.year, t.month, t.day, 23, 59, 59, 999);
        }
        return (inicio, fim);
      case 'todo':
      default:
        return (null, null);
    }
  }

  Future<void> _escolherDataInicioPersonalizado() async {
    final hoje = DateTime.now();
    final inicial =
        _dataPersonalizadaInicio ?? DateTime(hoje.year, hoje.month, hoje.day);
    final d = await showDatePicker(
      context: context,
      initialDate: inicial,
      firstDate: DateTime(2000),
      lastDate: DateTime(hoje.year + 1, 12, 31),
    );
    if (!mounted || d == null) return;
    setState(() {
      _dataPersonalizadaInicio = DateTime(d.year, d.month, d.day);
      if (_dataPersonalizadaFim != null &&
          _dataPersonalizadaInicio!.isAfter(_dataPersonalizadaFim!)) {
        _dataPersonalizadaFim = DateTime(
          _dataPersonalizadaInicio!.year,
          _dataPersonalizadaInicio!.month,
          _dataPersonalizadaInicio!.day,
          23,
          59,
          59,
          999,
        );
      }
    });
    _agendarPesquisa();
  }

  Future<void> _escolherDataFimPersonalizado() async {
    final hoje = DateTime.now();
    final inicial =
        _dataPersonalizadaFim ??
        _dataPersonalizadaInicio ??
        DateTime(hoje.year, hoje.month, hoje.day);
    final d = await showDatePicker(
      context: context,
      initialDate: inicial,
      firstDate: DateTime(2000),
      lastDate: DateTime(hoje.year + 1, 12, 31),
    );
    if (!mounted || d == null) return;
    setState(() {
      _dataPersonalizadaFim = DateTime(d.year, d.month, d.day, 23, 59, 59, 999);
      if (_dataPersonalizadaInicio != null &&
          _dataPersonalizadaInicio!.isAfter(_dataPersonalizadaFim!)) {
        _dataPersonalizadaInicio = DateTime(
          _dataPersonalizadaFim!.year,
          _dataPersonalizadaFim!.month,
          _dataPersonalizadaFim!.day,
        );
      }
    });
    _agendarPesquisa();
  }

  String _rotuloFormaPagamento(String forma) {
    switch (forma) {
      case 'pix':
        return 'PIX';
      case 'cartao_credito':
        return 'Cartao de credito';
      case 'cartao_debito':
        return 'Cartao de debito';
      case 'fiado':
        return 'Fiado';
      case 'transferencia':
        return 'Transferencia';
      case 'dinheiro':
        return 'Dinheiro';
      case 'misto':
        return 'Pagamento misto';
      default:
        return 'Dinheiro';
    }
  }

  String _rotuloPagamentoLinhaLista(Venda v) {
    if (v.formaPagamento != 'misto' || v.pagamentosJson.trim().isEmpty) {
      return '${_rotuloFormaPagamento(v.formaPagamento)}'
          '${v.formaPagamento == 'cartao_credito' ? ' ${v.quantidadeParcelas}x' : ''}';
    }
    final linhas = PagamentoOrcamentoCodec.decode(v.pagamentosJson);
    return linhas
        .map(
          (l) =>
              '${_rotuloFormaPagamento(l.meio)} ${_formatarMoeda(l.valor)}'
              '${l.meio == 'cartao_credito' ? ' ${l.parcelas}x' : ''}',
        )
        .join(' | ');
  }

  String _rotuloTipoEntrega(String tipo) =>
      EntregaVendaHelper.rotuloTipoEntregaVenda(tipo);

  String _textoEntregaLista(Venda v) {
    if (v.tipoEntrega == EntregaVendaHelper.tipoMisto) {
      final tipos = _itensDaVendaSync(v).map((i) => i.tipoEntregaItem);
      return '${_rotuloTipoEntrega(v.tipoEntrega)} (${EntregaVendaHelper.resumoContagem(tipos)})';
    }
    return _rotuloTipoEntrega(v.tipoEntrega);
  }

  String _linhaRetiradaFutura(Venda v) {
    if (!v.entregaPendente) {
      return 'Retirada futura: Nao';
    }
    final unidades = _itensDaVendaSync(v).fold<int>(
      0,
      (a, i) => a + i.quantidadePendenteRetirada,
    );
    return 'Retirada futura: Pendente ($unidades un. a retirar)';
  }

  bool _vendaTemRetiradaPendenteParaCliente(Venda v) {
    if (v.cancelada || v.status != 'finalizada') return false;
    try {
      final itens = _itensDaVendaSync(v);
      return itens.any((i) => i.quantidadePendenteRetirada > 0) ||
          EntregaVendaHelper.vendaPermiteRetiradaLojaCarretoAntesSaida(
            v,
            itens: itens,
          );
    } catch (_) {
      return false;
    }
  }

  Future<void> _abrirRegistrarRetirada(Venda v) async {
    final atual = widget.vendaRepository.obterPorId(v.id);
    if (atual == null || !_vendaTemRetiradaPendenteParaCliente(atual)) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Nao ha itens pendentes para o cliente retirar na loja '
            '(retirada futura ou carreto antes da saida do romaneio).',
          ),
        ),
      );
      return;
    }
    final itens = await _itensDaVendaAsync(atual);
    if (!mounted) return;
    if (itens.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Nao foi possivel carregar os itens desta venda.'),
        ),
      );
      return;
    }
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => _DialogRegistrarRetiradaCliente(
        venda: atual,
        itens: itens,
        vendaRepository: widget.vendaRepository,
        vendedorRepository: widget.vendedorRepository,
        usuarioRepository: _usuarioRepository,
      ),
    );
    if (ok == true && mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Retirada registrada.')));
      _pesquisar();
    }
  }

  /// Observacao de entrega (log com data/operador) ou itens com retirada ja registrada.
  bool _temRegistroRetiradaOuEntrega(Venda v) {
    if (v.observacaoEntrega.trim().isNotEmpty) return true;
    try {
      final itens = _itensDaVendaSync(v);
      return itens.any((i) => i.quantidadeJaRetirada > 0);
    } catch (_) {
      return false;
    }
  }

  /// Itens da venda sem depender de ToMany (quebrado no terminal leve / entidade detached).
  List<ItemVenda> _itensDaVendaSync(Venda v) {
    try {
      final viaRepo =
          widget.vendaRepository.listarItensPorVenda(v.id) as List<ItemVenda>?;
      if (viaRepo != null && viaRepo.isNotEmpty) return viaRepo;
    } catch (_) {}
    try {
      final locais = v.itens.toList();
      if (locais.isNotEmpty) return locais;
    } catch (_) {}
    return const [];
  }

  Future<List<ItemVenda>> _itensDaVendaAsync(Venda v) async {
    final repo = widget.vendaRepository;
    if (repo is VendaApiRepository) {
      try {
        return await repo.carregarItensRemoto(v.id);
      } catch (_) {
        return _itensDaVendaSync(v);
      }
    }
    return _itensDaVendaSync(v);
  }

  Future<void> _mostrarHistoricoRetirada(Venda v) async {
    try {
      final atual = widget.vendaRepository.obterPorId(v.id) ?? v;
      final itens = await _itensDaVendaAsync(atual);
      final linhas = <String>[];
      if (atual.observacaoEntrega.trim().isNotEmpty) {
        linhas.add(atual.observacaoEntrega.trim());
      }
      final comRetirada =
          itens.where((i) => i.quantidadeJaRetirada > 0).toList();
      if (comRetirada.isNotEmpty) {
        if (linhas.isNotEmpty) linhas.add('');
        linhas.add('Resumo — ja retirado por item:');
        for (final i in comRetirada) {
          linhas.add('- ${i.nomeProduto}: ${i.quantidadeJaRetirada} un.');
        }
      }
      final texto = linhas.isEmpty
          ? 'Nenhum registro de retirada ou texto de entrega nesta venda.'
          : linhas.join('\n');

      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Historico de retiradas e entrega'),
          content: SizedBox(
            width: 480,
            child: SingleChildScrollView(child: SelectableText(texto)),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Fechar'),
            ),
          ],
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Nao foi possivel abrir o historico: $e')),
      );
    }
  }

  Future<void> _segundaViaCupom(Venda vIn) async {
    final v = widget.vendaRepository.obterPorId(vIn.id) ?? vIn;
    if (v.cancelada) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Nao e possivel emitir cupom de venda cancelada.'),
        ),
      );
      return;
    }
    if (v.status != 'finalizada') {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Segunda via disponivel apenas para vendas finalizadas.',
          ),
        ),
      );
      return;
    }
    final config = await widget.appConfigRepository.carregarEmpresaConfig();
    if (!mounted) return;
    final autorizado = await autorizarSegundaViaCupomSeConfigurado(
      context: context,
      usuarioRepository: _usuarioRepository,
      exigirAutorizacao: config.exigirAutorizacaoSegundaViaCupom,
    );
    if (!mounted || !autorizado) return;

    // Terminal Leve: carrega itens via API (ToMany detached quebra o PDF).
    final itens = await _itensDaVendaAsync(v);
    if (!mounted) return;
    if (itens.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Nao foi possivel carregar os itens desta venda para o PDF.',
          ),
        ),
      );
      return;
    }

    final infer = CupomNaoFiscalVendaPdf.inferirRecebidoTrocoSegundaVia(v);
    final nomeArquivo =
        'venda_${v.numeroOrcamento > 0 ? v.numeroOrcamento : v.id}_2via.pdf';
    await mostrarFluxoImpressaoCupomVenda(
      context,
      printService: widget.printService,
      config: config,
      title: 'Segunda via do cupom',
      content: 'Deseja imprimir ou gerar PDF da segunda via?',
      gerarPdf: () => CupomNaoFiscalVendaPdf.gerar(
        venda: v,
        config: config,
        cliente: _clienteDaVenda(v),
        vendedor: _vendedorDaVenda(v),
        totalRecebido: infer.recebido,
        troco: infer.troco,
        segundaVia: true,
        dataCabecalhoVenda: v.data,
        itens: itens,
      ),
      dadosEscPos: CupomBalcaoDados(
        venda: v,
        config: config,
        itens: itens,
        cliente: _clienteDaVenda(v),
        vendedor: _vendedorDaVenda(v),
        totalRecebido: infer.recebido,
        troco: infer.troco,
        segundaVia: true,
      ),
      suggestedFileName: nomeArquivo,
    );
  }

  Future<void> _mostrarModalItensVenda(Venda v) async {
    if (!mounted) return;
    final venda = widget.vendaRepository.obterPorId(v.id) ?? v;
    final itens = await _itensDaVendaAsync(venda);
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          title: Text('Produtos — ${_rotuloVendaUsuario(venda)}'),
          content: SizedBox(
            width: 440,
            child: itens.isEmpty
                ? const Text('Nenhum item registrado nesta venda.')
                : ConstrainedBox(
                    constraints: const BoxConstraints(maxHeight: 420),
                    child: SingleChildScrollView(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          for (final item in itens)
                            Padding(
                              padding: const EdgeInsets.symmetric(vertical: 6),
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  SizedBox(
                                    width: 44,
                                    child: Text(
                                      EntregaVendaHelper.abreviacaoTipoItem(
                                        item.tipoEntregaItem,
                                      ),
                                      style: TextStyle(
                                        fontWeight: FontWeight.w700,
                                        color: Theme.of(
                                          ctx,
                                        ).colorScheme.primary,
                                      ),
                                    ),
                                  ),
                                  Expanded(
                                    child: Text(
                                      '${item.quantidadeExibicaoVenda} x ${item.nomeProduto}',
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  Text(
                                    _formatarMoeda(item.subtotal),
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Fechar'),
            ),
          ],
        );
      },
    );
  }

  Future<ListagemVendasPagina> _obterPaginaListagem({
    required int offset,
  }) async {
    final filtros = _montarFiltroListagemAtual();
    final repo = widget.vendaRepository;
    if (repo is VendaApiRepository) {
      return repo.hidratarListagemVendas(
        filtros,
        offset: offset,
        limite: _tamPaginaListagem,
      );
    }
    return repo.listarListagemVendasPaginaComTotal(
      filtros,
      offset: offset,
      limite: _tamPaginaListagem,
    ) as ListagemVendasPagina;
  }

  Future<void> _pesquisar() async {
    _debounceFiltros?.cancel();
    final seq = ++_pesquisaSeq;
    setState(() => _carregandoListagem = true);
    try {
      final pagina = await _obterPaginaListagem(offset: 0);
      final distintosCancel = widget.vendaRepository
          .listarDistintosCanceladaPor();
      if (!mounted || seq != _pesquisaSeq) return;
      final scheme = Theme.of(context).colorScheme;
      final vendas = (pagina.vendas as List).whereType<Venda>().toList();
      final itensUi = _mapearVendasParaItensUi(vendas, scheme);
      setState(() {
        _resultados = vendas;
        _itensUi = itensUi;
        _totalListagemVendas = pagina.total;
        _valorTotalFiltro = pagina.totalValor;
        _offsetListagem = vendas.length;
        _carregandoListagem = false;
        _distintosCanceladaPor =
            (distintosCancel as List?)?.whereType<String>().toList() ??
                const [];
        if (_canceladaPorFiltro != 'todos' &&
            !_distintosCanceladaPor.contains(_canceladaPorFiltro)) {
          _canceladaPorFiltro = 'todos';
        }
      });
    } catch (e, st) {
      debugPrint('ListagemVendas._pesquisar: $e\n$st');
      if (!mounted || seq != _pesquisaSeq) return;
      setState(() {
        _resultados = const [];
        _itensUi = const [];
        _totalListagemVendas = 0;
        _valorTotalFiltro = 0;
        _offsetListagem = 0;
        _carregandoListagem = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Erro ao carregar vendas: $e')),
      );
    }
  }

  Future<void> _carregarMaisVendas() async {
    if (_carregandoListagem) return;
    if (_resultados.length >= _totalListagemVendas) {
      return;
    }
    setState(() => _carregandoListagem = true);
    try {
      final pagina = await _obterPaginaListagem(offset: _offsetListagem);
      if (!mounted) return;
      final scheme = Theme.of(context).colorScheme;
      setState(() {
        _resultados.addAll(pagina.vendas);
        _offsetListagem += (pagina.vendas as List).length;
        _totalListagemVendas = pagina.total;
        _valorTotalFiltro = pagina.totalValor;
        _itensUi = _mapearVendasParaItensUi(_resultados, scheme);
        _carregandoListagem = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _carregandoListagem = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Erro ao carregar mais vendas: $e')),
      );
    }
  }

  FiltroListagemVendas _montarFiltroListagemAtual() {
    final range = _limitesPeriodo();
    return FiltroListagemVendas(
      textoBusca: _buscaController.text,
      dataInicioUtc: range.$1?.toUtc(),
      dataFimUtc: range.$2?.toUtc(),
      filtroCancelamento: _filtroCancelamento,
      canceladaPorFiltro: _canceladaPorFiltro,
      formaPagamento: _formaPagamento,
      tipoEntrega: _tipoEntrega,
      entregaPendente: _entregaPendente,
      filtroFiscal: _filtroFiscal,
    );
  }

  void _limparFiltros() {
    setState(() {
      _periodoPreset = 'ultimos_30';
      _dataPersonalizadaInicio = null;
      _dataPersonalizadaFim = null;
      _formaPagamento = 'todos';
      _tipoEntrega = 'todos';
      _entregaPendente = 'todos';
      _filtroFiscal = 'todos';
      _filtroCancelamento = 'ativas';
      _canceladaPorFiltro = 'todos';
      _buscaController.clear();
    });
    _pesquisar();
  }

  int _contarFiltrosAtivos() {
    var n = 0;
    if (_periodoPreset != 'ultimos_30') n++;
    if (_canceladaPorFiltro != 'todos') n++;
    if (_formaPagamento != 'todos') n++;
    if (_tipoEntrega != 'todos') n++;
    if (_filtroFiscal != 'todos') n++;
    if (_entregaPendente != 'todos') n++;
    if (_filtroCancelamento != 'ativas') n++;
    if (_buscaController.text.trim().isNotEmpty) n++;
    return n;
  }

  double get _valorTotalExibido => _valorTotalFiltro;

  /// Pre-carrega NFe / frete / devolucao em lote e monta o ViewModel.
  /// Chamado so apos pesquisa/pagina — nunca dentro de [build].
  List<ListagemVendaItemUi> _mapearVendasParaItensUi(
    List<Venda> vendas,
    ColorScheme scheme,
  ) {
    final freteIds = <int>{};
    for (final v in vendas) {
      final idFrete = v.idOrcamentoFreteRetiradaAberto;
      if (idFrete != 0) freteIds.add(idFrete);
    }
    final fretePorId = <int, Venda?>{
      for (final id in freteIds) id: widget.vendaRepository.obterPorId(id),
    };

    final nfePorId = <int, VendaDocumentoNfe55Resumo?>{};
    final devTrocaPorId = <int, ({double dev, double troca})>{};
    for (final v in vendas) {
      nfePorId[v.id] = _nfe55ResumoDeVenda(v);
      if (!v.cancelada && v.status == 'finalizada') {
        final viaApi = LanApiClient.devolucaoListagem[v];
        if (viaApi != null &&
            (viaApi.dev > 0.005 || viaApi.troca > 0.005)) {
          devTrocaPorId[v.id] = viaApi;
          continue;
        }
        try {
          final dev = widget.vendaRepository
              .valorReferenciaDevolvidoAcumuladoVenda(v.id) as double;
          final troca = widget.vendaRepository.valorSaidaTrocaAcumuladoVenda(
            v.id,
          ) as double;
          if (dev > 0.005 || troca > 0.005) {
            devTrocaPorId[v.id] = (dev: dev, troca: troca);
          }
        } catch (_) {}
      }
    }

    return [
      for (final v in vendas)
        () {
          try {
            return _montarItemUi(
              v,
              scheme: scheme,
              nfe55: nfePorId[v.id],
              freteFilho: fretePorId[v.idOrcamentoFreteRetiradaAberto],
              devTroca: devTrocaPorId[v.id],
            );
          } catch (e) {
            debugPrint('ListagemVendas.item ${v.id}: $e');
            return ListagemVendaItemUi(
              venda: v,
              titulo: 'Venda #${v.id}',
              status: v.cancelada ? 'Cancelada' : 'Finalizada',
              statusDetalhe: null,
              statusCor: v.cancelada ? scheme.error : scheme.primary,
              dataHora: _dataHora.format(v.data.toLocal()),
              cliente: 'Sem cliente',
              vendedor: 'Sem vendedor',
              pagamento: v.formaPagamento,
              entrega: v.tipoEntrega,
              badgeNumero: '${v.numeroOrcamento > 0 ? v.numeroOrcamento : v.id}',
              totalFormatado: _formatarMoeda(v.total),
              cancelada: v.cancelada,
              alertas: const [],
              temDevolucaoTroca: false,
            );
          }
        }(),
    ];
  }

  ListagemVendaItemUi _montarItemUi(
    Venda v, {
    required ColorScheme scheme,
    VendaDocumentoNfe55Resumo? nfe55,
    Venda? freteFilho,
    ({double dev, double troca})? devTroca,
  }) {
    final cliente = _clienteDaVenda(v);
    final alertas = <String>[];

    if (devTroca != null) {
      final liq = devTroca.troca - devTroca.dev;
      alertas.add(
        'Dev/troca: devolvido ${_formatarMoeda(devTroca.dev)} · saida '
        '${_formatarMoeda(devTroca.troca)} · liquido ${_formatarMoeda(liq)}',
      );
    }
    if (v.idOrcamentoFreteRetiradaAberto != 0) {
      final filho = freteFilho;
      final n = filho?.numeroOrcamento ?? 0;
      final rot = n > 0
          ? '#$n'
          : '(id ${filho?.id ?? v.idOrcamentoFreteRetiradaAberto})';
      alertas.add('Frete carreto pendente no caixa $rot');
    }
    if (_temRegistroRetiradaOuEntrega(v)) {
      alertas.add('Rastreio disponivel no historico de retiradas');
    }
    if (v.cancelada) {
      alertas.add(
        'Cancelada por: ${v.canceladaPor.isEmpty ? 'Nao informado' : v.canceladaPor}'
        '${v.canceladaEm == null ? '' : ' · ${_dataHora.format(v.canceladaEm!.toLocal())}'}'
        '${v.motivoCancelamento.isEmpty ? '' : ' · ${v.motivoCancelamento}'}',
      );
    }

    var entrega = _textoEntregaLista(v);
    if (v.entregaPendente) {
      entrega = '$entrega · Pendente';
      alertas.insert(0, _linhaRetiradaFutura(v));
    }

    final statusCompleto = v.cancelada
        ? 'Venda cancelada'
        : _statusOperacionalLista(v, nfe55: nfe55);
    final statusResumido = v.cancelada
        ? 'Cancelada'
        : _statusOperacionalResumidoLista(v, nfe55: nfe55);

    return ListagemVendaItemUi(
      venda: v,
      titulo: _rotuloCupomFiscalLista(v, nfe55: nfe55),
      status: statusResumido,
      statusDetalhe: statusCompleto != statusResumido ? statusCompleto : null,
      statusCor: v.cancelada
          ? scheme.error
          : _corStatusOperacionalLista(v, scheme),
      dataHora: _dataHora.format(v.data.toLocal()),
      cliente: cliente?.nomeRazao ?? 'Sem cliente',
      vendedor: _rotuloVendedorUmLinha(v),
      pagamento: _rotuloPagamentoLinhaLista(v),
      entrega: entrega,
      badgeNumero: _badgeNumeroVenda(v),
      totalFormatado: _formatarMoeda(v.total),
      cancelada: v.cancelada,
      alertas: alertas,
      temDevolucaoTroca: devTroca != null,
    );
  }

  void _executarAcaoMenu(String value, Venda v) {
    switch (value) {
      case 'historico':
        unawaited(_mostrarHistoricoRetirada(v));
        return;
      case 'retirada':
        unawaited(_abrirRegistrarRetirada(v));
        return;
      case 'pagar_frete':
        unawaited(_abrirPagarFreteCarreto(v));
        return;
      case 'devolucao':
        unawaited(_abrirRegistrarDevolucaoTroca(v));
        return;
      case 'devolucao_fiscal':
        unawaited(_abrirDevolucoesFiscais(v));
        return;
      case 'emitir_nfce':
        unawaited(_emitirNfce(v));
        return;
      case 'danfe_nfce':
        unawaited(_verDanfeNfce(v));
        return;
      case 'danfe_nfe55':
        unawaited(_verNfe55(v));
        return;
      case 'segunda_via':
        unawaited(_segundaViaCupom(v));
        return;
      case 'cancelar':
        unawaited(_cancelarVenda(v));
        return;
    }
  }

  List<PopupMenuEntry<String>> _menuItensVenda(Venda v) {
    try {
      return _menuItensVendaUnsafe(v);
    } catch (e) {
      debugPrint('ListagemVendas.menu ${v.id}: $e');
      return const [
        PopupMenuItem<String>(
          value: 'historico',
          child: Text('Historico de retiradas'),
        ),
      ];
    }
  }

  List<PopupMenuEntry<String>> _menuItensVendaUnsafe(Venda v) {
    final temNfce = v.nfceEmitida;
    final clienteVenda = EmitirNfceVendaFlow.clienteDaVenda(
      v,
      widget.clienteRepository,
    );
    final podeEmitirNfce = EmitirNfceVendaFlow.podeEmitir(
      v,
      cliente: clienteVenda,
    );
    var temNfe55 = false;
    try {
      temNfe55 =
          widget.vendaRepository.obterNfe55AutorizadaPorVenda(v.id) != null;
    } catch (_) {}

    return [
      if (podeEmitirNfce)
        const PopupMenuItem<String>(
          value: 'emitir_nfce',
          child: Text('Emitir NFC-e'),
        ),
      if (temNfce)
        const PopupMenuItem<String>(
          value: 'danfe_nfce',
          child: Text('Ver NFC-e (DANFE)'),
        ),
      if (temNfe55)
        const PopupMenuItem<String>(
          value: 'danfe_nfe55',
          child: Text('Ver NF-e modelo 55'),
        ),
      if (!v.cancelada && v.status == 'finalizada')
        const PopupMenuItem<String>(
          value: 'segunda_via',
          child: Text('Controle interno (2ª via / PDF)'),
        ),
      if (_podePagarFreteCarreto(v))
        const PopupMenuItem<String>(
          value: 'pagar_frete',
          child: Text('Pagar frete (carreto)'),
        ),
      if (_vendaTemRetiradaPendenteParaCliente(v))
        const PopupMenuItem<String>(
          value: 'retirada',
          child: Text('Registrar retirada'),
        ),
      if (_temRegistroRetiradaOuEntrega(v))
        const PopupMenuItem<String>(
          value: 'historico',
          child: Text('Historico de retiradas'),
        ),
      if (_podeRegistrarDevolucaoTroca(v))
        const PopupMenuItem<String>(
          value: 'devolucao',
          child: Text('Devolucao / troca'),
        ),
      if (_temDevolucaoFiscal(v))
        const PopupMenuItem<String>(
          value: 'devolucao_fiscal',
          child: Text('NF-e de devolucao (DANFE)'),
        ),
      if (!v.cancelada &&
          v.status == 'finalizada' &&
          widget.podeCancelarVendas)
        const PopupMenuItem<String>(
          value: 'cancelar',
          child: Text('Cancelar venda'),
        ),
    ];
  }

  String _csvEscape(String texto) => '"${texto.replaceAll('"', '""')}"';

  Future<List<Venda>> _listarFiltroCompletoParaExport() async {
    final filtros = _montarFiltroListagemAtual();
    final repo = widget.vendaRepository;
    if (repo is VendaApiRepository) {
      return repo.listarListagemVendasExportacao(filtros);
    }
    return (repo.listarListagemVendasCompleto(filtros) as List)
        .whereType<Venda>()
        .toList();
  }

  Future<void> _exportarCancelamentosCsv() async {
    final canceladas = (await _listarFiltroCompletoParaExport())
        .where((v) => v.cancelada)
        .toList();
    if (!mounted) return;
    if (canceladas.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Nao ha vendas canceladas para exportar.'),
        ),
      );
      return;
    }
    final linhas = <String>[
      'venda_id,numero_venda,data_venda,cancelada_em,cancelada_por,motivo,total',
      ...canceladas.map((v) {
        final dataVenda = DateFormat(
          'dd/MM/yyyy HH:mm',
        ).format(v.data.toLocal());
        final canceladaEm = v.canceladaEm == null
            ? ''
            : DateFormat('dd/MM/yyyy HH:mm').format(v.canceladaEm!.toLocal());
        return [
          v.id.toString(),
          v.numeroOrcamento.toString(),
          _csvEscape(dataVenda),
          _csvEscape(canceladaEm),
          _csvEscape(
            v.canceladaPor.trim().isEmpty ? 'Nao informado' : v.canceladaPor,
          ),
          _csvEscape(v.motivoCancelamento),
          v.total.toStringAsFixed(2).replaceAll('.', ','),
        ].join(',');
      }),
    ];
    final selectedPath = await FilePicker.platform.saveFile(
      dialogTitle: 'Salvar relatorio de cancelamentos',
      fileName:
          'cancelamentos_${DateFormat('yyyyMMdd_HHmm').format(DateTime.now())}.csv',
      type: FileType.custom,
      allowedExtensions: const ['csv'],
    );
    if (selectedPath == null) return;
    final normalizedPath = selectedPath.toLowerCase().endsWith('.csv')
        ? selectedPath
        : '$selectedPath.csv';
    final file = File(normalizedPath);
    await file.writeAsString(linhas.join('\n'), flush: true);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Relatorio salvo em: $normalizedPath')),
    );
  }

  Future<Uint8List> _gerarCancelamentosPdfBytes(List<Venda> canceladas) async {
    final doc = pw.Document();
    final fmt = DateFormat('dd/MM/yyyy HH:mm');
    final totalCancelado = canceladas.fold<double>(
      0,
      (acc, v) => acc + v.total,
    );
    doc.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(20),
        build: (context) {
          return [
            pw.Text(
              'Relatorio de Cancelamentos',
              style: pw.TextStyle(fontSize: 15, fontWeight: pw.FontWeight.bold),
            ),
            pw.SizedBox(height: 6),
            pw.Text('Gerado em: ${fmt.format(DateTime.now())}'),
            pw.Text('Quantidade: ${canceladas.length}'),
            pw.Text(
              'Total cancelado: ${_formatarMoeda(totalCancelado)}',
              style: pw.TextStyle(fontWeight: pw.FontWeight.bold),
            ),
            pw.SizedBox(height: 10),
            ...canceladas.map((v) {
              final emVenda = fmt.format(v.data.toLocal());
              final emCancelada = v.canceladaEm == null
                  ? 'Nao informado'
                  : fmt.format(v.canceladaEm!.toLocal());
              final por = v.canceladaPor.trim().isEmpty
                  ? 'Nao informado'
                  : v.canceladaPor.trim();
              final motivo = v.motivoCancelamento.trim().isEmpty
                  ? 'Nao informado'
                  : v.motivoCancelamento.trim();
              return pw.Container(
                margin: const pw.EdgeInsets.only(bottom: 6),
                padding: const pw.EdgeInsets.all(8),
                decoration: pw.BoxDecoration(
                  border: pw.Border.all(color: PdfColors.grey400),
                  borderRadius: pw.BorderRadius.circular(4),
                ),
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Text(
                      _rotuloVendaUsuario(v),
                      style: pw.TextStyle(fontWeight: pw.FontWeight.bold),
                    ),
                    pw.SizedBox(height: 2),
                    pw.Text('Data venda: $emVenda'),
                    pw.Text('Cancelada em: $emCancelada'),
                    pw.Text('Cancelada por: $por'),
                    pw.Text('Motivo: $motivo'),
                    pw.Text('Total: ${_formatarMoeda(v.total)}'),
                  ],
                ),
              );
            }),
          ];
        },
      ),
    );
    return doc.save();
  }

  Future<void> _exportarCancelamentosPdf() async {
    final canceladas = (await _listarFiltroCompletoParaExport())
        .where((v) => v.cancelada)
        .toList();
    if (!mounted) return;
    if (canceladas.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Nao ha vendas canceladas para exportar.'),
        ),
      );
      return;
    }
    final acao = await showDialog<String>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Relatorio de cancelamentos'),
          content: const Text('Deseja imprimir ou salvar em PDF?'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, 'fechar'),
              child: const Text('Fechar'),
            ),
            OutlinedButton.icon(
              onPressed: () => Navigator.pop(context, 'salvar'),
              icon: const Icon(Icons.picture_as_pdf_outlined),
              label: const Text('Salvar PDF'),
            ),
            ElevatedButton.icon(
              onPressed: () => Navigator.pop(context, 'imprimir'),
              icon: const Icon(Icons.print_outlined),
              label: const Text('Imprimir'),
            ),
          ],
        );
      },
    );
    if (!mounted || acao == null || acao == 'fechar') return;
    final pdfBytes = await _gerarCancelamentosPdfBytes(canceladas);
    if (acao == 'imprimir') {
      await Printing.layoutPdf(onLayout: (_) async => pdfBytes);
      return;
    }
    final selectedPath = await FilePicker.platform.saveFile(
      dialogTitle: 'Salvar relatorio de cancelamentos (PDF)',
      fileName:
          'cancelamentos_${DateFormat('yyyyMMdd_HHmm').format(DateTime.now())}.pdf',
      type: FileType.custom,
      allowedExtensions: const ['pdf'],
    );
    if (selectedPath == null) return;
    final normalizedPath = selectedPath.toLowerCase().endsWith('.pdf')
        ? selectedPath
        : '$selectedPath.pdf';
    await File(normalizedPath).writeAsBytes(pdfBytes, flush: true);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Relatorio PDF salvo em: $normalizedPath')),
    );
  }

  Future<void> _cancelarVenda(Venda venda) async {
    final resultado = await CancelarVendaUi.executar(
      context: context,
      vendaRepository: widget.vendaRepository,
      clienteRepository: widget.clienteRepository,
      usuarioRepository: _usuarioRepository,
      usuarioAtual: widget.usuarioAtual,
      podeCancelarVendas: widget.podeCancelarVendas,
      venda: venda,
    );
    if (!mounted) return;
    if (resultado == CancelarVendaUiResultado.sucesso) {
      _pesquisar();
    }
  }

  @override
  Widget build(BuildContext context) {
    final usarTabela =
        MediaQuery.sizeOf(context).width >=
        ListagemVendasLayout.breakpointTabela;
    final itensUiBrutos = _itensUi;
    final itensUi = usarTabela
        ? itensUiBrutos
        : ordenarItensListagemVendas(
            itensUiBrutos,
            coluna: _colunaOrdenacao,
            ascendente: _ordenacaoAscendente,
          );
    final theme = Theme.of(context);

    return Scaffold(
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ListagemVendasCabecalho(
            totalRegistros: _totalListagemVendas,
            exibidos: _resultados.length,
            valorTotalExibido: _valorTotalExibido,
            onAtualizar: _carregandoListagem ? null : () => unawaited(_pesquisar()),
          ),
          if (_carregandoListagem)
            const LinearProgressIndicator(minHeight: 2),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  ListagemVendasFiltrosPanel(
                    buscaController: _buscaController,
                    filtrosAtivos: _contarFiltrosAtivos(),
                    onPesquisar: _pesquisar,
                    onBuscaChanged: _agendarPesquisa,
                    onLimpar: _limparFiltros,
                    onExportarCsv: _exportarCancelamentosCsv,
                    onExportarPdf: _exportarCancelamentosPdf,
                    periodoPersonalizado: _periodoPreset == 'personalizado'
                        ? Wrap(
                            spacing: 10,
                            runSpacing: 8,
                            crossAxisAlignment: WrapCrossAlignment.center,
                            children: [
                              OutlinedButton.icon(
                                onPressed: _escolherDataInicioPersonalizado,
                                icon: const Icon(
                                  Icons.event_outlined,
                                  size: 18,
                                ),
                                label: Text(
                                  _dataPersonalizadaInicio == null
                                      ? 'Data inicial'
                                      : 'De ${_dataDia.format(_dataPersonalizadaInicio!)}',
                                ),
                              ),
                              OutlinedButton.icon(
                                onPressed: _escolherDataFimPersonalizado,
                                icon: const Icon(
                                  Icons.event_outlined,
                                  size: 18,
                                ),
                                label: Text(
                                  _dataPersonalizadaFim == null
                                      ? 'Data final'
                                      : 'Ate ${_dataDia.format(_dataPersonalizadaFim!)}',
                                ),
                              ),
                              Text(
                                'Inclui o dia inteiro de cada data.',
                                style: theme.textTheme.bodySmall,
                              ),
                            ],
                          )
                        : null,
                    filtrosAvancados: (ctx, constraints) =>
                        ListagemVendasFiltrosGrade(
                          children: [
                            DropdownButtonFormField<String>(
                              initialValue: _periodoPreset,
                              isExpanded: true,
                              decoration: const InputDecoration(
                                labelText: 'Periodo',
                                isDense: true,
                              ),
                              items: const [
                                DropdownMenuItem(
                                  value: 'hoje',
                                  child: Text('Hoje'),
                                ),
                                DropdownMenuItem(
                                  value: 'ultimos_7',
                                  child: Text('Ultimos 7 dias'),
                                ),
                                DropdownMenuItem(
                                  value: 'ultimos_30',
                                  child: Text('Ultimos 30 dias'),
                                ),
                                DropdownMenuItem(
                                  value: 'mes_atual',
                                  child: Text('Mes atual'),
                                ),
                                DropdownMenuItem(
                                  value: 'mes_anterior',
                                  child: Text('Mes anterior'),
                                ),
                                DropdownMenuItem(
                                  value: 'ano_atual',
                                  child: Text('Ano atual'),
                                ),
                                DropdownMenuItem(
                                  value: 'todo',
                                  child: Text('Todo o periodo'),
                                ),
                                DropdownMenuItem(
                                  value: 'personalizado',
                                  child: Text('Datas escolhidas'),
                                ),
                              ],
                              onChanged: (v) {
                                if (v == null) return;
                                setState(() {
                                  _periodoPreset = v;
                                  if (v == 'personalizado' &&
                                      (_dataPersonalizadaInicio == null ||
                                          _dataPersonalizadaFim == null)) {
                                    final n = DateTime.now();
                                    _dataPersonalizadaInicio = DateTime(
                                      n.year,
                                      n.month,
                                      n.day,
                                    ).subtract(const Duration(days: 29));
                                    _dataPersonalizadaFim = DateTime(
                                      n.year,
                                      n.month,
                                      n.day,
                                      23,
                                      59,
                                      59,
                                      999,
                                    );
                                  }
                                });
                                _agendarPesquisa();
                              },
                            ),
                            DropdownButtonFormField<String>(
                              initialValue: _canceladaPorFiltro,
                              isExpanded: true,
                              decoration: const InputDecoration(
                                labelText: 'Cancelada por',
                                isDense: true,
                              ),
                              items: [
                                const DropdownMenuItem(
                                  value: 'todos',
                                  child: Text('Todos'),
                                ),
                                ..._distintosCanceladaPor.map(
                                  (u) => DropdownMenuItem(
                                    value: u,
                                    child: Text(
                                      u,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                ),
                              ],
                              onChanged: (v) {
                                if (v != null) {
                                  setState(() => _canceladaPorFiltro = v);
                                  _agendarPesquisa();
                                }
                              },
                            ),
                            DropdownButtonFormField<String>(
                              initialValue: _formaPagamento,
                              isExpanded: true,
                              decoration: const InputDecoration(
                                labelText: 'Pagamento',
                                isDense: true,
                              ),
                              items: [
                                const DropdownMenuItem(
                                  value: 'todos',
                                  child: Text('Todos'),
                                ),
                                ...[
                                  'dinheiro',
                                  'pix',
                                  'cartao_credito',
                                  'cartao_debito',
                                  'fiado',
                                  'transferencia',
                                  'misto',
                                ].map(
                                  (f) => DropdownMenuItem(
                                    value: f,
                                    child: Text(_rotuloFormaPagamento(f)),
                                  ),
                                ),
                              ],
                              onChanged: (v) {
                                if (v != null) {
                                  setState(() => _formaPagamento = v);
                                  _agendarPesquisa();
                                }
                              },
                            ),
                            DropdownButtonFormField<String>(
                              initialValue: _tipoEntrega,
                              isExpanded: true,
                              decoration: const InputDecoration(
                                labelText: 'Entrega',
                                isDense: true,
                              ),
                              items: const [
                                DropdownMenuItem(
                                  value: 'todos',
                                  child: Text('Todos'),
                                ),
                                DropdownMenuItem(
                                  value: 'retirada',
                                  child: Text('Leva Agora'),
                                ),
                                DropdownMenuItem(
                                  value: 'retirada_futura',
                                  child: Text('Retirada futura'),
                                ),
                                DropdownMenuItem(
                                  value: 'entrega_loja',
                                  child: Text('Carreto'),
                                ),
                                DropdownMenuItem(
                                  value: 'misto',
                                  child: Text('Venda mista'),
                                ),
                              ],
                              onChanged: (v) {
                                if (v != null) {
                                  setState(() => _tipoEntrega = v);
                                  _agendarPesquisa();
                                }
                              },
                            ),
                            DropdownButtonFormField<String>(
                              initialValue: _filtroFiscal,
                              isExpanded: true,
                              decoration: const InputDecoration(
                                labelText: 'Documento fiscal',
                                isDense: true,
                              ),
                              items: const [
                                DropdownMenuItem(
                                  value: 'todos',
                                  child: Text('Todos'),
                                ),
                                DropdownMenuItem(
                                  value: 'sem_nfce_eletronico',
                                  child: Text('Sem NFC-e (PIX/cartao)'),
                                ),
                              ],
                              onChanged: (v) {
                                if (v != null) {
                                  setState(() => _filtroFiscal = v);
                                  _agendarPesquisa();
                                }
                              },
                            ),
                            DropdownButtonFormField<String>(
                              initialValue: _entregaPendente,
                              isExpanded: true,
                              decoration: const InputDecoration(
                                labelText: 'Retirada futura',
                                isDense: true,
                              ),
                              items: const [
                                DropdownMenuItem(
                                  value: 'todos',
                                  child: Text('Todos'),
                                ),
                                DropdownMenuItem(
                                  value: 'nao',
                                  child: Text('Entregue (normal)'),
                                ),
                                DropdownMenuItem(
                                  value: 'sim',
                                  child: Text('Pendente'),
                                ),
                              ],
                              onChanged: (v) {
                                if (v != null) {
                                  setState(() => _entregaPendente = v);
                                  _agendarPesquisa();
                                }
                              },
                            ),
                            DropdownButtonFormField<String>(
                              initialValue: _filtroCancelamento,
                              isExpanded: true,
                              decoration: const InputDecoration(
                                labelText: 'Cancelamento',
                                isDense: true,
                              ),
                              items: const [
                                DropdownMenuItem(
                                  value: 'ativas',
                                  child: Text('Nao canceladas'),
                                ),
                                DropdownMenuItem(
                                  value: 'canceladas',
                                  child: Text('Somente canceladas'),
                                ),
                                DropdownMenuItem(
                                  value: 'todas',
                                  child: Text('Todas'),
                                ),
                              ],
                              onChanged: (v) {
                                if (v != null) {
                                  setState(() => _filtroCancelamento = v);
                                  _agendarPesquisa();
                                }
                              },
                            ),
                          ],
                        ),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          _totalListagemVendas == 0
                              ? 'Nenhuma venda encontrada com os filtros.'
                              : 'Exibindo ${_resultados.length} de $_totalListagemVendas · '
                                    'lotes de $_tamPaginaListagem',
                          style: theme.textTheme.titleSmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ),
                      if (!usarTabela && _resultados.isNotEmpty) ...[
                        PopupMenuButton<ListagemVendasColuna>(
                          tooltip: 'Ordenar lista',
                          onSelected: (coluna) {
                            setState(() {
                              if (_colunaOrdenacao == coluna) {
                                _ordenacaoAscendente = !_ordenacaoAscendente;
                              } else {
                                _colunaOrdenacao = coluna;
                                _ordenacaoAscendente =
                                    colunaOrdenacaoPadraoAscendente(coluna);
                              }
                            });
                          },
                          itemBuilder: (context) => [
                            for (final coluna in ListagemVendasColuna.values)
                              PopupMenuItem(
                                value: coluna,
                                child: Row(
                                  children: [
                                    if (_colunaOrdenacao == coluna)
                                      Icon(
                                        _ordenacaoAscendente
                                            ? Icons.arrow_upward_rounded
                                            : Icons.arrow_downward_rounded,
                                        size: 16,
                                        color: theme.colorScheme.primary,
                                      )
                                    else
                                      const SizedBox(width: 16),
                                    const SizedBox(width: 8),
                                    Text(coluna.rotulo),
                                  ],
                                ),
                              ),
                          ],
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 8,
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(Icons.sort_rounded, size: 18),
                                const SizedBox(width: 6),
                                Text(
                                  _colunaOrdenacao.rotulo,
                                  style: theme.textTheme.labelMedium,
                                ),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                      ],
                      if (_resultados.length < _totalListagemVendas)
                        FilledButton.tonal(
                          onPressed: _carregandoListagem
                              ? null
                              : () => unawaited(_carregarMaisVendas()),
                          child: Text('Carregar mais $_tamPaginaListagem'),
                        ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Expanded(
                    child: _resultados.isEmpty
                        ? Center(
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  Icons.receipt_long_outlined,
                                  size: 48,
                                  color: theme.colorScheme.outline,
                                ),
                                const SizedBox(height: 12),
                                Text(
                                  'Nenhuma venda finalizada com os filtros atuais.',
                                  style: theme.textTheme.bodyLarge?.copyWith(
                                    color: theme.colorScheme.onSurfaceVariant,
                                  ),
                                ),
                              ],
                            ),
                          )
                        : usarTabela
                        ? ListagemVendasTabela(
                            itens: itensUiBrutos,
                            onTapItem: (item) =>
                                _mostrarModalItensVenda(item.venda),
                            onAcaoMenu: (acao, item) =>
                                _executarAcaoMenu(acao, item.venda),
                            menuBuilder: (item) => _menuItensVenda(item.venda),
                          )
                        : ListagemVendasListaCards(
                            itens: itensUi,
                            onTapItem: (item) =>
                                _mostrarModalItensVenda(item.venda),
                            onAcaoMenu: (acao, item) =>
                                _executarAcaoMenu(acao, item.venda),
                            menuBuilder: (item) => _menuItensVenda(item.venda),
                          ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _DialogoFreteCarretoRetiradaFutura extends StatefulWidget {
  const _DialogoFreteCarretoRetiradaFutura({
    required this.vendaMae,
    required this.cliente,
    required this.enderecoInicial,
    required this.observacaoInicial,
    required this.vendaRepository,
    required this.formatarMoeda,
    required this.parseValor,
    required this.onSucesso,
  });

  final Venda vendaMae;
  final Cliente cliente;
  final String enderecoInicial;
  final String observacaoInicial;
  final dynamic vendaRepository;
  final String Function(double) formatarMoeda;
  final double Function(String) parseValor;
  final VoidCallback onSucesso;

  @override
  State<_DialogoFreteCarretoRetiradaFutura> createState() =>
      _DialogoFreteCarretoRetiradaFuturaState();
}

class _DialogoFreteCarretoRetiradaFuturaState
    extends State<_DialogoFreteCarretoRetiradaFutura> {
  late final TextEditingController _endereco;
  late final TextEditingController _obs;
  late final TextEditingController _frete;
  String _prioridade = 'normal';
  String _janela = 'nao_definida';
  DateTime? _dataEntrega;

  @override
  void initState() {
    super.initState();
    _endereco = TextEditingController(text: widget.enderecoInicial);
    _obs = TextEditingController(text: widget.observacaoInicial);
    _frete = TextEditingController();
    _dataEntrega = DateTime.now();
  }

  @override
  void dispose() {
    _endereco.dispose();
    _obs.dispose();
    _frete.dispose();
    super.dispose();
  }

  Future<void> _gerar() async {
    final vf = widget.parseValor(_frete.text);
    if (_endereco.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Informe o endereco de entrega.')),
      );
      return;
    }
    if (_prioridade == 'agendada' && _janela == 'nao_definida') {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Para entrega agendada, selecione janela Manha ou Tarde.',
          ),
        ),
      );
      return;
    }
    if (_dataEntrega == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Defina a data da entrega.')),
      );
      return;
    }

    if (vf <= 0) {
      final ok = await showDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (ctx) => AlertDialog(
          title: const Text('Frete zerado'),
          content: const Text(
            'Confirmar orcamento de carreto com frete gratuito?',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Nao'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Frete gratuito'),
            ),
          ],
        ),
      );
      if (ok != true) return;
    }

    try {
      final pagamento = DadosPagamentoOrcamento(
        formaPagamento: 'dinheiro',
        quantidadeParcelas: 1,
      );
      final repo = widget.vendaRepository;
      final int idFilho;
      if (repo is VendaApiRepository) {
        idFilho = await repo.registrarOrcamentoFreteRetiradaFuturaRemoto(
          vendaMaeId: widget.vendaMae.id,
          valorFreteCobrado: vf,
          pagamento: pagamento,
          enderecoEntrega: _endereco.text.trim(),
          observacaoEntrega: _obs.text.trim(),
          prioridadeEntrega: _prioridade,
          janelaEntrega: _janela,
          dataEntregaMarcada: _dataEntrega!,
          vendedorId: widget.vendaMae.vendedor.targetId == 0
              ? null
              : widget.vendaMae.vendedor.targetId,
        );
      } else {
        idFilho = repo.registrarOrcamentoFreteRetiradaFutura(
          vendaMaeId: widget.vendaMae.id,
          valorFreteCobrado: vf,
          pagamento: pagamento,
          enderecoEntrega: _endereco.text.trim(),
          observacaoEntrega: _obs.text.trim(),
          prioridadeEntrega: _prioridade,
          janelaEntrega: _janela,
          dataEntregaMarcada: _dataEntrega!,
          vendedorId: widget.vendaMae.vendedor.targetId == 0
              ? null
              : widget.vendaMae.vendedor.targetId,
        );
        await LanSyncScheduler.solicitarSyncPrioritario();
      }
      if (!mounted) return;
      final filho = widget.vendaRepository.obterPorId(idFilho);
      final n = filho?.numeroOrcamento ?? 0;
      Navigator.of(context).pop();
      widget.onSucesso();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Orcamento de frete ${n > 0 ? '#$n' : '#$idFilho'} gerado. Finalize no Caixa.',
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(LanApiFeedback.mensagem(e))));
    }
  }

  @override
  Widget build(BuildContext context) {
    final ref = widget.vendaMae.numeroOrcamento > 0
        ? '${widget.vendaMae.numeroOrcamento}'
        : '${widget.vendaMae.id}';
    return AlertDialog(
      title: Text('Frete carreto — ref. venda $ref'),
      content: SizedBox(
        width: 500,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Cliente: ${widget.cliente.nomeRazao}',
                style: Theme.of(context).textTheme.bodyMedium,
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _frete,
                decoration: const InputDecoration(
                  labelText: 'Valor do frete (R\$)',
                ),
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _endereco,
                maxLines: 2,
                decoration: const InputDecoration(
                  labelText: 'Endereco de entrega',
                ),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _obs,
                maxLines: 2,
                decoration: const InputDecoration(
                  labelText: 'Observacoes da entrega',
                ),
              ),
              const SizedBox(height: 8),
              InputDecorator(
                decoration: const InputDecoration(
                  labelText: 'Prioridade da entrega',
                ),
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<String>(
                    isExpanded: true,
                    value: _prioridade,
                    items: const [
                      DropdownMenuItem(value: 'normal', child: Text('Normal')),
                      DropdownMenuItem(
                        value: 'urgente',
                        child: Text('Urgente'),
                      ),
                      DropdownMenuItem(
                        value: 'agendada',
                        child: Text('Agendada'),
                      ),
                    ],
                    onChanged: (v) => setState(() {
                      _prioridade = v ?? 'normal';
                      if (_prioridade == 'agendada') {
                        if (_janela == 'nao_definida') {
                          _janela = 'manha';
                        }
                      } else {
                        _janela = 'nao_definida';
                      }
                    }),
                  ),
                ),
              ),
              if (_prioridade == 'agendada') ...[
                const SizedBox(height: 8),
                InputDecorator(
                  decoration: const InputDecoration(labelText: 'Janela'),
                  child: DropdownButtonHideUnderline(
                    child: DropdownButton<String>(
                      isExpanded: true,
                      value: _janela,
                      items: const [
                        DropdownMenuItem(value: 'manha', child: Text('Manha')),
                        DropdownMenuItem(value: 'tarde', child: Text('Tarde')),
                      ],
                      onChanged: (v) => setState(() => _janela = v ?? 'manha'),
                    ),
                  ),
                ),
              ],
              const SizedBox(height: 8),
              OutlinedButton.icon(
                onPressed: () async {
                  final agora = DateTime.now();
                  final inicial = _dataEntrega ?? agora;
                  final escolhido = await showDatePicker(
                    context: context,
                    initialDate: inicial,
                    firstDate: DateTime(agora.year, agora.month, agora.day),
                    lastDate: DateTime(agora.year + 3, 12, 31),
                  );
                  if (!mounted || escolhido == null) return;
                  setState(() => _dataEntrega = escolhido);
                },
                icon: const Icon(Icons.event_outlined),
                label: Text(
                  _dataEntrega == null
                      ? 'Definir data da entrega'
                      : 'Data: ${_dataEntrega!.day.toString().padLeft(2, '0')}/'
                            '${_dataEntrega!.month.toString().padLeft(2, '0')}/'
                            '${_dataEntrega!.year}',
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'O total da venda $ref nao e alterado; o frete entra em orcamento separado '
                'para pagamento no caixa. Ao pagar, a venda mae vira carreto e aparece em Entregas.',
                style: Theme.of(context).textTheme.bodySmall,
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
          onPressed: _gerar,
          child: const Text('Gerar orcamento de frete'),
        ),
      ],
    );
  }
}

class _LinhaRetiradaCliente {
  const _LinhaRetiradaCliente({
    required this.item,
    required this.pendente,
    required this.rotulo,
    required this.carretoNaLoja,
  });

  final ItemVenda item;
  final int pendente;
  final String rotulo;
  final bool carretoNaLoja;
}

class _DialogRegistrarRetiradaCliente extends StatefulWidget {
  const _DialogRegistrarRetiradaCliente({
    required this.venda,
    required this.itens,
    required this.vendaRepository,
    required this.vendedorRepository,
    required this.usuarioRepository,
  });

  final Venda venda;
  final List<ItemVenda> itens;
  final dynamic vendaRepository;
  final dynamic vendedorRepository;
  final dynamic usuarioRepository;

  @override
  State<_DialogRegistrarRetiradaCliente> createState() =>
      _DialogRegistrarRetiradaClienteState();
}

class _DialogRegistrarRetiradaClienteState
    extends State<_DialogRegistrarRetiradaCliente> {
  late final Map<int, TextEditingController> _controllers;
  late final TextEditingController _quemRetirouController;

  List<_LinhaRetiradaCliente> get _linhasPendentes {
    final v = widget.venda;
    final carretoLoja =
        EntregaVendaHelper.vendaPermiteRetiradaLojaCarretoAntesSaida(
      v,
      itens: widget.itens,
    );
    final linhas = <_LinhaRetiradaCliente>[];
    for (final it in widget.itens) {
      final qFut = it.quantidadePendenteRetirada;
      if (qFut > 0) {
        linhas.add(
          _LinhaRetiradaCliente(
            item: it,
            pendente: qFut,
            rotulo: 'Retirada futura',
            carretoNaLoja: false,
          ),
        );
      }
      if (carretoLoja) {
        final qCar = it.quantidadeAindaNoCarretoAntesSaida;
        if (qCar > 0) {
          linhas.add(
            _LinhaRetiradaCliente(
              item: it,
              pendente: qCar,
              rotulo: 'Carreto (busca na loja)',
              carretoNaLoja: true,
            ),
          );
        }
      }
    }
    return linhas;
  }

  @override
  void initState() {
    super.initState();
    _quemRetirouController = TextEditingController();
    _controllers = {
      for (final linha in _linhasPendentes)
        linha.item.id: TextEditingController(text: ''),
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

  void _preencherTudo() {
    for (final linha in _linhasPendentes) {
      final c = _controllers[linha.item.id];
      if (c != null) {
        c.text = '${linha.pendente}';
      }
    }
    setState(() {});
  }

  Future<void> _confirmar() async {
    final mapFutura = <int, int>{};
    final mapCarretoLoja = <int, int>{};
    for (final linha in _linhasPendentes) {
      final c = _controllers[linha.item.id];
      if (c == null) continue;
      final q = int.tryParse(c.text.trim()) ?? 0;
      if (q <= 0) continue;
      if (linha.carretoNaLoja) {
        mapCarretoLoja[linha.item.id] = q;
      } else {
        mapFutura[linha.item.id] = q;
      }
    }
    if (mapFutura.isEmpty && mapCarretoLoja.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Informe ao menos uma quantidade maior que zero.'),
        ),
      );
      return;
    }
    final operador = await solicitarOperadorRetiradaNaLoja(
      context: context,
      vendedorRepository: widget.vendedorRepository,
      usuarioRepository: widget.usuarioRepository,
    );
    if (operador == null || !mounted) return;
    try {
      final quem = _quemRetirouController.text.trim();
      final retiradoPor = quem.isEmpty ? null : quem;
      final api = widget.vendaRepository is VendaApiRepository
          ? widget.vendaRepository as VendaApiRepository
          : null;
      if (mapFutura.isNotEmpty) {
        if (api != null) {
          await api.registrarRetiradaParcialRemoto(
            widget.venda.id,
            mapFutura,
            usuario: operador,
            retiradoPor: retiradoPor,
          );
        } else {
          widget.vendaRepository.registrarRetiradaParcial(
            widget.venda.id,
            mapFutura,
            usuario: operador,
            retiradoPor: retiradoPor,
          );
        }
      }
      if (mapCarretoLoja.isNotEmpty) {
        if (api != null) {
          await api.registrarRetiradaParcialLojaCarretoAntesSaidaRemoto(
            widget.venda.id,
            mapCarretoLoja,
            usuario: operador,
            retiradoPor: retiradoPor,
          );
        } else {
          widget.vendaRepository.registrarRetiradaParcialLojaCarretoAntesSaida(
            widget.venda.id,
            mapCarretoLoja,
            usuario: operador,
            retiradoPor: retiradoPor,
          );
        }
      }
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Nao foi possivel registrar: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AlertDialog(
      title: const Text('Registrar retirada'),
      content: SizedBox(
        width: 420,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: _quemRetirouController,
                textCapitalization: TextCapitalization.words,
                decoration: const InputDecoration(
                  labelText: 'Quem retirou',
                  hintText: 'Opcional',
                  isDense: true,
                ),
              ),
              const SizedBox(height: 12),
              for (final linha in _linhasPendentes)
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
                              linha.item.nomeProduto,
                              style: theme.textTheme.titleSmall?.copyWith(
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            Text(
                              '${linha.rotulo} · pendente ${linha.pendente} un.',
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
                          controller: _controllers[linha.item.id],
                          enabled: linha.pendente > 0,
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
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('Cancelar'),
        ),
        TextButton(
          onPressed: _preencherTudo,
          child: const Text('Retirar tudo'),
        ),
        FilledButton(onPressed: _confirmar, child: const Text('Confirmar')),
      ],
    );
  }
}
