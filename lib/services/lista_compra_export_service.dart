import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:intl/intl.dart';
import 'package:path/path.dart' as p;
import 'package:printing/printing.dart';
import 'package:url_launcher/url_launcher.dart';

import '../data/lista_compra_repository.dart';
import '../domain/lista_compra_item_constantes.dart';
import '../model/item_lista_compra.dart';
import 'pdf_relatorio_texto.dart';

/// Exportacao CSV, PDF e texto para WhatsApp (Fase 3).
class ListaCompraExportService {
  ListaCompraExportService(this._repo);

  final ListaCompraRepository _repo;
  static final _moeda = NumberFormat('#,##0.00', 'pt_BR');
  static final _data = DateFormat('dd/MM/yyyy HH:mm', 'pt_BR');

  String montarTextoPedidoFornecedor(ListaCompraGrupoFornecedor grupo) {
    final buf = StringBuffer();
    buf.writeln('Pedido de compra — ${grupo.fornecedor}');
    buf.writeln('Gerado em ${_data.format(DateTime.now())}');
    buf.writeln('');
    var n = 1;
    for (final item in grupo.itens) {
      final prod = _repo.produtoDe(item);
      final nome = item.nomeExibicao(prod);
      final sku = prod?.codigoInterno ?? '';
      final qtd = item.quantidadePendenteRecebimento;
      buf.write('$n. $nome');
      if (sku.isNotEmpty) buf.write(' (SKU $sku)');
      buf.writeln(' — $qtd ${item.unidade}');
      if (item.observacao.trim().isNotEmpty) {
        buf.writeln('   Obs: ${item.observacao.trim()}');
      }
      n++;
    }
    if (grupo.valorEstimado > 0) {
      buf.writeln('');
      buf.writeln('Valor estimado: R\$ ${_moeda.format(grupo.valorEstimado)}');
    }
    return buf.toString().trim();
  }

  String montarTextoTodosFornecedores() {
    final grupos = _repo.agruparAtivosPorFornecedor();
    if (grupos.isEmpty) return 'Lista de compras vazia.';
    return grupos.map(montarTextoPedidoFornecedor).join('\n\n---\n\n');
  }

  Future<void> compartilharWhatsApp(String texto) async {
    final uri = Uri.parse(
      'https://wa.me/?text=${Uri.encodeComponent(texto)}',
    );
    if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
      await launchUrl(uri);
    }
  }

  Future<String?> exportarCsv({
    required List<ItemListaCompra> itens,
    String? pastaDestino,
  }) async {
    final pasta = pastaDestino ??
        await FilePicker.platform.getDirectoryPath(
          dialogTitle: 'Pasta para salvar lista de compras (CSV)',
        );
    if (pasta == null || pasta.trim().isEmpty) return null;

    final ts = DateFormat('yyyyMMdd_HHmmss').format(DateTime.now());
    final arquivo = File(p.join(pasta, 'lista_compras_$ts.csv'));
    final linhas = <String>[
      'Fornecedor;SKU;Produto;Qtd;Unidade;Prioridade;Status;Origem;Observacao;Criado em',
    ];
    for (final item in itens) {
      final prod = _repo.produtoDe(item);
      linhas.add([
        _csv(item.fornecedorTexto),
        _csv(prod?.codigoInterno ?? ''),
        _csv(item.nomeExibicao(prod)),
        '${item.quantidadePendenteRecebimento}',
        _csv(item.unidade),
        _csv(ListaCompraItemPrioridade.rotulo(item.prioridade)),
        _csv(ListaCompraItemStatus.rotulo(item.status)),
        _csv(ListaCompraItemOrigem.rotulo(item.origem)),
        _csv(item.observacao),
        _csv(_data.format(item.criadoEm.toLocal())),
      ].join(';'));
    }
    await arquivo.writeAsString('\uFEFF${linhas.join('\n')}', encoding: utf8);
    return arquivo.path;
  }

  Future<void> imprimirOuSalvarPdf({
    required List<ItemListaCompra> itens,
    String titulo = 'Lista de compras',
  }) async {
    final texto = _montarTextoPdf(itens, titulo: titulo);
    final bytes = await gerarPdfRelatorioTextoPaginas([texto]);
    await Printing.layoutPdf(onLayout: (_) async => bytes);
  }

  Future<String?> salvarPdfEmArquivo({
    required List<ItemListaCompra> itens,
    String titulo = 'Lista de compras',
  }) async {
    final pasta = await FilePicker.platform.getDirectoryPath(
      dialogTitle: 'Pasta para salvar lista de compras (PDF)',
    );
    if (pasta == null || pasta.trim().isEmpty) return null;
    final ts = DateFormat('yyyyMMdd_HHmmss').format(DateTime.now());
    final arquivo = File(p.join(pasta, 'lista_compras_$ts.pdf'));
    final bytes = await gerarPdfRelatorioTextoPaginas([
      _montarTextoPdf(itens, titulo: titulo),
    ]);
    await arquivo.writeAsBytes(bytes, flush: true);
    return arquivo.path;
  }

  String _montarTextoPdf(List<ItemListaCompra> itens, {required String titulo}) {
    final buf = StringBuffer();
    buf.writeln(titulo.toUpperCase());
    buf.writeln('Gerado em ${_data.format(DateTime.now())}');
    buf.writeln('');
    for (final item in itens) {
      final prod = _repo.produtoDe(item);
      final nome = item.nomeExibicao(prod);
      final sku = prod?.codigoInterno ?? '';
      buf.writeln(
        '- $nome${sku.isNotEmpty ? ' [$sku]' : ''}: '
        '${item.quantidadePendenteRecebimento} ${item.unidade} '
        '(${ListaCompraItemStatus.rotulo(item.status)})',
      );
      if (item.fornecedorTexto.trim().isNotEmpty) {
        buf.writeln('  Fornecedor: ${item.fornecedorTexto.trim()}');
      }
      if (item.observacao.trim().isNotEmpty) {
        buf.writeln('  Obs: ${item.observacao.trim()}');
      }
    }
    return buf.toString();
  }

  static String _csv(String valor) {
    final t = valor.replaceAll('"', '""');
    return '"$t"';
  }
}
