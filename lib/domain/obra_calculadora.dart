import 'dart:math' as math;

/// Tipos de receita suportados na calculadora de obra.
enum ObraReceitaTipo {
  parede,
  reboco,
  piso,
  contrapiso,
  laje,
  fundacao,
  telhado,
}

extension ObraReceitaTipoExt on ObraReceitaTipo {
  String get rotulo => switch (this) {
        ObraReceitaTipo.parede => 'Parede (alvenaria)',
        ObraReceitaTipo.reboco => 'Reboco / chapisco',
        ObraReceitaTipo.piso => 'Piso (ceramica)',
        ObraReceitaTipo.contrapiso => 'Contrapiso',
        ObraReceitaTipo.laje => 'Laje (concreto)',
        ObraReceitaTipo.fundacao => 'Fundacao',
        ObraReceitaTipo.telhado => 'Telhado',
      };

  bool get usaConcreto =>
      this == ObraReceitaTipo.laje || this == ObraReceitaTipo.fundacao;
}

/// Tipos de tijolo suportados (parede de vedacao).
enum TipoTijoloObra {
  ceramico8f_9x19x19,
  ceramico6f_9x14x19,
  ceramico8f_9x19x29,
}

extension TipoTijoloObraExt on TipoTijoloObra {
  String get rotulo => switch (this) {
        TipoTijoloObra.ceramico8f_9x19x19 => 'Ceramico 8 furos 9×19×19 cm',
        TipoTijoloObra.ceramico6f_9x14x19 => 'Ceramico 6 furos 9×14×19 cm',
        TipoTijoloObra.ceramico8f_9x19x29 => 'Ceramico 8 furos 9×19×29 cm',
      };

  (double larguraFaceM, double alturaFaceM, double espessuraParedeM)
      get dimensoesM => switch (this) {
            TipoTijoloObra.ceramico8f_9x19x19 => (0.19, 0.19, 0.09),
            TipoTijoloObra.ceramico6f_9x14x19 => (0.19, 0.14, 0.09),
            TipoTijoloObra.ceramico8f_9x19x29 => (0.19, 0.29, 0.09),
          };
}

enum ObraMaterialPapel {
  tijolo,
  cimento,
  areia,
  pisoRevestimento,
  brita,
  telha,
  ferro,
}

enum ObraAberturaTipo { porta, janela, personalizada }

/// Abertura padrao ou customizada para desconto de area em parede.
class ObraAberturaPadrao {
  const ObraAberturaPadrao({
    required this.tipo,
    this.quantidade = 1,
    this.larguraM = 0.80,
    this.alturaM = 2.10,
  });

  final ObraAberturaTipo tipo;
  final int quantidade;
  final double larguraM;
  final double alturaM;

  double get areaUnitariaM2 => larguraM * alturaM;
  double get areaTotalM2 => areaUnitariaM2 * quantidade.clamp(1, 99);

  factory ObraAberturaPadrao.porta({int quantidade = 1}) =>
      ObraAberturaPadrao(
        tipo: ObraAberturaTipo.porta,
        quantidade: quantidade,
        larguraM: 0.80,
        alturaM: 2.10,
      );

  factory ObraAberturaPadrao.janela({int quantidade = 1}) =>
      ObraAberturaPadrao(
        tipo: ObraAberturaTipo.janela,
        quantidade: quantidade,
        larguraM: 1.20,
        alturaM: 1.20,
      );

  Map<String, dynamic> toMap() => {
        'tipo': tipo.name,
        'quantidade': quantidade,
        'larguraM': larguraM,
        'alturaM': alturaM,
      };

  factory ObraAberturaPadrao.fromMap(Map<String, dynamic> m) {
    final tipo = ObraAberturaTipo.values.firstWhere(
      (t) => t.name == m['tipo'],
      orElse: () => ObraAberturaTipo.personalizada,
    );
    return ObraAberturaPadrao(
      tipo: tipo,
      quantidade: (m['quantidade'] as num?)?.toInt() ?? 1,
      larguraM: (m['larguraM'] as num?)?.toDouble() ?? 0.80,
      alturaM: (m['alturaM'] as num?)?.toDouble() ?? 2.10,
    );
  }
}

class ObraCalculadoraEntrada {
  const ObraCalculadoraEntrada({
    required this.larguraM,
    required this.alturaM,
    this.tipoTijolo = TipoTijoloObra.ceramico8f_9x19x19,
    this.perdaPct = 10,
    this.juntaM = 0.01,
    this.tracoCimento = 1,
    this.tracoAreia = 4,
    this.pesoSacoCimentoKg = 50,
    this.densidadeCimentoKgM3 = 1440,
    this.aberturas = const [],
  });

  final double larguraM;
  final double alturaM;
  final TipoTijoloObra tipoTijolo;
  final double perdaPct;
  final double juntaM;
  final int tracoCimento;
  final int tracoAreia;
  final double pesoSacoCimentoKg;
  final double densidadeCimentoKgM3;
  final List<ObraAberturaPadrao> aberturas;

  double get areaBrutaM2 => larguraM * alturaM;

  double get areaAberturasM2 =>
      aberturas.fold(0.0, (s, a) => s + a.areaTotalM2);

