import 'dart:io';

import 'package:objectbox/objectbox.dart';
import 'package:path/path.dart' as p;

import '../data/objectbox.dart';
import '../data/produto_busca_util.dart';
import '../domain/complemento_entrega_codec.dart';
import '../domain/entrega_venda_helper.dart';
import '../domain/estoque/tipo_movimento_estoque.dart';
import '../domain/produto_estoque_sync.dart';
import '../model/item_venda.dart';
import '../model/produto.dart';
import '../model/venda.dart';
import '../objectbox.g.dart';
import 'compras_preditivas_service.dart';

/// Ponto unico de movimentacao de estoque no ObjectBox.
///
/// Regra: baixa fisica de venda no balcao ocorre no **cupom nao fiscal**, nao na
/// NFC-e/NF-e de venda. Reservas (carreto / retirada futura) seguem no orcamento
/// e na finalizacao; saida do carro e retiradas parciais usam tipos proprios.
class GerenciadorEstoqueService {
  GerenciadorEstoqueService(this._db);

  final ObjectBox _db;
  static bool _migracaoBaixadoCupomLegadoOk = false;

  // --- Persistencia e politica ---

  void persistirProduto(Produto produto, TipoMovimentoEstoque tipo) {
    if (tipo == TipoMovimentoEstoque.nfceEmissao ||
        tipo == TipoMovimentoEstoque.nfeVendaEmissao) {
      PoliticaMovimentoEstoque.validarNaoAlteraEstoque(tipo);
    }
    ProdutoEstoqueSync.marcarEstoqueAlterado(produto);
    _db.produtoBox.put(produto);
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
  void registrarEntradaPorNotaFiscal(Produto produto, num quantidade) {
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
    atual.estoqueReal += qtd;
    atual.estoqueAtual = atual.estoqueReal;
    persistirProduto(atual, TipoMovimentoEstoque.entradaNfeCompra);
    produto.estoqueReal = atual.estoqueReal;
    produto.estoqueAtual = atual.estoqueAtual;
    produto.estoqueVersao = atual.estoqueVersao;
  }

  /// Estorno da entrada de estoque de uma NF-e de compra ja lancada.
  void estornarEntradaPorNotaFiscal(Produto produto, num quantidade) {
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
    atual.estoqueReal = estoqueApos;
    atual.estoqueAtual = atual.estoqueReal;
    persistirProduto(atual, TipoMovimentoEstoque.estornoEntradaNfeCompra);
    produto.estoqueReal = atual.estoqueReal;
    produto.estoqueAtual = atual.estoqueAtual;
    produto.estoqueVersao = atual.estoqueVersao;
  }

  /// Ajuste direto de inventario (cadastro de produto, perda, quebra, balanco).
  void executarAjusteManualInventario(
    Produto produto,
    num novaQuantidadeFisica,
    String motivo,
  ) {
    if (produto.id <= 0) {
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
    final atual = _db.produtoBox.get(produto.id);
    if (atual == null) {
      throw StateError('Produto id ${produto.id} nao encontrado.');
    }
    if (alvo < atual.estoqueReservado) {
      throw StateError(
        'Novo fisico ($alvo) menor que o reservado (${atual.estoqueReservado}) '
        'em "${atual.nome}". Libere reservas antes do ajuste.',
      );
    }
    atual.estoqueReal = alvo;
    atual.estoqueAtual = alvo;
    persistirProduto(atual, TipoMovimentoEstoque.ajusteManual);
    produto.estoqueReal = atual.estoqueReal;
    produto.estoqueAtual = atual.estoqueAtual;
    produto.estoqueVersao = atual.estoqueVersao;
    produto.estoqueReservado = atual.estoqueReservado;
  }

  // --- Migracao legado cupom ---

  void migrarEstoqueBaixadoCupomLegadoUmaVez() {
    if (_migracaoBaixadoCupomLegadoOk) return;
    try {
      final flag = File(
        p.join(_db.storeDirectoryPath, '.migracao_estoque_baixado_cupom_v1'),
      );
      if (flag.existsSync()) {
        _migracaoBaixadoCupomLegadoOk = true;
        return;
      }
      _db.store.runInTransaction(TxMode.write, () {
        final query = _db.vendaBox
            .query(Venda_.status.equals('finalizada'))
            .build();
        try {
          for (final v in query.find()) {
            if (!v.estoqueBaixadoCupom) {
              v.estoqueBaixadoCupom = true;
              _db.vendaBox.put(v);
            }
          }
        } finally {
          query.close();
        }
      });
      flag.writeAsStringSync('ok');
      _migracaoBaixadoCupomLegadoOk = true;
    } catch (_) {
      // Proxima abertura tenta de novo.
    }
  }

  // --- Orcamento: reserva ---

  int quantidadeReservavelOrcamentoItem(ItemVenda item) {
    final tipo = EntregaVendaHelper.tipoEfetivoItem(item);
    if (tipo == EntregaVendaHelper.tipoRetirada) return 0;
    if (tipo == EntregaVendaHelper.tipoRetiradaFutura ||
        tipo == EntregaVendaHelper.tipoEntregaLoja) {
      return item.quantidade;
    }
    return 0;
  }

  void reservarEstoqueItemOrcamento({
    required ItemVenda item,
    required bool permitirVendaSemEstoque,
  }) {
    final q = quantidadeReservavelOrcamentoItem(item);
    if (q <= 0) return;
    final produto = item.produto.target;
    if (produto == null) {
      throw StateError('Produto do item "${item.nomeProduto}" nao encontrado.');
    }
    if (!permitirVendaSemEstoque && produto.estoqueLivreParaVenda < q) {
      throw StateError(
        'Estoque insuficiente para reservar ${produto.nome} '
        '(livre ${produto.estoqueLivreParaVenda}, necessario $q).',
      );
    }
    produto.estoqueReservado += q;
    if (EntregaVendaHelper.tipoEfetivoItem(item) ==
        EntregaVendaHelper.tipoEntregaLoja) {
      item.quantidadeNoCarreto = q;
      _db.itemVendaBox.put(item);
    }
    persistirProduto(produto, TipoMovimentoEstoque.orcamentoReserva);
  }

  void liberarReservaEstoqueItemOrcamento(ItemVenda item) {
    final q = quantidadeReservavelOrcamentoItem(item);
    if (q <= 0) return;
    final produto = item.produto.target;
    if (produto == null) return;
    final reservadoAtual = produto.estoqueReservado;
    produto.estoqueReservado =
        (reservadoAtual - q).clamp(0, reservadoAtual).toInt();
    if (EntregaVendaHelper.tipoEfetivoItem(item) ==
            EntregaVendaHelper.tipoEntregaLoja &&
        item.quantidadeNoCarreto > 0) {
      item.quantidadeNoCarreto = 0;
      _db.itemVendaBox.put(item);
    }
    persistirProduto(produto, TipoMovimentoEstoque.orcamentoLiberaReserva);
  }

  void liberarReservaEstoqueOrcamento(Venda venda) {
    for (final item in venda.itens) {
      liberarReservaEstoqueItemOrcamento(item);
    }
  }

  // --- Finalizacao caixa (reserva; retirada imediata no cupom) ---

  void ajustarReservaEstoqueAoFinalizarItem({
    required ItemVenda item,
    required bool permitirVendaSemEstoque,
  }) {
    final produto = item.produto.target;
    if (produto == null) {
      throw StateError('Produto do item "${item.nomeProduto}" nao encontrado.');
    }
    final q = item.quantidade;
    if (q <= 0) return;

    final tipo = EntregaVendaHelper.tipoEfetivoItem(item);
    if (tipo == EntregaVendaHelper.tipoRetirada) {
      if (!permitirVendaSemEstoque && produto.estoqueLivreParaVenda < q) {
        throw StateError('Estoque insuficiente para ${produto.nome}.');
      }
      return;
    }

    if (!permitirVendaSemEstoque && produto.estoqueLivreParaVenda < q) {
      throw StateError('Estoque insuficiente para ${produto.nome}.');
    }

    switch (tipo) {
      case EntregaVendaHelper.tipoRetiradaFutura:
        if (produto.estoqueReservado < q) {
          final falta = q - produto.estoqueReservado;
          if (!permitirVendaSemEstoque &&
              produto.estoqueLivreParaVenda < falta) {
            throw StateError(
              'Reserva de estoque insuficiente para ${produto.nome}.',
            );
          }
          produto.estoqueReservado += falta;
          persistirProduto(
            produto,
            TipoMovimentoEstoque.finalizacaoAjustaReserva,
          );
        }
        break;
      case EntregaVendaHelper.tipoEntregaLoja:
        if (produto.estoqueReservado < q) {
          final falta = q - produto.estoqueReservado;
          if (!permitirVendaSemEstoque &&
              produto.estoqueLivreParaVenda < falta) {
            throw StateError(
              'Reserva de estoque insuficiente para ${produto.nome}.',
            );
          }
          produto.estoqueReservado += falta;
        }
        item.quantidadeNoCarreto = q;
        _db.itemVendaBox.put(item);
        persistirProduto(
          produto,
          TipoMovimentoEstoque.finalizacaoAjustaReserva,
        );
        break;
      default:
        break;
    }
  }

  // --- Cupom nao fiscal ---

  void baixarEstoqueRetiradaImediataCupomNaoFiscal({
    required ItemVenda item,
    required bool permitirVendaSemEstoque,
    Map<int, int>? consumoVendasPrecalculado,
  }) {
    if (EntregaVendaHelper.tipoEfetivoItem(item) !=
        EntregaVendaHelper.tipoRetirada) {
      return;
    }
    final produto = item.produto.target;
    if (produto == null) {
      throw StateError('Produto do item "${item.nomeProduto}" nao encontrado.');
    }
    final q = item.quantidade;
    if (q <= 0) return;
    if (item.quantidadeJaRetirada >= q) return;

    if (!permitirVendaSemEstoque && produto.estoqueLivreParaVenda < q) {
      throw StateError('Estoque insuficiente para ${produto.nome}.');
    }

    PoliticaMovimentoEstoque.validarPermiteAlteracaoFisica(
      TipoMovimentoEstoque.cupomNaoFiscalVenda,
    );
    produto.estoqueReal -= q;
    item.quantidadeJaRetirada = q;
    _db.itemVendaBox.put(item);
    persistirProduto(produto, TipoMovimentoEstoque.cupomNaoFiscalVenda);
    ComprasPreditivasService(_db).atualizarAposVendaRegistrada(
      produto: produto,
      quantidadeVendida: q,
      estoqueRealJaAbatido: true,
      consumoPrecalculado: consumoVendasPrecalculado,
    );
  }

  void registrarBaixaEstoqueCupomNaoFiscal({
    required Venda venda,
    required bool permitirVendaSemEstoque,
  }) {
    if (venda.status != 'finalizada' || venda.cancelada) {
      throw StateError(
        'Somente vendas finalizadas ativas recebem baixa de cupom nao fiscal.',
      );
    }
    if (venda.estoqueBaixadoCupom) return;

    final consumo =
        ComprasPreditivasService(_db).montarConsumoPorProdutoNoPeriodo();
    for (final item in venda.itens) {
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
    if (!permitirVendaSemEstoque &&
        produto.estoqueLivreParaVenda < quantidade) {
      throw StateError('Estoque insuficiente para ${produto.nome}.');
    }
    PoliticaMovimentoEstoque.validarPermiteAlteracaoFisica(
      TipoMovimentoEstoque.vendaDiretaLegada,
    );
    produto.estoqueReal -= quantidade;
    persistirProduto(produto, TipoMovimentoEstoque.vendaDiretaLegada);
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
      persistirProduto(produto, TipoMovimentoEstoque.carretoSaida);
      item.quantidadeJaRetirada += q;
      _db.itemVendaBox.put(item);
    }
  }

  // --- Carreto ---

  static int quantidadeItemParaEstoqueCarreto(ItemVenda item) {
    if (EntregaVendaHelper.itemMigradoRetiradaFuturaParaCarreto(item)) {
      return item.quantidadeNoCarreto;
    }
    if (EntregaVendaHelper.tipoEfetivoItem(item) !=
        EntregaVendaHelper.tipoEntregaLoja) {
      return 0;
    }
    return item.quantidadeAindaNoCarretoAntesSaida;
  }

  void validarEstoqueAntesDespachoCarreto(Venda venda) {
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
      if (produto.estoqueReal < q) {
        falhas.add(
          '${e.value.nome}: fisico ${produto.estoqueReal}, '
          'necessario $q para saida do carro.',
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

  void baixarEstoqueCarretoAoMarcarSaida(Venda venda) {
    for (final item in venda.itens) {
      final produto = item.produto.target;
      if (produto == null) continue;
      final q = quantidadeItemParaEstoqueCarreto(item);
      if (q <= 0) continue;

      final qReserva = q.clamp(0, produto.estoqueReservado);
      if (qReserva <= 0) continue;

      produto.estoqueReservado -= qReserva;
      produto.estoqueReal -= qReserva;
      persistirProduto(produto, TipoMovimentoEstoque.carretoSaida);
    }
  }

  void estornarBaixaEstoqueCarretoAoDesmarcarSaida(
    Venda venda, {
    required String complementoEntregaJson,
  }) {
    for (final item in venda.itens) {
      final produto = item.produto.target;
      if (produto == null) continue;
      var q = quantidadeItemParaEstoqueCarreto(item);
      if (q <= 0) continue;
      if (venda.statusEntrega == 'entregue_complemento_pendente' &&
          complementoEntregaJson.trim().isNotEmpty) {
        final m = _quantidadeComplementoDeclaradaPorItem(
          complementoEntregaJson,
          item.id,
        );
        q -= m;
        if (q < 0) q = 0;
      }
      if (q <= 0) continue;
      produto.estoqueReal += q;
      produto.estoqueReservado += q;
      persistirProduto(produto, TipoMovimentoEstoque.carretoEstornoSaida);
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
      final produto = item.produto.target;
      if (produto == null) {
        throw StateError('Produto do item ${item.id} nao encontrado.');
      }
      produto.estoqueReservado += e.value;
      produto.estoqueReal += e.value;
      persistirProduto(produto, TipoMovimentoEstoque.complementoEntregaFalta);
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
      persistirProduto(produto, TipoMovimentoEstoque.complementoEntregaBaixa);
    }
  }

  // --- Retirada futura / loja pre-saida ---

  void recomporEstoqueAoMarcarEntregaPendente(Venda venda) {
    for (final item in venda.itens) {
      final produto = item.produto.target;
      if (produto == null) {
        throw StateError('Produto do item ${item.id} nao encontrado.');
      }
      produto.estoqueReal += item.quantidade;
      produto.estoqueReservado += item.quantidade;
      persistirProduto(produto, TipoMovimentoEstoque.retiradaTotalImediata);
    }
  }

  void baixarReservaEFisicoRetirada({
    required ItemVenda item,
    required int quantidade,
    required TipoMovimentoEstoque tipo,
    required bool permitirSemConferenciaEstoque,
  }) {
    if (quantidade <= 0) return;
    final produto = item.produto.target;
    if (produto == null) {
      throw StateError('Produto do item ${item.id} nao encontrado.');
    }
    if (!permitirSemConferenciaEstoque) {
      if (produto.estoqueReal < quantidade) {
        throw StateError(
          'Estoque fisico insuficiente para retirar $quantidade de ${produto.nome}.',
        );
      }
      if (produto.estoqueReservado < quantidade) {
        throw StateError(
          'Estoque reservado inconsistente para ${produto.nome}.',
        );
      }
    }
    PoliticaMovimentoEstoque.validarPermiteAlteracaoFisica(tipo);
    produto.estoqueReal -= quantidade;
    produto.estoqueReservado -= quantidade;
    persistirProduto(produto, tipo);
  }

  // --- Cancelamento ---

  void estornarEstoqueAoCancelarVenda(Venda venda) {
    for (final item in venda.itens) {
      final produto = item.produto.target;
      if (produto == null) continue;

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
          final qReserva = quantidadeItemParaEstoqueCarreto(item);
          final reservadoAtual = produto.estoqueReservado;
          produto.estoqueReservado = (reservadoAtual - qReserva)
              .clamp(0, reservadoAtual)
              .toInt();
        }
      } else if (venda.estoqueBaixadoCupom ||
          EntregaVendaHelper.tipoEfetivoItem(item) !=
              EntregaVendaHelper.tipoRetirada) {
        produto.estoqueReal += item.quantidade;
      }
      persistirProduto(produto, TipoMovimentoEstoque.cancelamentoVendaEstorno);
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
    persistirProduto(produto, TipoMovimentoEstoque.devolucaoCliente);
  }

  void baixarEstoqueSaidaTroca({
    required Produto produto,
    required int quantidade,
    required bool permitirVendaSemEstoque,
  }) {
    if (quantidade <= 0) return;
    if (!permitirVendaSemEstoque && produto.estoqueReal < quantidade) {
      throw StateError(
        'Estoque insuficiente na troca para ${produto.nome} (precisa $quantidade).',
      );
    }
    PoliticaMovimentoEstoque.validarPermiteAlteracaoFisica(
      TipoMovimentoEstoque.devolucaoCliente,
    );
    produto.estoqueReal -= quantidade;
    persistirProduto(produto, TipoMovimentoEstoque.devolucaoCliente);
  }
}
