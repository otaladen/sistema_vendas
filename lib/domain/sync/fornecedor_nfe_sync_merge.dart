/// Resolve conflito de sync quando o mesmo CNPJ chega com IDs locais diferentes.
abstract final class FornecedorNfeSyncMerge {
  FornecedorNfeSyncMerge._();

  /// [idLocalPorCnpj]: ID ja existente no ObjectBox com o mesmo CNPJ (ou null).
  /// [incomingId]: ID vindo do payload remoto (global do servidor).
  ///
  /// Em conflito, preserva o registro local e indica alias do ID remoto → local
  /// (vinculos remotos apontando ao ID remoto passam a usar o local).
  static ({int idManter, bool aliasIncomingParaLocal}) decidir({
    required int incomingId,
    required int? idLocalPorCnpj,
  }) {
    if (idLocalPorCnpj == null) {
      return (
        idManter: incomingId > 0 ? incomingId : 0,
        aliasIncomingParaLocal: false,
      );
    }
    if (incomingId <= 0 || incomingId == idLocalPorCnpj) {
      return (idManter: idLocalPorCnpj, aliasIncomingParaLocal: false);
    }
    return (idManter: idLocalPorCnpj, aliasIncomingParaLocal: true);
  }
}

/// Mesma ideia para NF-e importada (chave de acesso unica).
abstract final class NfeImportadaSyncMerge {
  NfeImportadaSyncMerge._();

  static ({int idManter, bool aliasIncomingParaLocal}) decidir({
    required int incomingId,
    required int? idLocalPorChave,
  }) {
    if (idLocalPorChave == null) {
      return (
        idManter: incomingId > 0 ? incomingId : 0,
        aliasIncomingParaLocal: false,
      );
    }
    if (incomingId <= 0 || incomingId == idLocalPorChave) {
      return (idManter: idLocalPorChave, aliasIncomingParaLocal: false);
    }
    return (idManter: idLocalPorChave, aliasIncomingParaLocal: true);
  }
}
