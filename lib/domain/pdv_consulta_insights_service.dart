import '../data/kit_orcamento_repository.dart';
import '../data/produto_repository.dart';
import '../data/produto_sugestao_venda_repository.dart';
import '../data/venda_repository.dart';
import '../domain/sugestao_venda_tipo.dart';
import '../model/kit_orcamento.dart';
import '../model/produto.dart';
import 'pdv_consulta_multi_deposito_util.dart';
import 'pdv_consulta_similares_util.dart';
import 'pdv_sugestao_venda_historico_service.dart';
import 'produto_precificacao.dart';

/// Resumo de compras do cliente para um produto.
class PdvConsultaHistoricoClienteProduto {
  const PdvConsultaHistoricoClienteProduto({
    required this.comprasNoPeriodo,
    required this.quantidadeLiquida,
    this.ultimaCompraEm,
    this.diasPeriodo = 90,
  });

  const PdvConsultaHistoricoClienteProduto.vazio({this.diasPeriodo = 90})
      : comprasNoPeriodo = 0,
        quantidadeLiquida = 0,
        ultimaCompraEm = null;

  final int comprasNoPeriodo;
  final int quantidadeLiquida;
  final DateTime? ultimaCompraEm;
  final int diasPeriodo;

  bool get temHistorico => comprasNoPeriodo > 0;
}

/// Alerta de margem para gerente (custo x preco da tabela ativa).
class PdvConsultaAlertaMargem {
  const PdvConsultaAlertaMargem({
    required this.margemPercentual,
    required this.margemMinimaReferencia,
    required this.precoVenda,
    required this.custoReferencia,
    required this.abaixoMargemMinima,
    required this.abaixoCusto,
  });

  final double margemPercentual;
  final double margemMinimaReferencia;
  final double precoVenda;
  final double custoReferencia;
  final bool abaixoMargemMinima;
  final bool abaixoCusto;
}

/// Produto substituto/similar sugerido na consulta.
class PdvConsultaProdutoSimilar {
  const PdvConsultaProdutoSimilar({
    required this.produtoId,
    required this.nome,
    required this.estoqueDisponivel,
    required this.precoReferencia,
    this.cadastrado = false,
  });

  final int produtoId;
  final String nome;
  final int estoqueDisponivel;
  final double precoReferencia;
  final bool cadastrado;

  bool get semEstoque => estoqueDisponivel <= 0;
}

/// Kit de orcamento que inclui o produto selecionado.
class PdvConsultaKitResumo {
  const PdvConsultaKitResumo({
    required this.kitId,
    required this.nome,
    required this.quantidadeItens,
  });

  final int kitId;
  final String nome;
  final int quantidadeItens;
}

/// Produto agregado sugerido para oferta ao cliente.
class PdvConsultaAgregadoVenda {
  const PdvConsultaAgregadoVenda({
    required this.produtoId,
    required this.nome,
    required this.estoqueDisponivel,
    required this.precoReferencia,
    required this.tipo,
    required this.quantidadeSugerida,
    this.observacao = '',
    this.cadastrado = false,
    this.historico = false,
    this.vendasJuntasHistorico = 0,
  });

  final int produtoId;
  final String nome;
  final int estoqueDisponivel;
  final double precoReferencia;
  final SugestaoVendaTipo tipo;
  final int quantidadeSugerida;
  final String observacao;
  final bool cadastrado;
  final bool historico;
  final int vendasJuntasHistorico;

  bool get semEstoque => estoqueDisponivel <= 0;

  String get rotuloOrigem {
    if (historico) return 'Historico';
    if (cadastrado) return 'Sugestao';
    return '';
  }

