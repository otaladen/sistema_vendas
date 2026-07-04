import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import '../data/app_config_repository.dart';
import '../data/cliente_repository.dart';
import '../data/produto_repository.dart';
import '../data/usuario_repository.dart';
import '../data/sync/lan_sync_scheduler.dart';
import '../data/venda_repository.dart';
import '../domain/entrega_venda_helper.dart';
import '../domain/venda_documento_rotulo_helper.dart';
import '../domain/pagamento_orcamento.dart';
import '../data/vendedor_repository.dart';
import '../model/cliente.dart';
import '../model/item_venda.dart';
import '../model/usuario_sistema.dart';
import '../model/venda.dart';
import '../model/vendedor.dart';
import '../services/cupom_nao_fiscal_venda_pdf.dart';
import '../services/print_service.dart';
import 'clientes_page.dart';
import 'cupom_venda_impressao_helper.dart';
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
import '../domain/fiscal/abrir_danfe_focus.dart';
import '../services/focus_nfe_service.dart';
import 'fiscal/abrir_documento_fiscal.dart';
import 'fiscal/emitir_nfce_venda_flow.dart';
import 'fiscal/widgets/devolucao_fiscal_historico_panel.dart';
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
  });

  final VendaRepository vendaRepository;
  final ClienteRepository clienteRepository;
  final VendedorRepository vendedorRepository;
  final ProdutoRepository produtoRepository;
  final AppConfigRepository appConfigRepository;
  final PrintService printService;
  final String usuarioAtual;
  final bool podeCancelarVendas;
  final UsuarioSistema usuarioLogado;

  @override
  State<ListagemVendasPage> createState() => _ListagemVendasPageState();
}

class _ListagemVendasPageState extends State<ListagemVendasPage> {
  static const int _tamPaginaListagem = 20;

  final NumberFormat _currency = NumberFormat('#,##0.00', 'pt_BR');
  final DateFormat _dataHora = DateFormat('dd/MM/yyyy HH:mm');
  final DateFormat _dataDia = DateFormat('dd/MM/yyyy');
  final _buscaController = TextEditingController();
  final UsuarioRepository _usuarioRepository = UsuarioRepository();
  late final FocusNfeService _focusNfeService =
      FocusNfeService(config: criarFocusNfeConfigPadrao());

  String _periodoPreset = 'ultimos_30';
  DateTime? _dataPersonalizadaInicio;
  DateTime? _dataPersonalizadaFim;
  String _formaPagamento = 'todos';
  String _tipoEntrega = 'todos';
  String _entregaPendente = 'todos';
  String _filtroFiscal = 'todos';
  String _filtroCancelamento = 'ativas';
  String _canceladaPorFiltro = 'todos';
  int? _clienteIdFiltro;
  int? _vendedorIdFiltro;

  List<Venda> _resultados = [];
  List<String> _distintosCanceladaPor = [];
  int _offsetListagem = 0;
  int _totalListagemVendas = 0;
  ListagemVendasColuna _colunaOrdenacao = ListagemVendasColuna.data;
  bool _ordenacaoAscendente = false;

  @override
  void initState() {
    super.initState();
    _distintosCanceladaPor = widget.vendaRepository.listarDistintosCanceladaPor();
    _pesquisar();
  }

  @override
  void dispose() {
    _buscaController.dispose();
    super.dispose();
  }

  String _formatarMoeda(double valor) => 'R\$ ${_currency.format(valor)}';

  String _rotuloCupomFiscalLista(Venda v) {
    final nfe55 = widget.vendaRepository.obterNfe55AutorizadaPorVenda(v.id);
    return VendaDocumentoRotuloHelper.rotuloIdentificacaoLista(
      v,
      nfe55: nfe55 == null
          ? null
          : VendaDocumentoNfe55Resumo(
              numero: nfe55.numero,
              autorizada: nfe55.autorizada,
            ),
    );
  }

  VendaDocumentoNfe55Resumo? _nfe55Resumo(Venda v) {
    final nfe55 = widget.vendaRepository.obterNfe55AutorizadaPorVenda(v.id);
    return nfe55 == null
        ? null
        : VendaDocumentoNfe55Resumo(
            numero: nfe55.numero,
            autorizada: nfe55.autorizada,
          );
  }

  String _statusOperacionalLista(Venda v) {
    return VendaDocumentoRotuloHelper.statusOperacionalLista(
      v,
      nfe55: _nfe55Resumo(v),
    );
  }

