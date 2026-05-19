import '../domain/complemento_entrega_codec.dart';
import '../domain/entrega_venda_helper.dart';
import '../domain/pagamento_orcamento.dart';
import '../services/compras_preditivas_service.dart';
import '../model/item_venda.dart';
import '../model/historico_entrega.dart';
import '../model/linha_devolucao_entrada.dart';
import '../model/linha_troca_saida.dart';
import '../model/produto.dart';
import '../model/registro_devolucao.dart';
import '../model/venda.dart';
import '../objectbox.g.dart';
import 'objectbox.dart';
import 'sync/sync_write_trigger.dart';

void _aplicarPagamentoNoOrcamento(
  Venda venda,
  DadosPagamentoOrcamento pagamento, {
  required double totalOrcamento,
}) {
  final linhas = pagamento.linhasMisto;
  if (linhas != null && linhas.length >= 2) {
    final soma = PagamentoOrcamentoCodec.soma(linhas);
    if ((soma - totalOrcamento).abs() > 0.02) {
      throw StateError(
        'Pagamento misto: soma (${soma.toStringAsFixed(2)}) deve igualar '
        'total (${totalOrcamento.toStringAsFixed(2)}).',
      );
    }
    for (final l in linhas) {
      if (l.meio == 'cartao_debito' && l.parcelas != 1) {
        throw StateError('Cartao de debito deve ser a vista em cada linha.');
      }
    }
    venda.formaPagamento = 'misto';
    venda.pagamentosJson = PagamentoOrcamentoCodec.encode(linhas);
    var maxPar = 1;
    for (final l in linhas) {
      if (l.meio == 'cartao_credito' && l.parcelas > maxPar) {
        maxPar = l.parcelas;
      }
    }
    venda.quantidadeParcelas = maxPar;
    return;
  }
  final parcelas = pagamento.formaPagamento == 'cartao_credito'
      ? pagamento.quantidadeParcelas
      : 1;
  venda.formaPagamento = pagamento.formaPagamento;
  venda.quantidadeParcelas = parcelas;
  venda.pagamentosJson = '';
}

class PeriodoFiltro {
  PeriodoFiltro({required this.inicio, required this.fim});

  final DateTime inicio;
  final DateTime fim;
}

/// Linha de saida do produto em vendas finalizadas (relatorio por periodo).
class SaidaProdutoRelatorioLinha {
  const SaidaProdutoRelatorioLinha({
    required this.dataVenda,
    required this.quantidade,
    required this.valorUnitario,
    required this.total,
    required this.nota,
    required this.lucro,
    required this.acrescimo,
    required this.clienteNome,
    required this.vendaId,
    required this.itemVendaId,
  });

  final DateTime dataVenda;
  final int quantidade;
  final double valorUnitario;
  final double total;
  final int nota;
  final double lucro;
  final double acrescimo;
  final String clienteNome;
  final int vendaId;
  final int itemVendaId;
}

class ItemVendaInput {
  ItemVendaInput({
    required this.produtoId,
    required this.quantidade,
    required this.precoUnitario,
    this.precoTipo = 'preco1',
    this.tipoEntregaItem = EntregaVendaHelper.tipoRetirada,
  });

  final int produtoId;
  final int quantidade;
  final double precoUnitario;
  final String precoTipo;
  final String tipoEntregaItem;
}

ItemVenda _criarItemVendaFromInput(
  ItemVendaInput input,
  Produto produto,
) {
  return ItemVenda(
    nomeProduto: produto.nome,
    quantidade: input.quantidade,
    precoTipo: input.precoTipo,
    precoUnitario: input.precoUnitario,
    precoCustoUnitario: produto.precoCusto,
    tipoEntregaItem: EntregaVendaHelper.normalizarTipoItem(input.tipoEntregaItem),
  );
}

void _aplicarDadosEntregaOrcamentoNaVenda(
  Venda venda,
  DadosEntregaOrcamento entrega,
  List<ItemVendaInput> itensInput,
) {
  final tipos = itensInput.map((i) => i.tipoEntregaItem);
  final temCarreto = EntregaVendaHelper.iterableTemCarreto(tipos);
  final temFutura = EntregaVendaHelper.iterableTemRetiradaFutura(tipos);
  venda.tipoEntrega = EntregaVendaHelper.resolverTipoEntregaVenda(tipos);
  venda.entregaPendente = temFutura;
  venda.valorFrete = temCarreto ? entrega.valorFrete : 0;
  venda.enderecoEntrega = temCarreto ? entrega.enderecoEntrega : '';
  venda.observacaoEntrega = temCarreto ? entrega.observacaoEntrega : '';
  venda.statusEntrega = temCarreto ? 'pendente' : 'nao_aplicavel';
  venda.prioridadeEntrega = temCarreto ? entrega.prioridadeEntrega : 'normal';
  venda.janelaEntrega = temCarreto ? entrega.janelaEntrega : 'nao_definida';
  venda.dataEntregaMarcada = temCarreto ? entrega.dataEntregaMarcada : null;
}

void _baixarEstoqueItemAoFinalizarOrcamento({
  required ObjectBox db,
  required ItemVenda item,
  required bool permitirVendaSemEstoque,
  Map<int, int>? consumoVendasPrecalculado,
}) {
  final produto = item.produto.target;
  if (produto == null) {
    throw StateError('Produto do item "${item.nomeProduto}" nao encontrado.');
  }
  final q = item.quantidade;
  if (q <= 0) return;

  final tipo = EntregaVendaHelper.tipoEfetivoItem(item);
  if (!permitirVendaSemEstoque && produto.estoqueLivreParaVenda < q) {
    throw StateError('Estoque insuficiente para ${produto.nome}.');
  }

  switch (tipo) {
    case EntregaVendaHelper.tipoRetirada:
      produto.estoqueReal -= q;
      ComprasPreditivasService(db).atualizarAposVendaRegistrada(
        produto: produto,
        quantidadeVendida: q,
        estoqueRealJaAbatido: true,
        consumoPrecalculado: consumoVendasPrecalculado,
      );
      break;
    case EntregaVendaHelper.tipoRetiradaFutura:
      produto.estoqueReservado += q;
      db.produtoBox.put(produto);
      break;
    case EntregaVendaHelper.tipoEntregaLoja:
      produto.estoqueReservado += q;
      item.quantidadeNoCarreto = q;
      db.produtoBox.put(produto);
      db.itemVendaBox.put(item);
      break;
  }
}

class LinhaDevolucaoEntradaInput {
  const LinhaDevolucaoEntradaInput({
    required this.itemVendaId,
    required this.quantidade,
  });

  final int itemVendaId;
  final int quantidade;
}

class LinhaTrocaSaidaInput {
  const LinhaTrocaSaidaInput({
    required this.produtoId,
    required this.quantidade,
    required this.precoUnitario,
    this.precoTipo = 'preco1',
    required this.precoCustoUnitario,
  });

  final int produtoId;
  final int quantidade;
  final double precoUnitario;
  final String precoTipo;
  final double precoCustoUnitario;
}

/// Impacto financeiro das devolucoes/trocas cuja **data do registro** cai no periodo.
class ImpactosDevolucaoTrocaPeriodo {
  const ImpactosDevolucaoTrocaPeriodo({
    required this.impactoFaturamentoTotal,
    required this.impactoLucroTotal,
    required this.porVendedorFaturamento,
    required this.porVendedorLucro,
    required this.porClienteFaturamento,
  });

  /// Negativo em devolucao pura; troca pode ser misto (saida - entrada).
  final double impactoFaturamentoTotal;

  /// Aproxima lucro: entrada usa custo do item da venda; saida troca usa custo da linha.
  final double impactoLucroTotal;

  final Map<int, double> porVendedorFaturamento;
  final Map<int, double> porVendedorLucro;
  final Map<int, double> porClienteFaturamento;
}

/// Deltas para ranking de produtos (entrada devolucao negativa; saida troca positiva).
class DeltaProdutoDevolucao {
  const DeltaProdutoDevolucao({
    required this.chaveAgg,
    required this.nomeExibicao,
    required this.produtoId,
    required this.deltaQuantidade,
    required this.deltaValor,
  });

  final String chaveAgg;
  final String nomeExibicao;
  final int produtoId;
  final int deltaQuantidade;
  final double deltaValor;
}

class DadosPagamentoOrcamento {
  DadosPagamentoOrcamento({
    required this.formaPagamento,
    required this.quantidadeParcelas,
    this.linhasMisto,
  });

  final String formaPagamento;
  final int quantidadeParcelas;

  /// Quando preenchido (2+ linhas ou modo misto), [formaPagamento] deve ser `misto`.
  final List<PagamentoOrcamentoLinha>? linhasMisto;
}

class DadosEntregaOrcamento {
  DadosEntregaOrcamento({
    required this.tipoEntrega,
    required this.valorFrete,
    this.enderecoEntrega = '',
    this.observacaoEntrega = '',
    this.prioridadeEntrega = 'normal',
    this.janelaEntrega = 'nao_definida',
    this.dataEntregaMarcada,
  });

  final String tipoEntrega; // retirada | retirada_futura | entrega_loja
  final double valorFrete;
  final String enderecoEntrega;
  final String observacaoEntrega;
  final String prioridadeEntrega; // normal | urgente | agendada
  final String janelaEntrega; // manha | tarde | nao_definida
  final DateTime? dataEntregaMarcada;
}

/// Filtros da [ListagemVendasPage]: condicoes aplicadas no ObjectBox (sem `getAll`).
class FiltroListagemVendas {
  const FiltroListagemVendas({
    required this.textoBusca,
    this.dataInicioUtc,
    this.dataFimUtc,
    required this.filtroCancelamento,
    required this.canceladaPorFiltro,
    required this.formaPagamento,
    required this.tipoEntrega,
    required this.entregaPendente,
    this.clienteId,
    this.vendedorId,
  });

  final String textoBusca;
  final DateTime? dataInicioUtc;
  final DateTime? dataFimUtc;

  /// `ativas` | `canceladas` | `todas`
  final String filtroCancelamento;

  /// `todos` ou valor exato (como no dropdown de cancelamentos).
  final String canceladaPorFiltro;
  final String formaPagamento;
  final String tipoEntrega;

  /// `todos` | `sim` | `nao`
  final String entregaPendente;
  final int? clienteId;
  final int? vendedorId;
}

/// Pagina da listagem de vendas + total de linhas que obedecem ao [FiltroListagemVendas].
class ListagemVendasPagina {
  const ListagemVendasPagina({required this.vendas, required this.total});

  final List<Venda> vendas;
  final int total;
}

class VendaRepository {
  VendaRepository(this._db, {void Function()? onAposEscrita})
    : _onAposEscrita = onAposEscrita;

  final ObjectBox _db;
  final void Function()? _onAposEscrita;
  void _processarComprasPreditivasAposBaixaEstoque(
    Produto produto,
    int quantidadeVendida, {
    Map<int, int>? consumoVendasPrecalculado,
  }) {
    ComprasPreditivasService(_db).atualizarAposVendaRegistrada(
      produto: produto,
      quantidadeVendida: quantidadeVendida,
      estoqueRealJaAbatido: true,
      consumoPrecalculado: consumoVendasPrecalculado,
    );
  }

  void _notificarRedeAposEscrita() {
    _onAposEscrita?.call();
    notificarAlteracaoParaRede();
  }

  List<Venda> listarTodas() {
    final query = _db.vendaBox
        .query()
        .order(Venda_.data, flags: Order.descending)
        .build();
    final vendas = query.find();
    query.close();
    return vendas;
  }

  Query<Venda> _queryListagemVendasOrdenada(Condition<Venda> cond, FiltroListagemVendas f) {
    final qb = _db.vendaBox.query(cond);
    if (f.filtroCancelamento == 'canceladas') {
      qb.order(Venda_.canceladaEm, flags: Order.descending);
    } else {
      qb.order(Venda_.data, flags: Order.descending);
    }
    return qb.build();
  }

