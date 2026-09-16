import '../../domain/relatorio_evolucao_mensal.dart';
import 'relatorio_comparativo.dart';

export '../../domain/relatorio_evolucao_mensal.dart';

/// Consolida faturamento mensal no historico local (ObjectBox) ou cache da API.
RelatorioEvolucaoMensal consolidarEvolucaoMensal(
  dynamic vendaRepository, {
  required EvolucaoPeriodoPreset preset,
  DateTime? agora,
}) {
  final limites = limitesPeriodoEvolucao(preset, agora: agora);
  return montarEvolucaoMensal(
    preset: preset,
    inicio: limites.$1,
    fim: limites.$2,
    totaisDoMes: (ini, fim) {
      final t = relatorioTotaisPeriodo(vendaRepository, (ini, fim));
      return EvolucaoTotaisMes(
        faturamento: t.faturamento,
        lucro: t.lucro,
        qtdNotas: t.qtdNotas,
      );
    },
  );
}
