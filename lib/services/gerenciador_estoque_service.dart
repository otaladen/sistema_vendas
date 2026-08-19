import '../data/lote_produto_repository.dart';
import '../data/movimento_estoque_repository.dart';
import '../data/objectbox.dart';
import '../data/produto_busca_util.dart';
import '../domain/complemento_entrega_codec.dart';
import '../domain/entrega_venda_helper.dart';
import '../domain/entregas/loja_origem_mercadoria.dart';
import '../domain/entregas/buscar_na_loja.dart';
import '../domain/produto_embalagem.dart';
import '../domain/estoque/tipo_movimento_estoque.dart';
import '../domain/produto_estoque_sync.dart';
import '../domain/venda_documento_rotulo_helper.dart';
import '../model/item_venda.dart';
import '../model/produto.dart';
import '../model/venda.dart';
import '../objectbox.g.dart';
import 'compras_preditivas_service.dart';
import 'lote_fefo_service.dart';

/// Ponto unico de movimentacao de estoque no ObjectBox.
///
/// Regra: baixa fisica de venda no balcao ocorre no **cupom nao fiscal**, nao na
/// NFC-e/NF-e de venda. Reservas (carreto / retirada futura) seguem no orcamento
/// e na finalizacao; saida do carro e retiradas parciais usam tipos proprios.
/// Snapshot de saldos antes de uma mutacao (kardex).
typedef EstoqueAntes = ({int fisico, int reserva});

class GerenciadorEstoqueService {
  GerenciadorEstoqueService(this._db)
      : _movimentos = MovimentoEstoqueRepository(_db),
        _lotes = LoteProdutoRepository(_db);

  final ObjectBox _db;
  final MovimentoEstoqueRepository _movimentos;
  final LoteProdutoRepository _lotes;
  LoteFefoService get _fefo => LoteFefoService(_lotes);
  EstoqueAntes _snap(Produto p) =>
      (fisico: p.estoqueReal, reserva: p.estoqueReservado);

  void _garantirEscalaEstoque(Produto produto) {
    ProdutoEmbalagem.garantirEstoqueEmEscalaNoProduto(produto);
  }

  /// Sempre relê o [Produto] do ObjectBox antes de mutar estoque.
  ///
  /// Varios [ItemVenda] da mesma venda (ex.: misto leva+futura) podem manter
  /// `item.produto.target` apontando para instancias distintas/stale; gravar
  /// a antiga zera [Produto.estoqueReservado] apos a reserva da outra linha.
  ///
  /// Se o ToOne foi zerado (put via Backlink incompleto), tenta religar pelo
  /// nome snapshot da linha.
  Produto _produtoAtualDoItem(ItemVenda item) {
    Produto? produto;
    final produtoId = _produtoIdDoItem(item);
    if (produtoId > 0) {
      produto = _db.produtoBox.get(produtoId);
    }
    produto ??= _produtoPorNomeSnapshot(item.nomeProduto);
    if (produto == null) {
      throw StateError(
        'Produto do item "${item.nomeProduto}" nao encontrado.',
      );
    }
    final idAntes = _produtoIdDoItem(item);
    try {
      item.produto.target = produto;
    } catch (_) {}
    if (item.id > 0 && idAntes != produto.id) {
      try {
        _db.itemVendaBox.put(item);
      } catch (_) {}
    }
    return produto;
  }

  int _produtoIdDoItem(ItemVenda item) {
    try {
      return item.produto.targetId;
    } catch (_) {
      return 0;
    }
  }

  Produto? _produtoPorNomeSnapshot(String nome) {
    final n = nome.trim();
    if (n.isEmpty) return null;
    final q = _db.produtoBox
        .query(Produto_.nome.equals(n, caseSensitive: false))
        .build();
    try {
      final hits = q.find();
      if (hits.isEmpty) return null;
      if (hits.length == 1) return hits.first;
      final ativos = hits.where((p) => p.ativo).toList();
      if (ativos.length == 1) return ativos.first;
      return null;
    } finally {
      q.close();
    }
  }

  // --- Persistencia e politica ---

  void persistirProduto(
    Produto produto,
    TipoMovimentoEstoque tipo, {
    EstoqueAntes? antes,
    String documentoReferencia = '',
    String motivo = '',
    String usuarioLogin = '',
  }) {
    if (tipo == TipoMovimentoEstoque.nfceEmissao ||
        tipo == TipoMovimentoEstoque.nfeVendaEmissao) {
      PoliticaMovimentoEstoque.validarNaoAlteraEstoque(tipo);
    }
    // Rede de seguranca: reservado nunca deve ficar negativo (stale/legado).
    if (produto.estoqueReservado < 0) {
      produto.estoqueReservado = 0;
    }
    ProdutoEstoqueSync.marcarEstoqueAlterado(produto);
    _db.produtoBox.put(produto);
    if (antes != null && produto.id > 0) {
      _movimentos.registrar(
        produto: produto,
        tipo: tipo,
        saldoFisicoAntes: antes.fisico,
        saldoReservaAntes: antes.reserva,
        saldoFisicoDepois: produto.estoqueReal,
        saldoReservaDepois: produto.estoqueReservado,
        documentoReferencia: documentoReferencia,
        motivo: motivo,
        usuarioLogin: usuarioLogin,
      );
    }
  }

  void garantirDocumentoFiscalNaoAlteraEstoque(TipoMovimentoEstoque tipo) {
    PoliticaMovimentoEstoque.validarNaoAlteraEstoque(tipo);
  }

  /// Grava cadastro/custo/metricas sem movimentar [estoqueReal] nem [estoqueVersao].
  // policy-allow: metadados produto (custo medio, precos, flags)
  int persistirProdutoMetadados(Produto produto) {
    return _db.produtoBox.put(produto);
  }

  static int _quantidadeInteira(num quantidade) {
    if (!quantidade.isFinite) {
      throw StateError('Quantidade de estoque invalida (nao finita).');
    }
    return quantidade.round();
  }