  Condition<Venda> _condicaoListagemVendas(FiltroListagemVendas f) {
    Condition<Venda> c = Venda_.status.equals('finalizada');
    switch (f.filtroCancelamento) {
      case 'ativas':
        c = c & Venda_.cancelada.equals(false);
        break;
      case 'canceladas':
        c = c & Venda_.cancelada.equals(true);
        break;
      default:
        break;
    }
    if (f.canceladaPorFiltro != 'todos') {
      final u = f.canceladaPorFiltro.trim();
      if (u.isNotEmpty) {
        c = c & Venda_.canceladaPor.equals(u, caseSensitive: false);
      }
    }
    if (f.dataInicioUtc != null) {
      c = c & Venda_.data.greaterOrEqualDate(f.dataInicioUtc!);
    }
    if (f.dataFimUtc != null) {
      c = c & Venda_.data.lessOrEqualDate(f.dataFimUtc!);
    }
    if (f.formaPagamento != 'todos') {
      c = c & Venda_.formaPagamento.equals(f.formaPagamento);
    }
    if (f.tipoEntrega != 'todos') {
      if (f.tipoEntrega == EntregaVendaHelper.tipoEntregaLoja) {
        final condCarreto = Venda_.tipoEntrega.equals(
              EntregaVendaHelper.tipoEntregaLoja,
            ) |
            Venda_.tipoEntrega.equals(EntregaVendaHelper.tipoMisto);
        c = c & condCarreto;
      } else {
        c = c & Venda_.tipoEntrega.equals(f.tipoEntrega);
      }
    }
    if (f.entregaPendente == 'sim') {
      c = c & Venda_.entregaPendente.equals(true);
    } else if (f.entregaPendente == 'nao') {
      c = c & Venda_.entregaPendente.equals(false);
    }
    if (f.clienteId != null) {
      c = c & Venda_.cliente.equals(f.clienteId!);
    }
    if (f.vendedorId != null) {
      c = c & Venda_.vendedor.equals(f.vendedorId!);
    }

    final tb = f.textoBusca.trim();
    if (tb.isEmpty) {
      return c;
    }
    final lower = tb.toLowerCase();
    final orPartes = <Condition<Venda>>[];
    final asInt = int.tryParse(tb.replaceAll(RegExp(r'[^0-9]'), ''));
    if (asInt != null) {
      orPartes.add(Venda_.id.equals(asInt));
      orPartes.add(Venda_.numeroOrcamento.equals(asInt));
    }

    final qc = _db.clienteBox
        .query(
          Cliente_.nomeRazao
              .contains(lower, caseSensitive: false)
              .or(Cliente_.nomeFantasia.contains(lower, caseSensitive: false)),
        )
        .build();
    try {
      final idsCliente = qc.find().map((e) => e.id).toList();
      if (idsCliente.isNotEmpty) {
        orPartes.add(Venda_.cliente.oneOf(idsCliente));
      }
    } finally {
      qc.close();
    }

    final qv = _db.vendedorBox
        .query(
          Vendedor_.codigoInterno
              .contains(lower, caseSensitive: false)
              .or(Vendedor_.nomeCompleto.contains(lower, caseSensitive: false))
              .or(Vendedor_.apelido.contains(lower, caseSensitive: false)),
        )
        .build();
    try {
      final idsVendedor = qv.find().map((e) => e.id).toList();
      if (idsVendedor.isNotEmpty) {
        orPartes.add(Venda_.vendedor.oneOf(idsVendedor));
      }
    } finally {
      qv.close();
    }

    final qi = _db.itemVendaBox
        .query(
          ItemVenda_.nomeProduto.contains(lower, caseSensitive: false),
        )
        .build();
    try {
      final idsVenda = <int>{};
      for (final it in qi.find()) {
        final vid = it.venda.targetId;
        if (vid != 0) {
          idsVenda.add(vid);
        }
      }
      if (idsVenda.isNotEmpty) {
        orPartes.add(Venda_.id.oneOf(idsVenda.toList()));
      }
    } finally {
      qi.close();
    }

    final Condition<Venda> textoCond;
    if (orPartes.isEmpty) {
      textoCond = Venda_.id.equals(0);
    } else if (orPartes.length == 1) {
      textoCond = orPartes.first;
    } else {
      textoCond = orPartes.reduce((a, b) => a | b);
    }
    return c & textoCond;
  }

  /// Total de vendas finalizadas que obedecem ao filtro (sem paginacao).
  int contarListagemVendas(FiltroListagemVendas f) {
    final cond = _condicaoListagemVendas(f);
    final query = _db.vendaBox.query(cond).build();
    try {
      return query.count();
    } finally {
      query.close();
    }
  }

  /// Uma pagina de resultados + total; [limite] tipico 20. Use [offset] 0 na primeira carga.
  ListagemVendasPagina listarListagemVendasPaginaComTotal(
    FiltroListagemVendas f, {
    required int offset,
    required int limite,
  }) {
    final cond = _condicaoListagemVendas(f);
    final qCount = _db.vendaBox.query(cond).build();
    final total = qCount.count();
    qCount.close();

    final query = _queryListagemVendasOrdenada(cond, f);
    try {
      query.offset = offset;
      query.limit = limite;
      final vendas = query.find();
      return ListagemVendasPagina(vendas: vendas, total: total);
    } finally {
      query.close();
    }
  }

  /// Todas as vendas do filtro (sem limite). Use com cuidado em exportacoes.
  List<Venda> listarListagemVendasCompleto(FiltroListagemVendas f) {
    final cond = _condicaoListagemVendas(f);
    final query = _queryListagemVendasOrdenada(cond, f);
    try {
      return query.find();
    } finally {
      query.close();
    }
  }

  /// Valores distintos de [Venda.canceladaPor] para filtros/UI, sem carregar
  /// entidades [Venda] (property query + `distinct` no ObjectBox).
  List<String> listarDistintosCanceladaPor() {
    final cond = Venda_.status
        .equals('finalizada')
        .and(Venda_.cancelada.equals(true))
        .and(Venda_.canceladaPor.notEquals('', caseSensitive: true));
    final q = _db.vendaBox.query(cond).build();
    try {
      final pq = q.property<String>(Venda_.canceladaPor);
      pq.distinct = true;
      try {
        final raw = pq.find();
        final unicos = <String>{};
        for (final s in raw) {
          final t = s.trim();
          if (t.isNotEmpty) {
            unicos.add(t);
          }
        }
        final lista = unicos.toList()
          ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
        return lista;
      } finally {
        pq.close();
      }
    } finally {
      q.close();
    }
  }

  Venda? obterPorId(int id) => _db.vendaBox.get(id);

  List<Venda> listarOrcamentosPendentes() {
    return listarTodas().where((venda) => venda.status == 'orcamento').toList();
  }

  List<Venda> listarComprasFinalizadasPorCliente(
    int clienteId, {
    DateTime? inicio,
    DateTime? fim,
  }) {
    final inicioUtc = inicio?.toUtc();
    final fimUtc = fim?.toUtc();
    return listarTodas()
        .where(
          (venda) =>
              venda.status == 'finalizada' &&
              !venda.cancelada &&
              venda.cliente.targetId == clienteId &&
              (inicioUtc == null || !venda.data.toUtc().isBefore(inicioUtc)) &&
              (fimUtc == null || !venda.data.toUtc().isAfter(fimUtc)),
        )
        .toList()
      ..sort((a, b) => b.data.compareTo(a.data));
  }

  double totalGastoCliente(int clienteId) {
    return listarComprasFinalizadasPorCliente(
      clienteId,
    ).fold<double>(0, (total, venda) => total + venda.total);
  }

  List<Venda> listarPorPeriodo(PeriodoFiltro periodo) {
    final inicioUtc = periodo.inicio.toUtc();
    final fimUtc = periodo.fim.toUtc();
    return listarTodas()
        .where(
          (venda) =>
              !venda.data.toUtc().isBefore(inicioUtc) &&
              !venda.data.toUtc().isAfter(fimUtc),
        )
        .toList();
  }

  /// Itens de venda finalizada (nao cancelada) com o [produtoId], data da venda no intervalo.
  /// Quantidade liquida = vendida menos devolvida na linha; linhas com quantidade zero sao omitidas.
  List<SaidaProdutoRelatorioLinha> listarSaidasProdutoPeriodo({
    required int produtoId,
    required DateTime inicio,
    required DateTime fim,
  }) {
    final inicioUtc = inicio.toUtc();
    final fimUtc = fim.toUtc();
    final qb = _db.itemVendaBox.query(ItemVenda_.produto.equals(produtoId));
    qb.link(
      ItemVenda_.venda,
      Venda_.status
          .equals('finalizada')
          .and(Venda_.cancelada.equals(false))
          .and(Venda_.data.greaterOrEqualDate(inicioUtc))
          .and(Venda_.data.lessOrEqualDate(fimUtc)),
    );
    final query = qb.build();
    try {
      final itens = query.find();
      final vendasPorId = <int, Venda>{};
      for (final it in itens) {
        final vid = it.venda.targetId;
        if (vid > 0) {
          vendasPorId.putIfAbsent(vid, () => _db.vendaBox.get(vid)!);
        }
      }
      final out = <SaidaProdutoRelatorioLinha>[];
      for (final item in itens) {
        final v = vendasPorId[item.venda.targetId];
        if (v == null) continue;
        final qtd = item.quantidade - item.quantidadeDevolvida;
        if (qtd <= 0) continue;
        final brutoLinha = qtd * item.precoUnitario;
        final somaIt = v.somaSubtotalItens;
        var acres = 0.0;
        if (somaIt > 0.0001) {
          acres = v.descontoImplicitoTotal * (brutoLinha / somaIt);
        }
        final cli = v.cliente.target;
        final nomeCli = (cli?.nomeRazao ?? '').trim();
        final nota = v.numeroOrcamento > 0 ? v.numeroOrcamento : v.id;
        out.add(
          SaidaProdutoRelatorioLinha(
            dataVenda: v.data.toLocal(),
            quantidade: qtd,
            valorUnitario: item.precoUnitario,
            total: brutoLinha,
            nota: nota,
            lucro: qtd * (item.precoUnitario - item.precoCustoUnitario),
            acrescimo: acres,
            clienteNome: nomeCli.isEmpty ? '-' : nomeCli,
            vendaId: v.id,
            itemVendaId: item.id,
          ),
        );
      }
      out.sort((a, b) {
        final c = a.dataVenda.compareTo(b.dataVenda);
        if (c != 0) return c;
        final d = a.vendaId.compareTo(b.vendaId);
        if (d != 0) return d;
        return a.itemVendaId.compareTo(b.itemVendaId);
      });
      return out;
    } finally {
      query.close();
    }
  }

  int registrarVenda(
    List<ItemVendaInput> itensInput, {
    bool permitirVendaSemEstoque = true,
  }) {
    if (itensInput.isEmpty) {
      throw ArgumentError('A venda deve conter ao menos um item.');
    }

    final novoId = _db.store.runInTransaction(TxMode.write, () {
      final venda = Venda(
        status: 'finalizada',
        entregaPendente: false,
        numeroOrcamento: 0,
        formaPagamento: 'dinheiro',
        quantidadeParcelas: 1,
      );
      final itens = <ItemVenda>[];
      double total = 0;
      double custoTotal = 0;
      final consumoVendas =
          ComprasPreditivasService(_db).montarConsumoPorProdutoNoPeriodo();

      for (final input in itensInput) {
        final produto = _db.produtoBox.get(input.produtoId);
        if (produto == null) {
          throw StateError('Produto ${input.produtoId} nao encontrado.');
        }
        if (input.quantidade <= 0) {
          throw StateError('Quantidade invalida para ${produto.nome}.');
        }

        if (!permitirVendaSemEstoque &&
            produto.estoqueLivreParaVenda < input.quantidade) {
          throw StateError('Estoque insuficiente para ${produto.nome}.');
        }

        produto.estoqueReal -= input.quantidade;
        _processarComprasPreditivasAposBaixaEstoque(
          produto,
          input.quantidade,
          consumoVendasPrecalculado: consumoVendas,
        );

        final item = ItemVenda(
          nomeProduto: produto.nome,
          quantidade: input.quantidade,
          precoTipo: input.precoTipo,
          precoUnitario: input.precoUnitario,
          precoCustoUnitario: produto.precoCusto,
        );
        item.produto.target = produto;
        itens.add(item);

        total += item.subtotal;
        custoTotal += item.subtotalCusto;
      }

      venda.total = total;
      venda.custoTotal = custoTotal;
      venda.lucroTotal = total - custoTotal;
      final vendaId = _db.vendaBox.put(venda);
      venda.id = vendaId;

      for (final item in itens) {
        item.venda.target = venda;
        _db.itemVendaBox.put(item);
      }

      return vendaId;
    });
    _notificarRedeAposEscrita();
    return novoId;
  }

