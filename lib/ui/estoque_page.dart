import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:path/path.dart' as p;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../data/produto_repository.dart';
import '../model/produto.dart';

final NumberFormat _moedaBRL = NumberFormat('#,##0.00', 'pt_BR');

class EstoquePage extends StatefulWidget {
  const EstoquePage({super.key, required this.produtoRepository});

  final ProdutoRepository produtoRepository;

  @override
  State<EstoquePage> createState() => _EstoquePageState();
}

class _EstoquePageState extends State<EstoquePage> {
  final TextEditingController _buscaController = TextEditingController();
  String _filtroBusca = '';

  @override
  void dispose() {
    _buscaController.dispose();
    super.dispose();
  }

  String _formatarMoedaBRL(double valor) {
    return 'R\$ ${_moedaBRL.format(valor)}';
  }

  String _csvSeguro(String valor) {
    final texto = valor.replaceAll('"', '""');
    return '"$texto"';
  }

  String _formatarNumeroCsv(double valor) {
    return valor.toStringAsFixed(2).replaceAll('.', ',');
  }

  String _formatarMoedaPdfRapida(num valor) {
    return valor.toStringAsFixed(2).replaceAll('.', ',');
  }

  double _precoAVista(Produto produto) {
    return produto.preco2 > 0 ? produto.preco2 : produto.precoVenda;
  }

