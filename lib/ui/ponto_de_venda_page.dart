import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'dart:io';
import 'dart:typed_data';
import 'package:file_picker/file_picker.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import '../data/app_config_repository.dart';
import '../data/cliente_repository.dart';
import '../data/produto_repository.dart';
import '../data/venda_repository.dart';
import '../model/cliente.dart';
import '../model/produto.dart';
import '../model/venda.dart';
import 'produto_detalhe_venda_page.dart';

class PontoDeVendaPage extends StatefulWidget {
  const PontoDeVendaPage({
    super.key,
    required this.produtoRepository,
    required this.clienteRepository,
    required this.vendaRepository,
  });

  final ProdutoRepository produtoRepository;
  final ClienteRepository clienteRepository;
  final VendaRepository vendaRepository;

  @override
  State<PontoDeVendaPage> createState() => _PontoDeVendaPageState();
}

class _PontoDeVendaPageState extends State<PontoDeVendaPage> {
  static const int _validadeOrcamentoDias = 7;
  final _pesquisaController = TextEditingController();
  final _valorFreteController = TextEditingController();
  final _enderecoEntregaController = TextEditingController();
  final _observacaoEntregaController = TextEditingController();
  final _configRepository = AppConfigRepository();
  final NumberFormat _currency = NumberFormat('#,##0.00', 'pt_BR');
  List<Produto> _produtos = [];
  List<Cliente> _clientes = [];
  final List<_OrcamentoItemDraft> _carrinho = [];
  String _formaPagamentoSelecionada = 'dinheiro';
  int _parcelasSelecionadas = 1;
  int? _clienteSelecionadoId;
  String _tipoEntregaSelecionada = 'retirada';

  @override
  void initState() {
    super.initState();
    _carregarDadosIniciais();
  }

  @override
  void dispose() {
    _pesquisaController.dispose();
    _valorFreteController.dispose();
    _enderecoEntregaController.dispose();
    _observacaoEntregaController.dispose();
    super.dispose();
  }

  void _pesquisar() {
    setState(() {
      _produtos = widget.produtoRepository.pesquisar(_pesquisaController.text);
    });
  }

  void _carregarDadosIniciais() {
    setState(() {
      _produtos = widget.produtoRepository.listarTodos();
      _clientes = widget.clienteRepository.listarTodos().where((c) => c.ativo).toList();
    });
  }

  String _formatarMoeda(double valor) => 'R\$ ${_currency.format(valor)}';