  int registrarOrcamento(
    List<ItemVendaInput> itensInput, {
    required DadosPagamentoOrcamento pagamento,
    required DadosEntregaOrcamento entrega,
    int? clienteId,
    int? vendedorId,
    double descontoEmReais = 0,
  }) {
    if (itensInput.isEmpty) {
      throw ArgumentError('O orcamento deve conter ao menos um item.');
    }
    final novoId = _db.store.runInTransaction(TxMode.write, () {
      final proximoNumero = _proximoNumeroOrcamento();
      final venda = Venda(
        status: 'orcamento',
        numeroOrcamento: proximoNumero,
        formaPagamento: 'dinheiro',
        quantidadeParcelas: 1,
        pagamentosJson: '',
      );
      _aplicarDadosEntregaOrcamentoNaVenda(venda, entrega, itensInput);
      if (clienteId != null) {
        final cliente = _db.clienteBox.get(clienteId);
        if (cliente != null) {
          venda.cliente.target = cliente;
        }
      }
      if (vendedorId != null) {
        final vendedor = _db.vendedorBox.get(vendedorId);
        if (vendedor != null) {
          venda.vendedor.target = vendedor;
        }
      }
      final itens = <ItemVenda>[];
      double total = 0;
      double custoTotal = 0;

      for (final input in itensInput) {
        final produto = _db.produtoBox.get(input.produtoId);
        if (produto == null) {
          throw StateError('Produto ${input.produtoId} nao encontrado.');
        }
        if (input.quantidade <= 0) {
          throw StateError('Quantidade invalida para ${produto.nome}.');
        }

        final item = _criarItemVendaFromInput(input, produto);
        item.produto.target = produto;
        itens.add(item);
        total += item.subtotal;
        custoTotal += item.subtotalCusto;
      }

      if (EntregaVendaHelper.vendaTemItensCarreto(venda)) {
        if (venda.valorFrete < 0) {
          throw StateError('Valor de frete nao pode ser negativo.');
        }
        if (venda.enderecoEntrega.trim().isEmpty) {
          throw StateError('Endereco de entrega obrigatorio para carreto.');
        }
      }
      venda.total = total + venda.valorFrete;
      venda.custoTotal = custoTotal;
      if (descontoEmReais.isNaN ||
          descontoEmReais.isInfinite ||
          descontoEmReais < 0) {
        throw ArgumentError('Valor de desconto invalido.');
      }
      final descAplicado = descontoEmReais.clamp(0, venda.total).toDouble();
      venda.total = (venda.total - descAplicado)
          .clamp(0, double.infinity)
          .toDouble();
      venda.lucroTotal = venda.total - custoTotal;
      _aplicarPagamentoNoOrcamento(
        venda,
        pagamento,
        totalOrcamento: venda.total,
      );
      final vendaId = _db.vendaBox.put(venda);
      venda.id = vendaId;

      for (final item in itens) {
        item.venda.target = venda;
        _db.itemVendaBox.put(item);
      }

      return vendaId;
    });
    _notificarRedeAposEscrita();
    return novoId;
  }

  static const String _codigoProdutoFreteRetiradaFutura =
      '__FRETE_RET_FUTURA__';

  int _obterOuCriarProdutoFreteRetiradaFutura() {
    final q = _db.produtoBox
        .query(Produto_.codigoInterno.equals(_codigoProdutoFreteRetiradaFutura))
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
      codigoInterno: _codigoProdutoFreteRetiradaFutura,
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
    return _db.produtoBox.put(novo);
  }

  /// Orcamento filho so para o frete; total da venda mae nao e alterado (opcao 3).
  int registrarOrcamentoFreteRetiradaFutura({
    required int vendaMaeId,
    required double valorFreteCobrado,
    required DadosPagamentoOrcamento pagamento,
    required String enderecoEntrega,
    required String observacaoEntrega,
    required String prioridadeEntrega,
    required String janelaEntrega,
    required DateTime dataEntregaMarcada,
    int? vendedorId,
  }) {
    final novoId = _db.store.runInTransaction(TxMode.write, () {
      final mae = _db.vendaBox.get(vendaMaeId);
      if (mae == null) {
        throw StateError('Venda mae $vendaMaeId nao encontrada.');
      }
      if (mae.cancelada || mae.status != 'finalizada') {
        throw StateError(
          'Somente venda finalizada pode contratar frete de retirada futura.',
        );
      }
      if (mae.tipoEntrega != 'retirada_futura' || !mae.entregaPendente) {
        throw StateError(
          'Somente venda com retirada futura pendente aceita frete carreto.',
        );
      }
      if (mae.idOrcamentoFreteRetiradaAberto != 0) {
        throw StateError(
          'Ja existe orcamento de frete pendente para esta venda. Finalize ou cancele no caixa antes.',
        );
      }
      final temPendencia = mae.itens.any(
        (i) => i.quantidadePendenteRetirada > 0,
      );
      if (!temPendencia) {
        throw StateError('Nao ha quantidade pendente de retirada nesta venda.');
      }
      if (mae.cliente.targetId == 0) {
        throw StateError('Venda sem cliente. Cadastre o cliente antes.');
      }
      if (valorFreteCobrado < 0) {
        throw StateError('Valor de frete invalido.');
      }

      final produtoId = _obterOuCriarProdutoFreteRetiradaFutura();
      final proximoNumero = _proximoNumeroOrcamento();
      final venda = Venda(
        status: 'orcamento',
        numeroOrcamento: proximoNumero,
        formaPagamento: 'dinheiro',
        quantidadeParcelas: 1,
        tipoEntrega: 'retirada',
        valorFrete: 0,
        entregaPendente: false,
        vendaOrigemFreteRetiradaId: vendaMaeId,
      );
      venda.enderecoEntrega = enderecoEntrega.trim();
      venda.observacaoEntrega = observacaoEntrega.trim();
      venda.prioridadeEntrega = prioridadeEntrega;
      venda.janelaEntrega = janelaEntrega;
      venda.dataEntregaMarcada = dataEntregaMarcada;
      final cliId = mae.cliente.targetId;
      if (cliId != 0) {
        final cli = mae.cliente.target ?? _db.clienteBox.get(cliId);
        if (cli != null) {
          venda.cliente.target = cli;
        }
      }
      if (vendedorId != null) {
        final v = _db.vendedorBox.get(vendedorId);
        if (v != null) {
          venda.vendedor.target = v;
        }
      }

      final produto = _db.produtoBox.get(produtoId);
      if (produto == null) {
        throw StateError('Produto interno de frete nao encontrado.');
      }

      final refMae = mae.numeroOrcamento > 0
          ? '${mae.numeroOrcamento}'
          : '${mae.id}';
      final item = ItemVenda(
        nomeProduto: 'Frete carreto (ref. venda $refMae)',
        quantidade: 1,
        precoTipo: 'preco1',
        precoUnitario: valorFreteCobrado,
        precoCustoUnitario: 0,
      );
      item.produto.target = produto;
      final total = item.subtotal;
      venda.total = total;
      venda.custoTotal = 0;
      venda.lucroTotal = total;
      _aplicarPagamentoNoOrcamento(venda, pagamento, totalOrcamento: total);
      final vendaId = _db.vendaBox.put(venda);
      venda.id = vendaId;
      item.venda.target = venda;
      _db.itemVendaBox.put(item);

      mae.idOrcamentoFreteRetiradaAberto = vendaId;
      _db.vendaBox.put(mae);

      return vendaId;
    });
    _notificarRedeAposEscrita();
    return novoId;
  }

  /// Agrupa entregas de carreto (mesmo cliente) para a equipe ver como um unico carregamento.
  void definirGrupoEntregaLogistica(
    Set<int> vendaIds, {
    String motoristaEntrega = '',
  }) {
    final ids = vendaIds.where((id) => id > 0).toList()..sort();
    if (ids.length < 2) {
      throw StateError('Selecione ao menos duas entregas para agrupar.');
    }
    _db.store.runInTransaction(TxMode.write, () {
      final vendas = <Venda>[];
      for (final id in ids) {
        final v = _db.vendaBox.get(id);
        if (v == null) {
          throw StateError('Venda $id nao encontrada.');
        }
        vendas.add(v);
      }
      for (final v in vendas) {
        if (v.cancelada ||
            v.status != 'finalizada' ||
            !EntregaVendaHelper.vendaTemItensCarreto(v)) {
          throw StateError(
            'Somente entregas de carreto finalizadas podem ser agrupadas.',
          );
        }
      }
      final clienteRef = vendas.first.cliente.targetId;
      if (clienteRef == 0) {
        throw StateError(
          'Vendas sem cliente nao podem ser agrupadas (cadastre o cliente).',
        );
      }
      for (final v in vendas) {
        if (v.cliente.targetId != clienteRef) {
          throw StateError(
            'Agrupar na mesma carga exige o mesmo cliente em todas as notas.',
          );
        }
      }
      final grupoId = ids.first;
      final motorista = motoristaEntrega.trim();
      vendas.sort((a, b) => a.id.compareTo(b.id));
      for (var i = 0; i < vendas.length; i++) {
        final v = vendas[i];
        v.grupoEntregaFreteId = grupoId;
        v.ordemEntrega = i + 1;
        if (motorista.isNotEmpty) {
          v.motoristaEntrega = motorista;
        }
        _db.vendaBox.put(v);
      }
    });
    _notificarRedeAposEscrita();
  }

  /// Atualiza o motorista em todas as vendas do mesmo [grupoEntregaFreteId].
  void definirMotoristaEntregaNoGrupo(int grupoId, String motoristaEntrega) {
    if (grupoId <= 0) {
      throw StateError('Grupo de entrega invalido.');
    }
    final motorista = motoristaEntrega.trim();
    if (motorista.isEmpty) {
      throw StateError('Informe o motorista.');
    }
    _db.store.runInTransaction(TxMode.write, () {
      final q = _db.vendaBox
          .query(Venda_.grupoEntregaFreteId.equals(grupoId))
          .build();
      try {
        final vendas = q.find();
        if (vendas.isEmpty) {
          throw StateError('Nenhuma entrega encontrada neste grupo.');
        }
        for (final v in vendas) {
          if (!EntregaVendaHelper.vendaTemItensCarreto(v)) {
            throw StateError('Somente entregas da loja possuem motorista.');
          }
          v.motoristaEntrega = motorista;
          _db.vendaBox.put(v);
        }
      } finally {
        q.close();
      }
    });
    _notificarRedeAposEscrita();
  }

  void limparGrupoEntregaLogisticaEm(Set<int> vendaIds) {
    _db.store.runInTransaction(TxMode.write, () {
      for (final id in vendaIds) {
        final v = _db.vendaBox.get(id);
        if (v == null) continue;
        v.grupoEntregaFreteId = 0;
        v.ordemEntrega = 0;
        _db.vendaBox.put(v);
      }
    });
    _notificarRedeAposEscrita();
  }