  /// Entrada fisica por conferencia/importacao de NF-e de compra.
  void registrarEntradaPorNotaFiscal(
    Produto produto,
    num quantidade, {
    String documentoReferencia = '',
    String numeroLote = '',
    DateTime? dataValidade,
  }) {
    if (produto.id <= 0) {
      throw StateError(
        'Produto sem id: grave o cadastro antes de registrar entrada por NF-e.',
      );
    }
    final qtd = _quantidadeInteira(quantidade);
    if (qtd <= 0) return;
    PoliticaMovimentoEstoque.validarPermiteAlteracaoFisica(
      TipoMovimentoEstoque.entradaNfeCompra,
    );
    final atual = _db.produtoBox.get(produto.id);
    if (atual == null) {
      throw StateError('Produto id ${produto.id} nao encontrado.');
    }
    _garantirEscalaEstoque(atual);
    final antes = _snap(atual);
    atual.estoqueReal += qtd;
    atual.estoqueAtual = atual.estoqueReal;
    if (atual.controlaLoteValidade) {
      _lotes.registrarEntrada(
        produto: atual,
        quantidade: qtd,
        numeroLote: numeroLote,
        dataValidade: dataValidade,
      );
    }
    persistirProduto(
      atual,
      TipoMovimentoEstoque.entradaNfeCompra,
      antes: antes,
      documentoReferencia: documentoReferencia,
    );
    produto.estoqueReal = atual.estoqueReal;
    produto.estoqueAtual = atual.estoqueAtual;
    produto.estoqueVersao = atual.estoqueVersao;
  }

  /// Estorno da entrada de estoque de uma NF-e de compra ja lancada.
  void estornarEntradaPorNotaFiscal(
    Produto produto,
    num quantidade, {
    String documentoReferencia = '',
  }) {
    if (produto.id <= 0) {
      throw StateError('Produto sem id para estornar entrada de NF-e.');
    }
    final qtd = _quantidadeInteira(quantidade);
    if (qtd <= 0) return;
    PoliticaMovimentoEstoque.validarPermiteAlteracaoFisica(
      TipoMovimentoEstoque.estornoEntradaNfeCompra,
    );
    final atual = _db.produtoBox.get(produto.id);
    if (atual == null) {
      throw StateError('Produto id ${produto.id} nao encontrado.');
    }
    if (atual.estoqueReal < qtd) {
      throw StateError(
        'Estoque insuficiente para estornar entrada em "${atual.nome}": '
        'fisico ${atual.estoqueReal}, entrada da nota $qtd.',
      );
    }
    final estoqueApos = atual.estoqueReal - qtd;
    if (estoqueApos < atual.estoqueReservado) {
      throw StateError(
        'Em "${atual.nome}" ha ${atual.estoqueReservado} un. reservadas; '
        'apos o estorno restariam $estoqueApos no fisico.',
      );
    }
    final antes = _snap(atual);
    atual.estoqueReal = estoqueApos;
    atual.estoqueAtual = atual.estoqueReal;
    if (atual.controlaLoteValidade) {
      _fefo.consumirFefo(produto: atual, quantidade: qtd);
    }
    persistirProduto(
      atual,
      TipoMovimentoEstoque.estornoEntradaNfeCompra,
      antes: antes,
      documentoReferencia: documentoReferencia,
    );
    produto.estoqueReal = atual.estoqueReal;
    produto.estoqueAtual = atual.estoqueAtual;
    produto.estoqueVersao = atual.estoqueVersao;
  }

  /// Ajuste direto de inventario (cadastro de produto, perda, quebra, balanco).
  void executarAjusteManualInventario(
    Produto produto,
    num novaQuantidadeFisica,
    String motivo, {
    String usuarioLogin = '',
    String numeroLote = '',
    DateTime? dataValidade,
  }) {
    if (produto.id <= 0) {
      throw StateError(
        'Produto sem id: inclua o cadastro antes do ajuste de inventario.',
      );
    }
    final atual = _db.produtoBox.get(produto.id);
    if (atual == null) {
      throw StateError('Produto id ${produto.id} nao encontrado.');
    }
    _garantirEscalaEstoque(atual);
    final antes = _snap(atual);
    final alvo = _quantidadeInteira(novaQuantidadeFisica);
    final delta = alvo - atual.estoqueReal;
    prepararAjusteManualInventario(atual, novaQuantidadeFisica, motivo);
    if (atual.controlaLoteValidade && delta != 0) {
      if (delta > 0) {
        _lotes.registrarEntrada(
          produto: atual,
          quantidade: delta,
          numeroLote: numeroLote,
          dataValidade: dataValidade,
        );
      } else {
        _fefo.consumirFefo(produto: atual, quantidade: -delta);
      }
    }
    persistirProduto(
      atual,
      TipoMovimentoEstoque.ajusteManual,
      antes: antes,
      motivo: motivo,
      usuarioLogin: usuarioLogin,
    );
    produto.estoqueReal = atual.estoqueReal;
    produto.estoqueAtual = atual.estoqueAtual;
    produto.estoqueVersao = atual.estoqueVersao;
    produto.estoqueReservado = atual.estoqueReservado;
  }

  /// Valida e aplica estoque alvo em memoria (persistir na mesma transacao do caller).
  void prepararAjusteManualInventario(
    Produto produtoAlvo,
    num novaQuantidadeFisica,
    String motivo,
  ) {
    if (produtoAlvo.id <= 0) {
      throw StateError(
        'Produto sem id: inclua o cadastro antes do ajuste de inventario.',
      );
    }
    final motivoNorm = motivo.trim();
    if (motivoNorm.isEmpty) {
      throw StateError('Informe o motivo do ajuste manual de estoque.');
    }
    final alvo = _quantidadeInteira(novaQuantidadeFisica);
    if (alvo < 0) {
      throw StateError('Quantidade fisica nao pode ser negativa.');
    }
    PoliticaMovimentoEstoque.validarPermiteAlteracaoFisica(
      TipoMovimentoEstoque.ajusteManual,
    );
    if (alvo < produtoAlvo.estoqueReservado) {
      throw StateError(
        'Novo fisico ($alvo) menor que o reservado (${produtoAlvo.estoqueReservado}) '
        'em "${produtoAlvo.nome}". Libere reservas antes do ajuste.',
      );
    }
    produtoAlvo.estoqueReal = alvo;
    produtoAlvo.estoqueAtual = alvo;
    ProdutoEstoqueSync.marcarEstoqueAlterado(produtoAlvo);
  }

