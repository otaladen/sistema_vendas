import 'dart:convert';

/// Presets de layout (cupom/orcamento).
enum LayoutImpressaoPreset {
  padrao,
  /// Bobina 80 mm — area imprimivel 72 mm (valores alinhados, sem corte na margem).
  bematechMp4200,
  economico,
  compacto,
  destaque,
  personalizado,
}

/// Familia de fonte embutida no PDF (compativel com bobina termica).
enum LayoutFamiliaFonte {
  helvetica,
  courier,
  times;

  String get rotulo {
    switch (this) {
      case LayoutFamiliaFonte.helvetica:
        return 'Padrao (Helvetica)';
      case LayoutFamiliaFonte.courier:
        return 'Monoespacada (Courier)';
      case LayoutFamiliaFonte.times:
        return 'Serifada (Times)';
    }
  }

  static LayoutFamiliaFonte fromString(String? v) {
    switch (v) {
      case 'courier':
        return LayoutFamiliaFonte.courier;
      case 'times':
        return LayoutFamiliaFonte.times;
      default:
        return LayoutFamiliaFonte.helvetica;
    }
  }

  String get codigo => name;
}

/// Tamanho de fonte em tres niveis (bobina 80 mm).
enum LayoutTamanhoFonte {
  p,
  m,
  g;

  double get fontSizeNome {
    switch (this) {
      case LayoutTamanhoFonte.p:
        return 11;
      case LayoutTamanhoFonte.m:
        return 13;
      case LayoutTamanhoFonte.g:
        return 15;
    }
  }

  double get fontSizeCorpo {
    switch (this) {
      case LayoutTamanhoFonte.p:
        return 8;
      case LayoutTamanhoFonte.m:
        return 9;
      case LayoutTamanhoFonte.g:
        return 10;
    }
  }

  double get fontSizeContato => fontSizeCorpo - 1;

  double get fontSizeTipoDocumento => fontSizeCorpo - 0.5;

  double get fontSizeItem {
    switch (this) {
      case LayoutTamanhoFonte.p:
        return 8;
      case LayoutTamanhoFonte.m:
        return 9;
      case LayoutTamanhoFonte.g:
        return 10;
    }
  }

  double get fontSizeItemDetalhe => fontSizeItem - 1;

  double get fontSizeTotais {
    switch (this) {
      case LayoutTamanhoFonte.p:
        return 8;
      case LayoutTamanhoFonte.m:
        return 9;
      case LayoutTamanhoFonte.g:
        return 10;
    }
  }

  double get fontSizeTotalDestaque => fontSizeTotais + 1;

  double get fontSizeRodape => fontSizeCorpo - 1;

  static LayoutTamanhoFonte fromString(String? v) {
    switch (v) {
      case 'p':
        return LayoutTamanhoFonte.p;
      case 'g':
        return LayoutTamanhoFonte.g;
      default:
        return LayoutTamanhoFonte.m;
    }
  }

  String get codigo {
    switch (this) {
      case LayoutTamanhoFonte.p:
        return 'p';
      case LayoutTamanhoFonte.m:
        return 'm';
      case LayoutTamanhoFonte.g:
        return 'g';
    }
  }
}

/// Como a impressao direta define a altura da pagina na bobina.
enum LayoutModoImpressaoDireta {
  /// Usa a altura calculada do PDF (recomendado — menos papel em branco).
  alturaPdf,
  /// Altura fixa curta (impressoras que ignoram o PDF).
  altura150,
  altura200,
  /// Deixa o driver decidir (pode avancar muito papel).
  driverIlimitado;

  String get rotulo {
    switch (this) {
      case LayoutModoImpressaoDireta.alturaPdf:
        return 'Altura do PDF (economico)';
      case LayoutModoImpressaoDireta.altura150:
        return 'Altura fixa 150 mm';
      case LayoutModoImpressaoDireta.altura200:
        return 'Altura fixa 200 mm';
      case LayoutModoImpressaoDireta.driverIlimitado:
        return 'Driver automatico (pode gastar papel)';
    }
  }

  double? get alturaFixaMm {
    switch (this) {
      case LayoutModoImpressaoDireta.altura150:
        return 150;
      case LayoutModoImpressaoDireta.altura200:
        return 200;
      case LayoutModoImpressaoDireta.alturaPdf:
      case LayoutModoImpressaoDireta.driverIlimitado:
        return null;
    }
  }