  /// Define a sequencia de paradas (1..n) no mesmo [grupoEntregaFreteId].
  void atualizarSequenciaEntregaNoGrupo(int grupoId, List<int> vendaIdsOrdenados) {
    if (grupoId <= 0) {
      throw StateError('Grupo de entrega invalido.');
    }
    final ids = List<int>.from(vendaIdsOrdenados);
    if (ids.isEmpty) return;
    _db.store.runInTransaction(TxMode.write, () {
      for (var i = 0; i < ids.length; i++) {
        final v = _db.vendaBox.get(ids[i]);
        if (v == null) {
          throw StateError('Venda ${ids[i]} nao encontrada.');
        }
        if (v.grupoEntregaFreteId != grupoId) {
          throw StateError(
            'Venda ${v.numeroOrcamento} nao pertence a este grupo (mesmo carro).',
          );
        }
        v.ordemEntrega = i + 1;
        _db.vendaBox.put(v);
      }
    });
    _notificarRedeAposEscrita();
  }

  void _migrarUmaMaeRetiradaFuturaParaCarretoNaTransacao(
    Venda filho,
    Venda mae,
  ) {
    if (mae.idOrcamentoFreteRetiradaAberto != filho.id) {
      throw StateError(
        'Inconsistencia: este orcamento nao e o frete pendente da venda mae '
        '${mae.id}.',
      );
    }
    if (mae.cancelada || mae.status != 'finalizada') {
      throw StateError('Venda mae invalida para migracao.');
    }
    if (mae.tipoEntrega != 'retirada_futura' || !mae.entregaPendente) {
      throw StateError('Venda mae nao esta mais em retirada futura pendente.');
    }

    for (final item in mae.itens) {
      final q = item.quantidadePendenteRetirada;
      item.quantidadeNoCarreto = q;
      if (q <= 0) {
        _db.itemVendaBox.put(item);
        continue;
      }
      final produto = item.produto.target;
      if (produto == null) {
        throw StateError(
          'Item "${item.nomeProduto}" sem produto ligado: nao e possivel '
          'baixar estoque na migracao.',
        );
      }
      if (produto.estoqueReservado < q || produto.estoqueReal < q) {
        throw StateError(
          'Estoque insuficiente para ${produto.nome}: reservado '
          '${produto.estoqueReservado}, precisa $q (fisico ${produto.estoqueReal}).',
        );
      }
      produto.estoqueReservado -= q;
      produto.estoqueReal -= q;
      _db.produtoBox.put(produto);
      item.quantidadeJaRetirada += q;
      _db.itemVendaBox.put(item);
    }

    mae.tipoEntrega = 'entrega_loja';
    mae.valorFrete = 0;
    mae.enderecoEntrega = filho.enderecoEntrega.trim();
    mae.observacaoEntrega = filho.observacaoEntrega.trim();
    mae.prioridadeEntrega = filho.prioridadeEntrega;
    mae.janelaEntrega = filho.janelaEntrega;
    mae.dataEntregaMarcada = filho.dataEntregaMarcada;
    mae.statusEntrega = 'pendente';
    mae.entregaPendente = false;
    mae.motoristaEntrega = '';
    mae.cargaSeparada = false;
    mae.cargaCarregada = false;
    mae.cargaSaiu = false;
    mae.idOrcamentoFreteRetiradaAberto = 0;

    final dataHora = DateTime.now().toLocal();
    final prefixo =
        '[${dataHora.day.toString().padLeft(2, '0')}/'
        '${dataHora.month.toString().padLeft(2, '0')}/'
        '${dataHora.year} ${dataHora.hour.toString().padLeft(2, '0')}:'
        '${dataHora.minute.toString().padLeft(2, '0')}]';
    final linha =
        '$prefixo CAIXA: Migrada para carreto apos pagamento do frete '
        '(orc. ${filho.numeroOrcamento}).';
    final atualObs = mae.observacaoEntrega.trim();
    mae.observacaoEntrega = atualObs.isEmpty ? linha : '$atualObs\n$linha';

    _db.vendaBox.put(mae);
  }

  void _migrarVendaMaeRetiradaFuturaParaCarretoNaTransacao(Venda filho) {
    final maeId = filho.vendaOrigemFreteRetiradaId;
    if (maeId <= 0) {
      throw StateError(
        'Orcamento de frete sem vinculo a venda mae (dados inconsistentes).',
      );
    }
    final mae = _db.vendaBox.get(maeId);
    if (mae == null) {
      throw StateError('Venda mae $maeId nao encontrada ao finalizar frete.');
    }
    _migrarUmaMaeRetiradaFuturaParaCarretoNaTransacao(filho, mae);
  }

  void atualizarOrcamento(
    int vendaId,
    List<ItemVendaInput> itensInput, {
    required DadosPagamentoOrcamento pagamento,
    required DadosEntregaOrcamento entrega,
    int? clienteId,
    int? vendedorId,
    double descontoEmReais = 0,
  }) {
    if (itensInput.isEmpty) {
      throw ArgumentError('O orcamento deve conter ao menos um item.');
    }
    _db.store.runInTransaction(TxMode.write, () {
      final venda = _db.vendaBox.get(vendaId);
      if (venda == null) {
        throw StateError('Orcamento $vendaId nao encontrado.');
      }
      if (venda.status != 'orcamento') {
        throw StateError('Somente orcamentos podem ser alterados.');
      }
      if (venda.cancelada) {
        throw StateError('Nao e possivel editar orcamento cancelado.');
      }

      _aplicarDadosEntregaOrcamentoNaVenda(venda, entrega, itensInput);

      if (clienteId == null) {
        venda.cliente.target = null;
      } else {
        final cliente = _db.clienteBox.get(clienteId);
        if (cliente == null) {
          throw StateError('Cliente $clienteId nao encontrado.');
        }
        venda.cliente.target = cliente;
      }

      if (vendedorId == null) {
        venda.vendedor.target = null;
      } else {
        final vendedor = _db.vendedorBox.get(vendedorId);
        if (vendedor == null) {
          throw StateError('Vendedor $vendedorId nao encontrado.');
        }
        venda.vendedor.target = vendedor;
      }

      final idsAntigos = venda.itens.map((i) => i.id).toList();
      if (idsAntigos.isNotEmpty) {
        _db.itemVendaBox.removeMany(idsAntigos);
      }
      venda.itens.clear();

      double total = 0;
      double custoTotal = 0;
      for (final input in itensInput) {
        final produto = _db.produtoBox.get(input.produtoId);
        if (produto == null) {
          throw StateError('Produto ${input.produtoId} nao encontrado.');
        }
        if (input.quantidade <= 0) {
          throw StateError('Quantidade invalida para ${produto.nome}.');
        }
        final item = _criarItemVendaFromInput(input, produto);
        item.produto.target = produto;
        item.venda.target = venda;
        _db.itemVendaBox.put(item);
        total += item.subtotal;
        custoTotal += item.subtotalCusto;
      }

      if (EntregaVendaHelper.vendaTemItensCarreto(venda)) {
        if (venda.valorFrete < 0) {
          throw StateError('Valor de frete nao pode ser negativo.');
        }
        if (venda.enderecoEntrega.trim().isEmpty) {
          throw StateError('Endereco de entrega obrigatorio para carreto.');
        }
      }

      venda.total = total + venda.valorFrete;
      venda.custoTotal = custoTotal;
      if (descontoEmReais.isNaN ||
          descontoEmReais.isInfinite ||
          descontoEmReais < 0) {
        throw ArgumentError('Valor de desconto invalido.');
      }
      final descAplicado = descontoEmReais.clamp(0, venda.total).toDouble();
      venda.total = (venda.total - descAplicado)
          .clamp(0, double.infinity)
          .toDouble();
      venda.lucroTotal = venda.total - custoTotal;
      _aplicarPagamentoNoOrcamento(
        venda,
        pagamento,
        totalOrcamento: venda.total,
      );
      _db.vendaBox.put(venda);
    });
    _notificarRedeAposEscrita();
  }

  void converterOrcamentoParaVenda(
    int vendaId, {
    bool permitirVendaSemEstoque = true,
  }) {
    _db.store.runInTransaction(TxMode.write, () {
      final venda = _db.vendaBox.get(vendaId);
      if (venda == null) {
        throw StateError('Orcamento $vendaId nao encontrado.');
      }
      if (venda.status != 'orcamento') {
        throw StateError('Somente orcamentos podem ser finalizados.');
      }

      final filhoFreteRetirada = venda.vendaOrigemFreteRetiradaId > 0;

      if (!filhoFreteRetirada) {
        EntregaVendaHelper.aplicarLegadoTipoUnicoNosItensSeNecessario(venda);
        venda.carretoReservaAteSaida = venda.itens.any(
          (i) =>
              EntregaVendaHelper.tipoEfetivoItem(i) ==
              EntregaVendaHelper.tipoEntregaLoja,
        );
        venda.entregaPendente = venda.itens.any(
          (i) =>
              EntregaVendaHelper.tipoEfetivoItem(i) ==
              EntregaVendaHelper.tipoRetiradaFutura,
        );
        final consumoVendas =
            ComprasPreditivasService(_db).montarConsumoPorProdutoNoPeriodo();
        for (final item in venda.itens) {
          _baixarEstoqueItemAoFinalizarOrcamento(
            db: _db,
            item: item,
            permitirVendaSemEstoque: permitirVendaSemEstoque,
            consumoVendasPrecalculado: consumoVendas,
          );
        }
      }

      venda.status = 'finalizada';
      venda.cancelada = false;
      venda.motivoCancelamento = '';
      venda.canceladaPor = '';
      venda.canceladaEm = null;
      _db.vendaBox.put(venda);

      if (filhoFreteRetirada) {
        _migrarVendaMaeRetiradaFuturaParaCarretoNaTransacao(venda);
      }
    });
    _notificarRedeAposEscrita();
  }

  static int _quantidadeItemParaEstoqueCarreto(ItemVenda item) {
    final base = item.quantidade - item.quantidadeDevolvida;
    if (base < 0) return 0;
    final loja = item.quantidadeJaRetirada;
    final truck = base - loja;
    return truck < 0 ? 0 : truck;
  }

  void _baixarEstoqueCarretoAoMarcarSaida(Venda venda) {
    for (final item in venda.itens) {
      final produto = item.produto.target;
      if (produto == null) continue;
      final q = _quantidadeItemParaEstoqueCarreto(item);
      if (q <= 0) continue;
      if (produto.estoqueReservado < q) {
        throw StateError(
          'Reservado insuficiente para ${produto.nome} ao marcar saida do carreto '
          '(reservado ${produto.estoqueReservado}, precisa $q).',
        );
      }
      if (produto.estoqueReal < q) {
        throw StateError(
          'Estoque fisico insuficiente para ${produto.nome} ao marcar saida '
          '(real ${produto.estoqueReal}, precisa $q).',
        );
      }
      produto.estoqueReservado -= q;
      produto.estoqueReal -= q;
      _db.produtoBox.put(produto);
    }
  }