  String detalheLinha(String Function(double) formatarMoeda) {
    final precoQtd = semEstoque
        ? 'Sem estoque · ${formatarMoeda(precoReferencia)} · $quantidadeSugerida un.'
        : '$estoqueDisponivel · ${formatarMoeda(precoReferencia)} · $quantidadeSugerida un.';
    if (historico) {
      final vendas = vendasJuntasHistorico > 0
          ? '$vendasJuntasHistorico vendas juntas · '
          : '';
      return 'Historico · $vendas$precoQtd';
    }
    if (cadastrado) {
      return 'Sugestao · ${tipo.rotulo} · $precoQtd';
    }
    return '${tipo.rotulo} · $precoQtd';
  }

  /// Texto enxuto para a faixa do carrinho (PDV rapido).
  String subtituloFaixaCarrinho(String Function(double) formatarMoeda) {
    final precoQtd =
        '${formatarMoeda(precoReferencia)} · $quantidadeSugerida un.';
    if (semEstoque) return 'Sem estoque · $precoQtd';
    return precoQtd;
  }

  /// Badge opcional na faixa do carrinho.
  String? badgeFaixaCarrinho() {
    if (historico) return 'Historico';
    if (cadastrado) return 'Cadastro';
    return null;
  }
}

/// Pacote de insights premium (consulta PDV pacote 3).
class PdvConsultaInsightsPacote {
  const PdvConsultaInsightsPacote({
    this.historicoCliente,
    this.alertaMargem,
    this.similares = const [],
    this.agregados = const [],
    this.kits = const [],
    this.rotuloDeposito,
    this.trechoAplicacao,
  });

  final PdvConsultaHistoricoClienteProduto? historicoCliente;
  final PdvConsultaAlertaMargem? alertaMargem;
  final List<PdvConsultaProdutoSimilar> similares;
  final List<PdvConsultaAgregadoVenda> agregados;
  final List<PdvConsultaKitResumo> kits;
  final String? rotuloDeposito;
  final String? trechoAplicacao;

  bool get temConteudo =>
      historicoCliente != null ||
      alertaMargem != null ||
      similares.isNotEmpty ||
      agregados.isNotEmpty ||
      kits.isNotEmpty ||
      (rotuloDeposito?.isNotEmpty ?? false) ||
      (trechoAplicacao?.isNotEmpty ?? false);
}

/// Monta insights contextuais para o painel lateral da consulta PDV.
abstract final class PdvConsultaInsightsService {
  PdvConsultaInsightsService._();

