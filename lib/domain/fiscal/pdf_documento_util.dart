import 'dart:typed_data';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

/// Utilitarios leves para PDFs fiscais baixados (ex.: DANFE Focus).
class PdfDocumentoUtil {
  PdfDocumentoUtil._();

  /// Conta paginas em um PDF existente (heuristica sobre objetos /Page).
  static int contarPaginas(Uint8List bytes) {
    final text = String.fromCharCodes(bytes);
    final re = RegExp(r'/Type\s*/Page[^s]');
    return re.allMatches(text).length.clamp(1, 99);
  }

  /// Extrai paginas (0-based) rasterizando e remontando um PDF de uma folha cada.
  static Future<Uint8List> extrairPaginas(
    Uint8List bytes, {
    required List<int> indices,
    double dpi = 200,
  }) async {
    if (indices.isEmpty) return bytes;
    final doc = pw.Document();
    await for (final raster in Printing.raster(
      bytes,
      pages: indices,
      dpi: dpi,
    )) {
      final png = await raster.toPng();
      final wPt = raster.width * 72.0 / dpi;
      final hPt = raster.height * 72.0 / dpi;
      doc.addPage(
        pw.Page(
          pageFormat: PdfPageFormat(wPt, hPt, marginAll: 0),
          margin: pw.EdgeInsets.zero,
          build: (_) => pw.Center(
            child: pw.Image(
              pw.MemoryImage(png),
              width: wPt,
              height: hPt,
              fit: pw.BoxFit.fill,
            ),
          ),
        ),
      );
    }
    return doc.save();
  }
}