  static LayoutModoImpressaoDireta fromString(String? v) {
    switch (v) {
      case 'altura150':
        return LayoutModoImpressaoDireta.altura150;
      case 'altura200':
        return LayoutModoImpressaoDireta.altura200;
      case 'driverIlimitado':
        return LayoutModoImpressaoDireta.driverIlimitado;
      default:
        return LayoutModoImpressaoDireta.alturaPdf;
    }
  }

  String get codigo => name;
}

enum LayoutComprimentoDivisoria {
  curto,
  medio,
  longo;

  int get caracteres {
    switch (this) {
      case LayoutComprimentoDivisoria.curto:
        return 28;
      case LayoutComprimentoDivisoria.medio:
        return 36;
      case LayoutComprimentoDivisoria.longo:
        return 44;
    }
  }

  static LayoutComprimentoDivisoria fromString(String? v) {
    switch (v) {
      case 'curto':
        return LayoutComprimentoDivisoria.curto;
      case 'longo':
        return LayoutComprimentoDivisoria.longo;
      default:
        return LayoutComprimentoDivisoria.medio;
    }
  }

  String get codigo {
    switch (this) {
      case LayoutComprimentoDivisoria.curto:
        return 'curto';
      case LayoutComprimentoDivisoria.medio:
        return 'medio';
      case LayoutComprimentoDivisoria.longo:
        return 'longo';
    }
  }
}

/// Opcoes visuais de um documento (cupom ou orcamento).
class ConfigLayoutImpressao {
  const ConfigLayoutImpressao({
    this.preset = LayoutImpressaoPreset.padrao,
    this.familiaFonte = LayoutFamiliaFonte.helvetica,
    this.exibirLogo = true,
    this.tamanhoNomeLoja = LayoutTamanhoFonte.m,
    this.tamanhoFonteCorpo = LayoutTamanhoFonte.m,
    this.exibirTelefone = true,
    this.exibirEndereco = true,
    this.faixaComDivisorias = true,
    this.tituloDocumento = '',
    this.destacarSegundaVia = true,
    this.caractereDivisoriaSimples = '-',
    this.caractereDivisoriaDestaque = '=',
    this.comprimentoDivisoria = LayoutComprimentoDivisoria.medio,
    this.exibirVendedor = true,
    this.exibirDocumentoCliente = true,
    this.exibirTelefoneCliente = true,
    this.exibirEntrega = true,
    this.exibirEnderecoEntrega = true,
    this.exibirValidadeOrcamento = false,
    this.exibirObservacaoEntrega = false,
    this.colunasEsquerdaDireita = true,
    this.cabecalhoColunasItens = true,
    this.tamanhoFonteItens = LayoutTamanhoFonte.m,
    this.tamanhoFonteTotais = LayoutTamanhoFonte.m,
    this.linhaQuantidadePreco = true,
    this.divisoriaDestaqueAntesTotais = true,
    this.alinharTotaisColunas = true,
    this.alinharPagamentoColunas = true,
    this.destacarTotal = true,
    this.destacarTroco = true,
    this.divisoriaAntesRodape = true,
    this.espacoCompacto = false,
    this.flexColunaEsquerda = 3,
    this.larguraColunaValorMm = 32,
    this.reservarColunaValorFixa = true,
    this.larguraPaginaPdfMm = 72,
    this.margemPaginaMm = 2,
    this.margemCorteMm = 2,
    this.fatorEspacoVertical = 1,
    this.fatorAlturaPaginaPdf = 1.05,
    this.alturaLogoMm = 36,
    this.espacoEntreItensMm = 1.5,
    this.exibirEspacoFinal = true,
    this.modoImpressaoDireta = LayoutModoImpressaoDireta.alturaPdf,
    this.estiloCupomNfce = true,
  });

