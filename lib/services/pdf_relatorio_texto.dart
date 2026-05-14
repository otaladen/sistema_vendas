import 'dart:typed_data';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

/// PDF leve: uma pagina por bloco de texto (Courier).
Future<Uint8List> gerarPdfRelatorioTextoPaginas(List<String> conteudoPorPagina) async {
  final doc = pw.Document();
  final f = pw.Font.courier();
  final estilo = pw.TextStyle.defaultStyle().copyWith(
    fontSize: 7,
    fontNormal: f,
    fontBold: pw.Font.courierBold(),
    fontItalic: pw.Font.courierOblique(),
    fontBoldItalic: pw.Font.courierBoldOblique(),
    lineSpacing: 0.35,
    height: 1.05,
  );
  final pages =
      conteudoPorPagina.isEmpty ? <String>['(sem linhas para exibir)'] : conteudoPorPagina;
  for (final texto in pages) {
    doc.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(32),
        build: (_) => pw.Text(texto, style: estilo),
      ),
    );
  }
  return doc.save();
}
