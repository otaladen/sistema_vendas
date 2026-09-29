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

/// Quantos backups completos (com fotos) guardar. Independente dos leves.
class BackupRetencaoCompletosOpcoes {
  BackupRetencaoCompletosOpcoes._();

  static const ilimitada = 0;
  static const copias2 = 2;
  static const copias4 = 4;
  static const copias8 = 8;

  static const valoresPermitidos = [ilimitada, copias2, copias4, copias8];

  static int normalizar(int? copias) {
    if (copias == null) return copias4;
    if (valoresPermitidos.contains(copias)) return copias;
    if (copias <= 0) return ilimitada;
    if (copias <= 3) return copias2;
    if (copias <= 6) return copias4;
    return copias8;
  }

  static String rotulo(int copias) {
    switch (normalizar(copias)) {
      case ilimitada:
        return 'Manter todos os completos';
      case copias2:
        return 'Manter ultimos 2 completos';
      case copias8:
        return 'Manter ultimos 8 completos';
      case copias4:
      default:
        return 'Manter ultimos 4 completos';
    }
  }
}