  double get areaLiquidaM2 =>
      math.max(0, areaBrutaM2 - areaAberturasM2);

  bool get valida => larguraM > 0 && alturaM > 0 && areaLiquidaM2 > 0 && perdaPct >= 0;
}

class ObraArgamassaEntrada {
  const ObraArgamassaEntrada({
    required this.areaM2,
    this.perdaPct = 15,
    this.espessuraMm = 20,
    this.tracoCimento = 1,
    this.tracoAreia = 4,
    this.pesoSacoCimentoKg = 50,
    this.densidadeCimentoKgM3 = 1440,
    this.rotuloReceita = 'Reboco',
  });

  final double areaM2;
  final double perdaPct;
  final double espessuraMm;
  final int tracoCimento;
  final int tracoAreia;
  final double pesoSacoCimentoKg;
  final double densidadeCimentoKgM3;
  final String rotuloReceita;

  bool get valida => areaM2 > 0 && espessuraMm > 0 && perdaPct >= 0;
}

class ObraPisoEntrada {
  const ObraPisoEntrada({
    required this.areaM2,
    this.perdaPct = 10,
    this.m2PorCaixa = 1.44,
  });

  final double areaM2;
  final double perdaPct;
  final double m2PorCaixa;

  bool get valida => areaM2 > 0 && m2PorCaixa > 0 && perdaPct >= 0;
}

class ObraLajeEntrada {
  const ObraLajeEntrada({
    required this.areaM2,
    this.perdaPct = 10,
    this.espessuraMm = 100,
    this.tracoCimento = 1,
    this.tracoAreia = 2,
    this.tracoBrita = 3,
    this.pesoSacoCimentoKg = 50,
    this.densidadeCimentoKgM3 = 1440,
  });

  final double areaM2;
  final double perdaPct;
  final double espessuraMm;
  final int tracoCimento;
  final int tracoAreia;
  final int tracoBrita;
  final double pesoSacoCimentoKg;
  final double densidadeCimentoKgM3;

  double get volumeM3 => areaM2 * (espessuraMm / 1000);

  bool get valida => areaM2 > 0 && espessuraMm > 0 && perdaPct >= 0;
}

class ObraFundacaoEntrada {
  const ObraFundacaoEntrada({
    required this.comprimentoM,
    required this.larguraM,
    required this.profundidadeM,
    this.perdaPct = 10,
    this.tracoCimento = 1,
    this.tracoAreia = 2,
    this.tracoBrita = 3,
    this.pesoSacoCimentoKg = 50,
    this.densidadeCimentoKgM3 = 1440,
    this.kgFerroPorM3 = 80,
  });

  final double comprimentoM;
  final double larguraM;
  final double profundidadeM;
  final double perdaPct;
  final int tracoCimento;
  final int tracoAreia;
  final int tracoBrita;
  final double pesoSacoCimentoKg;
  final double densidadeCimentoKgM3;
  final double kgFerroPorM3;

  double get volumeM3 => comprimentoM * larguraM * profundidadeM;

  bool get valida =>
      comprimentoM > 0 &&
      larguraM > 0 &&
      profundidadeM > 0 &&
      perdaPct >= 0;
}

class ObraTelhadoEntrada {
  const ObraTelhadoEntrada({
    required this.areaM2,
    this.perdaPct = 10,
    this.inclinacaoPct = 30,
    this.telhasPorM2 = 16,
  });

  final double areaM2;
  final double perdaPct;
  final double inclinacaoPct;
  final double telhasPorM2;

  double get areaInclinadaM2 {
    final i = inclinacaoPct.clamp(0, 60) / 100;
    return areaM2 * math.sqrt(1 + i * i);
  }

  bool get valida => areaM2 > 0 && telhasPorM2 > 0 && perdaPct >= 0;
}

class ObraCalculadoraParseResult {
  const ObraCalculadoraParseResult({
    required this.tipo,
    required this.larguraM,
    required this.alturaM,
    this.areaM2 = 0,
    this.comprimentoM = 0,
    this.profundidadeM = 0,
    this.tipoTijolo = TipoTijoloObra.ceramico8f_9x19x19,
    this.perdaPct = 10,
    this.espessuraMm = 20,
    this.inclinacaoPct = 30,
    this.aberturas = const [],
  });

  final ObraReceitaTipo tipo;
  final double larguraM;
  final double alturaM;
  final double areaM2;
  final double comprimentoM;
  final double profundidadeM;
  final TipoTijoloObra tipoTijolo;
  final double perdaPct;
  final double espessuraMm;
  final double inclinacaoPct;
  final List<ObraAberturaPadrao> aberturas;

  double get areaCalculadaM2 {
    if (areaM2 > 0) return areaM2;
    if (larguraM > 0 && alturaM > 0) return larguraM * alturaM;
    return 0;
  }
}

class ObraCalculadoraMaterialCalculado {
  const ObraCalculadoraMaterialCalculado({
    required this.papel,
    required this.quantidade,
    required this.unidadeRotulo,
    required this.rotulo,
    required this.detalhe,
  });

