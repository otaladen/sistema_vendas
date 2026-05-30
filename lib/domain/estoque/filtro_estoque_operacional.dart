/// Filtros operacionais da tela Estoque (Fase 1).
enum FiltroEstoqueOperacional {
  todos('Todos'),
  abaixoMinimo('Abaixo minimo'),
  ppCritico('PP critico'),
  comReserva('Com reserva'),
  estoqueNegativo('Estoque negativo'),
  semGiro30('Sem giro 30d'),
  semGiro60('Sem giro 60d'),
  semGiro90('Sem giro 90d');

  const FiltroEstoqueOperacional(this.rotulo);
  final String rotulo;

  int? get diasSemGiro {
    switch (this) {
      case FiltroEstoqueOperacional.semGiro30:
        return 30;
      case FiltroEstoqueOperacional.semGiro60:
        return 60;
      case FiltroEstoqueOperacional.semGiro90:
        return 90;
      default:
        return null;
    }
  }
}
