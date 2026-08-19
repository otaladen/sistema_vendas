import '../data/api/kit_promocao_api_repository.dart';
import '../model/kit_orcamento.dart';
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

  static List<KitOrcamentoItem> _itensDoKit(
    dynamic kitRepository,
    KitOrcamento kit,
  ) {
    if (kitRepository is KitOrcamentoApiRepository) {
      // Copia growable: a API devolve unmodifiable e o caller faz sort.
      return List<KitOrcamentoItem>.from(kitRepository.itensDoKit(kit));
    }
    try {
      return List<KitOrcamentoItem>.from(kit.itens);
    } catch (_) {
      return <KitOrcamentoItem>[];
    }
  }

  static PdvKitOrcamentoInsercaoMontada? montar({
    required dynamic kitRepository,
    required dynamic produtoRepository,
    required int kitId,
    required int quantidadeKits,
  }) {
    if (kitId <= 0 || quantidadeKits <= 0) return null;
    final kit = kitRepository.obterPorId(kitId);
    if (kit == null || kit is! KitOrcamento || !kit.ativo) return null;

    final itens = _itensDoKit(kitRepository, kit)
      ..sort((a, b) => a.ordem.compareTo(b.ordem));
    final linhas = <PdvKitOrcamentoLinhaInsercao>[];
    var ignorados = 0;

    for (final item in itens) {
      // targetId e seguro em detached; .target pode falhar no Terminal Leve.
      final pid = item.produto.targetId;
      Produto? p;
      if (pid > 0) {
        try {
          p = produtoRepository.obterPorId(pid) as Produto?;
        } catch (_) {
          p = null;
        }
      }
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
