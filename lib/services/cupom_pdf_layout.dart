import 'dart:typed_data';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../model/config_layout_impressao.dart';

/// Layout compacto para cupom/orcamento em bobina 80 mm (menos papel).
class CupomPdfLayout {
  CupomPdfLayout._();

  static const double larguraBobinaMm = 80;
  static const double feedCorteMm = 5;
  static const double margemPaginaMm = 4;
  static const double espacoBlocoMm = 2.5;

  static double _espacoBloco(ConfigLayoutImpressao layout) =>
      layout.espacoCompacto ? espacoBlocoMm * 0.65 : espacoBlocoMm;

  static pw.Font _fontePdf(ConfigLayoutImpressao layout) {
    switch (layout.familiaFonte) {
      case LayoutFamiliaFonte.courier:
        return pw.Font.courier();
      case LayoutFamiliaFonte.times:
        return pw.Font.times();
      case LayoutFamiliaFonte.helvetica:
        return pw.Font.helvetica();
    }
  }

  static pw.TextStyle estilo(
    ConfigLayoutImpressao layout, {
    required double fontSize,
    pw.FontWeight fontWeight = pw.FontWeight.normal,
  }) {
    return pw.TextStyle(
      font: _fontePdf(layout),
      fontSize: fontSize,
      fontWeight: fontWeight,
    );
  }

  /// Texto de corpo (cliente, venda, observacoes).
  static pw.Widget textoCorpo(
    String texto,
    ConfigLayoutImpressao layout, {
    pw.FontWeight fontWeight = pw.FontWeight.normal,
    double? fontSize,
  }) {
    return pw.Text(
      texto,
      style: estilo(
        layout,
        fontSize: fontSize ?? layout.tamanhoFonteCorpo.fontSizeCorpo,
        fontWeight: fontWeight,
      ),
    );
  }

  static pw.Widget espacoBloco(ConfigLayoutImpressao layout) =>
      pw.SizedBox(height: _espacoBloco(layout) * PdfPageFormat.mm);

  static pw.Widget divisoriaSecao({
    required ConfigLayoutImpressao layout,
    bool destaque = false,
  }) {
    final caractere =
        destaque ? layout.caractereDestaque : layout.caractereSimples;
    final linha = caractere * layout.comprimentoDivisoria.caracteres;
    return pw.Padding(
      padding: pw.EdgeInsets.symmetric(
        vertical: _espacoBloco(layout) * 0.65 * PdfPageFormat.mm,
      ),
      child: pw.Center(
        child: pw.Text(
          linha,
          style: estilo(
            layout,
            fontSize: layout.tamanhoFonteCorpo.fontSizeContato,
          ),
          textAlign: pw.TextAlign.center,
        ),
      ),
    );
  }

  static List<String> linhasTexto(String texto) {
    return texto
        .replaceAll(RegExp(r'\r\n?'), '\n')
        .split('\n')
        .map((l) => l.trim())
        .where((l) => l.isNotEmpty)
        .toList();
  }

  static pw.Widget tituloSecao(String texto, ConfigLayoutImpressao layout) {
    return pw.Padding(
      padding: pw.EdgeInsets.only(top: _espacoBloco(layout) * PdfPageFormat.mm),
      child: pw.Text(
        texto,
        style: estilo(
          layout,
          fontSize: layout.tamanhoFonteCorpo.fontSizeCorpo,
          fontWeight: pw.FontWeight.bold,
        ),
      ),
    );
  }

