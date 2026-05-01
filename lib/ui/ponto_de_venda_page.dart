import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import '../data/app_config_repository.dart';
import '../data/cliente_repository.dart';
import '../data/produto_repository.dart';
import '../data/venda_repository.dart';
import '../data/vendedor_repository.dart';
import '../model/cliente.dart';
import '../model/item_venda.dart';
import '../model/produto.dart';
import '../model/venda.dart';
import '../model/vendedor.dart';
import 'clientes_page.dart';
import 'produto_detalhe_venda_page.dart';

class PontoDeVendaPage extends StatefulWidget {
  const PontoDeVendaPage({
    super.key,
    required this.produtoRepository,
    required this.clienteRepository,
    required this.vendaRepository,
    required this.vendedorRepository,
  });

  final ProdutoRepository produtoRepository;
  final ClienteRepository clienteRepository;
  final VendaRepository vendaRepository;
  final VendedorRepository vendedorRepository;

  @override
  State<PontoDeVendaPage> createState() => _PontoDeVendaPageState();
}

class _PontoDeVendaPageState extends State<PontoDeVendaPage> {
  static const int _validadeOrcamentoDias = 7;
  static const int _selecaoSemClienteValor = -1;
  static const int _selecaoNovoClienteValor = -2;

  /// Altura fixa por linha (~6 visíveis na área típica da lista sem scroll excessivo).
  static const double _alturaLinhaProduto = 56;
  final _pesquisaController = TextEditingController();
  final _pesquisaFocus = FocusNode(debugLabel: 'pesquisaPdV');
  final _listaProdutosFocus = FocusNode(debugLabel: 'listaProdutosPdV');
  final _carrinhoFocus = FocusNode(debugLabel: 'carrinhoPdV');

  /// Checkout à direita (F7 / Shift+F7).
  final _focusClientePdV = FocusNode(debugLabel: 'pdvCliente');
  final _focusVendedorPdV = FocusNode(debugLabel: 'pdvVendedor');
  final _focusPagamentoPdV = FocusNode(debugLabel: 'pdvPagamento');
  final _focusEntregaPdV = FocusNode(debugLabel: 'pdvEntrega');
  final _focusParcelasPdV = FocusNode(debugLabel: 'pdvParcelas');
  final _focusValorFretePdV = FocusNode(debugLabel: 'pdvValorFrete');
  final _focusEnderecoEntregaPdV = FocusNode(debugLabel: 'pdvEnderecoEntrega');
  final _focusObsEntregaPdV = FocusNode(debugLabel: 'pdvObsEntrega');
  final _focusSalvarOrcamentoPdV = FocusNode(debugLabel: 'pdvSalvarOrcamento');
  final _listaProdutosScrollController = ScrollController();
  final _valorFreteController = TextEditingController();
  final _enderecoEntregaController = TextEditingController();
  final _observacaoEntregaController = TextEditingController();
  final _configRepository = AppConfigRepository();
  final NumberFormat _currency = NumberFormat('#,##0.00', 'pt_BR');
  Timer? _debouncePesquisa;
  bool _pesquisaAguardandoDebounce = false;
  List<Produto> _produtos = [];
  List<Cliente> _clientes = [];
  List<Vendedor> _vendedoresAtivos = [];
  final List<_OrcamentoItemDraft> _carrinho = [];

  /// Índice destacado na lista de produtos (setas do teclado).
  int? _indiceListaProduto;

  /// Linha selecionada no carrinho (para ↑↓ ajustar quantidade).
  int? _indiceLinhaCarrinho;

  /// Preco usado em adicao rapida e exibido na linha (F1/F2/F3).
  String _precoListaAtivo = 'preco1';
  String _formaPagamentoSelecionada = 'dinheiro';
  int _parcelasSelecionadas = 1;
  int? _clienteSelecionadoId;
  int? _vendedorSelecionadoId;
  String _tipoEntregaSelecionada = 'retirada';
  String _prioridadeEntregaSelecionada = 'normal';
  String _janelaEntregaSelecionada = 'nao_definida';
  DateTime? _dataEntregaMarcada;
  bool _permitirVendaSemEstoque = true;
  int? _orcamentoEmEdicaoId;
  int? _orcamentoEmEdicaoNumero;
  bool _mostrarAjudaAtalhos = false;
  bool _painelCheckoutRecolhido = false;
  bool _mostrarMaisOpcoesCheckout = false;