  final LayoutImpressaoPreset preset;
  final LayoutFamiliaFonte familiaFonte;
  final bool exibirLogo;
  final LayoutTamanhoFonte tamanhoNomeLoja;
  final LayoutTamanhoFonte tamanhoFonteCorpo;
  final bool exibirTelefone;
  final bool exibirEndereco;
  final bool faixaComDivisorias;
  final String tituloDocumento;
  final bool destacarSegundaVia;
  final String caractereDivisoriaSimples;
  final String caractereDivisoriaDestaque;
  final LayoutComprimentoDivisoria comprimentoDivisoria;
  final bool exibirVendedor;
  final bool exibirDocumentoCliente;
  final bool exibirTelefoneCliente;
  final bool exibirEntrega;
  final bool exibirEnderecoEntrega;
  final bool exibirValidadeOrcamento;
  final bool exibirObservacaoEntrega;
  final bool colunasEsquerdaDireita;
  final bool cabecalhoColunasItens;
  final LayoutTamanhoFonte tamanhoFonteItens;
  final LayoutTamanhoFonte tamanhoFonteTotais;
  final bool linhaQuantidadePreco;
  final bool divisoriaDestaqueAntesTotais;
  final bool alinharTotaisColunas;
  final bool alinharPagamentoColunas;
  final bool destacarTotal;
  final bool destacarTroco;
  final bool divisoriaAntesRodape;
  final bool espacoCompacto;

  /// Proporcao da coluna esquerda em modo flex (2–7; padrao 4 = 40%).
  final int flexColunaEsquerda;

  /// Largura reservada para valores (R$) em bobina 80 mm.
  final double larguraColunaValorMm;

  /// Reserva espaco fixo para valores — evita texto da esquerda “comer” o preco.
  final bool reservarColunaValorFixa;

  /// Largura do PDF enviado a impressora (mm). Papel 80 mm: use 72 (Bematech MP-4200 TH).
  final double larguraPaginaPdfMm;
  final double margemPaginaMm;
  final double margemCorteMm;
  final double fatorEspacoVertical;
  final double fatorAlturaPaginaPdf;
  final double alturaLogoMm;
  final double espacoEntreItensMm;
  final bool exibirEspacoFinal;
  final LayoutModoImpressaoDireta modoImpressaoDireta;

  /// Layout tabular inspirado na DANFE NFC-e (codigo, qtd, valores alinhados).
  final bool estiloCupomNfce;

  String get tituloDocumentoEfetivoCupom =>
      tituloDocumento.trim().isEmpty ? 'CUPOM NAO FISCAL' : tituloDocumento.trim();

  String get tituloDocumentoEfetivoOrcamento =>
      tituloDocumento.trim().isEmpty ? 'ORCAMENTO' : tituloDocumento.trim();

  String get caractereSimples =>
      caractereDivisoriaSimples.isEmpty ? '-' : caractereDivisoriaSimples[0];

  String get caractereDestaque =>
      caractereDivisoriaDestaque.isEmpty ? '=' : caractereDivisoriaDestaque[0];

  static ConfigLayoutImpressao padraoCupom() => const ConfigLayoutImpressao(
        familiaFonte: LayoutFamiliaFonte.courier,
      );

  static ConfigLayoutImpressao padraoOrcamento() =>
      economico(orcamento: true).copyWith(
        familiaFonte: LayoutFamiliaFonte.courier,
      );

  /// Bematech MP-4200 TH e termicas 80 mm com area util ~72 mm.
  static ConfigLayoutImpressao bematechMp4200({required bool orcamento}) {
    if (orcamento) {
      return economico(orcamento: true).copyWith(
        preset: LayoutImpressaoPreset.bematechMp4200,
        larguraPaginaPdfMm: 72,
        larguraColunaValorMm: 32,
        reservarColunaValorFixa: true,
        flexColunaEsquerda: 3,
        margemPaginaMm: 2,
        colunasEsquerdaDireita: true,
        linhaQuantidadePreco: true,
        alinharTotaisColunas: true,
        alinharPagamentoColunas: true,
      );
    }
    return const ConfigLayoutImpressao(
      preset: LayoutImpressaoPreset.bematechMp4200,
      larguraPaginaPdfMm: 72,
      larguraColunaValorMm: 32,
      reservarColunaValorFixa: true,
      flexColunaEsquerda: 3,
      margemPaginaMm: 2,
      margemCorteMm: 2,
      fatorAlturaPaginaPdf: 1.05,
      modoImpressaoDireta: LayoutModoImpressaoDireta.alturaPdf,
      estiloCupomNfce: true,
      colunasEsquerdaDireita: true,
      cabecalhoColunasItens: true,
      linhaQuantidadePreco: true,
      alinharTotaisColunas: true,
      alinharPagamentoColunas: true,
    );
  }