  String _statusOperacionalResumidoLista(Venda v) {
    return VendaDocumentoRotuloHelper.statusOperacionalResumidoLista(
      v,
      nfe55: _nfe55Resumo(v),
    );
  }

  Color _corStatusOperacionalLista(Venda v) {
    return VendaDocumentoRotuloHelper.corStatusLista(
      v,
      Theme.of(context).colorScheme,
    );
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
        appConfigRepository: widget.appConfigRepository,
        printService: widget.printService,
        focusNfeService: _focusNfeService,
      );

  Future<void> _emitirNfce(Venda v) async {
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
    return v.itens.any((i) => i.quantidade - i.quantidadeDevolvida > 0);
  }

  Future<void> _abrirDevolucoesFiscais(Venda v) async {
    final fiscalSvc = VendaFiscalService(
      vendaRepository: widget.vendaRepository,
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
    final fiscalSvc = VendaFiscalService(
      vendaRepository: widget.vendaRepository,
      clienteRepository: widget.clienteRepository,
    );
    return fiscalSvc.listarDevolucoesFiscaisPorVenda(v.id).isNotEmpty;
  }

  Future<void> _abrirRegistrarDevolucaoTroca(Venda v) async {
    if (!_podeRegistrarDevolucaoTroca(v)) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Devolucao/troca nao disponivel para esta venda.',
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
    return v.itens.any((i) => i.quantidadePendenteRetirada > 0);
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
      widget.vendaRepository.vincularClienteVendaFinalizada(v.id, c.id);
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
    final ligado = venda.cliente.target;
    if (ligado != null) return ligado;
    final id = venda.cliente.targetId;
    if (id == 0) return null;
    return widget.clienteRepository.obterPorId(id);
  }

  Vendedor? _vendedorDaVenda(Venda venda) {
    final ligado = venda.vendedor.target;
    if (ligado != null) return ligado;
    final id = venda.vendedor.targetId;
    if (id == 0) return null;
    return widget.vendedorRepository.obterPorId(id);
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
    final inicial = _dataPersonalizadaInicio ??
        DateTime(hoje.year, hoje.month, hoje.day);
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
  }

  Future<void> _escolherDataFimPersonalizado() async {
    final hoje = DateTime.now();
    final inicial = _dataPersonalizadaFim ??
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
      return '${_rotuloTipoEntrega(v.tipoEntrega)} (${EntregaVendaHelper.resumoContagem(v.itens.map((i) => i.tipoEntregaItem))})';
    }
    return _rotuloTipoEntrega(v.tipoEntrega);
  }

  String _linhaRetiradaFutura(Venda v) {
    if (!v.entregaPendente) {
      return 'Retirada futura: Nao';
    }
    final unidades = v.itens.fold<int>(
      0,
      (a, i) => a + i.quantidadePendenteRetirada,
    );
    return 'Retirada futura: Pendente ($unidades un. a retirar)';
  }

