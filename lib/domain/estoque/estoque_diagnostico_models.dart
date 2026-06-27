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
}
