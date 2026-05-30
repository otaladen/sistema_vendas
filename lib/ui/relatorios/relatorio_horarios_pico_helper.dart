import '../../model/venda.dart';

/// Resumo de vendas agrupadas por hora do dia (0–23).
class ResumoHorariosPico {
  const ResumoHorariosPico({
    required this.vendasPorHora,
    required this.totalVendas,
    required this.horaPico,
    required this.vendasNaHoraPico,
  });

  final List<int> vendasPorHora;
  final int totalVendas;
  final int horaPico;
  final int vendasNaHoraPico;

  int vendasNaHora(int hora) =>
      hora >= 0 && hora < 24 ? vendasPorHora[hora] : 0;

  double percentualNaHora(int hora) {
    if (totalVendas <= 0) return 0;
    return (vendasNaHora(hora) / totalVendas) * 100;
  }
}

ResumoHorariosPico relatorioCalcularHorariosPico(List<Venda> vendas) {
  final porHora = List<int>.filled(24, 0);
  for (final v in vendas) {
    porHora[v.data.toLocal().hour]++;
  }
  var horaPico = 0;
  var max = 0;
  for (var h = 0; h < 24; h++) {
    if (porHora[h] > max) {
      max = porHora[h];
      horaPico = h;
    }
  }
  return ResumoHorariosPico(
    vendasPorHora: porHora,
    totalVendas: vendas.length,
    horaPico: horaPico,
    vendasNaHoraPico: max,
  );
}

/// Ex.: `14h–15h` (vendas entre 14:00 e 14:59).
String relatorioFormatarFaixaHoraria(int hora) {
  final h = hora.clamp(0, 23);
  final fim = (h + 1) % 24;
  return '${h.toString().padLeft(2, '0')}h–${fim.toString().padLeft(2, '0')}h';
}

String relatorioFormatarRotuloHoraEixo(int hora) {
  return '${hora.clamp(0, 23).toString().padLeft(2, '0')}h';
}