  static PdvConsultaInsightsPacote montar({
    required Produto produto,
    required ProdutoRepository produtoRepository,
    required VendaRepository vendaRepository,
    KitOrcamentoRepository? kitOrcamentoRepository,
    ProdutoSugestaoVendaRepository? sugestaoVendaRepository,
    int? clienteId,
    required String precoListaAtivo,
    required double Function(Produto produto, String precoTipo) precoUnitarioDe,
    double margemMinimaPadrao = 20,
    double margemMinimaPromocao = 0,
    bool mostrarMargemGerente = false,
    String termoBusca = '',
    PdvConsultaDepositoRotulos rotulosDeposito =
        const PdvConsultaDepositoRotulos(),
    int diasHistoricoCliente = 90,
    int limiteSimilares = 5,
    int limiteAgregados = 8,
    int limiteKits = 3,
    int diasHistoricoAgregados = 90,
    int minimoVendasJuntasHistorico = 2,
    Set<int> excluirProdutoIdsAgregados = const {},
  }) {
    PdvConsultaHistoricoClienteProduto? historico;
    if (clienteId != null && clienteId > 0) {
      final resumo = vendaRepository.resumoComprasClienteProduto(
        clienteId,
        produto.id,
        dias: diasHistoricoCliente,
      );
      historico = PdvConsultaHistoricoClienteProduto(
        comprasNoPeriodo: resumo.comprasNoPeriodo,
        quantidadeLiquida: resumo.quantidadeLiquida,
        ultimaCompraEm: resumo.ultimaCompraEm,
        diasPeriodo: diasHistoricoCliente,
      );
    }

    PdvConsultaAlertaMargem? alertaMargem;
    if (mostrarMargemGerente) {
      alertaMargem = calcularAlertaMargem(
        produto: produto,
        precoVenda: precoUnitarioDe(produto, precoListaAtivo),
        margemMinimaPadrao: margemMinimaPadrao,
        margemMinimaPromocao: margemMinimaPromocao,
      );
    }

    final similares = listarSimilaresComEstoque(
      produto,
      produtoRepository,
      precoListaAtivo: precoListaAtivo,
      precoUnitarioDe: precoUnitarioDe,
      limite: limiteSimilares,
    );

    final kits = kitOrcamentoRepository == null
        ? const <PdvConsultaKitResumo>[]
        : listarKitsComProduto(kitOrcamentoRepository, produto.id, limite: limiteKits);

    final agregados = listarAgregadosParaPdv(
      referencia: produto,
      sugestaoVendaRepository: sugestaoVendaRepository,
      vendaRepository: vendaRepository,
      produtoRepository: produtoRepository,
      precoListaAtivo: precoListaAtivo,
      precoUnitarioDe: precoUnitarioDe,
      limite: limiteAgregados,
      excluirProdutoIds: excluirProdutoIdsAgregados,
      diasHistorico: diasHistoricoAgregados,
      minimoVendasJuntasHistorico: minimoVendasJuntasHistorico,
    );

    final loc = PdvConsultaMultiDepositoUtil.montarRotuloInsights(
      produto,
      rotulos: rotulosDeposito,
    );
    final rotuloDeposito = loc.isNotEmpty ? loc : null;

    final trechoAplicacao = extrairTrechoAplicacao(produto, termoBusca);

    return PdvConsultaInsightsPacote(
      historicoCliente: historico?.temHistorico == true ? historico : null,
      alertaMargem: alertaMargem,
      similares: similares,
      agregados: agregados,
      kits: kits,
      rotuloDeposito: rotuloDeposito,
      trechoAplicacao: trechoAplicacao,
    );
  }

  static List<PdvConsultaProdutoSimilar> listarSimilaresComEstoque(
    Produto referencia,
    ProdutoRepository produtoRepository, {
    required String precoListaAtivo,
    required double Function(Produto produto, String precoTipo) precoUnitarioDe,
    int limite = 5,
  }) {
    if (limite <= 0 || referencia.id <= 0) return const [];

    final cadastradosBrutos = List<Produto>.from(
      produtoRepository.listarSubstitutosCadastrados(referencia.id),
    );
    cadastradosBrutos.sort((a, b) {
      final aComEstoque = a.estoqueLivreParaVenda > 0;
      final bComEstoque = b.estoqueLivreParaVenda > 0;
      if (aComEstoque != bComEstoque) return aComEstoque ? -1 : 1;
      return a.nome.compareTo(b.nome);
    });

    final cadastrados = cadastradosBrutos
        .map(
          (p) => PdvConsultaProdutoSimilar(
            produtoId: p.id,
            nome: p.nome,
            estoqueDisponivel: p.estoqueLivreParaVenda,
            precoReferencia: precoUnitarioDe(p, precoListaAtivo),
            cadastrado: true,
          ),
        )
        .toList();

    final idsCadastrados = cadastrados.map((s) => s.produtoId).toSet();
    final restante = (limite - cadastrados.length).clamp(0, limite);
    if (restante <= 0) return cadastrados.take(limite).toList();

    if (!PdvConsultaSimilaresUtil.referenciaElegivel(referencia)) {
      return cadastrados;
    }

    final candidatos = produtoRepository
        .listarCandidatosSimilaresConsulta(referencia)
        .where(
          (p) =>
              !idsCadastrados.contains(p.id) &&
              PdvConsultaSimilaresUtil.candidatoCompativel(referencia, p),
        )
        .toList();
    if (candidatos.isEmpty) return cadastrados;

    final scored = <({Produto p, int score})>[];
    final catRef = _norm(referencia.categoria);
    final subRef = _norm(referencia.subcategoria);
    final marcaRef = _norm(referencia.marca);

    for (final p in candidatos) {
      var score = 0;
      score += p.estoqueLivreParaVenda.clamp(0, 500);
      if (catRef.isNotEmpty && _norm(p.categoria) == catRef) score += 200;
      if (subRef.isNotEmpty && _norm(p.subcategoria) == subRef) score += 300;
      if (marcaRef.isNotEmpty && _norm(p.marca) == marcaRef) score += 80;
      scored.add((p: p, score: score));
    }

    scored.sort((a, b) {
      final cmp = b.score.compareTo(a.score);
      if (cmp != 0) return cmp;
      return a.p.nome.compareTo(b.p.nome);
    });

    return [
      ...cadastrados,
      ...scored.take(restante).map((e) {
        final p = e.p;
        return PdvConsultaProdutoSimilar(
          produtoId: p.id,
          nome: p.nome,
          estoqueDisponivel: p.estoqueLivreParaVenda,
          precoReferencia: precoUnitarioDe(p, precoListaAtivo),
        );
      }),
    ];
  }