  void _estornarBaixaEstoqueCarretoAoDesmarcarSaida(Venda venda) {
    for (final item in venda.itens) {
      final produto = item.produto.target;
      if (produto == null) continue;
      var q = _quantidadeItemParaEstoqueCarreto(item);
      if (q <= 0) continue;
      if (venda.statusEntrega == 'entregue_complemento_pendente' &&
          venda.complementoEntregaJson.trim().isNotEmpty) {
        final m = _quantidadeComplementoDeclaradaPorItem(
          venda.complementoEntregaJson,
          item.id,
        );
        q -= m;
        if (q < 0) q = 0;
      }
      if (q <= 0) continue;
      produto.estoqueReal += q;
      produto.estoqueReservado += q;
      _db.produtoBox.put(produto);
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

  /// Volta ao fisico + reservado o que nao saiu na ida (apos baixa total no "Saiu").
  void _creditarEstoqueComplementoFaltaNaIda(
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
      final maxQ = _quantidadeItemParaEstoqueCarreto(item);
      if (e.value > maxQ) {
        throw StateError(
          'Falta declarada (${e.value}) de "${item.nomeProduto}" excede o '
          'entregavel da linha ($maxQ).',
        );
      }
      final produto = item.produto.target;
      if (produto == null) {
        throw StateError('Produto do item ${item.id} nao encontrado.');
      }
      produto.estoqueReservado += e.value;
      produto.estoqueReal += e.value;
      _db.produtoBox.put(produto);
    }
  }

  /// Segunda viagem: baixa o que havia sido creditado ao registrar o complemento.
  void _baixarEstoqueComplementoEntregaAoConcluir(
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
      final maxQ = _quantidadeItemParaEstoqueCarreto(item);
      if (e.value > maxQ) {
        throw StateError(
          'Quantidade do complemento (${e.value}) de "${item.nomeProduto}" '
          'excede o entregavel da linha ($maxQ).',
        );
      }
      final produto = item.produto.target;
      if (produto == null) {
        throw StateError('Produto do item ${item.id} nao encontrado.');
      }
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
      produto.estoqueReservado -= e.value;
      produto.estoqueReal -= e.value;
      _db.produtoBox.put(produto);
    }
  }

  void atualizarQuantidadeItemOrcamento(
    int vendaId,
    int itemId,
    int novaQuantidade,
  ) {
    if (novaQuantidade <= 0) {
      throw StateError('Quantidade deve ser maior que zero.');
    }
    _db.store.runInTransaction(TxMode.write, () {
      final venda = _db.vendaBox.get(vendaId);
      if (venda == null) {
        throw StateError('Orcamento $vendaId nao encontrado.');
      }
      if (venda.status != 'orcamento') {
        throw StateError('Somente orcamentos podem ser alterados.');
      }
      final item = venda.itens.where((i) => i.id == itemId).firstOrNull;
      if (item == null) {
        throw StateError('Item $itemId nao encontrado no orcamento.');
      }
      item.quantidade = novaQuantidade;
      _db.itemVendaBox.put(item);
      _recalcularTotaisVenda(venda);
    });
    _notificarRedeAposEscrita();
  }

  void removerItemOrcamento(int vendaId, int itemId) {
    _db.store.runInTransaction(TxMode.write, () {
      final venda = _db.vendaBox.get(vendaId);
      if (venda == null) {
        throw StateError('Orcamento $vendaId nao encontrado.');
      }
      if (venda.status != 'orcamento') {
        throw StateError('Somente orcamentos podem ser alterados.');
      }
      final existeItem = venda.itens.any((i) => i.id == itemId);
      if (!existeItem) {
        throw StateError('Item $itemId nao encontrado no orcamento.');
      }
      venda.itens.removeWhere((i) => i.id == itemId);
      _db.itemVendaBox.remove(itemId);
      if (venda.itens.isEmpty) {
        throw StateError('O orcamento precisa manter ao menos 1 item.');
      }
      _recalcularTotaisVenda(venda);
    });
    _notificarRedeAposEscrita();
  }

  void vincularClienteNoOrcamento(int vendaId, int? clienteId) {
    _db.store.runInTransaction(TxMode.write, () {
      final venda = _db.vendaBox.get(vendaId);
      if (venda == null) {
        throw StateError('Orcamento $vendaId nao encontrado.');
      }
      if (venda.status != 'orcamento') {
        throw StateError('Somente orcamentos podem ser alterados.');
      }
      if (clienteId == null) {
        venda.cliente.target = null;
      } else {
        final cliente = _db.clienteBox.get(clienteId);
        if (cliente == null) {
          throw StateError('Cliente $clienteId nao encontrado.');
        }
        venda.cliente.target = cliente;
      }
      _db.vendaBox.put(venda);
    });
    _notificarRedeAposEscrita();
  }

  void registrarNfceEmitida({
    required int vendaId,
    required String chaveAcesso,
    String numero = '',
    String serie = '',
    String protocolo = '',
    String urlDanfe = '',
  }) {
    _db.store.runInTransaction(TxMode.write, () {
      final venda = _db.vendaBox.get(vendaId);
      if (venda == null) {
        throw StateError('Venda $vendaId nao encontrada.');
      }
      venda.nfceChaveAcesso = chaveAcesso.trim();
      venda.nfceNumero = numero.trim();
      venda.nfceSerie = serie.trim();
      venda.nfceProtocolo = protocolo.trim();
      venda.nfceUrlDanfe = urlDanfe.trim();
      venda.nfceEmitidaEm = DateTime.now().toUtc();
      _db.vendaBox.put(venda);
    });
    _notificarRedeAposEscrita();
  }

  void vincularClienteVendaFinalizada(int vendaId, int clienteId) {
    _db.store.runInTransaction(TxMode.write, () {
      final venda = _db.vendaBox.get(vendaId);
      if (venda == null) {
        throw StateError('Venda $vendaId nao encontrada.');
      }
      if (venda.status != 'finalizada') {
        throw StateError(
          'Somente venda finalizada pode receber vinculo de cliente.',
        );
      }
      if (venda.cancelada) {
        throw StateError('Venda cancelada nao pode ser alterada.');
      }
      final cliente = _db.clienteBox.get(clienteId);
      if (cliente == null) {
        throw StateError('Cliente $clienteId nao encontrado.');
      }
      venda.cliente.target = cliente;
      _db.vendaBox.put(venda);
    });
    _notificarRedeAposEscrita();
  }

  void aplicarDescontoNoOrcamento(int vendaId, double valorDesconto) {
    _db.store.runInTransaction(TxMode.write, () {
      final venda = _db.vendaBox.get(vendaId);
      if (venda == null) {
        throw StateError('Orcamento $vendaId nao encontrado.');
      }
      if (venda.status != 'orcamento') {
        throw StateError('Somente orcamentos podem receber desconto.');
      }
      if (valorDesconto.isNaN ||
          valorDesconto.isInfinite ||
          valorDesconto < 0) {
        throw StateError('Valor de desconto invalido.');
      }
      final totalAntesDesconto = venda.total;
      final descontoAplicado = valorDesconto.clamp(0, venda.total).toDouble();
      venda.total = (venda.total - descontoAplicado)
          .clamp(0, double.infinity)
          .toDouble();
      venda.lucroTotal = venda.total - venda.custoTotal;
      if (venda.formaPagamento == 'misto' &&
          venda.pagamentosJson.trim().isNotEmpty &&
          totalAntesDesconto > 0) {
        final linhas = PagamentoOrcamentoCodec.decode(venda.pagamentosJson);
        if (linhas.length >= 2) {
          final fator = venda.total / totalAntesDesconto;
          final escaladas = linhas
              .map(
                (l) => PagamentoOrcamentoLinha(
                  meio: l.meio,
                  valor: (l.valor * fator),
                  parcelas: l.parcelas,
                ),
              )
              .toList();
          var soma = PagamentoOrcamentoCodec.soma(escaladas);
          final diff = venda.total - soma;
          if (escaladas.isNotEmpty && diff.abs() > 0.001) {
            final i = escaladas.length - 1;
            final u = escaladas[i];
            escaladas[i] = PagamentoOrcamentoLinha(
              meio: u.meio,
              valor: (u.valor + diff).clamp(0, double.infinity),
              parcelas: u.parcelas,
            );
            soma = PagamentoOrcamentoCodec.soma(escaladas);
          }
          venda.pagamentosJson = PagamentoOrcamentoCodec.encode(escaladas);
        }
      }
      _db.vendaBox.put(venda);
    });
    _notificarRedeAposEscrita();
  }

  /// Substitui linhas do misto ja com valores finais (ex.: conferidos no caixa).
  /// [linhas] deve somar exatamente [Venda.total] do orcamento no momento da gravacao.
  void substituirPagamentosMistoOrcamento(
    int vendaId,
    List<PagamentoOrcamentoLinha> linhas,
  ) {
    _db.store.runInTransaction(TxMode.write, () {
      final venda = _db.vendaBox.get(vendaId);
      if (venda == null) {
        throw StateError('Orcamento $vendaId nao encontrado.');
      }
      if (venda.status != 'orcamento') {
        throw StateError('Somente orcamentos podem ser alterados.');
      }
      if (venda.formaPagamento != 'misto') {
        throw StateError('Orcamento nao esta em pagamento misto.');
      }
      if (linhas.isEmpty) {
        throw StateError('Nenhuma linha de pagamento informada.');
      }
      final soma = PagamentoOrcamentoCodec.soma(linhas);
      if ((soma - venda.total).abs() > 0.05) {
        throw StateError(
          'Pagamento misto: soma (${soma.toStringAsFixed(2)}) deve igualar '
          'total (${venda.total.toStringAsFixed(2)}).',
        );
      }
      for (final l in linhas) {
        if (l.meio == 'cartao_debito' && l.parcelas != 1) {
          throw StateError('Cartao de debito deve ser a vista em cada linha.');
        }
      }
      var maxPar = 1;
      for (final l in linhas) {
        if (l.meio == 'cartao_credito' && l.parcelas > maxPar) {
          maxPar = l.parcelas;
        }
      }
      venda.quantidadeParcelas = maxPar;
      venda.pagamentosJson = PagamentoOrcamentoCodec.encode(linhas);
      _db.vendaBox.put(venda);
    });
    _notificarRedeAposEscrita();
  }

  List<Venda> listarEntregas({
    String? statusEntrega,
    String bairroTermo = '',
    DateTime? inicio,
    DateTime? fim,
  }) {
    final termo = bairroTermo.trim().toLowerCase();
    final inicioUtc = inicio?.toUtc();
    final fimUtc = fim?.toUtc();
    return listarTodas().where((venda) {
      if (venda.status != 'finalizada') return false;
      if (!EntregaVendaHelper.vendaTemItensCarreto(venda)) return false;
      if (statusEntrega != null &&
          statusEntrega != 'todos' &&
          venda.statusEntrega != statusEntrega) {
        return false;
      }
      final dataVendaUtc = venda.data.toUtc();
      if (inicioUtc != null && dataVendaUtc.isBefore(inicioUtc)) return false;
      if (fimUtc != null && dataVendaUtc.isAfter(fimUtc)) return false;
      if (termo.isNotEmpty &&
          !venda.enderecoEntrega.toLowerCase().contains(termo)) {
        return false;
      }
      return true;
    }).toList();
  }

  void atualizarStatusEntrega(
    int vendaId,
    String novoStatus, {
    String? complementoEntregaJson,
  }) {
    _db.store.runInTransaction(TxMode.write, () {
      final venda = _db.vendaBox.get(vendaId);
      if (venda == null) {
        throw StateError('Venda/Orcamento $vendaId nao encontrado.');
      }
      if (!EntregaVendaHelper.vendaTemItensCarreto(venda)) {
        throw StateError(
          'Somente pedidos de entrega podem ter status de entrega.',
        );
      }
      final statusAnterior = venda.statusEntrega;

      if (novoStatus == 'entregue_complemento_pendente') {
        final j = complementoEntregaJson?.trim() ?? '';
        if (j.isEmpty) {
          throw StateError(
            'Registro de itens em falta obrigatorio para entrega com complemento pendente.',
          );
        }
        final linhas = ComplementoEntregaCodec.decode(j);
        venda.statusEntrega = novoStatus;
        venda.complementoEntregaJson = j;
        _creditarEstoqueComplementoFaltaNaIda(venda, linhas);
      } else if (novoStatus == 'entregue') {
        final linhasComplemento = statusAnterior == 'entregue_complemento_pendente'
            ? ComplementoEntregaCodec.decode(venda.complementoEntregaJson)
            : const <LinhaComplementoEntrega>[];
        venda.statusEntrega = novoStatus;
        venda.complementoEntregaJson = '';
        if (linhasComplemento.isNotEmpty) {
          _baixarEstoqueComplementoEntregaAoConcluir(venda, linhasComplemento);
        }
      } else {
        venda.statusEntrega = novoStatus;
      }
      _db.vendaBox.put(venda);
    });
    _notificarRedeAposEscrita();
  }

