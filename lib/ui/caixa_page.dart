import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:flutter/services.dart';
import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import '../main.dart';
import '../data/app_config_repository.dart';
import '../data/cliente_repository.dart';
import '../data/produto_repository.dart';
import '../data/venda_repository.dart';
import '../model/cliente.dart';
import '../model/venda.dart';

class CaixaPage extends StatefulWidget {
  const CaixaPage({
    super.key,
    required this.clienteRepository,
    required this.produtoRepository,
    required this.vendaRepository,
  });

  final ClienteRepository clienteRepository;
  final ProdutoRepository produtoRepository;
  final VendaRepository vendaRepository;

  @override
  State<CaixaPage> createState() => _CaixaPageState();
}

class _CaixaPageState extends State<CaixaPage> {
  final NumberFormat _currency = NumberFormat('#,##0.00', 'pt_BR');
  static const double _valorMinimoParcela = 5.0;
  List<Venda> _orcamentos = [];
  Venda? _selecionado;
  final _valorRecebidoController = TextEditingController();
  final _valorRecebidoFocusNode = FocusNode();
  final ScrollController _orcamentosScrollController = ScrollController();
  final ScrollController _itensScrollController = ScrollController();
  final _configRepository = AppConfigRepository();
  double? _valorRecebido;
  int? _itemSelecionadoId;
  List<Cliente> _clientesAtivos = [];

  @override
  void initState() {
    super.initState();
    _clientesAtivos = widget.clienteRepository.listarTodos().where((c) => c.ativo).toList();
    _carregarOrcamentos();
  }

  void _carregarOrcamentos() {
    setState(() {
      _orcamentos = widget.vendaRepository.listarOrcamentosPendentes();
      if (_selecionado != null) {
        _selecionado = _orcamentos.where((v) => v.id == _selecionado!.id).firstOrNull;
      }
      if (_selecionado == null) {
        _valorRecebidoController.clear();
        _valorRecebido = null;
        _valorRecebidoFocusNode.unfocus();
        _itemSelecionadoId = null;
      }
    });
  }

