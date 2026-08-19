/// Status da sessao de balanco/inventario.
abstract final class InventarioSessaoStatus {
  static const aberta = 'aberta';
  static const aplicada = 'aplicada';
  static const cancelada = 'cancelada';

  static const Set<String> abertos = {aberta};

  static String rotulo(String status) {
    switch (status) {
      case aplicada:
        return 'Aplicada';
      case cancelada:
        return 'Cancelada';
      default:
        return 'Aberta';
    }
  }
}

/// Estado de cada item na contagem.
abstract final class InventarioItemEstado {
  static const pendente = 'pendente';
  static const conferidoOk = 'conferido_ok';
  static const divergente = 'divergente';

  static String rotulo(String estado) {
    switch (estado) {
      case conferidoOk:
        return 'Conferido OK';
      case divergente:
        return 'Divergente';
      default:
        return 'Pendente';
    }
  }
}

/// Filtros rapidos da tela de contagem.
abstract final class InventarioFiltroLista {
  static const todos = 'todos';
  static const faltaContar = 'falta_contar';
  static const conferidosOk = 'conferidos_ok';
  static const divergentes = 'divergentes';

  static String rotulo(String filtro) {
    switch (filtro) {
      case faltaContar:
        return 'Falta contar';
      case conferidosOk:
        return 'Conferidos OK';
      case divergentes:
        return 'Divergentes';
      default:
        return 'Todos';
    }
  }
}