  void atualizarPrioridadeEntrega(int vendaId, String novaPrioridade) {
    _db.store.runInTransaction(TxMode.write, () {
      final venda = _db.vendaBox.get(vendaId);
      if (venda == null) {
        throw StateError('Venda/Orcamento $vendaId nao encontrado.');
      }
      final prioridade = switch (novaPrioridade) {
        'urgente' => 'urgente',
        'agendada' => 'agendada',
        _ => 'normal',
      };
      venda.prioridadeEntrega = prioridade;
      _db.vendaBox.put(venda);
    });
    _notificarRedeAposEscrita();
  }

  void atualizarChecklistCargaEntrega(
    int vendaId, {
    bool? separado,
    bool? carregado,
    bool? saiu,
  }) {
    _db.store.runInTransaction(TxMode.write, () {
      final venda = _db.vendaBox.get(vendaId);
      if (venda == null) {
        throw StateError('Venda/Orcamento $vendaId nao encontrado.');
      }
      if (!EntregaVendaHelper.vendaTemItensCarreto(venda)) {
        throw StateError(
          'Somente entregas da loja possuem checklist de carga.',
        );
      }
      final saiuAntes = venda.cargaSaiu;
      if (separado != null) venda.cargaSeparada = separado;
      if (carregado != null) venda.cargaCarregada = carregado;
      if (saiu != null) venda.cargaSaiu = saiu;
      final saiuDepois = venda.cargaSaiu;

      if (venda.carretoReservaAteSaida &&
          venda.status == 'finalizada' &&
          !venda.cancelada) {
        if (!saiuAntes && saiuDepois) {
          _baixarEstoqueCarretoAoMarcarSaida(venda);
        } else if (saiuAntes && !saiuDepois) {
          _estornarBaixaEstoqueCarretoAoDesmarcarSaida(venda);
        }
      }

      _db.vendaBox.put(venda);
    });
    _notificarRedeAposEscrita();
  }

  void atualizarMotoristaEntrega(int vendaId, String motorista) {
    _db.store.runInTransaction(TxMode.write, () {
      final venda = _db.vendaBox.get(vendaId);
      if (venda == null) {
        throw StateError('Venda/Orcamento $vendaId nao encontrado.');
      }
      if (!EntregaVendaHelper.vendaTemItensCarreto(venda)) {
        throw StateError('Somente entregas da loja possuem motorista.');
      }
      venda.motoristaEntrega = motorista.trim();
      _db.vendaBox.put(venda);
    });
    _notificarRedeAposEscrita();
  }

  /// Define ou remove a data de entrega agendada (somente dia local; hora ignorada).
  void atualizarDataEntregaMarcada(int vendaId, DateTime? novaData) {
    _db.store.runInTransaction(TxMode.write, () {
      final venda = _db.vendaBox.get(vendaId);
      if (venda == null) {
        throw StateError('Venda/Orcamento $vendaId nao encontrado.');
      }
      if (!EntregaVendaHelper.vendaTemItensCarreto(venda)) {
        throw StateError(
          'Somente entregas da loja possuem data de entrega marcada.',
        );
      }
      if (venda.status != 'finalizada') {
        throw StateError(
          'Somente vendas finalizadas podem ter data de entrega ajustada aqui.',
        );
      }
      if (novaData != null) {
        final d = novaData.toLocal();
        venda.dataEntregaMarcada = DateTime(d.year, d.month, d.day);
      } else {
        venda.dataEntregaMarcada = null;
      }
      _db.vendaBox.put(venda);
    });
    _notificarRedeAposEscrita();
  }

  int migrarMotoristaEntregaLegado() {
    final n = _db.store.runInTransaction(TxMode.write, () {
      final vendas = _db.vendaBox.getAll();
      var totalMigradas = 0;
      for (final venda in vendas) {
        if (!EntregaVendaHelper.vendaTemItensCarreto(venda)) continue;
        if (venda.motoristaEntrega.trim().isNotEmpty) continue;
        final linhas = venda.observacaoEntrega.split('\n');
        String? motorista;
        final linhasSemMotorista = <String>[];
        for (final linha in linhas) {
          final limpa = linha.trim();
          if (limpa.startsWith('Motorista:') && motorista == null) {
            final nome = limpa.substring('Motorista:'.length).trim();
            if (nome.isNotEmpty) {
              motorista = nome;
            }
            continue;
          }
          if (limpa.isNotEmpty) {
            linhasSemMotorista.add(linha.trimRight());
          }
        }
        if (motorista == null) continue;
        venda.motoristaEntrega = motorista;
        venda.observacaoEntrega = linhasSemMotorista.join('\n');
        _db.vendaBox.put(venda);
        totalMigradas++;
      }
      return totalMigradas;
    });
    _notificarRedeAposEscrita();
    return n;
  }

  void registrarHistoricoStatusEntrega({
    required int vendaId,
    required String statusAnterior,
    required String statusNovo,
    required String usuario,
  }) {
    _db.store.runInTransaction(TxMode.write, () {
      final venda = _db.vendaBox.get(vendaId);
      if (venda == null) return;
      final item = HistoricoEntrega(
        statusAnterior: statusAnterior,
        statusNovo: statusNovo,
        usuario: usuario.trim().isEmpty ? 'sistema' : usuario.trim(),
        dataHora: DateTime.now(),
      );
      item.venda.target = venda;
      _db.historicoEntregaBox.put(item);
    });
    _notificarRedeAposEscrita();
  }

  void _anexarLinhaObservacaoEntregaEmVenda(
    Venda venda,
    String status,
    String motivo,
    String usuario,
  ) {
    final motivoLimpo = motivo.trim();
    if (motivoLimpo.isEmpty) return;
    final quem = usuario.trim().isEmpty ? 'sistema' : usuario.trim();
    final dataHora = DateTime.now().toLocal();
    final prefixo =
        '[${dataHora.day.toString().padLeft(2, '0')}/'
        '${dataHora.month.toString().padLeft(2, '0')}/'
        '${dataHora.year} ${dataHora.hour.toString().padLeft(2, '0')}:'
        '${dataHora.minute.toString().padLeft(2, '0')}]';
    final linha = '$prefixo ${status.toUpperCase()} por $quem: $motivoLimpo';
    final atual = venda.observacaoEntrega.trim();
    venda.observacaoEntrega = atual.isEmpty ? linha : '$atual\n$linha';
  }

  void registrarOcorrenciaEntrega({
    required int vendaId,
    required String status,
    required String motivo,
    required String usuario,
  }) {
    final motivoLimpo = motivo.trim();
    if (motivoLimpo.isEmpty) return;
    _db.store.runInTransaction(TxMode.write, () {
      final venda = _db.vendaBox.get(vendaId);
      if (venda == null) return;
      _anexarLinhaObservacaoEntregaEmVenda(venda, status, motivoLimpo, usuario);
      _db.vendaBox.put(venda);
    });
    _notificarRedeAposEscrita();
  }

  List<HistoricoEntrega> listarHistoricoEntrega(int vendaId) {
    final query = _db.historicoEntregaBox
        .query(HistoricoEntrega_.venda.equals(vendaId))
        .order(HistoricoEntrega_.dataHora)
        .build();
    final itens = query.find();
    query.close();
    return itens;
  }

  /// Retirada futura (entrega pendente):
  /// - No **orcamento** (antes de finalizar no Caixa): apenas grava a flag; o estoque
  ///   so e movido na finalizacao (`converterOrcamentoParaVenda`).
  /// - Na **venda finalizada**: converte entrega imediata em pendente (recompoe
  ///   estoqueReal e incrementa estoqueReservado).
  void marcarEntregaComoPendente(int vendaId) {
    _db.store.runInTransaction(TxMode.write, () {
      final venda = _db.vendaBox.get(vendaId);
      if (venda == null) {
        throw StateError('Venda $vendaId nao encontrada.');
      }
      if (venda.cancelada) {
        throw StateError('Nao e possivel alterar venda cancelada.');
      }
      if (venda.entregaPendente) {
        return;
      }

      if (venda.status == 'orcamento') {
        venda.entregaPendente = true;
        _db.vendaBox.put(venda);
        return;
      }

      if (venda.status != 'finalizada') {
        throw StateError(
          'Somente orcamentos ou vendas finalizadas podem ser marcados como retirada futura.',
        );
      }

      for (final item in venda.itens) {
        final produto = item.produto.target;
        if (produto == null) {
          throw StateError('Produto do item ${item.id} nao encontrado.');
        }
        produto.estoqueReal += item.quantidade;
        produto.estoqueReservado += item.quantidade;
        _db.produtoBox.put(produto);
      }

      venda.entregaPendente = true;
      _db.vendaBox.put(venda);
    });
    _notificarRedeAposEscrita();
  }

  int _proximoNumeroOrcamento() {
    final orcamentos = listarTodas().map((v) => v.numeroOrcamento);
    final maior = orcamentos.isEmpty
        ? 0
        : orcamentos.reduce((a, b) => a > b ? a : b);
    return maior + 1;
  }

  void _recalcularTotaisVenda(Venda venda) {
    double total = 0;
    double custoTotal = 0;
    for (final item in venda.itens) {
      total += item.subtotal;
      custoTotal += item.subtotalCusto;
    }
    venda.total = total + (venda.valorFrete > 0 ? venda.valorFrete : 0);
    venda.custoTotal = custoTotal;
    venda.lucroTotal = venda.total - custoTotal;
    _db.vendaBox.put(venda);
  }

  /// Retirada parcial ou total em venda com `entregaPendente`.
  /// Para cada unidade retirada, baixa [Produto.estoqueReservado] e [Produto.estoqueReal].
  /// Quando todos os itens tiverem sido totalmente retirados, [Venda.entregaPendente]
  /// passa a `false`.
  void registrarRetiradaParcial(
    int vendaId,
    Map<int, int> quantidadePorItemVendaId, {
    required String usuario,
    String? retiradoPor,
    bool permitirSemConferenciaEstoque = true,
  }) {
    final filtrado = <int, int>{};
    for (final e in quantidadePorItemVendaId.entries) {
      if (e.value > 0) {
        filtrado[e.key] = e.value;
      }
    }
    if (filtrado.isEmpty) {
      throw StateError('Informe ao menos uma quantidade a retirar.');
    }

    final usuarioLimpo = usuario.trim().isEmpty ? 'sistema' : usuario.trim();
    final linhasLog = <String>[];

    _db.store.runInTransaction(TxMode.write, () {
      final venda = _db.vendaBox.get(vendaId);
      if (venda == null) {
        throw StateError('Venda $vendaId nao encontrada.');
      }
      if (venda.cancelada) {
        throw StateError('Venda cancelada nao pode registrar retirada.');
      }
      if (venda.status != 'finalizada') {
        throw StateError('Somente vendas finalizadas permitem retirada.');
      }
      if (!venda.entregaPendente) {
        throw StateError('Esta venda nao esta com retirada futura pendente.');
      }

      for (final e in filtrado.entries) {
        final itemId = e.key;
        final qRet = e.value;
        final item = _db.itemVendaBox.get(itemId);
        if (item == null) {
          throw StateError('Item de venda $itemId nao encontrado.');
        }
        if (item.venda.targetId != vendaId) {
          throw StateError('Item $itemId nao pertence a esta venda.');
        }
        final pendente = item.quantidadePendenteRetirada;
        if (qRet > pendente) {
          throw StateError(
            'Retirada de $qRet un. de "${item.nomeProduto}" excede o pendente ($pendente).',
          );
        }

        final produto = item.produto.target;
        if (produto == null) {
          throw StateError('Produto do item ${item.id} nao encontrado.');
        }
        if (!permitirSemConferenciaEstoque) {
          if (produto.estoqueReal < qRet) {
            throw StateError(
              'Estoque fisico insuficiente para retirar $qRet de ${produto.nome}.',
            );
          }
          if (produto.estoqueReservado < qRet) {
            throw StateError(
              'Estoque reservado inconsistente para ${produto.nome}.',
            );
          }
        }

        produto.estoqueReal -= qRet;
        produto.estoqueReservado -= qRet;
        _db.produtoBox.put(produto);

        item.quantidadeJaRetirada += qRet;
        _db.itemVendaBox.put(item);

        linhasLog.add('${item.nomeProduto} x$qRet');
      }

      var aindaPendente = false;
      for (final it in venda.itens) {
        if (it.quantidadePendenteRetirada > 0) {
          aindaPendente = true;
          break;
        }
      }
      if (!aindaPendente) {
        venda.entregaPendente = false;
      }
      _db.vendaBox.put(venda);
    });
    _notificarRedeAposEscrita();

    final trecho = linhasLog.join('; ');
    var motivoFinal = trecho.isEmpty
        ? 'Retirada registrada.'
        : 'Retirada: $trecho';
    final quemRetirou = retiradoPor?.trim() ?? '';
    if (quemRetirou.isNotEmpty) {
      motivoFinal = '$motivoFinal Quem retirou: $quemRetirou.';
    }
    registrarOcorrenciaEntrega(
      vendaId: vendaId,
      status: 'retirada_futura',
      motivo: motivoFinal,
      usuario: usuarioLimpo,
    );
  }