  static List<PdvConsultaAgregadoVenda> listarAgregadosComEstoque(
    Produto referencia,
    ProdutoSugestaoVendaRepository sugestaoVendaRepository,
    ProdutoRepository produtoRepository, {
    required String precoListaAtivo,
    required double Function(Produto produto, String precoTipo) precoUnitarioDe,
    int limite = 8,
    Set<int> excluirProdutoIds = const {},
  }) {
    if (limite <= 0 || referencia.id <= 0) return const [];

    final linhas = sugestaoVendaRepository.listarPorProdutoOrigem(referencia.id);
    final result = <PdvConsultaAgregadoVenda>[];
    for (final linha in linhas) {
      if (result.length >= limite) break;
      if (excluirProdutoIds.contains(linha.produtoSugeridoId)) continue;
      final p = produtoRepository.obterPorId(linha.produtoSugeridoId);
      if (p == null || !p.ativo) continue;
      result.add(
        PdvConsultaAgregadoVenda(
          produtoId: p.id,
          nome: p.nome,
          estoqueDisponivel: p.estoqueLivreParaVenda,
          precoReferencia: precoUnitarioDe(p, precoListaAtivo),
          tipo: SugestaoVendaTipo.fromCodigo(linha.tipo),
          quantidadeSugerida: linha.quantidadeSugerida,
          observacao: linha.observacao.trim(),
          cadastrado: true,
          historico: false,
        ),
      );
    }
    return result;
  }

  /// Cadastro manual + historico de vendas (prioridade ao cadastro).
  static List<PdvConsultaAgregadoVenda> listarAgregadosParaPdv({
    required Produto referencia,
    ProdutoSugestaoVendaRepository? sugestaoVendaRepository,
    required VendaRepository vendaRepository,
    required ProdutoRepository produtoRepository,
    required String precoListaAtivo,
    required double Function(Produto produto, String precoTipo) precoUnitarioDe,
    int limite = 8,
    Set<int> excluirProdutoIds = const {},
    int diasHistorico = 90,
    int minimoVendasJuntasHistorico = 2,
  }) {
    if (limite <= 0 || referencia.id <= 0) return const [];

    final excluir = {
      ...excluirProdutoIds,
      referencia.id,
    };

    final manual = sugestaoVendaRepository == null
        ? const <PdvConsultaAgregadoVenda>[]
        : listarAgregadosComEstoque(
            referencia,
            sugestaoVendaRepository,
            produtoRepository,
            precoListaAtivo: precoListaAtivo,
            precoUnitarioDe: precoUnitarioDe,
            limite: limite,
            excluirProdutoIds: excluir,
          );

    final restante = limite - manual.length;
    if (restante <= 0) return manual;

    final idsManual = manual.map((e) => e.produtoId).toSet();
    final historico = PdvSugestaoVendaHistoricoService.listarAgregadosHistorico(
      referencia.id,
      vendaRepository,
      produtoRepository,
      precoListaAtivo: precoListaAtivo,
      precoUnitarioDe: precoUnitarioDe,
      excluirProdutoIds: {...excluir, ...idsManual},
      limite: restante,
      dias: diasHistorico,
      minimoVendasJuntas: minimoVendasJuntasHistorico,
    );

    return [...manual, ...historico];
  }

