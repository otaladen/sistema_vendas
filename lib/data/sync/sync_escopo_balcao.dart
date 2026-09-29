/// Entidades que ficam no PC que gravou e nao viajam no sync continuo do balcao.
///
/// O saldo do dia continua em [Produto] e [Venda]. Kardex, log central e
/// metrica de sugestao do PDV sao historico local.
abstract final class SyncEscopoBalcao {
  SyncEscopoBalcao._();

  static const foraDoSyncContinuo = <String>{
    'movimento_estoque',
    'auditoria_evento',
    'sugestao_venda_metrica',
  };

  static bool estaForaDoSyncContinuo(String? entity) {
    final nome = (entity ?? '').trim();
    if (nome.isEmpty) return false;
    return foraDoSyncContinuo.contains(nome);
  }
}