  /// Maxima economia de papel (teste na loja).
  static ConfigLayoutImpressao economico({required bool orcamento}) =>
      ConfigLayoutImpressao(
        preset: LayoutImpressaoPreset.economico,
        tamanhoNomeLoja: LayoutTamanhoFonte.p,
        tamanhoFonteCorpo: LayoutTamanhoFonte.p,
        tamanhoFonteItens: LayoutTamanhoFonte.p,
        tamanhoFonteTotais: LayoutTamanhoFonte.p,
        comprimentoDivisoria: LayoutComprimentoDivisoria.curto,
        cabecalhoColunasItens: false,
        faixaComDivisorias: false,
        divisoriaDestaqueAntesTotais: false,
        divisoriaAntesRodape: false,
        colunasEsquerdaDireita: false,
        linhaQuantidadePreco: false,
        estiloCupomNfce: false,
        espacoCompacto: true,
        margemPaginaMm: 2,
        margemCorteMm: 0,
        fatorEspacoVertical: 0.5,
        fatorAlturaPaginaPdf: 1.0,
        alturaLogoMm: 28,
        espacoEntreItensMm: 1,
        exibirEspacoFinal: false,
        exibirValidadeOrcamento: orcamento,
        exibirObservacaoEntrega: false,
        exibirEntrega: !orcamento ? false : false,
      );

  static ConfigLayoutImpressao compacto({required bool orcamento}) =>
      ConfigLayoutImpressao(
        preset: LayoutImpressaoPreset.compacto,
        tamanhoNomeLoja: LayoutTamanhoFonte.p,
        tamanhoFonteCorpo: LayoutTamanhoFonte.p,
        tamanhoFonteItens: LayoutTamanhoFonte.p,
        tamanhoFonteTotais: LayoutTamanhoFonte.p,
        comprimentoDivisoria: LayoutComprimentoDivisoria.curto,
        cabecalhoColunasItens: false,
        estiloCupomNfce: false,
        espacoCompacto: true,
        margemPaginaMm: 2.5,
        margemCorteMm: 2,
        fatorEspacoVertical: 0.65,
        fatorAlturaPaginaPdf: 0.9,
        alturaLogoMm: 32,
        espacoEntreItensMm: 1.2,
        exibirValidadeOrcamento: orcamento,
        exibirObservacaoEntrega: orcamento,
      );

  static ConfigLayoutImpressao destaque({required bool orcamento}) =>
      ConfigLayoutImpressao(
        preset: LayoutImpressaoPreset.destaque,
        tamanhoNomeLoja: LayoutTamanhoFonte.g,
        tamanhoFonteCorpo: LayoutTamanhoFonte.g,
        tamanhoFonteItens: LayoutTamanhoFonte.g,
        tamanhoFonteTotais: LayoutTamanhoFonte.g,
        comprimentoDivisoria: LayoutComprimentoDivisoria.longo,
        exibirValidadeOrcamento: orcamento,
        exibirObservacaoEntrega: orcamento,
      );

  static ConfigLayoutImpressao fromPreset(
    LayoutImpressaoPreset preset, {
    required bool orcamento,
  }) {
    switch (preset) {
      case LayoutImpressaoPreset.bematechMp4200:
        return bematechMp4200(orcamento: orcamento);
      case LayoutImpressaoPreset.economico:
        return economico(orcamento: orcamento);
      case LayoutImpressaoPreset.compacto:
        return compacto(orcamento: orcamento);
      case LayoutImpressaoPreset.destaque:
        return destaque(orcamento: orcamento);
      case LayoutImpressaoPreset.padrao:
        return orcamento ? padraoOrcamento() : padraoCupom();
      case LayoutImpressaoPreset.personalizado:
        return orcamento ? padraoOrcamento() : padraoCupom();
    }
  }

