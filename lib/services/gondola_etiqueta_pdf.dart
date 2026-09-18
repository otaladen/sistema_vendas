import 'dart:typed_data';

import 'package:barcode/barcode.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

/// Etiquetas de gondola em A4 (3 colunas) para produtos com preco reajustado.
Future<Uint8List> gerarPdfEtiquetasGondolaProdutos(
  List<({String nome, String codigo, double preco})> itens,
) async {
  final doc = pw.Document();
  const porLinha = 3;
  const alturaEtiqueta = 88.0;

  String fmtMoeda(double v) =>
      'R\$ ${v.toStringAsFixed(2).replaceAll('.', ',')}';

  String sanitizarCode128(String raw) {
    final b = StringBuffer();
    for (final c in raw.runes) {
      if (c >= 32 && c <= 126) {
        b.writeCharCode(c);
      }
      if (b.length >= 80) break;
    }
    final s = b.toString().trim();
    return s.isEmpty ? '-' : s;
  }

  pw.Widget etiqueta(({String nome, String codigo, double preco}) e) {
    final codigoSeguro = sanitizarCode128(e.codigo);
    return pw.Container(
      height: alturaEtiqueta,
      padding: const pw.EdgeInsets.all(6),
      decoration: pw.BoxDecoration(
        border: pw.Border.all(color: PdfColors.grey700, width: 1),
        borderRadius: pw.BorderRadius.circular(4),
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.stretch,
        children: [
          pw.Text(
            e.nome.trim().isEmpty ? 'Sem nome' : e.nome,
            maxLines: 2,
            style: pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold),
          ),
          pw.SizedBox(height: 4),
          pw.Center(
            child: pw.BarcodeWidget(
              barcode: Barcode.code128(),
              data: codigoSeguro,
              width: 120,
              height: 28,
              drawText: true,
            ),
          ),
          pw.Spacer(),
          pw.Center(
            child: pw.Text(
              fmtMoeda(e.preco),
              style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold),
            ),
          ),
        ],
      ),
    );
  }

  final linhas = <List<({String nome, String codigo, double preco})>>[];
  for (var i = 0; i < itens.length; i += porLinha) {
    linhas.add(
      itens.sublist(
        i,
        i + porLinha > itens.length ? itens.length : i + porLinha,
      ),
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
                ],
              ),
            ),
        ];
      },
    ),
  );

  return doc.save();
}
