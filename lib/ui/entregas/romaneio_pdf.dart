import 'dart:typed_data';

import 'package:intl/intl.dart';
import 'package:pdf/widgets.dart' as pw;

import '../../model/venda.dart';
import 'logistica_entregas.dart';

Future<Uint8List> gerarEntregasRomaneioPdfBytes({
  required List<Venda> entregasDia,
  required String tituloPeriodo,
  required DateTime emissao,
  required pw.Widget Function(Venda venda) pdfUmaEntrega,
}) async {
  final doc = pw.Document();
  final horaEmissao = DateFormat('dd/MM/yyyy HH:mm').format(emissao);
  doc.addPage(
    pw.Page(
      build: (context) {
        return pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Text(
              'Romaneio de Entregas - $tituloPeriodo',
              style: pw.TextStyle(
                fontSize: 16,
                fontWeight: pw.FontWeight.bold,
              ),
            ),
            pw.SizedBox(height: 4),
            pw.Text('Emitido em: $horaEmissao'),
            pw.Text('Total de entregas: ${entregasDia.length}'),
            pw.SizedBox(height: 10),
            pw.Divider(),
            ...blocosEntregaComCarretoAgrupado(entregasDia).expand((bloco) {
              if (bloco.length >= 2 && bloco.first.grupoEntregaFreteId > 0) {
                return [
                  pw.Container(
                    margin: const pw.EdgeInsets.only(bottom: 8),
                    padding: const pw.EdgeInsets.all(6),
                    decoration: pw.BoxDecoration(
                      border: pw.Border.all(width: 0.7),
                    ),
                    child: pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.start,
                      children: [
                        pw.Text(
                          rotuloGrupoLogistica(bloco),
                          style: pw.TextStyle(
                            fontWeight: pw.FontWeight.bold,
                            fontSize: 11,
                          ),
                        ),
                        pw.Text(
                          '${bloco.length} pedidos no mesmo veiculo',
                          style: const pw.TextStyle(fontSize: 9.5),
                        ),
                        pw.SizedBox(height: 4),
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
