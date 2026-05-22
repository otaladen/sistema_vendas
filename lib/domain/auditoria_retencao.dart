/// Politica de retencao do log central (Fase 3).
class AuditoriaRetencaoOpcoes {
  AuditoriaRetencaoOpcoes._();

  /// Nao apaga automaticamente no inicio do app.
  static const desativada = 0;

  static const dias90 = 90;
  static const dias180 = 180;

  static const valoresPermitidos = [desativada, dias90, dias180];

  static int normalizar(int? dias) {
    if (dias == null) return dias90;
    if (valoresPermitidos.contains(dias)) return dias;
    if (dias <= 0) return desativada;
    if (dias <= 120) return dias90;
    return dias180;
  }

  static String rotulo(int dias) {
    switch (normalizar(dias)) {
      case desativada:
        return 'Sem limpeza automatica';
      case dias180:
        return 'Manter ultimos 180 dias';
      case dias90:
      default:
        return 'Manter ultimos 90 dias';
    }
  }
}