  // --- Orcamento pendente (PDV): sem reserva de estoque.
  // Reserva de retirada futura / carreto ocorre so na finalizacao no caixa
  // ([ajustarReservaEstoqueAoFinalizarItem] / converterOrcamentoParaVenda).

  int quantidadeReservavelOrcamentoItem(ItemVenda item) {
    final tipo = EntregaVendaHelper.tipoEfetivoItem(item);
    if (tipo == EntregaVendaHelper.tipoRetirada) return 0;
    if (tipo == EntregaVendaHelper.tipoRetiradaFutura ||
        tipo == EntregaVendaHelper.tipoEntregaLoja) {
      return item.quantidadeUnidadeEstoque;
    }
    return 0;
  }

  void reservarEstoqueItemOrcamento({
    required ItemVenda item,
    required bool permitirVendaSemEstoque,
  }) {
    // No-op: orcamento nao reserva; ver [ajustarReservaEstoqueAoFinalizarItem].
  }

  /// Libera reserva de orcamento.
  ///
  /// No-op: orcamentos nao reservam estoque (so na finalizacao no caixa).
  void liberarReservaEstoqueItemOrcamento(ItemVenda item) {
    // No-op.
  }

  void liberarReservaEstoqueOrcamento(Venda venda) {
    for (final item in venda.itens) {
      liberarReservaEstoqueItemOrcamento(item);
    }
  }

  // --- Finalizacao caixa (reserva; retirada imediata no cupom) ---

  /// Incrementa [Produto.estoqueReservado] na finalizacao no caixa
  /// (retirada futura / carreto).
  ///
  /// Sempre soma a quantidade deste item: o total reservado do produto pode ja
  /// incluir outras vendas — nao comparar com [qReserva] absoluto.
  /// Relê o [Produto] do ObjectBox para nao gravar instancia stale.
  void ajustarReservaEstoqueAoFinalizarItem({
    required ItemVenda item,
    required bool permitirVendaSemEstoque,
  }) {
    final produto = _produtoAtualDoItem(item);

    final qReserva = item.quantidadeUnidadeEstoque;
    final qArmazenado = item.quantidade;
    if (qArmazenado <= 0) {
      throw StateError(
        'Quantidade invalida ao reservar "${produto.nome}" (item ${item.id}).',
      );
    }
    if (qReserva <= 0) {
      throw StateError(
        'Quantidade de estoque invalida ao reservar "${produto.nome}": '
        'armazenado=$qArmazenado, unidadeEstoque=$qReserva.',
      );
    }

    final tipo = EntregaVendaHelper.tipoEfetivoItem(item);
    if (tipo == EntregaVendaHelper.tipoRetirada) {
      return;
    }

    if (!permitirVendaSemEstoque) {
      final livre = produto.estoqueReal - produto.estoqueReservado;
      if (livre < qReserva) {
        throw StateError(
          'Estoque insuficiente para reservar "${produto.nome}": '
          'livre $livre, necessario $qReserva.',
        );
      }
    }

    switch (tipo) {
      case EntregaVendaHelper.tipoRetiradaFutura:
        final antes = _snap(produto);
        produto.estoqueReservado += qReserva;
        persistirProduto(
          produto,
          TipoMovimentoEstoque.finalizacaoAjustaReserva,
          antes: antes,
          documentoReferencia: _refItemVenda(item),
          motivo: 'Reserva retirada futura ${_refItemVenda(item)}',
        );
        break;
      case EntregaVendaHelper.tipoEntregaLoja:
        final antes = _snap(produto);
        produto.estoqueReservado += qReserva;
        item.quantidadeNoCarreto = qArmazenado;
        _db.itemVendaBox.put(item);
        persistirProduto(
          produto,
          TipoMovimentoEstoque.finalizacaoAjustaReserva,
          antes: antes,
          documentoReferencia: _refItemVenda(item),
          motivo: 'Reserva carreto ${_refItemVenda(item)}',
        );
        break;
      default:
        throw StateError(
          'Tipo de entrega nao suportado para reserva: $tipo '
          '(item ${item.id} / ${item.nomeProduto}).',
        );
    }
  }

  // --- Cupom nao fiscal (baixa retirada imediata; na finalizacao do caixa) ---

  void baixarEstoqueRetiradaImediataCupomNaoFiscal({
    required ItemVenda item,
    required bool permitirVendaSemEstoque,
    Map<int, int>? consumoVendasPrecalculado,
  }) {
    if (EntregaVendaHelper.tipoEfetivoItem(item) !=
        EntregaVendaHelper.tipoRetirada) {
      return;
    }
    final produto = _produtoAtualDoItem(item);
    _garantirEscalaEstoque(produto);
    final qArmazenado = item.quantidade;
    final qEstoque = item.quantidadeUnidadeEstoque;
    if (qArmazenado <= 0) return;
    if (item.quantidadeJaRetirada >= qArmazenado) return;

    // Livre = fisico - reservado. Em venda mista a reserva (futura/carreto)
    // ja foi aplicada antes desta baixa; validar so o fisico permite
    // disponivel negativo (ex.: real 5, reserva 3, leva 3 → livre -1).
    final livre = produto.estoqueReal - produto.estoqueReservado;
    if (!permitirVendaSemEstoque && livre < qEstoque) {
      throw StateError(
        'Estoque insuficiente para "${produto.nome}": '
        'livre $livre (fisico ${produto.estoqueReal}, reservado '
        '${produto.estoqueReservado}), necessario $qEstoque.',
      );
    }

    PoliticaMovimentoEstoque.validarPermiteAlteracaoFisica(
      TipoMovimentoEstoque.cupomNaoFiscalVenda,
    );
    final antes = _snap(produto);
    if (produto.controlaLoteValidade) {
      final consumos = _fefo.consumirFefo(
        produto: produto,
        quantidade: qEstoque,
      );
      final existentes = LoteConsumoSnapshot.decodeList(item.loteConsumosJson);
      item.loteConsumosJson = LoteConsumoSnapshot.encodeList([
        ...existentes,
        ...consumos,
      ]);
    }
    produto.estoqueReal -= qEstoque;
    item.quantidadeJaRetirada = qArmazenado;
    _db.itemVendaBox.put(item);
    persistirProduto(
      produto,
      TipoMovimentoEstoque.cupomNaoFiscalVenda,
      antes: antes,
      documentoReferencia: _refItemVenda(item),
    );
    ComprasPreditivasService(_db).atualizarAposVendaRegistrada(
      produto: produto,
      quantidadeVendida: qEstoque,
      estoqueRealJaAbatido: true,
      consumoPrecalculado: consumoVendasPrecalculado,
    );
  }

