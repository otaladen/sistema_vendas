/// Politica de retencao das fotos de prova de entrega (POD).
class PodFotoRetencaoOpcoes {
  PodFotoRetencaoOpcoes._();

  static const desativada = 0;
  static const meses3 = 90;
  static const meses6 = 180;
  static const meses12 = 365;
  static const meses24 = 730;

  static const valoresPermitidos = [
    desativada,
    meses3,
    meses6,
    meses12,
    meses24,
  ];

  static int normalizar(int? dias) {
    if (dias == null) return meses6;
    if (valoresPermitidos.contains(dias)) return dias;
    if (dias <= 0) return desativada;
    if (dias <= 120) return meses3;
    if (dias <= 270) return meses6;
    if (dias <= 450) return meses12;
    return meses24;
  }

  static String rotulo(int dias) {
    switch (normalizar(dias)) {
      case desativada:
        return 'Sem limpeza automatica';
      case meses3:
        return 'Manter 3 meses';
      case meses12:
        return 'Manter 12 meses';
      case meses24:
        return 'Manter 24 meses';
      case meses6:
      default:
        return 'Manter 6 meses';
    }
  }
}