  final ObraMaterialPapel papel;
  final double quantidade;
  final String unidadeRotulo;
  final String rotulo;
  final String detalhe;
}

class ObraCalculadoraResultado {
  const ObraCalculadoraResultado({
    required this.tipo,
    required this.areaM2,
    required this.materiais,
    this.areaBrutaM2,
    this.areaAberturasM2 = 0,
    this.tijolosPorM2 = 0,
    this.entradaParede,
    this.entradaArgamassa,
    this.entradaPiso,
    this.entradaLaje,
    this.entradaFundacao,
    this.entradaTelhado,
    this.volumeM3 = 0,
  });

  final ObraReceitaTipo tipo;
  final double areaM2;
  final double? areaBrutaM2;
  final double areaAberturasM2;
  final double tijolosPorM2;
  final double volumeM3;
  final List<ObraCalculadoraMaterialCalculado> materiais;
  final ObraCalculadoraEntrada? entradaParede;
  final ObraArgamassaEntrada? entradaArgamassa;
  final ObraPisoEntrada? entradaPiso;
  final ObraLajeEntrada? entradaLaje;
  final ObraFundacaoEntrada? entradaFundacao;
  final ObraTelhadoEntrada? entradaTelhado;

  String get resumo {
    final parts = materiais
        .map(
          (m) =>
              '${m.quantidade.toStringAsFixed(_casasDecimais(m.papel))} '
              '${m.unidadeRotulo} ${m.rotulo}',
        )
        .join(' · ');
    final prefix = switch (tipo) {
      ObraReceitaTipo.parede => '${areaM2.toStringAsFixed(2)} m² parede',
      ObraReceitaTipo.reboco => '${areaM2.toStringAsFixed(2)} m² reboco',
      ObraReceitaTipo.piso => '${areaM2.toStringAsFixed(2)} m² piso',
      ObraReceitaTipo.contrapiso => '${areaM2.toStringAsFixed(2)} m² contrapiso',
      ObraReceitaTipo.laje =>
        '${areaM2.toStringAsFixed(2)} m² laje · ${volumeM3.toStringAsFixed(2)} m³',
      ObraReceitaTipo.fundacao =>
        '${volumeM3.toStringAsFixed(2)} m³ fundacao',
      ObraReceitaTipo.telhado =>
        '${areaM2.toStringAsFixed(2)} m² telhado',
    };
    return '$prefix · $parts';
  }

  static int _casasDecimais(ObraMaterialPapel p) =>
      switch (p) {
        ObraMaterialPapel.areia ||
        ObraMaterialPapel.brita ||
        ObraMaterialPapel.pisoRevestimento =>
          2,
        ObraMaterialPapel.ferro => 1,
        _ => 0,
      };
}

abstract final class ObraCalculadora {
  ObraCalculadora._();

  /// Exibido no PDV ao montar materiais.
  static const avisoEstimativa =
      'Quantidades estimadas — confira com o responsavel tecnico da obra.';

  /// Fator de correcao da area do telhado pela inclinacao (% = cm por 100 cm).
  static double fatorInclinacaoTelhado(double inclinacaoPct) {
    final i = inclinacaoPct.clamp(0, 60) / 100;
    return math.sqrt(1 + i * i);
  }

  /// Consumo de referencia por m³ de concreto estrutural (traço 1:2:3, mercado BR).
  static const double _kgCimentoM3Traco123 = 350;
  static const double _areiaM3Traco123 = 0.50;
  static const double _britaM3Traco123 = 0.80;
  static const int _partesTraco123 = 6;

  static double _kgCimentoAssentamentoM2(
    TipoTijoloObra tipo,
    int tracoCimento,
    int tracoAreia,
  ) {
    final baseKg = switch (tipo) {
      TipoTijoloObra.ceramico8f_9x19x19 => 15.0,
      TipoTijoloObra.ceramico6f_9x14x19 => 18.0,
      TipoTijoloObra.ceramico8f_9x19x29 => 12.0,
    };
    return baseKg *
        (tracoCimento / 1.0) *
        (4.0 / math.max(1, tracoAreia));
  }

  static double _areiaAssentamentoM3PorM2(
    TipoTijoloObra tipo,
    int tracoAreia,
  ) {
    final base = switch (tipo) {
      TipoTijoloObra.ceramico8f_9x19x19 => 0.040,
      TipoTijoloObra.ceramico6f_9x14x19 => 0.048,
      TipoTijoloObra.ceramico8f_9x19x29 => 0.032,
    };
    return base * (tracoAreia / 4.0);
  }