  void registrarBaixaEstoqueCupomNaoFiscal({
    required Venda venda,
    required bool permitirVendaSemEstoque,
    Iterable<ItemVenda>? itens,
  }) {
    if (venda.status != 'finalizada' || venda.cancelada) {
      throw StateError(
        'Somente vendas finalizadas ativas recebem baixa de cupom nao fiscal.',
      );
    }
    if (venda.estoqueBaixadoCupom) return;

    final lista = itens ?? venda.itens;
    final consumo =
        ComprasPreditivasService(_db).montarConsumoPorProdutoNoPeriodo();
    for (final item in lista) {
      baixarEstoqueRetiradaImediataCupomNaoFiscal(
        item: item,
        permitirVendaSemEstoque: permitirVendaSemEstoque,
        consumoVendasPrecalculado: consumo,
      );
    }
    venda.estoqueBaixadoCupom = true;
    venda.cupomNaoFiscalEmitidoEm = DateTime.now().toUtc();
    _db.vendaBox.put(venda);
  }

  // --- Venda direta legada ---

  void baixarEstoqueVendaDiretaLegada({
    required Produto produto,
    required int quantidade,
    required bool permitirVendaSemEstoque,
    Map<int, int>? consumoVendasPrecalculado,
  }) {
    if (quantidade <= 0) {
      throw StateError('Quantidade invalida para ${produto.nome}.');
    }
    PoliticaMovimentoEstoque.validarPermiteAlteracaoFisica(
      TipoMovimentoEstoque.vendaDiretaLegada,
    );
    final antes = _snap(produto);
    produto.estoqueReal -= quantidade;
    persistirProduto(
      produto,
      TipoMovimentoEstoque.vendaDiretaLegada,
      antes: antes,
      documentoReferencia: 'Produto ${produto.id}',
    );
    ComprasPreditivasService(_db).atualizarAposVendaRegistrada(
      produto: produto,
      quantidadeVendida: quantidade,
      estoqueRealJaAbatido: true,
      consumoPrecalculado: consumoVendasPrecalculado,
    );
  }

  // --- Produto interno frete ---

  int obterOuCriarProdutoFreteRetiradaFutura() {
    final q = _db.produtoBox
        .query(Produto_.codigoInterno.equals(kCodigoInternoFreteRetiradaFutura))
        .build();
    try {
      final existente = q.findFirst();
      if (existente != null) {
        return existente.id;
      }
    } finally {
      q.close();
    }
    final novo = Produto(
      codigoInterno: kCodigoInternoFreteRetiradaFutura,
      nome: 'Servico: Frete carreto (retirada futura)',
      quantidadeMinima: 0,
      precoCusto: 0,
      precoVenda: 0,
      preco1: 0,
      preco2: 0,
      preco3: 0,
      ativo: true,
    );
    novo.estoqueReal = 0;
    novo.estoqueReservado = 0;
    novo.estoqueAtual = 0;
    return _db.produtoBox.put(novo);
  }

  // --- Migracao retirada futura > carreto ---

  void migrarEstoqueRetiradaFuturaParaCarretoItens(Iterable<ItemVenda> itens) {
    for (final item in itens) {
      final qArmazenado = item.quantidadePendenteRetirada;
      item.quantidadeNoCarreto = qArmazenado;
      if (qArmazenado <= 0) {
        _db.itemVendaBox.put(item);
        continue;
      }
      final qEstoque = item.quantidadeUnidadeEstoqueDe(qArmazenado);
      final produto = _produtoAtualDoItem(item);
      if (produto.estoqueReservado < qEstoque || produto.estoqueReal < qEstoque) {
        throw StateError(
          'Estoque insuficiente para ${produto.nome}: reservado '
          '${produto.estoqueReservado}, precisa $qEstoque (fisico ${produto.estoqueReal}).',
        );
      }
      final antes = _snap(produto);
      final r = produto.estoqueReservado;
      produto.estoqueReservado = (r - qEstoque).clamp(0, r).toInt();
      produto.estoqueReal -= qEstoque;
      persistirProduto(
        produto,
        TipoMovimentoEstoque.carretoSaida,
        antes: antes,
        documentoReferencia: _refItemVenda(item),
      );
      item.quantidadeJaRetirada += qArmazenado;
      _db.itemVendaBox.put(item);
    }
  }

  // --- Carreto ---

  static int quantidadeItemParaEstoqueCarreto(ItemVenda item) {
    int armazenado;
    if (EntregaVendaHelper.itemMigradoRetiradaFuturaParaCarreto(item)) {
      armazenado = item.quantidadeNoCarreto;
    } else if (EntregaVendaHelper.tipoEfetivoItem(item) !=
        EntregaVendaHelper.tipoEntregaLoja) {
      return 0;
    } else {
      armazenado = item.quantidadeAindaNoCarretoAntesSaida;
    }
    return ProdutoEmbalagem.unidadeEstoqueDeQuantidadeArmazenada(
      produto: item.produto.target,
      quantidadeArmazenada: armazenado,
    );
  }

