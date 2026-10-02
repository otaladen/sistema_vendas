import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

import '../model/historico_entrada.dart';
import '../model/item_lista_compra.dart';
import '../model/item_venda.dart';
import '../model/movimento_estoque.dart';
import '../model/produto.dart';
import '../model/vinculo_fornecedor_produto.dart';
import '../domain/produto/produto_busca_util.dart';
import '../domain/produto_imagem_nome_arquivo.dart';
import '../domain/pdv_consulta_similares_util.dart';
import '../domain/produto_substitutos_util.dart';
import '../domain/pdv_busca_inteligente.dart';
import '../domain/produto_exclusao_guard.dart';
import '../domain/produto_nome_exibicao.dart';
import '../domain/produto_nome_titulo_normalizer.dart';
import '../domain/produto_unidades_catalogo.dart';
import '../services/gerenciador_estoque_service.dart';
import '../services/produto_imagem_service.dart';
import 'lote_produto_repository.dart';
import 'movimento_estoque_repository.dart';
import 'produto_busca_util.dart';
import '../objectbox.g.dart';
import 'objectbox.dart';
import 'objectbox_lifecycle_hub.dart';
import 'sync/sync_delete_outbox.dart';
import 'sync/sync_dirty_outbox.dart';
import 'sync/sync_write_trigger.dart';

/// Resultado de [ProdutoRepository.zerarCadastroCompleto].
class ProdutoCadastroZerarResultado {
  const ProdutoCadastroZerarResultado({
    required this.produtosRemovidos,
    required this.movimentosRemovidos,
    required this.historicosEntradaRemovidos,
    required this.vinculosRemovidos,
    required this.kitsRemovidos,
    required this.kitItensRemovidos,
    required this.promocoesRemovidas,
    required this.promocaoItensRemovidos,
    required this.promocaoCombosRemovidos,
    required this.sugestoesRemovidas,
    required this.metricasSugestaoRemovidas,
    required this.itensListaCompraRemovidos,
    required this.imagensRemovidas,
  });

  final int produtosRemovidos;
  final int movimentosRemovidos;
  final int historicosEntradaRemovidos;
  final int vinculosRemovidos;
  final int kitsRemovidos;
  final int kitItensRemovidos;
  final int promocoesRemovidas;
  final int promocaoItensRemovidos;
  final int promocaoCombosRemovidos;
  final int sugestoesRemovidas;
  final int metricasSugestaoRemovidas;
  final int itensListaCompraRemovidos;
  final int imagensRemovidas;
}

/// Media ponderada (quantidade interna * custo unitario da nota) sobre todas as
/// [HistoricoEntrada] do produto. Retorna null se nao houver linhas validas.
double? calcularCustoMedioPonderadoEntradasNfe(ObjectBox db, int produtoId) {
  if (produtoId <= 0) return null;
  final q = db.historicoEntradaBox
      .query(HistoricoEntrada_.produto.equals(produtoId))
      .build();
  try {
    var somaValor = 0.0;
    var somaQtd = 0;
    for (final h in q.find()) {
      final qtd = h.quantidadeEntradaEstoque;
      final unit = h.precoCustoUnitarioNota;
      if (qtd <= 0 || unit <= 0) continue;
      somaValor += qtd * unit;
      somaQtd += qtd;
    }
    if (somaQtd <= 0) return null;
    return somaValor / somaQtd;
  } finally {
    q.close();
  }
}

/// Lancada ao gravar produto com SKU ja usado por outro cadastro.
class ProdutoSkuDuplicadoException implements Exception {
  ProdutoSkuDuplicadoException({
    required this.sku,
    required this.produtoExistenteNome,
    this.produtoExistenteId,
  });

  final String sku;
  final String produtoExistenteNome;
  final int? produtoExistenteId;

  @override
  String toString() =>
      'SKU "$sku" ja cadastrado no produto "$produtoExistenteNome".';
}

