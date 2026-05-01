import '../model/item_venda.dart';
import '../model/historico_entrega.dart';
import '../model/venda.dart';
import '../objectbox.g.dart';
import 'objectbox.dart';

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
  });

  final String formaPagamento;
  final int quantidadeParcelas;
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

  final String tipoEntrega; // retirada | entrega_loja
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
      final parcelas = pagamento.formaPagamento == 'cartao_credito'
          ? pagamento.quantidadeParcelas
          : 1;
      final venda = Venda(
        status: 'orcamento',
        numeroOrcamento: proximoNumero,
        formaPagamento: pagamento.formaPagamento,
        quantidadeParcelas: parcelas,
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
            'Endereco de entrega obrigatorio para entrega da loja.',
          );
        }
      }
      venda.total = total + venda.valorFrete;
      venda.custoTotal = custoTotal;
      venda.lucroTotal = venda.total - custoTotal;
      final vendaId = _db.vendaBox.put(venda);
      venda.id = vendaId;

      for (final item in itens) {
        item.venda.target = venda;
        _db.itemVendaBox.put(item);
      }

      return vendaId;
    });
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

      final parcelas = pagamento.formaPagamento == 'cartao_credito'
          ? pagamento.quantidadeParcelas
          : 1;
      venda.formaPagamento = pagamento.formaPagamento;
      venda.quantidadeParcelas = parcelas;
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
            'Endereco de entrega obrigatorio para entrega da loja.',
          );
        }
      }

      venda.total = total + venda.valorFrete;
      venda.custoTotal = custoTotal;
      venda.lucroTotal = venda.total - custoTotal;
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
          if (!permitirVendaSemEstoque && produto.estoqueReal < item.quantidade) {
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

      venda.status = 'finalizada';
      venda.cancelada = false;
      venda.motivoCancelamento = '';
      venda.canceladaPor = '';
      venda.canceladaEm = null;
      _db.vendaBox.put(venda);
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
      final descontoAplicado = valorDesconto.clamp(0, venda.total).toDouble();
      venda.total = (venda.total - descontoAplicado).clamp(0, double.infinity)
          .toDouble();
      venda.lucroTotal = venda.total - venda.custoTotal;
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

      if (venda.status == 'orcamento') {
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