  /// Unidades fisicas desta loja (linha inteira local ou recorte buscar-na-loja).
  ///
  /// O recorte so conta depois do patio confirmar (origem mista / separado).
  static int quantidadeFisicaDestaLojaCarreto(Venda venda, ItemVenda item) {
    final qTotal = quantidadeItemParaEstoqueCarreto(item);
    if (qTotal <= 0) return 0;
    final origem = LojaOrigemMercadoria.origemEfetiva(
      origemItem: item.lojaOrigemMercadoria,
      origemVenda: venda.lojaOrigemMercadoria,
      cargaSaiu: venda.cargaSaiu,
    );
    final qBuscar = item.quantidadeBuscarNaLoja;
    final recorteConfirmado = qBuscar > 0 &&
        (BuscarNaLoja.ehSeparado(item.buscarNaLojaStatus) ||
            LojaOrigemMercadoria.ehMisto(origem));
    if (recorteConfirmado) {
      final emEstoque = ProdutoEmbalagem.unidadeEstoqueDeQuantidadeArmazenada(
        produto: item.produto.target,
        quantidadeArmazenada: qBuscar,
      );
      if (emEstoque < 0) return 0;
      return emEstoque > qTotal ? qTotal : emEstoque;
    }
    return LojaOrigemMercadoria.ehLocal(origem) ? qTotal : 0;
  }

  void validarEstoqueAntesDespachoCarreto(
    Venda venda, {
    bool permitirVendaSemEstoque = true,
  }) {
    if (!venda.carretoReservaAteSaida) return;
    final porProduto = <int, ({int q, String nome})>{};
    for (final item in venda.itens) {
      final q = quantidadeItemParaEstoqueCarreto(item);
      if (q <= 0) continue;
      final produto = item.produto.target;
      final pid = produto?.id ?? item.produto.targetId;
      if (pid <= 0) {
        throw StateError(
          'Item "${item.nomeProduto}" sem produto vinculado — '
          'nao e possivel despachar.',
        );
      }
      final nome = produto?.nome ?? item.nomeProduto;
      final atual = porProduto[pid];
      porProduto[pid] = (
        q: (atual?.q ?? 0) + q,
        nome: nome,
      );
    }
    if (porProduto.isEmpty) return;

    final fisicoPorProduto = <int, int>{};
    for (final item in venda.itens) {
      final qFisico = quantidadeFisicaDestaLojaCarreto(venda, item);
      if (qFisico <= 0) continue;
      final pid = item.produto.target?.id ?? item.produto.targetId;
      if (pid <= 0) continue;
      fisicoPorProduto[pid] = (fisicoPorProduto[pid] ?? 0) + qFisico;
    }

    final falhas = <String>[];
    for (final e in porProduto.entries) {
      final produto = _db.produtoBox.get(e.key);
      if (produto == null) {
        falhas.add('Produto id ${e.key} nao encontrado.');
        continue;
      }
      final q = e.value.q;
      if (produto.estoqueReservado < q) {
        falhas.add(
          '${e.value.nome}: reservado ${produto.estoqueReservado}, '
          'necessario $q para o romaneio.',
        );
      }
      final qFisico = fisicoPorProduto[e.key] ?? 0;
      if (qFisico > 0 &&
          !permitirVendaSemEstoque &&
          produto.estoqueReal < qFisico) {
        falhas.add(
          '${e.value.nome}: fisico ${produto.estoqueReal}, '
          'necessario $qFisico para saida do carro.',
        );
      }
    }
    if (falhas.isNotEmpty) {
      throw StateError(
        'Nao foi possivel marcar "Saiu": estoque insuficiente.\n'
        '${falhas.join('\n')}',
      );
    }
  }

  void baixarEstoqueCarretoAoMarcarSaida(
    Venda venda, {
    bool permitirVendaSemEstoque = true,
  }) {
    final falhas = <String>[];
    for (final item in venda.itens) {
      final q = quantidadeItemParaEstoqueCarreto(item);
      if (q <= 0) continue;
      final qFisico = quantidadeFisicaDestaLojaCarreto(venda, item);
      final origemKardex = qFisico <= 0
          ? LojaOrigemMercadoria.outraLoja
          : (qFisico < q
              ? LojaOrigemMercadoria.misto
              : LojaOrigemMercadoria.local);
      final motivo = LojaOrigemMercadoria.motivoKardex(
        origem: origemKardex,
        vendaId: venda.id,
        numeroOrcamento: venda.numeroOrcamento,
      );

      final Produto produto;
      try {
        produto = _produtoAtualDoItem(item);
      } catch (e) {
        falhas.add('$e');
        continue;
      }
      if (produto.estoqueReservado < q) {
        falhas.add(
          '${produto.nome}: reservado ${produto.estoqueReservado}, '
          'necessario $q para saida do carro.',
        );
        continue;
      }
      if (qFisico > 0 &&
          !permitirVendaSemEstoque &&
          produto.estoqueReal < qFisico) {
        falhas.add(
          '${produto.nome}: fisico ${produto.estoqueReal}, '
          'necessario $qFisico para saida do carro.',
        );
        continue;
      }

      final antes = _snap(produto);
      if (qFisico > 0 && produto.controlaLoteValidade) {
        final consumos =
            _fefo.consumirFefo(produto: produto, quantidade: qFisico);
        final existentes =
            LoteConsumoSnapshot.decodeList(item.loteConsumosJson);
        item.loteConsumosJson = LoteConsumoSnapshot.encodeList([
          ...existentes,
          ...consumos,
        ]);
        _db.itemVendaBox.put(item);
      }
      final r = produto.estoqueReservado;
      produto.estoqueReservado = (r - q).clamp(0, r).toInt();
      if (qFisico > 0) {
        produto.estoqueReal -= qFisico;
      }
      persistirProduto(
        produto,
        TipoMovimentoEstoque.carretoSaida,
        antes: antes,
        documentoReferencia: _refVenda(venda),
        motivo: motivo,
      );
    }
    if (falhas.isNotEmpty) {
      throw StateError(
        'Nao foi possivel baixar estoque do carreto ao marcar "Saiu".\n'
        '${falhas.join('\n')}',
      );
    }
  }

