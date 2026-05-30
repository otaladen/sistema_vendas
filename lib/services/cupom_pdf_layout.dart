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

  // --- Layout DANFE NFC-e (contingencia) para cupom nao fiscal ---

  static const String tituloDanfeNfce =
      'Documento Auxiliar da Nota Fiscal de Consumidor Eletronica';

  static String urlConsultaNfcePorUf([String? uf]) {
    final u = (uf ?? FiscalConfig.ufEmitente).trim().toUpperCase();
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

  static String formatarChaveAcessoGrupos(String chave) {
    final d = chaveAcessoSomenteDigitos(chave);
    if (d.length != 44) return chave.trim();
    final grupos = <String>[];
    for (var i = 0; i < d.length; i += 4) {
      grupos.add(d.substring(i, i + 4));
    }
    return grupos.join(' ');
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

  static pw.Widget faixaContingenciaNfce({
    required ConfigLayoutImpressao layout,
    String titulo = 'EMITIDA EM CONTINGENCIA',
    String subtitulo = 'Pendente de autorizacao',
  }) {
    final fs = layout.tamanhoFonteCorpo.fontSizeCorpo;
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.stretch,
      children: [
        divisoriaSecao(layout: layout, destaque: true),
        pw.SizedBox(height: 1 * PdfPageFormat.mm),
        _textoCentralizado(
          layout,
          texto: titulo,
          fontSize: fs,
          fontWeight: pw.FontWeight.bold,
        ),
        pw.SizedBox(height: 0.8 * PdfPageFormat.mm),
        _textoCentralizado(
          layout,
          texto: subtitulo,
          fontSize: fs - 0.5,
          fontWeight: pw.FontWeight.bold,
        ),
        pw.SizedBox(height: 1 * PdfPageFormat.mm),
        divisoriaSecao(layout: layout, destaque: true),
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
          texto: 'Consulta pela Chave de Acesso',
          fontSize: fs,
          fontWeight: pw.FontWeight.bold,
        ),
        pw.SizedBox(height: 0.8 * PdfPageFormat.mm),
        _textoCentralizado(
          layout,
          texto: url,
          fontSize: fs - 0.5,
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
    final lado = (larguraBobinaMm - layout.margemPaginaMm * 2)
        .clamp(28.0, 42.0);
    return pw.Column(
      children: [
        pw.SizedBox(height: 1.5 * PdfPageFormat.mm),
        pw.Center(
          child: pw.BarcodeWidget(
            barcode: Barcode.qrCode(),
            data: data,
            width: lado * PdfPageFormat.mm,
            height: lado * PdfPageFormat.mm,
            drawText: false,
          ),
        ),
        pw.SizedBox(height: 1 * PdfPageFormat.mm),
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
        if (destaque) divisoriaSecao(layout: layout, destaque: true),
        pw.SizedBox(height: 1.5 * PdfPageFormat.mm),
        _textoCentralizado(
          layout,
          texto: titulo,
          fontSize: fsTitulo,
          fontWeight: pw.FontWeight.bold,
        ),
        if (subtitulo != null && subtitulo.trim().isNotEmpty) ...[
          pw.SizedBox(height: 1 * PdfPageFormat.mm),
          _textoCentralizado(
            layout,
            texto: subtitulo.trim(),
            fontSize: fsSub,
          ),
        ],
        pw.SizedBox(height: 1.5 * PdfPageFormat.mm),
        if (destaque) divisoriaSecao(layout: layout, destaque: true),
      ],
    );
  }

  static pw.TextStyle _estiloCelulaNfce(
    ConfigLayoutImpressao layout, {
    bool bold = false,
  }) {
    return estilo(
      layout,
      fontSize: layout.tamanhoFonteItens.fontSizeItemDetalhe,
      fontWeight: bold ? pw.FontWeight.bold : pw.FontWeight.normal,
    );
  }

  static pw.Widget _celulaNfce(
    String texto,
    ConfigLayoutImpressao layout, {
    pw.TextAlign align = pw.TextAlign.left,
    bool bold = false,
    int maxLines = 4,
  }) {
    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(vertical: 0.5, horizontal: 0.5),
      child: pw.Text(
        texto,
        style: _estiloCelulaNfce(layout, bold: bold),
        textAlign: align,
        maxLines: maxLines,
        softWrap: true,
      ),
    );
  }

  static pw.Widget tabelaCabecalhoItensNfce(ConfigLayoutImpressao layout) {
    return pw.Table(
      columnWidths: const {
        0: pw.FlexColumnWidth(1.1),
        1: pw.FlexColumnWidth(2.6),
        2: pw.FlexColumnWidth(0.9),
        3: pw.FlexColumnWidth(0.7),
        4: pw.FlexColumnWidth(1.2),
        5: pw.FlexColumnWidth(1.2),
      },
      defaultVerticalAlignment: pw.TableCellVerticalAlignment.middle,
      children: [
        pw.TableRow(
          children: [
            _celulaNfce('Cod.', layout, bold: true),
            _celulaNfce('Descricao', layout, bold: true),
            _celulaNfce('Qtde', layout, bold: true, align: pw.TextAlign.right),
            _celulaNfce('UN', layout, bold: true, align: pw.TextAlign.center),
            _celulaNfce('Vl Unit', layout, bold: true, align: pw.TextAlign.right),
            _celulaNfce('Vl Total', layout, bold: true, align: pw.TextAlign.right),
          ],
        ),
      ],
    );
  }

  static pw.Widget tabelaLinhaItemNfce({
    required ConfigLayoutImpressao layout,
    required String codigo,
    required String descricao,
    required int quantidade,
    required String unidade,
    required String valorUnitario,
    required String valorTotal,
  }) {
    return pw.Table(
      columnWidths: const {
        0: pw.FlexColumnWidth(1.1),
        1: pw.FlexColumnWidth(2.6),
        2: pw.FlexColumnWidth(0.9),
        3: pw.FlexColumnWidth(0.7),
        4: pw.FlexColumnWidth(1.2),
        5: pw.FlexColumnWidth(1.2),
      },
      defaultVerticalAlignment: pw.TableCellVerticalAlignment.top,
      children: [
        pw.TableRow(
          children: [
            _celulaNfce(codigo, layout, maxLines: 2),
            _celulaNfce(descricao, layout, maxLines: 3),
            _celulaNfce(
              '$quantidade',
              layout,
              align: pw.TextAlign.right,
            ),
            _celulaNfce(unidade, layout, align: pw.TextAlign.center),
            _celulaNfce(valorUnitario, layout, align: pw.TextAlign.right),
            _celulaNfce(
              valorTotal,
              layout,
              align: pw.TextAlign.right,
              bold: true,
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
        flexEsquerda: 6,
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
  }) {
    var n = 38 + qtdItens * 2;
    if (segundaVia) n += 3;
    if (temDesconto) n++;
    if (temEntrega) n += 2;
    if (temFiado) n += 2 + linhasFiado;
    if (temChave) n += 2;
    n += linhasRodape;
    return n;
  }
}

enum EmpresaModeloPdf { a4, bobina }

EmpresaModeloPdf empresaModeloPdfDeString(String? modelo) {
  return modelo == 'a4' ? EmpresaModeloPdf.a4 : EmpresaModeloPdf.bobina;
}
