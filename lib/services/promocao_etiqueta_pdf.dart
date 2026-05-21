import 'dart:typed_data';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../domain/promocao_info_vigente.dart';
import '../model/produto.dart';

/// Etiquetas simples de gondola (A4, 3 colunas) para produtos em promocao.
Future<Uint8List> gerarPdfEtiquetasGondolaPromocao(
  List<({Produto produto, PromocaoInfoVigente info})> itens,
) async {
  final doc = pw.Document();
  const porLinha = 3;
  const alturaEtiqueta = 72.0;

  String fmtMoeda(double v) => 'R\$ ${v.toStringAsFixed(2)}';

  pw.Widget etiqueta(({Produto produto, PromocaoInfoVigente info}) e) {
    return pw.Container(
      height: alturaEtiqueta,
      padding: const pw.EdgeInsets.all(6),
      decoration: pw.BoxDecoration(
        border: pw.Border.all(color: PdfColors.red800, width: 1.2),
        borderRadius: pw.BorderRadius.circular(4),
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text(
            'PROMO',
            style: pw.TextStyle(
              fontSize: 9,
              fontWeight: pw.FontWeight.bold,
              color: PdfColors.red800,
            ),
          ),
          pw.SizedBox(height: 2),
          pw.Text(
            e.produto.nome,
            maxLines: 2,
            style: pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold),
          ),
          pw.Spacer(),
          pw.Text(
            fmtMoeda(e.info.precoCalculado),
            style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold),
          ),
          if (e.info.precoBasePreco1 > e.info.precoCalculado + 0.01)
            pw.Text(
              'De ${fmtMoeda(e.info.precoBasePreco1)}',
              style: const pw.TextStyle(
                fontSize: 7,
                decoration: pw.TextDecoration.lineThrough,
              ),
            ),
          pw.Text(
            e.info.resumoRegra,
            maxLines: 1,
            style: const pw.TextStyle(fontSize: 6),
          ),
          pw.Text(
            'SKU ${e.produto.codigoInterno}',
            style: const pw.TextStyle(fontSize: 6),
          ),
        ],
      ),
    );
  }

  final linhas = <List<({Produto produto, PromocaoInfoVigente info})>>[];
  for (var i = 0; i < itens.length; i += porLinha) {
    linhas.add(
      itens.sublist(i, i + porLinha > itens.length ? itens.length : i + porLinha),
    );
  }

  doc.addPage(
    pw.MultiPage(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.all(16),
      build: (context) {
        return [
          for (final row in linhas)
            pw.Padding(
              padding: const pw.EdgeInsets.only(bottom: 8),
              child: pw.Row(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  for (var c = 0; c < porLinha; c++)
                    pw.Expanded(
                      child: c < row.length
                          ? etiqueta(row[c])
                          : pw.SizedBox(height: alturaEtiqueta),
                    ),
                  if (porLinha > 1) ...[
                    for (var g = 0; g < porLinha - 1; g++) pw.SizedBox(width: 6),
                  ],
                ],
              ),
            ),
        ];
      },
    ),
  );

  return doc.save();
}