  ConfigLayoutImpressao copyWith({
    LayoutImpressaoPreset? preset,
    LayoutFamiliaFonte? familiaFonte,
    bool? exibirLogo,
    LayoutTamanhoFonte? tamanhoNomeLoja,
    LayoutTamanhoFonte? tamanhoFonteCorpo,
    bool? exibirTelefone,
    bool? exibirEndereco,
    bool? faixaComDivisorias,
    String? tituloDocumento,
    bool? destacarSegundaVia,
    String? caractereDivisoriaSimples,
    String? caractereDivisoriaDestaque,
    LayoutComprimentoDivisoria? comprimentoDivisoria,
    bool? exibirVendedor,
    bool? exibirDocumentoCliente,
    bool? exibirTelefoneCliente,
    bool? exibirEntrega,
    bool? exibirEnderecoEntrega,
    bool? exibirValidadeOrcamento,
    bool? exibirObservacaoEntrega,
    bool? colunasEsquerdaDireita,
    bool? cabecalhoColunasItens,
    LayoutTamanhoFonte? tamanhoFonteItens,
    LayoutTamanhoFonte? tamanhoFonteTotais,
    bool? linhaQuantidadePreco,
    bool? divisoriaDestaqueAntesTotais,
    bool? alinharTotaisColunas,
    bool? alinharPagamentoColunas,
    bool? destacarTotal,
    bool? destacarTroco,
    bool? divisoriaAntesRodape,
    bool? espacoCompacto,
    int? flexColunaEsquerda,
    double? larguraColunaValorMm,
    bool? reservarColunaValorFixa,
    double? larguraPaginaPdfMm,
    double? margemPaginaMm,
    double? margemCorteMm,
    double? fatorEspacoVertical,
    double? fatorAlturaPaginaPdf,
    double? alturaLogoMm,
    double? espacoEntreItensMm,
    bool? exibirEspacoFinal,
    LayoutModoImpressaoDireta? modoImpressaoDireta,
    bool? estiloCupomNfce,
  }) {
    return ConfigLayoutImpressao(
      preset: preset ?? this.preset,
      familiaFonte: familiaFonte ?? this.familiaFonte,
      exibirLogo: exibirLogo ?? this.exibirLogo,
      tamanhoNomeLoja: tamanhoNomeLoja ?? this.tamanhoNomeLoja,
      tamanhoFonteCorpo: tamanhoFonteCorpo ?? this.tamanhoFonteCorpo,
      exibirTelefone: exibirTelefone ?? this.exibirTelefone,
      exibirEndereco: exibirEndereco ?? this.exibirEndereco,
      faixaComDivisorias: faixaComDivisorias ?? this.faixaComDivisorias,
      tituloDocumento: tituloDocumento ?? this.tituloDocumento,
      destacarSegundaVia: destacarSegundaVia ?? this.destacarSegundaVia,
      caractereDivisoriaSimples:
          caractereDivisoriaSimples ?? this.caractereDivisoriaSimples,
      caractereDivisoriaDestaque:
          caractereDivisoriaDestaque ?? this.caractereDivisoriaDestaque,
      comprimentoDivisoria: comprimentoDivisoria ?? this.comprimentoDivisoria,
      exibirVendedor: exibirVendedor ?? this.exibirVendedor,
      exibirDocumentoCliente:
          exibirDocumentoCliente ?? this.exibirDocumentoCliente,
      exibirTelefoneCliente:
          exibirTelefoneCliente ?? this.exibirTelefoneCliente,
      exibirEntrega: exibirEntrega ?? this.exibirEntrega,
      exibirEnderecoEntrega:
          exibirEnderecoEntrega ?? this.exibirEnderecoEntrega,
      exibirValidadeOrcamento:
          exibirValidadeOrcamento ?? this.exibirValidadeOrcamento,
      exibirObservacaoEntrega:
          exibirObservacaoEntrega ?? this.exibirObservacaoEntrega,
      colunasEsquerdaDireita:
          colunasEsquerdaDireita ?? this.colunasEsquerdaDireita,
      cabecalhoColunasItens:
          cabecalhoColunasItens ?? this.cabecalhoColunasItens,
      tamanhoFonteItens: tamanhoFonteItens ?? this.tamanhoFonteItens,
      tamanhoFonteTotais: tamanhoFonteTotais ?? this.tamanhoFonteTotais,
      linhaQuantidadePreco: linhaQuantidadePreco ?? this.linhaQuantidadePreco,
      divisoriaDestaqueAntesTotais:
          divisoriaDestaqueAntesTotais ?? this.divisoriaDestaqueAntesTotais,
      alinharTotaisColunas: alinharTotaisColunas ?? this.alinharTotaisColunas,
      alinharPagamentoColunas:
          alinharPagamentoColunas ?? this.alinharPagamentoColunas,
      destacarTotal: destacarTotal ?? this.destacarTotal,
      destacarTroco: destacarTroco ?? this.destacarTroco,
      divisoriaAntesRodape: divisoriaAntesRodape ?? this.divisoriaAntesRodape,
      espacoCompacto: espacoCompacto ?? this.espacoCompacto,
      flexColunaEsquerda: flexColunaEsquerda ?? this.flexColunaEsquerda,
      larguraColunaValorMm: larguraColunaValorMm ?? this.larguraColunaValorMm,
      reservarColunaValorFixa:
          reservarColunaValorFixa ?? this.reservarColunaValorFixa,
      larguraPaginaPdfMm: larguraPaginaPdfMm ?? this.larguraPaginaPdfMm,
      margemPaginaMm: margemPaginaMm ?? this.margemPaginaMm,
      margemCorteMm: margemCorteMm ?? this.margemCorteMm,
      fatorEspacoVertical: fatorEspacoVertical ?? this.fatorEspacoVertical,
      fatorAlturaPaginaPdf: fatorAlturaPaginaPdf ?? this.fatorAlturaPaginaPdf,
      alturaLogoMm: alturaLogoMm ?? this.alturaLogoMm,
      espacoEntreItensMm: espacoEntreItensMm ?? this.espacoEntreItensMm,
      exibirEspacoFinal: exibirEspacoFinal ?? this.exibirEspacoFinal,
      modoImpressaoDireta: modoImpressaoDireta ?? this.modoImpressaoDireta,
      estiloCupomNfce: estiloCupomNfce ?? this.estiloCupomNfce,
    );
  }