  static List<ObraCalculadoraMaterialCalculado> _materiaisAssentamentoParede({
    required double areaM2,
    required double fatorPerda,
    required TipoTijoloObra tipoTijolo,
    required int tracoCimento,
    required int tracoAreia,
    required double pesoSacoCimentoKg,
  }) {
    final kgCimento =
        areaM2 *
        _kgCimentoAssentamentoM2(tipoTijolo, tracoCimento, tracoAreia) *
        fatorPerda;
    final volAreia =
        areaM2 * _areiaAssentamentoM3PorM2(tipoTijolo, tracoAreia) * fatorPerda;
    final sacos = pesoSacoCimentoKg > 0
        ? (kgCimento / pesoSacoCimentoKg).ceilToDouble()
        : 0.0;
    return [
      ObraCalculadoraMaterialCalculado(
        papel: ObraMaterialPapel.cimento,
        quantidade: sacos,
        unidadeRotulo: 'SC',
        rotulo: 'Cimento (assentamento $tracoCimento:$tracoAreia)',
        detalhe:
            '${kgCimento.toStringAsFixed(0)} kg · ~${_kgCimentoAssentamentoM2(tipoTijolo, tracoCimento, tracoAreia).toStringAsFixed(0)} kg/m²',
      ),
      ObraCalculadoraMaterialCalculado(
        papel: ObraMaterialPapel.areia,
        quantidade: _arredondarAreiaM3(volAreia),
        unidadeRotulo: 'M³',
        rotulo: 'Areia media',
        detalhe: 'Assentamento de alvenaria',
      ),
    ];
  }

  static double tijolosPorMetroQuadrado(
    TipoTijoloObra tipo, {
    double juntaM = 0.01,
  }) {
    final (larg, alt, _) = tipo.dimensoesM;
    final denom = (larg + juntaM) * (alt + juntaM);
    if (denom <= 0) return 0;
    return 1 / denom;
  }

  static ObraCalculadoraResultado? calcularParedeAlvenaria(
    ObraCalculadoraEntrada entrada,
  ) {
    if (!entrada.valida) return null;

    final area = entrada.areaLiquidaM2;
    final fatorPerda = 1 + (entrada.perdaPct.clamp(0, 50) / 100);
    final nPorM2 = tijolosPorMetroQuadrado(
      entrada.tipoTijolo,
      juntaM: entrada.juntaM,
    );
    final tijolos = (area * nPorM2 * fatorPerda).ceilToDouble();

    final materiaisArg = _materiaisAssentamentoParede(
      areaM2: area,
      fatorPerda: fatorPerda,
      tipoTijolo: entrada.tipoTijolo,
      tracoCimento: entrada.tracoCimento,
      tracoAreia: entrada.tracoAreia,
      pesoSacoCimentoKg: entrada.pesoSacoCimentoKg,
    );

    return ObraCalculadoraResultado(
      tipo: ObraReceitaTipo.parede,
      areaM2: area,
      areaBrutaM2: entrada.areaBrutaM2,
      areaAberturasM2: entrada.areaAberturasM2,
      tijolosPorM2: nPorM2,
      entradaParede: entrada,
      materiais: [
        ObraCalculadoraMaterialCalculado(
          papel: ObraMaterialPapel.tijolo,
          quantidade: tijolos,
          unidadeRotulo: 'UN',
          rotulo: 'Tijolos',
          detalhe:
              '${area.toStringAsFixed(2)} m² × ${nPorM2.toStringAsFixed(1)}/m² '
              '+ ${entrada.perdaPct.toStringAsFixed(0)}% perda'
              '${entrada.areaAberturasM2 > 0 ? ' · −${entrada.areaAberturasM2.toStringAsFixed(2)} m² aberturas' : ''}',
        ),
        ...materiaisArg,
      ],
    );
  }

  static ObraCalculadoraResultado? calcularReboco(ObraArgamassaEntrada entrada) {
    if (!entrada.valida) return null;
    return _calcularArgamassaSuperficie(
      entrada: entrada.copyWith(rotuloReceita: 'Reboco'),
      tipo: ObraReceitaTipo.reboco,
    );
  }

  static ObraCalculadoraResultado? calcularContrapiso(
    ObraArgamassaEntrada entrada,
  ) {
    if (!entrada.valida) return null;
    return _calcularArgamassaSuperficie(
      entrada: entrada.copyWith(rotuloReceita: 'Contrapiso'),
      tipo: ObraReceitaTipo.contrapiso,
    );
  }

  static ObraCalculadoraResultado? calcularPiso(ObraPisoEntrada entrada) {
    if (!entrada.valida) return null;
    final fator = 1 + (entrada.perdaPct.clamp(0, 50) / 100);
    final areaComPerda = entrada.areaM2 * fator;
    final caixas = (areaComPerda / entrada.m2PorCaixa).ceilToDouble();
    return ObraCalculadoraResultado(
      tipo: ObraReceitaTipo.piso,
      areaM2: entrada.areaM2,
      entradaPiso: entrada,
      materiais: [
        ObraCalculadoraMaterialCalculado(
          papel: ObraMaterialPapel.pisoRevestimento,
          quantidade: caixas,
          unidadeRotulo: 'CX',
          rotulo: 'Revestimento piso',
          detalhe:
              '${entrada.areaM2.toStringAsFixed(2)} m² ÷ ${entrada.m2PorCaixa.toStringAsFixed(2)} m²/cx '
              '+ ${entrada.perdaPct.toStringAsFixed(0)}% perda',
        ),
      ],
    );
  }

