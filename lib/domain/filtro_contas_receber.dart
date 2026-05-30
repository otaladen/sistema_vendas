/// Filtros da listagem de contas a receber (fiado).
enum FiltroContasReceber {
  todos,
  vencidos,
  venceHoje,
  proximos7,
  emDia,
}

extension FiltroContasReceberExt on FiltroContasReceber {
  String get rotulo {
    switch (this) {
      case FiltroContasReceber.todos:
        return 'Todos';
      case FiltroContasReceber.vencidos:
        return 'Vencidos';
      case FiltroContasReceber.venceHoje:
        return 'Vence hoje';
      case FiltroContasReceber.proximos7:
        return 'Proximos 7 dias';
      case FiltroContasReceber.emDia:
        return 'A vencer';
    }
  }
}