  bool _vendaTemRetiradaPendenteParaCliente(Venda v) {
    if (v.cancelada || v.status != 'finalizada') return false;
    return v.itens.any((i) => i.quantidadePendenteRetirada > 0) ||
        EntregaVendaHelper.vendaPermiteRetiradaLojaCarretoAntesSaida(v);
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
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => _DialogRegistrarRetiradaCliente(
        venda: atual,
        vendaRepository: widget.vendaRepository,
        usuario: widget.usuarioAtual,
      ),
    );
    if (ok == true && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Retirada registrada.')),
      );
      _pesquisar();
    }
  }

  /// Observacao de entrega (log com data/operador) ou itens com retirada ja registrada.
  bool _temRegistroRetiradaOuEntrega(Venda v) {
    if (v.observacaoEntrega.trim().isNotEmpty) return true;
    return v.itens.any((i) => i.quantidadeJaRetirada > 0);
  }

  Future<void> _mostrarHistoricoRetirada(Venda v) async {
    final atual = widget.vendaRepository.obterPorId(v.id) ?? v;
    final linhas = <String>[];
    if (atual.observacaoEntrega.trim().isNotEmpty) {
      linhas.add(atual.observacaoEntrega.trim());
    }
    final comRetirada =
        atual.itens.where((i) => i.quantidadeJaRetirada > 0).toList();
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
          child: SingleChildScrollView(
            child: SelectableText(texto),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Fechar'),
          ),
        ],
      ),
    );
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
          content: Text('Segunda via disponivel apenas para vendas finalizadas.'),
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
      ),
      suggestedFileName: nomeArquivo,
    );
  }

  Future<void> _mostrarModalItensVenda(Venda v) async {
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          title: Text('Produtos — ${_rotuloVendaUsuario(v)}'),
          content: SizedBox(
            width: 440,
            child: v.itens.isEmpty
                ? const Text('Nenhum item registrado nesta venda.')
                : ConstrainedBox(
                    constraints: const BoxConstraints(maxHeight: 420),
                    child: SingleChildScrollView(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          for (final item in v.itens)
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
                                        color: Theme.of(ctx).colorScheme.primary,
                                      ),
                                    ),
                                  ),
                                  Expanded(
                                    child: Text(
                                      '${item.quantidade}x ${item.nomeProduto}',
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

  void _pesquisar() {
    final filtros = _montarFiltroListagemAtual();
    final pagina = widget.vendaRepository.listarListagemVendasPaginaComTotal(
      filtros,
      offset: 0,
      limite: _tamPaginaListagem,
    );
    final distintosCancel = widget.vendaRepository.listarDistintosCanceladaPor();
    setState(() {
      _resultados = pagina.vendas;
      _totalListagemVendas = pagina.total;
      _offsetListagem = pagina.vendas.length;
      _distintosCanceladaPor = distintosCancel;
      if (_canceladaPorFiltro != 'todos' &&
          !_distintosCanceladaPor.contains(_canceladaPorFiltro)) {
        _canceladaPorFiltro = 'todos';
      }
    });
  }

  void _carregarMaisVendas() {
    if (_resultados.length >= _totalListagemVendas) {
      return;
    }
    final pagina = widget.vendaRepository.listarListagemVendasPaginaComTotal(
      _montarFiltroListagemAtual(),
      offset: _offsetListagem,
      limite: _tamPaginaListagem,
    );
    setState(() {
      _resultados.addAll(pagina.vendas);
      _offsetListagem += pagina.vendas.length;
    });
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
      clienteId: _clienteIdFiltro,
      vendedorId: _vendedorIdFiltro,
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
      _clienteIdFiltro = null;
      _vendedorIdFiltro = null;
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
    if (_clienteIdFiltro != null) n++;
    if (_vendedorIdFiltro != null) n++;
    if (_filtroCancelamento != 'ativas') n++;
    if (_buscaController.text.trim().isNotEmpty) n++;
    return n;
  }

  double get _valorTotalExibido =>
      _resultados.fold(0.0, (s, v) => s + v.total);

  ListagemVendaItemUi _buildItemUi(Venda v) {
    final cliente = _clienteDaVenda(v);
    final alertas = <String>[];

    if (!v.cancelada &&
        v.status == 'finalizada' &&
        (widget.vendaRepository.valorReferenciaDevolvidoAcumuladoVenda(v.id) >
                0.005 ||
            widget.vendaRepository.valorSaidaTrocaAcumuladoVenda(v.id) >
                0.005)) {
      final dev = widget.vendaRepository
          .valorReferenciaDevolvidoAcumuladoVenda(v.id);
      final troca =
          widget.vendaRepository.valorSaidaTrocaAcumuladoVenda(v.id);
      final liq = troca - dev;
      alertas.add(
        'Dev/troca: devolvido ${_formatarMoeda(dev)} · saida '
        '${_formatarMoeda(troca)} · liquido ${_formatarMoeda(liq)}',
      );
    }
    if (v.idOrcamentoFreteRetiradaAberto != 0) {
      final filho = widget.vendaRepository
          .obterPorId(v.idOrcamentoFreteRetiradaAberto);
      final n = filho?.numeroOrcamento ?? 0;
      final rot = n > 0 ? '#$n' : '(id ${filho?.id})';
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

    final statusCompleto =
        v.cancelada ? 'Venda cancelada' : _statusOperacionalLista(v);
    final statusResumido =
        v.cancelada ? 'Cancelada' : _statusOperacionalResumidoLista(v);

    return ListagemVendaItemUi(
      venda: v,
      titulo: _rotuloCupomFiscalLista(v),
      status: statusResumido,
      statusDetalhe:
          statusCompleto != statusResumido ? statusCompleto : null,
      statusCor: v.cancelada
          ? Theme.of(context).colorScheme.error
          : _corStatusOperacionalLista(v),
      dataHora: _dataHora.format(v.data.toLocal()),
      cliente: cliente?.nomeRazao ?? 'Sem cliente',
      vendedor: _rotuloVendedorUmLinha(v),
      pagamento: _rotuloPagamentoLinhaLista(v),
      entrega: entrega,
      badgeNumero: _badgeNumeroVenda(v),
      totalFormatado: _formatarMoeda(v.total),
      cancelada: v.cancelada,
      alertas: alertas,
    );
  }

  void _executarAcaoMenu(String value, Venda v) {
    switch (value) {
      case 'historico':
        _mostrarHistoricoRetirada(v);
      case 'retirada':
        _abrirRegistrarRetirada(v);
      case 'pagar_frete':
        _abrirPagarFreteCarreto(v);
      case 'devolucao':
        _abrirRegistrarDevolucaoTroca(v);
      case 'devolucao_fiscal':
        _abrirDevolucoesFiscais(v);
      case 'emitir_nfce':
        _emitirNfce(v);
      case 'danfe_nfce':
        _verDanfeNfce(v);
      case 'danfe_nfe55':
        _verNfe55(v);
      case 'segunda_via':
        _segundaViaCupom(v);
      case 'cancelar':
        _cancelarVenda(v);
    }
  }

  List<PopupMenuEntry<String>> _menuItensVenda(Venda v) {
    final temNfce = v.nfceEmitida;
    final clienteVenda = EmitirNfceVendaFlow.clienteDaVenda(
      v,
      widget.clienteRepository,
    );
    final podeEmitirNfce = EmitirNfceVendaFlow.podeEmitir(
      v,
      cliente: clienteVenda,
    );
    final temNfe55 =
        widget.vendaRepository.obterNfe55AutorizadaPorVenda(v.id) != null;

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
      PopupMenuItem<String>(
        value: 'cancelar',
        enabled: !v.cancelada,
        child: const Text('Cancelar venda'),
      ),
    ];
  }

  String _csvEscape(String texto) => '"${texto.replaceAll('"', '""')}"';

  Future<void> _exportarCancelamentosCsv() async {
    final canceladas = widget.vendaRepository
        .listarListagemVendasCompleto(_montarFiltroListagemAtual())
        .where((v) => v.cancelada)
        .toList();
    if (canceladas.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Nao ha vendas canceladas para exportar.')),
      );
      return;
    }
    final linhas = <String>[
      'venda_id,numero_venda,data_venda,cancelada_em,cancelada_por,motivo,total',
      ...canceladas.map((v) {
        final dataVenda = DateFormat('dd/MM/yyyy HH:mm').format(v.data.toLocal());
        final canceladaEm = v.canceladaEm == null
            ? ''
            : DateFormat('dd/MM/yyyy HH:mm').format(v.canceladaEm!.toLocal());
        return [
          v.id.toString(),
          v.numeroOrcamento.toString(),
          _csvEscape(dataVenda),
          _csvEscape(canceladaEm),
          _csvEscape(v.canceladaPor.trim().isEmpty ? 'Nao informado' : v.canceladaPor),
          _csvEscape(v.motivoCancelamento),
          v.total.toStringAsFixed(2).replaceAll('.', ','),
        ].join(',');
      }),
    ];
    final selectedPath = await FilePicker.platform.saveFile(
      dialogTitle: 'Salvar relatorio de cancelamentos',
      fileName: 'cancelamentos_${DateFormat('yyyyMMdd_HHmm').format(DateTime.now())}.csv',
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
    final totalCancelado = canceladas.fold<double>(0, (acc, v) => acc + v.total);
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
    final canceladas = widget.vendaRepository
        .listarListagemVendasCompleto(_montarFiltroListagemAtual())
        .where((v) => v.cancelada)
        .toList();
    if (canceladas.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Nao ha vendas canceladas para exportar.')),
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
    final clientes = widget.clienteRepository
        .listarTodos()
        .where((c) => c.ativo)
        .toList();
    final vendedores = widget.vendedorRepository.listarAtivos();
    final usarTabela =
        MediaQuery.sizeOf(context).width >= ListagemVendasLayout.breakpointTabela;
    final itensUiBrutos = _resultados.map(_buildItemUi).toList();
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
            onAtualizar: _pesquisar,
          ),
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
                                icon: const Icon(Icons.event_outlined, size: 18),
                                label: Text(
                                  _dataPersonalizadaInicio == null
                                      ? 'Data inicial'
                                      : 'De ${_dataDia.format(_dataPersonalizadaInicio!)}',
                                ),
                              ),
                              OutlinedButton.icon(
                                onPressed: _escolherDataFimPersonalizado,
                                icon: const Icon(Icons.event_outlined, size: 18),
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
                            if (v != null) setState(() => _tipoEntrega = v);
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
                            if (v != null) setState(() => _filtroFiscal = v);
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
                            }
                          },
                        ),
                        DropdownButtonFormField<int?>(
                          initialValue: _clienteIdFiltro,
                          isExpanded: true,
                          decoration: const InputDecoration(
                            labelText: 'Cliente',
                            isDense: true,
                          ),
                          items: [
                            const DropdownMenuItem<int?>(
                              value: null,
                              child: Text('Todos'),
                            ),
                            ...clientes.map(
                              (c) => DropdownMenuItem<int?>(
                                value: c.id,
                                child: Text(
                                  c.nomeRazao,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ),
                          ],
                          onChanged: (v) =>
                              setState(() => _clienteIdFiltro = v),
                        ),
                        DropdownButtonFormField<int?>(
                          initialValue: _vendedorIdFiltro,
                          isExpanded: true,
                          decoration: const InputDecoration(
                            labelText: 'Vendedor',
                            isDense: true,
                          ),
                          items: [
                            const DropdownMenuItem<int?>(
                              value: null,
                              child: Text('Todos'),
                            ),
                            ...vendedores.map(
                              (vd) => DropdownMenuItem<int?>(
                                value: vd.id,
                                child: Text(
                                  vd.apelido.trim().isNotEmpty
                                      ? vd.apelido
                                      : vd.nomeCompleto,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ),
                          ],
                          onChanged: (v) =>
                              setState(() => _vendedorIdFiltro = v),
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
                          onPressed: _carregarMaisVendas,
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
                                menuBuilder: (item) =>
                                    _menuItensVenda(item.venda),
                              )
                            : ListagemVendasListaCards(
                                itens: itensUi,
                                onTapItem: (item) =>
                                    _mostrarModalItensVenda(item.venda),
                                onAcaoMenu: (acao, item) =>
                                    _executarAcaoMenu(acao, item.venda),
                                menuBuilder: (item) =>
                                    _menuItensVenda(item.venda),
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
  final VendaRepository vendaRepository;
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
      final idFilho = widget.vendaRepository.registrarOrcamentoFreteRetiradaFutura(
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
      await LanSyncScheduler.solicitarSyncImediato();
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
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Erro: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final ref =
        widget.vendaMae.numeroOrcamento > 0
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
                      DropdownMenuItem(value: 'urgente', child: Text('Urgente')),
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
                  decoration: const InputDecoration(
                    labelText: 'Janela',
                  ),
                  child: DropdownButtonHideUnderline(
                    child: DropdownButton<String>(
                      isExpanded: true,
                      value: _janela,
                      items: const [
                        DropdownMenuItem(
                          value: 'manha',
                          child: Text('Manha'),
                        ),
                        DropdownMenuItem(
                          value: 'tarde',
                          child: Text('Tarde'),
                        ),
                      ],
                      onChanged: (v) =>
                          setState(() => _janela = v ?? 'manha'),
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
    required this.vendaRepository,
    required this.usuario,
  });

  final Venda venda;
  final VendaRepository vendaRepository;
  final String usuario;

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
        EntregaVendaHelper.vendaPermiteRetiradaLojaCarretoAntesSaida(v);
    final linhas = <_LinhaRetiradaCliente>[];
    for (final it in v.itens) {
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
    try {
      final quem = _quemRetirouController.text.trim();
      final retiradoPor = quem.isEmpty ? null : quem;
      if (mapFutura.isNotEmpty) {
        widget.vendaRepository.registrarRetiradaParcial(
          widget.venda.id,
          mapFutura,
          usuario: widget.usuario,
          retiradoPor: retiradoPor,
        );
      }
      if (mapCarretoLoja.isNotEmpty) {
        widget.vendaRepository.registrarRetiradaParcialLojaCarretoAntesSaida(
          widget.venda.id,
          mapCarretoLoja,
          usuario: widget.usuario,
          retiradoPor: retiradoPor,
        );
      }
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
      title: const Text('Registrar retirada'),
      content: SizedBox(
        width: 420,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Cliente retirando na loja agora (parcial ou total). '
                'Itens de carreto so aparecem enquanto o romaneio nao saiu.',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 12),
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
        FilledButton(
          onPressed: _confirmar,
          child: const Text('Confirmar'),
        ),
      ],
    );
  }
}
