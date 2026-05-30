/// Filtros da listagem de contas a pagar.
enum FiltroContasPagar {
  todos,
  pendentes,
  pagos,
  atrasados,
}

extension FiltroContasPagarExt on FiltroContasPagar {
  String get rotulo {
    switch (this) {
      case FiltroContasPagar.todos:
        return 'Todos';
      case FiltroContasPagar.pendentes:
        return 'Pendentes';
      case FiltroContasPagar.pagos:
        return 'Pagos';
      case FiltroContasPagar.atrasados:
        return 'Atrasados';
    }
  }
}