  /// Depois da saida (reserva ja liberada), baixa so o fisico dos itens
  /// que passaram a sair desta loja.
  void baixarFisicoCarretoAposSaiuOrigemLocal(
    Venda venda, {
    required Iterable<ItemVenda> itens,
    bool permitirVendaSemEstoque = true,
  }) {
    final falhas = <String>[];
    for (final item in itens) {
      final q = quantidadeFisicaDestaLojaCarreto(venda, item);
      if (q <= 0) continue;
      final Produto produto;
      try {
        produto = _produtoAtualDoItem(item);
      } catch (e) {
        falhas.add('$e');
        continue;
      }
      if (!permitirVendaSemEstoque && produto.estoqueReal < q) {
        falhas.add(
          '${produto.nome}: fisico ${produto.estoqueReal}, '
          'necessario $q para buscar nesta loja.',
        );
        continue;
      }
      final antes = _snap(produto);
      if (produto.controlaLoteValidade) {
        final consumos = _fefo.consumirFefo(produto: produto, quantidade: q);
        final existentes =
            LoteConsumoSnapshot.decodeList(item.loteConsumosJson);
        item.loteConsumosJson = LoteConsumoSnapshot.encodeList([
          ...existentes,
          ...consumos,
        ]);
        _db.itemVendaBox.put(item);
      }
      produto.estoqueReal -= q;
      persistirProduto(
        produto,
        TipoMovimentoEstoque.carretoSaida,
        antes: antes,
        documentoReferencia: _refVenda(venda),
        motivo: LojaOrigemMercadoria.motivoKardex(
          origem: LojaOrigemMercadoria.local,
          vendaId: venda.id,
          numeroOrcamento: venda.numeroOrcamento,
        ),
      );
    }
    if (falhas.isNotEmpty) {
      throw StateError(
        'Nao foi possivel baixar o fisico ao buscar nesta loja.\n'
        '${falhas.join('\n')}',
      );
    }
  }

  /// Motorista desiste apos o patio ter separado: devolve so o fisico desta loja.
  void estornarFisicoCarretoBuscarNaLoja(
    Venda venda, {
    required Iterable<ItemVenda> itens,
  }) {
    for (final item in itens) {
      final q = quantidadeFisicaDestaLojaCarreto(venda, item);
      if (q <= 0) continue;
      final produto = _produtoAtualDoItem(item);
      final antes = _snap(produto);
      if (produto.controlaLoteValidade) {
        _fefo.devolverConsumos(
          produto,
          LoteConsumoSnapshot.decodeList(item.loteConsumosJson),
        );
        item.loteConsumosJson = '';
        _db.itemVendaBox.put(item);
      }
      produto.estoqueReal += q;
      persistirProduto(
        produto,
        TipoMovimentoEstoque.carretoEstornoSaida,
        antes: antes,
        documentoReferencia: _refVenda(venda),
        motivo: LojaOrigemMercadoria.motivoKardex(
          origem: LojaOrigemMercadoria.local,
          vendaId: venda.id,
          numeroOrcamento: venda.numeroOrcamento,
        ),
      );
    }
  }

  void estornarBaixaEstoqueCarretoAoDesmarcarSaida(
    Venda venda, {
    required String complementoEntregaJson,
  }) {
    for (final item in venda.itens) {
      var q = quantidadeItemParaEstoqueCarreto(item);
      var qFisico = quantidadeFisicaDestaLojaCarreto(venda, item);
      if (q <= 0 && qFisico <= 0) continue;
      if (venda.statusEntrega == 'entregue_complemento_pendente' &&
          complementoEntregaJson.trim().isNotEmpty) {
        final m = _quantidadeComplementoDeclaradaPorItem(
          complementoEntregaJson,
          item.id,
        );
        q -= m;
        qFisico -= m;
        if (q < 0) q = 0;
        if (qFisico < 0) qFisico = 0;
      }
      if (q <= 0 && qFisico <= 0) continue;
      final produto = _produtoAtualDoItem(item);
      final antes = _snap(produto);
      if (qFisico > 0) {
        produto.estoqueReal += qFisico;
      }
      if (q > 0) {
        produto.estoqueReservado += q;
      }
      final origemKardex = qFisico <= 0
          ? LojaOrigemMercadoria.outraLoja
          : (qFisico < q
              ? LojaOrigemMercadoria.misto
              : LojaOrigemMercadoria.local);
      persistirProduto(
        produto,
        TipoMovimentoEstoque.carretoEstornoSaida,
        antes: antes,
        documentoReferencia: _refVenda(venda),
        motivo: LojaOrigemMercadoria.motivoKardex(
          origem: origemKardex,
          vendaId: venda.id,
          numeroOrcamento: venda.numeroOrcamento,
        ),
      );
    }
  }

  int _quantidadeComplementoDeclaradaPorItem(String json, int itemVendaId) {
    var s = 0;
    for (final l in ComplementoEntregaCodec.decode(json)) {
      if (l.itemVendaId == itemVendaId) s += l.quantidade;
    }
    return s;
  }

  bool _vendaCarretoReservaComSaidaParaEstoqueComplemento(Venda v) {
    return EntregaVendaHelper.vendaTemItensCarreto(v) &&
        v.carretoReservaAteSaida &&
        v.cargaSaiu &&
        v.status == 'finalizada' &&
        !v.cancelada;
  }