  /// Retirada parcial na **loja** antes do carro sair (carreto com reserva ate a saida).
  /// Baixa [Produto.estoqueReservado] e [Produto.estoqueReal] na hora (mercadoria sai com o cliente).
  /// A carga do romaneio passa a considerar [ItemVenda.quantidadeJaRetirada] ate marcar [Venda.cargaSaiu].
  void registrarRetiradaParcialLojaCarretoAntesSaida(
    int vendaId,
    Map<int, int> quantidadePorItemVendaId, {
    required String usuario,
    String? retiradoPor,
    bool permitirSemConferenciaEstoque = true,
  }) {
    final filtrado = <int, int>{};
    for (final e in quantidadePorItemVendaId.entries) {
      if (e.value > 0) {
        filtrado[e.key] = e.value;
      }
    }
    if (filtrado.isEmpty) {
      throw StateError('Informe ao menos uma quantidade a retirar.');
    }

    final usuarioLimpo = usuario.trim().isEmpty ? 'sistema' : usuario.trim();
    final linhasLog = <String>[];

    _db.store.runInTransaction(TxMode.write, () {
      final venda = _db.vendaBox.get(vendaId);
      if (venda == null) {
        throw StateError('Venda $vendaId nao encontrada.');
      }
      if (venda.cancelada) {
        throw StateError('Venda cancelada nao pode registrar retirada.');
      }
      if (venda.status != 'finalizada') {
        throw StateError('Somente vendas finalizadas permitem retirada na loja.');
      }
      if (venda.tipoEntrega != 'entrega_loja') {
        throw StateError(
          'Somente entregas da loja (carreto) permitem retirada na loja por esta acao.',
        );
      }
      if (!venda.carretoReservaAteSaida) {
        throw StateError(
          'Esta entrega nao usa reserva ate a saida; use o fluxo de retirada futura ou devolucao.',
        );
      }
      if (venda.cargaSaiu) {
        throw StateError(
          'O carro ja marcou saida; retirada na loja so e permitida ate antes disso.',
        );
      }
      final migrada = venda.itens.any((i) => i.quantidadeNoCarreto > 0);
      if (migrada) {
        throw StateError(
          'Venda migrada de retirada futura: use a listagem de vendas para retirada futura.',
        );
      }

      for (final e in filtrado.entries) {
        final itemId = e.key;
        final qRet = e.value;
        final item = _db.itemVendaBox.get(itemId);
        if (item == null) {
          throw StateError('Item de venda $itemId nao encontrado.');
        }
        if (item.venda.targetId != vendaId) {
          throw StateError('Item $itemId nao pertence a esta venda.');
        }
        final pendente = item.quantidadeAindaNoCarretoAntesSaida;
        if (qRet > pendente) {
          throw StateError(
            'Retirada de $qRet un. de "${item.nomeProduto}" excede o que ainda '
            'segue para o carro ($pendente).',
          );
        }

        final produto = item.produto.target;
        if (produto == null) {
          throw StateError('Produto do item ${item.id} nao encontrado.');
        }
        if (!permitirSemConferenciaEstoque) {
          if (produto.estoqueReal < qRet) {
            throw StateError(
              'Estoque fisico insuficiente para retirar $qRet de ${produto.nome}.',
            );
          }
          if (produto.estoqueReservado < qRet) {
            throw StateError(
              'Estoque reservado inconsistente para ${produto.nome}.',
            );
          }
        }

        produto.estoqueReal -= qRet;
        produto.estoqueReservado -= qRet;
        _db.produtoBox.put(produto);

        item.quantidadeJaRetirada += qRet;
        _db.itemVendaBox.put(item);

        linhasLog.add('${item.nomeProduto} x$qRet');
      }

      _db.vendaBox.put(venda);
    });
    _notificarRedeAposEscrita();

    final trecho = linhasLog.join('; ');
    var motivoFinal = trecho.isEmpty
        ? 'Retirada na loja (pre-saida) registrada.'
        : 'Retirada na loja (pre-saida): $trecho';
    final quemRetirou = retiradoPor?.trim() ?? '';
    if (quemRetirou.isNotEmpty) {
      motivoFinal = '$motivoFinal Quem retirou: $quemRetirou.';
    }
    registrarOcorrenciaEntrega(
      vendaId: vendaId,
      status: 'retirada_loja_pre_saida',
      motivo: motivoFinal,
      usuario: usuarioLimpo,
    );
  }

  void cancelarVenda(
    int vendaId, {
    String motivo = '',
    String canceladaPor = '',
  }) {
    final motivoLimpo = motivo.trim();
    final usuarioCancelamento = canceladaPor.trim();
    _db.store.runInTransaction(TxMode.write, () {
      final venda = _db.vendaBox.get(vendaId);
      if (venda == null) {
        throw StateError('Venda $vendaId nao encontrada.');
      }
      if (venda.cancelada) {
        throw StateError('Venda $vendaId ja esta cancelada.');
      }

      if (venda.status != 'orcamento' &&
          venda.entregaPendente &&
          venda.itens.any((i) => i.quantidadeJaRetirada > 0)) {
        throw StateError(
          'Nao e possivel cancelar: ja houve retirada parcial de mercadoria nesta venda.',
        );
      }

      if (venda.status != 'orcamento' &&
          venda.itens.any((i) => i.quantidadeDevolvida > 0)) {
        throw StateError(
          'Nao e possivel cancelar: existem devolucoes/trocas registradas nesta venda.',
        );
      }

      if (venda.status == 'orcamento') {
        if (venda.vendaOrigemFreteRetiradaId > 0) {
          final mae = _db.vendaBox.get(venda.vendaOrigemFreteRetiradaId);
          if (mae != null && mae.idOrcamentoFreteRetiradaAberto == vendaId) {
            mae.idOrcamentoFreteRetiradaAberto = 0;
            _db.vendaBox.put(mae);
          }
        }
        venda.cancelada = true;
        venda.motivoCancelamento = motivoLimpo;
        venda.canceladaPor = usuarioCancelamento;
        venda.canceladaEm = DateTime.now();
        _db.vendaBox.put(venda);
        return;
      }

      for (final item in venda.itens) {
        final produto = item.produto.target;
        if (produto != null) {
          if (venda.entregaPendente) {
            final reservadoAtual = produto.estoqueReservado;
            produto.estoqueReservado = (reservadoAtual - item.quantidade)
                .clamp(0, reservadoAtual)
                .toInt();
          } else if (EntregaVendaHelper.vendaTemItensCarreto(venda) &&
              venda.carretoReservaAteSaida) {
            if (venda.cargaSaiu) {
              produto.estoqueReal += item.quantidade;
            } else {
              final qReserva = _quantidadeItemParaEstoqueCarreto(item);
              final reservadoAtual = produto.estoqueReservado;
              produto.estoqueReservado = (reservadoAtual - qReserva)
                  .clamp(0, reservadoAtual)
                  .toInt();
            }
          } else {
            produto.estoqueReal += item.quantidade;
          }
          _db.produtoBox.put(produto);
        }
      }

      venda.cancelada = true;
      venda.motivoCancelamento = motivoLimpo;
      venda.canceladaPor = usuarioCancelamento;
      venda.canceladaEm = DateTime.now();
      _db.vendaBox.put(venda);
    });
    _notificarRedeAposEscrita();
  }

