import '../data/kit_orcamento_repository.dart';
import '../data/produto_repository.dart';
import '../model/produto.dart';

/// Linha resolvida de um kit para inserir no orcamento PDV.
class PdvKitOrcamentoLinhaInsercao {
  const PdvKitOrcamentoLinhaInsercao({
    required this.produto,
    required this.quantidade,
  });

  final Produto produto;
  final double quantidade;
}

/// Resultado da montagem de um kit para o carrinho.
class PdvKitOrcamentoInsercaoMontada {
  const PdvKitOrcamentoInsercaoMontada({
    required this.kitId,
    required this.nomeKit,
    required this.quantidadeKits,
    required this.linhas,
    this.itensIgnorados = 0,
  });

  final int kitId;
  final String nomeKit;
  final int quantidadeKits;
  final List<PdvKitOrcamentoLinhaInsercao> linhas;
  final int itensIgnorados;

  bool get temLinhas => linhas.isNotEmpty;
}

abstract final class PdvKitOrcamentoInsercaoUtil {
  PdvKitOrcamentoInsercaoUtil._();

  static PdvKitOrcamentoInsercaoMontada? montar({
    required KitOrcamentoRepository kitRepository,
    required ProdutoRepository produtoRepository,
    required int kitId,
    required int quantidadeKits,
  }) {
    if (kitId <= 0 || quantidadeKits <= 0) return null;
    final kit = kitRepository.obterPorId(kitId);
    if (kit == null || !kit.ativo) return null;

    final itens = kit.itens.toList()..sort((a, b) => a.ordem.compareTo(b.ordem));
    final linhas = <PdvKitOrcamentoLinhaInsercao>[];
    var ignorados = 0;

    for (final item in itens) {
      final pid = item.produto.targetId;
      final p = pid > 0 ? produtoRepository.obterPorId(pid) : null;
      if (p == null || !p.ativo) {
        ignorados++;
        continue;
      }
      final q = item.quantidade * quantidadeKits;
      if (q <= 0) {
        ignorados++;
        continue;
      }
      linhas.add(
        PdvKitOrcamentoLinhaInsercao(
          produto: p,
          quantidade: q.toDouble(),
        ),
      );
    }

    if (linhas.isEmpty) return null;

    return PdvKitOrcamentoInsercaoMontada(
      kitId: kit.id,
      nomeKit: kit.nome,
      quantidadeKits: quantidadeKits,
      linhas: linhas,
      itensIgnorados: ignorados,
    );
  }
}