  void creditarEstoqueComplementoFaltaNaIda(
    Venda venda,
    List<LinhaComplementoEntrega> linhas,
  ) {
    if (!_vendaCarretoReservaComSaidaParaEstoqueComplemento(venda)) return;
    final porItem = <int, int>{};
    for (final l in linhas) {
      if (l.itemVendaId <= 0 || l.quantidade <= 0) continue;
      porItem[l.itemVendaId] = (porItem[l.itemVendaId] ?? 0) + l.quantidade;
    }
    if (porItem.isEmpty) {
      throw StateError('Complemento sem linhas validas para estoque.');
    }
    for (final e in porItem.entries) {
      final item = _db.itemVendaBox.get(e.key);
      if (item == null || item.venda.targetId != venda.id) {
        throw StateError('Item de venda ${e.key} invalido no complemento.');
      }
      final maxQ = quantidadeItemParaEstoqueCarreto(item);
      if (e.value > maxQ) {
        throw StateError(
          'Falta declarada (${e.value}) de "${item.nomeProduto}" excede o '
          'entregavel da linha ($maxQ).',
        );
      }
      final produto = _produtoAtualDoItem(item);
      final antes = _snap(produto);
      produto.estoqueReservado += e.value;
      produto.estoqueReal += e.value;
      persistirProduto(
        produto,
        TipoMovimentoEstoque.complementoEntregaFalta,
        antes: antes,
        documentoReferencia: _refVenda(venda),
      );
    }
  }

  void baixarEstoqueComplementoEntregaAoConcluir(
    Venda venda,
    List<LinhaComplementoEntrega> linhas,
  ) {
    if (!_vendaCarretoReservaComSaidaParaEstoqueComplemento(venda)) return;
    final porItem = <int, int>{};
    for (final l in linhas) {
      if (l.itemVendaId <= 0 || l.quantidade <= 0) continue;
      porItem[l.itemVendaId] = (porItem[l.itemVendaId] ?? 0) + l.quantidade;
    }
    if (porItem.isEmpty) return;
    for (final e in porItem.entries) {
      final item = _db.itemVendaBox.get(e.key);
      if (item == null || item.venda.targetId != venda.id) {
        throw StateError('Item de venda ${e.key} invalido no complemento.');
      }
      final maxQ = quantidadeItemParaEstoqueCarreto(item);
      if (e.value > maxQ) {
        throw StateError(
          'Quantidade do complemento (${e.value}) de "${item.nomeProduto}" '
          'excede o entregavel da linha ($maxQ).',
        );
      }
      final produto = _produtoAtualDoItem(item);
      if (produto.estoqueReservado < e.value) {
        throw StateError(
          'Reservado insuficiente para ${produto.nome} ao concluir complemento '
          '(reservado ${produto.estoqueReservado}, precisa ${e.value}).',
        );
      }
      if (produto.estoqueReal < e.value) {
        throw StateError(
          'Estoque fisico insuficiente para ${produto.nome} ao concluir complemento '
          '(real ${produto.estoqueReal}, precisa ${e.value}).',
        );
      }
      final antes = _snap(produto);
      final r = produto.estoqueReservado;
      produto.estoqueReservado = (r - e.value).clamp(0, r).toInt();
      produto.estoqueReal -= e.value;
      persistirProduto(
        produto,
        TipoMovimentoEstoque.complementoEntregaBaixa,
        antes: antes,
        documentoReferencia: _refVenda(venda),
      );
    }
  }

  // --- Retirada futura / loja pre-saida ---

  void recomporEstoqueAoMarcarEntregaPendente(Venda venda) {
    for (final item in venda.itens) {
      // So recompoe linhas que ja baixaram fisico (leva agora). Itens que ja
      // eram futura/carreto ja tem reserva — somar de novo infla o reservado.
      if (EntregaVendaHelper.tipoEfetivoItem(item) !=
          EntregaVendaHelper.tipoRetirada) {
        continue;
      }
      final produto = _produtoAtualDoItem(item);
      final antes = _snap(produto);
      final qEstoque = item.quantidadeUnidadeEstoque;
      if (qEstoque <= 0) continue;
      produto.estoqueReal += qEstoque;
      produto.estoqueReservado += qEstoque;
      item.tipoEntregaItem = EntregaVendaHelper.tipoRetiradaFutura;
      item.quantidadeJaRetirada = 0;
      _db.itemVendaBox.put(item);
      persistirProduto(
        produto,
        TipoMovimentoEstoque.retiradaTotalImediata,
        antes: antes,
        documentoReferencia: _refVenda(venda),
      );
    }
  }

  void baixarReservaEFisicoRetirada({
    required ItemVenda item,
    required int quantidade,
    required TipoMovimentoEstoque tipo,
    required bool permitirSemConferenciaEstoque,
  }) {
    if (quantidade <= 0) return;
    final produto = _produtoAtualDoItem(item);
    _garantirEscalaEstoque(produto);
    final qEstoque = item.quantidadeUnidadeEstoqueDe(quantidade);
    if (qEstoque <= 0) return;
    if (!permitirSemConferenciaEstoque) {
      if (produto.estoqueReal < qEstoque) {
        throw StateError(
          'Estoque fisico insuficiente para retirar $qEstoque de ${produto.nome}.',
        );
      }
      if (produto.estoqueReservado < qEstoque) {
        throw StateError(
          'Estoque reservado inconsistente para ${produto.nome} '
          '(reservado ${produto.estoqueReservado}, precisa $qEstoque).',
        );
      }
    }
    PoliticaMovimentoEstoque.validarPermiteAlteracaoFisica(tipo);
    final antes = _snap(produto);
    if (produto.controlaLoteValidade) {
      final consumos = _fefo.consumirFefo(
        produto: produto,
        quantidade: qEstoque,
      );
      final existentes = LoteConsumoSnapshot.decodeList(item.loteConsumosJson);
      item.loteConsumosJson = LoteConsumoSnapshot.encodeList([
        ...existentes,
        ...consumos,
      ]);
      _db.itemVendaBox.put(item);
    }
    produto.estoqueReal -= qEstoque;
    final reservado = produto.estoqueReservado;
    if (reservado < 0) {
      produto.estoqueReservado = 0;
    } else {
      produto.estoqueReservado =
          (reservado - qEstoque).clamp(0, reservado).toInt();
    }
    persistirProduto(
      produto,
      tipo,
      antes: antes,
      documentoReferencia: _refItemVenda(item),
      motivo: 'Retirada de venda futura ${_refItemVenda(item)}',
    );
  }

  // --- Cancelamento ---