  @override
  void initState() {
    super.initState();
    _carregarDadosIniciais();
    _carregarConfiguracaoVendaSemEstoque();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _pesquisaFocus.requestFocus();
    });
  }

  Future<void> _carregarConfiguracaoVendaSemEstoque() async {
    final config = await _configRepository.carregarEmpresaConfig();
    if (!mounted) {
      return;
    }
    setState(() {
      _permitirVendaSemEstoque = config.permitirVendaSemEstoque;
    });
  }

  @override
  void dispose() {
    _debouncePesquisa?.cancel();
    _listaProdutosScrollController.dispose();
    _listaProdutosFocus.dispose();
    _carrinhoFocus.dispose();
    _focusClientePdV.dispose();
    _focusVendedorPdV.dispose();
    _focusPagamentoPdV.dispose();
    _focusEntregaPdV.dispose();
    _focusParcelasPdV.dispose();
    _focusValorFretePdV.dispose();
    _focusEnderecoEntregaPdV.dispose();
    _focusObsEntregaPdV.dispose();
    _focusSalvarOrcamentoPdV.dispose();
    _pesquisaFocus.dispose();
    _pesquisaController.dispose();
    _valorFreteController.dispose();
    _enderecoEntregaController.dispose();
    _observacaoEntregaController.dispose();
    super.dispose();
  }

  void _pesquisar({
    bool executarAtalhoRapido = false,
    bool focarListaAposPesquisar = true,
  }) {
    final comando = _PesquisaComando.parse(_pesquisaController.text);
    var adicionouViaComandoRapido = false;
    _debouncePesquisa?.cancel();
    setState(() {
      _pesquisaAguardandoDebounce = false;
      _produtos = widget.produtoRepository.pesquisar(
        comando.termoBusca,
        clienteId: _clienteSelecionadoId,
        limite: 50,
      );
      _indiceListaProduto = _produtos.isEmpty ? null : 0;
    });
    if (executarAtalhoRapido && _produtos.isNotEmpty) {
      final primeiro = _produtos.first;
      if (comando.adicaoDireta) {
        _adicionarComQuantidade(primeiro, 1);
        adicionouViaComandoRapido = true;
      } else if (comando.quantidadeDireta != null) {
        _adicionarComQuantidade(primeiro, comando.quantidadeDireta!);
        adicionouViaComandoRapido = true;
      }
      if (adicionouViaComandoRapido) {
        setState(() {
          _pesquisaController.clear();
          _produtos = widget.produtoRepository.listarTodos();
          _indiceListaProduto = _produtos.isEmpty ? null : 0;
        });
      }
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _scrollParaIndiceLista();
      if (adicionouViaComandoRapido) {
        _pesquisaFocus.requestFocus();
      } else if (focarListaAposPesquisar && _produtos.isNotEmpty) {
        _listaProdutosFocus.requestFocus();
      }
    });
  }

  void _agendarPesquisaDebounce() {
    _debouncePesquisa?.cancel();
    if (!_pesquisaAguardandoDebounce && mounted) {
      setState(() {
        _pesquisaAguardandoDebounce = true;
      });
    }
    _debouncePesquisa = Timer(const Duration(milliseconds: 160), () {
      if (!mounted) return;
      _pesquisar(focarListaAposPesquisar: false);
    });
  }

  void _irDoCampoPesquisaParaLista() {
    if (_produtos.isEmpty) return;
    setState(() {
      _indiceListaProduto = 0;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _scrollParaIndiceLista();
      _listaProdutosFocus.requestFocus();
    });
  }

  void _scrollParaIndiceLista() {
    final i = _indiceListaProduto;
    if (i == null || !_listaProdutosScrollController.hasClients) return;
    final maxOffset = _listaProdutosScrollController.position.maxScrollExtent;
    final target = (i * _alturaLinhaProduto).clamp(0.0, maxOffset);
    _listaProdutosScrollController.jumpTo(target);
  }

  bool _estoqueCritico(Produto p) => p.estoqueReal < p.quantidadeMinima;

  TextSpan _textoComDestaqueBusca({
    required BuildContext context,
    required String texto,
    required String termoBusca,
    required TextStyle estiloBase,
  }) {
    final termo = termoBusca.trim().toLowerCase();
    if (termo.isEmpty) {
      return TextSpan(text: texto, style: estiloBase);
    }
    final textoLower = texto.toLowerCase();
    final spans = <TextSpan>[];
    var cursor = 0;

    while (cursor < texto.length) {
      final indice = textoLower.indexOf(termo, cursor);
      if (indice < 0) {
        spans.add(TextSpan(text: texto.substring(cursor)));
        break;
      }
      if (indice > cursor) {
        spans.add(TextSpan(text: texto.substring(cursor, indice)));
      }
      spans.add(
        TextSpan(
          text: texto.substring(indice, indice + termo.length),
          style: estiloBase.copyWith(
            color: Theme.of(context).colorScheme.primary,
            fontWeight: FontWeight.w700,
          ),
        ),
      );
      cursor = indice + termo.length;
    }

    return TextSpan(style: estiloBase, children: spans);
  }

  /// Volta o foco ao campo de pesquisa para fluxo continuado sem mouse.
  void _voltarFocoParaPesquisa() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _pesquisaFocus.requestFocus();
    });
  }

  void _mostrarSkuEDescricao(Produto produto) {
    final desc = produto.descricao.trim().isEmpty
        ? 'Sem descricao tecnica cadastrada.'
        : produto.descricao.trim();
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(produto.nome),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              SelectableText('SKU: ${produto.codigoInterno}'),
              const SizedBox(height: 12),
              const Text(
                'Descricao',
                style: TextStyle(fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 4),
              SelectableText(desc),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Fechar'),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              Navigator.push(
                context,
                MaterialPageRoute<void>(
                  builder: (_) => ProdutoDetalheVendaPage(produto: produto),
                ),
              );
            },
            child: const Text('Pagina completa'),
          ),
        ],
      ),
    );
  }

  bool _ctrlPressionado() {
    final keys = HardwareKeyboard.instance.logicalKeysPressed;
    return keys.contains(LogicalKeyboardKey.controlLeft) ||
        keys.contains(LogicalKeyboardKey.controlRight);
  }

  bool _shiftPressionado() {
    final keys = HardwareKeyboard.instance.logicalKeysPressed;
    return keys.contains(LogicalKeyboardKey.shiftLeft) ||
        keys.contains(LogicalKeyboardKey.shiftRight);
  }

  /// Atalhos tipo caixa: Numpad + ou Shift+= no teclado principal.
  bool _ehTeclaMais(KeyDownEvent event) =>
      event.logicalKey == LogicalKeyboardKey.numpadAdd ||
      (_shiftPressionado() && event.logicalKey == LogicalKeyboardKey.equal);

  List<FocusNode> _cadeiaFocoCheckout() {
    final nodes = <FocusNode>[
      _focusClientePdV,
      _focusVendedorPdV,
      _focusPagamentoPdV,
      _focusEntregaPdV,
    ];
    if (_tipoEntregaSelecionada == 'entrega_loja') {
      nodes.add(_focusValorFretePdV);
      nodes.add(_focusEnderecoEntregaPdV);
      nodes.add(_focusObsEntregaPdV);
    }
    nodes.add(_focusParcelasPdV);
    nodes.add(_focusSalvarOrcamentoPdV);
    return nodes;
  }

  void _focarProximoCampoCheckout() {
    final chain = _cadeiaFocoCheckout();
    if (chain.isEmpty) {
      return;
    }
    final idx = chain.indexWhere((n) => n.hasFocus);
    final next = idx < 0 ? 0 : (idx + 1) % chain.length;
    chain[next].requestFocus();
  }

  void _focarCampoCheckoutAnterior() {
    final chain = _cadeiaFocoCheckout();
    if (chain.isEmpty) {
      return;
    }
    final idx = chain.indexWhere((n) => n.hasFocus);
    final prev = idx < 0
        ? chain.length - 1
        : (idx - 1 + chain.length) % chain.length;
    chain[prev].requestFocus();
  }

  void _focarCarrinhoAtalho() {
    if (_carrinho.isNotEmpty) {
      setState(() {
        _indiceLinhaCarrinho = (_indiceLinhaCarrinho ?? _carrinho.length - 1)
            .clamp(0, _carrinho.length - 1);
      });
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }
      _carrinhoFocus.requestFocus();
    });
  }

  void _limparPesquisaAtalho() {
    setState(() {
      _pesquisaController.clear();
    });
    _carregarDadosIniciais();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }
      _pesquisaFocus.requestFocus();
    });
  }

  /// Adiciona 1 unidade com o preco ativo (F1/F2/F3); mescla linha identica.
  void _adicionarRapido(Produto produto) {
    _adicionarComQuantidade(produto, 1);
  }

  void _adicionarComQuantidade(Produto produto, int quantidade) {
    if (quantidade <= 0) return;
    final precoTipo = _precoListaAtivo;
    final unit = _precoPorTipo(produto, precoTipo);
    if (!_permitirVendaSemEstoque) {
      final fresh = widget.produtoRepository.obterPorId(produto.id) ?? produto;
      final disp = fresh.estoqueReal;
      if (disp <= 0) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Sem estoque de ${produto.nome}.')),
        );
        return;
      }
      final idxExistente = _carrinho.indexWhere(
        (e) => e.produto.id == produto.id && e.precoTipo == precoTipo,
      );
      if (idxExistente >= 0) {
        final novoTotal = _carrinho[idxExistente].quantidade + quantidade;
        if (novoTotal > disp) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                'Estoque maximo para ${produto.nome}: $disp (ja ha ${_carrinho[idxExistente].quantidade} no orcamento).',
              ),
            ),
          );
          return;
        }
      } else if (quantidade > disp) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Estoque maximo para ${produto.nome}: $disp.')),
        );
        return;
      }
    }
    final idxExistente = _carrinho.indexWhere(
      (e) => e.produto.id == produto.id && e.precoTipo == precoTipo,
    );
    setState(() {
      if (idxExistente >= 0) {
        _carrinho[idxExistente].quantidade += quantidade;
        _indiceLinhaCarrinho = idxExistente;
      } else {
        _carrinho.add(
          _OrcamentoItemDraft(
            produto: produto,
            quantidade: quantidade,
            precoTipo: precoTipo,
            precoUnitario: unit,
          ),
        );
        _indiceLinhaCarrinho = _carrinho.length - 1;
      }
    });
    _voltarFocoParaPesquisa();
  }

  KeyEventResult _onKeyListaProdutos(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    if (_produtos.isEmpty) return KeyEventResult.ignored;

    final n = _produtos.length;
    var i = _indiceListaProduto ?? 0;
    i = i.clamp(0, n - 1);

    if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
      setState(() {
        _indiceListaProduto = (i + 1).clamp(0, n - 1);
      });
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => _scrollParaIndiceLista(),
      );
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.arrowUp) {
      setState(() {
        _indiceListaProduto = (i - 1).clamp(0, n - 1);
      });
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => _scrollParaIndiceLista(),
      );
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.escape) {
      _pesquisaFocus.requestFocus();
      return KeyEventResult.handled;
    }
    if (_ehTeclaMais(event)) {
      _adicionarRapido(_produtos[i]);
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.enter ||
        event.logicalKey == LogicalKeyboardKey.numpadEnter) {
      unawaited(_adicionarAoOrcamento(_produtos[i]));
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  void _ajustarIndiceAposRemoverCarrinho(int removido) {
    if (_carrinho.isEmpty) {
      _indiceLinhaCarrinho = null;
      return;
    }
    final sel = _indiceLinhaCarrinho;
    if (sel == null) return;
    if (removido < sel) {
      _indiceLinhaCarrinho = sel - 1;
    } else if (removido == sel) {
      _indiceLinhaCarrinho = removido.clamp(0, _carrinho.length - 1);
    }
  }

  void _alterarQuantidadeCarrinho(int index, int delta) {
    if (!_permitirVendaSemEstoque && delta > 0) {
      final item = _carrinho[index];
      final fresh =
          widget.produtoRepository.obterPorId(item.produto.id) ?? item.produto;
      final disp = fresh.estoqueReal;
      if (item.quantidade + delta > disp) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Estoque maximo: $disp (atual no orcamento: ${item.quantidade}).',
            ),
          ),
        );
        return;
      }
    }
    setState(() {
      final item = _carrinho[index];
      final nova = item.quantidade + delta;
      if (nova <= 0) {
        _carrinho.removeAt(index);
        _ajustarIndiceAposRemoverCarrinho(index);
      } else {
        item.quantidade = nova;
      }
    });
  }

  void _removerItemCarrinho(int index) {
    setState(() {
      _carrinho.removeAt(index);
      _ajustarIndiceAposRemoverCarrinho(index);
    });
  }

  /// Setas na lista de **carrinho** (foco no orcamento): quantidade; Ctrl+setas = outra linha.
  KeyEventResult _onKeyCarrinho(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    if (_carrinho.isEmpty) return KeyEventResult.ignored;

    final n = _carrinho.length;
    var idx = _indiceLinhaCarrinho ?? 0;
    idx = idx.clamp(0, n - 1);
    final ctrl = _ctrlPressionado();

    if (event.logicalKey == LogicalKeyboardKey.escape) {
      _pesquisaFocus.requestFocus();
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.delete ||
        event.logicalKey == LogicalKeyboardKey.backspace) {
      _removerItemCarrinho(idx);
      return KeyEventResult.handled;
    }
    if (!ctrl && event.logicalKey == LogicalKeyboardKey.numpadAdd) {
      _alterarQuantidadeCarrinho(idx, 1);
      return KeyEventResult.handled;
    }
    if (!ctrl && event.logicalKey == LogicalKeyboardKey.numpadSubtract) {
      _alterarQuantidadeCarrinho(idx, -1);
      return KeyEventResult.handled;
    }
    if (ctrl && event.logicalKey == LogicalKeyboardKey.arrowDown) {
      setState(() {
        _indiceLinhaCarrinho = (idx + 1).clamp(0, n - 1);
      });
      return KeyEventResult.handled;
    }
    if (ctrl && event.logicalKey == LogicalKeyboardKey.arrowUp) {
      setState(() {
        _indiceLinhaCarrinho = (idx - 1).clamp(0, n - 1);
      });
      return KeyEventResult.handled;
    }
    if (!ctrl && event.logicalKey == LogicalKeyboardKey.arrowDown) {
      _alterarQuantidadeCarrinho(idx, 1);
      return KeyEventResult.handled;
    }
    if (!ctrl && event.logicalKey == LogicalKeyboardKey.arrowUp) {
      _alterarQuantidadeCarrinho(idx, -1);
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  void _carregarDadosIniciais() {
    setState(() {
      _produtos = widget.produtoRepository.listarTodos();
      _clientes = widget.clienteRepository
          .listarTodos()
          .where((c) => c.ativo)
          .toList();
      _vendedoresAtivos = widget.vendedorRepository.listarAtivos();
      _indiceListaProduto = _produtos.isEmpty ? null : 0;
    });
  }

  String _rotuloItemVendedorPdV(Vendedor v) {
    final nome = v.apelido.trim().isNotEmpty
        ? v.apelido.trim()
        : v.nomeCompleto.trim();
    final codigo = v.codigoInterno.trim();
    return codigo.isEmpty ? nome : '$codigo · $nome';
  }

  String _formatarMoeda(double valor) => 'R\$ ${_currency.format(valor)}';

  double _parseValorMonetario(String valor) {
    final normalizado = valor.trim().replaceAll('.', '').replaceAll(',', '.');
    if (normalizado.isEmpty) return 0;
    return double.tryParse(normalizado) ?? 0;
  }

  Cliente? _clienteSelecionado() {
    final id = _clienteSelecionadoId;
    if (id == null) return null;
    return _clientes.where((c) => c.id == id).firstOrNull;
  }

  String _rotuloClienteSelecionadoPdV() {
    final cliente = _clienteSelecionado();
    return cliente?.nomeRazao ?? 'Sem cliente';
  }

  Future<void> _selecionarClienteNoOrcamento(int? value) async {
    if (value == null) {
      setState(() {
        _clienteSelecionadoId = null;
        _tipoEntregaSelecionada = 'retirada';
        _prioridadeEntregaSelecionada = 'normal';
        _janelaEntregaSelecionada = 'nao_definida';
        _dataEntregaMarcada = null;
        _valorFreteController.clear();
        _enderecoEntregaController.clear();
        _observacaoEntregaController.clear();
      });
      return;
    }
    final cliente = _clientes.where((c) => c.id == value).firstOrNull;
    if (cliente == null) return;
    final entrega = await _abrirDialogEntregaCliente(cliente: cliente);
    if (!mounted || entrega == null) {
      return;
    }
    setState(() {
      _clienteSelecionadoId = value;
      _tipoEntregaSelecionada = 'entrega_loja';
      _prioridadeEntregaSelecionada = 'normal';
      _dataEntregaMarcada ??= DateTime.now();
      _valorFreteController.text = entrega.valorFrete;
      _enderecoEntregaController.text = entrega.endereco;
      _observacaoEntregaController.text = entrega.observacao;
    });
  }

  Future<void> _abrirCadastroNovoClienteNoPdv() async {
    final clienteCriado = await Navigator.push<Cliente>(
      context,
      MaterialPageRoute(
        builder: (_) => ClientesPage(
          clienteRepository: widget.clienteRepository,
          vendaRepository: widget.vendaRepository,
          retornarClienteAoSalvar: true,
        ),
      ),
    );
    if (!mounted || clienteCriado == null) {
      return;
    }
    setState(() {
      _clientes = widget.clienteRepository
          .listarTodos()
          .where((c) => c.ativo)
          .toList();
    });
    await _selecionarClienteNoOrcamento(clienteCriado.id);
  }

  Future<void> _abrirSeletorClienteNoPdv() async {
    final resultado = await showDialog<int>(
      context: context,
      builder: (dialogContext) {
        final pesquisaController = TextEditingController();
        var filtrados = List<Cliente>.from(_clientes);
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: const Text('Selecionar cliente'),
              content: SizedBox(
                width: 680,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextField(
                      controller: pesquisaController,
                      autofocus: true,
                      decoration: const InputDecoration(
                        labelText: 'Buscar por nome, documento, telefone...',
                        prefixIcon: Icon(Icons.search),
                      ),
                      onChanged: (value) {
                        final termo = value.trim().toLowerCase();
                        final termoNumerico =
                            value.replaceAll(RegExp(r'\D'), '');
                        setDialogState(() {
                          if (termo.isEmpty) {
                            filtrados = List<Cliente>.from(_clientes);
                            return;
                          }
                          filtrados = _clientes.where((cliente) {
                            final campos = [
                              cliente.nomeRazao,
                              cliente.nomeFantasia,
                              cliente.documento,
                              cliente.telefone,
                              cliente.whatsapp,
                              cliente.email,
                              cliente.cidade,
                            ].map((e) => e.toLowerCase());
                            final matchTexto = campos.any(
                              (campo) => campo.contains(termo),
                            );
                            if (matchTexto) return true;
                            if (termoNumerico.isEmpty) return false;
                            final camposNumericos = [
                              cliente.documento,
                              cliente.telefone,
                              cliente.whatsapp,
                              cliente.cep,
                            ].map((e) => e.replaceAll(RegExp(r'\D'), ''));
                            return camposNumericos.any(
                              (campoNumerico) =>
                                  campoNumerico.contains(termoNumerico),
                            );
                          }).toList();
                        });
                      },
                    ),
                    const SizedBox(height: 10),
                    ListTile(
                      dense: true,
                      leading: const Icon(Icons.person_off_outlined),
                      title: const Text('Sem cliente'),
                      onTap: () => Navigator.pop(
                        dialogContext,
                        _selecaoSemClienteValor,
                      ),
                    ),
                    ListTile(
                      dense: true,
                      leading: const Icon(Icons.person_add_alt_1_outlined),
                      title: const Text('+ Novo cliente...'),
                      onTap: () => Navigator.pop(
                        dialogContext,
                        _selecaoNovoClienteValor,
                      ),
                    ),
                    const Divider(height: 12),
                    ConstrainedBox(
                      constraints: BoxConstraints(
                        maxHeight: MediaQuery.of(context).size.height * 0.45,
                      ),
                      child: filtrados.isEmpty
                          ? const Center(child: Text('Nenhum cliente encontrado.'))
                          : ListView.builder(
                              shrinkWrap: true,
                              itemCount: filtrados.length,
                              itemBuilder: (context, index) {
                                final c = filtrados[index];
                                final documento = c.documento.trim().isEmpty
                                    ? '-'
                                    : c.documento;
                                return ListTile(
                                  dense: true,
                                  title: Text(c.nomeRazao),
                                  subtitle: Text(
                                    'Doc: $documento | Tel: ${c.telefone.trim().isEmpty ? '-' : c.telefone}',
                                  ),
                                  onTap: () => Navigator.pop(dialogContext, c.id),
                                );
                              },
                            ),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(dialogContext),
                  child: const Text('Cancelar'),
                ),
              ],
            );
          },
        );
      },
    );

    if (!mounted || resultado == null) {
      return;
    }
    if (resultado == _selecaoNovoClienteValor) {
      await _abrirCadastroNovoClienteNoPdv();
      return;
    }
    if (resultado == _selecaoSemClienteValor) {
      await _selecionarClienteNoOrcamento(null);
      return;
    }
    await _selecionarClienteNoOrcamento(resultado);
  }

  String _montarEnderecoEntregaCliente(Cliente cliente) {
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

  String _montarObservacaoEntregaCliente(Cliente cliente) {
    final partes = <String>[];
    final referencia = cliente.referencia.trim();
    final telefone = cliente.telefone.trim();
    if (telefone.isNotEmpty) {
      partes.add('Tel: $telefone');
    }
    if (referencia.isNotEmpty) {
      partes.add(referencia);
    }
    return partes.join(' | ');
  }

  String _resumoEntrega() {
    final endereco = _enderecoEntregaController.text.trim();
    final obs = _observacaoEntregaController.text.trim();
    final frete = _valorFreteController.text.trim();
    final partes = <String>[];
    if (endereco.isNotEmpty) {
      partes.add(endereco);
    }
    if (obs.isNotEmpty) {
      partes.add('Obs: $obs');
    }
    if (frete.isNotEmpty && _parseValorMonetario(frete) > 0) {
      partes.add('Frete: ${_formatarMoeda(_parseValorMonetario(frete))}');
    }
    if (_dataEntregaMarcada != null) {
      partes.add(
        'Data marcada: ${DateFormat('dd/MM/yyyy').format(_dataEntregaMarcada!)}',
      );
    }
    return partes.isEmpty ? 'Sem dados de entrega informados.' : partes.join(' | ');
  }

  Future<_EntregaDialogResult?> _abrirDialogEntregaCliente({
    required Cliente cliente,
  }) async {
    final enderecoInicial = _montarEnderecoEntregaCliente(cliente);
    final obsInicial = _montarObservacaoEntregaCliente(cliente);
    return showDialog<_EntregaDialogResult>(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        return _EntregaClienteDialog(
          clienteNome: cliente.nomeRazao,
          enderecoInicial: enderecoInicial,
          observacaoInicial: obsInicial,
          valorFreteInicial: _valorFreteController.text.trim(),
        );
      },
    );
  }

  double _precoPorTipo(Produto produto, String precoTipo) {
    switch (precoTipo) {
      case 'preco2':
        return produto.preco2 > 0 ? produto.preco2 : produto.precoVenda;
      case 'preco3':
        return produto.preco3 > 0 ? produto.preco3 : produto.precoVenda;
      case 'preco1':
      default:
        return produto.preco1 > 0 ? produto.preco1 : produto.precoVenda;
    }
  }

  String _rotuloPreco(String precoTipo) {
    switch (precoTipo) {
      case 'preco2':
        return 'À Vista';
      case 'preco3':
        return 'Atacado';
      case 'preco1':
      default:
        return 'A Prazo';
    }
  }

  Future<void> _adicionarAoOrcamento(Produto produto) async {
    final result = await showDialog<_AdicionarOrcamentoResult>(
      context: context,
      builder: (context) => _AdicionarAoOrcamentoDialog(
        produto: produto,
        precoTipoInicial: _precoListaAtivo,
        precoUnitarioDe: (t) => _precoPorTipo(produto, t),
        formatarMoeda: _formatarMoeda,
      ),
    );

    if (result == null) {
      return;
    }
    if (!mounted) {
      return;
    }
    final quantidade = result.quantidade;
    final precoTipo = result.precoTipo;
    if (quantidade <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Quantidade deve ser maior que zero.')),
      );
      return;
    }

    final precoUnit = _precoPorTipo(produto, precoTipo);
    if (!_permitirVendaSemEstoque) {
      final fresh = widget.produtoRepository.obterPorId(produto.id) ?? produto;
      final disp = fresh.estoqueReal;
      if (disp <= 0) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Sem estoque de ${produto.nome}.')),
        );
        return;
      }

      final idxExistente = _carrinho.indexWhere(
        (e) => e.produto.id == produto.id && e.precoTipo == precoTipo,
      );
      if (idxExistente >= 0) {
        final novoTotal = _carrinho[idxExistente].quantidade + quantidade;
        if (novoTotal > disp) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                'Estoque maximo para ${produto.nome}: $disp (ja ha ${_carrinho[idxExistente].quantidade} no orcamento).',
              ),
            ),
          );
          return;
        }
      } else {
        if (quantidade > disp) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Estoque maximo para ${produto.nome}: $disp.'),
            ),
          );
          return;
        }
      }
    }

    final idxExistente = _carrinho.indexWhere(
      (e) => e.produto.id == produto.id && e.precoTipo == precoTipo,
    );

    setState(() {
      if (idxExistente >= 0) {
        _carrinho[idxExistente].quantidade =
            _carrinho[idxExistente].quantidade + quantidade;
        _indiceLinhaCarrinho = idxExistente;
      } else {
        _carrinho.add(
          _OrcamentoItemDraft(
            produto: produto,
            quantidade: quantidade,
            precoTipo: precoTipo,
            precoUnitario: precoUnit,
          ),
        );
        _indiceLinhaCarrinho = _carrinho.length - 1;
      }
    });
    _voltarFocoParaPesquisa();
  }

  Future<void> _salvarOrcamento() async {
    if (_carrinho.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Adicione ao menos um item no orcamento.'),
        ),
      );
      return;
    }
    try {
      final valorFrete = _tipoEntregaSelecionada == 'entrega_loja'
          ? _parseValorMonetario(_valorFreteController.text)
          : 0.0;
      if (_tipoEntregaSelecionada == 'entrega_loja' &&
          _enderecoEntregaController.text.trim().isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Informe o endereco para entrega da loja.'),
          ),
        );
        return;
      }
      if (_tipoEntregaSelecionada == 'entrega_loja' &&
          _prioridadeEntregaSelecionada == 'agendada' &&
          _janelaEntregaSelecionada == 'nao_definida') {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Para entrega agendada, selecione janela Manha ou Tarde.',
            ),
          ),
        );
        return;
      }
      if (_tipoEntregaSelecionada == 'entrega_loja' &&
          _dataEntregaMarcada == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Defina a data combinada da entrega com o cliente.'),
          ),
        );
        return;
      }
      if (valorFrete < 0) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Valor do frete nao pode ser negativo.'),
          ),
        );
        return;
      }
      final itens = _carrinho
          .map(
            (item) => ItemVendaInput(
              produtoId: item.produto.id,
              quantidade: item.quantidade,
              precoUnitario: item.precoUnitario,
              precoTipo: item.precoTipo,
            ),
          )
          .toList();
      final pagamento = DadosPagamentoOrcamento(
        formaPagamento: _formaPagamentoSelecionada,
        quantidadeParcelas: _formaPagamentoSelecionada == 'cartao_credito'
            ? _parcelasSelecionadas
            : 1,
      );
      final entrega = DadosEntregaOrcamento(
        tipoEntrega: _tipoEntregaSelecionada,
        valorFrete: valorFrete,
        enderecoEntrega: _enderecoEntregaController.text.trim(),
        observacaoEntrega: _observacaoEntregaController.text.trim(),
        prioridadeEntrega: _tipoEntregaSelecionada == 'entrega_loja'
            ? _prioridadeEntregaSelecionada
            : 'normal',
        janelaEntrega: _tipoEntregaSelecionada == 'entrega_loja'
            ? _janelaEntregaSelecionada
            : 'nao_definida',
        dataEntregaMarcada: _tipoEntregaSelecionada == 'entrega_loja'
            ? _dataEntregaMarcada
            : null,
      );
      final orcamentoEdicaoId = _orcamentoEmEdicaoId;
      int orcamentoId;
      if (orcamentoEdicaoId != null) {
        widget.vendaRepository.atualizarOrcamento(
          orcamentoEdicaoId,
          itens,
          pagamento: pagamento,
          entrega: entrega,
          clienteId: _clienteSelecionadoId,
          vendedorId: _vendedorSelecionadoId,
        );
        orcamentoId = orcamentoEdicaoId;
      } else {
        orcamentoId = widget.vendaRepository.registrarOrcamento(
          itens,
          pagamento: pagamento,
          entrega: entrega,
          clienteId: _clienteSelecionadoId,
          vendedorId: _vendedorSelecionadoId,
        );
      }
      final vendaSalva = widget.vendaRepository.obterPorId(orcamentoId);
      final numeroOrcamentoSalvo = vendaSalva?.numeroOrcamento ?? _orcamentoEmEdicaoNumero;
      setState(() {
        _carrinho.clear();
        _formaPagamentoSelecionada = 'dinheiro';
        _parcelasSelecionadas = 1;
        _clienteSelecionadoId = null;
        _vendedorSelecionadoId = null;
        _tipoEntregaSelecionada = 'retirada';
        _prioridadeEntregaSelecionada = 'normal';
        _janelaEntregaSelecionada = 'nao_definida';
        _dataEntregaMarcada = null;
        _valorFreteController.clear();
        _enderecoEntregaController.clear();
        _observacaoEntregaController.clear();
        _orcamentoEmEdicaoId = null;
        _orcamentoEmEdicaoNumero = null;
      });
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            orcamentoEdicaoId != null
                ? 'Orcamento #$numeroOrcamentoSalvo atualizado com sucesso.'
                : 'Orcamento #$orcamentoId salvo para o caixa.',
          ),
        ),
      );
      if (vendaSalva != null && mounted) {
        await _mostrarAcoesPdfOrcamento(vendaSalva);
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Erro ao salvar orcamento: $e')));
    }
  }

  Future<bool> _confirmarSubstituirRascunhoAtual() async {
    if (_carrinho.isEmpty) {
      return true;
    }
    final resposta = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Carregar outro orcamento'),
        content: const Text(
          'Existe um orcamento em edicao na tela. Deseja descartar este rascunho e carregar outro?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Carregar'),
          ),
        ],
      ),
    );
    return resposta == true;
  }

  String _rotuloVendedorUmLinhaOrcamento(Venda venda) {
    final vendedor = _vendedorDaVenda(venda);
    if (vendedor == null) {
      return 'Sem vendedor';
    }
    final nome = vendedor.apelido.trim().isNotEmpty
        ? vendedor.apelido.trim()
        : vendedor.nomeCompleto.trim();
    final codigo = vendedor.codigoInterno.trim();
    return codigo.isEmpty ? nome : '$codigo · $nome';
  }

  String _normalizarTextoComparacao(String texto) {
    var t = texto.trim().toLowerCase();
    const mapa = {
      'á': 'a',
      'à': 'a',
      'â': 'a',
      'ã': 'a',
      'ä': 'a',
      'é': 'e',
      'è': 'e',
      'ê': 'e',
      'ë': 'e',
      'í': 'i',
      'ì': 'i',
      'î': 'i',
      'ï': 'i',
      'ó': 'o',
      'ò': 'o',
      'ô': 'o',
      'õ': 'o',
      'ö': 'o',
      'ú': 'u',
      'ù': 'u',
      'û': 'u',
      'ü': 'u',
      'ç': 'c',
    };
    mapa.forEach((origem, destino) {
      t = t.replaceAll(origem, destino);
    });
    t = t.replaceAll(RegExp(r'[^a-z0-9]+'), ' ').trim();
    return t;
  }

  Produto? _resolverProdutoItemOrcamento(
    ItemVenda item,
    List<Produto> todosProdutos,
  ) {
    final porTarget = item.produto.target;
    if (porTarget != null) {
      return porTarget;
    }
    final porId = widget.produtoRepository.obterPorId(item.produto.targetId);
    if (porId != null) {
      return porId;
    }

    final nomeItem = _normalizarTextoComparacao(item.nomeProduto);
    if (nomeItem.isEmpty) {
      return null;
    }

    final exato = todosProdutos.where((p) {
      final nome = _normalizarTextoComparacao(p.nome);
      return nome == nomeItem;
    }).firstOrNull;
    if (exato != null) {
      return exato;
    }

    final aproximado = todosProdutos.where((p) {
      final nome = _normalizarTextoComparacao(p.nome);
      return nome.contains(nomeItem) || nomeItem.contains(nome);
    }).firstOrNull;
    return aproximado;
  }

  Future<void> _abrirLeitorOrcamento() async {
    final podeSubstituir = await _confirmarSubstituirRascunhoAtual();
    if (!mounted || !podeSubstituir) {
      return;
    }
    final pendentes = widget.vendaRepository.listarOrcamentosPendentes();
    if (pendentes.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Nao ha orcamentos pendentes para leitura.')),
      );
      return;
    }

    final pesquisaController = TextEditingController();
    List<Venda> resultados = List<Venda>.from(pendentes);
    final selecionado = await showDialog<Venda>(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: const Text('Ler orcamento'),
              content: SizedBox(
                width: 760,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextField(
                      controller: pesquisaController,
                      autofocus: true,
                      decoration: const InputDecoration(
                        labelText: 'Numero, cliente, vendedor...',
                        prefixIcon: Icon(Icons.search),
                      ),
                      onChanged: (value) {
                        final termo = value.trim().toLowerCase();
                        setDialogState(() {
                          resultados = pendentes.where((orc) {
                            final cliente = _clienteDaVenda(orc)?.nomeRazao ?? '';
                            final vendedor = _rotuloVendedorUmLinhaOrcamento(orc);
                            return orc.numeroOrcamento.toString().contains(termo) ||
                                cliente.toLowerCase().contains(termo) ||
                                vendedor.toLowerCase().contains(termo);
                          }).toList();
                        });
                      },
                    ),
                    const SizedBox(height: 10),
                    ConstrainedBox(
                      constraints: BoxConstraints(
                        minHeight: 220,
                        maxHeight: MediaQuery.of(context).size.height * 0.58,
                      ),
                      child: resultados.isEmpty
                          ? const Center(child: Text('Nenhum orcamento encontrado.'))
                          : ListView.builder(
                              shrinkWrap: true,
                              itemCount: resultados.length,
                              itemBuilder: (context, index) {
                                final orc = resultados[index];
                                final cliente =
                                    _clienteDaVenda(orc)?.nomeRazao ?? 'Sem cliente';
                                return ListTile(
                                  title: Text('Orcamento #${orc.numeroOrcamento}'),
                                  subtitle: Text(
                                    '$cliente | Itens: ${orc.itens.length} | Total: ${_formatarMoeda(orc.total)}',
                                  ),
                                  onTap: () => Navigator.pop(context, orc),
                                );
                              },
                            ),
                    ),
                  ],
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
    pesquisaController.dispose();
    if (!mounted || selecionado == null) {
      return;
    }

    final orcamentoCompleto =
        widget.vendaRepository.obterPorId(selecionado.id) ?? selecionado;
    final drafts = <_OrcamentoItemDraft>[];
    final nomesItensSemProduto = <String>[];
    final todosProdutos = widget.produtoRepository.listarTodos();
    for (final item in orcamentoCompleto.itens) {
      final produto = _resolverProdutoItemOrcamento(item, todosProdutos);
      if (produto == null) {
        nomesItensSemProduto.add(item.nomeProduto);
        continue;
      }
      drafts.add(
        _OrcamentoItemDraft(
          produto: produto,
          quantidade: item.quantidade,
          precoTipo: item.precoTipo,
          precoUnitario: item.precoUnitario,
        ),
      );
    }
    if (drafts.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            nomesItensSemProduto.isNotEmpty
                ? 'Nao foi possivel carregar itens do orcamento. Produtos sem cadastro atual.'
                : 'Nao foi possivel carregar itens do orcamento selecionado.',
          ),
        ),
      );
      return;
    }

    final clienteIdCarregado = orcamentoCompleto.cliente.targetId == 0
        ? null
        : orcamentoCompleto.cliente.targetId;
    final vendedorIdCarregado = orcamentoCompleto.vendedor.targetId == 0
        ? null
        : orcamentoCompleto.vendedor.targetId;
    final clienteIdValido = clienteIdCarregado != null &&
            _clientes.any((c) => c.id == clienteIdCarregado)
        ? clienteIdCarregado
        : null;
    final vendedorIdValido = vendedorIdCarregado != null &&
            _vendedoresAtivos.any((v) => v.id == vendedorIdCarregado)
        ? vendedorIdCarregado
        : null;
    final tipoEntregaValido = orcamentoCompleto.tipoEntrega == 'entrega_loja'
        ? 'entrega_loja'
        : 'retirada';
    final prioridadeValida = switch (orcamentoCompleto.prioridadeEntrega) {
      'urgente' => 'urgente',
      'agendada' => 'agendada',
      _ => 'normal',
    };
    final janelaValida = switch (orcamentoCompleto.janelaEntrega) {
      'manha' => 'manha',
      'tarde' => 'tarde',
      _ => 'nao_definida',
    };

    setState(() {
      _carrinho
        ..clear()
        ..addAll(drafts);
      _indiceLinhaCarrinho = _carrinho.isEmpty ? null : 0;
      _clienteSelecionadoId = clienteIdValido;
      _vendedorSelecionadoId = vendedorIdValido;
      _formaPagamentoSelecionada = orcamentoCompleto.formaPagamento;
      _parcelasSelecionadas = orcamentoCompleto.quantidadeParcelas <= 0
          ? 1
          : orcamentoCompleto.quantidadeParcelas;
      _tipoEntregaSelecionada = tipoEntregaValido;
      _prioridadeEntregaSelecionada = prioridadeValida;
      _janelaEntregaSelecionada = janelaValida;
      _dataEntregaMarcada = orcamentoCompleto.dataEntregaMarcada;
      _valorFreteController.text =
          orcamentoCompleto.valorFrete.toStringAsFixed(2).replaceAll('.', ',');
      _enderecoEntregaController.text = orcamentoCompleto.enderecoEntrega;
      _observacaoEntregaController.text = orcamentoCompleto.observacaoEntrega;
      _orcamentoEmEdicaoId = orcamentoCompleto.id;
      _orcamentoEmEdicaoNumero = orcamentoCompleto.numeroOrcamento;
    });
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          nomesItensSemProduto.isEmpty
              ? 'Orcamento #${selecionado.numeroOrcamento} carregado com ${drafts.length} item(ns) para edicao.'
              : 'Orcamento #${selecionado.numeroOrcamento} carregado com ${drafts.length} item(ns). ${nomesItensSemProduto.length} item(ns) sem produto cadastrado foram ignorados.',
        ),
      ),
    );
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
      default:
        return 'Dinheiro';
    }
  }

  String _rotuloTipoEntrega(String tipoEntrega) {
    switch (tipoEntrega) {
      case 'entrega_loja':
        return 'Entrega da loja';
      case 'retirada':
      default:
        return 'Retirada na loja';
    }
  }

  Cliente? _clienteDaVenda(Venda venda) {
    final clienteLigado = venda.cliente.target;
    if (clienteLigado != null) {
      return clienteLigado;
    }
    final clienteId = venda.cliente.targetId;
    if (clienteId == 0) {
      return null;
    }
    return widget.clienteRepository.obterPorId(clienteId);
  }

  Vendedor? _vendedorDaVenda(Venda venda) {
    final ligado = venda.vendedor.target;
    if (ligado != null) {
      return ligado;
    }
    final vid = venda.vendedor.targetId;
    if (vid == 0) {
      return null;
    }
    return widget.vendedorRepository.obterPorId(vid);
  }

  String _rotuloVendedorOrcamentoPdf(Venda venda) {
    final v = _vendedorDaVenda(venda);
    if (v == null) {
      return 'Sem vendedor';
    }
    final nome = v.apelido.trim().isNotEmpty
        ? v.apelido.trim()
        : v.nomeCompleto.trim();
    final codigo = v.codigoInterno.trim();
    return codigo.isNotEmpty ? '$codigo · $nome' : nome;
  }

  Future<Uint8List> _gerarOrcamentoPdfBytes(Venda venda) async {
    final cliente = _clienteDaVenda(venda);
    final empresa = await _configRepository.carregarEmpresaConfig();
    final logoBytes = empresa.logoPath.trim().isNotEmpty
        ? await File(
            empresa.logoPath,
          ).readAsBytes().catchError((_) => Uint8List(0))
        : Uint8List(0);
    final doc = pw.Document();
    final dataEmissao = DateTime.now();
    final dataHora = DateFormat('dd/MM/yyyy HH:mm').format(dataEmissao);
    final validade = dataEmissao.add(Duration(days: _validadeOrcamentoDias));
    final validadeFmt = DateFormat('dd/MM/yyyy').format(validade);
    final subtotalProdutos = (venda.total - venda.valorFrete)
        .clamp(0, double.infinity)
        .toDouble();
    doc.addPage(
      pw.Page(
        pageFormat: empresa.modeloPdf == 'a4'
            ? PdfPageFormat.a4
            : PdfPageFormat(80 * PdfPageFormat.mm, double.infinity),
        margin: const pw.EdgeInsets.all(8),
        build: (context) {
          return pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Center(
                child: pw.Text(
                  'ORCAMENTO - ${empresa.nomeLoja}',
                  style: pw.TextStyle(
                    fontSize: 11,
                    fontWeight: pw.FontWeight.bold,
                  ),
                ),
              ),
              if (logoBytes.isNotEmpty)
                pw.Center(
                  child: pw.Padding(
                    padding: const pw.EdgeInsets.only(top: 4, bottom: 4),
                    child: pw.Image(pw.MemoryImage(logoBytes), height: 45),
                  ),
                ),
              if (empresa.telefone.trim().isNotEmpty)
                pw.Center(
                  child: pw.Text(
                    'Tel: ${empresa.telefone}',
                    style: const pw.TextStyle(fontSize: 8),
                  ),
                ),
              if (empresa.endereco.trim().isNotEmpty)
                pw.Center(
                  child: pw.Text(
                    empresa.endereco,
                    style: const pw.TextStyle(fontSize: 8),
                    textAlign: pw.TextAlign.center,
                  ),
                ),
              pw.SizedBox(height: 6),
              pw.Text(
                'Numero: #${venda.numeroOrcamento}',
                style: const pw.TextStyle(fontSize: 9),
              ),
              pw.Text(
                'Data: $dataHora',
                style: const pw.TextStyle(fontSize: 9),
              ),
              pw.Text(
                'Cliente: ${cliente?.nomeRazao ?? 'Sem cliente'}',
                style: const pw.TextStyle(fontSize: 9),
              ),
              pw.Text(
                'Vendedor: ${_rotuloVendedorOrcamentoPdf(venda)}',
                style: const pw.TextStyle(fontSize: 9),
              ),
              if ((cliente?.telefone.trim().isNotEmpty ?? false))
                pw.Text(
                  'Telefone: ${cliente!.telefone}',
                  style: const pw.TextStyle(fontSize: 9),
                ),
              pw.Text(
                'Validade do orcamento: $validadeFmt ($_validadeOrcamentoDias dias)',
                style: pw.TextStyle(
                  fontSize: 9,
                  fontWeight: pw.FontWeight.bold,
                ),
              ),
              pw.Text(
                'Pagamento: ${_rotuloFormaPagamento(venda.formaPagamento)}'
                '${venda.formaPagamento == 'cartao_credito' ? ' | ${venda.quantidadeParcelas}x' : ''}',
                style: const pw.TextStyle(fontSize: 9),
              ),
              pw.Text(
                'Entrega: ${_rotuloTipoEntrega(venda.tipoEntrega)}',
                style: const pw.TextStyle(fontSize: 9),
              ),
              if (venda.enderecoEntrega.trim().isNotEmpty)
                pw.Text(
                  'Endereco: ${venda.enderecoEntrega}',
                  style: const pw.TextStyle(fontSize: 9),
                ),
              if (venda.observacaoEntrega.trim().isNotEmpty)
                pw.Text(
                  'Obs: ${venda.observacaoEntrega}',
                  style: const pw.TextStyle(fontSize: 9),
                ),
              pw.SizedBox(height: 8),
              pw.Text(
                'ITENS',
                style: pw.TextStyle(
                  fontSize: 9,
                  fontWeight: pw.FontWeight.bold,
                ),
              ),
              pw.SizedBox(height: 4),
              ...venda.itens.map(
                (item) => pw.Padding(
                  padding: const pw.EdgeInsets.only(bottom: 4),
                  child: pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      pw.Text(
                        item.nomeProduto,
                        style: const pw.TextStyle(fontSize: 9),
                      ),
                      pw.Text(
                        '${item.quantidade} x ${_formatarMoeda(item.precoUnitario)} = ${_formatarMoeda(item.subtotal)}',
                        style: const pw.TextStyle(fontSize: 8),
                      ),
                    ],
                  ),
                ),
              ),
              pw.Divider(),
              pw.Text(
                'Subtotal: ${_formatarMoeda(subtotalProdutos)}',
                style: const pw.TextStyle(fontSize: 9),
              ),
              pw.Text(
                'Frete: ${_formatarMoeda(venda.valorFrete)}',
                style: const pw.TextStyle(fontSize: 9),
              ),
              pw.Text(
                'Total: ${_formatarMoeda(venda.total)}',
                style: pw.TextStyle(
                  fontSize: 10,
                  fontWeight: pw.FontWeight.bold,
                ),
              ),
              pw.SizedBox(height: 6),
              pw.Text(
                'Este orcamento e valido por $_validadeOrcamentoDias dias a partir da data de emissao.',
                style: const pw.TextStyle(fontSize: 8),
              ),
              pw.SizedBox(height: 6),
              pw.Text(
                empresa.rodapeOrcamento,
                style: const pw.TextStyle(fontSize: 8),
              ),
            ],
          );
        },
      ),
    );
    return doc.save();
  }

  Future<String?> _escolherSalvarPdf({
    required Uint8List bytes,
    required String suggestedFileName,
    String? initialDirectory,
  }) async {
    final selectedPath = await FilePicker.platform.saveFile(
      dialogTitle: 'Escolha onde salvar o PDF',
      fileName: suggestedFileName,
      initialDirectory: initialDirectory,
      type: FileType.custom,
      allowedExtensions: const ['pdf'],
    );
    if (selectedPath == null) return null;
    final normalizedPath = selectedPath.toLowerCase().endsWith('.pdf')
        ? selectedPath
        : '$selectedPath.pdf';
    final file = File(normalizedPath);
    await file.writeAsBytes(bytes, flush: true);
    return file.path;
  }

  Future<Printer?> _obterImpressoraPadrao(String printerName) async {
    if (printerName.trim().isEmpty) return null;
    final printers = await Printing.listPrinters();
    for (final printer in printers) {
      if (printer.name == printerName) return printer;
    }
    return null;
  }

  Future<void> _mostrarAcoesPdfOrcamento(Venda venda) async {
    final config = await _configRepository.carregarEmpresaConfig();
    if (!mounted) return;
    final acao = await showDialog<String>(
      context: context,
      builder: (context) {
        return CallbackShortcuts(
          bindings: <ShortcutActivator, VoidCallback>{
            const SingleActivator(LogicalKeyboardKey.escape): () =>
                Navigator.pop(context, 'fechar'),
            const SingleActivator(LogicalKeyboardKey.digit1): () =>
                Navigator.pop(context, 'fechar'),
            const SingleActivator(LogicalKeyboardKey.digit2): () =>
                Navigator.pop(context, 'pdf'),
            const SingleActivator(LogicalKeyboardKey.digit3): () =>
                Navigator.pop(context, 'direto'),
            const SingleActivator(LogicalKeyboardKey.digit4): () =>
                Navigator.pop(context, 'imprimir'),
            const SingleActivator(LogicalKeyboardKey.numpad1): () =>
                Navigator.pop(context, 'fechar'),
            const SingleActivator(LogicalKeyboardKey.numpad2): () =>
                Navigator.pop(context, 'pdf'),
            const SingleActivator(LogicalKeyboardKey.numpad3): () =>
                Navigator.pop(context, 'direto'),
            const SingleActivator(LogicalKeyboardKey.numpad4): () =>
                Navigator.pop(context, 'imprimir'),
          },
          child: AlertDialog(
            title: const Text('Orcamento salvo'),
            content: const Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Deseja imprimir o orcamento ou mandar em PDF?'),
                SizedBox(height: 10),
                Text(
                  'Teclado: Esc ou 1 — fechar · 2 — PDF · 3 — impressao direta · '
                  '4 — acao Imprimir (Enter confirma o botao em foco) · Tab entre botoes',
                  style: TextStyle(fontSize: 12.5),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, 'fechar'),
                child: const Text('Fechar (Esc · 1)'),
              ),
              OutlinedButton.icon(
                onPressed: () => Navigator.pop(context, 'pdf'),
                icon: const Icon(Icons.picture_as_pdf_outlined),
                label: const Text('Mandar em PDF (2)'),
              ),
              OutlinedButton.icon(
                onPressed: () => Navigator.pop(context, 'direto'),
                icon: const Icon(Icons.print),
                label: const Text('Impressao direta (3)'),
              ),
              ElevatedButton.icon(
                autofocus: true,
                onPressed: () => Navigator.pop(context, 'imprimir'),
                icon: const Icon(Icons.print_outlined),
                label: const Text('Imprimir (4 · Enter)'),
              ),
            ],
          ),
        );
      },
    );
    if (!mounted || acao == null || acao == 'fechar') return;
    try {
      final pdfBytes = await _gerarOrcamentoPdfBytes(venda);
      if (acao == 'imprimir') {
        await Printing.layoutPdf(onLayout: (_) async => pdfBytes);
        return;
      }
      if (acao == 'direto') {
        final printer = await _obterImpressoraPadrao(config.impressoraPadrao);
        if (printer == null) {
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Impressora padrao nao configurada/encontrada.'),
            ),
          );
          return;
        }
        await Printing.directPrintPdf(
          printer: printer,
          onLayout: (_) async => pdfBytes,
          name: 'Orcamento ${venda.numeroOrcamento}',
          format: config.modeloPdf == 'a4'
              ? PdfPageFormat.a4
              : PdfPageFormat(80 * PdfPageFormat.mm, double.infinity),
        );
        return;
      }
      final path = await _escolherSalvarPdf(
        bytes: pdfBytes,
        suggestedFileName: 'orcamento_${venda.numeroOrcamento}.pdf',
        initialDirectory: config.pastaPadraoPdf.trim().isEmpty
            ? null
            : config.pastaPadraoPdf.trim(),
      );
      if (!mounted || path == null) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('PDF do orcamento salvo em: $path')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Nao foi possivel gerar/imprimir orcamento: $e'),
        ),
      );
    }
  }

  double get _totalOrcamento =>
      _carrinho.fold(0, (total, item) => total + item.subtotal);

  double get _valorFreteAtual => _tipoEntregaSelecionada == 'entrega_loja'
      ? _parseValorMonetario(_valorFreteController.text)
      : 0.0;

  double get _totalGeralComFrete => _totalOrcamento + _valorFreteAtual;

  String _rotuloParcela(int parcelas) {
    if (parcelas <= 0) {
      return '1x';
    }
    final valorParcela = _totalGeralComFrete / parcelas;
    return '${parcelas}x de ${_formatarMoeda(valorParcela)}';
  }

  @override
  Widget build(BuildContext context) {
    return Shortcuts(
      shortcuts: const <ShortcutActivator, Intent>{
        SingleActivator(LogicalKeyboardKey.arrowDown):
            IrParaListaProdutosIntent(),
        SingleActivator(LogicalKeyboardKey.f1): SelecionarPrecoListaIntent(
          'preco1',
        ),
        SingleActivator(LogicalKeyboardKey.f2): SelecionarPrecoListaIntent(
          'preco2',
        ),
        SingleActivator(LogicalKeyboardKey.f3): SelecionarPrecoListaIntent(
          'preco3',
        ),
        SingleActivator(LogicalKeyboardKey.f5): PdvRecarregarProdutosIntent(),
        SingleActivator(LogicalKeyboardKey.f6): PdvFocarCarrinhoIntent(),
        SingleActivator(LogicalKeyboardKey.f7): PdvCheckoutProximoIntent(),
        SingleActivator(LogicalKeyboardKey.f7, shift: true):
            PdvCheckoutAnteriorIntent(),
        SingleActivator(LogicalKeyboardKey.f10): PdvSalvarOrcamentoIntent(),
        SingleActivator(LogicalKeyboardKey.keyS, control: true):
            PdvSalvarOrcamentoIntent(),
        SingleActivator(LogicalKeyboardKey.keyO, control: true):
            PdvLerOrcamentoIntent(),
        SingleActivator(LogicalKeyboardKey.keyK, control: true):
            PdvLimparPesquisaIntent(),
      },
      child: Actions(
        actions: <Type, Action<Intent>>{
          IrParaListaProdutosIntent: CallbackAction<IrParaListaProdutosIntent>(
            onInvoke: (_) {
              if (!_pesquisaFocus.hasFocus || _produtos.isEmpty) {
                return null;
              }
              _irDoCampoPesquisaParaLista();
              return null;
            },
          ),
          SelecionarPrecoListaIntent:
              CallbackAction<SelecionarPrecoListaIntent>(
                onInvoke: (intent) {
                  setState(() => _precoListaAtivo = intent.precoTipo);
                  return null;
                },
              ),
          PdvRecarregarProdutosIntent:
              CallbackAction<PdvRecarregarProdutosIntent>(
                onInvoke: (_) {
                  _carregarDadosIniciais();
                  return null;
                },
              ),
          PdvFocarCarrinhoIntent: CallbackAction<PdvFocarCarrinhoIntent>(
            onInvoke: (_) {
              _focarCarrinhoAtalho();
              return null;
            },
          ),
          PdvCheckoutProximoIntent: CallbackAction<PdvCheckoutProximoIntent>(
            onInvoke: (_) {
              _focarProximoCampoCheckout();
              return null;
            },
          ),
          PdvCheckoutAnteriorIntent: CallbackAction<PdvCheckoutAnteriorIntent>(
            onInvoke: (_) {
              _focarCampoCheckoutAnterior();
              return null;
            },
          ),
          PdvSalvarOrcamentoIntent: CallbackAction<PdvSalvarOrcamentoIntent>(
            onInvoke: (_) {
              unawaited(_salvarOrcamento());
              return null;
            },
          ),
          PdvLerOrcamentoIntent: CallbackAction<PdvLerOrcamentoIntent>(
            onInvoke: (_) {
              unawaited(_abrirLeitorOrcamento());
              return null;
            },
          ),
          PdvLimparPesquisaIntent: CallbackAction<PdvLimparPesquisaIntent>(
            onInvoke: (_) {
              _limparPesquisaAtalho();
              return null;
            },
          ),
        },
        child: Scaffold(
          appBar: AppBar(
            title: const Text('Ponto de Venda'),
            actions: [
              IconButton(
                tooltip: 'Ler orcamento para editar',
                onPressed: _abrirLeitorOrcamento,
                icon: const Icon(Icons.description_outlined),
              ),
            ],
          ),
          body: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  flex: 3,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      TextField(
                        autofocus: true,
                        focusNode: _pesquisaFocus,
                        controller: _pesquisaController,
                        textInputAction: TextInputAction.search,
                        decoration: InputDecoration(
                          labelText: 'Pesquisar produto para venda',
                          suffixIcon: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              IconButton(
                                tooltip: 'Limpar busca',
                                onPressed: () {
                                  _pesquisaController.clear();
                                  _debouncePesquisa?.cancel();
                                  setState(() {
                                    _pesquisaAguardandoDebounce = false;
                                  });
                                  _pesquisar();
                                },
                                icon: const Icon(Icons.clear),
                              ),
                              IconButton(
                                tooltip: 'Pesquisar',
                                onPressed: () {
                                  _debouncePesquisa?.cancel();
                                  setState(() {
                                    _pesquisaAguardandoDebounce = false;
                                  });
                                  _pesquisar(executarAtalhoRapido: true);
                                },
                                icon: const Icon(Icons.search),
                              ),
                              IconButton(
                                tooltip: 'Recarregar produtos',
                                onPressed: () {
                                  _debouncePesquisa?.cancel();
                                  setState(() {
                                    _pesquisaAguardandoDebounce = false;
                                  });
                                  _carregarDadosIniciais();
                                },
                                icon: const Icon(Icons.refresh),
                              ),
                              if (_pesquisaAguardandoDebounce)
                                Padding(
                                  padding: const EdgeInsets.only(right: 8),
                                  child: Text(
                                    'buscando...',
                                    style: Theme.of(context).textTheme.bodySmall,
                                  ),
                                ),
                            ],
                          ),
                        ),
                        onChanged: (_) => _agendarPesquisaDebounce(),
                        onSubmitted: (_) =>
                            _pesquisar(executarAtalhoRapido: true),
                      ),
                      const SizedBox(height: 6),
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              'Preco: ${_rotuloPreco(_precoListaAtivo)} · ${_produtos.length} produtos',
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                          ),
                          TextButton.icon(
                            onPressed: () {
                              setState(() {
                                _mostrarAjudaAtalhos = !_mostrarAjudaAtalhos;
                              });
                            },
                            icon: Icon(
                              _mostrarAjudaAtalhos
                                  ? Icons.keyboard_arrow_up
                                  : Icons.keyboard_arrow_down,
                            ),
                            label: Text(
                              _mostrarAjudaAtalhos
                                  ? 'Ocultar atalhos'
                                  : 'Ajuda de atalhos',
                            ),
                          ),
                        ],
                      ),
                      AnimatedCrossFade(
                        crossFadeState: _mostrarAjudaAtalhos
                            ? CrossFadeState.showFirst
                            : CrossFadeState.showSecond,
                        duration: const Duration(milliseconds: 180),
                        firstChild: Container(
                          width: double.infinity,
                          margin: const EdgeInsets.only(top: 4, bottom: 8),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 8,
                          ),
                          decoration: BoxDecoration(
                            color: Theme.of(context).colorScheme.surfaceContainerHighest,
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Text(
                            'F1–F3 preco · F5 recarrega · Ctrl+K limpa busca · Enter -> lista · '
                            'Numpad+ adiciona 1 · F6 carrinho · F7 checkout · Ctrl+O ler orcamento · '
                            'F10/Ctrl+S salvar.',
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ),
                        secondChild: const SizedBox.shrink(),
                      ),
                      const SizedBox(height: 8),
                      Expanded(
                        child: _produtos.isEmpty
                            ? Center(
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    const Text('Nenhum produto encontrado.'),
                                    const SizedBox(height: 8),
                                    OutlinedButton.icon(
                                      onPressed: _carregarDadosIniciais,
                                      icon: const Icon(Icons.refresh),
                                      label: const Text('Recarregar produtos'),
                                    ),
                                  ],
                                ),
                              )
                            : Builder(
                                builder: (context) {
                                  final termoBuscaDestaque = _PesquisaComando.parse(
                                    _pesquisaController.text,
                                  ).termoBusca;
                                  return Focus(
                                focusNode: _listaProdutosFocus,
                                onKeyEvent: _onKeyListaProdutos,
                                child: ListView.builder(
                                  controller: _listaProdutosScrollController,
                                  itemExtent: _alturaLinhaProduto,
                                  itemCount: _produtos.length,
                                  itemBuilder: (context, index) {
                                    final item = _produtos[index];
                                    final selecionado =
                                        _indiceListaProduto == index;
                                    final precoLinha = _precoPorTipo(
                                      item,
                                      _precoListaAtivo,
                                    );
                                    final scheme = Theme.of(
                                      context,
                                    ).colorScheme;
                                    final critico = _estoqueCritico(item);
                                    return Material(
                                      color: selecionado
                                          ? scheme.primaryContainer.withValues(
                                              alpha: 0.55,
                                            )
                                          : Theme.of(
                                              context,
                                            ).colorScheme.surface,
                                      child: InkWell(
                                        onTap: () =>
                                            _mostrarSkuEDescricao(item),
                                        child: Padding(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 10,
                                            vertical: 6,
                                          ),
                                          child: Row(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.center,
                                            children: [
                                              Expanded(
                                                child: RichText(
                                                  maxLines: 2,
                                                  overflow: TextOverflow.ellipsis,
                                                  text: _textoComDestaqueBusca(
                                                    context: context,
                                                    texto: item.nome,
                                                    termoBusca:
                                                        termoBuscaDestaque,
                                                    estiloBase:
                                                        Theme.of(context)
                                                            .textTheme
                                                            .bodyMedium ??
                                                        const TextStyle(),
                                                  ),
                                                ),
                                              ),
                                              Column(
                                                mainAxisAlignment:
                                                    MainAxisAlignment.center,
                                                crossAxisAlignment:
                                                    CrossAxisAlignment.end,
                                                children: [
                                                  Text(
                                                    _formatarMoeda(precoLinha),
                                                    style: Theme.of(context)
                                                        .textTheme
                                                        .titleSmall
                                                        ?.copyWith(
                                                          fontWeight:
                                                              FontWeight.bold,
                                                        ),
                                                  ),
                                                  Text(
                                                    'Est: ${item.estoque}',
                                                    style: Theme.of(context)
                                                        .textTheme
                                                        .labelMedium
                                                        ?.copyWith(
                                                          color: critico
                                                              ? scheme.error
                                                              : scheme.tertiary,
                                                          fontWeight:
                                                              FontWeight.w700,
                                                        ),
                                                  ),
                                                ],
                                              ),
                                              IconButton(
                                                tooltip:
                                                    'À Vista ou Atacado, quantidade…',
                                                visualDensity:
                                                    VisualDensity.compact,
                                                padding: EdgeInsets.zero,
                                                constraints:
                                                    const BoxConstraints(
                                                      minWidth: 32,
                                                      minHeight: 36,
                                                    ),
                                                icon: const Icon(
                                                  Icons.tune,
                                                  size: 20,
                                                ),
                                                onPressed: () =>
                                                    _adicionarAoOrcamento(item),
                                              ),
                                              IconButton(
                                                tooltip:
                                                    'Adicionar (${_rotuloPreco(_precoListaAtivo)})',
                                                visualDensity:
                                                    VisualDensity.compact,
                                                padding: EdgeInsets.zero,
                                                constraints:
                                                    const BoxConstraints(
                                                      minWidth: 36,
                                                      minHeight: 36,
                                                    ),
                                                icon: const Icon(
                                                  Icons
                                                      .add_shopping_cart_outlined,
                                                ),
                                                onPressed: () =>
                                                    _adicionarRapido(item),
                                              ),
                                            ],
                                          ),
                                        ),
                                      ),
                                    );
                                  },
                                ),
                              );
                                },
                              ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 10),
                AnimatedContainer(
                  duration: const Duration(milliseconds: 180),
                  curve: Curves.easeOut,
                  width: _painelCheckoutRecolhido ? 64 : 470,
                  child: _painelCheckoutRecolhido
                      ? Card(
                          child: Column(
                            children: [
                              IconButton(
                                tooltip: 'Expandir checkout',
                                onPressed: () {
                                  setState(() {
                                    _painelCheckoutRecolhido = false;
                                  });
                                },
                                icon: const Icon(Icons.chevron_left),
                              ),
                              const SizedBox(height: 8),
                              Text(
                                '${_carrinho.length}',
                                style: Theme.of(context).textTheme.titleMedium,
                              ),
                              Text(
                                'itens',
                                style: Theme.of(context).textTheme.bodySmall,
                              ),
                              const Divider(height: 20),
                              Padding(
                                padding: const EdgeInsets.symmetric(horizontal: 6),
                                child: Text(
                                  _formatarMoeda(_totalGeralComFrete),
                                  textAlign: TextAlign.center,
                                  style: Theme.of(context).textTheme.bodySmall
                                      ?.copyWith(fontWeight: FontWeight.w700),
                                ),
                              ),
                            ],
                          ),
                        )
                      : Card(
                          child: Theme(
                      data: Theme.of(context).copyWith(
                        visualDensity: VisualDensity.compact,
                        inputDecorationTheme:
                            Theme.of(context).inputDecorationTheme.copyWith(
                                  isDense: true,
                                  contentPadding: const EdgeInsets.symmetric(
                                    horizontal: 10,
                                    vertical: 10,
                                  ),
                                ),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(10),
                        child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  'Orcamento em atendimento',
                                  style: Theme.of(context).textTheme.titleMedium,
                                ),
                              ),
                              IconButton(
                                tooltip: 'Recolher checkout',
                                onPressed: () {
                                  setState(() {
                                    _painelCheckoutRecolhido = true;
                                  });
                                },
                                icon: const Icon(Icons.chevron_right),
                              ),
                            ],
                          ),
                          if (_carrinho.isNotEmpty)
                            Padding(
                              padding: const EdgeInsets.only(top: 4),
                              child: Text(
                                'F6 foca aqui · ↑↓ quantidade · Ctrl+↑↓ linha · Del remove · Numpad ± quantidade',
                                style: Theme.of(context).textTheme.bodySmall,
                              ),
                            ),
                          const SizedBox(height: 6),
                          Expanded(
                            child: _carrinho.isEmpty
                                ? const Center(
                                    child: Text('Nenhum item no orcamento.'),
                                  )
                                : Focus(
                                    focusNode: _carrinhoFocus,
                                    onKeyEvent: _onKeyCarrinho,
                                    child: ListView.separated(
                                      itemCount: _carrinho.length,
                                      separatorBuilder: (_, _) => const Divider(
                                        height: 1,
                                        thickness: 1,
                                      ),
                                      itemBuilder: (context, index) {
                                        final item = _carrinho[index];
                                        final theme = Theme.of(context);
                                        return Semantics(
                                          container: true,
                                          label:
                                              '${item.produto.nome}, ${_rotuloPreco(item.precoTipo)}, quantidade ${item.quantidade}',
                                          child: ListTile(
                                            selected:
                                                _indiceLinhaCarrinho == index,
                                            selectedTileColor: theme
                                                .colorScheme
                                                .primaryContainer
                                                .withValues(alpha: 0.35),
                                            onTap: () {
                                              setState(
                                                () => _indiceLinhaCarrinho =
                                                    index,
                                              );
                                              _carrinhoFocus.requestFocus();
                                            },
                                            contentPadding:
                                                const EdgeInsets.symmetric(
                                                  horizontal: 8,
                                                  vertical: 2,
                                                ),
                                            dense: true,
                                            visualDensity:
                                                VisualDensity.compact,
                                            title: Text(
                                              item.produto.nome,
                                              maxLines: 2,
                                              overflow: TextOverflow.ellipsis,
                                              style: theme.textTheme.bodyLarge,
                                            ),
                                            subtitle: Text(
                                              '${_rotuloPreco(item.precoTipo)} · ${_formatarMoeda(item.precoUnitario)} / un · subtotal ${_formatarMoeda(item.subtotal)}',
                                              maxLines: 2,
                                            ),
                                            trailing: Row(
                                              mainAxisSize: MainAxisSize.min,
                                              children: [
                                                IconButton(
                                                  tooltip: 'Diminuir',
                                                  visualDensity:
                                                      VisualDensity.compact,
                                                  style: IconButton.styleFrom(
                                                    backgroundColor: theme
                                                        .colorScheme
                                                        .surfaceContainerHighest,
                                                    tapTargetSize:
                                                        MaterialTapTargetSize
                                                            .shrinkWrap,
                                                    padding:
                                                        const EdgeInsets.all(6),
                                                  ),
                                                  icon: const Icon(
                                                    Icons.remove,
                                                    size: 20,
                                                  ),
                                                  onPressed: () =>
                                                      _alterarQuantidadeCarrinho(
                                                        index,
                                                        -1,
                                                      ),
                                                ),
                                                Padding(
                                                  padding:
                                                      const EdgeInsets.symmetric(
                                                        horizontal: 6,
                                                      ),
                                                  child: Text(
                                                    '${item.quantidade}',
                                                    style: theme
                                                        .textTheme
                                                        .titleMedium
                                                        ?.copyWith(
                                                          fontWeight:
                                                              FontWeight.w600,
                                                        ),
                                                  ),
                                                ),
                                                IconButton(
                                                  tooltip: 'Aumentar',
                                                  visualDensity:
                                                      VisualDensity.compact,
                                                  style: IconButton.styleFrom(
                                                    backgroundColor: theme
                                                        .colorScheme
                                                        .surfaceContainerHighest,
                                                    tapTargetSize:
                                                        MaterialTapTargetSize
                                                            .shrinkWrap,
                                                    padding:
                                                        const EdgeInsets.all(6),
                                                  ),
                                                  icon: const Icon(
                                                    Icons.add,
                                                    size: 20,
                                                  ),
                                                  onPressed: () =>
                                                      _alterarQuantidadeCarrinho(
                                                        index,
                                                        1,
                                                      ),
                                                ),
                                                IconButton(
                                                  tooltip: 'Remover item',
                                                  visualDensity:
                                                      VisualDensity.compact,
                                                  style: IconButton.styleFrom(
                                                    foregroundColor:
                                                        theme.colorScheme.error,
                                                    tapTargetSize:
                                                        MaterialTapTargetSize
                                                            .shrinkWrap,
                                                    padding:
                                                        const EdgeInsets.all(6),
                                                  ),
                                                  icon: const Icon(
                                                    Icons.delete_outline,
                                                    size: 22,
                                                  ),
                                                  onPressed: () =>
                                                      _removerItemCarrinho(
                                                        index,
                                                      ),
                                                ),
                                              ],
                                            ),
                                          ),
                                        );
                                      },
                                    ),
                                  ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            'Subtotal produtos: ${_formatarMoeda(_totalOrcamento)}',
                            style: Theme.of(context).textTheme.bodyLarge,
                          ),
                          const SizedBox(height: 2),
                          Text(
                            'Frete: ${_formatarMoeda(_valorFreteAtual)}',
                            style: Theme.of(context).textTheme.bodyLarge,
                          ),
                          const SizedBox(height: 2),
                          Text(
                            'Total geral: ${_formatarMoeda(_totalGeralComFrete)}',
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                          const SizedBox(height: 6),
                          InkWell(
                            onTap: _abrirSeletorClienteNoPdv,
                            borderRadius: BorderRadius.circular(12),
                            child: InputDecorator(
                              decoration: const InputDecoration(
                                labelText: 'Cliente (opcional)',
                                suffixIcon: Icon(Icons.search),
                              ),
                              child: Text(_rotuloClienteSelecionadoPdV()),
                            ),
                          ),
                          const SizedBox(height: 8),
                          DropdownButtonFormField<int?>(
                            focusNode: _focusVendedorPdV,
                            initialValue: _vendedorSelecionadoId,
                            decoration: const InputDecoration(
                              labelText: 'Vendedor (opcional)',
                            ),
                            items: [
                              const DropdownMenuItem<int?>(
                                value: null,
                                child: Text('Sem vendedor'),
                              ),
                              ..._vendedoresAtivos.map(
                                (v) => DropdownMenuItem<int?>(
                                  value: v.id,
                                  child: Text(_rotuloItemVendedorPdV(v)),
                                ),
                              ),
                            ],
                            onChanged: (value) {
                              setState(() => _vendedorSelecionadoId = value);
                            },
                          ),
                          const SizedBox(height: 8),
                          DropdownButtonFormField<String>(
                            focusNode: _focusPagamentoPdV,
                            initialValue: _formaPagamentoSelecionada,
                            decoration: const InputDecoration(
                              labelText: 'Forma de pagamento',
                            ),
                            items: const [
                              DropdownMenuItem(
                                value: 'dinheiro',
                                child: Text('Dinheiro'),
                              ),
                              DropdownMenuItem(
                                value: 'pix',
                                child: Text('PIX'),
                              ),
                              DropdownMenuItem(
                                value: 'cartao_credito',
                                child: Text('Cartao de credito'),
                              ),
                              DropdownMenuItem(
                                value: 'cartao_debito',
                                child: Text('Cartao de debito'),
                              ),
                              DropdownMenuItem(
                                value: 'fiado',
                                child: Text('Fiado'),
                              ),
                              DropdownMenuItem(
                                value: 'transferencia',
                                child: Text('Transferencia'),
                              ),
                            ],
                            onChanged: (value) {
                              if (value == null) {
                                return;
                              }
                              setState(() {
                                _formaPagamentoSelecionada = value;
                                if (_formaPagamentoSelecionada !=
                                    'cartao_credito') {
                                  _parcelasSelecionadas = 1;
                                }
                              });
                            },
                          ),
                          const SizedBox(height: 4),
                          ExpansionTile(
                            tilePadding: EdgeInsets.zero,
                            childrenPadding: EdgeInsets.zero,
                            initiallyExpanded: _mostrarMaisOpcoesCheckout,
                            onExpansionChanged: (value) {
                              setState(() {
                                _mostrarMaisOpcoesCheckout = value;
                              });
                            },
                            title: const Text('Mais opcoes (entrega, frete e parcelas)'),
                            children: [
                              const SizedBox(height: 4),
                              DropdownButtonFormField<String>(
                                focusNode: _focusEntregaPdV,
                                initialValue: _tipoEntregaSelecionada,
                                decoration: const InputDecoration(
                                  labelText: 'Tipo de entrega',
                                ),
                                items: const [
                                  DropdownMenuItem(
                                    value: 'retirada',
                                    child: Text('Retirada na loja'),
                                  ),
                                  DropdownMenuItem(
                                    value: 'entrega_loja',
                                    child: Text('Entrega da loja'),
                                  ),
                                ],
                                onChanged: (value) {
                                  if (value == null) return;
                                  setState(() {
                                    _tipoEntregaSelecionada = value;
                                    if (_tipoEntregaSelecionada != 'entrega_loja') {
                                      _prioridadeEntregaSelecionada = 'normal';
                                      _janelaEntregaSelecionada = 'nao_definida';
                                      _dataEntregaMarcada = null;
                                      _valorFreteController.clear();
                                      _enderecoEntregaController.clear();
                                      _observacaoEntregaController.clear();
                                    }
                                  });
                                },
                              ),
                              if (_tipoEntregaSelecionada == 'entrega_loja') ...[
                                const SizedBox(height: 8),
                                Row(
                                  children: [
                                    Expanded(
                                      child: DropdownButtonFormField<String>(
                                        initialValue: _prioridadeEntregaSelecionada,
                                        decoration: const InputDecoration(
                                          labelText: 'Prioridade da entrega',
                                        ),
                                        items: const [
                                          DropdownMenuItem(
                                            value: 'normal',
                                            child: Text('Normal'),
                                          ),
                                          DropdownMenuItem(
                                            value: 'urgente',
                                            child: Text('Urgente'),
                                          ),
                                          DropdownMenuItem(
                                            value: 'agendada',
                                            child: Text('Agendada'),
                                          ),
                                        ],
                                        onChanged: (value) {
                                          if (value == null) return;
                                          setState(() {
                                            _prioridadeEntregaSelecionada = value;
                                            if (_prioridadeEntregaSelecionada ==
                                                    'agendada' &&
                                                _janelaEntregaSelecionada ==
                                                    'nao_definida') {
                                              _janelaEntregaSelecionada = 'manha';
                                            }
                                          });
                                        },
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: DropdownButtonFormField<String>(
                                        initialValue: _janelaEntregaSelecionada,
                                        decoration: const InputDecoration(
                                          labelText: 'Janela',
                                        ),
                                        items: const [
                                          DropdownMenuItem(
                                            value: 'nao_definida',
                                            child: Text('Nao definida'),
                                          ),
                                          DropdownMenuItem(
                                            value: 'manha',
                                            child: Text('Manha'),
                                          ),
                                          DropdownMenuItem(
                                            value: 'tarde',
                                            child: Text('Tarde'),
                                          ),
                                        ],
                                        onChanged: (value) {
                                          if (value == null) return;
                                          setState(() {
                                            _janelaEntregaSelecionada = value;
                                          });
                                        },
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 8),
                                SizedBox(
                                  width: double.infinity,
                                  child: OutlinedButton.icon(
                                    onPressed: () async {
                                      final agora = DateTime.now();
                                      final inicial = _dataEntregaMarcada ?? agora;
                                      final escolhido = await showDatePicker(
                                        context: context,
                                        initialDate: inicial,
                                        firstDate: DateTime(
                                          agora.year,
                                          agora.month,
                                          agora.day,
                                        ),
                                        lastDate: DateTime(
                                          agora.year + 3,
                                          12,
                                          31,
                                        ),
                                      );
                                      if (!mounted || escolhido == null) return;
                                      setState(() {
                                        _dataEntregaMarcada = escolhido;
                                      });
                                    },
                                    icon: const Icon(Icons.event_outlined),
                                    label: Text(
                                      _dataEntregaMarcada == null
                                          ? 'Definir data da entrega'
                                          : 'Data da entrega: ${DateFormat('dd/MM/yyyy').format(_dataEntregaMarcada!)}',
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 8),
                                Container(
                                  width: double.infinity,
                                  padding: const EdgeInsets.all(10),
                                  decoration: BoxDecoration(
                                    color: Theme.of(context)
                                        .colorScheme
                                        .surfaceContainerLowest,
                                    borderRadius: BorderRadius.circular(8),
                                    border: Border.all(
                                      color: Theme.of(
                                        context,
                                      ).colorScheme.outlineVariant,
                                    ),
                                  ),
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        'Entrega configurada',
                                        style: Theme.of(context).textTheme.labelLarge,
                                      ),
                                      const SizedBox(height: 4),
                                      Text(
                                        _resumoEntrega(),
                                        style: Theme.of(context).textTheme.bodySmall,
                                      ),
                                      const SizedBox(height: 8),
                                      Align(
                                        alignment: Alignment.centerLeft,
                                        child: OutlinedButton.icon(
                                          onPressed: () async {
                                            final cliente = _clienteSelecionado();
                                            if (cliente == null) {
                                              ScaffoldMessenger.of(
                                                context,
                                              ).showSnackBar(
                                                const SnackBar(
                                                  content: Text(
                                                    'Selecione um cliente para editar a entrega.',
                                                  ),
                                                ),
                                              );
                                              return;
                                            }
                                            final entrega =
                                                await _abrirDialogEntregaCliente(
                                                  cliente: cliente,
                                                );
                                            if (!mounted || entrega == null) return;
                                            setState(() {
                                              _tipoEntregaSelecionada =
                                                  'entrega_loja';
                                              _dataEntregaMarcada ??=
                                                  DateTime.now();
                                              _valorFreteController.text =
                                                  entrega.valorFrete;
                                              _enderecoEntregaController.text =
                                                  entrega.endereco;
                                              _observacaoEntregaController.text =
                                                  entrega.observacao;
                                            });
                                          },
                                          icon: const Icon(Icons.edit_outlined),
                                          label: const Text(
                                            'Editar dados da entrega',
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                              const SizedBox(height: 8),
                              DropdownButtonFormField<int>(
                                focusNode: _focusParcelasPdV,
                                initialValue: _parcelasSelecionadas,
                                decoration: const InputDecoration(
                                  labelText: 'Parcelas',
                                ),
                                items: List.generate(
                                  12,
                                  (index) => DropdownMenuItem(
                                    value: index + 1,
                                    child: Text(_rotuloParcela(index + 1)),
                                  ),
                                ),
                                onChanged:
                                    _formaPagamentoSelecionada == 'cartao_credito'
                                    ? (value) {
                                        if (value != null) {
                                          setState(() {
                                            _parcelasSelecionadas = value;
                                          });
                                        }
                                      }
                                    : null,
                              ),
                              if (_formaPagamentoSelecionada ==
                                  'cartao_credito') ...[
                                const SizedBox(height: 6),
                                Text(
                                  'Selecionado: ${_rotuloParcela(_parcelasSelecionadas)}',
                                ),
                              ],
                            ],
                          ),
                          if (_orcamentoEmEdicaoId != null) ...[
                            const SizedBox(height: 8),
                            Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    'Editando orcamento #${_orcamentoEmEdicaoNumero ?? '-'}',
                                    style: Theme.of(context).textTheme.bodySmall
                                        ?.copyWith(fontWeight: FontWeight.w600),
                                  ),
                                ),
                                TextButton(
                                  onPressed: () {
                                    setState(() {
                                      _orcamentoEmEdicaoId = null;
                                      _orcamentoEmEdicaoNumero = null;
                                    });
                                  },
                                  child: const Text('Cancelar edicao'),
                                ),
                              ],
                            ),
                          ],
                          const SizedBox(height: 8),
                          SizedBox(
                            width: double.infinity,
                            child: Focus(
                              focusNode: _focusSalvarOrcamentoPdV,
                              child: ElevatedButton.icon(
                                onPressed: _salvarOrcamento,
                                icon: const Icon(Icons.save_outlined),
                                label: Text(
                                  _orcamentoEmEdicaoId != null
                                      ? 'Atualizar orcamento (F10 · Ctrl+S)'
                                      : 'Salvar orcamento (F10 · Ctrl+S)',
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
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

class _AdicionarOrcamentoResult {
  const _AdicionarOrcamentoResult({
    required this.quantidade,
    required this.precoTipo,
  });
  final int quantidade;
  final String precoTipo;
}

class _EntregaDialogResult {
  const _EntregaDialogResult({
    required this.valorFrete,
    required this.endereco,
    required this.observacao,
  });

  final String valorFrete;
  final String endereco;
  final String observacao;
}

class _EntregaClienteDialog extends StatefulWidget {
  const _EntregaClienteDialog({
    required this.clienteNome,
    required this.valorFreteInicial,
    required this.enderecoInicial,
    required this.observacaoInicial,
  });

  final String clienteNome;
  final String valorFreteInicial;
  final String enderecoInicial;
  final String observacaoInicial;

  @override
  State<_EntregaClienteDialog> createState() => _EntregaClienteDialogState();
}

class _EntregaClienteDialogState extends State<_EntregaClienteDialog> {
  late final TextEditingController _freteController;
  late final TextEditingController _enderecoController;
  late final TextEditingController _obsController;

  @override
  void initState() {
    super.initState();
    _freteController = TextEditingController(text: widget.valorFreteInicial);
    _enderecoController = TextEditingController(text: widget.enderecoInicial);
    _obsController = TextEditingController(text: widget.observacaoInicial);
  }

  @override
  void dispose() {
    _freteController.dispose();
    _enderecoController.dispose();
    _obsController.dispose();
    super.dispose();
  }

  void _confirmar() {
    if (_enderecoController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Informe o endereco de entrega para continuar.'),
        ),
      );
      return;
    }
    Navigator.of(context).pop(
      _EntregaDialogResult(
        valorFrete: _freteController.text.trim(),
        endereco: _enderecoController.text.trim(),
        observacao: _obsController.text.trim(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return CallbackShortcuts(
      bindings: <ShortcutActivator, VoidCallback>{
        const SingleActivator(LogicalKeyboardKey.escape): () =>
            Navigator.of(context).pop(),
        const SingleActivator(LogicalKeyboardKey.enter): _confirmar,
        const SingleActivator(LogicalKeyboardKey.numpadEnter): _confirmar,
      },
      child: AlertDialog(
        title: Text('Entrega de ${widget.clienteNome}'),
        content: SizedBox(
          width: 460,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: _freteController,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                decoration: const InputDecoration(
                  labelText: 'Valor do frete',
                  hintText: 'Ex.: 35,00',
                ),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _enderecoController,
                decoration: const InputDecoration(
                  labelText: 'Endereco de entrega',
                ),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _obsController,
                maxLines: 2,
                decoration: const InputDecoration(
                  labelText: 'Observacoes da entrega',
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancelar (Esc)'),
          ),
          ElevatedButton(
            onPressed: _confirmar,
            child: const Text('Confirmar (Enter)'),
          ),
        ],
      ),
    );
  }
}

class _AdicionarAoOrcamentoDialog extends StatefulWidget {
  const _AdicionarAoOrcamentoDialog({
    required this.produto,
    required this.precoTipoInicial,
    required this.precoUnitarioDe,
    required this.formatarMoeda,
  });

  final Produto produto;
  final String precoTipoInicial;
  final double Function(String precoTipo) precoUnitarioDe;
  final String Function(double) formatarMoeda;

  @override
  State<_AdicionarAoOrcamentoDialog> createState() =>
      _AdicionarAoOrcamentoDialogState();
}

class _AdicionarAoOrcamentoDialogState
    extends State<_AdicionarAoOrcamentoDialog> {
  late String _precoTipo;
  late final TextEditingController _qtdController;
  final _qtdFocus = FocusNode(debugLabel: 'pdvDialogQtd');

  @override
  void initState() {
    super.initState();
    _precoTipo = widget.precoTipoInicial;
    _qtdController = TextEditingController(text: '1');
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _qtdFocus.requestFocus();
        _qtdController.selection = TextSelection(
          baseOffset: 0,
          extentOffset: _qtdController.text.length,
        );
      }
    });
  }

  @override
  void dispose() {
    _qtdController.dispose();
    _qtdFocus.dispose();
    super.dispose();
  }

  void _confirmar() {
    final q = int.tryParse(_qtdController.text.trim());
    if (q == null || q <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Informe uma quantidade maior que zero.')),
      );
      return;
    }
    Navigator.of(
      context,
    ).pop(_AdicionarOrcamentoResult(quantidade: q, precoTipo: _precoTipo));
  }

  @override
  Widget build(BuildContext context) {
    final precoUnit = widget.precoUnitarioDe(_precoTipo);
    return AlertDialog(
      title: Text('Adicionar: ${widget.produto.nome}'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          DropdownButtonFormField<String>(
            key: ValueKey(_precoTipo),
            initialValue: _precoTipo,
            decoration: const InputDecoration(labelText: 'Tipo de preco'),
            items: const [
              DropdownMenuItem(value: 'preco1', child: Text('A Prazo')),
              DropdownMenuItem(value: 'preco2', child: Text('À Vista')),
              DropdownMenuItem(value: 'preco3', child: Text('Atacado')),
            ],
            onChanged: (value) {
              if (value != null) {
                setState(() => _precoTipo = value);
              }
            },
          ),
          const SizedBox(height: 8),
          TextFormField(
            controller: _qtdController,
            focusNode: _qtdFocus,
            autofocus: true,
            decoration: const InputDecoration(labelText: 'Quantidade'),
            keyboardType: TextInputType.number,
            textInputAction: TextInputAction.done,
            onFieldSubmitted: (_) => _confirmar(),
          ),
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerLeft,
            child: Text('Preco: ${widget.formatarMoeda(precoUnit)}'),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancelar'),
        ),
        ElevatedButton(onPressed: _confirmar, child: const Text('Adicionar')),
      ],
    );
  }
}

/// Atalho para sair da pesquisa com seta para baixo e focar na lista de produtos.
class IrParaListaProdutosIntent extends Intent {
  const IrParaListaProdutosIntent();
}

/// F1/F2/F3 alternam qual preco usa adicao rapida e Enter na lista.
class SelecionarPrecoListaIntent extends Intent {
  const SelecionarPrecoListaIntent(this.precoTipo);
  final String precoTipo;
}

class PdvRecarregarProdutosIntent extends Intent {
  const PdvRecarregarProdutosIntent();
}

class PdvFocarCarrinhoIntent extends Intent {
  const PdvFocarCarrinhoIntent();
}

class PdvCheckoutProximoIntent extends Intent {
  const PdvCheckoutProximoIntent();
}

class PdvCheckoutAnteriorIntent extends Intent {
  const PdvCheckoutAnteriorIntent();
}

class PdvSalvarOrcamentoIntent extends Intent {
  const PdvSalvarOrcamentoIntent();
}

class PdvLerOrcamentoIntent extends Intent {
  const PdvLerOrcamentoIntent();
}

class PdvLimparPesquisaIntent extends Intent {
  const PdvLimparPesquisaIntent();
}

class _PesquisaComando {
  const _PesquisaComando({
    required this.termoBusca,
    this.quantidadeDireta,
    this.adicaoDireta = false,
  });

  final String termoBusca;
  final int? quantidadeDireta;
  final bool adicaoDireta;

  static _PesquisaComando parse(String textoOriginal) {
    final texto = textoOriginal.trim();
    if (texto.isEmpty) {
      return const _PesquisaComando(termoBusca: '');
    }

    final addDireto = RegExp(r'^\s*(.+?)\s*\+\s*$').firstMatch(texto);
    if (addDireto != null) {
      return _PesquisaComando(
        termoBusca: addDireto.group(1)!.trim(),
        adicaoDireta: true,
      );
    }

    final quantidadeDireta = RegExp(r'^\s*(\d{1,3})\s+(.+)$').firstMatch(texto);
    if (quantidadeDireta != null) {
      final qtd = int.tryParse(quantidadeDireta.group(1)!);
      final termo = quantidadeDireta.group(2)!.trim();
      if (qtd != null && qtd > 0 && termo.isNotEmpty) {
        return _PesquisaComando(termoBusca: termo, quantidadeDireta: qtd);
      }
    }

    return _PesquisaComando(termoBusca: texto);
  }
}

class _OrcamentoItemDraft {
  _OrcamentoItemDraft({
    required this.produto,
    required this.quantidade,
    required this.precoTipo,
    required this.precoUnitario,
  });

  final Produto produto;
  int quantidade;
  final String precoTipo;
  final double precoUnitario;

  double get subtotal => quantidade * precoUnitario;
}
