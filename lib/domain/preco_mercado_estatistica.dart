/// Estatisticas robustas para amostras de preco de mercado.
class PrecoMercadoEstatistica {
  PrecoMercadoEstatistica._();

  /// Remove outliers pelo metodo IQR e devolve precos mantidos (ordenados).
  static List<double> filtrarOutliers(Iterable<double> precos) {
    final limpos = precos.where((p) => p.isFinite && p > 0).toList()..sort();
    if (limpos.length < 4) return List<double>.from(limpos);

    final q1 = _percentil(limpos, 0.25);
    final q3 = _percentil(limpos, 0.75);
    final iqr = q3 - q1;
    if (iqr <= 0) return List<double>.from(limpos);

    final low = q1 - 1.5 * iqr;
    final high = q3 + 1.5 * iqr;
    return limpos.where((p) => p >= low && p <= high).toList();
  }

  static double? mediana(List<double> ordenados) {
    if (ordenados.isEmpty) return null;
    final n = ordenados.length;
    final mid = n ~/ 2;
    if (n.isOdd) return ordenados[mid];
    return (ordenados[mid - 1] + ordenados[mid]) / 2;
  }

  static double? percentil(List<double> ordenados, double p) {
    if (ordenados.isEmpty) return null;
    return _percentil(ordenados, p.clamp(0.0, 1.0));
  }

  static double? minimo(List<double> ordenados) =>
      ordenados.isEmpty ? null : ordenados.first;

  static double? maximo(List<double> ordenados) =>
      ordenados.isEmpty ? null : ordenados.last;

  static double _percentil(List<double> ordenados, double p) {
    if (ordenados.length == 1) return ordenados.first;
    final pos = (ordenados.length - 1) * p;
    final lo = pos.floor();
    final hi = pos.ceil();
    if (lo == hi) return ordenados[lo];
    final w = pos - lo;
    return ordenados[lo] * (1 - w) + ordenados[hi] * w;
  }
}
