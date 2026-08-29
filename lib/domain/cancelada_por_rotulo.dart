/// Quem cancelou a venda: login de operador ou identificador interno.
///
/// Ferramentas de manutencao gravam slugs (ex. `ferramenta_limpar_entregas`)
/// em [Venda.canceladaPor]; a UI mostra um rotulo humano, o filtro continua
/// usando o valor gravado.
abstract final class CanceladaPorRotulo {
  CanceladaPorRotulo._();

  static const ferramentaLimparEntregas = 'ferramenta_limpar_entregas';
  static const manutencao = 'manutencao';
  static const sistema = 'sistema';

  static String exibicao(String valor) {
    final t = valor.trim();
    if (t.isEmpty) return 'Nao informado';
    switch (t) {
      case ferramentaLimparEntregas:
        return 'Sistema (limpeza de entregas)';
      case manutencao:
        return 'Manutencao';
      case sistema:
        return 'Sistema';
    }
    if (t.startsWith('ferramenta_')) return 'Sistema';
    return t;
  }
}
