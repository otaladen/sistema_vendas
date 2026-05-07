import '../domain/pagamento_orcamento.dart';
import '../model/item_venda.dart';
import '../model/historico_entrega.dart';
import '../model/produto.dart';
import '../model/venda.dart';
import '../objectbox.g.dart';
import 'objectbox.dart';

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

class ItemVendaInput {
  ItemVendaInput({
    required this.produtoId,
    required this.quantidade,
    required this.precoUnitario,
    this.precoTipo = 'preco1',
  });

  final int produtoId;
  final int quantidade;
  final double precoUnitario;
  final String precoTipo;
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

class VendaRepository {
  VendaRepository(this._db);

  final ObjectBox _db;

  List<Venda> listarTodas() {
    final query = _db.vendaBox
        .query()
        .order(Venda_.data, flags: Order.descending)
        .build();
    final vendas = query.find();
    query.close();
    return vendas;
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

  int registrarVenda(
    List<ItemVendaInput> itensInput, {
    bool permitirVendaSemEstoque = true,
  }) {
    if (itensInput.isEmpty) {
      throw ArgumentError('A venda deve conter ao menos um item.');
    }

    return _db.store.runInTransaction(TxMode.write, () {
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

      for (final input in itensInput) {
        final produto = _db.produtoBox.get(input.produtoId);
        if (produto == null) {
          throw StateError('Produto ${input.produtoId} nao encontrado.');
        }
        if (input.quantidade <= 0) {
          throw StateError('Quantidade invalida para ${produto.nome}.');
        }

        if (!permitirVendaSemEstoque && produto.estoqueReal < input.quantidade) {
          throw StateError('Estoque insuficiente para ${produto.nome}.');
        }

        produto.estoqueReal -= input.quantidade;
        _db.produtoBox.put(produto);

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
  }

  int registrarOrcamento(
    List<ItemVendaInput> itensInput, {
    required DadosPagamentoOrcamento pagamento,
    required DadosEntregaOrcamento entrega,
    int? clienteId,
    int? vendedorId,
  }) {
    if (itensInput.isEmpty) {
      throw ArgumentError('O orcamento deve conter ao menos um item.');
    }
    return _db.store.runInTransaction(TxMode.write, () {
      final proximoNumero = _proximoNumeroOrcamento();
      final venda = Venda(
        status: 'orcamento',
        numeroOrcamento: proximoNumero,
        formaPagamento: 'dinheiro',
        quantidadeParcelas: 1,
        pagamentosJson: '',
        tipoEntrega: entrega.tipoEntrega,
        valorFrete: entrega.tipoEntrega == 'entrega_loja'
            ? entrega.valorFrete
            : 0,
        enderecoEntrega: entrega.tipoEntrega == 'entrega_loja'
            ? entrega.enderecoEntrega
            : '',
        observacaoEntrega: entrega.tipoEntrega == 'entrega_loja'
            ? entrega.observacaoEntrega
            : '',
        statusEntrega: entrega.tipoEntrega == 'entrega_loja'
            ? 'pendente'
            : 'nao_aplicavel',
        prioridadeEntrega: entrega.tipoEntrega == 'entrega_loja'
            ? entrega.prioridadeEntrega
            : 'normal',
        janelaEntrega: entrega.tipoEntrega == 'entrega_loja'
            ? entrega.janelaEntrega
            : 'nao_definida',
        dataEntregaMarcada: entrega.tipoEntrega == 'entrega_loja'
            ? entrega.dataEntregaMarcada
            : null,
        entregaPendente: entrega.tipoEntrega == 'retirada_futura',
      );
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

      if (venda.tipoEntrega == 'entrega_loja') {
        if (venda.valorFrete < 0) {
          throw StateError('Valor de frete nao pode ser negativo.');
        }
        if (venda.enderecoEntrega.trim().isEmpty) {
          throw StateError(
            'Endereco de entrega obrigatorio para carreto.',
          );
        }
      }
      venda.total = total + venda.valorFrete;
      venda.custoTotal = custoTotal;
      venda.lucroTotal = venda.total - custoTotal;
      _aplicarPagamentoNoOrcamento(venda, pagamento, totalOrcamento: venda.total);
      final vendaId = _db.vendaBox.put(venda);
      venda.id = vendaId;

      for (final item in itens) {
        item.venda.target = venda;
        _db.itemVendaBox.put(item);
      }

      return vendaId;
    });
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
    return _db.store.runInTransaction(TxMode.write, () {
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
      final temPendencia =
          mae.itens.any((i) => i.quantidadePendenteRetirada > 0);
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

      final refMae =
          mae.numeroOrcamento > 0 ? '${mae.numeroOrcamento}' : '${mae.id}';
      final item = ItemVenda(
        nomeProduto: 'Frete carreto (ref. venda #$refMae)',
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
  }

  /// Agrupa entregas de carreto (mesmo cliente) para a equipe ver como um unico carregamento.
  void definirGrupoEntregaLogistica(Set<int> vendaIds) {
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
            v.tipoEntrega != 'entrega_loja') {
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
      for (final v in vendas) {
        v.grupoEntregaFreteId = grupoId;
        _db.vendaBox.put(v);
      }
    });
  }

  void limparGrupoEntregaLogisticaEm(Set<int> vendaIds) {
    _db.store.runInTransaction(TxMode.write, () {
      for (final id in vendaIds) {
        final v = _db.vendaBox.get(id);
        if (v == null) continue;
        v.grupoEntregaFreteId = 0;
        _db.vendaBox.put(v);
      }
    });
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
    final prefixo = '[${dataHora.day.toString().padLeft(2, '0')}/'
        '${dataHora.month.toString().padLeft(2, '0')}/'
        '${dataHora.year} ${dataHora.hour.toString().padLeft(2, '0')}:'
        '${dataHora.minute.toString().padLeft(2, '0')}]';
    final linha =
        '$prefixo CAIXA: Migrada para carreto apos pagamento do frete '
        '(orc. #${filho.numeroOrcamento}).';
    final atualObs = mae.observacaoEntrega.trim();
    mae.observacaoEntrega =
        atualObs.isEmpty ? linha : '$atualObs\n$linha';

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

      venda.tipoEntrega = entrega.tipoEntrega;
      venda.valorFrete = entrega.tipoEntrega == 'entrega_loja' ? entrega.valorFrete : 0;
      venda.enderecoEntrega = entrega.tipoEntrega == 'entrega_loja'
          ? entrega.enderecoEntrega
          : '';
      venda.observacaoEntrega = entrega.tipoEntrega == 'entrega_loja'
          ? entrega.observacaoEntrega
          : '';
      venda.statusEntrega = entrega.tipoEntrega == 'entrega_loja'
          ? 'pendente'
          : 'nao_aplicavel';
      venda.prioridadeEntrega = entrega.tipoEntrega == 'entrega_loja'
          ? entrega.prioridadeEntrega
          : 'normal';
      venda.janelaEntrega = entrega.tipoEntrega == 'entrega_loja'
          ? entrega.janelaEntrega
          : 'nao_definida';
      venda.dataEntregaMarcada = entrega.tipoEntrega == 'entrega_loja'
          ? entrega.dataEntregaMarcada
          : null;
      venda.entregaPendente = entrega.tipoEntrega == 'retirada_futura';

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
        final item = ItemVenda(
          nomeProduto: produto.nome,
          quantidade: input.quantidade,
          precoTipo: input.precoTipo,
          precoUnitario: input.precoUnitario,
          precoCustoUnitario: produto.precoCusto,
        );
        item.produto.target = produto;
        item.venda.target = venda;
        _db.itemVendaBox.put(item);
        total += item.subtotal;
        custoTotal += item.subtotalCusto;
      }

      if (venda.tipoEntrega == 'entrega_loja') {
        if (venda.valorFrete < 0) {
          throw StateError('Valor de frete nao pode ser negativo.');
        }
        if (venda.enderecoEntrega.trim().isEmpty) {
          throw StateError(
            'Endereco de entrega obrigatorio para carreto.',
          );
        }
      }

      venda.total = total + venda.valorFrete;
      venda.custoTotal = custoTotal;
      venda.lucroTotal = venda.total - custoTotal;
      _aplicarPagamentoNoOrcamento(venda, pagamento, totalOrcamento: venda.total);
      _db.vendaBox.put(venda);
    });
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
        if (venda.entregaPendente) {
          if (!permitirVendaSemEstoque) {
            for (final item in venda.itens) {
              final produto = item.produto.target;
              if (produto == null) {
                throw StateError('Produto do item ${item.id} nao encontrado.');
              }
              if (produto.estoqueReal < item.quantidade) {
                throw StateError(
                  'Estoque insuficiente para reservar ${produto.nome}.',
                );
              }
            }
          }
          for (final item in venda.itens) {
            final produto = item.produto.target;
            if (produto != null) {
              produto.estoqueReservado += item.quantidade;
              _db.produtoBox.put(produto);
            }
          }
        } else {
          for (final item in venda.itens) {
            final produto = item.produto.target;
            if (produto == null) {
              throw StateError('Produto do item ${item.id} nao encontrado.');
            }
            if (!permitirVendaSemEstoque &&
                produto.estoqueReal < item.quantidade) {
              throw StateError('Estoque insuficiente para ${produto.nome}.');
            }
          }
          for (final item in venda.itens) {
            final produto = item.produto.target;
            if (produto != null) {
              produto.estoqueReal -= item.quantidade;
              _db.produtoBox.put(produto);
            }
          }
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
  }

  void vincularClienteVendaFinalizada(int vendaId, int clienteId) {
    _db.store.runInTransaction(TxMode.write, () {
      final venda = _db.vendaBox.get(vendaId);
      if (venda == null) {
        throw StateError('Venda $vendaId nao encontrada.');
      }
      if (venda.status != 'finalizada') {
        throw StateError('Somente venda finalizada pode receber vinculo de cliente.');
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
      if (valorDesconto.isNaN || valorDesconto.isInfinite || valorDesconto < 0) {
        throw StateError('Valor de desconto invalido.');
      }
      final totalAntesDesconto = venda.total;
      final descontoAplicado = valorDesconto.clamp(0, venda.total).toDouble();
      venda.total = (venda.total - descontoAplicado).clamp(0, double.infinity)
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
      if (venda.tipoEntrega != 'entrega_loja') return false;
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

  void atualizarStatusEntrega(int vendaId, String novoStatus) {
    _db.store.runInTransaction(TxMode.write, () {
      final venda = _db.vendaBox.get(vendaId);
      if (venda == null) {
        throw StateError('Venda/Orcamento $vendaId nao encontrado.');
      }
      if (venda.tipoEntrega != 'entrega_loja') {
        throw StateError(
          'Somente pedidos de entrega podem ter status de entrega.',
        );
      }
      venda.statusEntrega = novoStatus;
      _db.vendaBox.put(venda);
    });
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
      if (venda.tipoEntrega != 'entrega_loja') {
        throw StateError('Somente entregas da loja possuem checklist de carga.');
      }
      if (separado != null) venda.cargaSeparada = separado;
      if (carregado != null) venda.cargaCarregada = carregado;
      if (saiu != null) venda.cargaSaiu = saiu;
      _db.vendaBox.put(venda);
    });
  }

  void atualizarMotoristaEntrega(int vendaId, String motorista) {
    _db.store.runInTransaction(TxMode.write, () {
      final venda = _db.vendaBox.get(vendaId);
      if (venda == null) {
        throw StateError('Venda/Orcamento $vendaId nao encontrado.');
      }
      if (venda.tipoEntrega != 'entrega_loja') {
        throw StateError('Somente entregas da loja possuem motorista.');
      }
      venda.motoristaEntrega = motorista.trim();
      _db.vendaBox.put(venda);
    });
  }

  int migrarMotoristaEntregaLegado() {
    return _db.store.runInTransaction(TxMode.write, () {
      final vendas = _db.vendaBox.getAll();
      var totalMigradas = 0;
      for (final venda in vendas) {
        if (venda.tipoEntrega != 'entrega_loja') continue;
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
      final quem = usuario.trim().isEmpty ? 'sistema' : usuario.trim();
      final dataHora = DateTime.now().toLocal();
      final prefixo = '[${dataHora.day.toString().padLeft(2, '0')}/'
          '${dataHora.month.toString().padLeft(2, '0')}/'
          '${dataHora.year} ${dataHora.hour.toString().padLeft(2, '0')}:'
          '${dataHora.minute.toString().padLeft(2, '0')}]';
      final linha = '$prefixo ${status.toUpperCase()} por $quem: $motivoLimpo';
      final atual = venda.observacaoEntrega.trim();
      venda.observacaoEntrega = atual.isEmpty ? linha : '$atual\n$linha';
      _db.vendaBox.put(venda);
    });
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

    final trecho = linhasLog.join('; ');
    var motivoFinal =
        trecho.isEmpty ? 'Retirada registrada.' : 'Retirada: $trecho';
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
  }
}