  Map<String, dynamic> toJson() => {
        'preset': preset.name,
        'familiaFonte': familiaFonte.codigo,
        'exibirLogo': exibirLogo,
        'tamanhoNomeLoja': tamanhoNomeLoja.codigo,
        'tamanhoFonteCorpo': tamanhoFonteCorpo.codigo,
        'exibirTelefone': exibirTelefone,
        'exibirEndereco': exibirEndereco,
        'faixaComDivisorias': faixaComDivisorias,
        'tituloDocumento': tituloDocumento,
        'destacarSegundaVia': destacarSegundaVia,
        'caractereDivisoriaSimples': caractereDivisoriaSimples,
        'caractereDivisoriaDestaque': caractereDivisoriaDestaque,
        'comprimentoDivisoria': comprimentoDivisoria.codigo,
        'exibirVendedor': exibirVendedor,
        'exibirDocumentoCliente': exibirDocumentoCliente,
        'exibirTelefoneCliente': exibirTelefoneCliente,
        'exibirEntrega': exibirEntrega,
        'exibirEnderecoEntrega': exibirEnderecoEntrega,
        'exibirValidadeOrcamento': exibirValidadeOrcamento,
        'exibirObservacaoEntrega': exibirObservacaoEntrega,
        'colunasEsquerdaDireita': colunasEsquerdaDireita,
        'cabecalhoColunasItens': cabecalhoColunasItens,
        'tamanhoFonteItens': tamanhoFonteItens.codigo,
        'tamanhoFonteTotais': tamanhoFonteTotais.codigo,
        'linhaQuantidadePreco': linhaQuantidadePreco,
        'divisoriaDestaqueAntesTotais': divisoriaDestaqueAntesTotais,
        'alinharTotaisColunas': alinharTotaisColunas,
        'alinharPagamentoColunas': alinharPagamentoColunas,
        'destacarTotal': destacarTotal,
        'destacarTroco': destacarTroco,
        'divisoriaAntesRodape': divisoriaAntesRodape,
        'espacoCompacto': espacoCompacto,
        'flexColunaEsquerda': flexColunaEsquerda,
        'larguraColunaValorMm': larguraColunaValorMm,
        'reservarColunaValorFixa': reservarColunaValorFixa,
        'larguraPaginaPdfMm': larguraPaginaPdfMm,
        'margemPaginaMm': margemPaginaMm,
        'margemCorteMm': margemCorteMm,
        'fatorEspacoVertical': fatorEspacoVertical,
        'fatorAlturaPaginaPdf': fatorAlturaPaginaPdf,
        'alturaLogoMm': alturaLogoMm,
        'espacoEntreItensMm': espacoEntreItensMm,
        'exibirEspacoFinal': exibirEspacoFinal,
        'modoImpressaoDireta': modoImpressaoDireta.codigo,
        'estiloCupomNfce': estiloCupomNfce,
      };

