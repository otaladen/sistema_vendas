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

  Map<String, dynamic> toJson() => {
        'mes': mes,
        'ano': ano,
        'totalSaidas': totalSaidas,
        'saidasAutorizadas': saidasAutorizadas,
        'saidasCanceladas': saidasCanceladas,
        'saidasRejeitadas': saidasRejeitadas,
        'nfce65': nfce65,
        'nfe55': nfe55,
        'valorSaidasAutorizadas': valorSaidasAutorizadas,
        'valorSaidasCanceladas': valorSaidasCanceladas,
        'totalEntradas': totalEntradas,
        'valorEntradas': valorEntradas,
        'alertasVendaCancelada': alertasVendaCancelada,
      };

  factory FechamentoFiscalResumo.fromJson(Map<String, dynamic> json) {
    return FechamentoFiscalResumo(
      mes: (json['mes'] as num?)?.toInt() ?? 0,
      ano: (json['ano'] as num?)?.toInt() ?? 0,
      totalSaidas: (json['totalSaidas'] as num?)?.toInt() ?? 0,
      saidasAutorizadas: (json['saidasAutorizadas'] as num?)?.toInt() ?? 0,
      saidasCanceladas: (json['saidasCanceladas'] as num?)?.toInt() ?? 0,
      saidasRejeitadas: (json['saidasRejeitadas'] as num?)?.toInt() ?? 0,
      nfce65: (json['nfce65'] as num?)?.toInt() ?? 0,
      nfe55: (json['nfe55'] as num?)?.toInt() ?? 0,
      valorSaidasAutorizadas:
          (json['valorSaidasAutorizadas'] as num?)?.toDouble() ?? 0,
      valorSaidasCanceladas:
          (json['valorSaidasCanceladas'] as num?)?.toDouble() ?? 0,
      totalEntradas: (json['totalEntradas'] as num?)?.toInt() ?? 0,
      valorEntradas: (json['valorEntradas'] as num?)?.toDouble() ?? 0,
      alertasVendaCancelada:
          (json['alertasVendaCancelada'] as num?)?.toInt() ?? 0,
    );
  }
}