  /// Devolucao (estoque de volta) ou troca (devolucao + saida de novos itens).
  /// Registro de devolucao e local; venda e produtos seguem na sync LAN.
  int registrarDevolucaoOuTroca({
    required int vendaOrigemId,
    required String tipo,
    required String motivo,
    required String observacaoFinanceira,
    required String registradoPor,
    required List<LinhaDevolucaoEntradaInput> entradas,
    required List<LinhaTrocaSaidaInput> saidasTroca,
    bool permitirVendaSemEstoque = true,
  }) {
    final tipoLimpo = tipo.trim().toLowerCase();
    if (tipoLimpo != 'devolucao' && tipoLimpo != 'troca') {
      throw StateError('Tipo deve ser devolucao ou troca.');
    }
    final motivoLimpo = motivo.trim();
    if (motivoLimpo.isEmpty) {
      throw StateError('Informe o motivo da devolucao/troca.');
    }
    final filtradas = entradas.where((e) => e.quantidade > 0).toList();
    if (filtradas.isEmpty) {
      throw StateError('Informe ao menos um item com quantidade devolvida.');
    }
    if (tipoLimpo == 'troca' && saidasTroca.every((s) => s.quantidade <= 0)) {
      throw StateError('Em troca, informe ao menos um produto de saida.');
    }

    final registroId = _db.store.runInTransaction(TxMode.write, () {
      final venda = _db.vendaBox.get(vendaOrigemId);
      if (venda == null) {
        throw StateError('Venda $vendaOrigemId nao encontrada.');
      }
      if (venda.cancelada) {
        throw StateError('Venda cancelada nao aceita devolucao/troca.');
      }
      if (venda.status != 'finalizada') {
        throw StateError(
          'Somente vendas finalizadas permitem devolucao/troca.',
        );
      }
      if (venda.vendaOrigemFreteRetiradaId > 0) {
        throw StateError(
          'Devolucao/troca nao disponivel para orcamento de frete (venda filha).',
        );
      }

      for (final e in filtradas) {
        final item = _db.itemVendaBox.get(e.itemVendaId);
        if (item == null) {
          throw StateError('Item de venda ${e.itemVendaId} nao encontrado.');
        }
        if (item.venda.targetId != vendaOrigemId) {
          throw StateError('Item ${e.itemVendaId} nao pertence a esta venda.');
        }
        final maxDev = item.quantidade - item.quantidadeDevolvida;
        if (e.quantidade > maxDev) {
          throw StateError(
            'Devolucao de ${e.quantidade} un. de "${item.nomeProduto}" '
            'excede o disponivel ($maxDev).',
          );
        }
        final produto = item.produto.target;
        if (produto == null) {
          throw StateError('Produto do item ${item.id} nao encontrado.');
        }
        _aplicarEstoqueEntradaDevolucao(
          venda: venda,
          item: item,
          produto: produto,
          qtd: e.quantidade,
        );
        _db.produtoBox.put(produto);
        item.quantidadeDevolvida += e.quantidade;
        _db.itemVendaBox.put(item);
      }

      if (tipoLimpo == 'troca') {
        for (final s in saidasTroca) {
          if (s.quantidade <= 0) continue;
          final p = _db.produtoBox.get(s.produtoId);
          if (p == null) {
            throw StateError('Produto ${s.produtoId} nao encontrado.');
          }
          if (!permitirVendaSemEstoque && p.estoqueReal < s.quantidade) {
            throw StateError(
              'Estoque insuficiente na troca para ${p.nome} (precisa ${s.quantidade}).',
            );
          }
        }
        for (final s in saidasTroca) {
          if (s.quantidade <= 0) continue;
          final p = _db.produtoBox.get(s.produtoId);
          if (p == null) {
            throw StateError('Produto ${s.produtoId} nao encontrado.');
          }
          p.estoqueReal -= s.quantidade;
          _db.produtoBox.put(p);
        }
      }

      final reg = RegistroDevolucao(
        tipo: tipoLimpo,
        motivo: motivoLimpo,
        observacaoFinanceira: observacaoFinanceira.trim(),
        registradoPor: registradoPor.trim().isEmpty
            ? 'sistema'
            : registradoPor.trim(),
      );
      reg.vendaOrigem.target = venda;
      final regId = _db.registroDevolucaoBox.put(reg);
      final regSalvo = _db.registroDevolucaoBox.get(regId);
      if (regSalvo == null) {
        throw StateError('Falha ao gravar registro de devolucao.');
      }

      for (final e in filtradas) {
        final item = _db.itemVendaBox.get(e.itemVendaId);
        if (item == null) continue;
        final produto = item.produto.target;
        if (produto == null) continue;
        final linha = LinhaDevolucaoEntrada(
          itemVendaId: item.id,
          quantidade: e.quantidade,
          precoUnitarioReferencia: item.precoUnitario,
          nomeProdutoSnapshot: item.nomeProduto,
        );
        linha.registro.target = regSalvo;
        linha.produto.target = produto;
        _db.linhaDevolucaoEntradaBox.put(linha);
      }

      if (tipoLimpo == 'troca') {
        for (final s in saidasTroca) {
          if (s.quantidade <= 0) continue;
          final p = _db.produtoBox.get(s.produtoId);
          if (p == null) continue;
          final linha = LinhaTrocaSaida(
            quantidade: s.quantidade,
            precoUnitario: s.precoUnitario,
            precoCustoUnitario: s.precoCustoUnitario,
            precoTipo: s.precoTipo,
            nomeProdutoSnapshot: p.nome,
          );
          linha.registro.target = regSalvo;
          linha.produto.target = p;
          _db.linhaTrocaSaidaBox.put(linha);
        }
      }

      if (EntregaVendaHelper.vendaTemItensCarreto(venda)) {
        final hist = HistoricoEntrega(
          statusAnterior: venda.statusEntrega,
          statusNovo: tipoLimpo == 'troca'
              ? HistoricoEntregaEventos.troca
              : HistoricoEntregaEventos.devolucao,
          usuario: regSalvo.registradoPor,
          dataHora: DateTime.now(),
        );
        hist.venda.target = venda;
        _db.historicoEntregaBox.put(hist);

        final statusObs = tipoLimpo == 'troca'
            ? 'Troca material (retorno)'
            : 'Devolucao material (retorno)';
        _anexarLinhaObservacaoEntregaEmVenda(
          venda,
          statusObs,
          motivoLimpo,
          regSalvo.registradoPor,
        );
        _db.vendaBox.put(venda);
      }

      return regId;
    });
    _notificarRedeAposEscrita();
    return registroId;
  }

  List<RegistroDevolucao> listarRegistrosDevolucaoPorVenda(int vendaId) {
    final q = _db.registroDevolucaoBox
        .query(RegistroDevolucao_.vendaOrigem.equals(vendaId))
        .order(RegistroDevolucao_.data, flags: Order.descending)
        .build();
    final list = q.find();
    q.close();
    return list;
  }

  List<RegistroDevolucao> listarRegistrosDevolucaoPorPeriodo(
    PeriodoFiltro periodo,
  ) {
    final inicioUtc = periodo.inicio.toUtc();
    final fimUtc = periodo.fim.toUtc();
    final q = _db.registroDevolucaoBox
        .query()
        .order(RegistroDevolucao_.data, flags: Order.descending)
        .build();
    final all = q.find();
    q.close();
    return all.where((r) {
      final d = r.data.toUtc();
      return !d.isBefore(inicioUtc) && !d.isAfter(fimUtc);
    }).toList();
  }

  double valorReferenciaEntradaRegistro(RegistroDevolucao r) {
    var s = 0.0;
    for (final l in r.linhasEntrada) {
      s += l.quantidade * l.precoUnitarioReferencia;
    }
    return s;
  }

  double valorSaidaTrocaRegistro(RegistroDevolucao r) {
    var s = 0.0;
    for (final l in r.linhasSaidaTroca) {
      s += l.quantidade * l.precoUnitario;
    }
    return s;
  }

  /// Efeito na receita: troca = saida - entrada; devolucao = -entrada.
  double impactoFaturamentoRegistro(RegistroDevolucao r) {
    final e = valorReferenciaEntradaRegistro(r);
    if (r.tipo == 'troca') {
      return valorSaidaTrocaRegistro(r) - e;
    }
    return -e;
  }

  double impactoLucroRegistro(RegistroDevolucao r) {
    var lucro = 0.0;
    for (final l in r.linhasEntrada) {
      final item = _db.itemVendaBox.get(l.itemVendaId);
      final cu = item?.precoCustoUnitario ?? 0;
      lucro -= l.quantidade * (l.precoUnitarioReferencia - cu);
    }
    for (final l in r.linhasSaidaTroca) {
      lucro += l.quantidade * (l.precoUnitario - l.precoCustoUnitario);
    }
    return lucro;
  }

  ImpactosDevolucaoTrocaPeriodo calcularImpactosDevolucaoTrocaPeriodo(
    PeriodoFiltro periodo,
  ) {
    final regs = listarRegistrosDevolucaoPorPeriodo(periodo);
    var fatT = 0.0;
    var lucT = 0.0;
    final pvFat = <int, double>{};
    final pvLuc = <int, double>{};
    final pcFat = <int, double>{};
    for (final r in regs) {
      final fat = impactoFaturamentoRegistro(r);
      final luc = impactoLucroRegistro(r);
      fatT += fat;
      lucT += luc;
      final vidOrigem = r.vendaOrigem.targetId;
      final vOrigem = vidOrigem > 0 ? (_db.vendaBox.get(vidOrigem)) : null;
      final vendedorId = vOrigem?.vendedor.targetId ?? 0;
      pvFat[vendedorId] = (pvFat[vendedorId] ?? 0) + fat;
      pvLuc[vendedorId] = (pvLuc[vendedorId] ?? 0) + luc;
      final clienteId = vOrigem?.cliente.targetId ?? 0;
      pcFat[clienteId] = (pcFat[clienteId] ?? 0) + fat;
    }
    return ImpactosDevolucaoTrocaPeriodo(
      impactoFaturamentoTotal: fatT,
      impactoLucroTotal: lucT,
      porVendedorFaturamento: pvFat,
      porVendedorLucro: pvLuc,
      porClienteFaturamento: pcFat,
    );
  }

  /// Ids de produtos mais vendidos no periodo (quantidade liquida desc).
  List<int> listarProdutoIdsMaisVendidos({
    int dias = 30,
    int limite = 50,
  }) {
    if (limite <= 0) return const [];
    final fim = DateTime.now().toUtc();
    final inicio = fim.subtract(Duration(days: dias));
    final qb = _db.itemVendaBox.query();
    qb.link(
      ItemVenda_.venda,
      Venda_.status
          .equals('finalizada')
          .and(Venda_.cancelada.equals(false))
          .and(Venda_.data.greaterOrEqualDate(inicio))
          .and(Venda_.data.lessOrEqualDate(fim)),
    );
    final query = qb.build();
    try {
      final itens = query.find();
      final qtdPorProduto = <int, int>{};
      for (final item in itens) {
        final pid = item.produto.targetId;
        if (pid <= 0) continue;
        final q = item.quantidade - item.quantidadeDevolvida;
        if (q <= 0) continue;
        qtdPorProduto[pid] = (qtdPorProduto[pid] ?? 0) + q;
      }
      final ordenado = qtdPorProduto.entries.toList()
        ..sort((a, b) => b.value.compareTo(a.value));
      return ordenado.take(limite).map((e) => e.key).toList();
    } finally {
      query.close();
    }
  }

  List<DeltaProdutoDevolucao> listarDeltasProdutosDevolucaoPeriodo(
    PeriodoFiltro periodo,
  ) {
    final out = <DeltaProdutoDevolucao>[];
    for (final r in listarRegistrosDevolucaoPorPeriodo(periodo)) {
      for (final l in r.linhasEntrada) {
        final pid = l.produto.targetId;
        final nome = l.nomeProdutoSnapshot.trim().isNotEmpty
            ? l.nomeProdutoSnapshot.trim()
            : (l.produto.target?.nome ?? '');
        final chave = pid > 0 ? 'id:$pid' : 'nome:$nome';
        final v = l.quantidade * l.precoUnitarioReferencia;
        out.add(
          DeltaProdutoDevolucao(
            chaveAgg: chave,
            nomeExibicao: nome.isEmpty ? 'Produto' : nome,
            produtoId: pid,
            deltaQuantidade: -l.quantidade,
            deltaValor: -v,
          ),
        );
      }
      for (final l in r.linhasSaidaTroca) {
        final pid = l.produto.targetId;
        final nome = l.nomeProdutoSnapshot.trim().isNotEmpty
            ? l.nomeProdutoSnapshot.trim()
            : (l.produto.target?.nome ?? '');
        final chave = pid > 0 ? 'id:$pid' : 'nome:$nome';
        final v = l.quantidade * l.precoUnitario;
        out.add(
          DeltaProdutoDevolucao(
            chaveAgg: chave,
            nomeExibicao: nome.isEmpty ? 'Produto' : nome,
            produtoId: pid,
            deltaQuantidade: l.quantidade,
            deltaValor: v,
          ),
        );
      }
    }
    return out;
  }

  /// Valor de referencia ja devolvido (preco original da linha) para exibicao.
  double valorReferenciaDevolvidoAcumuladoVenda(int vendaId) {
    final v = _db.vendaBox.get(vendaId);
    if (v == null) return 0;
    var s = 0.0;
    for (final it in v.itens) {
      if (it.quantidadeDevolvida <= 0) continue;
      s += it.quantidadeDevolvida * it.precoUnitario;
    }
    return s;
  }

  double valorSaidaTrocaAcumuladoVenda(int vendaId) {
    var s = 0.0;
    for (final r in listarRegistrosDevolucaoPorVenda(vendaId)) {
      if (r.tipo != 'troca') continue;
      s += valorSaidaTrocaRegistro(r);
    }
    return s;
  }

  void _aplicarEstoqueEntradaDevolucao({
    required Venda venda,
    required ItemVenda item,
    required Produto produto,
    required int qtd,
  }) {
    if (qtd <= 0) return;
    if (venda.entregaPendente) {
      final daReserva = qtd <= item.quantidadePendenteRetirada
          ? qtd
          : item.quantidadePendenteRetirada;
      final daCliente = qtd - daReserva;
      if (daReserva > 0) {
        final r = produto.estoqueReservado;
        produto.estoqueReservado = (r - daReserva).clamp(0, r).toInt();
      }
      if (daCliente > 0) {
        produto.estoqueReal += daCliente;
      }
    } else if (EntregaVendaHelper.vendaTemItensCarreto(venda) &&
        venda.carretoReservaAteSaida &&
        !venda.cargaSaiu) {
      final r = produto.estoqueReservado;
      produto.estoqueReservado = (r - qtd).clamp(0, r).toInt();
    } else {
      produto.estoqueReal += qtd;
    }
  }
}
