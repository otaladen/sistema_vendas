import 'dart:typed_data';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../model/cliente.dart';
import '../model/config_layout_impressao.dart';

/// Layout compacto para cupom/orcamento em bobina 80 mm (menos papel).
class CupomPdfLayout {
  CupomPdfLayout._();

  static const double larguraBobinaMm = 80;
  static const double espacoBlocoMm = 2.5;

  static double _margemPagina(ConfigLayoutImpressao layout) =>
      layout.margemPaginaMm.clamp(1, 8);

  static double _margemCorte(ConfigLayoutImpressao layout) =>
      layout.margemCorteMm.clamp(0, 12);

  static double _fatorEspaco(ConfigLayoutImpressao layout) {
    var f = layout.fatorEspacoVertical.clamp(0.4, 1.3);
    if (layout.espacoCompacto) f *= 0.65;
    return f;
  }

  static double _espacoBloco(ConfigLayoutImpressao layout) =>
      espacoBlocoMm * _fatorEspaco(layout);

  static double _espacoItem(ConfigLayoutImpressao layout) =>
      layout.espacoEntreItensMm.clamp(0.5, 4) * _fatorEspaco(layout);

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
    int? flexEsquerda,
  }) {
    final fs = fontSize ?? layout.tamanhoFonteItens.fontSizeItem;
    final estiloEsq = estilo(layout, fontSize: fs, fontWeight: fontWeight);
    final estiloDir = estilo(
      layout,
      fontSize: fs,
      fontWeight: fontWeightDireita ?? fontWeight,
    );

    if (direita.isEmpty) {
      return pw.Text(
        esquerda,
        style: estiloEsq,
        softWrap: true,
        maxLines: 4,
      );
    }

    if (layout.reservarColunaValorFixa) {
      final wValor = layout.larguraColunaValorMm.clamp(20, 40) * PdfPageFormat.mm;
      return pw.Row(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Expanded(
            child: pw.Text(
              esquerda,
              style: estiloEsq,
              softWrap: true,
              maxLines: 4,
            ),
          ),
          pw.SizedBox(
            width: wValor,
            child: pw.Text(
              direita,
              style: estiloDir,
              textAlign: pw.TextAlign.right,
              softWrap: false,
            ),
          ),
        ],
      );
    }

    final flexEsq = (flexEsquerda ?? layout.flexColunaEsquerda).clamp(2, 7);
    final flexDir = (10 - flexEsq).clamp(1, 10);
    return pw.Row(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Expanded(
          flex: flexEsq,
          child: pw.Text(
            esquerda,
            style: estiloEsq,
            softWrap: true,
            maxLines: 3,
          ),
        ),
        pw.Expanded(
          flex: flexDir,
          child: pw.Text(
            direita,
            style: estiloDir,
            textAlign: pw.TextAlign.right,
            softWrap: false,
          ),
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
    String sufixoEntrega = '',
  }) {
    final nomeLinha = sufixoEntrega.isEmpty
        ? nomeProduto
        : '$nomeProduto$sufixoEntrega';
    final fsNome = layout.tamanhoFonteItens.fontSizeItem;
    final fsDet = layout.tamanhoFonteItens.fontSizeItemDetalhe;

    final padItem = _espacoItem(layout);
    if (!layout.colunasEsquerdaDireita) {
      return pw.Padding(
        padding: pw.EdgeInsets.only(bottom: padItem),
        child: pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Text(
              nomeLinha,
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
      padding: pw.EdgeInsets.only(bottom: padItem),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.stretch,
        children: [
          linhaColunas(
            layout: layout,
            esquerda: nomeLinha,
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
    final estiloLinha = estilo(layout, fontSize: fs, fontWeight: negrito);

    if (!usarColunas) {
      return pw.Padding(
        padding: pw.EdgeInsets.only(bottom: 0.5 * PdfPageFormat.mm),
        child: pw.Text(
          '$rotulo $valor',
          style: estiloLinha,
        ),
      );
    }

    // Valor longo (ex.: pagamento misto) — rotulo em linha propria evita quebrar "Pagamento:".
    if (valor.length > 32) {
      return pw.Padding(
        padding: pw.EdgeInsets.only(bottom: 0.5 * PdfPageFormat.mm),
        child: pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.stretch,
          children: [
            pw.Text(rotulo, style: estiloLinha),
            pw.SizedBox(height: 0.3 * PdfPageFormat.mm),
            pw.Text(valor, style: estiloLinha),
          ],
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
    final hLogo = layout.alturaLogoMm.clamp(20.0, 52.0);
    return [
      if (temLogo)
        pw.Center(
          child: pw.Padding(
            padding: pw.EdgeInsets.only(bottom: 2 * PdfPageFormat.mm),
            child: pw.Image(pw.MemoryImage(logo), height: hLogo),
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

  /// Cabecalho do orcamento (sem entrega; cliente/vendedor opcionais).
  static int contarLinhasCabecalhoOrcamento({
    required ConfigLayoutImpressao layout,
    required bool temCliente,
    required bool temVendedor,
    Cliente? cliente,
  }) {
    var n = 3;
    if (temCliente) {
      n++;
      if (layout.exibirDocumentoCliente &&
          (cliente?.documento.trim().isNotEmpty ?? false)) {
        n++;
      }
      if (layout.exibirTelefoneCliente &&
          (cliente?.telefone.trim().isNotEmpty ?? false)) {
        n++;
      }
    }
    if (temVendedor && layout.exibirVendedor) n++;
    if (layout.exibirValidadeOrcamento) n += 2;
    return n;
  }

  static int contarLinhasExtrasOrcamento({
    required ConfigLayoutImpressao layout,
    required bool temDesconto,
    required bool temFrete,
    String textoRodape = '',
  }) {
    var n = 13;
    if (layout.divisoriaDestaqueAntesTotais) n++;
    if (cabecalhoColunasItens(layout) != null) n++;
    if (temDesconto) n++;
    if (temFrete) n++;
    n += linhasTexto(textoRodape).length;
    if (layout.divisoriaAntesRodape && textoRodape.trim().isNotEmpty) n++;
    return n;
  }

  static int unidadesAlturaItensTermico(
    Iterable<String> nomesProduto, {
    int caracteresPorLinha = 24,
  }) {
    var u = 0;
    for (final nome in nomesProduto) {
      final linhasNome =
          (nome.length / caracteresPorLinha).ceil().clamp(1, 4);
      u += linhasNome + 1;
    }
    return u.clamp(0, 999);
  }

  static PdfPageFormat formatoPaginaTermica({
    required ConfigLayoutImpressao layout,
    required int linhasTexto,
    required int qtdItens,
    int linhasExtras = 0,
    bool comLogo = false,
    bool segundaVia = false,
  }) {
    final margem = _margemPagina(layout);
    final corte = _margemCorte(layout);
    final fatorAltura = layout.fatorAlturaPaginaPdf.clamp(0.75, 1.15);
    final fatorEsp = _fatorEspaco(layout);
    final alturaLinhaMm = 3.4 * fatorEsp;
    final alturaItemMm = (5.5 + layout.espacoEntreItensMm) * fatorEsp;
    final blocoCabecalhoMm = 22.0 * fatorEsp;
    var mm = margem * 2 +
        blocoCabecalhoMm +
        linhasTexto * alturaLinhaMm +
        qtdItens * alturaItemMm +
        linhasExtras * alturaLinhaMm;
    if (layout.exibirEspacoFinal) mm += corte;
    if (comLogo) mm += layout.alturaLogoMm.clamp(20, 52) + 4;
    if (segundaVia) mm += 4;
    mm = (mm * fatorAltura).clamp(45.0, 1200.0);
    return PdfPageFormat(
      larguraBobinaMm * PdfPageFormat.mm,
      mm * PdfPageFormat.mm,
      marginTop: margem * PdfPageFormat.mm,
      marginBottom: margem * PdfPageFormat.mm,
      marginLeft: margem * PdfPageFormat.mm,
      marginRight: margem * PdfPageFormat.mm,
    );
  }

  static PdfPageFormat formatoPagina(
    EmpresaModeloPdf modelo, {
    required ConfigLayoutImpressao layout,
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
      layout: layout,
      linhasTexto: linhasTexto,
      qtdItens: qtdItens,
      linhasExtras: linhasExtras,
      comLogo: comLogo,
      segundaVia: segundaVia,
    );
  }

  /// Formato para impressao direta conforme layout (evita papel em branco).
  static PdfPageFormat formatoImpressaoDireta({
    required ConfigLayoutImpressao layout,
    required PdfPageFormat formatoPdf,
  }) {
    switch (layout.modoImpressaoDireta) {
      case LayoutModoImpressaoDireta.driverIlimitado:
        return PdfPageFormat(
          larguraBobinaMm * PdfPageFormat.mm,
          double.infinity,
          marginTop: _margemPagina(layout) * PdfPageFormat.mm,
          marginBottom: _margemPagina(layout) * PdfPageFormat.mm,
          marginLeft: _margemPagina(layout) * PdfPageFormat.mm,
          marginRight: _margemPagina(layout) * PdfPageFormat.mm,
        );
      case LayoutModoImpressaoDireta.altura150:
      case LayoutModoImpressaoDireta.altura200:
        final h = layout.modoImpressaoDireta.alturaFixaMm ?? 150;
        return PdfPageFormat(
          larguraBobinaMm * PdfPageFormat.mm,
          h * PdfPageFormat.mm,
          marginTop: formatoPdf.marginTop,
          marginBottom: formatoPdf.marginBottom,
          marginLeft: formatoPdf.marginLeft,
          marginRight: formatoPdf.marginRight,
        );
      case LayoutModoImpressaoDireta.alturaPdf:
        return formatoPdf;
    }
  }

  @Deprecated('Use formatoImpressaoDireta com layout e formatoPdf')
  static PdfPageFormat formatoImpressaoDiretaBobina() => PdfPageFormat(
        larguraBobinaMm * PdfPageFormat.mm,
        double.infinity,
      );

  static pw.Widget espacoFinalDocumento(ConfigLayoutImpressao layout) {
    if (!layout.exibirEspacoFinal) return pw.SizedBox();
    return pw.Column(
      mainAxisSize: pw.MainAxisSize.min,
      children: [
        espacoBloco(layout),
        pw.SizedBox(height: _margemCorte(layout) * PdfPageFormat.mm),
      ],
    );
  }
}

enum EmpresaModeloPdf { a4, bobina }

EmpresaModeloPdf empresaModeloPdfDeString(String? modelo) {
  return modelo == 'a4' ? EmpresaModeloPdf.a4 : EmpresaModeloPdf.bobina;
}