  static ObraCalculadoraResultado? calcularLaje(ObraLajeEntrada entrada) {
    if (!entrada.valida) return null;
    final vol = entrada.volumeM3;
    final materiais = _materiaisConcreto(
      volumeM3: vol,
      perdaPct: entrada.perdaPct,
      tracoCimento: entrada.tracoCimento,
      tracoAreia: entrada.tracoAreia,
      tracoBrita: entrada.tracoBrita,
      pesoSacoCimentoKg: entrada.pesoSacoCimentoKg,
      densidadeCimentoKgM3: entrada.densidadeCimentoKgM3,
      rotuloCimento: 'Cimento (laje ${entrada.tracoCimento}:${entrada.tracoAreia}:${entrada.tracoBrita})',
    );
    return ObraCalculadoraResultado(
      tipo: ObraReceitaTipo.laje,
      areaM2: entrada.areaM2,
      volumeM3: vol * (1 + entrada.perdaPct.clamp(0, 50) / 100),
      entradaLaje: entrada,
      materiais: materiais,
    );
  }

  static ObraCalculadoraResultado? calcularFundacao(
    ObraFundacaoEntrada entrada,
  ) {
    if (!entrada.valida) return null;
    final fator = 1 + (entrada.perdaPct.clamp(0, 50) / 100);
    final vol = entrada.volumeM3 * fator;
    final materiais = [
      ..._materiaisConcreto(
        volumeM3: entrada.volumeM3,
        perdaPct: entrada.perdaPct,
        tracoCimento: entrada.tracoCimento,
        tracoAreia: entrada.tracoAreia,
        tracoBrita: entrada.tracoBrita,
        pesoSacoCimentoKg: entrada.pesoSacoCimentoKg,
        densidadeCimentoKgM3: entrada.densidadeCimentoKgM3,
        rotuloCimento:
            'Cimento (fund. ${entrada.tracoCimento}:${entrada.tracoAreia}:${entrada.tracoBrita})',
      ),
      ObraCalculadoraMaterialCalculado(
        papel: ObraMaterialPapel.ferro,
        quantidade: (vol * entrada.kgFerroPorM3).ceilToDouble(),
        unidadeRotulo: 'KG',
        rotulo: 'Ferro (armacao)',
        detalhe:
            '${entrada.kgFerroPorM3.toStringAsFixed(0)} kg/m³ × ${vol.toStringAsFixed(2)} m³',
      ),
    ];
    return ObraCalculadoraResultado(
      tipo: ObraReceitaTipo.fundacao,
      areaM2: entrada.comprimentoM * entrada.larguraM,
      volumeM3: vol,
      entradaFundacao: entrada,
      materiais: materiais,
    );
  }

  static ObraCalculadoraResultado? calcularTelhado(
    ObraTelhadoEntrada entrada,
  ) {
    if (!entrada.valida) return null;
    final fator = 1 + (entrada.perdaPct.clamp(0, 50) / 100);
    final areaIncl = entrada.areaInclinadaM2;
    final telhas = (areaIncl * entrada.telhasPorM2 * fator).ceilToDouble();
    return ObraCalculadoraResultado(
      tipo: ObraReceitaTipo.telhado,
      areaM2: entrada.areaM2,
      entradaTelhado: entrada,
      materiais: [
        ObraCalculadoraMaterialCalculado(
          papel: ObraMaterialPapel.telha,
          quantidade: telhas,
          unidadeRotulo: 'UN',
          rotulo: 'Telhas',
          detalhe:
              '${areaIncl.toStringAsFixed(2)} m² inclinada × ${entrada.telhasPorM2.toStringAsFixed(0)}/m² '
              '+ ${entrada.perdaPct.toStringAsFixed(0)}% perda',
        ),
      ],
    );
  }

  static List<ObraCalculadoraMaterialCalculado> _materiaisConcreto({
    required double volumeM3,
    required double perdaPct,
    required int tracoCimento,
    required int tracoAreia,
    required int tracoBrita,
    required double pesoSacoCimentoKg,
    required double densidadeCimentoKgM3,
    required String rotuloCimento,
  }) {
    final fator = 1 + (perdaPct.clamp(0, 50) / 100);
    final vol = volumeM3 * fator;
    final partes = tracoCimento + tracoAreia + tracoBrita;
    final escalaTraco = _partesTraco123 / partes;

    final kgCimento = vol *
        _kgCimentoM3Traco123 *
        (tracoCimento / 1.0) *
        escalaTraco;
    final volAreia =
        vol * _areiaM3Traco123 * (tracoAreia / 2.0) * escalaTraco;
    final volBrita =
        vol * _britaM3Traco123 * (tracoBrita / 3.0) * escalaTraco;
    final sacos = pesoSacoCimentoKg > 0
        ? (kgCimento / pesoSacoCimentoKg).ceilToDouble()
        : 0.0;
    return [
      ObraCalculadoraMaterialCalculado(
        papel: ObraMaterialPapel.cimento,
        quantidade: sacos,
        unidadeRotulo: 'SC',
        rotulo: rotuloCimento,
        detalhe:
            '${vol.toStringAsFixed(2)} m³ concreto · ${kgCimento.toStringAsFixed(0)} kg',
      ),
      ObraCalculadoraMaterialCalculado(
        papel: ObraMaterialPapel.areia,
        quantidade: _arredondarAreiaM3(volAreia),
        unidadeRotulo: 'M³',
        rotulo: 'Areia',
        detalhe: 'Traço $tracoCimento:$tracoAreia:$tracoBrita',
      ),
      ObraCalculadoraMaterialCalculado(
        papel: ObraMaterialPapel.brita,
        quantidade: _arredondarAreiaM3(volBrita),
        unidadeRotulo: 'M³',
        rotulo: 'Brita',
        detalhe: 'Traço $tracoCimento:$tracoAreia:$tracoBrita',
      ),
    ];
  }

