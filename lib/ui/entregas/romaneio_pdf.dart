import 'dart:typed_data';

import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../../model/venda.dart';
import 'logistica_entregas.dart';

/// Formato de pagina do PDF do romaneio de entregas.
enum RomaneioPdfLayout {
  /// Pagina A4 (padrao).
  a4,

  /// Bobina termica 80 mm (altura continua).
  bobina80mm,
}

Future<Uint8List> gerarEntregasRomaneioPdfBytes({
  required List<Venda> entregasDia,
  required String tituloPeriodo,
  required DateTime emissao,
  required pw.Widget Function(Venda venda) pdfUmaEntrega,
  RomaneioPdfLayout layout = RomaneioPdfLayout.a4,
}) async {
  final doc = pw.Document();
  final horaEmissao = DateFormat('dd/MM/yyyy HH:mm').format(emissao);
  final bobina = layout == RomaneioPdfLayout.bobina80mm;
  final pageFormat = bobina
      ? PdfPageFormat(80 * PdfPageFormat.mm, double.infinity)
      : PdfPageFormat.a4;

  final fsTitulo = bobina ? 10.0 : 16.0;
  final fsMeta = bobina ? 7.5 : 12.0;
  final fsGrupoTitulo = bobina ? 7.8 : 11.0;
  final fsGrupoSub = bobina ? 7.0 : 9.5;
  final padGrupo = bobina ? 4.0 : 6.0;
  final gapGrupoBottom = bobina ? 5.0 : 8.0;
  final gapAposTitulo = bobina ? 3.0 : 4.0;
  final gapAntesLista = bobina ? 6.0 : 10.0;

  doc.addPage(
    pw.Page(
      pageFormat: pageFormat,
      margin: bobina ? const pw.EdgeInsets.all(8) : null,
      build: (context) {
        return pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Text(
              'Romaneio de Entregas - $tituloPeriodo',
              style: pw.TextStyle(
                fontSize: fsTitulo,
                fontWeight: pw.FontWeight.bold,
              ),
            ),
            pw.SizedBox(height: gapAposTitulo),
            pw.Text(
              'Emitido em: $horaEmissao',
              style: pw.TextStyle(fontSize: fsMeta),
            ),
            pw.Text(
              'Total de entregas: ${entregasDia.length}',
              style: pw.TextStyle(fontSize: fsMeta),
            ),
            if (bobina)
              pw.Text(
                'Formato: bobina 80 mm',
                style: pw.TextStyle(fontSize: fsMeta - 0.5),
              ),
            pw.SizedBox(height: gapAntesLista),
            pw.Divider(thickness: bobina ? 0.6 : 1.0),
            ...blocosEntregaComCarretoAgrupado(entregasDia).expand((bloco) {
              if (bloco.length >= 2 && bloco.first.grupoEntregaFreteId > 0) {
                return [
                  pw.Container(
                    margin: pw.EdgeInsets.only(bottom: gapGrupoBottom),
                    padding: pw.EdgeInsets.all(padGrupo),
                    decoration: pw.BoxDecoration(
                      border: pw.Border.all(width: bobina ? 0.5 : 0.7),
                    ),
                    child: pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.start,
                      children: [
                        pw.Text(
                          rotuloGrupoLogistica(bloco),
                          style: pw.TextStyle(
                            fontWeight: pw.FontWeight.bold,
                            fontSize: fsGrupoTitulo,
                          ),
                        ),
                        pw.Text(
                          '${bloco.length} pedidos no mesmo veiculo',
                          style: pw.TextStyle(fontSize: fsGrupoSub),
                        ),
                        pw.SizedBox(height: bobina ? 3 : 4),
                        ...bloco.map(pdfUmaEntrega),
                      ],
                    ),
                  ),
                ];
              }
              return bloco.map(pdfUmaEntrega);
            }),
          ],
        );
      },
    ),
  );
  return doc.save();
}