  factory ConfigLayoutImpressao.fromJson(
    Map<String, dynamic>? json, {
    required ConfigLayoutImpressao padrao,
  }) {
    if (json == null || json.isEmpty) return padrao;
    LayoutImpressaoPreset preset = LayoutImpressaoPreset.padrao;
    final presetStr = json['preset']?.toString();
    if (presetStr != null) {
      preset = LayoutImpressaoPreset.values.firstWhere(
        (e) => e.name == presetStr,
        orElse: () => LayoutImpressaoPreset.personalizado,
      );
    }
    return ConfigLayoutImpressao(
      preset: preset,
      exibirLogo: json['exibirLogo'] as bool? ?? padrao.exibirLogo,
      familiaFonte: LayoutFamiliaFonte.fromString(
        json['familiaFonte']?.toString(),
      ),
      tamanhoNomeLoja: LayoutTamanhoFonte.fromString(
        json['tamanhoNomeLoja']?.toString(),
      ),
      tamanhoFonteCorpo: json['tamanhoFonteCorpo'] != null
          ? LayoutTamanhoFonte.fromString(json['tamanhoFonteCorpo']?.toString())
          : padrao.tamanhoFonteCorpo,
      exibirTelefone: json['exibirTelefone'] as bool? ?? padrao.exibirTelefone,
      exibirEndereco: json['exibirEndereco'] as bool? ?? padrao.exibirEndereco,
      faixaComDivisorias:
          json['faixaComDivisorias'] as bool? ?? padrao.faixaComDivisorias,
      tituloDocumento:
          json['tituloDocumento']?.toString() ?? padrao.tituloDocumento,
      destacarSegundaVia:
          json['destacarSegundaVia'] as bool? ?? padrao.destacarSegundaVia,
      caractereDivisoriaSimples:
          json['caractereDivisoriaSimples']?.toString() ??
              padrao.caractereDivisoriaSimples,
      caractereDivisoriaDestaque:
          json['caractereDivisoriaDestaque']?.toString() ??
              padrao.caractereDivisoriaDestaque,
      comprimentoDivisoria: LayoutComprimentoDivisoria.fromString(
        json['comprimentoDivisoria']?.toString(),
      ),
      exibirVendedor: json['exibirVendedor'] as bool? ?? padrao.exibirVendedor,
      exibirDocumentoCliente: json['exibirDocumentoCliente'] as bool? ??
          padrao.exibirDocumentoCliente,
      exibirTelefoneCliente: json['exibirTelefoneCliente'] as bool? ??
          padrao.exibirTelefoneCliente,
      exibirEntrega: json['exibirEntrega'] as bool? ?? padrao.exibirEntrega,
      exibirEnderecoEntrega: json['exibirEnderecoEntrega'] as bool? ??
          padrao.exibirEnderecoEntrega,
      exibirValidadeOrcamento: json['exibirValidadeOrcamento'] as bool? ??
          padrao.exibirValidadeOrcamento,
      exibirObservacaoEntrega: json['exibirObservacaoEntrega'] as bool? ??
          padrao.exibirObservacaoEntrega,
      colunasEsquerdaDireita: json['colunasEsquerdaDireita'] as bool? ??
          padrao.colunasEsquerdaDireita,
      cabecalhoColunasItens: json['cabecalhoColunasItens'] as bool? ??
          padrao.cabecalhoColunasItens,
      tamanhoFonteItens: LayoutTamanhoFonte.fromString(
        json['tamanhoFonteItens']?.toString(),
      ),
      tamanhoFonteTotais: json['tamanhoFonteTotais'] != null
          ? LayoutTamanhoFonte.fromString(json['tamanhoFonteTotais']?.toString())
          : padrao.tamanhoFonteTotais,
      linhaQuantidadePreco:
          json['linhaQuantidadePreco'] as bool? ?? padrao.linhaQuantidadePreco,
      divisoriaDestaqueAntesTotais: json['divisoriaDestaqueAntesTotais'] as bool? ??
          padrao.divisoriaDestaqueAntesTotais,
      alinharTotaisColunas:
          json['alinharTotaisColunas'] as bool? ?? padrao.alinharTotaisColunas,
      alinharPagamentoColunas: json['alinharPagamentoColunas'] as bool? ??
          padrao.alinharPagamentoColunas,
      destacarTotal: json['destacarTotal'] as bool? ?? padrao.destacarTotal,
      destacarTroco: json['destacarTroco'] as bool? ?? padrao.destacarTroco,
      divisoriaAntesRodape: json['divisoriaAntesRodape'] as bool? ??
          padrao.divisoriaAntesRodape,
      espacoCompacto:
          json['espacoCompacto'] as bool? ?? padrao.espacoCompacto,
      flexColunaEsquerda: ((json['flexColunaEsquerda'] as num?) ??
              padrao.flexColunaEsquerda)
          .toInt()
          .clamp(2, 7),
      larguraColunaValorMm: ((json['larguraColunaValorMm'] as num?) ??
              padrao.larguraColunaValorMm)
          .toDouble()
          .clamp(20, 40),
      reservarColunaValorFixa: json['reservarColunaValorFixa'] as bool? ??
          padrao.reservarColunaValorFixa,
      larguraPaginaPdfMm:
          ((json['larguraPaginaPdfMm'] as num?) ?? padrao.larguraPaginaPdfMm)
              .toDouble()
              .clamp(68, 80),
      margemPaginaMm: ((json['margemPaginaMm'] as num?) ?? padrao.margemPaginaMm)
          .toDouble()
          .clamp(1, 8),
      margemCorteMm: ((json['margemCorteMm'] as num?) ?? padrao.margemCorteMm)
          .toDouble()
          .clamp(0, 12),
      fatorEspacoVertical:
          ((json['fatorEspacoVertical'] as num?) ?? padrao.fatorEspacoVertical)
              .toDouble()
              .clamp(0.4, 1.3),
      fatorAlturaPaginaPdf:
          ((json['fatorAlturaPaginaPdf'] as num?) ?? padrao.fatorAlturaPaginaPdf)
              .toDouble()
              .clamp(0.75, 1.15),
      alturaLogoMm: ((json['alturaLogoMm'] as num?) ?? padrao.alturaLogoMm)
          .toDouble()
          .clamp(20, 52),
      espacoEntreItensMm:
          ((json['espacoEntreItensMm'] as num?) ?? padrao.espacoEntreItensMm)
              .toDouble()
              .clamp(0.5, 4),
      exibirEspacoFinal:
          json['exibirEspacoFinal'] as bool? ?? padrao.exibirEspacoFinal,
      modoImpressaoDireta: LayoutModoImpressaoDireta.fromString(
        json['modoImpressaoDireta']?.toString(),
      ),
      estiloCupomNfce:
          json['estiloCupomNfce'] as bool? ?? padrao.estiloCupomNfce,
    );
  }
}