  static ObraCalculadoraResultado? calcularDeParse(
    ObraCalculadoraParseResult parse, {
    double perdaRebocoPct = 15,
    double perdaPisoPct = 10,
    double perdaContrapisoPct = 10,
    double m2PorCaixaPiso = 1.44,
    double espessuraRebocoMm = 20,
    double espessuraContrapisoMm = 30,
    double espessuraLajeMm = 100,
    double perdaLajePct = 10,
    double perdaFundacaoPct = 10,
    double perdaTelhadoPct = 10,
    double telhasPorM2 = 16,
    double inclinacaoTelhadoPct = 30,
  }) {
    switch (parse.tipo) {
      case ObraReceitaTipo.parede:
        return calcularParedeAlvenaria(
          ObraCalculadoraEntrada(
            larguraM: parse.larguraM,
            alturaM: parse.alturaM,
            tipoTijolo: parse.tipoTijolo,
            perdaPct: parse.perdaPct,
            aberturas: parse.aberturas,
          ),
        );
      case ObraReceitaTipo.reboco:
        final area = parse.areaCalculadaM2;
        return calcularReboco(
          ObraArgamassaEntrada(
            areaM2: area,
            perdaPct: perdaRebocoPct,
            espessuraMm: parse.espessuraMm > 0 ? parse.espessuraMm : espessuraRebocoMm,
          ),
        );
      case ObraReceitaTipo.piso:
        return calcularPiso(
          ObraPisoEntrada(
            areaM2: parse.areaCalculadaM2,
            perdaPct: perdaPisoPct,
            m2PorCaixa: m2PorCaixaPiso,
          ),
        );
      case ObraReceitaTipo.contrapiso:
        return calcularContrapiso(
          ObraArgamassaEntrada(
            areaM2: parse.areaCalculadaM2,
            perdaPct: perdaContrapisoPct,
            espessuraMm:
                parse.espessuraMm > 0 ? parse.espessuraMm : espessuraContrapisoMm,
          ),
        );
      case ObraReceitaTipo.laje:
        return calcularLaje(
          ObraLajeEntrada(
            areaM2: parse.areaCalculadaM2,
            perdaPct: perdaLajePct,
            espessuraMm:
                parse.espessuraMm > 0 ? parse.espessuraMm : espessuraLajeMm,
          ),
        );
      case ObraReceitaTipo.fundacao:
        final comp = (parse.comprimentoM > 0
                ? parse.comprimentoM
                : (parse.larguraM > 0 ? parse.larguraM : 1.0))
            .toDouble();
        final larg = (parse.alturaM > 0 ? parse.alturaM : 0.40).toDouble();
        final prof = (parse.profundidadeM > 0
                ? parse.profundidadeM
                : (parse.espessuraMm >= 100
                    ? parse.espessuraMm / 1000
                    : 0.50))
            .toDouble();
        return calcularFundacao(
          ObraFundacaoEntrada(
            comprimentoM: comp,
            larguraM: larg,
            profundidadeM: prof,
            perdaPct: perdaFundacaoPct,
          ),
        );
      case ObraReceitaTipo.telhado:
        return calcularTelhado(
          ObraTelhadoEntrada(
            areaM2: parse.areaCalculadaM2,
            perdaPct: perdaTelhadoPct,
            inclinacaoPct: parse.inclinacaoPct > 0
                ? parse.inclinacaoPct
                : inclinacaoTelhadoPct,
            telhasPorM2: telhasPorM2,
          ),
        );
    }
  }

  static ObraCalculadoraResultado? _calcularArgamassaSuperficie({
    required ObraArgamassaEntrada entrada,
    required ObraReceitaTipo tipo,
  }) {
    final fator = 1 + (entrada.perdaPct.clamp(0, 50) / 100);
    final espM = entrada.espessuraMm / 1000;
    final volTotal = entrada.areaM2 * espM * fator;
    final rotulo = entrada.rotuloReceita;
    final materiais = _materiaisArgamassa(
      volArgamassaTotal: volTotal,
      tracoCimento: entrada.tracoCimento,
      tracoAreia: entrada.tracoAreia,
      pesoSacoCimentoKg: entrada.pesoSacoCimentoKg,
      densidadeCimentoKgM3: entrada.densidadeCimentoKgM3,
      rotuloCimento: 'Cimento ($rotulo ${entrada.tracoCimento}:${entrada.tracoAreia})',
    );
    return ObraCalculadoraResultado(
      tipo: tipo,
      areaM2: entrada.areaM2,
      entradaArgamassa: entrada,
      materiais: materiais,
    );
  }