class ProdutoRepository extends ChangeNotifier
    implements ObjectBoxStoreLifecycleListener {
  ProdutoRepository(this._db) : _estoque = GerenciadorEstoqueService(_db) {
    ObjectBoxLifecycleHub.registrar(this);
  }

  final ObjectBox _db;
  final GerenciadorEstoqueService _estoque;

  ObjectBox get objectBox => _db;

  static const List<String> _unidadesValidas =
      ProdutoUnidadesCatalogo.unidadesVenda;
  static const Duration _cacheTtl = Duration(minutes: 2);

  List<ProdutoBuscaDoc> _cacheDocs = const [];
  int _cacheProdutoCount = -1;
  DateTime? _cacheMontadoEm;

  /// >0: [salvar]/invalidacao nao notifica UI/rede (importacao em lote).
  int _importacaoEmLoteDepth = 0;

  static bool _migracaoAtivoLegadoOk = false;

  String get productImagesDirPath => _db.productImagesDir.path;

  /// Quando [somenteAtivos] e true, retorna apenas produtos vendiveis (PDV).
  /// Padrao false: cadastro, estoque, relatorios e resolucao de itens antigos em orcamentos.
  List<Produto> listarTodos({bool somenteAtivos = false}) {
    if (_db.leituraIndisponivel) return const [];
    _migrarCampoAtivoLegadoUmaVez();
    late final List<Produto> produtos;
    if (somenteAtivos) {
      final query = _db.produtoBox
          .query(Produto_.ativo.equals(true))
          .order(Produto_.nome)
          .build();
      try {
        produtos = query.find();
      } finally {
        query.close();
      }
    } else {
      final query = _db.produtoBox.query().order(Produto_.nome).build();
      try {
        produtos = query.find();
      } finally {
        query.close();
      }
    }
    _normalizarDadosLegados(produtos);
    return produtos;
  }

  /// Pagina produtos ordenados por nome (sugestoes PDV sem carregar catalogo inteiro).
  ///
  /// [prefixoNome]: filtra pelo inicio do nome (ex.: `M` → letra M), case-insensitive.
  List<Produto> listarPaginado({
    int offset = 0,
    int limit = 50,
    bool somenteAtivos = true,
    bool somenteInativos = false,
    String? prefixoNome,
  }) {
    if (_db.leituraIndisponivel) return const [];
    _migrarCampoAtivoLegadoUmaVez();
    if (limit <= 0) return const [];
    final pfx = (prefixoNome ?? '').trim();
    Condition<Produto>? cond;
    if (somenteInativos) {
      cond = Produto_.ativo.equals(false);
    } else if (somenteAtivos) {
      cond = Produto_.ativo.equals(true);
    }
    if (pfx.isNotEmpty) {
      final porNome = Produto_.nome.startsWith(pfx, caseSensitive: false);
      cond = cond == null ? porNome : cond & porNome;
    }
    final qb = cond == null ? _db.produtoBox.query() : _db.produtoBox.query(cond);
    final query = qb.order(Produto_.nome).build();
    try {
      query.offset = offset < 0 ? 0 : offset;
      query.limit = limit;
      final produtos = query.find();
      _normalizarDadosLegados(produtos);
      return produtos;
    } finally {
      query.close();
    }
  }

  /// Candidatos para sugestao de substitutos na consulta PDV.
  List<Produto> listarCandidatosSimilaresConsulta(
    Produto referencia, {
    int limite = 80,
  }) {
    if (referencia.id <= 0 || limite <= 0) return const [];
    if (!PdvConsultaSimilaresUtil.referenciaElegivel(referencia)) {
      return const [];
    }
    _migrarCampoAtivoLegadoUmaVez();

    final categoria = referencia.categoria.trim();
    final subcategoria = referencia.subcategoria.trim();
    late final Query<Produto> query;

    if (PdvConsultaSimilaresUtil.subcategoriaUtil(subcategoria)) {
      query = _db.produtoBox
          .query(
            Produto_.ativo.equals(true) &
                Produto_.subcategoria.equals(subcategoria, caseSensitive: false),
          )
          .order(Produto_.nome)
          .build();
    } else if (PdvConsultaSimilaresUtil.categoriaEspecifica(categoria)) {
      query = _db.produtoBox
          .query(
            Produto_.ativo.equals(true) &
                Produto_.categoria.equals(categoria, caseSensitive: false),
          )
          .order(Produto_.nome)
          .build();
    } else {
      return const [];
    }

    try {
      query.limit = limite + 1;
      final produtos = query
          .find()
          .where(
            (p) =>
                p.id != referencia.id &&
                PdvConsultaSimilaresUtil.candidatoCompativel(referencia, p),
          )
          .take(limite)
          .toList();
      _normalizarDadosLegados(produtos);
      return produtos;
    } finally {
      query.close();
    }
  }

  /// Substitutos cadastrados manualmente no produto (consulta PDV pacote 5).
  List<Produto> listarSubstitutosCadastrados(int produtoId) {
    if (produtoId <= 0) return const [];
    final ref = obterPorId(produtoId);
    if (ref == null) return const [];
    final ids = ProdutoSubstitutosUtil.parseIds(ref.substitutosIds);
    if (ids.isEmpty) return const [];

    final out = <Produto>[];
    for (final id in ids) {
      if (id == produtoId) continue;
      final p = obterPorId(id);
      if (p == null || !p.ativo) continue;
      out.add(p);
    }
    return out;
  }

  /// Migracao unica: registros antigos ganham coluna [ativo]; define todos como ativos.
  void _migrarCampoAtivoLegadoUmaVez() {
    if (_migracaoAtivoLegadoOk) return;
    try {
      final flag = File(
        p.join(_db.storeDirectoryPath, '.migracao_produto_ativo_v1'),
      );
      if (flag.existsSync()) {
        _migracaoAtivoLegadoOk = true;
        return;
      }
      _db.store.runInTransaction(TxMode.write, () {
        final todos = _db.produtoBox.getAll();
        for (final prod in todos) {
          prod.ativo = true;
          _db.produtoBox.put(prod);
        }
      });
      flag.writeAsStringSync('ok');
      _invalidarCacheBusca();
      notificarAlteracaoParaRede(entidade: 'produto', entidadeId: 0);
      _migracaoAtivoLegadoOk = true;
    } catch (_) {
      // Falha de IO: proxima chamada tenta novamente.
    }
  }

  void _normalizarDadosLegados(List<Produto> produtos) {
    final alterados = <Produto>[];
    for (final produto in produtos) {
      final unidade = produto.unidade.trim().toUpperCase();
      final unidadeValida = _unidadesValidas.contains(unidade);
      var houveAjuste = false;
      if (produto.unidade != unidade) {
        produto.unidade = unidade;
        houveAjuste = true;
      }
      if (!unidadeValida) {
        produto.unidade = 'UN';
        houveAjuste = true;
      }
      final precoBase = produto.precoVenda > 0 ? produto.precoVenda : 0.0;
      if (produto.preco1 <= 0 && precoBase > 0) {
        produto.preco1 = precoBase;
        houveAjuste = true;
      }
      if (produto.preco2 <= 0 && precoBase > 0) {
        produto.preco2 = precoBase;
        houveAjuste = true;
      }
      if (produto.preco3 <= 0 && precoBase > 0) {
        produto.preco3 = precoBase;
        houveAjuste = true;
      }
      if (produto.estoqueAtual != produto.estoqueReal) {
        produto.estoqueAtual = produto.estoqueReal;
        houveAjuste = true;
      }
      if (produto.leadTimeDias <= 0) {
        produto.leadTimeDias = 7;
        houveAjuste = true;
      }
      if (produto.estoqueSeguranca <= 0 && produto.quantidadeMinima > 0) {
        produto.estoqueSeguranca = produto.quantidadeMinima;
        houveAjuste = true;
      }
      if (houveAjuste) {
        alterados.add(produto);
      }
    }
    if (alterados.isEmpty) {
      return;
    }
    _db.store.runInTransaction(TxMode.write, () {
      for (final p in alterados) {
        _db.produtoBox.put(p);
      }
    });
    notificarAlteracaoParaRede(entidade: 'produto', entidadeId: 0);
  }

  /// - [somenteAtivos] padrao true (PDV): ignora inativos.
  /// - [somenteInativos]: quando true, retorna apenas inativos ([somenteAtivos] e ignorado).
  /// - Ambos false: todos os produtos (cadastro / busca ampla).
  /// - [clienteId] nao altera o ranking: ele precisa ser identico no terminal leve,
  ///   que nao tem o historico de vendas por cliente.
  List<Produto> pesquisar(
    String termo, {
    int? clienteId,
    int offset = 0,
    int limite = 50,
    bool somenteAtivos = true,
    bool somenteInativos = false,
    bool excluirProdutosInternos = false,
  }) {
    _migrarCampoAtivoLegadoUmaVez();
    _garantirCachesAtualizados();
    return ProdutoBuscaUtil.pesquisar(
      _cacheDocs,
      termo,
      offset: offset,
      limite: limite,
      somenteAtivos: somenteAtivos,
      somenteInativos: somenteInativos,
      excluirProdutosInternos: excluirProdutosInternos,
    );
  }

  /// Pagina de busca para listas longas (cadastro, estoque, dialogo de pesquisa).
  /// Com texto e so ativos: mesmo motor do PDV (sem produtos `__...__`).
  List<Produto> pesquisarPaginaCadastro(
    String termo, {
    int offset = 0,
    int limite = 40,
    bool somenteAtivos = true,
    bool somenteInativos = false,
  }) {
    final consulta = termo.trim();
    final comoPdv = consulta.isNotEmpty &&
        somenteAtivos &&
        !somenteInativos;
    return pesquisar(
      termo,
      offset: offset,
      limite: limite,
      somenteAtivos: somenteAtivos,
      somenteInativos: somenteInativos,
      excluirProdutosInternos: comoPdv,
    );
  }

  /// Resolucao exata por GTIN (campo [Produto.codigoBarras] ou digitos em [apelidosBusca]).
  Produto? buscarPorCodigoBarras(
    String codigo, {
    bool somenteAtivos = true,
  }) {
    _migrarCampoAtivoLegadoUmaVez();
    final dig = normalizarCodigoBarrasConsulta(codigo);
    if (dig.isEmpty) return null;
    _garantirCachesAtualizados();
    for (final doc in _cacheDocs) {
      if (!doc.correspondeCodigoBarras(dig)) continue;
      if (somenteAtivos && !doc.produto.ativo) return null;
      return doc.produto;
    }
    final q = _db.produtoBox
        .query(Produto_.codigoBarras.equals(dig))
        .build();
    try {
      final lista = q.find();
      for (final p in lista) {
        if (somenteAtivos && !p.ativo) continue;
        return p;
      }
    } finally {
      q.close();
    }
    return null;
  }

  /// Motor de busca do PDV: ranking, curingas `%`, apelidos, EAN; sem produtos `__...__`.
  List<Produto> pesquisarPadraoPdv(
    String termo, {
    int? clienteId,
    int offset = 0,
    int limite = 50,
    bool somenteAtivos = true,
    bool somenteInativos = false,
  }) {
    return pesquisar(
      termo,
      clienteId: clienteId,
      offset: offset,
      limite: limite,
      somenteAtivos: somenteAtivos,
      somenteInativos: somenteInativos,
      excluirProdutosInternos: true,
    );
  }

  /// Busca PDV com regra de auto-selecao: so quando ha exatamente 1 correspondencia
  /// real (codigo de barras, codigo interno ou unico no ranking).
  PdvPesquisaResolvida resolverPesquisaPdv(
    String termo, {
    int? clienteId,
    bool somenteAtivos = true,
  }) {
    _migrarCampoAtivoLegadoUmaVez();
    _garantirCachesAtualizados();
    return ProdutoBuscaUtil.resolverPesquisaPdv(
      _cacheDocs,
      termo,
      somenteAtivos: somenteAtivos,
      resolverCodigoBarras: (t) =>
          resolverLeitorCodigoBarras(t, somenteAtivos: somenteAtivos),
    );
  }

  /// [pesquisarPadraoPdv] restrito a uma lista ja carregada (ex.: estoque).
  List<Produto> pesquisarNaBasePadraoPdv(
    String termo,
    Iterable<Produto> base, {
    int limite = 500,
    bool somenteAtivos = false,
    bool somenteInativos = false,
  }) {
    return pesquisarNaBase(
      termo,
      base,
      limite: limite,
      somenteAtivos: somenteAtivos,
      somenteInativos: somenteInativos,
      excluirProdutosInternos: true,
    );
  }

  /// Aplica [pesquisar] sobre uma colecao ja carregada (mantem ordem do ranking).
  List<Produto> pesquisarNaBase(
    String termo,
    Iterable<Produto> base, {
    int limite = 500,
    bool somenteAtivos = false,
    bool somenteInativos = false,
    bool excluirProdutosInternos = true,
  }) {
    final listaBase = base is List<Produto> ? base : base.toList();
    final t = termo.trim();
    if (t.isEmpty) return listaBase;
    final idsBase = listaBase.map((p) => p.id).toSet();
    return pesquisar(
      t,
      limite: limite,
      somenteAtivos: somenteAtivos,
      somenteInativos: somenteInativos,
      excluirProdutosInternos: excluirProdutosInternos,
    ).where((p) => idsBase.contains(p.id)).toList();
  }

  /// Leitor de barras: retorna produto unico quando a consulta e GTIN completo.
  Produto? resolverLeitorCodigoBarras(
    String termo, {
    bool somenteAtivos = true,
  }) {
    if (!consultaPareceCodigoBarras(termo)) return null;
    return buscarPorCodigoBarras(termo, somenteAtivos: somenteAtivos);
  }

  void _garantirCachesAtualizados() {
    if (_db.leituraIndisponivel) return;
    final agora = DateTime.now();
    final produtoCount = _db.produtoBox.count();
    final ttlExpirado =
        _cacheMontadoEm == null ||
        agora.difference(_cacheMontadoEm!) > _cacheTtl;
    if (produtoCount != _cacheProdutoCount || _cacheDocs.isEmpty || ttlExpirado) {
      _migrarCampoAtivoLegadoUmaVez();
      final produtos = _db.produtoBox.getAll();
      _normalizarDadosLegados(produtos);
      _cacheDocs = ProdutoBuscaUtil.criarDocs(produtos);
      _cacheProdutoCount = produtoCount;
    }
    _cacheMontadoEm = agora;
  }

  /// Persiste cadastro; alteracao de [Produto.estoqueReal] passa pelo gerenciador.
  int salvar(
    Produto produto, {
    String motivoAjusteEstoque = 'Ajuste manual cadastro produto',
    String usuarioAjusteEstoque = '',
  }) {
    produto.codigoInterno = normalizarCodigoInternoPersistido(
      produto.codigoInterno,
    );
    final nomeBruto = produto.nome;
    final nomeTitulo = ProdutoNomeTituloNormalizer.normalizar(nomeBruto);
    final impressaoBruta = produto.nomeImpressao.trim();
    // Se impressao seguia o nome antigo (ou vazia), acompanha o titulo novo.
    if (impressaoBruta.isEmpty ||
        impressaoBruta == nomeBruto.trim() ||
        impressaoBruta == nomeTitulo) {
      produto.nomeImpressao = nomeTitulo;
    }
    produto.nome = nomeTitulo;
    produto.nomeImpressao = ProdutoNomeExibicao.normalizarNomeImpressaoPersistido(
      nome: produto.nome,
      nomeImpressao: produto.nomeImpressao,
    );
    _garantirSkuUnico(produto);
    final id = _db.store.runInTransaction(TxMode.write, () {
      if (produto.id > 0) {
        final existente = _db.produtoBox.get(produto.id);
        if (existente == null) {
          throw StateError('Produto id ${produto.id} nao encontrado.');
        }
        final novoEstoque = produto.estoqueReal;
        final precosMudaram = _precosComerciaisDiferentes(existente, produto);
        _copiarCamposCadastro(existente, produto);
        if (precosMudaram) {
          existente.precoAlteradoEm = DateTime.now().toUtc();
        }
        final estoqueMudou = novoEstoque != existente.estoqueReal;
        if (!estoqueMudou) {
          existente.estoqueAtual = existente.estoqueReal;
        }
        // Cadastro antes do ajuste de estoque: o gerenciador recarrega o produto do banco.
        _db.produtoBox.put(existente);
        if (estoqueMudou) {
          _estoque.executarAjusteManualInventario(
            existente,
            novoEstoque,
            motivoAjusteEstoque,
            usuarioLogin: usuarioAjusteEstoque,
          );
        }
        return existente.id;
      }

      final estoqueInicial = produto.estoqueReal;
      produto.estoqueReal = 0;
      produto.estoqueAtual = 0;
      produto.precoAlteradoEm ??= DateTime.now().toUtc();
      final novoId = _db.produtoBox.put(produto);
      produto.id = novoId;
      if (estoqueInicial > 0) {
        _estoque.executarAjusteManualInventario(
          produto,
          estoqueInicial,
          motivoAjusteEstoque,
          usuarioLogin: usuarioAjusteEstoque,
        );
      }
      return novoId;
    });
    if (_importacaoEmLoteDepth <= 0) {
      invalidarCacheBusca();
      notificarAlteracaoParaRede(entidade: 'produto', entidadeId: id);
    }
    if (produto.controlaLoteValidade && id > 0) {
      final p = _db.produtoBox.get(id);
      if (p != null) {
        LoteProdutoRepository(_db).garantirMigracaoSemLote(p);
      }
    }
    return id;
  }

  static void _copiarCamposCadastro(Produto destino, Produto origem) {
    destino.codigoInterno = origem.codigoInterno;
    destino.nome = origem.nome;
    destino.nomeImpressao = origem.nomeImpressao;
    destino.descricao = origem.descricao;
    destino.unidade = origem.unidade;
    destino.categoria = origem.categoria;
    destino.subcategoria = origem.subcategoria;
    destino.marca = origem.marca;
    destino.fornecedor = origem.fornecedor;
    destino.fabricante = origem.fabricante;
    destino.codigoBarras = origem.codigoBarras;
    destino.apelidosBusca = origem.apelidosBusca;
    destino.fotoPath = origem.fotoPath;
    destino.localizacao = origem.localizacao;
    destino.estoqueCd = origem.estoqueCd;
    destino.substitutosIds = origem.substitutosIds;
    destino.ncm = origem.ncm;
    destino.cest = origem.cest;
    destino.grupoTributario = origem.grupoTributario;
    destino.cfopVenda = origem.cfopVenda;
    destino.icmsOrigem = origem.icmsOrigem;
    destino.icmsSituacaoTributaria = origem.icmsSituacaoTributaria;
    destino.pisCofinsSituacaoTributaria = origem.pisCofinsSituacaoTributaria;
    // estoqueReservado / estoqueReal / estoqueVersao: nao copiar do formulario —
    // reserva e fisico so mudam pelo GerenciadorEstoqueService.
    destino.leadTimeDias = origem.leadTimeDias;
    destino.vendaMediaDiaria = origem.vendaMediaDiaria;
    destino.estoqueSeguranca = origem.estoqueSeguranca;
    destino.quantidadeMinima = origem.quantidadeMinima;
    destino.precoCusto = origem.precoCusto;
    destino.custoMedio = origem.custoMedio;
    destino.preco1 = origem.preco1;
    destino.preco2 = origem.preco2;
    destino.preco3 = origem.preco3;
    destino.precoVenda = origem.precoVenda;
    destino.limiteDescontoPreco1 = origem.limiteDescontoPreco1;
    destino.limiteDescontoPreco2 = origem.limiteDescontoPreco2;
    destino.limiteDescontoPreco3 = origem.limiteDescontoPreco3;
    destino.unidadeCompra = origem.unidadeCompra;
    destino.quantidadePorEmbalagem = origem.quantidadePorEmbalagem;
    destino.embalagemMultiplica = origem.embalagemMultiplica;
    destino.permiteQuantidadeFracionada = origem.permiteQuantidadeFracionada;
    destino.ultimaVendaEm = origem.ultimaVendaEm;
    // precoAlteradoEm: controlado em [salvar] quando precos mudam.
    destino.criadoEm = origem.criadoEm;
    destino.ativo = origem.ativo;
    destino.controlaLoteValidade = origem.controlaLoteValidade;
    destino.percentualBotaFora = origem.percentualBotaFora;
  }

  static bool _precosComerciaisDiferentes(Produto a, Produto b) {
    bool dif(double x, double y) => (x - y).abs() > 0.0001;
    return dif(a.preco1, b.preco1) ||
        dif(a.preco2, b.preco2) ||
        dif(a.preco3, b.preco3) ||
        dif(a.precoVenda, b.precoVenda) ||
        dif(a.precoCusto, b.precoCusto);
  }

  /// Remove zeros a esquerda de SKUs numericos legados (ex.: 008858 -> 8858).
  /// Pula produtos cujo SKU canonico ja pertence a outro cadastro.
  int migrarSkuZerosEsquerdaLegado() {
    final todos = _db.produtoBox.getAll();
    if (todos.isEmpty) return 0;

    var alterados = 0;
    _db.store.runInTransaction(TxMode.write, () {
      for (final p in todos) {
        final atual = p.codigoInterno.trim();
        if (atual.isEmpty) continue;
        final novo = normalizarCodigoInternoPersistido(atual);
        if (novo == atual) continue;

        final novoLower = novo.toLowerCase();
        final conflito = todos.any(
          (outro) =>
              outro.id != p.id &&
              outro.codigoInterno.trim().toLowerCase() == novoLower,
        );
        if (conflito) {
          debugPrint(
            'Migracao SKU: pulando produto ${p.id} ($atual -> $novo) — SKU ja em uso.',
          );
          continue;
        }

        p.codigoInterno = novo;
        _db.produtoBox.put(p);
        alterados++;
      }
    });

    if (alterados > 0) {
      invalidarCacheBusca();
      notificarAlteracaoParaRede(entidade: 'produto', entidadeId: 0);
      debugPrint('Migracao SKU: $alterados produto(s) normalizado(s).');
    }
    return alterados;
  }

  /// Aplica o mesmo [fotoPath] a varios produtos (ex.: foto em lote na pesquisa).
  int aplicarFotoEmVarios({
    required Iterable<int> ids,
    required String fotoPath,
  }) {
    final path = fotoPath.trim();
    if (path.isEmpty) return 0;
    final unicos = ids.where((id) => id > 0).toSet();
    if (unicos.isEmpty) return 0;
    final alteradosIds = <int>[];
    _db.store.runInTransaction(TxMode.write, () {
      for (final id in unicos) {
        final p = _db.produtoBox.get(id);
        if (p == null) continue;
        if (p.fotoPath.trim() == path) continue;
        p.fotoPath = path;
        _db.produtoBox.put(p);
        alteradosIds.add(id);
      }
    });
    for (final id in alteradosIds) {
      notificarAlteracaoParaRede(entidade: 'produto', entidadeId: id);
    }
    if (alteradosIds.isNotEmpty) {
      invalidarCacheBusca();
    }
    return alteradosIds.length;
  }

  bool remover(int id) {
    ProdutoExclusaoGuard.garantirPodeExcluir(_db, id);
    final ok = _db.produtoBox.remove(id);
    if (ok) {
      registrarDeleteParaRede('produto', id);
      invalidarCacheBusca();
    }
    return ok;
  }

  /// Exclui varios produtos de uma vez (cadastro / limpeza).
  /// Retorna quantos foram removidos com sucesso.
  int removerVarios(Iterable<int> ids) {
    final unicos = ids.where((id) => id > 0).toSet().toList();
    if (unicos.isEmpty) return 0;
    final removidosIds = <int>[];
    _db.store.runInTransaction(TxMode.write, () {
      for (final id in unicos) {
        ProdutoExclusaoGuard.garantirPodeExcluir(_db, id);
        if (_db.produtoBox.remove(id)) {
          removidosIds.add(id);
        }
      }
    });
    for (final id in removidosIds) {
      registrarDeleteParaRede('produto', id);
    }
    if (removidosIds.isNotEmpty) {
      invalidarCacheBusca();
    }
    return removidosIds.length;
  }

  /// Converte nomes em MAIUSCULO para titulo (ex.: Abracadeira de Nylon…).
  ///
  /// Atualiza tambem [Produto.nomeImpressao] quando ele era igual ao nome antigo
  /// ou estava vazio.
  ({int alterados, int inalterados}) padronizarNomesTituloEmLote() {
    var alterados = 0;
    var inalterados = 0;
    _db.store.runInTransaction(TxMode.write, () {
      for (final p in _db.produtoBox.getAll()) {
        final nomeAntigo = p.nome;
        final impressaoAntiga = p.nomeImpressao.trim();
        final nomeNovo = ProdutoNomeTituloNormalizer.normalizar(nomeAntigo);
        if (nomeNovo.isEmpty || nomeNovo == nomeAntigo.trim()) {
          inalterados++;
          continue;
        }
        p.nome = nomeNovo;
        if (impressaoAntiga.isEmpty || impressaoAntiga == nomeAntigo.trim()) {
          p.nomeImpressao = nomeNovo;
        } else {
          p.nomeImpressao = ProdutoNomeExibicao.normalizarNomeImpressaoPersistido(
            nome: nomeNovo,
            nomeImpressao: impressaoAntiga,
          );
        }
        _db.produtoBox.put(p);
        alterados++;
      }
    });
    if (alterados > 0) {
      invalidarCacheBusca();
      notificarAlteracaoParaRede(entidade: 'produto', entidadeId: 0);
    }
    return (alterados: alterados, inalterados: inalterados);
  }

  /// Quantos produtos apontam para o mesmo arquivo de foto.
  int contarProdutosComFotoPath(
    String imagePath, {
    int? excluirProdutoId,
  }) {
    final alvo = imagePath.trim();
    if (alvo.isEmpty) return 0;
    final alvoAbs = p.normalize(File(alvo).absolute.path);
    final alvoBase = p.basename(alvoAbs);
    var n = 0;
    for (final pr in _db.produtoBox.getAll()) {
      if (excluirProdutoId != null && pr.id == excluirProdutoId) continue;
      final fp = pr.fotoPath.trim();
      if (fp.isEmpty) continue;
      final fpAbs = p.normalize(File(fp).absolute.path);
      if (fpAbs == alvoAbs || p.basename(fpAbs) == alvoBase) {
        n++;
      }
    }
    return n;
  }

  /// Converte fotoPath absoluto (outro PC) para basename de imagem.
  int normalizarFotoPathsParaSyncLan() {
    var alterados = 0;
    _db.store.runInTransaction(TxMode.write, () {
      for (final pr in _db.produtoBox.getAll()) {
        final raw = pr.fotoPath.trim();
        if (raw.isEmpty) continue;
        final nome = ProdutoImagemNomeArquivo.extrairNomeParaLan(raw);
        if (nome == null || nome == raw) continue;
        pr.fotoPath = nome;
        _db.produtoBox.put(pr);
        alterados++;
      }
    });
    if (alterados > 0) {
      invalidarCacheBusca();
    }
    return alterados;
  }

  /// Une fotos com o mesmo conteudo em um unico arquivo e atualiza os produtos.
  Future<({int produtosAtualizados, int arquivosRemovidos})>
      consolidarFotosDuplicadas() async {
    final produtos = _db.produtoBox.getAll();
    final pares = <({int id, String fotoPath})>[
      for (final pr in produtos)
        if (pr.fotoPath.trim().isNotEmpty)
          (id: pr.id, fotoPath: pr.fotoPath.trim()),
    ];
    if (pares.isEmpty) {
      return (produtosAtualizados: 0, arquivosRemovidos: 0);
    }

    final svc = ProdutoImagemService(imagesDirectoryPath: productImagesDirPath);
    final resultado = await svc.consolidarImagensDuplicadas(pares);
    if (resultado.novosPaths.isEmpty) {
      return (
        produtosAtualizados: 0,
        arquivosRemovidos: resultado.arquivosRemovidos,
      );
    }

    var atualizados = 0;
    _db.store.runInTransaction(TxMode.write, () {
      for (final entry in resultado.novosPaths.entries) {
        final pr = _db.produtoBox.get(entry.key);
        if (pr == null) continue;
        pr.fotoPath = entry.value;
        _db.produtoBox.put(pr);
        atualizados++;
      }
    });
    if (atualizados > 0) {
      invalidarCacheBusca();
      notificarAlteracaoParaRede(entidade: 'produto', entidadeId: 0);
    }
    return (
      produtosAtualizados: atualizados,
      arquivosRemovidos: resultado.arquivosRemovidos,
    );
  }

  /// Remove todos os produtos do cadastro para reimportacao do zero.
  ///
  /// Mantem vendas, clientes, usuarios e itens historicos de venda.
  /// Limpa dados satelites do catalogo (movimentos, historico de entrada,
  /// kits, promocões, sugestoes, vinculos e lista de compras).
  Future<ProdutoCadastroZerarResultado> zerarCadastroCompleto({
    bool limparImagens = true,
  }) async {
    final produtos = _db.produtoBox.getAll();
    final ids = produtos.map((p) => p.id).where((id) => id > 0).toList();
    final total = ids.length;

    final imagensRemovidas = limparImagens
        ? await _limparPastaImagensProdutos()
        : 0;

    var movimentos = 0;
    var historicos = 0;
    var vinculos = 0;
    var kits = 0;
    var kitItens = 0;
    var promocoes = 0;
    var promoItens = 0;
    var promoCombos = 0;
    var sugestoes = 0;
    var metricasSugestao = 0;
    var listaCompras = 0;

    _db.store.runInTransaction(TxMode.write, () {
      historicos = _db.historicoEntradaBox.removeAll();
      movimentos = _db.movimentoEstoqueBox.removeAll();
      vinculos = _db.vinculoFornecedorProdutoBox.removeAll();
      kitItens = _db.kitOrcamentoItemBox.removeAll();
      kits = _db.kitOrcamentoBox.removeAll();
      promoItens = _db.promocaoItemBox.removeAll();
      promoCombos = _db.promocaoComboItemBox.removeAll();
      promocoes = _db.promocaoBox.removeAll();
      sugestoes = _db.produtoSugestaoVendaBox.removeAll();
      metricasSugestao = _db.sugestaoVendaMetricaEventoBox.removeAll();
      listaCompras = _db.itemListaCompraBox.removeAll();
      _db.produtoBox.removeAll();
    });

    if (ids.isNotEmpty) {
      await SyncDeleteOutbox.registrarVarios(
        entity: 'produto',
        entityIds: ids,
      );
      await SyncDirtyOutbox.removerVarios(
        entity: 'produto',
        entityIds: ids,
      );
    }
    invalidarCacheBusca();
    notificarAlteracaoParaRede(entidade: 'produto', entidadeId: 0);

    return ProdutoCadastroZerarResultado(
      produtosRemovidos: total,
      movimentosRemovidos: movimentos,
      historicosEntradaRemovidos: historicos,
      vinculosRemovidos: vinculos,
      kitsRemovidos: kits,
      kitItensRemovidos: kitItens,
      promocoesRemovidas: promocoes,
      promocaoItensRemovidos: promoItens,
      promocaoCombosRemovidos: promoCombos,
      sugestoesRemovidas: sugestoes,
      metricasSugestaoRemovidas: metricasSugestao,
      itensListaCompraRemovidos: listaCompras,
      imagensRemovidas: imagensRemovidas,
    );
  }

  Future<int> _limparPastaImagensProdutos() async {
    final dir = _db.productImagesDir;
    if (!dir.existsSync()) return 0;
    var removidas = 0;
    for (final entity in dir.listSync()) {
      try {
        if (entity is File) {
          await entity.delete();
          removidas++;
        }
      } catch (_) {
        // Melhor esforco: cadastro ja foi limpo.
      }
    }
    return removidas;
  }

  /// Remove cadastros duplicados do mesmo codigo interno (mantem 1 por SKU).
  ///
  /// Criterio do sobrevivente: maior estoque, depois menor id (mais antigo).
  /// Retorna quantos registros foram removidos.
  Future<int> deduplicarProdutosMesmoSku({bool notificarRede = true}) async {
    final porSku = <String, List<Produto>>{};
    for (final p in _db.produtoBox.getAll()) {
      final sku = p.codigoInterno.trim().toLowerCase();
      if (sku.isEmpty) continue;
      (porSku[sku] ??= <Produto>[]).add(p);
    }

    final gruposDup = <List<Produto>>[];
    for (final g in porSku.values) {
      if (g.length < 2) continue;
      g.sort((a, b) {
        final estoque = b.estoqueReal.compareTo(a.estoqueReal);
        if (estoque != 0) return estoque;
        return a.id.compareTo(b.id);
      });
      gruposDup.add(g);
    }
    if (gruposDup.isEmpty) return 0;

    final idsDup = <int>[
      for (final g in gruposDup)
        for (var i = 1; i < g.length; i++) g[i].id,
    ];
    if (idsDup.isEmpty) return 0;

    // Query por ToOne (nao varre todas as vendas da loja).
    final qItens = _db.itemVendaBox
        .query(ItemVenda_.produto.oneOf(idsDup))
        .build();
    final qHist = _db.historicoEntradaBox
        .query(HistoricoEntrada_.produto.oneOf(idsDup))
        .build();
    final qMov = _db.movimentoEstoqueBox
        .query(MovimentoEstoque_.produto.oneOf(idsDup))
        .build();
    final qVinc = _db.vinculoFornecedorProdutoBox
        .query(VinculoFornecedorProduto_.produto.oneOf(idsDup))
        .build();
    final qLista = _db.itemListaCompraBox
        .query(ItemListaCompra_.produto.oneOf(idsDup))
        .build();
    late final List<ItemVenda> itensVenda;
    late final List<HistoricoEntrada> historicos;
    late final List<MovimentoEstoque> movimentos;
    late final List<VinculoFornecedorProduto> vinculos;
    late final List<ItemListaCompra> listaCompra;
    try {
      itensVenda = qItens.find();
      historicos = qHist.find();
      movimentos = qMov.find();
      vinculos = qVinc.find();
      listaCompra = qLista.find();
    } finally {
      qItens.close();
      qHist.close();
      qMov.close();
      qVinc.close();
      qLista.close();
    }

    final keeperPorDupId = <int, Produto>{};
    final removidos = <int>[];

    _db.store.runInTransaction(TxMode.write, () {
      for (final grupo in gruposDup) {
        final keeper = grupo.first;
        for (var i = 1; i < grupo.length; i++) {
          final dup = grupo[i];
          keeperPorDupId[dup.id] = keeper;
          if (dup.estoqueReal != 0) {
            keeper.estoqueReal += dup.estoqueReal;
            keeper.estoqueAtual = keeper.estoqueReal;
            keeper.estoqueVersao++;
            _db.produtoBox.put(keeper);
          }
          _db.produtoBox.remove(dup.id);
          removidos.add(dup.id);
        }
      }

      for (final item in itensVenda) {
        final k = keeperPorDupId[item.produto.targetId];
        if (k == null) continue;
        item.produto.target = k;
        _db.itemVendaBox.put(item);
      }
      for (final h in historicos) {
        final k = keeperPorDupId[h.produto.targetId];
        if (k == null) continue;
        h.produto.target = k;
        _db.historicoEntradaBox.put(h);
      }
      for (final mv in movimentos) {
        final k = keeperPorDupId[mv.produto.targetId];
        if (k == null) continue;
        mv.produto.target = k;
        _db.movimentoEstoqueBox.put(mv);
      }
      for (final v in vinculos) {
        final k = keeperPorDupId[v.produto.targetId];
        if (k == null) continue;
        v.produto.target = k;
        _db.vinculoFornecedorProdutoBox.put(v);
      }
      for (final item in listaCompra) {
        final k = keeperPorDupId[item.produto.targetId];
        if (k == null) continue;
        item.produto.target = k;
        _db.itemListaCompraBox.put(item);
      }
    });

    if (removidos.isEmpty) return 0;

    invalidarCacheBusca();
    await SyncDeleteOutbox.registrarVarios(
      entity: 'produto',
      entityIds: removidos,
    );
    if (notificarRede) {
      notificarAlteracaoParaRede(entidade: 'produto', entidadeId: 0);
    }
    return removidos.length;
  }

  Produto? obterPorId(int id) => _db.produtoBox.get(id);

  /// Busca por codigo interno (literal ou numerico sem zeros a esquerda).
  Produto? obterPorCodigoInterno(String codigo, {int? ignorarProdutoId}) {
    final lista = listarPorCodigoInterno(
      codigo,
      ignorarProdutoId: ignorarProdutoId,
    );
    return lista.isEmpty ? null : lista.first;
  }

  /// Todos os produtos com o mesmo SKU (detecta duplicatas reais).
  List<Produto> listarPorCodigoInterno(
    String codigo, {
    int? ignorarProdutoId,
  }) {
    final alvo = codigo.trim();
    if (alvo.isEmpty) return const [];
    _garantirCachesAtualizados();
    final norm = normalizarTextoBuscaProduto(alvo);
    final out = <Produto>[];
    for (final doc in _cacheDocs) {
      final p = doc.produto;
      if (ignorarProdutoId != null && p.id == ignorarProdutoId) continue;
      if (doc.correspondeCodigoInterno(norm)) out.add(p);
    }
    return out;
  }

  /// SKU automatico curto para PDV: 1, 2, 3… apos o maior numerico ja cadastrado.
  String proximoSkuAutomatico({int? ignorarProdutoId}) {
    final codigos = <String>[];
    for (final p in listarTodos()) {
      if (ignorarProdutoId != null && p.id == ignorarProdutoId) continue;
      codigos.add(p.codigoInterno);
    }
    var sku = proximoSkuNumericoSequencial(codigos);
    var tentativas = 0;
    while (obterPorCodigoInterno(sku, ignorarProdutoId: ignorarProdutoId) !=
            null &&
        tentativas < 1000) {
      final n = int.tryParse(sku) ?? 0;
      sku = '${n + 1}';
      tentativas++;
    }
    return sku;
  }

  void _garantirSkuUnico(Produto produto) {
    final sku = produto.codigoInterno.trim();
    if (sku.isEmpty) return;
    final conflito = obterPorCodigoInterno(
      sku,
      ignorarProdutoId: produto.id > 0 ? produto.id : null,
    );
    if (conflito != null) {
      throw ProdutoSkuDuplicadoException(
        sku: sku,
        produtoExistenteNome: conflito.nome,
        produtoExistenteId: conflito.id,
      );
    }
  }

  /// Entradas por importacao de NF-e, mais recentes primeiro.
  List<HistoricoEntrada> listarHistoricoEntradaPorProduto(int produtoId) {
    final q = _db.historicoEntradaBox
        .query(HistoricoEntrada_.produto.equals(produtoId))
        .order(HistoricoEntrada_.dataEmissao, flags: Order.descending)
        .build();
    try {
      return q.find();
    } finally {
      q.close();
    }
  }

  /// Data da NF-e de entrada mais recente, se houver.
  DateTime? obterDataUltimaCompraProduto(int produtoId) {
    final entradas = listarHistoricoEntradaPorProduto(produtoId);
    if (entradas.isEmpty) return null;
    return entradas.first.dataEmissao;
  }

  /// Kardex de movimentacoes de estoque, mais recentes primeiro.
  List<MovimentoEstoque> listarMovimentosEstoquePorProduto(
    int produtoId, {
    int limite = 200,
  }) =>
      MovimentoEstoqueRepository(_db).listarPorProduto(
        produtoId,
        limite: limite,
      );

  /// Ajuste manual de inventario com registro no kardex.
  void ajustarEstoqueManual({
    required int produtoId,
    required int novaQuantidadeFisica,
    required String motivo,
    String usuarioLogin = '',
    String numeroLote = '',
    DateTime? dataValidade,
  }) {
    _db.store.runInTransaction(TxMode.write, () {
      final produto = _db.produtoBox.get(produtoId);
      if (produto == null) {
        throw StateError('Produto id $produtoId nao encontrado.');
      }
      _estoque.executarAjusteManualInventario(
        produto,
        novaQuantidadeFisica,
        motivo,
        usuarioLogin: usuarioLogin,
        numeroLote: numeroLote,
        dataValidade: dataValidade,
      );
      if (produto.controlaLoteValidade) {
        LoteProdutoRepository(_db).garantirMigracaoSemLote(produto);
      }
    });
    invalidarCacheBusca();
    notificarAlteracaoParaRede(entidade: 'produto', entidadeId: produtoId);
    notificarAlteracaoParaRede(entidade: 'lote_produto', entidadeId: 0);
  }

  /// Media ponderada das entradas de NF-e; null se nao houver historico valido.
  double? calcularCustoMedioPonderadoPorEntradasNfe(int produtoId) =>
      calcularCustoMedioPonderadoEntradasNfe(_db, produtoId);

  /// Atualiza [Produto.custoMedio]: prioridade entradas NF-e; senao [legadoImportacao];
  /// senao [Produto.precoCusto].
  void sincronizarCustoMedioInteligenteParaProduto(
    int produtoId, {
    double? legadoImportacao,
  }) {
    final p = _db.produtoBox.get(produtoId);
    if (p == null) return;
    final cm = calcularCustoMedioPonderadoEntradasNfe(_db, produtoId);
    if (cm != null) {
      p.custoMedio = cm;
    } else if (legadoImportacao != null && legadoImportacao > 0) {
      p.custoMedio = legadoImportacao;
    } else {
      p.custoMedio = p.precoCusto < 0 ? 0 : p.precoCusto;
    }
    _db.produtoBox.put(p);
    if (_importacaoEmLoteDepth <= 0) {
      invalidarCacheBusca();
      notificarAlteracaoParaRede(entidade: 'produto', entidadeId: produtoId);
    }
  }

  /// Recalcula custo medio para varios produtos (uma notificacao ao final).
  void sincronizarCustoMedioInteligenteParaProdutos(
    Iterable<int> produtoIds, {
    Map<int, double>? legadoImportacaoPorId,
  }) {
    final vistos = <int>{};
    for (final id in produtoIds) {
      if (id <= 0 || vistos.contains(id)) continue;
      vistos.add(id);
      final p = _db.produtoBox.get(id);
      if (p == null) continue;
      final legado = legadoImportacaoPorId?[id];
      final cm = calcularCustoMedioPonderadoEntradasNfe(_db, id);
      if (cm != null) {
        p.custoMedio = cm;
      } else if (legado != null && legado > 0) {
        p.custoMedio = legado;
      } else {
        p.custoMedio = p.precoCusto < 0 ? 0 : p.precoCusto;
      }
      _db.produtoBox.put(p);
    }
    if (vistos.isNotEmpty) {
      invalidarCacheBusca();
      notificarAlteracaoParaRede(entidade: 'produto', entidadeId: 0);
    }
  }

  /// Executa gravacoes em massa sem rebuild de cache/notificacao a cada item.
  Future<T> executarImportacaoEmLote<T>(Future<T> Function() acao) async {
    _importacaoEmLoteDepth++;
    enterSyncApplySilencioso();
    try {
      return await acao();
    } finally {
      leaveSyncApplySilencioso();
      _importacaoEmLoteDepth--;
      if (_importacaoEmLoteDepth <= 0) {
        invalidarCacheBusca();
        notificarAlteracaoParaRede(entidade: 'produto', entidadeId: 0);
      }
    }
  }

  void _invalidarCacheBusca() {
    _cacheDocs = const [];
    _cacheProdutoCount = -1;
    _cacheMontadoEm = null;
  }

  /// Atualiza estoque nos docs em cache sem rebuild completo do catalogo.
  void _sincronizarEstoqueNosDocsCache() {
    if (_cacheDocs.isEmpty) return;
    for (final doc in _cacheDocs) {
      final id = doc.produto.id;
      if (id <= 0) continue;
      final fresh = _db.produtoBox.get(id);
      if (fresh == null) continue;
      doc.produto.estoqueReal = fresh.estoqueReal;
      doc.produto.estoqueReservado = fresh.estoqueReservado;
      doc.produto.estoqueAtual = fresh.estoqueAtual;
      doc.produto.preco1 = fresh.preco1;
      doc.produto.preco2 = fresh.preco2;
      doc.produto.preco3 = fresh.preco3;
      doc.produto.precoVenda = fresh.precoVenda;
      doc.produto.precoCusto = fresh.precoCusto;
      doc.produto.nome = fresh.nome;
      doc.produto.ativo = fresh.ativo;
    }
  }

  /// Apos venda/entrega: estoque mudou, mas o catalogo de busca
  /// (nomes, barras, etc.) continua valido. Atualiza docs em memoria e avisa a UI.
  void atualizarCacheAposMovimentoEstoque() {
    _sincronizarEstoqueNosDocsCache();
    notifyListeners();
  }

  @override
  Future<void> onObjectBoxClosingForCopy() async {
    _invalidarCacheBusca();
  }

  @override
  void onObjectBoxReopenedAfterCopy() {
    _invalidarCacheBusca();
    notifyListeners();
  }

  @override
  void dispose() {
    ObjectBoxLifecycleHub.remover(this);
    super.dispose();
  }

  /// Chamado apos operacoes que alteram cadastro/estrutura do catalogo
  /// (salvar produto, sync de produtos, importacao, etc.).
  void invalidarCacheBusca() {
    _invalidarCacheBusca();
    notifyListeners();
  }
}
