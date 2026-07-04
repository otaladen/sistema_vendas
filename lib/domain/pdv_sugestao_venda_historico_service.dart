import '../data/produto_repository.dart';
import '../data/venda_repository.dart';
import '../model/produto.dart';
import 'pdv_consulta_insights_service.dart';
import 'produto_coocorrencia_venda.dart';
import 'sugestao_venda_tipo.dart';

/// Sugestoes agregadas derivadas do historico de vendas (Fase 3).
abstract final class PdvSugestaoVendaHistoricoService {
  PdvSugestaoVendaHistoricoService._();

  static const _cacheTtl = Duration(minutes: 10);
  static final Map<int, ({DateTime expira, List<ProdutoCoocorrenciaVenda> itens})>
      _cacheCoocorrencia = {};

  static void invalidarCache() => _cacheCoocorrencia.clear();

  static List<ProdutoCoocorrenciaVenda> _coocorrenciasDe(
    int produtoOrigemId,
    VendaRepository vendaRepository, {
    int dias = 90,
    int minimoVendasJuntas = 2,
  }) {
    final agora = DateTime.now();
    final emCache = _cacheCoocorrencia[produtoOrigemId];
    if (emCache != null && emCache.expira.isAfter(agora)) {
      return emCache.itens;
    }
    final lista = vendaRepository.listarProdutosCompradosJunto(
      produtoOrigemId,
      dias: dias,
      minimoVendasJuntas: minimoVendasJuntas,
    );
    _cacheCoocorrencia[produtoOrigemId] = (
      expira: agora.add(_cacheTtl),
      itens: lista,
    );
    return lista;
  }

  static List<PdvConsultaAgregadoVenda> listarAgregadosHistorico(
    int produtoOrigemId,
    VendaRepository vendaRepository,
    ProdutoRepository produtoRepository, {
    required String precoListaAtivo,
    required double Function(Produto produto, String precoTipo) precoUnitarioDe,
    Set<int> excluirProdutoIds = const {},
    int limite = 4,
    int dias = 90,
    int minimoVendasJuntas = 2,
  }) {
    if (limite <= 0 || produtoOrigemId <= 0) return const [];

    final cooc = _coocorrenciasDe(
      produtoOrigemId,
      vendaRepository,
      dias: dias,
      minimoVendasJuntas: minimoVendasJuntas,
    );
    if (cooc.isEmpty) return const [];

    final result = <PdvConsultaAgregadoVenda>[];
    for (final linha in cooc) {
      if (result.length >= limite) break;
      if (excluirProdutoIds.contains(linha.produtoId)) continue;
      final p = produtoRepository.obterPorId(linha.produtoId);
      if (p == null || !p.ativo) continue;

      final qtdSugerida = linha.quantidadeMedia.round().clamp(1, 999);
      result.add(
        PdvConsultaAgregadoVenda(
          produtoId: p.id,
          nome: p.nome,
          estoqueDisponivel: p.estoqueLivreParaVenda,
          precoReferencia: precoUnitarioDe(p, precoListaAtivo),
          tipo: SugestaoVendaTipo.complementar,
          quantidadeSugerida: qtdSugerida,
          observacao:
              'Comprou junto em ${linha.vendasJuntas} venda(s) nos ultimos $dias dias',
          cadastrado: false,
          historico: true,
          vendasJuntasHistorico: linha.vendasJuntas,
        ),
      );
    }
    return result;
  }
}
