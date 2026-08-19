import '../model/venda.dart';

/// Enquadramento de periodo da listagem: data da nota **ou** finalizacao no caixa.
abstract final class ListagemVendasPeriodo {
  ListagemVendasPeriodo._();

  static bool noIntervaloUtc(
    Venda venda, {
    DateTime? inicioUtc,
    DateTime? fimUtc,
  }) {
    if (inicioUtc == null && fimUtc == null) return true;
    final ini = inicioUtc?.toUtc();
    final fim = fimUtc?.toUtc();
    return _instanteNoIntervalo(venda.data, ini, fim) ||
        (venda.finalizadaEm != null &&
            _instanteNoIntervalo(venda.finalizadaEm!, ini, fim));
  }

  static bool _instanteNoIntervalo(
    DateTime instante,
    DateTime? inicioUtc,
    DateTime? fimUtc,
  ) {
    final d = instante.toUtc();
    if (inicioUtc != null && d.isBefore(inicioUtc)) return false;
    if (fimUtc != null && d.isAfter(fimUtc)) return false;
    return true;
  }
}
