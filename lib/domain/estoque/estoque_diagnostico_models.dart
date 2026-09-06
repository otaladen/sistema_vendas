/// Severidade de um achado no diagnostico de estoque.
enum EstoqueDiagnosticoSeveridade {
  info,
  alerta,
  critico,
}

/// Codigo estavel para agrupamento e acoes na UI.
enum EstoqueDiagnosticoCodigo {
  vendaBaixaPendente,
  vendaBaixaPendenteNfceProcessando,
  vendaFlagBaixaSemMovimento,
  saldoDivergenteKardex,
  reservaNegativa,
  saldoAbsurdo,
  carretoReservaAusente,
}

class EstoqueDiagnosticoAchado {
  const EstoqueDiagnosticoAchado({
    required this.codigo,
    required this.severidade,
    required this.titulo,
    required this.detalhe,
    this.vendaId,
    this.produtoId,
    this.podeReprocessarBaixa = false,
  });

  final EstoqueDiagnosticoCodigo codigo;
  final EstoqueDiagnosticoSeveridade severidade;
  final String titulo;
  final String detalhe;
  final int? vendaId;
  final int? produtoId;
  final bool podeReprocessarBaixa;
}

class EstoqueDiagnosticoResultado {
  const EstoqueDiagnosticoResultado({
    required this.achados,
    required this.geradoEm,
  });

  final List<EstoqueDiagnosticoAchado> achados;
  final DateTime geradoEm;

  bool get temProblema =>
      achados.any((a) => a.severidade != EstoqueDiagnosticoSeveridade.info);

  int get quantidadeCriticos => achados
      .where((a) => a.severidade == EstoqueDiagnosticoSeveridade.critico)
      .length;

  int get quantidadeAlertas => achados
      .where((a) => a.severidade == EstoqueDiagnosticoSeveridade.alerta)
      .length;

  int get quantidadeInformativos => achados
      .where((a) => a.severidade == EstoqueDiagnosticoSeveridade.info)
      .length;

  static EstoqueDiagnosticoResultado? fromApiMap(Map<String, dynamic>? m) {
    if (m == null) return null;
    final achadosRaw = m['achados'];
    if (achadosRaw is! List) return null;
    final achados = <EstoqueDiagnosticoAchado>[];
    for (final raw in achadosRaw.whereType<Map>()) {
      final a = Map<String, dynamic>.from(raw);
      final codigoNome = (a['codigo'] ?? '').toString();
      final sevNome = (a['severidade'] ?? '').toString();
      achados.add(
        EstoqueDiagnosticoAchado(
          codigo: EstoqueDiagnosticoCodigo.values.firstWhere(
            (c) => c.name == codigoNome,
            orElse: () => EstoqueDiagnosticoCodigo.saldoDivergenteKardex,
          ),
          severidade: EstoqueDiagnosticoSeveridade.values.firstWhere(
            (s) => s.name == sevNome,
            orElse: () => EstoqueDiagnosticoSeveridade.alerta,
          ),
          titulo: (a['titulo'] ?? '').toString(),
          detalhe: (a['detalhe'] ?? '').toString(),
          vendaId: (a['vendaId'] as num?)?.toInt(),
          produtoId: (a['produtoId'] as num?)?.toInt(),
          podeReprocessarBaixa: a['podeReprocessarBaixa'] == true,
        ),
      );
    }
    final geradoEm =
        DateTime.tryParse((m['geradoEm'] ?? '').toString()) ?? DateTime.now();
    return EstoqueDiagnosticoResultado(
      achados: achados,
      geradoEm: geradoEm,
    );
  }
}