  void _focarValorRecebidoSeDinheiro() {
    final selecionado = _selecionado;
    if (selecionado == null || selecionado.formaPagamento != 'dinheiro') {
      return;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _valorRecebidoFocusNode.requestFocus();
      }
    });
  }

  String _formatarMoeda(double valor) => 'R\$ ${_currency.format(valor)}';

  double? _parseValor(String texto) {
    final normalizado = texto.trim().replaceAll('.', '').replaceAll(',', '.');
    if (normalizado.isEmpty) {
      return null;
    }
    return double.tryParse(normalizado);
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

  String _rotuloStatusEntrega(String status) {
    switch (status) {
      case 'pendente':
        return 'Pendente';
      case 'roteirizada':
        return 'Roteirizada';
      case 'saiu_entrega':
        return 'Saiu para entrega';
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

  Future<void> _finalizarOrcamento(Venda venda) async {
    final totalVenda = venda.total;
    final formaPagamento = venda.formaPagamento;
    final parcelas = venda.quantidadeParcelas;
    final totalRecebido = formaPagamento == 'dinheiro' ? (_valorRecebido ?? 0) : totalVenda;
    final trocoFinal = formaPagamento == 'dinheiro'
        ? (totalRecebido - totalVenda).clamp(0, double.infinity).toDouble()
        : 0.0;
    final itensCount = venda.itens.length;

    if (venda.formaPagamento == 'dinheiro') {
      final recebido = _valorRecebido ?? 0;
      if (recebido < venda.total) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Valor recebido insuficiente para finalizar em dinheiro.')),
        );
        return;
      }
    }
    if (venda.formaPagamento == 'cartao_credito') {
      final valorParcela = venda.quantidadeParcelas > 0
          ? (venda.total / venda.quantidadeParcelas)
          : venda.total;
      if (valorParcela < _valorMinimoParcela) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Parcela minima de ${_formatarMoeda(_valorMinimoParcela)} nao atingida. Ajuste as parcelas.',
            ),
          ),
        );
        return;
      }
    }
    if (venda.formaPagamento == 'cartao_debito' && venda.quantidadeParcelas != 1) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Cartao de debito deve ser sempre a vista (1x).')),
      );
      return;
    }
    final confirmarFinalizacao = await _mostrarResumoFechamentoVenda(
      numeroOrcamento: venda.numeroOrcamento,
      formaPagamento: formaPagamento,
      quantidadeParcelas: parcelas,
      totalVenda: totalVenda,
      totalRecebido: totalRecebido,
      troco: trocoFinal,
      quantidadeItens: itensCount,
    );
    if (confirmarFinalizacao != true) {
      return;
    }
    try {
      widget.vendaRepository.converterOrcamentoParaVenda(venda.id);
      _carregarOrcamentos();
      if (!mounted) return;
      setState(() {
        _selecionado = null;
        _itemSelecionadoId = null;
        _valorRecebidoController.clear();
        _valorRecebido = null;
      });
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Orcamento #${venda.numeroOrcamento} finalizado.')));
      await _mostrarAcoesNotaPosVenda(
        venda: venda,
        totalRecebido: totalRecebido,
        troco: trocoFinal,
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Nao foi possivel finalizar: $e')),
      );
    }
  }

  Future<Uint8List> _gerarNotaPdfBytes({
    required Venda venda,
    required double totalRecebido,
    required double troco,
  }) async {
    final cliente = _clienteDaVenda(venda);
    final config = await _configRepository.carregarEmpresaConfig();
    final logoBytes = config.logoPath.trim().isNotEmpty
        ? await File(config.logoPath).readAsBytes().catchError((_) => Uint8List(0))
        : Uint8List(0);
    final doc = pw.Document();
    final dataHora = DateFormat('dd/MM/yyyy HH:mm').format(DateTime.now());
    doc.addPage(
      pw.Page(
        pageFormat: config.modeloPdf == 'a4'
            ? PdfPageFormat.a4
            : PdfPageFormat(80 * PdfPageFormat.mm, double.infinity),
        margin: const pw.EdgeInsets.all(8),
        build: (context) {
          final subtotalProdutos =
              (venda.total - venda.valorFrete).clamp(0, double.infinity).toDouble();
          return pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Center(
                child: pw.Text(
                  config.nomeLoja,
                  style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold),
                ),
              ),
              if (logoBytes.isNotEmpty)
                pw.Center(
                  child: pw.Padding(
                    padding: const pw.EdgeInsets.only(top: 4, bottom: 4),
                    child: pw.Image(pw.MemoryImage(logoBytes), height: 45),
                  ),
                ),
              if (config.telefone.trim().isNotEmpty)
                pw.Center(
                  child: pw.Text(
                    'Tel: ${config.telefone}',
                    style: const pw.TextStyle(fontSize: 8),
                  ),
                ),
              if (config.endereco.trim().isNotEmpty)
                pw.Center(
                  child: pw.Text(
                    config.endereco,
                    style: const pw.TextStyle(fontSize: 8),
                    textAlign: pw.TextAlign.center,
                  ),
                ),
              pw.Center(
                child: pw.Text(
                  'CUPOM NAO FISCAL',
                  style: const pw.TextStyle(fontSize: 9),
                ),
              ),
              pw.SizedBox(height: 6),
              pw.Divider(),
              pw.Text(
                'ORCAMENTO #${venda.numeroOrcamento}',
                style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold),
              ),
              pw.Text('Data: $dataHora', style: const pw.TextStyle(fontSize: 9)),
              pw.Text('Cliente: ${cliente?.nomeRazao ?? 'Sem cliente'}', style: const pw.TextStyle(fontSize: 9)),
              if ((cliente?.documento.trim().isNotEmpty ?? false))
                pw.Text('Documento: ${cliente!.documento}', style: const pw.TextStyle(fontSize: 9)),
              if ((cliente?.telefone.trim().isNotEmpty ?? false))
                pw.Text('Telefone: ${cliente!.telefone}', style: const pw.TextStyle(fontSize: 9)),
              pw.Text(
                'Pagamento: ${_rotuloFormaPagamento(venda.formaPagamento)}',
                style: const pw.TextStyle(fontSize: 9),
              ),
              if (venda.formaPagamento == 'cartao_credito')
                pw.Text('Parcelas: ${venda.quantidadeParcelas}x', style: const pw.TextStyle(fontSize: 9)),
              pw.Text(
                'Entrega: ${_rotuloTipoEntrega(venda.tipoEntrega)}'
                '${venda.tipoEntrega == 'entrega_loja' ? ' | Frete: ${_formatarMoeda(venda.valorFrete)}' : ''}',
                style: const pw.TextStyle(fontSize: 9),
              ),
              if (venda.enderecoEntrega.trim().isNotEmpty)
                pw.Text('Endereco: ${venda.enderecoEntrega}', style: const pw.TextStyle(fontSize: 9)),
              pw.SizedBox(height: 10),
              pw.Text(
                'ITENS',
                style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold),
              ),
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
                'TOTAL: ${_formatarMoeda(venda.total)}',
                style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold),
              ),
              pw.Text('Recebido: ${_formatarMoeda(totalRecebido)}', style: const pw.TextStyle(fontSize: 9)),
              pw.Text(
                'Troco: ${_formatarMoeda(troco)}',
                style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold),
              ),
              pw.SizedBox(height: 8),
              pw.Center(
                child: pw.Text(
                  config.rodapeNota,
                  style: const pw.TextStyle(fontSize: 8),
                ),
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
    if (selectedPath == null) {
      return null;
    }
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
      if (printer.name == printerName) {
        return printer;
      }
    }
    return null;
  }

  Future<void> _mostrarAcoesNotaPosVenda({
    required Venda venda,
    required double totalRecebido,
    required double troco,
  }) async {
    final config = await _configRepository.carregarEmpresaConfig();
    if (!mounted) return;
    final acao = await showDialog<String>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Nota da venda'),
          content: const Text('Deseja imprimir a nota agora ou gerar PDF?'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, 'fechar'),
              child: const Text('Fechar'),
            ),
            OutlinedButton.icon(
              onPressed: () => Navigator.pop(context, 'pdf'),
              icon: const Icon(Icons.picture_as_pdf_outlined),
              label: const Text('Mandar nota em PDF'),
            ),
            OutlinedButton.icon(
              onPressed: () => Navigator.pop(context, 'direto'),
              icon: const Icon(Icons.print),
              label: const Text('Impressao direta'),
            ),
            ElevatedButton.icon(
              onPressed: () => Navigator.pop(context, 'imprimir'),
              icon: const Icon(Icons.print_outlined),
              label: const Text('Imprimir nota'),
            ),
          ],
        );
      },
    );
    if (!mounted || acao == null || acao == 'fechar') return;
    try {
      final pdfBytes = await _gerarNotaPdfBytes(
        venda: venda,
        totalRecebido: totalRecebido,
        troco: troco,
      );
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
          name: 'Nota Orcamento ${venda.numeroOrcamento}',
          format: config.modeloPdf == 'a4'
              ? PdfPageFormat.a4
              : PdfPageFormat(80 * PdfPageFormat.mm, double.infinity),
        );
        return;
      }
      final path = await _escolherSalvarPdf(
        bytes: pdfBytes,
        suggestedFileName: 'nota_orcamento_${venda.numeroOrcamento}.pdf',
        initialDirectory: config.pastaPadraoPdf.trim().isEmpty ? null : config.pastaPadraoPdf.trim(),
      );
      if (!mounted || path == null) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('PDF salvo em: $path')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Nao foi possivel gerar/imprimir nota: $e')),
      );
    }
  }

  Future<bool?> _mostrarResumoFechamentoVenda({
    required int numeroOrcamento,
    required String formaPagamento,
    required int quantidadeParcelas,
    required double totalVenda,
    required double totalRecebido,
    required double troco,
    required int quantidadeItens,
  }) async {
    return showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        final semantic = Theme.of(context).extension<AppSemanticColors>();
        return AlertDialog(
          title: Text('Venda finalizada - Orcamento #$numeroOrcamento'),
          content: SizedBox(
            width: 520,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Pagamento: ${_rotuloFormaPagamento(formaPagamento)}'
                  '${formaPagamento == 'cartao_credito' ? ' | ${quantidadeParcelas}x' : ''}',
                ),
                const SizedBox(height: 4),
                Text('Itens: $quantidadeItens'),
                const SizedBox(height: 12),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: semantic?.successBg ?? Colors.green.shade50,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: semantic?.successBorder ?? Colors.green.shade200),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      const Text('TROCO'),
                      const SizedBox(height: 4),
                      Text(
                        _formatarMoeda(troco),
                        style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                          color: semantic?.successFg ?? Colors.green.shade800,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: _buildResumoCard(
                        context,
                        label: 'TOTAL DA VENDA',
                        valor: _formatarMoeda(totalVenda),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _buildResumoCard(
                        context,
                        label: 'TOTAL RECEBIDO',
                        valor: _formatarMoeda(totalRecebido),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Voltar e nao finalizar'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Concluir venda'),
            ),
          ],
        );
      },
    );
  }

  Future<void> _alterarQuantidadeItemSelecionado(int delta) async {
    final venda = _selecionado;
    final itemId = _itemSelecionadoId;
    if (venda == null || itemId == null) {
      return;
    }
    final item = venda.itens.where((i) => i.id == itemId).firstOrNull;
    if (item == null) {
      return;
    }
    final novaQuantidade = item.quantidade + delta;
    if (novaQuantidade <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Quantidade precisa ser maior que zero.')),
      );
      return;
    }
    try {
      widget.vendaRepository.atualizarQuantidadeItemOrcamento(venda.id, item.id, novaQuantidade);
      _carregarOrcamentos();
      setState(() {
        _itemSelecionadoId = item.id;
      });
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Nao foi possivel atualizar quantidade: $e')),
      );
    }
  }

  Future<void> _removerItemSelecionado() async {
    final venda = _selecionado;
    final itemId = _itemSelecionadoId;
    if (venda == null || itemId == null) {
      return;
    }
    try {
      widget.vendaRepository.removerItemOrcamento(venda.id, itemId);
      _carregarOrcamentos();
      setState(() {
        _itemSelecionadoId = null;
      });
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Nao foi possivel remover item: $e')),
      );
    }
  }

  Future<void> _vincularClienteAgora() async {
    final venda = _selecionado;
    if (venda == null) return;
    int? clienteSelecionadoId = venda.cliente.target?.id;
    final confirmar = await showDialog<bool>(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: const Text('Vincular cliente ao orcamento'),
              content: DropdownButtonFormField<int?>(
                initialValue: clienteSelecionadoId,
                decoration: const InputDecoration(labelText: 'Cliente (opcional)'),
                items: [
                  const DropdownMenuItem<int?>(
                    value: null,
                    child: Text('Sem cliente'),
                  ),
                  ..._clientesAtivos.map(
                    (c) => DropdownMenuItem<int?>(
                      value: c.id,
                      child: Text(c.nomeRazao),
                    ),
                  ),
                ],
                onChanged: (value) {
                  setDialogState(() {
                    clienteSelecionadoId = value;
                  });
                },
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context, false),
                  child: const Text('Cancelar'),
                ),
                ElevatedButton(
                  onPressed: () => Navigator.pop(context, true),
                  child: const Text('Salvar'),
                ),
              ],
            );
          },
        );
      },
    );
    if (confirmar != true) return;
    try {
      widget.vendaRepository.vincularClienteNoOrcamento(venda.id, clienteSelecionadoId);
      _carregarOrcamentos();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Cliente atualizado no orcamento.')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Nao foi possivel vincular cliente: $e')),
      );
    }
  }

  @override
  void dispose() {
    _valorRecebidoController.dispose();
    _valorRecebidoFocusNode.dispose();
    _orcamentosScrollController.dispose();
    _itensScrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final selecionado = _selecionado;
    final clienteSelecionado = selecionado == null ? null : _clienteDaVenda(selecionado);
    final totalSelecionado = selecionado?.total ?? 0;
    final freteSelecionado = selecionado?.valorFrete ?? 0;
    final subtotalProdutos = (totalSelecionado - freteSelecionado).clamp(0, double.infinity).toDouble();
    final troco = (((_valorRecebido ?? 0) - totalSelecionado).clamp(
      0,
      double.infinity,
    )).toDouble();
    return Shortcuts(
      shortcuts: <LogicalKeySet, Intent>{
        LogicalKeySet(LogicalKeyboardKey.enter): const ActivateIntent(),
        LogicalKeySet(LogicalKeyboardKey.escape): const DismissIntent(),
        LogicalKeySet(LogicalKeyboardKey.numpadAdd): const _AumentarQuantidadeIntent(),
        LogicalKeySet(LogicalKeyboardKey.equal, LogicalKeyboardKey.shift): const _AumentarQuantidadeIntent(),
        LogicalKeySet(LogicalKeyboardKey.numpadSubtract): const _DiminuirQuantidadeIntent(),
        LogicalKeySet(LogicalKeyboardKey.minus): const _DiminuirQuantidadeIntent(),
        LogicalKeySet(LogicalKeyboardKey.delete): const _RemoverItemIntent(),
        LogicalKeySet(LogicalKeyboardKey.f4): const _VincularClienteIntent(),
      },
      child: Actions(
        actions: <Type, Action<Intent>>{
          ActivateIntent: CallbackAction<ActivateIntent>(
            onInvoke: (intent) {
              final venda = _selecionado;
              if (venda != null) {
                _finalizarOrcamento(venda);
              }
              return null;
            },
          ),
          DismissIntent: CallbackAction<DismissIntent>(
            onInvoke: (intent) {
              if (_selecionado?.formaPagamento == 'dinheiro') {
                setState(() {
                  _valorRecebidoController.clear();
                  _valorRecebido = null;
                });
                _focarValorRecebidoSeDinheiro();
              }
              return null;
            },
          ),
          _AumentarQuantidadeIntent: CallbackAction<_AumentarQuantidadeIntent>(
            onInvoke: (intent) {
              if (_itemSelecionadoId != null) {
                _alterarQuantidadeItemSelecionado(1);
              }
              return null;
            },
          ),
          _DiminuirQuantidadeIntent: CallbackAction<_DiminuirQuantidadeIntent>(
            onInvoke: (intent) {
              if (_itemSelecionadoId != null) {
                _alterarQuantidadeItemSelecionado(-1);
              }
              return null;
            },
          ),
          _RemoverItemIntent: CallbackAction<_RemoverItemIntent>(
            onInvoke: (intent) {
              if (_itemSelecionadoId != null) {
                _removerItemSelecionado();
              }
              return null;
            },
          ),
          _VincularClienteIntent: CallbackAction<_VincularClienteIntent>(
            onInvoke: (intent) {
              if (_selecionado != null) {
                _vincularClienteAgora();
              }
              return null;
            },
          ),
        },
        child: Focus(
          autofocus: true,
          child: Scaffold(
            appBar: AppBar(title: const Text('Caixa')),
            body: Container(
              color: theme.colorScheme.surfaceContainerLowest,
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: selecionado == null
                  ? Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          flex: 3,
                          child: _buildListaOrcamentos(context),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          flex: 7,
                          child: Card(
                            child: Center(
                              child: Text(
                                'Selecione um orcamento para abrir o atendimento do caixa.',
                                style: Theme.of(context).textTheme.titleMedium,
                                textAlign: TextAlign.center,
                              ),
                            ),
                          ),
                        ),
                      ],
                    )
                  : Column(
                      children: [
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              colors: [
                                theme.colorScheme.primaryContainer,
                                theme.colorScheme.surfaceContainerHighest,
                              ],
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                            ),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: theme.colorScheme.outlineVariant),
                          ),
                          child: Row(
                            children: [
                              Icon(
                                Icons.point_of_sale_outlined,
                                color: theme.colorScheme.primary,
                              ),
                              const SizedBox(width: 8),
                              Text(
                                'CAIXA ABERTO',
                                style: theme.textTheme.titleLarge?.copyWith(
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              const Spacer(),
                              Text(
                                'Orcamento #${selecionado.numeroOrcamento}',
                                style: theme.textTheme.titleMedium,
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 10),
                        Expanded(
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Expanded(
                                flex: 3,
                                child: _buildListaOrcamentos(context),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                flex: 7,
                                child: Card(
                                  child: Padding(
                                    padding: const EdgeInsets.all(12),
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Container(
                                          width: double.infinity,
                                          padding: const EdgeInsets.all(10),
                                          decoration: BoxDecoration(
                                            color: Colors.grey.shade100,
                                            borderRadius: BorderRadius.circular(8),
                                            border: Border.all(color: Colors.grey.shade300),
                                          ),
                                          child: Row(
                                            children: [
                                              Expanded(
                                                child: Text(
                                                  'Pagamento: ${_rotuloFormaPagamento(selecionado.formaPagamento)}'
                                                  '${selecionado.formaPagamento == 'cartao_credito' ? ' | ${selecionado.quantidadeParcelas}x' : ''}',
                                                ),
                                              ),
                                              Text(
                                                'TOTAL: ${_formatarMoeda(totalSelecionado)}',
                                                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                                                  fontWeight: FontWeight.bold,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                        const SizedBox(height: 6),
                                        Text(
                                          'Entrega: ${_rotuloTipoEntrega(selecionado.tipoEntrega)}'
                                          '${selecionado.tipoEntrega == 'entrega_loja' ? ' | Frete: ${_formatarMoeda(selecionado.valorFrete)}' : ''}',
                                        ),
                                        if (selecionado.tipoEntrega == 'entrega_loja' &&
                                            selecionado.enderecoEntrega.trim().isNotEmpty)
                                          Text('Endereco: ${selecionado.enderecoEntrega}'),
                                        if (selecionado.tipoEntrega == 'entrega_loja')
                                          Text('Status entrega: ${_rotuloStatusEntrega(selecionado.statusEntrega)}'),
                                        if (selecionado.tipoEntrega == 'entrega_loja' &&
                                            selecionado.observacaoEntrega.trim().isNotEmpty)
                                          Text('Obs entrega: ${selecionado.observacaoEntrega}'),
                                        const SizedBox(height: 6),
                                        Row(
                                          children: [
                                            Expanded(
                                              child: Text(
                                                'Cliente: ${clienteSelecionado?.nomeRazao ?? 'Sem cliente'}',
                                              ),
                                            ),
                                            OutlinedButton.icon(
                                              onPressed: _vincularClienteAgora,
                                              icon: const Icon(Icons.person_add_alt_1_outlined),
                                              label: const Text('Vincular cliente agora (F4)'),
                                            ),
                                          ],
                                        ),
                                        if (selecionado.formaPagamento == 'cartao_credito') ...[
                                          const SizedBox(height: 6),
                                          Text(
                                            'Parcela: ${_formatarMoeda(selecionado.total / selecionado.quantidadeParcelas)}'
                                            ' (minimo ${_formatarMoeda(_valorMinimoParcela)})',
                                          ),
                                        ],
                                        const SizedBox(height: 8),
                                        Expanded(
                                          child: Row(
                                            children: [
                                              Expanded(
                                                child: Card(
                                                  elevation: 0,
                                                  color: Colors.grey.shade50,
                                                  child: Column(
                                                    children: [
                                                      Container(
                                                        padding: const EdgeInsets.symmetric(
                                                          horizontal: 8,
                                                          vertical: 6,
                                                        ),
                                                        decoration: BoxDecoration(
                                                          color: Colors.blueGrey.shade100,
                                                          borderRadius: const BorderRadius.only(
                                                            topLeft: Radius.circular(8),
                                                            topRight: Radius.circular(8),
                                                          ),
                                                        ),
                                                        child: const Row(
                                                          children: [
                                                            SizedBox(
                                                              width: 32,
                                                              child: Text(
                                                                '#',
                                                                style: TextStyle(
                                                                  fontWeight: FontWeight.bold,
                                                                ),
                                                              ),
                                                            ),
                                                            Expanded(
                                                              flex: 4,
                                                              child: Text(
                                                                'Produto',
                                                                style: TextStyle(
                                                                  fontWeight: FontWeight.bold,
                                                                ),
                                                              ),
                                                            ),
                                                            Expanded(
                                                              child: Text(
                                                                'Qtd',
                                                                style: TextStyle(
                                                                  fontWeight: FontWeight.bold,
                                                                ),
                                                              ),
                                                            ),
                                                            Expanded(
                                                              child: Text(
                                                                'Vlr Unit',
                                                                style: TextStyle(
                                                                  fontWeight: FontWeight.bold,
                                                                ),
                                                              ),
                                                            ),
                                                            Expanded(
                                                              child: Text(
                                                                'Total',
                                                                textAlign: TextAlign.right,
                                                                style: TextStyle(
                                                                  fontWeight: FontWeight.bold,
                                                                ),
                                                              ),
                                                            ),
                                                          ],
                                                        ),
                                                      ),
                                                      Expanded(
                                                        child: RawScrollbar(
                                                          controller: _itensScrollController,
                                                          thumbVisibility: true,
                                                          trackVisibility: true,
                                                          thickness: 10,
                                                          radius: const Radius.circular(8),
                                                          child: ListView.builder(
                                                            controller: _itensScrollController,
                                                            padding: const EdgeInsets.only(right: 10),
                                                            itemCount: selecionado.itens.length,
                                                            itemBuilder: (context, index) {
                                                              final item = selecionado.itens[index];
                                                              final selecionadoItem =
                                                                  _itemSelecionadoId == item.id;
                                                              return InkWell(
                                                                onTap: () {
                                                                  setState(() {
                                                                    _itemSelecionadoId = item.id;
                                                                  });
                                                                },
                                                                child: Container(
                                                                  color: selecionadoItem
                                                                      ? Colors.blue.shade50
                                                                      : null,
                                                                  padding: const EdgeInsets.symmetric(
                                                                    horizontal: 8,
                                                                    vertical: 6,
                                                                  ),
                                                                  child: Row(
                                                                    children: [
                                                                      SizedBox(
                                                                        width: 32,
                                                                        child: Text('${index + 1}'),
                                                                      ),
                                                                      Expanded(
                                                                        flex: 4,
                                                                        child: Text(item.nomeProduto),
                                                                      ),
                                                                      Expanded(
                                                                        child: Text(
                                                                          item.quantidade.toString(),
                                                                        ),
                                                                      ),
                                                                      Expanded(
                                                                        child: Text(
                                                                          _formatarMoeda(
                                                                            item.precoUnitario,
                                                                          ),
                                                                        ),
                                                                      ),
                                                                      Expanded(
                                                                        child: Text(
                                                                          _formatarMoeda(
                                                                            item.subtotal,
                                                                          ),
                                                                          textAlign: TextAlign.right,
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
                                                    ],
                                                  ),
                                                ),
                                              ),
                                              const SizedBox(width: 8),
                                              SizedBox(
                                                width: 160,
                                                child: Column(
                                                  children: [
                                                    _buildAcaoCaixaButton(
                                                      context,
                                                      label: '+ Quantidade',
                                                      onPressed: _itemSelecionadoId == null
                                                          ? null
                                                          : () => _alterarQuantidadeItemSelecionado(
                                                              1,
                                                            ),
                                                    ),
                                                    const SizedBox(height: 8),
                                                    _buildAcaoCaixaButton(
                                                      context,
                                                      label: '- Quantidade',
                                                      onPressed: _itemSelecionadoId == null
                                                          ? null
                                                          : () => _alterarQuantidadeItemSelecionado(
                                                              -1,
                                                            ),
                                                    ),
                                                    const SizedBox(height: 8),
                                                    _buildAcaoCaixaButton(
                                                      context,
                                                      label: 'Remover item',
                                                      onPressed: _itemSelecionadoId == null
                                                          ? null
                                                          : _removerItemSelecionado,
                                                    ),
                                                    const SizedBox(height: 8),
                                                    _buildAcaoCaixaButton(
                                                      context,
                                                      label: 'Atualizar',
                                                      onPressed: _carregarOrcamentos,
                                                    ),
                                                  ],
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                        const SizedBox(height: 8),
                                        Row(
                                          children: [
                                            Expanded(
                                              child: _buildResumoCard(
                                                context,
                                                label: 'SUBTOTAL PRODUTOS',
                                                valor: _formatarMoeda(subtotalProdutos),
                                              ),
                                            ),
                                            const SizedBox(width: 8),
                                            Expanded(
                                              child: _buildResumoCard(
                                                context,
                                                label: 'FRETE',
                                                valor: _formatarMoeda(freteSelecionado),
                                              ),
                                            ),
                                            const SizedBox(width: 8),
                                            Expanded(
                                              child: _buildResumoCard(
                                                context,
                                                label: 'TOTAL RECEBIDO',
                                                valor: _formatarMoeda(_valorRecebido ?? 0),
                                              ),
                                            ),
                                            const SizedBox(width: 8),
                                            Expanded(
                                              child: _buildResumoCard(
                                                context,
                                                label: 'TROCO',
                                                valor: _formatarMoeda(troco),
                                                destaque: true,
                                              ),
                                            ),
                                          ],
                                        ),
                                        const SizedBox(height: 8),
                                        if (selecionado.formaPagamento == 'dinheiro')
                                          TextField(
                                            controller: _valorRecebidoController,
                                            focusNode: _valorRecebidoFocusNode,
                                            keyboardType: const TextInputType.numberWithOptions(
                                              decimal: true,
                                            ),
                                            decoration: const InputDecoration(
                                              labelText: 'Valor recebido (dinheiro)',
                                              hintText: 'Ex.: 100,00',
                                            ),
                                            onChanged: (value) {
                                              setState(() {
                                                _valorRecebido = _parseValor(value);
                                              });
                                            },
                                          ),
                                        const SizedBox(height: 8),
                                        Row(
                                          children: [
                                            Expanded(
                                              child: Text(
                                                'Atalhos: Enter = finalizar | Esc = limpar recebido | + = aumentar qtd | - = diminuir qtd | Del = remover item | F4 = vincular cliente',
                                                style: Theme.of(context).textTheme.bodySmall,
                                              ),
                                            ),
                                            const SizedBox(width: 8),
                                            SizedBox(
                                              width: 280,
                                              child: ElevatedButton.icon(
                                                onPressed: () => _finalizarOrcamento(selecionado),
                                                icon: const Icon(Icons.check_circle_outline),
                                                label: const Text('Finalizar venda (Enter)'),
                                              ),
                                            ),
                                          ],
                                        ),
                                      ],
                                    ),
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
          ),
        ),
      ),
    );
  }

  Widget _buildListaOrcamentos(BuildContext context) {
    return Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
            child: Text(
              'Orcamentos pendentes',
              style: Theme.of(context).textTheme.titleMedium,
            ),
          ),
          const SizedBox(height: 8),
          Expanded(
            child: _orcamentos.isEmpty
                ? const Center(child: Text('Nenhum orcamento pendente.'))
                : RawScrollbar(
                    controller: _orcamentosScrollController,
                    thumbVisibility: true,
                    trackVisibility: true,
                    thickness: 10,
                    radius: const Radius.circular(8),
                    child: ListView.builder(
                      controller: _orcamentosScrollController,
                      padding: const EdgeInsets.only(right: 10, bottom: 8),
                      itemCount: _orcamentos.length,
                      itemBuilder: (context, index) {
                        final orc = _orcamentos[index];
                        return ListTile(
                          selected: _selecionado?.id == orc.id,
                          leading: CircleAvatar(
                            child: Text('${orc.numeroOrcamento}'),
                          ),
                          title: Text('Orcamento #${orc.numeroOrcamento}'),
                          subtitle: Text(
                            'Itens: ${orc.itens.length} | Total: ${_formatarMoeda(orc.total)}',
                          ),
                          onTap: () {
                            setState(() {
                              _selecionado = orc;
                              _valorRecebidoController.clear();
                              _valorRecebido = null;
                              _itemSelecionadoId = null;
                            });
                            _focarValorRecebidoSeDinheiro();
                          },
                        );
                      },
                    ),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildResumoCard(
    BuildContext context, {
    required String label,
    required String valor,
    bool destaque = false,
  }) {
    final semantic = Theme.of(context).extension<AppSemanticColors>();
    final color = destaque
        ? semantic?.successBg ?? Colors.green.shade50
        : semantic?.infoBg ?? Colors.blueGrey.shade50;
    final border = destaque
        ? semantic?.successBorder ?? Colors.green.shade200
        : semantic?.infoBorder ?? Colors.blueGrey.shade100;
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: Theme.of(context).textTheme.bodySmall),
          const SizedBox(height: 4),
          Text(
            valor,
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAcaoCaixaButton(
    BuildContext context, {
    required String label,
    required VoidCallback? onPressed,
  }) {
    return SizedBox(
      width: double.infinity,
      child: OutlinedButton(
        onPressed: onPressed,
        child: Text(label),
      ),
    );
  }
}

class _AumentarQuantidadeIntent extends Intent {
  const _AumentarQuantidadeIntent();
}

class _DiminuirQuantidadeIntent extends Intent {
  const _DiminuirQuantidadeIntent();
}

class _RemoverItemIntent extends Intent {
  const _RemoverItemIntent();
}

class _VincularClienteIntent extends Intent {
  const _VincularClienteIntent();
}
