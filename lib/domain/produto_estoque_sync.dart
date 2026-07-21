import '../data/sync/sync_entity_codec.dart';
import '../model/produto.dart';

class ProdutoMergeRemoto {
  const ProdutoMergeRemoto({
    required this.produto,
    this.estoqueLocalPreservado = false,
  });

  final Produto produto;
  final bool estoqueLocalPreservado;
}

/// Controle de concorrencia para estoque em sync LAN (last-write-wins por versao).
abstract final class ProdutoEstoqueSync {
  /// Incrementa antes de persistir alteracao local de estoque.
  static void marcarEstoqueAlterado(Produto produto) {
    produto.estoqueVersao++;
    produto.estoqueAtual = produto.estoqueReal;
  }

  /// Mescla cadastro remoto preservando estoque local quando a versao local e maior.
  static ProdutoMergeRemoto mergeProdutoRemoto({
    required Produto? local,
    required Map<String, dynamic> payload,
  }) {
    final remoto = SyncEntityCodec.produtoDeMap(payload);
    if (local == null || local.id <= 0) {
      return ProdutoMergeRemoto(produto: remoto);
    }

    final merged = SyncEntityCodec.produtoDeMap(payload);
    merged.id = local.id;

    final versaoRem = remoto.estoqueVersao;
    final versaoLoc = local.estoqueVersao;

    if (versaoRem > versaoLoc) {
      _preservarFotoSeRemotoVazio(merged, local);
      return ProdutoMergeRemoto(produto: merged);
    }
    if (versaoLoc > versaoRem) {
      merged.estoqueReal = local.estoqueReal;
      merged.estoqueReservado = local.estoqueReservado;
      merged.estoqueAtual = local.estoqueAtual;
      merged.estoqueVersao = local.estoqueVersao;
      _preservarFotoSeRemotoVazio(merged, local);
      return ProdutoMergeRemoto(
        produto: merged,
        estoqueLocalPreservado: true,
      );
    }
    // Empate: aplica remoto (mesma regra de LWW do sync).
    _preservarFotoSeRemotoVazio(merged, local);
    return ProdutoMergeRemoto(produto: merged);
  }

  /// Evita que um push antigo sem foto apague a foto ja conhecida.
  static void _preservarFotoSeRemotoVazio(Produto merged, Produto local) {
    if (merged.fotoPath.trim().isNotEmpty) return;
    final localFoto = SyncEntityCodec.fotoPathParaSync(local.fotoPath);
    if (localFoto.isEmpty) return;
    merged.fotoPath = localFoto;
  }
}