  static List<ObraCalculadoraMaterialCalculado> _materiaisArgamassa({
    required double volArgamassaTotal,
    required int tracoCimento,
    required int tracoAreia,
    required double pesoSacoCimentoKg,
    required double densidadeCimentoKgM3,
    required String rotuloCimento,
  }) {
    final partesTraco = tracoCimento + tracoAreia;
    final volCimento = volArgamassaTotal * (tracoCimento / partesTraco);
    final volAreia = volArgamassaTotal * (tracoAreia / partesTraco);
    final kgCimento = volCimento * densidadeCimentoKgM3;
    final sacosCimento = pesoSacoCimentoKg > 0
        ? (kgCimento / pesoSacoCimentoKg).ceilToDouble()
        : 0.0;
    return [
      ObraCalculadoraMaterialCalculado(
        papel: ObraMaterialPapel.cimento,
        quantidade: sacosCimento,
        unidadeRotulo: 'SC',
        rotulo: rotuloCimento,
        detalhe:
            '${kgCimento.toStringAsFixed(1)} kg · ${volArgamassaTotal.toStringAsFixed(3)} m³ argamassa',
      ),
      ObraCalculadoraMaterialCalculado(
        papel: ObraMaterialPapel.areia,
        quantidade: _arredondarAreiaM3(volAreia),
        unidadeRotulo: 'M³',
        rotulo: 'Areia media',
        detalhe: '${volArgamassaTotal.toStringAsFixed(3)} m³ argamassa total',
      ),
    ];
  }

  static double _arredondarAreiaM3(double v) {
    if (v <= 0) return 0;
    return (v * 100).ceilToDouble() / 100;
  }

  static TipoTijoloObra? detectarTipoTijoloPorTexto(String texto) {
    final t = texto.toLowerCase().replaceAll(' ', '');
    if (RegExp(r'9[x×]19[x×]19').hasMatch(t)) {
      return TipoTijoloObra.ceramico8f_9x19x19;
    }
    if (RegExp(r'9[x×]14[x×]19').hasMatch(t)) {
      return TipoTijoloObra.ceramico6f_9x14x19;
    }
    if (RegExp(r'9[x×]19[x×]29').hasMatch(t)) {
      return TipoTijoloObra.ceramico8f_9x19x29;
    }
    return null;
  }

  /// Parser local (regex) — Fase 2: reboco, piso, contrapiso, aberturas.
  static ObraCalculadoraParseResult? parseTextoLivre(
    String texto, {
    double perdaPadraoPct = 10,
  }) {
    final raw = texto.trim();
    if (raw.isEmpty) return null;
    final lower = raw.toLowerCase();

    final tipo = _detectarTipoReceita(lower);
    final dim = RegExp(
      r'(\d+[,.]?\d*)\s*[x×]\s*(\d+[,.]?\d*)',
      caseSensitive: false,
    ).firstMatch(raw);

    final areaDireta = RegExp(
      r'(\d+[,.]?\d*)\s*m\s*[²2]',
      caseSensitive: false,
    ).firstMatch(raw);

    final dim3 = RegExp(
      r'(\d+[,.]?\d*)\s*[x×]\s*(\d+[,.]?\d*)\s*[x×]\s*(\d+[,.]?\d*)',
      caseSensitive: false,
    ).firstMatch(raw);

    double largura = 0;
    double altura = 0;
    double area = 0;
    double comprimento = 0;
    double profundidade = 0;

    if (dim3 != null && (tipo == ObraReceitaTipo.fundacao || tipo == ObraReceitaTipo.laje)) {
      comprimento = _parseNum(dim3.group(1)!) ?? 0;
      largura = _parseNum(dim3.group(2)!) ?? 0;
      profundidade = _parseNum(dim3.group(3)!) ?? 0;
      area = comprimento * largura;
    } else if (dim != null) {
      largura = _parseNum(dim.group(1)!) ?? 0;
      altura = _parseNum(dim.group(2)!) ?? 0;
      area = largura * altura;
    } else if (areaDireta != null) {
      area = _parseNum(areaDireta.group(1)!) ?? 0;
    }

    if (tipo == ObraReceitaTipo.fundacao) {
      final compMatch = RegExp(
        r'(\d+[,.]?\d*)\s*m(?:etros?)?(?:\s*de|\s*linear)?',
        caseSensitive: false,
      ).firstMatch(lower);
      if (compMatch != null && comprimento <= 0) {
        comprimento = _parseNum(compMatch.group(1)!) ?? 0;
      }
      if (comprimento <= 0 && largura > 0 && profundidade <= 0) {
        comprimento = largura;
        largura = 0.40;
        profundidade = 0.50;
      }
      if (comprimento > 0 && largura <= 0) largura = 0.40;
      if (comprimento > 0 && profundidade <= 0) profundidade = 0.50;
    }

    if (area <= 0 && largura <= 0 && comprimento <= 0) return null;

    final aberturas = _parseAberturas(lower);
    final tipoTijolo =
        detectarTipoTijoloPorTexto(raw) ?? TipoTijoloObra.ceramico8f_9x19x19;

    final espessuraMatch = RegExp(
      r'(\d+[,.]?\d*)\s*mm',
      caseSensitive: false,
    ).firstMatch(raw);
    final espessuraMm = espessuraMatch != null
        ? (_parseNum(espessuraMatch.group(1)!) ?? 20)
        : 20.0;

    final inclMatch = RegExp(
      r'(\d+[,.]?\d*)\s*%\s*inclin',
      caseSensitive: false,
    ).firstMatch(raw);
    final inclinacaoPct = inclMatch != null
        ? (_parseNum(inclMatch.group(1)!) ?? 30)
        : 30.0;

    if (tipo == ObraReceitaTipo.parede &&
        !RegExp(r'parede|muro|alvenaria|veda|tijolo').hasMatch(lower) &&
        dim == null) {
      return null;
    }

    return ObraCalculadoraParseResult(
      tipo: tipo,
      larguraM: largura > 0 ? largura : 0,
      alturaM: altura > 0 ? altura : 0,
      areaM2: area,
      comprimentoM: comprimento,
      profundidadeM: profundidade,
      tipoTijolo: tipoTijolo,
      perdaPct: perdaPadraoPct,
      espessuraMm: espessuraMm,
      inclinacaoPct: inclinacaoPct,
      aberturas: aberturas,
    );
  }

