import 'dart:typed_data';

import 'package:barcode/barcode.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../config/fiscal_config.dart';
import '../model/cliente.dart';
import '../model/config_layout_impressao.dart';

/// Layout compacto para cupom/orcamento em bobina 80 mm (menos papel).
class CupomPdfLayout {
  CupomPdfLayout._();

  /// Largura do papel na bobina (referencia).
  static const double larguraPapelBobinaMm = 80;

  @Deprecated('Use larguraPdfMm(layout) — area imprimivel da MP-4200 e similares.')
  static const double larguraBobinaMm = larguraPapelBobinaMm;

  /// Folga extra na altura do PDF termico (evita corte na impressora).
  static const double margemSegurancaAlturaBobinaMm = 14;

  /// Largura do PDF = area imprimivel (72 mm na Bematech MP-4200 TH em papel 80 mm).
  static double larguraPdfMm(ConfigLayoutImpressao layout) =>
      layout.larguraPaginaPdfMm.clamp(68, 80);

  static double larguraUtilConteudoMm(ConfigLayoutImpressao layout) {
    final pdf = larguraPdfMm(layout);
    final margens = _margemPagina(layout) * 2;
    return (pdf - margens).clamp(48, pdf);
  }

  static double _larguraColunaValorEfetivaMm(ConfigLayoutImpressao layout) {
    final util = larguraUtilConteudoMm(layout);
    final maxValor = util * 0.48;
    return layout.larguraColunaValorMm.clamp(22, maxValor);
  }
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
        // Helvetica embutida no dart_pdf nao renderiza acentos PT-BR.
        return pw.Font.courier();
    }
  }

  static pw.Font _fontePdfBold(ConfigLayoutImpressao layout) {
    switch (layout.familiaFonte) {
      case LayoutFamiliaFonte.courier:
        return pw.Font.courierBold();
      case LayoutFamiliaFonte.times:
        return pw.Font.timesBold();
      case LayoutFamiliaFonte.helvetica:
        return pw.Font.courierBold();
    }
  }

  /// Documento PDF com tema alinhado ao layout (evita Helvetica padrao sem Unicode).
  static pw.Document criarDocumento(ConfigLayoutImpressao layout) {
    return pw.Document(
      theme: pw.ThemeData.withFont(
        base: _fontePdf(layout),
        bold: _fontePdfBold(layout),
      ),
    );
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

  /// Tracejado de ponta a ponta na area util da bobina (estilo cupom termico).
  static String linhaDivisoriaCompleta(ConfigLayoutImpressao layout) {
    final raw = layout.caractereSimples.trim();
    final c = raw.isEmpty ? '-' : raw[0];
    final fs = layout.tamanhoFonteCorpo.fontSizeContato;
    final larguraMm = larguraUtilConteudoMm(layout);
    final mmPorCaractere = (fs * 0.14 + 0.38).clamp(0.85, 1.45);
    final n = (larguraMm / mmPorCaractere).floor().clamp(32, 80);
    return c * n;
  }

  static pw.Widget divisoriaSecao({
    required ConfigLayoutImpressao layout,
    bool destaque = false,
    bool compacta = false,
  }) {
    final linha = linhaDivisoriaCompleta(layout);
    final fatorVertical = compacta ? 0.12 : 0.3;
    return pw.Padding(
      padding: pw.EdgeInsets.symmetric(
        vertical: _espacoBloco(layout) * fatorVertical * PdfPageFormat.mm,
      ),
      child: pw.SizedBox(
        width: larguraUtilConteudoMm(layout) * PdfPageFormat.mm,
        child: pw.Text(
          linha,
          style: estilo(
            layout,
            fontSize: layout.tamanhoFonteCorpo.fontSizeContato,
          ),
          textAlign: pw.TextAlign.center,
          maxLines: 1,
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
      final wValor = _larguraColunaValorEfetivaMm(layout) * PdfPageFormat.mm;
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
            child: _textoValorBobina(direita, estiloDir),
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
          child: _textoValorBobina(direita, estiloDir),
        ),
      ],
    );
  }

  /// Valores (R\$) encolhem se necessario — evita corte na margem direita da termica.
  static pw.Widget _textoValorBobina(String texto, pw.TextStyle style) {
    final fs = style.fontSize ?? 9;
    return pw.SizedBox(
      height: fs * 1.2,
      child: pw.FittedBox(
        fit: pw.BoxFit.scaleDown,
        alignment: pw.Alignment.topRight,
        child: pw.Text(
          texto,
          style: style,
          textAlign: pw.TextAlign.right,
          maxLines: 1,
        ),
      ),
    );
  }

  /// Linha rotulo/valor compacta para totais no estilo legado (sem folga vertical).
  static pw.Widget linhaResumoLegadoLdv({
    required ConfigLayoutImpressao layout,
    required String rotulo,
    required String valor,
    double? fontSize,
    pw.FontWeight fontWeight = pw.FontWeight.normal,
    pw.FontWeight? fontWeightValor,
  }) {
    final fs = fontSize ?? layout.tamanhoFonteTotais.fontSizeTotais;
    final pesoVal = fontWeightValor ?? fontWeight;
    final estiloEsq = estilo(layout, fontSize: fs, fontWeight: fontWeight);
    final estiloVal = estilo(layout, fontSize: fs, fontWeight: pesoVal);
    final wValor = _larguraColunaValorEfetivaMm(layout) * PdfPageFormat.mm;
    return pw.Padding(
      padding: pw.EdgeInsets.symmetric(vertical: 0.12 * PdfPageFormat.mm),
      child: pw.Row(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Expanded(
            child: pw.Text(
              rotulo,
              style: estiloEsq,
              maxLines: 2,
              softWrap: true,
            ),
          ),
          pw.SizedBox(
            width: wValor,
            child: pw.Text(
              valor,
              style: estiloVal,
              textAlign: pw.TextAlign.right,
              maxLines: 1,
            ),
          ),
        ],
      ),
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
    String? quantidadeExibicao,
    String sufixoEntrega = '',
  }) {
    final qtdTxt = quantidadeExibicao ?? '$quantidade';
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
                '$qtdTxt x ${formatarMoeda(precoUnitario)} = ${formatarMoeda(subtotal)}',
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
              esquerda: '$qtdTxt x ${formatarMoeda(precoUnitario)}',
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
        divisoriaSecao(layout: layout, compacta: true),
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
    var n = layout.espacoCompacto ? 7 : 13;
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
    // Valores < 1 encurtavam a pagina e cortavam o cupom na bobina.
    final fatorAltura = layout.fatorAlturaPaginaPdf < 1.0
        ? 1.0
        : layout.fatorAlturaPaginaPdf.clamp(1.0, 1.2);
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
    mm = mm * fatorAltura + margemSegurancaAlturaBobinaMm;
    mm = mm.clamp(45.0, 1200.0);
    return PdfPageFormat(
      larguraPdfMm(layout) * PdfPageFormat.mm,
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
          larguraPdfMm(layout) * PdfPageFormat.mm,
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
          larguraPdfMm(layout) * PdfPageFormat.mm,
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
        72 * PdfPageFormat.mm,
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

  // --- Layout DANFE NFC-e (contingencia) para cupom nao fiscal ---

  static const String tituloDanfeNfce =
      'Documento Auxiliar da Nota Fiscal de Consumidor Eletronica';

  /// Titulo do cupom legado (duas linhas, como no programa antigo / DANFE).
  static const String tituloDanfeNfceLegadoLinha1 =
      'DANFE NFC-e - DOCUMENTO AUXILIAR';
  static const String tituloDanfeNfceLegadoLinha2 =
      'NOTA FISCAL ELETRONICA PARA CONSUMIDOR FINAL';

  static String urlConsultaNfcePorUf([String? uf]) {
    final u = (uf ?? FiscalConfig.ufEmitente).trim().toUpperCase();
    if (u == 'BA') {
      return 'http://hinternet.sefaz.ba.gov.br/nfce/consulta';
    }
    return 'http://www.sefaz.$u.gov.br/nfce/consulta';
  }

  static String formatarCnpjCupom(String cnpj) {
    final d = cnpj.replaceAll(RegExp(r'\D'), '');
    if (d.length != 14) return cnpj.trim();
    return '${d.substring(0, 2)}.${d.substring(2, 5)}.${d.substring(5, 8)}/'
        '${d.substring(8, 12)}-${d.substring(12)}';
  }

  static String formatarDocumentoConsumidor(String documento) {
    final d = documento.replaceAll(RegExp(r'\D'), '');
    if (d.length == 11) {
      return '${d.substring(0, 3)}.${d.substring(3, 6)}.${d.substring(6, 9)}-'
          '${d.substring(9)}';
    }
    if (d.length == 14) return formatarCnpjCupom(d);
    return documento.trim();
  }

  static String chaveAcessoSomenteDigitos(String chave) =>
      chave.replaceAll(RegExp(r'\D'), '');

  /// Posicao 35 da chave NFC-e: tpEmis 9 = contingencia offline.
  static bool chaveNfceIndicaContingencia(String chave) {
    final d = chaveAcessoSomenteDigitos(chave);
    if (d.length != 44) return false;
    return d[34] == '9';
  }

  static String formatarChaveAcessoGrupos(String chave) {
    final d = chaveAcessoSomenteDigitos(chave);
    if (d.length != 44) return chave.trim();
    final grupos = <String>[];
    for (var i = 0; i < d.length; i += 4) {
      grupos.add(d.substring(i, i + 4));
    }
    return grupos.join(' ');
  }

  /// Chave NFC-e decorativa (44 digitos) derivada do numero da nota/cupom.
  /// Somente aparencia visual no cupom nao fiscal — nao substitui NFC-e real.
  static String gerarChaveAcessoDecorativaNfce({
    required String cnpj,
    required String uf,
    required String numeroNota,
    required String serie,
    DateTime? emissao,
  }) {
    final cuf = codigoUfIbgeNfce(uf).toString().padLeft(2, '0');
    final dt = emissao ?? DateTime.now();
    final aamm =
        '${(dt.year % 100).toString().padLeft(2, '0')}${dt.month.toString().padLeft(2, '0')}';
    final cnpjD = chaveAcessoSomenteDigitos(cnpj).padLeft(14, '0');
    final cnpjFmt = cnpjD.length > 14 ? cnpjD.substring(0, 14) : cnpjD;
    const mod = '65';
    final ser = chaveAcessoSomenteDigitos(serie).padLeft(3, '0');
    final serFmt = ser.length > 3 ? ser.substring(ser.length - 3) : ser;
    final nnf = chaveAcessoSomenteDigitos(numeroNota).padLeft(9, '0');
    final nnfFmt = nnf.length > 9 ? nnf.substring(nnf.length - 9) : nnf;
    const tpEmis = '9';
    final cnf = codigoNumericoDecorativoChaveNfce(numeroNota, cnpjFmt, serFmt);
    final base43 = '$cuf$aamm$cnpjFmt$mod$serFmt$nnfFmt$tpEmis$cnf';
    final dv = digitoVerificadorChaveNfce(base43);
    return '$base43$dv';
  }

  static int codigoUfIbgeNfce(String uf) {
    switch (uf.trim().toUpperCase()) {
      case 'BA':
        return 29;
      case 'SP':
        return 35;
      case 'RJ':
        return 33;
      case 'MG':
        return 31;
      case 'PE':
        return 26;
      case 'CE':
        return 23;
      default:
        return 29;
    }
  }

  static String codigoNumericoDecorativoChaveNfce(
    String numeroNota,
    String cnpj,
    String serie,
  ) {
    final seed = '$numeroNota|$cnpj|$serie';
    var hash = 0;
    for (var i = 0; i < seed.length; i++) {
      hash = (hash * 31 + seed.codeUnitAt(i)) & 0x7fffffff;
    }
    return (hash % 100000000).toString().padLeft(8, '0');
  }

  static int digitoVerificadorChaveNfce(String chave43) {
    if (chave43.length != 43) {
      throw ArgumentError('Chave sem DV deve ter 43 digitos');
    }
    var mult = 2;
    var soma = 0;
    for (var i = chave43.length - 1; i >= 0; i--) {
      soma += int.parse(chave43[i]) * mult;
      mult = mult == 9 ? 2 : mult + 1;
    }
    final resto = soma % 11;
    if (resto == 0 || resto == 1) return 0;
    return 11 - resto;
  }

  static String textoTributosLei12741(double valorTotal) {
    final trib = valorTotal * 0.2892;
    final federal = trib * 0.3847;
    final estadual = trib - federal;
    String fmt(double v) => v.toStringAsFixed(2).replaceAll('.', ',');
    return 'Tributos Totais Incidentes (Lei Federal 12.741/2012): '
        'Federal R\$ ${fmt(federal)} | Estadual R\$ ${fmt(estadual)}';
  }

  static pw.Widget _caixaLogoNfeDanfe(ConfigLayoutImpressao layout) {
    final fs = layout.tamanhoFonteCorpo.fontSizeTipoDocumento;
    return pw.Container(
      width: 14 * PdfPageFormat.mm,
      height: 14 * PdfPageFormat.mm,
      decoration: pw.BoxDecoration(
        border: pw.Border.all(width: 0.8),
      ),
      alignment: pw.Alignment.center,
      child: pw.Column(
        mainAxisAlignment: pw.MainAxisAlignment.center,
        children: [
          pw.Text(
            'NF-e',
            style: estilo(
              layout,
              fontSize: fs + 1,
              fontWeight: pw.FontWeight.bold,
            ),
          ),
          pw.Text(
            'NFC-e',
            style: estilo(
              layout,
              fontSize: fs - 1,
              fontWeight: pw.FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }

  static List<pw.Widget> cabecalhoDanfeNfceContingencia({
    required ConfigLayoutImpressao layout,
    required String razaoSocial,
    required String nomeLoja,
    String cnpj = '',
    String inscricaoEstadual = '',
    Uint8List? logoBytes,
    String? telefone,
    String? endereco,
  }) {
    final logo = logoBytes;
    final temLogoLoja = layout.exibirLogo && logo != null && logo.isNotEmpty;
    final fsNome = layout.tamanhoNomeLoja.fontSizeNome - 1.5;
    final fsCorpo = layout.tamanhoFonteCorpo.fontSizeContato;
    final hLogo = layout.alturaLogoMm.clamp(14.0, 36.0);
    final razao = razaoSocial.trim().isNotEmpty
        ? razaoSocial.trim()
        : (nomeLoja.trim().isEmpty ? 'Loja' : nomeLoja.trim());
    final fantasia = nomeLoja.trim();

    final colEmitente = <pw.Widget>[
      if (cnpj.trim().isNotEmpty)
        pw.Text(
          'CNPJ ${formatarCnpjCupom(cnpj)}',
          style: estilo(layout, fontSize: fsCorpo),
          textAlign: pw.TextAlign.left,
        ),
      pw.Text(
        razao,
        style: estilo(
          layout,
          fontSize: fsNome,
          fontWeight: pw.FontWeight.bold,
        ),
        textAlign: pw.TextAlign.left,
        maxLines: 3,
        softWrap: true,
      ),
      if (fantasia.isNotEmpty &&
          fantasia.toLowerCase() != razao.toLowerCase())
        pw.Text(
          fantasia,
          style: estilo(
            layout,
            fontSize: fsCorpo,
            fontWeight: pw.FontWeight.bold,
          ),
          textAlign: pw.TextAlign.left,
          maxLines: 2,
          softWrap: true,
        ),
      if (layout.exibirEndereco &&
          endereco != null &&
          endereco.trim().isNotEmpty)
        pw.Text(
          endereco.trim(),
          style: estilo(layout, fontSize: fsCorpo - 0.5),
          textAlign: pw.TextAlign.left,
          maxLines: 3,
          softWrap: true,
        ),
      if (inscricaoEstadual.trim().isNotEmpty)
        pw.Text(
          'IE ${inscricaoEstadual.trim()}',
          style: estilo(layout, fontSize: fsCorpo),
          textAlign: pw.TextAlign.left,
        ),
      if (layout.exibirTelefone &&
          telefone != null &&
          telefone.trim().isNotEmpty)
        pw.Text(
          'Tel: ${telefone.trim()}',
          style: estilo(layout, fontSize: fsCorpo - 0.5),
          textAlign: pw.TextAlign.left,
        ),
    ];

    final out = <pw.Widget>[
      pw.Row(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          _caixaLogoNfeDanfe(layout),
          pw.SizedBox(width: 2 * PdfPageFormat.mm),
          pw.Expanded(child: pw.Column(children: colEmitente)),
        ],
      ),
    ];

    if (temLogoLoja) {
      out.add(
        pw.Center(
          child: pw.Padding(
            padding: pw.EdgeInsets.only(top: 1.5 * PdfPageFormat.mm),
            child: pw.Image(pw.MemoryImage(logo), height: hLogo),
          ),
        ),
      );
    }

    return out;
  }

  /// Faixa do cupom interno (visual tipo DANFE, sem ser contingencia SEFAZ).
  static pw.Widget faixaCupomNaoFiscalDanfe({
    required ConfigLayoutImpressao layout,
    String titulo = 'CUPOM NAO FISCAL',
    String subtitulo = 'Controle interno — nao substitui a NFC-e',
  }) =>
      faixaContingenciaNfce(
        layout: layout,
        titulo: titulo,
        subtitulo: subtitulo,
      );

  static pw.Widget faixaContingenciaNfce({
    required ConfigLayoutImpressao layout,
    String titulo = 'EMITIDA EM CONTINGENCIA',
    String subtitulo = 'Pendente de autorizacao',
  }) {
    final fs = layout.tamanhoFonteCorpo.fontSizeCorpo;
    final sub = subtitulo.trim();
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.stretch,
      children: [
        divisoriaSecao(layout: layout, compacta: true),
        pw.SizedBox(height: 0.35 * PdfPageFormat.mm),
        _textoCentralizado(
          layout,
          texto: titulo,
          fontSize: fs,
          fontWeight: pw.FontWeight.bold,
        ),
        if (sub.isNotEmpty) ...[
          pw.SizedBox(height: 0.25 * PdfPageFormat.mm),
          _textoCentralizado(
            layout,
            texto: sub,
            fontSize: fs - 0.5,
            fontWeight: pw.FontWeight.bold,
          ),
        ],
        pw.SizedBox(height: 0.35 * PdfPageFormat.mm),
        divisoriaSecao(layout: layout, compacta: true),
      ],
    );
  }

  /// Aviso de contingencia apos pagamento/troco (programa antigo LDV).
  static pw.Widget faixaContingenciaAposPagamentoLegadoLdv({
    required ConfigLayoutImpressao layout,
    String titulo = 'NOTA EMITIDA EM CONTIGENCIA-AUTORIZACAO PENDENTE',
  }) {
    final fs = layout.tamanhoFonteCorpo.fontSizeCorpo;
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.stretch,
      children: [
        _textoCentralizado(
          layout,
          texto: titulo,
          fontSize: fs,
          fontWeight: pw.FontWeight.bold,
        ),
        pw.SizedBox(height: 0.35 * PdfPageFormat.mm),
      ],
    );
  }

  /// Linhas de endereco no formato do programa antigo (RUA / BAIRRO / CEP|TEL).
  static List<String> linhasEnderecoCupomLegado({
    required String? endereco,
    String? telefone,
    bool exibirTelefone = true,
  }) {
    final end = endereco?.trim() ?? '';
    if (end.isEmpty && (telefone?.trim().isEmpty ?? true)) return [];

    final cepRe = RegExp(r'(\d{5})-?(\d{3})');
    var cep = '';
    var resto = end;
    final cepMatch = cepRe.firstMatch(end);
    if (cepMatch != null) {
      cep = '${cepMatch.group(1)}${cepMatch.group(2)}';
      resto = end.replaceFirst(cepMatch.group(0)!, '').trim();
      resto = resto.replaceAll(RegExp(r'^[\s,\-–|]+'), '').trim();
    }

    final linhas = <String>[];
    if (resto.isNotEmpty) {
      final partes = resto
          .split(' - ')
          .map((e) => e.trim())
          .where((e) => e.isNotEmpty)
          .toList();
      if (partes.length >= 3) {
        linhas.add('RUA: ${partes.first}');
        final cidade = partes.last
            .replaceAll(RegExp(r'\s*-\s*[A-Z]{2}$'), '')
            .trim();
        linhas.add('BAIRRO: ${partes[partes.length - 2]} CIDADE: $cidade');
      } else if (partes.length == 2) {
        linhas.add('RUA: ${partes[0]}');
        linhas.add('CIDADE: ${partes[1]}');
      } else {
        linhas.add('RUA: $resto');
      }
    }

    final tel = telefone?.replaceAll(RegExp(r'\D'), '') ?? '';
    final rodape = <String>[];
    if (cep.isNotEmpty) rodape.add('CEP:$cep');
    if (exibirTelefone && tel.isNotEmpty) rodape.add('TEL:$tel');
    if (rodape.isNotEmpty) linhas.add(rodape.join(' '));

    return linhas;
  }

  static String formatarNumeroDocumentoLegado(String numero) {
    final digits = numero.replaceAll(RegExp(r'\D'), '');
    if (digits.isEmpty) return numero.trim();
    return digits.padLeft(9, '0');
  }

  /// Cabecalho centralizado no estilo do cupom termico antigo (LDV).
  static List<pw.Widget> cabecalhoLegadoLdv({
    required ConfigLayoutImpressao layout,
    required String razaoSocial,
    required String nomeLoja,
    String cnpj = '',
    String inscricaoEstadual = '',
    Uint8List? logoBytes,
    String? telefone,
    String? endereco,
  }) {
    final logo = logoBytes;
    final temLogoLoja = layout.exibirLogo && logo != null && logo.isNotEmpty;
    final fsNome = layout.tamanhoNomeLoja.fontSizeNome - 0.5;
    final fsCorpo = layout.tamanhoFonteCorpo.fontSizeContato - 0.5;
    final hLogo = layout.alturaLogoMm.clamp(10.0, 28.0);
    final razao = razaoSocial.trim().isNotEmpty
        ? razaoSocial.trim()
        : (nomeLoja.trim().isEmpty ? 'Loja' : nomeLoja.trim());

    final out = <pw.Widget>[];
    if (temLogoLoja) {
      out.add(
        pw.Center(
          child: pw.Padding(
            padding: pw.EdgeInsets.only(bottom: 1 * PdfPageFormat.mm),
            child: pw.Image(pw.MemoryImage(logo), height: hLogo),
          ),
        ),
      );
    }

    out.add(
      _textoCentralizado(
        layout,
        texto: razao.toUpperCase(),
        fontSize: fsNome,
        fontWeight: pw.FontWeight.bold,
      ),
    );

    final cnpjD = cnpj.replaceAll(RegExp(r'\D'), '');
    final ie = inscricaoEstadual.trim();
    if (cnpjD.isNotEmpty || ie.isNotEmpty) {
      final partes = <String>[];
      if (cnpjD.isNotEmpty) partes.add('CNPJ: $cnpjD');
      if (ie.isNotEmpty) partes.add('INSC.ESTADUAL: $ie');
      out.add(
        _textoCentralizado(
          layout,
          texto: partes.join(' | '),
          fontSize: fsCorpo,
        ),
      );
    }

    if (layout.exibirEndereco) {
      for (final linha in linhasEnderecoCupomLegado(
        endereco: endereco,
        telefone: telefone,
        exibirTelefone: layout.exibirTelefone,
      )) {
        out.add(
          _textoCentralizado(
            layout,
            texto: linha,
            fontSize: fsCorpo - 0.5,
          ),
        );
      }
    } else if (layout.exibirTelefone &&
        telefone != null &&
        telefone.trim().isNotEmpty) {
      final tel = telefone.replaceAll(RegExp(r'\D'), '');
      if (tel.isNotEmpty) {
        out.add(
          _textoCentralizado(
            layout,
            texto: 'TEL:$tel',
            fontSize: fsCorpo - 0.5,
          ),
        );
      }
    }

    return out;
  }

  /// Titulo em duas linhas (DANFE NFC-e ou cupom interno).
  static pw.Widget faixaTituloDocumentoLegadoLdv({
    required ConfigLayoutImpressao layout,
    required String linha1,
    required String linha2,
  }) {
    final fs = layout.tamanhoFonteCorpo.fontSizeTipoDocumento;
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.stretch,
      children: [
        divisoriaSecao(layout: layout, compacta: true),
        pw.SizedBox(height: 0.35 * PdfPageFormat.mm),
        _textoCentralizado(
          layout,
          texto: linha1,
          fontSize: fs,
          fontWeight: pw.FontWeight.bold,
        ),
        pw.SizedBox(height: 0.25 * PdfPageFormat.mm),
        _textoCentralizado(
          layout,
          texto: linha2,
          fontSize: fs - 0.5,
          fontWeight: pw.FontWeight.bold,
        ),
        pw.SizedBox(height: 0.35 * PdfPageFormat.mm),
        divisoriaSecao(layout: layout, compacta: true),
      ],
    );
  }

  static pw.Widget cabecalhoTabelaItensLegadoLdv(ConfigLayoutImpressao layout) {
    final fs = layout.tamanhoFonteItens.fontSizeItemDetalhe - 0.5;
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.stretch,
      children: [
        pw.Text(
          'ITEM COD UNI DESCRICAO',
          style: estilo(layout, fontSize: fs, fontWeight: pw.FontWeight.bold),
        ),
        pw.SizedBox(height: 0.3 * PdfPageFormat.mm),
        pw.Text(
          'QTD VLBRUTO DESC VLUNIT VLTOTAL',
          style: estilo(layout, fontSize: fs, fontWeight: pw.FontWeight.bold),
          textAlign: pw.TextAlign.right,
        ),
        divisoriaSecao(layout: layout, compacta: true),
      ],
    );
  }

  static pw.Widget linhaItemLegadoLdv({
    required ConfigLayoutImpressao layout,
    required String item,
    required String codigo,
    required String unidade,
    required String descricao,
    required String quantidade,
    required String vlBruto,
    required String desconto,
    required String vlUnit,
    required String vlTotal,
  }) {
    final fs = layout.tamanhoFonteItens.fontSizeItemDetalhe - 0.5;
    final estiloItem = estilo(layout, fontSize: fs);
    final estiloVal = estilo(layout, fontSize: fs - 0.5);
    final linhaProduto =
        '$item $codigo $unidade ${descricao.trim()}'.trim();

    return pw.Padding(
      padding: pw.EdgeInsets.only(bottom: 0.35 * PdfPageFormat.mm),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.stretch,
        children: [
          pw.Text(
            linhaProduto,
            style: estiloItem,
            maxLines: 3,
            softWrap: true,
          ),
          pw.SizedBox(height: 0.2 * PdfPageFormat.mm),
          pw.Row(
            children: [
              pw.Expanded(
                flex: 2,
                child: pw.Text(quantidade, style: estiloVal, textAlign: pw.TextAlign.right),
              ),
              pw.Expanded(
                flex: 2,
                child: pw.Text(vlBruto, style: estiloVal, textAlign: pw.TextAlign.right),
              ),
              pw.Expanded(
                flex: 2,
                child: pw.Text(desconto, style: estiloVal, textAlign: pw.TextAlign.right),
              ),
              pw.Expanded(
                flex: 2,
                child: pw.Text(vlUnit, style: estiloVal, textAlign: pw.TextAlign.right),
              ),
              pw.Expanded(
                flex: 2,
                child: pw.Text(
                  vlTotal,
                  style: estilo(layout, fontSize: fs - 0.5, fontWeight: pw.FontWeight.bold),
                  textAlign: pw.TextAlign.right,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  static pw.Widget blocoTotaisLegadoLdv({
    required ConfigLayoutImpressao layout,
    required int qtdItens,
    required String subtotal,
    required String desconto,
    required String frete,
    required String valorTotal,
    bool exibirFrete = false,
  }) {
    final fs = layout.tamanhoFonteTotais.fontSizeTotais;
    final fsDestaque = layout.tamanhoFonteTotais.fontSizeTotalDestaque;
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.stretch,
      children: [
        divisoriaSecao(layout: layout, compacta: true),
        linhaResumoLegadoLdv(
          layout: layout,
          rotulo: 'QTD. TOTAL DE ITENS',
          valor: '$qtdItens',
          fontSize: fs,
        ),
        linhaResumoLegadoLdv(
          layout: layout,
          rotulo: 'SUB TOTAL R\$',
          valor: subtotal,
          fontSize: fs,
        ),
        linhaResumoLegadoLdv(
          layout: layout,
          rotulo: 'DESCONTO R\$',
          valor: desconto,
          fontSize: fs,
        ),
        if (exibirFrete)
          linhaResumoLegadoLdv(
            layout: layout,
            rotulo: 'FRETE R\$',
            valor: frete,
            fontSize: fs,
          ),
        linhaResumoLegadoLdv(
          layout: layout,
          rotulo: 'VALOR TOTAL R\$',
          valor: valorTotal,
          fontSize: fsDestaque,
          fontWeight: pw.FontWeight.bold,
          fontWeightValor: pw.FontWeight.bold,
        ),
      ],
    );
  }

  static pw.Widget blocoPagamentoLegadoLdv({
    required ConfigLayoutImpressao layout,
    required String formaPagamento,
    required String valorPago,
    required String troco,
    List<({String forma, String valor})> linhasMisto = const [],
  }) {
    final fs = layout.tamanhoFonteTotais.fontSizeTotais;
    final forma = formaPagamento.trim().toUpperCase();
    final children = <pw.Widget>[
      pw.Padding(
        padding: pw.EdgeInsets.symmetric(vertical: 0.12 * PdfPageFormat.mm),
        child: _textoCentralizado(
          layout,
          texto: 'FORMA DE PAGAMENTO | VALOR PAGO',
          fontSize: fs,
          fontWeight: pw.FontWeight.bold,
        ),
      ),
    ];

    if (linhasMisto.isNotEmpty) {
      for (final l in linhasMisto) {
        children.add(
          linhaResumoLegadoLdv(
            layout: layout,
            rotulo: '${l.forma.toUpperCase()}:',
            valor: l.valor,
            fontSize: fs,
          ),
        );
      }
    } else {
      children.add(
        linhaResumoLegadoLdv(
          layout: layout,
          rotulo: '$forma:',
          valor: valorPago,
          fontSize: fs,
        ),
      );
    }

    children.addAll([
      linhaResumoLegadoLdv(
        layout: layout,
        rotulo: 'TROCO R\$',
        valor: troco,
        fontSize: fs,
        fontWeight:
            layout.destacarTroco ? pw.FontWeight.bold : pw.FontWeight.normal,
        fontWeightValor:
            layout.destacarTroco ? pw.FontWeight.bold : pw.FontWeight.normal,
      ),
      divisoriaSecao(layout: layout, compacta: true),
    ]);

    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.stretch,
      children: children,
    );
  }

  /// Consulta SEFAZ + chave de acesso (modelo cupom termico LDV).
  static pw.Widget blocoConsultaChaveAcessoLegadoLdv({
    required ConfigLayoutImpressao layout,
    required String chaveAcesso,
    String? urlConsulta,
  }) {
    final fs = layout.tamanhoFonteCorpo.fontSizeContato;
    final url = (urlConsulta ?? urlConsultaNfcePorUf()).trim();
    final chaveFmt = formatarChaveAcessoGrupos(chaveAcesso);
    final temChave = chaveAcessoSomenteDigitos(chaveAcesso).length == 44;

    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.stretch,
      children: [
        pw.SizedBox(height: 0.35 * PdfPageFormat.mm),
        _textoCentralizado(
          layout,
          texto: 'Consulte pela Chave de Acesso em',
          fontSize: fs - 0.5,
        ),
        pw.SizedBox(height: 0.25 * PdfPageFormat.mm),
        _textoCentralizado(
          layout,
          texto: url,
          fontSize: fs - 0.5,
        ),
        pw.SizedBox(height: 0.5 * PdfPageFormat.mm),
        _textoCentralizado(
          layout,
          texto: 'CHAVE DE ACESSO',
          fontSize: fs,
          fontWeight: pw.FontWeight.bold,
        ),
        pw.SizedBox(height: 0.35 * PdfPageFormat.mm),
        if (temChave)
          pw.Text(
            chaveFmt,
            style: estilo(layout, fontSize: fs - 0.5),
            textAlign: pw.TextAlign.center,
            softWrap: true,
          )
        else
          _textoCentralizado(
            layout,
            texto: 'Chave pendente de autorizacao na SEFAZ',
            fontSize: fs - 0.5,
            fontWeight: pw.FontWeight.bold,
          ),
        pw.SizedBox(height: 0.35 * PdfPageFormat.mm),
        divisoriaSecao(layout: layout, compacta: true),
      ],
    );
  }

  static pw.Widget textoConsumidorLegadoLdv({
    required ConfigLayoutImpressao layout,
    required String textoPrincipal,
    List<String> linhasExtras = const [],
  }) {
    final fs = layout.tamanhoFonteCorpo.fontSizeCorpo;
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.stretch,
      children: [
        pw.SizedBox(height: 0.35 * PdfPageFormat.mm),
        _textoCentralizado(
          layout,
          texto: textoPrincipal,
          fontSize: fs,
          fontWeight: pw.FontWeight.bold,
        ),
        ...linhasExtras.map(
          (l) => pw.Padding(
            padding: pw.EdgeInsets.only(top: 0.35 * PdfPageFormat.mm),
            child: _textoCentralizado(
              layout,
              texto: l,
              fontSize: fs - 0.5,
            ),
          ),
        ),
        pw.SizedBox(height: 0.35 * PdfPageFormat.mm),
        divisoriaSecao(layout: layout, compacta: true),
      ],
    );
  }

  static pw.Widget rodapeIdentificacaoLegadoLdv({
    required ConfigLayoutImpressao layout,
    required String numero,
    required String serie,
    required String emissao,
    String via = 'VIA CONSUMIDOR',
    String? linhaExtra,
  }) {
    final fs = layout.tamanhoFonteCorpo.fontSizeContato;
    final numFmt = formatarNumeroDocumentoLegado(numero);
    final serFmt = serie.trim().padLeft(3, '0');
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.stretch,
      children: [
        pw.SizedBox(height: 1 * PdfPageFormat.mm),
        _textoCentralizado(
          layout,
          texto: 'NUMERO: $numFmt SERIE: $serFmt EMISSAO: $emissao',
          fontSize: fs,
        ),
        _textoCentralizado(
          layout,
          texto: via.toUpperCase(),
          fontSize: fs,
          fontWeight: pw.FontWeight.bold,
        ),
        if (linhaExtra != null && linhaExtra.trim().isNotEmpty)
          _textoCentralizado(
            layout,
            texto: linhaExtra.trim(),
            fontSize: fs - 0.5,
          ),
      ],
    );
  }

  static pw.Widget blocoConsultaChaveAcessoNfce({
    required ConfigLayoutImpressao layout,
    required String chaveAcesso,
    String? urlConsulta,
    bool chavePendente = false,
  }) {
    final fs = layout.tamanhoFonteCorpo.fontSizeContato;
    final url = (urlConsulta ?? urlConsultaNfcePorUf()).trim();
    final chaveFmt = formatarChaveAcessoGrupos(chaveAcesso);
    final temChave = chaveFmt.replaceAll(' ', '').length == 44;

    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.stretch,
      children: [
        pw.SizedBox(height: 1.5 * PdfPageFormat.mm),
        divisoriaSecao(layout: layout),
        pw.SizedBox(height: 1 * PdfPageFormat.mm),
        _textoCentralizado(
          layout,
          texto: url,
          fontSize: fs - 0.5,
        ),
        pw.SizedBox(height: 0.8 * PdfPageFormat.mm),
        _textoCentralizado(
          layout,
          texto: 'Chave de Acesso',
          fontSize: fs,
          fontWeight: pw.FontWeight.bold,
        ),
        pw.SizedBox(height: 1 * PdfPageFormat.mm),
        if (temChave)
          pw.Text(
            chaveFmt,
            style: estilo(layout, fontSize: fs - 0.5),
            textAlign: pw.TextAlign.center,
            softWrap: true,
          )
        else
          _textoCentralizado(
            layout,
            texto: chavePendente
                ? 'Chave pendente de autorizacao na SEFAZ'
                : 'Chave de acesso nao informada',
            fontSize: fs - 0.5,
            fontWeight: pw.FontWeight.bold,
          ),
        divisoriaSecao(layout: layout),
      ],
    );
  }

  static pw.Widget blocoCupomInternoSemChaveNfce({
    required ConfigLayoutImpressao layout,
  }) {
    final fs = layout.tamanhoFonteCorpo.fontSizeContato;
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.stretch,
      children: [
        pw.SizedBox(height: 1.5 * PdfPageFormat.mm),
        divisoriaSecao(layout: layout),
        pw.SizedBox(height: 1 * PdfPageFormat.mm),
        _textoCentralizado(
          layout,
          texto: 'Documento interno de venda',
          fontSize: fs,
          fontWeight: pw.FontWeight.bold,
        ),
        pw.SizedBox(height: 0.8 * PdfPageFormat.mm),
        _textoCentralizado(
          layout,
          texto: 'Consulte a NFC-e no caixa apos autorizacao',
          fontSize: fs - 0.5,
        ),
        divisoriaSecao(layout: layout),
      ],
    );
  }

  static pw.Widget linhaIdentificacaoNfce({
    required ConfigLayoutImpressao layout,
    required String numero,
    required String serie,
    required String dataHora,
    String via = 'Via consumidor',
    String? linhaExtra,
  }) {
    final fs = layout.tamanhoFonteCorpo.fontSizeContato;
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.stretch,
      children: [
        pw.SizedBox(height: 1 * PdfPageFormat.mm),
        _textoCentralizado(
          layout,
          texto: 'NFC-e n. $numero  Serie $serie  $dataHora  $via',
          fontSize: fs,
        ),
        if (linhaExtra != null && linhaExtra.trim().isNotEmpty)
          _textoCentralizado(
            layout,
            texto: linhaExtra.trim(),
            fontSize: fs - 0.5,
          ),
      ],
    );
  }

  static pw.Widget qrCodeNfceDanfe({
    required ConfigLayoutImpressao layout,
    required String payload,
  }) {
    final data = payload.trim();
    if (data.isEmpty) return pw.SizedBox.shrink();
    final lado = (larguraUtilConteudoMm(layout) * 0.55).clamp(18.0, 24.0);
    final fs = layout.tamanhoFonteCorpo.fontSizeContato;
    return pw.Column(
      children: [
        pw.SizedBox(height: 0.6 * PdfPageFormat.mm),
        _textoCentralizado(
          layout,
          texto: 'Consulta via leitor de QR Code',
          fontSize: fs - 0.5,
        ),
        pw.SizedBox(height: 0.6 * PdfPageFormat.mm),
        pw.Center(
          child: pw.BarcodeWidget(
            barcode: Barcode.qrCode(),
            data: data,
            width: lado * PdfPageFormat.mm,
            height: lado * PdfPageFormat.mm,
            drawText: false,
          ),
        ),
        pw.SizedBox(height: 0.6 * PdfPageFormat.mm),
      ],
    );
  }

  static pw.Widget linhaTributosLei12741({
    required ConfigLayoutImpressao layout,
    required double valorTotal,
  }) {
    final fs = layout.tamanhoFonteCorpo.fontSizeContato - 0.5;
    return pw.Padding(
      padding: pw.EdgeInsets.symmetric(vertical: 1 * PdfPageFormat.mm),
      child: pw.Text(
        textoTributosLei12741(valorTotal),
        style: estilo(layout, fontSize: fs),
        textAlign: pw.TextAlign.center,
        softWrap: true,
      ),
    );
  }

  static List<pw.Widget> cabecalhoEmitenteNfce({
    required ConfigLayoutImpressao layout,
    required String razaoSocial,
    required String nomeLoja,
    String cnpj = '',
    String inscricaoEstadual = '',
    Uint8List? logoBytes,
    String? telefone,
    String? endereco,
  }) {
    final logo = logoBytes;
    final temLogo = layout.exibirLogo && logo != null && logo.isNotEmpty;
    final fsNome = layout.tamanhoNomeLoja.fontSizeNome - 1;
    final fsCorpo = layout.tamanhoFonteCorpo.fontSizeContato;
    final hLogo = layout.alturaLogoMm.clamp(18.0, 44.0);
    final razao = razaoSocial.trim().isNotEmpty
        ? razaoSocial.trim()
        : (nomeLoja.trim().isEmpty ? 'Loja' : nomeLoja.trim());
    final fantasia = nomeLoja.trim();
    final out = <pw.Widget>[];

    if (temLogo) {
      out.add(
        pw.Center(
          child: pw.Padding(
            padding: pw.EdgeInsets.only(bottom: 1.5 * PdfPageFormat.mm),
            child: pw.Image(pw.MemoryImage(logo), height: hLogo),
          ),
        ),
      );
    }

    if (cnpj.trim().isNotEmpty) {
      out.add(_textoCentralizado(
        layout,
        texto: 'CNPJ ${formatarCnpjCupom(cnpj)}',
        fontSize: fsCorpo,
      ));
    }
    out.add(_textoCentralizado(
      layout,
      texto: razao,
      fontSize: fsNome,
      fontWeight: pw.FontWeight.bold,
    ));
    if (fantasia.isNotEmpty &&
        fantasia.toLowerCase() != razao.toLowerCase()) {
      out.add(_textoCentralizado(
        layout,
        texto: fantasia,
        fontSize: fsCorpo,
        fontWeight: pw.FontWeight.bold,
      ));
    }
    if (inscricaoEstadual.trim().isNotEmpty) {
      out.add(_textoCentralizado(
        layout,
        texto: 'IE ${inscricaoEstadual.trim()}',
        fontSize: fsCorpo,
      ));
    }
    if (layout.exibirEndereco &&
        endereco != null &&
        endereco.trim().isNotEmpty) {
      out.add(_textoCentralizado(
        layout,
        texto: endereco.trim(),
        fontSize: fsCorpo,
      ));
    }
    if (layout.exibirTelefone &&
        telefone != null &&
        telefone.trim().isNotEmpty) {
      out.add(_textoCentralizado(
        layout,
        texto: 'Tel: ${telefone.trim()}',
        fontSize: fsCorpo,
      ));
    }
    return out;
  }

  static pw.Widget faixaTituloDocumentoAuxiliar({
    required ConfigLayoutImpressao layout,
    required String titulo,
  }) {
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.stretch,
      children: [
        divisoriaSecao(layout: layout),
        _textoCentralizado(
          layout,
          texto: titulo,
          fontSize: layout.tamanhoFonteCorpo.fontSizeTipoDocumento,
          fontWeight: pw.FontWeight.bold,
        ),
        divisoriaSecao(layout: layout),
      ],
    );
  }

  static pw.Widget faixaAvisoCentralNfce({
    required ConfigLayoutImpressao layout,
    required String titulo,
    String? subtitulo,
    bool destaque = false,
  }) {
    final fsTitulo = layout.tamanhoFonteCorpo.fontSizeCorpo;
    final fsSub = layout.tamanhoFonteCorpo.fontSizeContato;
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.stretch,
      children: [
        if (destaque) divisoriaSecao(layout: layout, compacta: true),
        pw.SizedBox(height: 0.35 * PdfPageFormat.mm),
        _textoCentralizado(
          layout,
          texto: titulo,
          fontSize: fsTitulo,
          fontWeight: pw.FontWeight.bold,
        ),
        if (subtitulo != null && subtitulo.trim().isNotEmpty) ...[
          pw.SizedBox(height: 0.25 * PdfPageFormat.mm),
          _textoCentralizado(
            layout,
            texto: subtitulo.trim(),
            fontSize: fsSub,
          ),
        ],
        pw.SizedBox(height: 0.35 * PdfPageFormat.mm),
        if (destaque) divisoriaSecao(layout: layout, compacta: true),
      ],
    );
  }

  static pw.TextStyle _estiloCelulaNfce(
    ConfigLayoutImpressao layout, {
    bool bold = false,
    bool valor = false,
  }) {
    var fs = layout.tamanhoFonteItens.fontSizeItemDetalhe;
    if (valor) fs = (fs - 0.5).clamp(6.5, fs);
    return estilo(
      layout,
      fontSize: fs,
      fontWeight: bold ? pw.FontWeight.bold : pw.FontWeight.normal,
    );
  }

  static pw.Widget _celulaNfce(
    String texto,
    ConfigLayoutImpressao layout, {
    pw.TextAlign align = pw.TextAlign.left,
    bool bold = false,
    int maxLines = 4,
    bool valorMonetario = false,
  }) {
    final estilo = _estiloCelulaNfce(layout, bold: bold, valor: valorMonetario);
    final child = valorMonetario && align == pw.TextAlign.right
        ? _textoValorBobina(texto, estilo)
        : pw.Text(
            texto,
            style: estilo,
            textAlign: align,
            maxLines: maxLines,
            softWrap: true,
          );
    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(vertical: 0.5, horizontal: 0.5),
      child: child,
    );
  }

  /// Colunas da tabela NFC-e: mais espaco para Vl Unit / Vl Total (bobina 72 mm).
  static Map<int, pw.TableColumnWidth> _largurasColunasTabelaNfce(
    ConfigLayoutImpressao layout,
  ) {
    return const {
      0: pw.FlexColumnWidth(0.95),
      1: pw.FlexColumnWidth(3.0),
      2: pw.FlexColumnWidth(1.0),
      3: pw.FlexColumnWidth(0.65),
      4: pw.FlexColumnWidth(1.75),
      5: pw.FlexColumnWidth(1.85),
    };
  }

  static pw.Widget tabelaCabecalhoItensNfce(ConfigLayoutImpressao layout) {
    return pw.Table(
      columnWidths: _largurasColunasTabelaNfce(layout),
      defaultVerticalAlignment: pw.TableCellVerticalAlignment.middle,
      children: [
        pw.TableRow(
          children: [
            _celulaNfce('Cod.', layout, bold: true),
            _celulaNfce('Descricao', layout, bold: true),
            _celulaNfce('Qtde', layout, bold: true, align: pw.TextAlign.right),
            _celulaNfce('UN', layout, bold: true, align: pw.TextAlign.center),
            _celulaNfce(
              'Vl Unit',
              layout,
              bold: true,
              align: pw.TextAlign.right,
              valorMonetario: true,
            ),
            _celulaNfce(
              'Vl Total',
              layout,
              bold: true,
              align: pw.TextAlign.right,
              valorMonetario: true,
            ),
          ],
        ),
      ],
    );
  }

  static pw.Widget tabelaLinhaItemNfce({
    required ConfigLayoutImpressao layout,
    required String codigo,
    required String descricao,
    required String quantidadeExibicao,
    required String unidade,
    required String valorUnitario,
    required String valorTotal,
  }) {
    return pw.Table(
      columnWidths: _largurasColunasTabelaNfce(layout),
      defaultVerticalAlignment: pw.TableCellVerticalAlignment.top,
      children: [
        pw.TableRow(
          children: [
            _celulaNfce(codigo, layout, maxLines: 2),
            _celulaNfce(descricao, layout, maxLines: 3),
            _celulaNfce(
              quantidadeExibicao,
              layout,
              align: pw.TextAlign.right,
            ),
            _celulaNfce(unidade, layout, align: pw.TextAlign.center),
            _celulaNfce(
              valorUnitario,
              layout,
              align: pw.TextAlign.right,
              valorMonetario: true,
            ),
            _celulaNfce(
              valorTotal,
              layout,
              align: pw.TextAlign.right,
              bold: true,
              valorMonetario: true,
            ),
          ],
        ),
      ],
    );
  }

  static pw.Widget linhaResumoNfce({
    required ConfigLayoutImpressao layout,
    required String rotulo,
    required String valor,
    bool destaque = false,
  }) {
    final fs = destaque
        ? layout.tamanhoFonteTotais.fontSizeTotalDestaque
        : layout.tamanhoFonteTotais.fontSizeTotais;
    return pw.Padding(
      padding: pw.EdgeInsets.only(
        top: 0.4 * PdfPageFormat.mm,
        bottom: 0.4 * PdfPageFormat.mm,
      ),
      child: linhaColunas(
        layout: layout,
        esquerda: rotulo,
        direita: valor,
        fontSize: fs,
        fontWeight: destaque ? pw.FontWeight.bold : pw.FontWeight.normal,
        fontWeightDireita: destaque ? pw.FontWeight.bold : pw.FontWeight.normal,
        flexEsquerda: 5,
      ),
    );
  }

  static pw.Widget blocoPagamentoNfce({
    required ConfigLayoutImpressao layout,
    required String formaPagamento,
    required String valorPago,
    required String troco,
    List<String> linhasPagamentoMisto = const [],
  }) {
    final fs = layout.tamanhoFonteTotais.fontSizeTotais;
    final children = <pw.Widget>[
      pw.SizedBox(height: 1 * PdfPageFormat.mm),
      linhaColunas(
        layout: layout,
        esquerda: 'FORMA PAGAMENTO',
        direita: formaPagamento,
        fontSize: fs,
        fontWeight: pw.FontWeight.bold,
        flexEsquerda: 5,
      ),
    ];
    if (linhasPagamentoMisto.isNotEmpty) {
      for (final l in linhasPagamentoMisto) {
        children.add(
          pw.Padding(
            padding: pw.EdgeInsets.only(left: 2 * PdfPageFormat.mm, top: 0.3 * PdfPageFormat.mm),
            child: textoCorpo(l, layout, fontSize: fs - 0.5),
          ),
        );
      }
    }
    children.addAll([
      linhaColunas(
        layout: layout,
        esquerda: 'VALOR PAGO R\$',
        direita: valorPago,
        fontSize: fs,
        flexEsquerda: 5,
      ),
      linhaColunas(
        layout: layout,
        esquerda: 'Troco R\$',
        direita: troco,
        fontSize: fs,
        fontWeight: layout.destacarTroco ? pw.FontWeight.bold : pw.FontWeight.normal,
        fontWeightDireita:
            layout.destacarTroco ? pw.FontWeight.bold : pw.FontWeight.normal,
        flexEsquerda: 5,
      ),
    ]);
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.stretch,
      children: children,
    );
  }

  static pw.Widget blocoConsumidorNfce({
    required ConfigLayoutImpressao layout,
    required String textoConsumidor,
    List<String> linhasExtras = const [],
  }) {
    final fs = layout.tamanhoFonteCorpo.fontSizeCorpo;
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.stretch,
      children: [
        pw.SizedBox(height: 1.5 * PdfPageFormat.mm),
        divisoriaSecao(layout: layout),
        pw.SizedBox(height: 1 * PdfPageFormat.mm),
        pw.Text(
          textoConsumidor,
          style: estilo(layout, fontSize: fs),
          softWrap: true,
        ),
        ...linhasExtras.map(
          (l) => pw.Padding(
            padding: pw.EdgeInsets.only(top: 0.5 * PdfPageFormat.mm),
            child: pw.Text(
              l,
              style: estilo(layout, fontSize: fs - 0.5),
              softWrap: true,
            ),
          ),
        ),
      ],
    );
  }

  static pw.Widget rodapeIdentificacaoCupomNfce({
    required ConfigLayoutImpressao layout,
    required String numeroDocumento,
    required String dataHora,
    String via = 'Via consumidor',
    String? linhaExtra,
  }) {
    final fs = layout.tamanhoFonteCorpo.fontSizeContato;
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.stretch,
      children: [
        pw.SizedBox(height: 1.5 * PdfPageFormat.mm),
        _textoCentralizado(
          layout,
          texto: 'Cupom n. $numeroDocumento  $dataHora  $via',
          fontSize: fs,
        ),
        if (linhaExtra != null && linhaExtra.trim().isNotEmpty)
          _textoCentralizado(
            layout,
            texto: linhaExtra.trim(),
            fontSize: fs,
          ),
      ],
    );
  }

  static int contarLinhasExtrasNfce({
    required int qtdItens,
    bool segundaVia = false,
    bool temDesconto = false,
    bool temEntrega = false,
    bool temFiado = false,
    int linhasFiado = 0,
    int linhasRodape = 1,
    bool temChave = false,
    bool contingenciaSefaz = false,
  }) {
    var n = 30 + (qtdItens * 2.5).ceil();
    if (segundaVia) n += 3;
    if (temDesconto) n++;
    if (temEntrega) n += 2;
    if (temFiado) n += 2 + linhasFiado;
    n += 12;
    if (contingenciaSefaz) n += 3;
    n += linhasRodape;
    return n;
  }
}

enum EmpresaModeloPdf { a4, bobina }

EmpresaModeloPdf empresaModeloPdfDeString(String? modelo) {
  return modelo == 'a4' ? EmpresaModeloPdf.a4 : EmpresaModeloPdf.bobina;
}
