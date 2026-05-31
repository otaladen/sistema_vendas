/// Politicas de alerta da folha simplificada.
abstract final class FuncionarioFolhaPolitica {
  static const double pctAlertaValesSalario = 0.40;
  static const int qtdAlertaValesMes = 3;
}

enum FuncionarioFolhaAlertaTipo {
  valesAltoPercentual,
  muitosValesNoMes,
}

class FuncionarioFolhaAlerta {
  const FuncionarioFolhaAlerta({
    required this.tipo,
    required this.funcionarioId,
    required this.nome,
    required this.codigo,
    required this.mensagem,
  });

  final FuncionarioFolhaAlertaTipo tipo;
  final int funcionarioId;
  final String nome;
  final String codigo;
  final String mensagem;
}

class FuncionarioMesResumo {
  const FuncionarioMesResumo({
    required this.funcionarioId,
    required this.mesReferencia,
    required this.salarioBase,
    required this.descontoFixo,
    required this.totalVales,
    required this.totalDescontosLancados,
    required this.totalBonus,
    required this.qtdVales,
    required this.liquidoApagar,
    required this.fechado,
    this.contaPagarId = 0,
  });

  final int funcionarioId;
  final DateTime mesReferencia;
  final double salarioBase;
  final double descontoFixo;
  final double totalVales;
  final double totalDescontosLancados;
  final double totalBonus;
  final int qtdVales;
  final double liquidoApagar;
  final bool fechado;
  final int contaPagarId;

  double get pctValesSalario =>
      salarioBase <= 0 ? 0 : totalVales / salarioBase;
}

class FolhaSetorLinha {
  const FolhaSetorLinha({
    required this.setorId,
    required this.setorRotulo,
    required this.qtdFuncionarios,
    required this.qtdAtivos,
    required this.folhaBase,
    required this.totalVales,
    required this.liquidoEstimado,
  });

  final String setorId;
  final String setorRotulo;
  final int qtdFuncionarios;
  final int qtdAtivos;
  final double folhaBase;
  final double totalVales;
  final double liquidoEstimado;
}

class FolhaMesHistoricoItem {
  const FolhaMesHistoricoItem({
    required this.mesReferencia,
    required this.liquidoApagar,
    required this.fechado,
    required this.totalVales,
  });

  final DateTime mesReferencia;
  final double liquidoApagar;
  final bool fechado;
  final double totalVales;
}
