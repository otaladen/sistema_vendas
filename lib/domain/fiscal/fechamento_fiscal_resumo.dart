import '../../services/fechamento_contabil_service.dart';

/// KPIs do mes para tela de relatorio fiscal (sem exportar ZIP).
class FechamentoFiscalResumo {
  const FechamentoFiscalResumo({
    required this.mes,
    required this.ano,
    required this.totalSaidas,
    required this.saidasAutorizadas,
    required this.saidasCanceladas,
    required this.saidasRejeitadas,
    required this.nfce65,
    required this.nfe55,
    required this.valorSaidasAutorizadas,
    required this.valorSaidasCanceladas,
    required this.totalEntradas,
    required this.valorEntradas,
    required this.alertasVendaCancelada,
  });

  final int mes;
  final int ano;
  final int totalSaidas;
  final int saidasAutorizadas;
  final int saidasCanceladas;
  final int saidasRejeitadas;
  final int nfce65;
  final int nfe55;
  final double valorSaidasAutorizadas;
  final double valorSaidasCanceladas;
  final int totalEntradas;
  final double valorEntradas;
  final int alertasVendaCancelada;

  static FechamentoFiscalResumo calcular(
    int mes,
    int ano,
    FechamentoContabilPacote pacote,
  ) {
    var aut = 0;
    var canc = 0;
    var rej = 0;
    var nfe55 = 0;
    var nfce = 0;
    var valorAut = 0.0;
    var valorCanc = 0.0;
    var alertas = 0;
    for (final s in pacote.saidas) {
      if (s.modelo == '55') {
        nfe55++;
      } else {
        nfce++;
      }
      if (s.cancelada) {
        canc++;
        valorCanc += s.valorTotal;
      } else if (s.autorizada) {
        aut++;
        valorAut += s.valorTotal;
      } else if (s.rejeitada) {
        rej++;
      }
      if (s.vendaOperacionalCancelada) alertas++;
    }
    var valorEnt = 0.0;
    for (final e in pacote.entradas) {
      valorEnt += e.valorTotal;
    }
    return FechamentoFiscalResumo(
      mes: mes,
      ano: ano,
      totalSaidas: pacote.saidas.length,
      saidasAutorizadas: aut,
      saidasCanceladas: canc,
      saidasRejeitadas: rej,
      nfce65: nfce,
      nfe55: nfe55,
      valorSaidasAutorizadas: valorAut,
      valorSaidasCanceladas: valorCanc,
      totalEntradas: pacote.entradas.length,
      valorEntradas: valorEnt,
      alertasVendaCancelada: alertas,
    );
  }
}