  static pw.Widget linhaColunas({
    required ConfigLayoutImpressao layout,
    required String esquerda,
    required String direita,
    double? fontSize,
    pw.FontWeight fontWeight = pw.FontWeight.normal,
    pw.FontWeight? fontWeightDireita,
    int flexEsquerda = 3,
  }) {
    final fs = fontSize ?? layout.tamanhoFonteItens.fontSizeItem;
    final estiloEsq = estilo(layout, fontSize: fs, fontWeight: fontWeight);
    final estiloDir = estilo(
      layout,
      fontSize: fs,
      fontWeight: fontWeightDireita ?? fontWeight,
    );
    return pw.Row(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Expanded(
          flex: flexEsquerda,
          child: pw.Text(esquerda, style: estiloEsq),
        ),
        if (direita.isNotEmpty)
          pw.Text(
            direita,
            style: estiloDir,
            textAlign: pw.TextAlign.right,
          ),
      ],
    );
  }

  static pw.Widget? cabecalhoColunasItens(ConfigLayoutImpressao layout) {
    if (!layout.cabecalhoColunasItens || !layout.colunasEsquerdaDireita) {
      return null;
    }
    return pw.Padding(
      padding: pw.EdgeInsets.only(bottom: 1.5 * PdfPageFormat.mm),
      child: linhaColunas(
        layout: layout,
        esquerda: 'DESCRICAO',
        direita: 'VALOR',
        fontSize: layout.tamanhoFonteItens.fontSizeItemDetalhe + 0.5,
        fontWeight: pw.FontWeight.bold,
      ),
    );
  }

  static pw.Widget itemVenda({
    required ConfigLayoutImpressao layout,
    required String nomeProduto,
    required int quantidade,
    required double precoUnitario,
    required double subtotal,
    required String Function(double) formatarMoeda,
  }) {
    final fsNome = layout.tamanhoFonteItens.fontSizeItem;
    final fsDet = layout.tamanhoFonteItens.fontSizeItemDetalhe;

    if (!layout.colunasEsquerdaDireita) {
      return pw.Padding(
        padding: const pw.EdgeInsets.only(bottom: 2.5),
        child: pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Text(
              nomeProduto,
              style: estilo(layout, fontSize: fsNome),
            ),
            if (layout.linhaQuantidadePreco)
              pw.Text(
                '$quantidade x ${formatarMoeda(precoUnitario)} = ${formatarMoeda(subtotal)}',
                style: estilo(layout, fontSize: fsDet),
              ),
          ],
        ),
      );
    }

    return pw.Padding(
      padding: const pw.EdgeInsets.only(bottom: 2.5),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.stretch,
        children: [
          linhaColunas(
            layout: layout,
            esquerda: nomeProduto,
            direita: formatarMoeda(subtotal),
            fontSize: fsNome,
            fontWeightDireita: pw.FontWeight.bold,
          ),
          if (layout.linhaQuantidadePreco) ...[
            pw.SizedBox(height: 0.4 * PdfPageFormat.mm),
            linhaColunas(
              layout: layout,
              esquerda: '$quantidade x ${formatarMoeda(precoUnitario)}',
              direita: '',
              fontSize: fsDet,
            ),
          ],
        ],
      ),
    );
  }

  static pw.Widget linhaTotal({
    required ConfigLayoutImpressao layout,
    required String rotulo,
    required String valor,
    double? fontSize,
    bool destaque = false,
    bool? colunas,
  }) {
    final fs = fontSize ??
        (destaque
            ? layout.tamanhoFonteTotais.fontSizeTotalDestaque
            : layout.tamanhoFonteTotais.fontSizeTotais);
    final usarColunas = colunas ?? layout.alinharTotaisColunas;
    final negrito = destaque ? pw.FontWeight.bold : pw.FontWeight.normal;
    if (!usarColunas) {
      return pw.Padding(
        padding: pw.EdgeInsets.only(bottom: 0.5 * PdfPageFormat.mm),
        child: pw.Text(
          '$rotulo $valor',
          style: estilo(layout, fontSize: fs, fontWeight: negrito),
        ),
      );
    }
    return pw.Padding(
      padding: pw.EdgeInsets.only(bottom: 0.5 * PdfPageFormat.mm),
      child: linhaColunas(
        layout: layout,
        esquerda: rotulo,
        direita: valor,
        fontSize: fs,
        fontWeight: negrito,
        fontWeightDireita: negrito,
      ),
    );
  }

  static pw.Widget _textoCentralizado(
    ConfigLayoutImpressao layout, {
    required String texto,
    required double fontSize,
    pw.FontWeight fontWeight = pw.FontWeight.normal,
  }) {
    return pw.Center(
      child: pw.Text(
        texto,
        textAlign: pw.TextAlign.center,
        style: estilo(layout, fontSize: fontSize, fontWeight: fontWeight),
      ),
    );
  }

  static List<pw.Widget> cabecalhoEmpresa({
    required ConfigLayoutImpressao layout,
    required String nomeLoja,
    Uint8List? logoBytes,
    String? telefone,
    String? endereco,
  }) {
    final logo = logoBytes;
    final temLogo = layout.exibirLogo && logo != null && logo.isNotEmpty;
    final fsNome = layout.tamanhoNomeLoja.fontSizeNome;
    final fsContato = layout.tamanhoFonteCorpo.fontSizeContato;
    return [
      if (temLogo)
        pw.Center(
          child: pw.Padding(
            padding: const pw.EdgeInsets.only(bottom: 3),
            child: pw.Image(pw.MemoryImage(logo), height: 40),
          ),
        ),
      _textoCentralizado(
        layout,
        texto: nomeLoja.trim().isEmpty ? 'Loja' : nomeLoja.trim(),
        fontSize: fsNome,
        fontWeight: pw.FontWeight.bold,
      ),
      if (layout.exibirTelefone &&
          telefone != null &&
          telefone.trim().isNotEmpty)
        _textoCentralizado(
          layout,
          texto: 'Tel: ${telefone.trim()}',
          fontSize: fsContato,
        ),
      if (layout.exibirEndereco &&
          endereco != null &&
          endereco.trim().isNotEmpty)
        _textoCentralizado(
          layout,
          texto: endereco.trim(),
          fontSize: fsContato,
        ),
    ];
  }

  static pw.Widget faixaTipoDocumento({
    required ConfigLayoutImpressao layout,
    required String titulo,
    String? subtitulo,
  }) {
    final fsTitulo = layout.tamanhoFonteCorpo.fontSizeTipoDocumento;
    final fsSub = layout.tamanhoFonteCorpo.fontSizeContato;
    final tituloWidget = _textoCentralizado(
      layout,
      texto: titulo,
      fontSize: fsTitulo,
      fontWeight: pw.FontWeight.bold,
    );
    if (!layout.faixaComDivisorias) {
      return pw.Column(
        children: [
          tituloWidget,
          if (subtitulo != null && subtitulo.trim().isNotEmpty)
            pw.Padding(
              padding: pw.EdgeInsets.only(top: 1.5 * PdfPageFormat.mm),
              child: _textoCentralizado(
                layout,
                texto: subtitulo.trim(),
                fontSize: fsSub,
                fontWeight: layout.destacarSegundaVia
                    ? pw.FontWeight.bold
                    : pw.FontWeight.normal,
              ),
            ),
        ],
      );
    }
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.stretch,
      children: [
        divisoriaSecao(layout: layout),
        tituloWidget,
        if (subtitulo != null && subtitulo.trim().isNotEmpty) ...[
          pw.SizedBox(height: 1.5 * PdfPageFormat.mm),
          _textoCentralizado(
            layout,
            texto: subtitulo.trim(),
            fontSize: fsSub,
            fontWeight: layout.destacarSegundaVia
                ? pw.FontWeight.bold
                : pw.FontWeight.normal,
          ),
        ],
        divisoriaSecao(layout: layout),
      ],
    );
  }

  static List<pw.Widget> rodapeDocumento({
    required ConfigLayoutImpressao layout,
    required String textoRodape,
  }) {
    final linhas = linhasTexto(textoRodape);
    if (linhas.isEmpty) return const [];
    final fs = layout.tamanhoFonteCorpo.fontSizeRodape;
    return [
      if (layout.divisoriaAntesRodape)
        divisoriaSecao(layout: layout, destaque: true),
      ...linhas.map(
        (l) => _textoCentralizado(
          layout,
          texto: l,
          fontSize: fs,
        ),
      ),
    ];
  }

  static PdfPageFormat formatoPaginaTermica({
    required int linhasTexto,
    required int qtdItens,
    int linhasExtras = 0,
    bool comLogo = false,
    bool segundaVia = false,
  }) {
    const alturaLinhaMm = 3.6;
    const alturaItemMm = 7.0;
    const blocoCabecalhoMm = 26.0;
    var mm = margemPaginaMm * 2 +
        blocoCabecalhoMm +
        linhasTexto * alturaLinhaMm +
        qtdItens * alturaItemMm +
        linhasExtras * alturaLinhaMm +
        feedCorteMm;
    if (comLogo) mm += 14;
    if (segundaVia) mm += 5;
    mm = mm.clamp(55.0, 1200.0);
    return PdfPageFormat(
      larguraBobinaMm * PdfPageFormat.mm,
      mm * PdfPageFormat.mm,
      marginTop: margemPaginaMm * PdfPageFormat.mm,
      marginBottom: margemPaginaMm * PdfPageFormat.mm,
      marginLeft: margemPaginaMm * PdfPageFormat.mm,
      marginRight: margemPaginaMm * PdfPageFormat.mm,
    );
  }

  static PdfPageFormat formatoPagina(
    EmpresaModeloPdf modelo, {
    required int linhasTexto,
    required int qtdItens,
    int linhasExtras = 0,
    bool comLogo = false,
    bool segundaVia = false,
  }) {
    if (modelo == EmpresaModeloPdf.a4) {
      return PdfPageFormat.a4;
    }
    return formatoPaginaTermica(
      linhasTexto: linhasTexto,
      qtdItens: qtdItens,
      linhasExtras: linhasExtras,
      comLogo: comLogo,
      segundaVia: segundaVia,
    );
  }
}

enum EmpresaModeloPdf { a4, bobina }

EmpresaModeloPdf empresaModeloPdfDeString(String? modelo) {
  return modelo == 'a4' ? EmpresaModeloPdf.a4 : EmpresaModeloPdf.bobina;
}