  /// Compatibilidade Fase 1 — retorna entrada de parede quando aplicavel.
  static ObraCalculadoraEntrada? parseTextoLivreParede(
    String texto, {
    double perdaPadraoPct = 10,
  }) {
    final p = parseTextoLivre(texto, perdaPadraoPct: perdaPadraoPct);
    if (p == null || p.tipo != ObraReceitaTipo.parede) return null;
    return ObraCalculadoraEntrada(
      larguraM: p.larguraM > 0 ? p.larguraM : math.sqrt(p.areaM2),
      alturaM: p.alturaM > 0 ? p.alturaM : (p.areaM2 / (p.larguraM > 0 ? p.larguraM : 1)),
      tipoTijolo: p.tipoTijolo,
      perdaPct: p.perdaPct,
      aberturas: p.aberturas,
    );
  }

  static ObraReceitaTipo _detectarTipoReceita(String lower) {
    if (RegExp(r'telhado|cobertura|telha|calha').hasMatch(lower)) {
      return ObraReceitaTipo.telhado;
    }
    if (RegExp(r'fundacao|sapata|baldrame|estaca|broca').hasMatch(lower)) {
      return ObraReceitaTipo.fundacao;
    }
    if (RegExp(r'laje|concreto\s*usinado|placa').hasMatch(lower)) {
      return ObraReceitaTipo.laje;
    }
    if (RegExp(r'contrapiso|massa\s*asf|regulariz').hasMatch(lower)) {
      return ObraReceitaTipo.contrapiso;
    }
    if (RegExp(r'reboco|chapisco|emassamento|massa\s*corrida').hasMatch(lower)) {
      return ObraReceitaTipo.reboco;
    }
    if (RegExp(r'piso|porcelanato|ceramica|revestimento|azulejo\s*piso')
        .hasMatch(lower)) {
      return ObraReceitaTipo.piso;
    }
    return ObraReceitaTipo.parede;
  }

  static List<ObraAberturaPadrao> _parseAberturas(String lower) {
    final out = <ObraAberturaPadrao>[];
    final portas = RegExp(r'(\d+)\s*porta').firstMatch(lower);
    if (portas != null) {
      out.add(
        ObraAberturaPadrao.porta(
          quantidade: int.tryParse(portas.group(1)!) ?? 1,
        ),
      );
    } else if (lower.contains('porta')) {
      out.add(ObraAberturaPadrao.porta());
    }
    final janelas = RegExp(r'(\d+)\s*janela').firstMatch(lower);
    if (janelas != null) {
      out.add(
        ObraAberturaPadrao.janela(
          quantidade: int.tryParse(janelas.group(1)!) ?? 1,
        ),
      );
    } else if (lower.contains('janela')) {
      out.add(ObraAberturaPadrao.janela());
    }
    return out;
  }

  static double? _parseNum(String s) =>
      double.tryParse(s.replaceAll(',', '.').trim());
}

extension ObraArgamassaEntradaCopy on ObraArgamassaEntrada {
  ObraArgamassaEntrada copyWith({
    double? areaM2,
    double? perdaPct,
    double? espessuraMm,
    int? tracoCimento,
    int? tracoAreia,
    double? pesoSacoCimentoKg,
    double? densidadeCimentoKgM3,
    String? rotuloReceita,
  }) {
    return ObraArgamassaEntrada(
      areaM2: areaM2 ?? this.areaM2,
      perdaPct: perdaPct ?? this.perdaPct,
      espessuraMm: espessuraMm ?? this.espessuraMm,
      tracoCimento: tracoCimento ?? this.tracoCimento,
      tracoAreia: tracoAreia ?? this.tracoAreia,
      pesoSacoCimentoKg: pesoSacoCimentoKg ?? this.pesoSacoCimentoKg,
      densidadeCimentoKgM3: densidadeCimentoKgM3 ?? this.densidadeCimentoKgM3,
      rotuloReceita: rotuloReceita ?? this.rotuloReceita,
    );
  }
}
