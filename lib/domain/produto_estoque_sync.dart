import '../data/sync/sync_entity_codec.dart';
import '../model/produto.dart';

/// Controle de concorrencia para estoque em sync LAN (last-write-wins por versao).
abstract final class ProdutoEstoqueSync {
  /// Incrementa antes de persistir alteracao local de estoque.
  static void marcarEstoqueAlterado(Produto produto) {
    produto.estoqueVersao++;
    produto.estoqueAtual = produto.estoqueReal;
  }

  /// Mescla cadastro remoto preservando estoque local quando a versao local e maior.
  static Produto mergeProdutoRemoto({
    required Produto? local,
    required Map<String, dynamic> payload,
  }) {
    final remoto = SyncEntityCodec.produtoDeMap(payload);
    if (local == null || local.id <= 0) {
      return remoto;
    }

    final merged = SyncEntityCodec.produtoDeMap(payload);
    merged.id = local.id;

    final versaoRem = remoto.estoqueVersao;
    final versaoLoc = local.estoqueVersao;

    if (versaoRem > versaoLoc) {
      return merged;
    }
    if (versaoLoc > versaoRem) {
      merged.estoqueReal = local.estoqueReal;
      merged.estoqueReservado = local.estoqueReservado;
      merged.estoqueAtual = local.estoqueAtual;
      merged.estoqueVersao = local.estoqueVersao;
      return merged;
    }
    // Empate: aplica remoto (mesma regra de LWW do sync).
    return merged;
  }
}