  Future<void> _mostrarProgressoExportacao(BuildContext context) {
    return showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => const AlertDialog(
        content: Row(
          children: [
            SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(strokeWidth: 2.2),
            ),
            SizedBox(width: 12),
            Expanded(child: Text('Exportando arquivo, aguarde...')),
          ],
        ),
      ),
    );
  }

  Future<void> _exportarTabelaProdutos(
    BuildContext context, {
    required bool incluirCustos,
  }) async {
    final pastaDestino = await FilePicker.platform.getDirectoryPath(
      dialogTitle: 'Escolha a pasta para exportar a tabela',
    );
    if (pastaDestino == null || pastaDestino.trim().isEmpty) {
      return;
    }

    _mostrarProgressoExportacao(context);
    try {
      final produtos = widget.produtoRepository.listarTodos();
      final timestamp = DateFormat('yyyyMMdd_HHmmss').format(DateTime.now());
      final tipoArquivo = incluirCustos ? 'tabela_preco_custo' : 'tabela_precos';
      final arquivo = File(p.join(pastaDestino, '${tipoArquivo}_$timestamp.csv'));
      final linhas = <String>[];

      if (incluirCustos) {
        linhas.add(
          'SKU;Nome;Unidade;Categoria;Estoque;Reservado;Minimo;Preco1;PrecoAVista;Preco3;PrecoAPrazo;Custo;CustoMedio',
        );
      } else {
        linhas.add(
          'SKU;Nome;Unidade;Categoria;Estoque;Reservado;Minimo;Preco1;PrecoAVista;Preco3;PrecoAPrazo',
        );
      }

      for (final produto in produtos) {
        final colunas = <String>[
          _csvSeguro(produto.codigoInterno),
          _csvSeguro(produto.nome),
          _csvSeguro(produto.unidade),
          _csvSeguro(produto.categoria),
          produto.estoque.toString(),
          produto.estoqueReservado.toString(),
          produto.quantidadeMinima.toString(),
          _formatarNumeroCsv(produto.preco1),
          _formatarNumeroCsv(_precoAVista(produto)),
          _formatarNumeroCsv(produto.preco3),
          _formatarNumeroCsv(produto.precoVenda),
        ];
        if (incluirCustos) {
          colunas.add(_formatarNumeroCsv(produto.precoCusto));
          colunas.add(_formatarNumeroCsv(produto.custoMedio));
        }
        linhas.add(colunas.join(';'));
      }

      await arquivo.writeAsString(
        '\uFEFF${linhas.join('\n')}',
        encoding: utf8,
      );
      if (!context.mounted) return;
      await Navigator.of(context, rootNavigator: true).maybePop();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          duration: const Duration(seconds: 6),
          content: Text('Tabela exportada com sucesso em: ${arquivo.path}'),
        ),
      );
    } catch (e) {
      if (!context.mounted) return;
      await Navigator.of(context, rootNavigator: true).maybePop();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          duration: const Duration(seconds: 7),
          content: Text('Falha ao exportar tabela: $e'),
        ),
      );
    }
  }

  Future<void> _exportarTabelaProdutosPdf(
    BuildContext context, {
    required bool incluirCustos,
  }) async {
    final pastaDestino = await FilePicker.platform.getDirectoryPath(
      dialogTitle: 'Escolha a pasta para exportar o PDF',
    );
    if (pastaDestino == null || pastaDestino.trim().isEmpty) {
      return;
    }

    _mostrarProgressoExportacao(context);
    try {
      final produtos = widget.produtoRepository.listarTodos();
      final timestamp = DateFormat('yyyyMMdd_HHmmss').format(DateTime.now());
      final tipoArquivo = incluirCustos ? 'tabela_preco_custo' : 'tabela_precos';
      final arquivo = File(p.join(pastaDestino, '${tipoArquivo}_$timestamp.pdf'));
      final titulo = incluirCustos
          ? 'Tabela de Preco e Custo - Estoque'
          : 'Tabela de Precos - Estoque';

      final documento = pw.Document();
      // Mantem margem de seguranca para evitar overflow vertical da tabela.
      const porPagina = 52;
      final totalPaginas = (produtos.length / porPagina).ceil().clamp(1, 9999);
      for (var pagina = 0; pagina < totalPaginas; pagina++) {
        final inicio = pagina * porPagina;
        final fim = math.min(inicio + porPagina, produtos.length);
        final recorte = produtos.sublist(inicio, fim);
        final linhas = recorte.map((p) {
          final colCodigo = p.codigoInterno;
          final colProduto = p.nome;
          final colPreco = _formatarMoedaPdfRapida(p.precoVenda);
          final colPrecoVista = _formatarMoedaPdfRapida(_precoAVista(p));
          if (!incluirCustos) {
            return [colCodigo, colProduto, colPreco, colPrecoVista];
          }
          final colCusto = _formatarMoedaPdfRapida(p.precoCusto);
          return [colCodigo, colProduto, colPreco, colPrecoVista, colCusto];
        }).toList();

        documento.addPage(
          pw.Page(
            pageFormat: PdfPageFormat.a4,
            margin: const pw.EdgeInsets.fromLTRB(18, 14, 18, 14),
            build: (context) {
              return pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Row(
                    mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                    children: [
                      pw.Text(
                        DateFormat('dd/MM/yyyy').format(DateTime.now()),
                        style: const pw.TextStyle(fontSize: 7),
                      ),
                      pw.Text(
                        titulo.toUpperCase(),
                        style: pw.TextStyle(
                          fontSize: 8,
                          fontWeight: pw.FontWeight.bold,
                        ),
                      ),
                      pw.Text(
                        'Pagina ${pagina + 1}',
                        style: const pw.TextStyle(fontSize: 7),
                      ),
                    ],
                  ),
                  pw.SizedBox(height: 6),
                  pw.Table(
                    border: pw.TableBorder.all(
                      color: const PdfColor(0.75, 0.75, 0.75),
                      width: 0.4,
                    ),
                    columnWidths: incluirCustos
                        ? {
                            0: const pw.FixedColumnWidth(52),
                            1: const pw.FlexColumnWidth(),
                            2: const pw.FixedColumnWidth(48),
                            3: const pw.FixedColumnWidth(48),
                            4: const pw.FixedColumnWidth(48),
                          }
                        : {
                            0: const pw.FixedColumnWidth(52),
                            1: const pw.FlexColumnWidth(),
                            2: const pw.FixedColumnWidth(52),
                            3: const pw.FixedColumnWidth(52),
                          },
                    children: [
                      pw.TableRow(
                        decoration: const pw.BoxDecoration(
                          color: PdfColor(0.92, 0.92, 0.92),
                        ),
                        children: incluirCustos
                            ? [
                                _cellCabecalho('Codigo'),
                                _cellCabecalho('Produto'),
                                _cellCabecalho('A prazo'),
                                _cellCabecalho('A vista'),
                                _cellCabecalho('Custo'),
                              ]
                            : [
                                _cellCabecalho('Codigo'),
                                _cellCabecalho('Produto'),
                                _cellCabecalho('A prazo'),
                                _cellCabecalho('A vista'),
                              ],
                      ),
                      ...linhas.map(
                        (c) => pw.TableRow(
                          children: incluirCustos
                              ? [
                                  _cellDado(c[0]),
                                  _cellDado(c[1]),
                                  _cellDadoDireita(c[2]),
                                  _cellDadoDireita(c[3]),
                                  _cellDadoDireita(c[4]),
                                ]
                              : [
                                  _cellDado(c[0]),
                                  _cellDado(c[1]),
                                  _cellDadoDireita(c[2]),
                                  _cellDadoDireita(c[3]),
                                ],
                        ),
                      ),
                    ],
                  ),
                ],
              );
            },
          ),
        );
      }

      final bytes = await documento.save().timeout(
        const Duration(seconds: 25),
        onTimeout: () => throw Exception(
          'Tempo excedido ao gerar PDF. Para grande volume, use CSV.',
        ),
      );
      await arquivo.writeAsBytes(bytes);
      if (!context.mounted) return;
      await Navigator.of(context, rootNavigator: true).maybePop();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          duration: const Duration(seconds: 6),
          content: Text('PDF exportado com sucesso em: ${arquivo.path}'),
        ),
      );
    } catch (e) {
      if (!context.mounted) return;
      await Navigator.of(context, rootNavigator: true).maybePop();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          duration: const Duration(seconds: 7),
          content: Text('Falha ao exportar PDF: $e'),
        ),
      );
    }
  }

  pw.Widget _cellCabecalho(String texto) {
    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(horizontal: 3, vertical: 2),
      child: pw.Text(
        texto,
        style: pw.TextStyle(fontSize: 7, fontWeight: pw.FontWeight.bold),
      ),
    );
  }

  pw.Widget _cellDado(String texto) {
    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(horizontal: 3, vertical: 1.8),
      child: pw.Text(
        texto,
        maxLines: 1,
        overflow: pw.TextOverflow.clip,
        style: const pw.TextStyle(fontSize: 7),
      ),
    );
  }

  pw.Widget _cellDadoDireita(String texto) {
    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(horizontal: 3, vertical: 1.8),
      child: pw.Align(
        alignment: pw.Alignment.centerRight,
        child: pw.Text(
          texto,
          maxLines: 1,
          overflow: pw.TextOverflow.clip,
          style: const pw.TextStyle(fontSize: 7),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final produtos = widget.produtoRepository.listarTodos();
    final termo = _filtroBusca.trim().toLowerCase();
    final produtosFiltrados = termo.isEmpty
        ? produtos
        : produtos.where((p) {
            return p.nome.toLowerCase().contains(termo) ||
                p.codigoInterno.toLowerCase().contains(termo) ||
                p.categoria.toLowerCase().contains(termo);
          }).toList();
    final totalAbaixoMinimo = produtos
        .where((p) => p.estoque <= p.quantidadeMinima)
        .length;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Estoque'),
        actions: [
          PopupMenuButton<String>(
            tooltip: 'Exportar tabelas',
            icon: const Icon(Icons.file_download_outlined),
            onSelected: (value) async {
              if (value == 'precos') {
                await _exportarTabelaProdutos(context, incluirCustos: false);
              } else if (value == 'preco_custo') {
                await _exportarTabelaProdutos(context, incluirCustos: true);
              } else if (value == 'precos_pdf') {
                await _exportarTabelaProdutosPdf(context, incluirCustos: false);
              } else if (value == 'preco_custo_pdf') {
                await _exportarTabelaProdutosPdf(context, incluirCustos: true);
              }
            },
            itemBuilder: (context) => const [
              PopupMenuItem<String>(
                value: 'precos',
                child: ListTile(
                  dense: true,
                  leading: Icon(Icons.sell_outlined),
                  title: Text('Exportar tabela de precos'),
                ),
              ),
              PopupMenuItem<String>(
                value: 'preco_custo',
                child: ListTile(
                  dense: true,
                  leading: Icon(Icons.price_change_outlined),
                  title: Text('Exportar tabela de preco e custo'),
                ),
              ),
              PopupMenuDivider(),
              PopupMenuItem<String>(
                value: 'precos_pdf',
                child: ListTile(
                  dense: true,
                  leading: Icon(Icons.picture_as_pdf_outlined),
                  title: Text('Exportar tabela de precos (PDF)'),
                ),
              ),
              PopupMenuItem<String>(
                value: 'preco_custo_pdf',
                child: ListTile(
                  dense: true,
                  leading: Icon(Icons.request_quote_outlined),
                  title: Text('Exportar tabela de preco e custo (PDF)'),
                ),
              ),
            ],
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: Column(
              children: [
                TextField(
                  controller: _buscaController,
                  decoration: InputDecoration(
                    labelText: 'Pesquisar por nome, SKU ou categoria',
                    prefixIcon: const Icon(Icons.search),
                    suffixIcon: _filtroBusca.isEmpty
                        ? null
                        : IconButton(
                            tooltip: 'Limpar pesquisa',
                            onPressed: () {
                              _buscaController.clear();
                              setState(() => _filtroBusca = '');
                            },
                            icon: const Icon(Icons.close),
                          ),
                  ),
                  onChanged: (value) => setState(() => _filtroBusca = value),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    Chip(
                      label: Text(
                        'Itens: ${produtosFiltrados.length}/${produtos.length}',
                      ),
                    ),
                    Chip(
                      avatar: Icon(
                        Icons.warning_amber_outlined,
                        color: totalAbaixoMinimo > 0 ? Colors.red : Colors.green,
                      ),
                      label: Text('Abaixo minimo: $totalAbaixoMinimo'),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: ListView.separated(
              padding: const EdgeInsets.all(12),
              itemCount: produtosFiltrados.length,
              cacheExtent: 800,
              separatorBuilder: (_, _) => const SizedBox(height: 6),
              itemBuilder: (context, index) {
                final produto = produtosFiltrados[index];
                final abaixoMinimo = produto.estoque <= produto.quantidadeMinima;
                return Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: Theme.of(context).colorScheme.outlineVariant,
                    ),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '${produto.nome} (${produto.unidade})',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: Theme.of(context).textTheme.titleSmall,
                            ),
                            const SizedBox(height: 2),
                            Text(
                              'SKU: ${produto.codigoInterno} | Estoque: ${produto.estoque} | Reservado: ${produto.estoqueReservado} | Minimo: ${produto.quantidadeMinima}',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            const SizedBox(height: 2),
                            Text(
                              'Custo: ${_formatarMoedaBRL(produto.precoCusto)} | Medio: ${_formatarMoedaBRL(produto.custoMedio)} | Venda: ${_formatarMoedaBRL(produto.precoVenda)}',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        abaixoMinimo ? 'Abaixo' : 'OK',
                        style: TextStyle(
                          color: abaixoMinimo ? Colors.red : Colors.green,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
