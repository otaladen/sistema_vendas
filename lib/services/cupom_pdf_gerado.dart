import 'dart:typed_data';

import 'package:pdf/pdf.dart';

import '../model/config_layout_impressao.dart';

/// PDF gerado com o [PdfPageFormat] usado na pagina (impressao direta na bobina).
class CupomPdfGerado {
  const CupomPdfGerado({
    required this.bytes,
    required this.pageFormat,
    required this.layout,
  });

  final Uint8List bytes;
  final PdfPageFormat pageFormat;
  final ConfigLayoutImpressao layout;
}
