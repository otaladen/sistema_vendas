import '../model/item_venda.dart';
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
  });

  final String tipoEntrega; // retirada | entrega_loja
  final double valorFrete;
  final String enderecoEntrega;
  final String observacaoEntrega;
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

  int registrarVenda(List<ItemVendaInput> itensInput) {
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
        if (produto.estoqueReal < input.quantidade) {
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

  void converterOrcamentoParaVenda(int vendaId) {
    _db.store.runInTransaction(TxMode.write, () {
      final venda = _db.vendaBox.get(vendaId);
      if (venda == null) {
        throw StateError('Orcamento $vendaId nao encontrado.');
      }
      if (venda.status != 'orcamento') {
        throw StateError('Somente orcamentos podem ser finalizados.');
      }

      if (venda.entregaPendente) {
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
          if (produto.estoqueReal < item.quantidade) {
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
    return listarTodas().where((venda) {
      if (venda.status != 'finalizada') return false;
      if (venda.tipoEntrega != 'entrega_loja') return false;
      if (statusEntrega != null &&
          statusEntrega != 'todos' &&
          venda.statusEntrega != statusEntrega) {
        return false;
      }
      if (inicio != null && venda.data.isBefore(inicio)) return false;
      if (fim != null && venda.data.isAfter(fim)) return false;
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

  void cancelarVenda(int vendaId) {
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
      _db.vendaBox.put(venda);
    });
  }
}
