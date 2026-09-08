import 'dart:convert';

import '../../model/item_venda.dart';
import '../../model/produto.dart';
import '../item_venda_produto_orfao.dart';
import '../produto_embalagem.dart';

/// Linha de carreto cujo produto foi excluido do cadastro — saida sem baixa de estoque.
class CarretoSaidaProdutoOrfaoLinha {
  const CarretoSaidaProdutoOrfaoLinha({
    required this.itemVendaId,
    required this.nomeProduto,
    required this.quantidade,
    required this.unidade,
  });

  final int itemVendaId;
  final String nomeProduto;
  final int quantidade;
  final String unidade;

  Map<String, dynamic> toJson() => {
        'itemVendaId': itemVendaId,
        'nomeProduto': nomeProduto,
        'quantidade': quantidade,
        'unidade': unidade,
      };
}

/// Auditoria de saida de carreto para itens sem produto no cadastro (JSON em historico).
class CarretoSaidaProdutoOrfaoEvento {
  const CarretoSaidaProdutoOrfaoEvento({
    required this.vendaId,
    required this.numeroOrcamento,
    required this.documento,
    required this.dataHora,
    required this.linhas,
  });

  static const int versao = 1;

  final int vendaId;
  final int numeroOrcamento;
  final String documento;
  final DateTime dataHora;
  final List<CarretoSaidaProdutoOrfaoLinha> linhas;

  String get textoHumano {
    final trecho = linhas
        .map(
          (l) =>
              '${l.nomeProduto} ${l.quantidade} ${l.unidade} (cadastro excluido)',
        )
        .join('; ');
    if (trecho.isEmpty) {
      return 'Saida carreto sem baixa de estoque — produto excluido do cadastro.';
    }
    return 'Saida carreto (sem estoque): $trecho.';
  }

  String encode() => jsonEncode({
        'v': versao,
        'vendaId': vendaId,
        'numeroOrcamento': numeroOrcamento,
        'documento': documento,
        'dataHora': dataHora.toUtc().toIso8601String(),
        'linhas': linhas.map((l) => l.toJson()).toList(),
      });

  static CarretoSaidaProdutoOrfaoEvento? tryParse(String raw) {
    final t = raw.trim();
    if (t.isEmpty || !t.startsWith('{')) return null;
    try {
      final decoded = jsonDecode(t);
      if (decoded is! Map) return null;
      final m = Map<String, dynamic>.from(decoded);
      final linhasRaw = m['linhas'];
      final linhas = <CarretoSaidaProdutoOrfaoLinha>[];
      if (linhasRaw is List) {
        for (final e in linhasRaw) {
          if (e is! Map) continue;
          final lm = Map<String, dynamic>.from(e);
          final q = (lm['quantidade'] as num?)?.toInt() ?? 0;
          if (q <= 0) continue;
          linhas.add(
            CarretoSaidaProdutoOrfaoLinha(
              itemVendaId: (lm['itemVendaId'] as num?)?.toInt() ?? 0,
              nomeProduto: (lm['nomeProduto'] ?? '').toString(),
              quantidade: q,
              unidade: (lm['unidade'] ?? 'UN').toString(),
            ),
          );
        }
      }
      if (linhas.isEmpty) return null;
      return CarretoSaidaProdutoOrfaoEvento(
        vendaId: (m['vendaId'] as num?)?.toInt() ?? 0,
        numeroOrcamento: (m['numeroOrcamento'] as num?)?.toInt() ?? 0,
        documento: (m['documento'] ?? '').toString(),
        dataHora: DateTime.tryParse((m['dataHora'] ?? '').toString())
                ?.toUtc() ??
            DateTime.now().toUtc(),
        linhas: linhas,
      );
    } catch (_) {
      return null;
    }
  }
}

/// Romaneio / carga quando o produto da linha nao existe mais no cadastro.
abstract final class RomaneioProdutoOrfaoHelper {
  RomaneioProdutoOrfaoHelper._();

  static const alertaProdutoNaoEncontrado =
      'Produto nao encontrado no cadastro atual';

  static bool itemOrfao(
    ItemVenda item, {
    Produto? Function(int id)? obterProduto,
  }) {
    return ItemVendaProdutoOrfaoHelper.itemSemProdutoVinculado(
      item,
      obterProduto: obterProduto,
    );
  }

  /// Unidade gravada na venda quando possivel; senao UN.
  static String unidadeSnapshot(
    ItemVenda item, {
    Produto? Function(int id)? obterProduto,
  }) {
    Produto? ligado;
    try {
      ligado = item.produto.target;
    } catch (_) {}
    if (ligado != null) {
      return ProdutoEmbalagem.normalizarUnidade(ligado.unidade);
    }
    final pid = item.produto.targetId;
    if (pid > 0 && obterProduto != null) {
      final p = obterProduto(pid);
      if (p != null) {
        return ProdutoEmbalagem.normalizarUnidade(p.unidade);
      }
    }
    return 'UN';
  }

  static String nomeSnapshot(ItemVenda item) {
    final nome = item.nomeProduto.trim();
    return nome.isEmpty ? 'Produto sem nome' : nome;
  }
}
