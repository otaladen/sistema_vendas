/// Meta mensal rateada pelos dias civis do intervalo (cruza virada de mes).
double relatorioMetaProporcionalPeriodo({
  required double metaMensal,
  required DateTime inicio,
  required DateTime fim,
}) {
  if (metaMensal <= 0.001) return 0;
  var total = 0.0;
  var d = DateTime(inicio.year, inicio.month, inicio.day);
  final last = DateTime(fim.year, fim.month, fim.day);
  while (!d.isAfter(last)) {
    final diasMes = DateTime(d.year, d.month + 1, 0).day;
    if (diasMes > 0) {
      total += metaMensal / diasMes;
    }
    d = d.add(const Duration(days: 1));
  }
  return total;
}

/// Comissao sobre a base; percentual invalido ou base negativa vira zero.
double relatorioComissaoPisoZero(double base, double percentual) {
  if (percentual <= 0) return 0;
  final raw = base * percentual / 100.0;
  return raw < 0 ? 0 : raw;
}
