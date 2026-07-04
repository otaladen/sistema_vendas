import 'dart:typed_data';

import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../data/app_config_repository.dart';
import '../domain/obra_calculadora_projeto.dart';
import '../domain/pdv_obra_calculadora_insercao.dart';

/// PDF de estimativa de materiais de obra (projeto acumulado no PDV).
Future<Uint8List> gerarObraCalculadoraProjetoPdf({
  required EmpresaConfig config,
  required ObraCalculadoraProjetoSessao projeto,
  required List<PdvObraCalculadoraLinhaInsercao> linhas,
  int tabelaPreco = 1,
}) async {
  final moeda = NumberFormat.currency(locale: 'pt_BR', symbol: 'R\$');
  final dataFmt = DateFormat('dd/MM/yyyy HH:mm');
  final qFmt = NumberFormat('#,##0.##', 'pt_BR');
  final agora = DateTime.now();

  final doc = pw.Document();
  final font = pw.Font.helvetica();
  final fontBold = pw.Font.helveticaBold();

  pw.TextStyle estilo([bool bold = false, double size = 9]) => pw.TextStyle(
        fontSize: size,
        font: bold ? fontBold : font,
      );

  double precoDe(PdvObraCalculadoraLinhaInsercao l) {
    final p = l.produto;
    return switch (tabelaPreco) {
      2 => p.preco2 > 0 ? p.preco2 : p.preco1,
      3 => p.preco3 > 0 ? p.preco3 : p.preco1,
      _ => p.preco1 > 0 ? p.preco1 : p.precoVenda,
    };
  }

  final linhasTabela = linhas.map((l) {
    final unit = precoDe(l);
    final total = unit * l.quantidade;
    final sub = l.substitutoAplicado && l.produtoOriginalNome != null
        ? ' (subst. ${l.produtoOriginalNome})'
        : '';
    return [
      pw.Text('${l.produto.nome}$sub', style: estilo()),
      pw.Text('${qFmt.format(l.quantidade)} ${l.material.unidadeRotulo}', style: estilo()),
      pw.Text(moeda.format(unit), style: estilo(), textAlign: pw.TextAlign.right),
      pw.Text(moeda.format(total), style: estilo(), textAlign: pw.TextAlign.right),
    ];
  }).toList();

  final totalGeral =
      linhas.fold<double>(0, (s, l) => s + precoDe(l) * l.quantidade);

  doc.addPage(
    pw.MultiPage(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.all(32),
      build: (ctx) => [
        pw.Text(
          config.nomeLoja.trim().isEmpty ? 'Material de construcao' : config.nomeLoja,
          style: estilo(true, 14),
        ),
        pw.SizedBox(height: 4),
        pw.Text('Estimativa de materiais de obra', style: estilo(true, 11)),
        pw.SizedBox(height: 8),
        if (projeto.nomeObra.trim().isNotEmpty)
          pw.Text('Obra: ${projeto.nomeObra.trim()}', style: estilo()),
        if (projeto.nomeCliente.trim().isNotEmpty)
          pw.Text('Cliente: ${projeto.nomeCliente.trim()}', style: estilo()),
        pw.Text('Emitido em: ${dataFmt.format(agora)}', style: estilo()),
        pw.SizedBox(height: 12),
        if (projeto.itens.isNotEmpty) ...[
          pw.Text('Composicao do projeto', style: estilo(true, 10)),
          pw.SizedBox(height: 4),
          ...projeto.itens.map(
            (i) => pw.Padding(
              padding: const pw.EdgeInsets.only(bottom: 2),
              child: pw.Text('• ${i.rotuloReceita}: ${i.resumo}', style: estilo()),
            ),
          ),
          pw.SizedBox(height: 12),
        ],
        pw.Text('Lista consolidada de materiais', style: estilo(true, 10)),
        pw.SizedBox(height: 6),
        pw.TableHelper.fromTextArray(
          headers: ['Produto', 'Qtd', 'Unit.', 'Total']
              .map((h) => pw.Text(h, style: estilo(true)))
              .toList(),
          data: linhasTabela,
          headerStyle: estilo(true),
          cellStyle: estilo(),
          headerDecoration: const pw.BoxDecoration(color: PdfColors.grey300),
          cellAlignment: pw.Alignment.centerLeft,
          columnWidths: {
            0: const pw.FlexColumnWidth(3),
            1: const pw.FlexColumnWidth(1.2),
            2: const pw.FlexColumnWidth(1),
            3: const pw.FlexColumnWidth(1),
          },
        ),
        pw.SizedBox(height: 12),
        pw.Align(
          alignment: pw.Alignment.centerRight,
          child: pw.Text(
            'Total estimado (P$tabelaPreco): ${moeda.format(totalGeral)}',
            style: estilo(true, 11),
          ),
        ),
        pw.SizedBox(height: 16),
        pw.Text(
          'Documento sem valor fiscal. Quantidades sao estimativa de balcao — '
          'confira medidas e perdas antes da compra.',
          style: estilo(false, 8),
        ),
      ],
    ),
  );

  return doc.save();
}