  double _parseValorMonetario(String valor) {
    final normalizado = valor.trim().replaceAll('.', '').replaceAll(',', '.');
    if (normalizado.isEmpty) return 0;
    return double.tryParse(normalizado) ?? 0;
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
        return 'Preco 2';
      case 'preco3':
        return 'Preco 3';
      case 'preco1':
      default:
        return 'Preco 1';
    }
  }

  Future<void> _adicionarAoOrcamento(Produto produto) async {
    int quantidade = 1;
    String precoTipo = 'preco1';

    final confirmado = await showDialog<bool>(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            final precoEscolhido = _precoPorTipo(produto, precoTipo);
            return AlertDialog(
              title: Text('Adicionar: ${produto.nome}'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  DropdownButtonFormField<String>(
                    initialValue: precoTipo,
                    decoration: const InputDecoration(labelText: 'Tipo de preco'),
                    items: const [
                      DropdownMenuItem(value: 'preco1', child: Text('Preco 1')),
                      DropdownMenuItem(value: 'preco2', child: Text('Preco 2')),
                      DropdownMenuItem(value: 'preco3', child: Text('Preco 3')),
                    ],
                    onChanged: (value) {
                      if (value != null) {
                        setDialogState(() => precoTipo = value);
                      }
                    },
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: TextFormField(
                          initialValue: quantidade.toString(),
                          decoration: const InputDecoration(labelText: 'Quantidade'),
                          keyboardType: TextInputType.number,
                          onChanged: (value) {
                            quantidade = int.tryParse(value) ?? 1;
                          },
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Text('Preco: ${_formatarMoeda(precoEscolhido)}'),
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context, false),
                  child: const Text('Cancelar'),
                ),
                ElevatedButton(
                  onPressed: () => Navigator.pop(context, true),
                  child: const Text('Adicionar'),
                ),
              ],
            );
          },
        );
      },
    );

    if (confirmado != true) {
      return;
    }
    if (!mounted) {
      return;
    }
    if (quantidade <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Quantidade deve ser maior que zero.')),
      );
      return;
    }

    setState(() {
      _carrinho.add(
        _OrcamentoItemDraft(
          produto: produto,
          quantidade: quantidade,
          precoTipo: precoTipo,
          precoUnitario: _precoPorTipo(produto, precoTipo),
        ),
      );
    });
  }

  Future<void> _salvarOrcamento() async {
    if (_carrinho.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Adicione ao menos um item no orcamento.')),
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
          const SnackBar(content: Text('Informe o endereco para entrega da loja.')),
        );
        return;
      }
      if (valorFrete < 0) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Valor do frete nao pode ser negativo.')),
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
      final orcamentoId = widget.vendaRepository.registrarOrcamento(
        itens,
        pagamento: DadosPagamentoOrcamento(
          formaPagamento: _formaPagamentoSelecionada,
          quantidadeParcelas: _formaPagamentoSelecionada == 'cartao_credito'
              ? _parcelasSelecionadas
              : 1,
        ),
        entrega: DadosEntregaOrcamento(
          tipoEntrega: _tipoEntregaSelecionada,
          valorFrete: valorFrete,
          enderecoEntrega: _enderecoEntregaController.text.trim(),
          observacaoEntrega: _observacaoEntregaController.text.trim(),
        ),
        clienteId: _clienteSelecionadoId,
      );
      final vendaSalva = widget.vendaRepository.obterPorId(orcamentoId);
      setState(() {
        _carrinho.clear();
        _formaPagamentoSelecionada = 'dinheiro';
        _parcelasSelecionadas = 1;
        _clienteSelecionadoId = null;
        _tipoEntregaSelecionada = 'retirada';
        _valorFreteController.clear();
        _enderecoEntregaController.clear();
        _observacaoEntregaController.clear();
      });
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Orcamento #$orcamentoId salvo para o caixa.')),
      );
      if (vendaSalva != null && mounted) {
        await _mostrarAcoesPdfOrcamento(vendaSalva);
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Erro ao salvar orcamento: $e')),
      );
    }
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

  Future<Uint8List> _gerarOrcamentoPdfBytes(Venda venda) async {
    final cliente = _clienteDaVenda(venda);
    final empresa = await _configRepository.carregarEmpresaConfig();
    final logoBytes = empresa.logoPath.trim().isNotEmpty
        ? await File(empresa.logoPath).readAsBytes().catchError((_) => Uint8List(0))
        : Uint8List(0);
    final doc = pw.Document();
    final dataHora = DateFormat('dd/MM/yyyy HH:mm').format(venda.data);
    final validade = venda.data.add(Duration(days: _validadeOrcamentoDias));
    final validadeFmt = DateFormat('dd/MM/yyyy').format(validade);
    final subtotalProdutos = (venda.total - venda.valorFrete).clamp(0, double.infinity).toDouble();
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
                  style: pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold),
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
                  child: pw.Text('Tel: ${empresa.telefone}', style: const pw.TextStyle(fontSize: 8)),
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
              pw.Text('Numero: #${venda.numeroOrcamento}', style: const pw.TextStyle(fontSize: 9)),
              pw.Text('Data: $dataHora', style: const pw.TextStyle(fontSize: 9)),
              pw.Text('Cliente: ${cliente?.nomeRazao ?? 'Sem cliente'}', style: const pw.TextStyle(fontSize: 9)),
              if ((cliente?.documento.trim().isNotEmpty ?? false))
                pw.Text('Documento: ${cliente!.documento}', style: const pw.TextStyle(fontSize: 9)),
              if ((cliente?.telefone.trim().isNotEmpty ?? false))
                pw.Text('Telefone: ${cliente!.telefone}', style: const pw.TextStyle(fontSize: 9)),
              pw.Text(
                'Validade do orcamento: $validadeFmt ($_validadeOrcamentoDias dias)',
                style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold),
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
                pw.Text('Endereco: ${venda.enderecoEntrega}', style: const pw.TextStyle(fontSize: 9)),
              if (venda.observacaoEntrega.trim().isNotEmpty)
                pw.Text('Obs: ${venda.observacaoEntrega}', style: const pw.TextStyle(fontSize: 9)),
              pw.SizedBox(height: 8),
              pw.Text('ITENS', style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold)),
              pw.SizedBox(height: 4),
              ...venda.itens.map(
                (item) => pw.Padding(
                  padding: const pw.EdgeInsets.only(bottom: 4),
                  child: pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      pw.Text(item.nomeProduto, style: const pw.TextStyle(fontSize: 9)),
                      pw.Text(
                        '${item.quantidade} x ${_formatarMoeda(item.precoUnitario)} = ${_formatarMoeda(item.subtotal)}',
                        style: const pw.TextStyle(fontSize: 8),
                      ),
                    ],
                  ),
                ),
              ),
              pw.Divider(),
              pw.Text('Subtotal: ${_formatarMoeda(subtotalProdutos)}', style: const pw.TextStyle(fontSize: 9)),
              pw.Text('Frete: ${_formatarMoeda(venda.valorFrete)}', style: const pw.TextStyle(fontSize: 9)),
              pw.Text(
                'Total: ${_formatarMoeda(venda.total)}',
                style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold),
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
    final normalizedPath =
        selectedPath.toLowerCase().endsWith('.pdf') ? selectedPath : '$selectedPath.pdf';
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
        return AlertDialog(
          title: const Text('Orcamento salvo'),
          content: const Text('Deseja imprimir o orcamento ou mandar em PDF?'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, 'fechar'),
              child: const Text('Fechar'),
            ),
            OutlinedButton.icon(
              onPressed: () => Navigator.pop(context, 'pdf'),
              icon: const Icon(Icons.picture_as_pdf_outlined),
              label: const Text('Mandar em PDF'),
            ),
            OutlinedButton.icon(
              onPressed: () => Navigator.pop(context, 'direto'),
              icon: const Icon(Icons.print),
              label: const Text('Impressao direta'),
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
            const SnackBar(content: Text('Impressora padrao nao configurada/encontrada.')),
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
        initialDirectory: config.pastaPadraoPdf.trim().isEmpty ? null : config.pastaPadraoPdf.trim(),
      );
      if (!mounted || path == null) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('PDF do orcamento salvo em: $path')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Nao foi possivel gerar/imprimir orcamento: $e')),
      );
    }
  }

  double get _totalOrcamento =>
      _carrinho.fold(0, (total, item) => total + item.subtotal);

  double get _valorFreteAtual =>
      _tipoEntregaSelecionada == 'entrega_loja'
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
    return Scaffold(
      appBar: AppBar(title: const Text('Ponto de Venda')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              flex: 3,
              child: Column(
                children: [
                  TextField(
                    controller: _pesquisaController,
                    decoration: InputDecoration(
                      labelText: 'Pesquisar produto para venda',
                      suffixIcon: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            tooltip: 'Limpar busca',
                            onPressed: () {
                              _pesquisaController.clear();
                              _carregarDadosIniciais();
                            },
                            icon: const Icon(Icons.clear),
                          ),
                          IconButton(
                            tooltip: 'Pesquisar',
                            onPressed: _pesquisar,
                            icon: const Icon(Icons.search),
                          ),
                          IconButton(
                            tooltip: 'Recarregar produtos',
                            onPressed: _carregarDadosIniciais,
                            icon: const Icon(Icons.refresh),
                          ),
                        ],
                      ),
                    ),
                    onSubmitted: (_) => _pesquisar(),
                  ),
                  const SizedBox(height: 6),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      'Produtos carregados: ${_produtos.length}',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ),
                  const SizedBox(height: 12),
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
                        : ListView.builder(
                            itemCount: _produtos.length,
                            itemBuilder: (context, index) {
                              final item = _produtos[index];
                              final descricaoCurta = item.descricao.trim().isEmpty
                                  ? 'Sem descricao tecnica cadastrada.'
                                  : item.descricao.trim();
                              return Card(
                                child: Padding(
                                  padding: const EdgeInsets.all(12),
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        item.nome,
                                        style: Theme.of(context).textTheme.titleSmall,
                                      ),
                                      const SizedBox(height: 6),
                                      Text(
                                        'SKU: ${item.codigoInterno} | Estoque: ${item.estoque}',
                                      ),
                                      Text(
                                        'P1: ${_formatarMoeda(_precoPorTipo(item, 'preco1'))} | '
                                        'P2: ${_formatarMoeda(_precoPorTipo(item, 'preco2'))} | '
                                        'P3: ${_formatarMoeda(_precoPorTipo(item, 'preco3'))}',
                                      ),
                                      Text(
                                        'Descricao: ${descricaoCurta.length > 70 ? '${descricaoCurta.substring(0, 70)}...' : descricaoCurta}',
                                      ),
                                      const SizedBox(height: 8),
                                      Row(
                                        mainAxisAlignment: MainAxisAlignment.end,
                                        children: [
                                          OutlinedButton(
                                            onPressed: () {
                                              Navigator.push(
                                                context,
                                                MaterialPageRoute(
                                                  builder: (_) =>
                                                      ProdutoDetalheVendaPage(produto: item),
                                                ),
                                              );
                                            },
                                            child: const Text('Detalhes'),
                                          ),
                                          const SizedBox(width: 8),
                                          ElevatedButton(
                                            onPressed: () => _adicionarAoOrcamento(item),
                                            child: const Text('Adicionar'),
                                          ),
                                        ],
                                      ),
                                    ],
                                  ),
                                ),
                              );
                            },
                          ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              flex: 2,
              child: Card(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Orcamento em atendimento',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(height: 8),
                      Expanded(
                        child: _carrinho.isEmpty
                            ? const Center(child: Text('Nenhum item no orcamento.'))
                            : ListView.builder(
                                itemCount: _carrinho.length,
                                itemBuilder: (context, index) {
                                  final item = _carrinho[index];
                                  return ListTile(
                                    dense: true,
                                    title: Text(item.produto.nome),
                                    subtitle: Text(
                                      '${_rotuloPreco(item.precoTipo)} | Qtd: ${item.quantidade} | Unit: ${_formatarMoeda(item.precoUnitario)}',
                                    ),
                                    trailing: IconButton(
                                      tooltip: 'Remover',
                                      onPressed: () {
                                        setState(() {
                                          _carrinho.removeAt(index);
                                        });
                                      },
                                      icon: const Icon(Icons.delete_outline),
                                    ),
                                  );
                                },
                              ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Subtotal produtos: ${_formatarMoeda(_totalOrcamento)}',
                        style: Theme.of(context).textTheme.bodyLarge,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Frete: ${_formatarMoeda(_valorFreteAtual)}',
                        style: Theme.of(context).textTheme.bodyLarge,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Total geral: ${_formatarMoeda(_totalGeralComFrete)}',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(height: 8),
                      DropdownButtonFormField<int?>(
                        initialValue: _clienteSelecionadoId,
                        decoration: const InputDecoration(
                          labelText: 'Cliente (opcional)',
                        ),
                        items: [
                          const DropdownMenuItem<int?>(
                            value: null,
                            child: Text('Sem cliente'),
                          ),
                          ..._clientes.map(
                            (c) => DropdownMenuItem<int?>(
                              value: c.id,
                              child: Text(c.nomeRazao),
                            ),
                          ),
                        ],
                        onChanged: (value) {
                          setState(() {
                            _clienteSelecionadoId = value;
                          });
                        },
                      ),
                      const SizedBox(height: 8),
                      DropdownButtonFormField<String>(
                        initialValue: _formaPagamentoSelecionada,
                        decoration: const InputDecoration(labelText: 'Forma de pagamento'),
                        items: const [
                          DropdownMenuItem(value: 'dinheiro', child: Text('Dinheiro')),
                          DropdownMenuItem(value: 'pix', child: Text('PIX')),
                          DropdownMenuItem(
                            value: 'cartao_credito',
                            child: Text('Cartao de credito'),
                          ),
                          DropdownMenuItem(
                            value: 'cartao_debito',
                            child: Text('Cartao de debito'),
                          ),
                          DropdownMenuItem(value: 'fiado', child: Text('Fiado')),
                          DropdownMenuItem(value: 'transferencia', child: Text('Transferencia')),
                        ],
                        onChanged: (value) {
                          if (value == null) {
                            return;
                          }
                          setState(() {
                            _formaPagamentoSelecionada = value;
                            if (_formaPagamentoSelecionada != 'cartao_credito') {
                              _parcelasSelecionadas = 1;
                            }
                          });
                        },
                      ),
                      const SizedBox(height: 8),
                      DropdownButtonFormField<String>(
                        initialValue: _tipoEntregaSelecionada,
                        decoration: const InputDecoration(labelText: 'Tipo de entrega'),
                        items: const [
                          DropdownMenuItem(value: 'retirada', child: Text('Retirada na loja')),
                          DropdownMenuItem(value: 'entrega_loja', child: Text('Entrega da loja')),
                        ],
                        onChanged: (value) {
                          if (value == null) return;
                          setState(() {
                            _tipoEntregaSelecionada = value;
                            if (_tipoEntregaSelecionada != 'entrega_loja') {
                              _valorFreteController.clear();
                              _enderecoEntregaController.clear();
                              _observacaoEntregaController.clear();
                            }
                          });
                        },
                      ),
                      if (_tipoEntregaSelecionada == 'entrega_loja') ...[
                        const SizedBox(height: 8),
                        TextField(
                          controller: _valorFreteController,
                          keyboardType: const TextInputType.numberWithOptions(decimal: true),
                          decoration: const InputDecoration(
                            labelText: 'Valor do frete',
                            hintText: 'Ex.: 35,00',
                          ),
                          onChanged: (_) => setState(() {}),
                        ),
                        const SizedBox(height: 8),
                        TextField(
                          controller: _enderecoEntregaController,
                          decoration: const InputDecoration(
                            labelText: 'Endereco de entrega',
                          ),
                        ),
                        const SizedBox(height: 8),
                        TextField(
                          controller: _observacaoEntregaController,
                          maxLines: 2,
                          decoration: const InputDecoration(
                            labelText: 'Observacoes da entrega',
                          ),
                        ),
                      ],
                      const SizedBox(height: 8),
                      DropdownButtonFormField<int>(
                        initialValue: _parcelasSelecionadas,
                        decoration: const InputDecoration(labelText: 'Parcelas'),
                        items: List.generate(
                          12,
                          (index) => DropdownMenuItem(
                            value: index + 1,
                            child: Text(_rotuloParcela(index + 1)),
                          ),
                        ),
                        onChanged: _formaPagamentoSelecionada == 'cartao_credito'
                            ? (value) {
                                if (value != null) {
                                  setState(() {
                                    _parcelasSelecionadas = value;
                                  });
                                }
                              }
                            : null,
                      ),
                      if (_formaPagamentoSelecionada == 'cartao_credito') ...[
                        const SizedBox(height: 6),
                        Text(
                          'Selecionado: ${_rotuloParcela(_parcelasSelecionadas)}',
                        ),
                      ],
                      const SizedBox(height: 8),
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton.icon(
                          onPressed: _salvarOrcamento,
                          icon: const Icon(Icons.save_outlined),
                          label: const Text('Salvar orcamento'),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
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
  final int quantidade;
  final String precoTipo;
  final double precoUnitario;

  double get subtotal => quantidade * precoUnitario;
}