  static List<PdvConsultaKitResumo> listarKitsComProduto(
    KitOrcamentoRepository repository,
    int produtoId, {
    int limite = 3,
  }) {
    if (produtoId <= 0 || limite <= 0) return const [];
    return repository
        .listarAtivosComProduto(produtoId, limite: limite)
        .map(
          (KitOrcamento k) => PdvConsultaKitResumo(
            kitId: k.id,
            nome: k.nome,
            quantidadeItens: k.itens.length,
          ),
        )
        .toList();
  }

  static PdvConsultaAlertaMargem calcularAlertaMargem({
    required Produto produto,
    required double precoVenda,
    double margemMinimaPadrao = 20,
    double margemMinimaPromocao = 0,
  }) {
    final custo = (produto.precoCusto > 0
            ? produto.precoCusto
            : (produto.custoMedio > 0 ? produto.custoMedio : 0))
        .toDouble();
    final margem = ProdutoPrecificacao.margemSobrePrecoVenda(
      custo: custo,
      precoVenda: precoVenda,
    );
    final minRef = margemMinimaPromocao > 0
        ? margemMinimaPromocao
        : margemMinimaPadrao;
    return PdvConsultaAlertaMargem(
      margemPercentual: margem,
      margemMinimaReferencia: minRef,
      precoVenda: precoVenda,
      custoReferencia: custo,
      abaixoMargemMinima: minRef > 0 && margem + 0.05 < minRef,
      abaixoCusto: custo > 0 && precoVenda + 0.009 < custo,
    );
  }

  /// Trecho da descricao/apelidos quando o termo bate (busca por aplicacao).
  static String? extrairTrechoAplicacao(Produto produto, String termoBusca) {
    final termo = _norm(termoBusca);
    if (termo.length < 3) return null;

    final descricao = produto.descricao.trim();
    if (descricao.isNotEmpty && _norm(descricao).contains(termo)) {
      return _snippet(descricao, termo);
    }

    for (final linha in produto.apelidosBusca.split(RegExp(r'[;\n]+'))) {
      final ap = linha.trim();
      if (ap.isEmpty) continue;
      if (_norm(ap).contains(termo)) return ap;
    }
    return null;
  }

  /// Filtro local: termo presente na descricao ou apelidos.
  static bool produtoCombinaAplicacao(Produto produto, String termoBusca) {
    final termo = _norm(termoBusca);
    if (termo.length < 3) return true;
    final desc = _norm(produto.descricao);
    if (desc.contains(termo)) return true;
    final apelidos = _norm(produto.apelidosBusca);
    return apelidos.contains(termo);
  }

  static String _norm(String s) => s.trim().toLowerCase();

  static String _snippet(String texto, String termoNorm) {
    final lower = texto.toLowerCase();
    final idx = lower.indexOf(termoNorm);
    if (idx < 0) return texto.length <= 120 ? texto : '${texto.substring(0, 117)}...';
    const raio = 48;
    final start = (idx - raio).clamp(0, texto.length);
    final end = (idx + termoNorm.length + raio).clamp(0, texto.length);
    var trecho = texto.substring(start, end).trim();
    if (start > 0) trecho = '...$trecho';
    if (end < texto.length) trecho = '$trecho...';
    return trecho;
  }
}