  void estornarEstoqueAoCancelarVenda(Venda venda) {
    for (final item in venda.itens) {
      if (item.produto.targetId <= 0 && item.produto.target == null) continue;
      final produto = _produtoAtualDoItem(item);

      final antes = _snap(produto);
      var alterou = false;
      final tipo = EntregaVendaHelper.tipoEfetivoItem(item);

      if (tipo == EntregaVendaHelper.tipoRetiradaFutura) {
        // So o pendente ainda esta no reservado; o ja retirado ja baixou fisico+reserva.
        final qEstorno =
            item.quantidadeUnidadeEstoqueDe(item.quantidadePendenteRetirada);
        if (qEstorno > 0) {
          final r = produto.estoqueReservado;
          final teto = r < 0 ? 0 : r;
          final novo = (r - qEstorno).clamp(0, teto).toInt();
          if (novo != produto.estoqueReservado) {
            produto.estoqueReservado = novo;
            alterou = true;
          }
        }
      } else if (tipo == EntregaVendaHelper.tipoEntregaLoja &&
          venda.carretoReservaAteSaida) {
        if (venda.cargaSaiu) {
          final qFisico = quantidadeFisicaDestaLojaCarreto(venda, item);
          if (qFisico > 0) {
            produto.estoqueReal += qFisico;
            if (produto.controlaLoteValidade) {
              _fefo.devolverConsumos(
                produto,
                LoteConsumoSnapshot.decodeList(item.loteConsumosJson),
              );
            }
            alterou = true;
          }
        } else {
          final qReserva = quantidadeItemParaEstoqueCarreto(item);
          final r = produto.estoqueReservado;
          final teto = r < 0 ? 0 : r;
          final novo = (r - qReserva).clamp(0, teto).toInt();
          if (novo != produto.estoqueReservado) {
            produto.estoqueReservado = novo;
            alterou = true;
          }
        }
      } else if (tipo == EntregaVendaHelper.tipoRetirada &&
          (venda.estoqueBaixadoCupom || item.quantidadeJaRetirada > 0)) {
        // Leva agora: devolve fisico. Nunca desconta reservado (misto).
        final q = item.quantidadeUnidadeEstoque;
        if (q > 0) {
          produto.estoqueReal += q;
          if (produto.controlaLoteValidade) {
            _fefo.devolverConsumos(
              produto,
              LoteConsumoSnapshot.decodeList(item.loteConsumosJson),
            );
          }
          alterou = true;
        }
      } else if (venda.estoqueBaixadoCupom ||
          tipo != EntregaVendaHelper.tipoRetirada) {
        produto.estoqueReal += item.quantidadeUnidadeEstoque;
        if (produto.controlaLoteValidade) {
          _fefo.devolverConsumos(
            produto,
            LoteConsumoSnapshot.decodeList(item.loteConsumosJson),
          );
        }
        alterou = true;
      }
      if (alterou) {
        persistirProduto(
          produto,
          TipoMovimentoEstoque.cancelamentoVendaEstorno,
          antes: antes,
          documentoReferencia: _refVenda(venda),
        );
      }
    }
  }

  // --- Devolucao / troca ---

  void aplicarEntradaDevolucao({
    required Venda venda,
    required ItemVenda item,
    required Produto produto,
    required int qtd,
  }) {
    if (qtd <= 0) return;
    final antes = _snap(produto);
    if (venda.entregaPendente) {
      final daReserva = qtd <= item.quantidadePendenteRetirada
          ? qtd
          : item.quantidadePendenteRetirada;
      final daCliente = qtd - daReserva;
      if (daReserva > 0) {
        final r = produto.estoqueReservado;
        final teto = r < 0 ? 0 : r;
        produto.estoqueReservado = (r - daReserva).clamp(0, teto).toInt();
      }
      if (daCliente > 0) {
        produto.estoqueReal += daCliente;
      }
    } else if (EntregaVendaHelper.vendaTemItensCarreto(venda) &&
        venda.carretoReservaAteSaida &&
        !venda.cargaSaiu) {
      final r = produto.estoqueReservado;
      final teto = r < 0 ? 0 : r;
      produto.estoqueReservado = (r - qtd).clamp(0, teto).toInt();
    } else {
      produto.estoqueReal += qtd;
    }
    persistirProduto(
      produto,
      TipoMovimentoEstoque.devolucaoCliente,
      antes: antes,
      documentoReferencia: _refVenda(venda),
    );
  }

  void baixarEstoqueSaidaTroca({
    required Produto produto,
    required int quantidade,
    required bool permitirVendaSemEstoque,
  }) {
    if (quantidade <= 0) return;
    PoliticaMovimentoEstoque.validarPermiteAlteracaoFisica(
      TipoMovimentoEstoque.devolucaoCliente,
    );
    final antes = _snap(produto);
    produto.estoqueReal -= quantidade;
    persistirProduto(
      produto,
      TipoMovimentoEstoque.devolucaoCliente,
      antes: antes,
      documentoReferencia: 'Troca produto ${produto.id}',
    );
  }

  /// Baixa fisica apos NF-e de devolucao de compra autorizada (loja → fabrica).
  void baixarEstoqueDevolucaoFornecedor({
    required Produto produto,
    required int quantidade,
    required String chaveNotaCompra,
    required String referenciaNfe,
  }) {
    if (quantidade <= 0) return;
    PoliticaMovimentoEstoque.validarPermiteAlteracaoFisica(
      TipoMovimentoEstoque.devolucaoFornecedor,
    );
    final antes = _snap(produto);
    produto.estoqueReal -= quantidade;
    final chave = chaveNotaCompra.replaceAll(RegExp(r'\D'), '');
    persistirProduto(
      produto,
      TipoMovimentoEstoque.devolucaoFornecedor,
      antes: antes,
      documentoReferencia: 'Dev. forn. $chave · $referenciaNfe',
    );
  }

  String _refVenda(Venda venda) =>
      VendaDocumentoRotuloHelper.rotuloControleInterno(venda);

  String _refItemVenda(ItemVenda item) {
    final venda = item.venda.target;
    if (venda != null) return _refVenda(venda);
    if (item.venda.targetId > 0) return 'Venda id ${item.venda.targetId}';
    return 'Item ${item.id}';
  }
}