/// Layout de cupom e orcamento (unico por loja, sincronizado na rede).
class LayoutImpressaoEmpresa {
  const LayoutImpressaoEmpresa({
    required this.cupom,
    required this.orcamento,
  });

  final ConfigLayoutImpressao cupom;
  final ConfigLayoutImpressao orcamento;

  static LayoutImpressaoEmpresa padrao() => LayoutImpressaoEmpresa(
        cupom: ConfigLayoutImpressao.padraoCupom(),
        orcamento: ConfigLayoutImpressao.padraoOrcamento(),
      );

  Map<String, dynamic> toJson() => {
        'cupom': cupom.toJson(),
        'orcamento': orcamento.toJson(),
      };

  String toJsonString() => jsonEncode(toJson());

  factory LayoutImpressaoEmpresa.fromJson(Map<String, dynamic>? json) {
    if (json == null || json.isEmpty) return padrao();
    return LayoutImpressaoEmpresa(
      cupom: ConfigLayoutImpressao.fromJson(
        json['cupom'] as Map<String, dynamic>?,
        padrao: ConfigLayoutImpressao.padraoCupom(),
      ),
      orcamento: ConfigLayoutImpressao.fromJson(
        json['orcamento'] as Map<String, dynamic>?,
        padrao: ConfigLayoutImpressao.padraoOrcamento(),
      ),
    );
  }

  static LayoutImpressaoEmpresa fromJsonString(String? raw) {
    if (raw == null || raw.trim().isEmpty) return padrao();
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map<String, dynamic>) {
        return LayoutImpressaoEmpresa.fromJson(decoded);
      }
    } catch (_) {}
    return padrao();
  }

  LayoutImpressaoEmpresa copyWith({
    ConfigLayoutImpressao? cupom,
    ConfigLayoutImpressao? orcamento,
  }) {
    return LayoutImpressaoEmpresa(
      cupom: cupom ?? this.cupom,
      orcamento: orcamento ?? this.orcamento,
    );
  }
}
