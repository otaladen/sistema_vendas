import 'dart:typed_data';

import 'package:syncfusion_flutter_pdf/pdf.dart';

import '../domain/lista_preco_externa_pdf_parser.dart';

/// Extrai texto do PDF e devolve itens da tabela de precos.
abstract final class ListaPrecoExternaPdfService {
  ListaPrecoExternaPdfService._();

  static ListaPrecoExternaParseResult importarBytes(
    Uint8List bytes, {
    String arquivoOrigem = '',
    String nomeLojaPadrao = 'Comprou Levou',
  }) {
    final doc = PdfDocument(inputBytes: bytes);
    try {
      final texto = PdfTextExtractor(doc).extractText();
      return ListaPrecoExternaPdfParser.parseTexto(
        texto,
        arquivoOrigem: arquivoOrigem,
        nomeLojaPadrao: nomeLojaPadrao,
      );
    } finally {
      doc.dispose();
    }
  }
}
