/// Politica de retencao de copias de backup em disco (Fase 2).
class BackupRetencaoOpcoes {
  BackupRetencaoOpcoes._();

  /// Nao apaga backups antigos automaticamente.
  static const ilimitada = 0;

  static const copias7 = 7;
  static const copias15 = 15;
  static const copias30 = 30;

  static const valoresPermitidos = [ilimitada, copias7, copias15, copias30];

  static int normalizar(int? copias) {
    if (copias == null) return copias15;
    if (valoresPermitidos.contains(copias)) return copias;
    if (copias <= 0) return ilimitada;
    if (copias <= 10) return copias7;
    if (copias <= 22) return copias15;
    return copias30;
  }

  static String rotulo(int copias) {
    switch (normalizar(copias)) {
      case ilimitada:
        return 'Manter todos (sem limite)';
      case copias7:
        return 'Manter ultimos 7 backups';
      case copias30:
        return 'Manter ultimos 30 backups';
      case copias15:
      default:
        return 'Manter ultimos 15 backups';
    }
  }
}
