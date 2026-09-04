import 'dart:async';

import '../domain/auditoria_catalogo.dart';
import '../domain/cancelada_por_rotulo.dart';
import '../domain/complemento_entrega_codec.dart';
import '../domain/entrega_filtro_util.dart';
import '../domain/entrega_lista_api.dart';
import '../data/conferencia_carga_repository.dart';
import '../domain/entregas/conferencia_carga_validacao.dart';
import '../domain/entrega_venda_helper.dart';
import '../domain/entregas/loja_origem_mercadoria.dart';
import '../domain/entregas/buscar_na_loja.dart';
import 'loja_origem_rede_store.dart';
import '../domain/entrega_nao_entregue.dart';
import '../domain/entrega_status_transicao.dart';
import '../domain/item_venda_produto_orfao.dart';
import '../services/entrega_fluxo_service.dart';
import '../domain/operacao_permissao_guard.dart';
import '../domain/entregas/agenda_carreto_ocupacao.dart';
import '../domain/filtro_listagem_entregas.dart';
import '../domain/limite_credito_helper.dart';
import '../config/fiscal_config.dart';
import '../domain/fiscal/fiscal_emissao_lock.dart';
import '../domain/fiscal/focus_documento_fiscal_url.dart';
import '../domain/fiscal/nfce_xml_local_service.dart';
import '../domain/fiscal/nfe_xml_local_service.dart';
import '../domain/fiscal/venda_nfce_obrigatoria_helper.dart';
import '../domain/estoque/tipo_movimento_estoque.dart';
import '../domain/pagamento_orcamento.dart';
import '../domain/plano_fiado.dart';
import '../domain/produto_coocorrencia_venda.dart';
import '../domain/promocao_cadastro.dart';
import '../domain/retirada_parcial_evento.dart';
import '../domain/saldo_retirada_item.dart';
import '../domain/promocao_preco_service.dart';
import '../domain/ultimas_vendas_finalizadas_ordenacao.dart';
import '../domain/venda_finalizacao_caixa_helper.dart';
import '../domain/caixa_meio_pagamento_fechamento.dart';
import '../domain/troca_diferenca_caixa.dart';
import 'promocao_repository.dart';
import '../services/auditoria_registrar.dart';
import '../services/compras_preditivas_service.dart';
import '../services/gerenciador_estoque_service.dart';
import '../model/item_venda.dart';
import '../model/historico_entrega.dart';
import '../model/linha_devolucao_entrada.dart';
import '../model/linha_troca_saida.dart';
import '../model/produto.dart';
import '../model/registro_devolucao.dart';
import '../model/usuario_sistema.dart';
import '../model/venda.dart';
import '../objectbox.g.dart';
import 'objectbox.dart';
import 'nfe_saida_fiscal_store.dart';
import 'recebimento_fiado_repository.dart';
import 'sync/sync_write_trigger.dart';
import 'titulo_receber_repository.dart';
import 'vale_credito_repository.dart';

/// Totais por meio de pagamento no periodo do caixa.
class TotaisMeiosPagamentoCaixa {
  const TotaisMeiosPagamentoCaixa({
    required this.dinheiro,
    required this.pix,
    required this.debito,
    required this.credito,
    this.vale = 0,
  });

  final double dinheiro;
  final double pix;
  final double debito;
  final double credito;

  /// Vale de credito: soma no total de vendas, mas nao na gaveta.
  final double vale;
}

/// Resumo de vendas finalizadas no periodo do caixa.
class ResumoVendasCaixaPeriodo {
  const ResumoVendasCaixaPeriodo({
    required this.totalVendas,
    required this.quantidadeVendas,
  });

  final double totalVendas;
  final int quantidadeVendas;
}

/// Resultado de [VendaRepository.limparAbaEntregasCancelandoVendas].
class ResultadoLimpezaAbaEntregas {
  const ResultadoLimpezaAbaEntregas({
    required this.canceladas,
    required this.forcadas,
    required this.falhas,
    required this.conferenciasRemovidas,
    required this.historicosRemovidos,
  });

  final int canceladas;
  /// Canceladas apenas com flag (sem estorno de estoque) quando o cancelamento normal falhou.
  final int forcadas;
  final List<String> falhas;
  final int conferenciasRemovidas;
  final int historicosRemovidos;
}

void _marcarUltimaVendaNosProdutos(ObjectBox db, Iterable<ItemVenda> itens) {
  final agora = DateTime.now().toUtc();
  // Relê do box e deduplica: varios itens podem apontar para o mesmo
  // Produto em memoria com estoqueReservado desatualizado (ex.: misto
  // leva+futura). Gravar a instancia stale apaga a reserva recem-feita.
  final vistos = <int>{};
  for (final item in itens) {
    final pid = item.produto.targetId;
    if (pid <= 0 || !vistos.add(pid)) continue;
    final produto = db.produtoBox.get(pid);
    if (produto == null) continue;
    produto.ultimaVendaEm = agora;
    db.produtoBox.put(produto);
    item.produto.target = produto;
  }
}

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

void _aplicarPlanoFiadoNoOrcamento(
  Venda venda, {
  List<PlanoFiadoParcela>? planoFiado,
}) {
  final valorFiado = LimiteCreditoHelper.valorFiadoNaVenda(venda);
  if (valorFiado <= 0.001) {
    venda.planoFiadoJson = '';
    return;
  }
  final parcelas = planoFiado ?? PlanoFiadoCodec.decode(venda.planoFiadoJson);
  if (!PlanoFiadoCodec.validarContraValor(parcelas, valorFiado)) {
    throw StateError(
      'Plano de parcelas do fiado invalido. A soma das parcelas deve igualar '
      'o valor fiado (${valorFiado.toStringAsFixed(2)}).',
    );
  }
  venda.planoFiadoJson = PlanoFiadoCodec.encode(parcelas);
}

class PeriodoFiltro {
  PeriodoFiltro({required this.inicio, required this.fim});

  final DateTime inicio;
  final DateTime fim;
}

/// Linha de saida do produto em vendas finalizadas (relatorio por periodo).
class VendaPromocaoRelatorioLinha {
  const VendaPromocaoRelatorioLinha({
    required this.dataVenda,
    required this.vendaId,
    required this.nota,
    required this.promocaoId,
    required this.promocaoNome,
    required this.produtoNome,
    required this.codigoInterno,
    required this.quantidade,
    required this.valorUnitario,
    required this.total,
    required this.lucro,
    required this.clienteNome,
    required this.itemVendaId,
  });

  final DateTime dataVenda;
  final int vendaId;
  final int nota;
  final int promocaoId;
  final String promocaoNome;
  final String produtoNome;
  final String codigoInterno;
  final int quantidade;
  final double valorUnitario;
  final double total;
  final double lucro;
  final String clienteNome;
  final int itemVendaId;
}

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
    this.promocaoId = 0,
    this.promocaoNomeSnapshot = '',
    this.precoUnitarioManual = false,
    this.botaForaAplicado = false,
    this.percentualBotaForaAplicado = 0,
  });

  final int produtoId;
  final int quantidade;
  final double precoUnitario;
  final String precoTipo;
  final String tipoEntregaItem;
  final int promocaoId;
  final String promocaoNomeSnapshot;
  final bool precoUnitarioManual;
  final bool botaForaAplicado;
  final double percentualBotaForaAplicado;
}

void validarItemVendaInput(ItemVendaInput input) {
  if (input.produtoId <= 0) {
    throw ArgumentError('Produto invalido no item da venda.');
  }
  if (input.quantidade <= 0) {
    throw ArgumentError('Quantidade deve ser maior que zero.');
  }
  if (input.precoUnitario < 0) {
    throw ArgumentError('Preco unitario nao pode ser negativo.');
  }
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
    promocaoId: input.promocaoId,
    promocaoNomeSnapshot: input.promocaoNomeSnapshot,
    precoUnitarioManual: input.precoUnitarioManual,
    botaForaAplicado: input.botaForaAplicado,
    percentualBotaForaAplicado: input.percentualBotaForaAplicado,
  );
}

void _aplicarDadosEntregaOrcamentoNaVenda(
  Venda venda,
  DadosEntregaOrcamento entrega,
  List<ItemVendaInput> itensInput,
) {
  final tipos = itensInput.map(
    (i) => EntregaVendaHelper.normalizarTipoItem(i.tipoEntregaItem),
  );
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
    required this.porClienteLucro,
    required this.porVendaFaturamento,
    required this.porVendaLucro,
  });

  /// Negativo em devolucao pura; troca pode ser misto (saida - entrada).
  final double impactoFaturamentoTotal;

  /// Aproxima lucro: entrada usa custo do item da venda; saida troca usa custo da linha.
  final double impactoLucroTotal;

  final Map<int, double> porVendedorFaturamento;
  final Map<int, double> porVendedorLucro;
  final Map<int, double> porClienteFaturamento;
  final Map<int, double> porClienteLucro;
  final Map<int, double> porVendaFaturamento;
  final Map<int, double> porVendaLucro;
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
    this.planoFiado,
  });

  final String formaPagamento;
  final int quantidadeParcelas;

  /// Quando preenchido (2+ linhas ou modo misto), [formaPagamento] deve ser `misto`.
  final List<PagamentoOrcamentoLinha>? linhasMisto;

  /// Parcelas e vencimentos do fiado (obrigatorio no PDV quando ha fiado).
  final List<PlanoFiadoParcela>? planoFiado;
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
    this.filtroFiscal = 'todos',
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

  /// `todos` | `sem_nfce_eletronico`
  final String filtroFiscal;
  final int? clienteId;
  final int? vendedorId;
}

/// Pagina da listagem de vendas + total de linhas que obedecem ao [FiltroListagemVendas].
class ListagemVendasPagina {
  const ListagemVendasPagina({
    required this.vendas,
    required this.total,
    this.totalValor = 0,
  });

  final List<Venda> vendas;
  final int total;

  /// Soma de [Venda.total] de **todas** as linhas do filtro, nao so da pagina.
  final double totalValor;
}

class VendaRepository {
  VendaRepository(this._db, {void Function()? onAposEscrita})
    : _onAposEscrita = onAposEscrita {
    titulos = TituloReceberRepository(_db);
    recebimentos = RecebimentoFiadoRepository(_db, titulos);
  }

  final ObjectBox _db;
  final void Function()? _onAposEscrita;
  late final TituloReceberRepository titulos;
  late final RecebimentoFiadoRepository recebimentos;
  late final GerenciadorEstoqueService _estoque = GerenciadorEstoqueService(_db);
  late final ConferenciaCargaRepository _conferenciaCarga =
      ConferenciaCargaRepository(_db);
  late final ValeCreditoRepository _vales = ValeCreditoRepository(_db);

  ObjectBox get objectBox => _db;

  void _notificarRedeAposEscrita({
    int? vendaId,
    Iterable<int>? vendaIds,
    bool estoqueAlterado = false,
    Iterable<int>? produtoIds,
  }) {
    _onAposEscrita?.call();
    if (vendaIds != null) {
      var algum = false;
      for (final id in vendaIds) {
        if (id <= 0) continue;
        algum = true;
        notificarAlteracaoParaRede(entidade: 'venda', entidadeId: id);
      }
      if (!algum) {
        notificarAlteracaoParaRede(
          entidade: 'venda',
          entidadeId: vendaId ?? 0,
        );
      }
    } else {
      notificarAlteracaoParaRede(
        entidade: 'venda',
        entidadeId: vendaId ?? 0,
      );
    }
    if (estoqueAlterado) {
      final ids = produtoIds?.where((id) => id > 0).toList() ?? const <int>[];
      notificarAlteracaoParaRede(
        entidade: 'produto',
        entidadeId: ids.length == 1 ? ids.first : 0,
        entidadeIds: ids.isEmpty ? null : ids,
      );
    }
  }

  Set<int> _produtoIdsDaVenda(Venda venda) {
    final ids = <int>{};
    for (final item in venda.itens) {
      final pid = item.produto.targetId;
      if (pid > 0) ids.add(pid);
    }
    return ids;
  }

  Set<int> _produtoIdsPorVendaId(int vendaId) {
    return listarItensPorVenda(vendaId)
        .map((i) => i.produto.targetId)
        .where((id) => id > 0)
        .toSet();
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

  /// Ultimas vendas finalizadas ativas (consulta limitada no ObjectBox).
  List<Venda> listarUltimasVendasFinalizadas({
    int limit = 20,
    UltimasVendasFinalizadasOrdenacao ordenacao =
        UltimasVendasFinalizadasOrdenacao.padrao,
  }) {
    if (limit <= 0) return const [];
    switch (ordenacao) {
      case UltimasVendasFinalizadasOrdenacao.porControle:
        return _listarUltimasFinalizadasPorControle(limit);
      case UltimasVendasFinalizadasOrdenacao.porFinalizacao:
        return _listarUltimasFinalizadasPorFinalizacaoCaixa(limit);
    }
  }

  List<Venda> _listarUltimasFinalizadasPorControle(int limit) {
    final query = _db.vendaBox
        .query(
          Venda_.status
              .equals('finalizada')
              .and(Venda_.cancelada.equals(false)),
        )
        .order(Venda_.numeroOrcamento, flags: Order.descending)
        .build();
    try {
      query.limit = (limit * 3).clamp(limit, 120);
      final lista = query.find();
      lista.sort((a, b) {
        final na = a.numeroOrcamento > 0 ? a.numeroOrcamento : a.id;
        final nb = b.numeroOrcamento > 0 ? b.numeroOrcamento : b.id;
        final cmp = nb.compareTo(na);
        if (cmp != 0) return cmp;
        return b.id.compareTo(a.id);
      });
      return lista.take(limit).toList();
    } finally {
      query.close();
    }
  }

  List<Venda> _listarUltimasFinalizadasPorFinalizacaoCaixa(int limit) {
    final base = Venda_.status
        .equals('finalizada')
        .and(Venda_.cancelada.equals(false));
    final pool = <int, Venda>{};

    void absorver(Query<Venda> query) {
      try {
        for (final v in query.find()) {
          pool.putIfAbsent(v.id, () => v);
        }
      } finally {
        query.close();
      }
    }

    absorver(
      _db.vendaBox
          .query(base)
          .order(Venda_.finalizadaEm, flags: Order.descending)
          .build()
        ..limit = (limit * 8).clamp(limit, 240),
    );
    absorver(
      _db.vendaBox
          .query(base)
          .order(Venda_.cupomNaoFiscalEmitidoEm, flags: Order.descending)
          .build()
        ..limit = (limit * 4).clamp(limit, 120),
    );

    final lista = pool.values.toList()
      ..sort((a, b) {
        final cmp = VendaFinalizacaoCaixaHelper.momentoFinalizacao(b)
            .compareTo(VendaFinalizacaoCaixaHelper.momentoFinalizacao(a));
        if (cmp != 0) return cmp;
        return b.id.compareTo(a.id);
      });
    return lista.take(limit).toList();
  }

  /// Corrige registros em que [Venda.finalizadaEm] foi copiado da data do orcamento.
  void corrigirFinalizadaEmCopiadaDaDataOrcamento() {
    _db.store.runInTransaction(TxMode.write, () {
      final query = _db.vendaBox
          .query(
            Venda_.status
                .equals('finalizada')
                .and(Venda_.cancelada.equals(false)),
          )
          .build();
      try {
        for (final venda in query.find()) {
          if (!VendaFinalizacaoCaixaHelper.ehFinalizadaEmCopiaDaDataOrcamento(
            venda,
          )) {
            continue;
          }
          venda.finalizadaEm = null;
          _db.vendaBox.put(venda);
        }
      } finally {
        query.close();
      }
    });
  }

  /// Vendas finalizadas a partir de [desde] (painel NF-e / pendencias).
  List<Venda> listarVendasFinalizadasDesde(
    DateTime desde, {
    int limit = 100,
  }) {
    if (limit <= 0) return const [];
    final inicioUtc = DateTime(desde.year, desde.month, desde.day).toUtc();
    final query = _db.vendaBox
        .query(
          Venda_.status
              .equals('finalizada')
              .and(Venda_.cancelada.equals(false))
              .and(Venda_.data.greaterOrEqualDate(inicioUtc)),
        )
        .order(Venda_.data, flags: Order.descending)
        .build();
    try {
      query.limit = limit;
      return query.find();
    } finally {
      query.close();
    }
  }

  /// Data da venda finalizada mais recente (relógio do sistema / caixa).
  DateTime? dataUltimaVendaFinalizada() {
    final ultimas = listarUltimasVendasFinalizadas(limit: 1);
    if (ultimas.isEmpty) return null;
    final v = ultimas.first;
    return VendaFinalizacaoCaixaHelper.momentoFinalizacao(v);
  }

  /// Orcamento pendente pelo numero exibido ao cliente.
  Venda? buscarOrcamentoPendentePorNumero(int numero) {
    if (numero <= 0) return null;
    final query = _db.vendaBox
        .query(
          Venda_.status
              .equals('orcamento')
              .and(Venda_.cancelada.equals(false))
              .and(Venda_.numeroOrcamento.equals(numero)),
        )
        .build();
    try {
      return query.findFirst();
    } finally {
      query.close();
    }
  }

  /// Segunda via: busca por numero do orcamento ou id interno da venda.
  Venda? buscarVendaFinalizadaPorNumeroOuId(int numeroOuId) {
    if (numeroOuId <= 0) return null;
    final porNumero = _db.vendaBox
        .query(
          Venda_.status
              .equals('finalizada')
              .and(Venda_.cancelada.equals(false))
              .and(Venda_.numeroOrcamento.equals(numeroOuId)),
        )
        .build();
    try {
      final v = porNumero.findFirst();
      if (v != null) return v;
    } finally {
      porNumero.close();
    }
    final porId = obterPorId(numeroOuId);
    if (porId == null ||
        porId.status != 'finalizada' ||
        porId.cancelada) {
      return null;
    }
    return porId;
  }

  /// Totais por meio de pagamento no periodo (fechamento de caixa).
  ///
  /// Periodo usa [Venda.finalizadaEm] (via [VendaFinalizacaoCaixaHelper]),
  /// nao a data de criacao do orcamento.
  TotaisMeiosPagamentoCaixa totaisMeiosPagamentoVendasFinalizadas({
    DateTime? inicio,
    DateTime? fim,
  }) {
    var dinheiro = 0.0;
    var pix = 0.0;
    var debito = 0.0;
    var credito = 0.0;
    var vale = 0.0;
    final query = _db.vendaBox
        .query(_condicaoCandidatasCaixaPeriodo(inicio: inicio, fim: fim))
        .build();
    try {
      for (final venda in query.find()) {
        if (!_vendaFinalizadaNoPeriodoCaixa(venda, inicio: inicio, fim: fim)) {
          continue;
        }
        _acumularTotaisMeioPagamentoVenda(
          venda,
          onDinheiro: (v) => dinheiro += v,
          onPix: (v) => pix += v,
          onDebito: (v) => debito += v,
          onCredito: (v) => credito += v,
          onVale: (v) => vale += v,
        );
      }
    } finally {
      query.close();
    }
    return TotaisMeiosPagamentoCaixa(
      dinheiro: dinheiro,
      pix: pix,
      debito: debito,
      credito: credito,
      vale: vale,
    );
  }

  /// Soma e contagem de vendas finalizadas no periodo (painel do caixa).
  ResumoVendasCaixaPeriodo resumoVendasFinalizadasNoPeriodo({
    DateTime? inicio,
    DateTime? fim,
  }) {
    var totalVendas = 0.0;
    var quantidadeVendas = 0;
    final query = _db.vendaBox
        .query(_condicaoCandidatasCaixaPeriodo(inicio: inicio, fim: fim))
        .build();
    try {
      for (final venda in query.find()) {
        if (!_vendaFinalizadaNoPeriodoCaixa(venda, inicio: inicio, fim: fim)) {
          continue;
        }
        totalVendas += venda.total;
        quantidadeVendas++;
      }
    } finally {
      query.close();
    }
    return ResumoVendasCaixaPeriodo(
      totalVendas: totalVendas,
      quantidadeVendas: quantidadeVendas,
    );
  }

  /// Janela larga no ObjectBox; o corte fino e [_vendaFinalizadaNoPeriodoCaixa].
  Condition<Venda> _condicaoCandidatasCaixaPeriodo({
    DateTime? inicio,
    DateTime? fim,
  }) {
    var c = Venda_.status
        .equals('finalizada')
        .and(Venda_.cancelada.equals(false));
    if (inicio == null && fim == null) return c;

    // Padding de fuso: finalizadaEm/data gravados em UTC vs abertura local.
    final iniPad = inicio?.toUtc().subtract(const Duration(hours: 14));
    final fimPad = fim?.toUtc().add(const Duration(hours: 14));

    Condition<Venda> porFinalizada;
    Condition<Venda> porData;
    Condition<Venda> porCupom;
    if (iniPad != null && fimPad != null) {
      porFinalizada = Venda_.finalizadaEm
          .greaterOrEqualDate(iniPad)
          .and(Venda_.finalizadaEm.lessOrEqualDate(fimPad));
      porData = Venda_.data
          .greaterOrEqualDate(iniPad)
          .and(Venda_.data.lessOrEqualDate(fimPad));
      porCupom = Venda_.cupomNaoFiscalEmitidoEm
          .greaterOrEqualDate(iniPad)
          .and(Venda_.cupomNaoFiscalEmitidoEm.lessOrEqualDate(fimPad));
    } else if (iniPad != null) {
      porFinalizada = Venda_.finalizadaEm.greaterOrEqualDate(iniPad);
      porData = Venda_.data.greaterOrEqualDate(iniPad);
      porCupom = Venda_.cupomNaoFiscalEmitidoEm.greaterOrEqualDate(iniPad);
    } else {
      porFinalizada = Venda_.finalizadaEm.lessOrEqualDate(fimPad!);
      porData = Venda_.data.lessOrEqualDate(fimPad);
      porCupom = Venda_.cupomNaoFiscalEmitidoEm.lessOrEqualDate(fimPad);
    }
    return c.and(porFinalizada.or(porData).or(porCupom));
  }

  bool _vendaFinalizadaNoPeriodoCaixa(
    Venda venda, {
    DateTime? inicio,
    DateTime? fim,
  }) {
    final m = VendaFinalizacaoCaixaHelper.momentoFinalizacao(venda);
    if (inicio != null && m.isBefore(inicio.toUtc())) return false;
    if (fim != null && m.isAfter(fim.toUtc())) return false;
    return true;
  }

  void _acumularTotaisMeioPagamentoVenda(
    Venda venda, {
    required void Function(double valor) onDinheiro,
    required void Function(double valor) onPix,
    required void Function(double valor) onDebito,
    required void Function(double valor) onCredito,
    void Function(double valor)? onVale,
  }) {
    void aplicar(String? meio, double valor) {
      if (valor <= 0) return;
      switch (CaixaMeioPagamentoFechamento.bucket(meio)) {
        case CaixaMeioPagamentoFechamento.bucketDinheiro:
          onDinheiro(valor);
          break;
        case CaixaMeioPagamentoFechamento.bucketPix:
          onPix(valor);
          break;
        case CaixaMeioPagamentoFechamento.bucketDebito:
          onDebito(valor);
          break;
        case CaixaMeioPagamentoFechamento.bucketCredito:
          onCredito(valor);
          break;
        case CaixaMeioPagamentoFechamento.bucketVale:
          onVale?.call(valor);
          break;
        default:
          // fiado / transferencia / outros / desconhecido: fora da gaveta.
          break;
      }
    }

    if (venda.formaPagamento == 'misto' &&
        venda.pagamentosJson.trim().isNotEmpty) {
      for (final l in PagamentoOrcamentoCodec.decode(venda.pagamentosJson)) {
        aplicar(l.meio, l.valor);
      }
      return;
    }
    aplicar(venda.formaPagamento, venda.total);
  }

  /// Vendas finalizadas (ativas ou canceladas) vinculadas ao vendedor.
  int contarVendasFinalizadasPorVendedor(int vendedorId) {
    if (vendedorId <= 0) return 0;
    final q = _db.vendaBox
        .query(
          Venda_.status
              .equals('finalizada')
              .and(Venda_.vendedor.equals(vendedorId)),
        )
        .build();
    try {
      return q.count();
    } finally {
      q.close();
    }
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

  /// ObjectBox nao aceita `oneOf` em ToOne (erro: Unsupported type for IN: 11).
  /// Processa todos os IDs em lotes para nao omitir homonimos ("Silva").
  Condition<Venda> _orRelacaoPorIds(
    Condition<Venda> Function(int id) equals,
    List<int> ids, {
    int lote = 250,
  }) {
    final passo = lote < 1 ? 250 : lote;
    Condition<Venda>? acc;
    for (var i = 0; i < ids.length; i += passo) {
      final fim = (i + passo) > ids.length ? ids.length : i + passo;
      final slice = ids.sublist(i, fim);
      var c = equals(slice.first);
      for (var j = 1; j < slice.length; j++) {
        c = c | equals(slice[j]);
      }
      acc = acc == null ? c : acc | c;
    }
    return acc ?? equals(0);
  }

  /// Data da nota **ou** [Venda.finalizadaEm] (orcamento faturado depois).
  Condition<Venda>? _condicaoPeriodoListagem(FiltroListagemVendas f) {
    final ini = f.dataInicioUtc;
    final fim = f.dataFimUtc;
    if (ini == null && fim == null) return null;

    late final Condition<Venda> porData;
    late final Condition<Venda> porFinalizada;
    if (ini != null && fim != null) {
      porData = Venda_.data
          .greaterOrEqualDate(ini)
          .and(Venda_.data.lessOrEqualDate(fim));
      porFinalizada = Venda_.finalizadaEm
          .greaterOrEqualDate(ini)
          .and(Venda_.finalizadaEm.lessOrEqualDate(fim));
    } else if (ini != null) {
      porData = Venda_.data.greaterOrEqualDate(ini);
      porFinalizada = Venda_.finalizadaEm.greaterOrEqualDate(ini);
    } else {
      porData = Venda_.data.lessOrEqualDate(fim!);
      porFinalizada = Venda_.finalizadaEm.lessOrEqualDate(fim);
    }
    return porData.or(porFinalizada);
  }

  double _somarTotalListagem(Condition<Venda> cond) {
    final q = _db.vendaBox.query(cond).build();
    try {
      return q.property(Venda_.total).sum();
    } finally {
      q.close();
    }
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
    final periodo = _condicaoPeriodoListagem(f);
    if (periodo != null) {
      c = c & periodo;
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
        orPartes.add(_orRelacaoPorIds(Venda_.cliente.equals, idsCliente));
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
        orPartes.add(_orRelacaoPorIds(Venda_.vendedor.equals, idsVendedor));
      }
    } finally {
      qv.close();
    }

    orPartes.add(
      Venda_.nfceNumero.contains(tb, caseSensitive: false),
    );
    orPartes.add(
      Venda_.nfceChaveAcesso.contains(tb, caseSensitive: false),
    );
    final digitosBusca = tb.replaceAll(RegExp(r'\D'), '');
    if (digitosBusca.length >= 4) {
      orPartes.add(
        Venda_.nfceChaveAcesso.contains(digitosBusca, caseSensitive: false),
      );
    }

    final idsNfe55 =
        NfeSaidaFiscalStore(_db.storeDirectoryPath).buscarVendaIdsPorTexto(tb);
    if (idsNfe55.isNotEmpty) {
      orPartes.add(Venda_.id.oneOf(idsNfe55));
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

  List<Venda> _listarCandidatasListagemFiscal(FiltroListagemVendas f) {
    final base = FiltroListagemVendas(
      textoBusca: f.textoBusca,
      dataInicioUtc: f.dataInicioUtc,
      dataFimUtc: f.dataFimUtc,
      filtroCancelamento: f.filtroCancelamento,
      canceladaPorFiltro: f.canceladaPorFiltro,
      formaPagamento: f.formaPagamento,
      tipoEntrega: f.tipoEntrega,
      entregaPendente: f.entregaPendente,
      filtroFiscal: 'todos',
      clienteId: f.clienteId,
      vendedorId: f.vendedorId,
    );
    var cond = _condicaoListagemVendas(base);
    cond = cond &
        Venda_.nfceChaveAcesso.equals('') &
        Venda_.nfceUrlDanfe.equals('');
    cond = cond &
        Venda_.formaPagamento.oneOf([
          'pix',
          'cartao_credito',
          'cartao_debito',
          'transferencia',
          'misto',
        ]);
    final query = _queryListagemVendasOrdenada(cond, base);
    try {
      return query.find();
    } finally {
      query.close();
    }
  }

  List<Venda> _filtrarListagemFiscal(
    List<Venda> vendas,
    FiltroListagemVendas f,
  ) {
    if (f.filtroFiscal != 'sem_nfce_eletronico') return vendas;
    return vendas.where(VendaNfceObrigatoriaHelper.ehPendenteEmissao).toList();
  }

  /// Total de vendas finalizadas que obedecem ao filtro (sem paginacao).
  int contarListagemVendas(FiltroListagemVendas f) {
    if (f.filtroFiscal == 'sem_nfce_eletronico') {
      return _filtrarListagemFiscal(
        _listarCandidatasListagemFiscal(f),
        f,
      ).length;
    }
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
    if (f.filtroFiscal == 'sem_nfce_eletronico') {
      final filtradas = _filtrarListagemFiscal(
        _listarCandidatasListagemFiscal(f),
        f,
      );
      final total = filtradas.length;
      final totalValor = filtradas.fold<double>(0, (s, v) => s + v.total);
      final vendas = filtradas.skip(offset).take(limite).toList();
      return ListagemVendasPagina(
        vendas: vendas,
        total: total,
        totalValor: totalValor,
      );
    }
    final cond = _condicaoListagemVendas(f);
    final qCount = _db.vendaBox.query(cond).build();
    final total = qCount.count();
    qCount.close();
    final totalValor = _somarTotalListagem(cond);

    final query = _queryListagemVendasOrdenada(cond, f);
    try {
      query.offset = offset;
      query.limit = limite;
      final vendas = query.find();
      return ListagemVendasPagina(
        vendas: vendas,
        total: total,
        totalValor: totalValor,
      );
    } finally {
      query.close();
    }
  }

  /// Todas as vendas do filtro (sem limite). Use com cuidado em exportacoes.
  List<Venda> listarListagemVendasCompleto(FiltroListagemVendas f) {
    if (f.filtroFiscal == 'sem_nfce_eletronico') {
      return _filtrarListagemFiscal(
        _listarCandidatasListagemFiscal(f),
        f,
      );
    }
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

  Venda? obterPorId(int id) {
    final v = _db.vendaBox.get(id);
    if (v == null) return null;
    if (v.itens.isEmpty) {
      v.itens.addAll(listarItensPorVenda(id));
    }
    return v;
  }

  List<ItemVenda> listarItensPorVenda(int vendaId) {
    final query =
        _db.itemVendaBox.query(ItemVenda_.venda.equals(vendaId)).build();
    try {
      return query.find();
    } finally {
      query.close();
    }
  }

  /// Item persistido (box.get), nao o Backlink [Venda.itens].
  ///
  /// O Backlink às vezes devolve ToOne [ItemVenda.produto] zerado; um put
  /// nesse objeto apaga o vinculo e quebra a finalizacao no caixa.
  ItemVenda? _itemPersistidoDaVenda(int vendaId, int itemId) {
    if (vendaId <= 0 || itemId <= 0) return null;
    final item = _db.itemVendaBox.get(itemId);
    if (item == null) return null;
    try {
      if (item.venda.targetId != vendaId) return null;
    } catch (_) {
      return null;
    }
    return item;
  }

  /// Query primeiro; se vazia, ToMany (backlink às vezes desalinhado da query).
  List<ItemVenda> listarItensDaVendaGarantidos(int vendaId) {
    if (vendaId <= 0) return const [];
    final viaQuery = listarItensPorVenda(vendaId);
    if (viaQuery.isNotEmpty) return viaQuery;
    final v = _db.vendaBox.get(vendaId);
    if (v == null) return const [];
    try {
      return List<ItemVenda>.from(v.itens);
    } catch (_) {
      return const [];
    }
  }

  /// Orcamentos salvos no PDV ainda nao finalizados no caixa (consulta indexada).
  List<Venda> listarOrcamentosPendentes({
    DateTime? desde,
    DateTime? ate,
    int? limit,
  }) {
    var cond = Venda_.status
        .equals('orcamento')
        .and(Venda_.cancelada.equals(false));
    if (desde != null) {
      final inicioUtc = DateTime(desde.year, desde.month, desde.day).toUtc();
      cond = cond.and(Venda_.data.greaterOrEqualDate(inicioUtc));
    }
    if (ate != null) {
      final fimUtc = DateTime(
        ate.year,
        ate.month,
        ate.day,
        23,
        59,
        59,
        999,
      ).toUtc();
      cond = cond.and(Venda_.data.lessOrEqualDate(fimUtc));
    }
    final query = _db.vendaBox
        .query(cond)
        .order(Venda_.numeroOrcamento, flags: Order.descending)
        .build();
    try {
      if (limit != null && limit > 0) {
        query.limit = limit;
      }
      final lista = query.find();
      // Garante ordem por numero mesmo se algum registro tiver numero 0
      // (cai para id) apos sync/remap.
      lista.sort((a, b) {
        final na = a.numeroOrcamento > 0 ? a.numeroOrcamento : a.id;
        final nb = b.numeroOrcamento > 0 ? b.numeroOrcamento : b.id;
        return nb.compareTo(na);
      });
      return lista;
    } finally {
      query.close();
    }
  }

  /// Quantidade de orcamentos pendentes com data ate o fim do dia [ate] (inclusive).
  int contarOrcamentosPendentesAte(DateTime ate) {
    final fimUtc = DateTime(
      ate.year,
      ate.month,
      ate.day,
      23,
      59,
      59,
      999,
    ).toUtc();
    final query = _db.vendaBox
        .query(
          Venda_.status
              .equals('orcamento')
              .and(Venda_.cancelada.equals(false))
              .and(Venda_.data.lessOrEqualDate(fimUtc)),
        )
        .build();
    try {
      return query.count();
    } finally {
      query.close();
    }
  }

  /// Cancela orcamentos pendentes com data de criacao ate o fim do dia [ate] (inclusive).
  int cancelarOrcamentosPendentesAte(
    DateTime ate, {
    String motivo = '',
    String canceladaPor = '',
  }) {
    final alvo = listarOrcamentosPendentes(ate: ate);
    final motivoPadrao = motivo.trim().isEmpty
        ? 'Manutencao: limpeza de orcamentos em aberto'
        : motivo.trim();
    for (final v in alvo) {
      cancelarVenda(
        v.id,
        motivo: motivoPadrao,
        canceladaPor: canceladaPor,
        omitirAuditoriaIndividual: true,
      );
    }
    if (alvo.isNotEmpty) {
      final dataFmt =
          '${ate.day.toString().padLeft(2, '0')}/${ate.month.toString().padLeft(2, '0')}/${ate.year}';
      AuditoriaRegistrar.registrar(
        modulo: AuditoriaModulo.orcamento,
        acao: AuditoriaAcao.cancelarLote,
        usuarioLogin: canceladaPor,
        entidade: 'orcamento',
        resumo: '${alvo.length} orcamento(s) apagados ate $dataFmt',
        detalhes: {
          'ateData': dataFmt,
          'quantidade': alvo.length,
          'motivo': motivoPadrao,
        },
      );
    }
    return alvo.length;
  }

  /// Compras finalizadas do cliente com o produto no periodo (consulta PDV).
  ({int comprasNoPeriodo, int quantidadeLiquida, DateTime? ultimaCompraEm})
      resumoComprasClienteProduto(
    int clienteId,
    int produtoId, {
    int dias = 90,
  }) {
    if (clienteId <= 0 || produtoId <= 0) {
      return (
        comprasNoPeriodo: 0,
        quantidadeLiquida: 0,
        ultimaCompraEm: null,
      );
    }
    final fim = DateTime.now().toUtc();
    final inicio = fim.subtract(Duration(days: dias));
    final vendas = listarComprasFinalizadasPorCliente(
      clienteId,
      inicio: inicio,
      fim: fim,
    );
    var compras = 0;
    var qtd = 0;
    DateTime? ultima;
    for (final venda in vendas) {
      var qtdNaVenda = 0;
      for (final item in venda.itens) {
        if (item.produto.targetId != produtoId) continue;
        final liquida = item.quantidade - item.quantidadeDevolvida;
        if (liquida <= 0) continue;
        qtdNaVenda += liquida;
      }
      if (qtdNaVenda <= 0) continue;
      compras++;
      qtd += qtdNaVenda;
      if (ultima == null || venda.data.isAfter(ultima)) {
        ultima = venda.data;
      }
    }
    return (
      comprasNoPeriodo: compras,
      quantidadeLiquida: qtd,
      ultimaCompraEm: ultima,
    );
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

  /// Saldo em titulos a receber em aberto (apos finalizar no caixa).
  double saldoFiadoEmAbertoCliente(int clienteId, {int? ignorarVendaId}) {
    if (clienteId <= 0) return 0;
    titulos.migrarTitulosLegadoSeNecessario();
    final abertos = titulos.listarAbertosPorCliente(clienteId);
    if (ignorarVendaId == null) {
      return abertos.fold<double>(0, (s, t) => s + t.saldo);
    }
    return abertos
        .where((t) => t.venda.targetId != ignorarVendaId)
        .fold<double>(0, (s, t) => s + t.saldo);
  }

  /// Fiado em orcamentos ainda nao finalizados no caixa (nao entram nos titulos).
  double fiadoPendenteEmOrcamentosCliente(
    int clienteId, {
    int? ignorarVendaId,
  }) {
    if (clienteId <= 0) return 0;
    final q = _db.vendaBox
        .query(
          Venda_.cliente.equals(clienteId) &
              Venda_.status.equals('orcamento') &
              Venda_.cancelada.equals(false),
        )
        .build();
    try {
      var total = 0.0;
      for (final v in q.find()) {
        if (ignorarVendaId != null && v.id == ignorarVendaId) continue;
        total += LimiteCreditoHelper.valorFiadoNaVenda(v);
      }
      return total;
    } finally {
      q.close();
    }
  }

  /// Titulos em aberto + fiado em outros orcamentos do cliente.
  double exposicaoFiadoCliente(int clienteId, {int? ignorarVendaId}) {
    return saldoFiadoEmAbertoCliente(clienteId, ignorarVendaId: ignorarVendaId) +
        fiadoPendenteEmOrcamentosCliente(clienteId, ignorarVendaId: ignorarVendaId);
  }

  ValidacaoLimiteCredito validarLimiteCredito({
    required int clienteId,
    required double valorFiadoOperacao,
    int? ignorarVendaId,
  }) {
    if (clienteId <= 0) {
      return ValidacaoLimiteCredito.semFiado();
    }
    if (valorFiadoOperacao <= 0.001) {
      return ValidacaoLimiteCredito.semFiado();
    }
    final cliente = _db.clienteBox.get(clienteId);
    if (cliente == null) {
      return const ValidacaoLimiteCredito(
        permitido: false,
        mensagem: 'Cliente nao encontrado para validar limite de credito.',
      );
    }
    if (cliente.bloqueadoFiado) {
      final motivo = cliente.motivoBloqueio.trim();
      return ValidacaoLimiteCredito(
        permitido: false,
        mensagem: motivo.isEmpty
            ? 'Cliente com fiado bloqueado no cadastro.'
            : 'Cliente com fiado bloqueado: $motivo',
        nomeCliente: cliente.nomeRazao,
      );
    }
    if (cliente.limiteCredito <= 0) {
      return ValidacaoLimiteCredito.semLimiteConfigurado();
    }
    final saldo = exposicaoFiadoCliente(
      clienteId,
      ignorarVendaId: ignorarVendaId,
    );
    final disponivel = (cliente.limiteCredito - saldo).clamp(0, double.infinity).toDouble();
    final apos = saldo + valorFiadoOperacao;
    if (apos <= cliente.limiteCredito + 0.02) {
      return ValidacaoLimiteCredito(
        permitido: true,
        saldoEmAberto: saldo,
        limite: cliente.limiteCredito,
        valorFiadoOperacao: valorFiadoOperacao,
        saldoAposOperacao: apos,
        nomeCliente: cliente.nomeRazao,
      );
    }
    final excedeDisponivel = valorFiadoOperacao - disponivel;
    return ValidacaoLimiteCredito(
      permitido: false,
      saldoEmAberto: saldo,
      limite: cliente.limiteCredito,
      valorFiadoOperacao: valorFiadoOperacao,
      saldoAposOperacao: apos,
      nomeCliente: cliente.nomeRazao,
      mensagem:
          'Limite de credito excedido para ${cliente.nomeRazao}. '
          'Exposicao fiado (titulos + orcamentos pendentes): '
          '${LimiteCreditoHelper.formatarMoedaBr(saldo)}. '
          'Disponivel para novo fiado: ${LimiteCreditoHelper.formatarMoedaBr(disponivel)}. '
          'Fiado desta operacao: ${LimiteCreditoHelper.formatarMoedaBr(valorFiadoOperacao)}'
          '${excedeDisponivel > 0.02 ? ' (excede o disponivel em ${LimiteCreditoHelper.formatarMoedaBr(excedeDisponivel)})' : ''}. '
          'Total ficaria ${LimiteCreditoHelper.formatarMoedaBr(apos)} '
          '(limite ${LimiteCreditoHelper.formatarMoedaBr(cliente.limiteCredito)}).',
    );
  }

  void _exigirClienteParaFiado({
    required int? clienteId,
    required double valorFiadoOperacao,
  }) {
    if (valorFiadoOperacao <= 0.001) return;
    if (clienteId == null || clienteId <= 0) {
      throw StateError(
        'Vincule um cliente ao orcamento para usar pagamento fiado.',
      );
    }
  }

  void _exigirLimiteCredito({
    required int? clienteId,
    required double valorFiadoOperacao,
    int? ignorarVendaId,
  }) {
    _exigirClienteParaFiado(
      clienteId: clienteId,
      valorFiadoOperacao: valorFiadoOperacao,
    );
    if (clienteId == null || clienteId <= 0) return;
    final r = validarLimiteCredito(
      clienteId: clienteId,
      valorFiadoOperacao: valorFiadoOperacao,
      ignorarVendaId: ignorarVendaId,
    );
    if (!r.permitido) {
      throw StateError(r.mensagem ?? 'Limite de credito excedido.');
    }
  }

  List<Venda> listarPorPeriodo(PeriodoFiltro periodo) {
    final inicioUtc = periodo.inicio.toUtc();
    final fimUtc = periodo.fim.toUtc();
    final q = _db.vendaBox
        .query(
          Venda_.data
              .greaterOrEqualDate(inicioUtc)
              .and(Venda_.data.lessOrEqualDate(fimUtc)),
        )
        .build();
    try {
      return q.find();
    } finally {
      q.close();
    }
  }

  /// Vendas **finalizadas** no dia civil local.
  ///
  /// Base: mesma regra do Caixa / Listagem (`Venda.data` no dia).
  /// Complemento: orcamento antigo pago hoje (`finalizadaEm`).
  List<Venda> listarVendasFinalizadasNoDiaLocal(DateTime diaRef) {
    final dia = DateTime(diaRef.year, diaRef.month, diaRef.day);
    final fim = DateTime(dia.year, dia.month, dia.day, 23, 59, 59, 999);
    final fimExclusivo = dia.add(const Duration(days: 1));
    final byId = <int, Venda>{};

    for (final v in listarPorPeriodo(PeriodoFiltro(inicio: dia, fim: fim))) {
      if (!v.cancelada && v.status == 'finalizada') {
        byId[v.id] = v;
      }
    }

    final feIni = dia.toUtc().subtract(const Duration(hours: 14));
    final feFim = fim.toUtc().add(const Duration(hours: 14));
    final qFe = _db.vendaBox
        .query(
          Venda_.status
              .equals('finalizada')
              .and(Venda_.cancelada.equals(false))
              .and(Venda_.finalizadaEm.greaterOrEqualDate(feIni))
              .and(Venda_.finalizadaEm.lessOrEqualDate(feFim)),
        )
        .build();
    try {
      for (final v in qFe.find()) {
        final m = VendaFinalizacaoCaixaHelper.momentoFinalizacao(v).toLocal();
        if (!m.isBefore(dia) && m.isBefore(fimExclusivo)) {
          byId[v.id] = v;
        }
      }
    } finally {
      qFe.close();
    }

    return byId.values.toList();
  }

  /// Contadores do painel (uma passagem, sem ordenar lista completa).
  ({int emAberto, int atrasadas}) contarEntregasPainelResumo() {
    final candidatas = _consultarEntregasCarretoNoBanco(
      statusEntrega: 'todos',
      inicio: null,
      fim: null,
      dataMarcadaInicio: null,
      dataMarcadaFim: null,
    );
    var emAberto = 0;
    var atrasadas = 0;
    for (final v in candidatas) {
      final st = v.statusEntrega.trim().toLowerCase();
      final finalizado = st == 'entregue' || st == 'cancelada';
      if (!finalizado) emAberto++;
      if (EntregaFiltroUtil.ehAtrasada(v)) atrasadas++;
    }
    return (emAberto: emAberto, atrasadas: atrasadas);
  }

  /// Linhas de vendas finalizadas com promocao aplicada no periodo.
  List<VendaPromocaoRelatorioLinha> listarVendasPromocaoPeriodo({
    required DateTime inicio,
    required DateTime fim,
    int? promocaoId,
  }) {
    final inicioUtc = inicio.toUtc();
    final fimUtc = fim.toUtc();
    final out = <VendaPromocaoRelatorioLinha>[];
    for (final v in listarTodas()) {
      if (v.status != 'finalizada' || v.cancelada) continue;
      final data = v.data.toUtc();
      if (data.isBefore(inicioUtc) || data.isAfter(fimUtc)) continue;
      final cli = v.cliente.target;
      final nomeCli = (cli?.nomeRazao ?? '').trim();
      final nota = v.numeroOrcamento > 0 ? v.numeroOrcamento : v.id;
      for (final item in v.itens) {
        if (item.promocaoId <= 0) continue;
        if (promocaoId != null && item.promocaoId != promocaoId) continue;
        final qtd = item.quantidade - item.quantidadeDevolvida;
        if (qtd <= 0) continue;
        final nomePromo = item.promocaoNomeSnapshot.trim().isNotEmpty
            ? item.promocaoNomeSnapshot.trim()
            : 'Promocao #${item.promocaoId}';
        out.add(
          VendaPromocaoRelatorioLinha(
            dataVenda: v.data.toLocal(),
            vendaId: v.id,
            nota: nota,
            promocaoId: item.promocaoId,
            promocaoNome: nomePromo,
            produtoNome: item.nomeProduto,
            codigoInterno: item.produto.target?.codigoInterno ?? '',
            quantidade: qtd,
            valorUnitario: item.precoUnitario,
            total: qtd * item.precoUnitario,
            lucro: qtd * (item.precoUnitario - item.precoCustoUnitario),
            clienteNome: nomeCli.isEmpty ? '-' : nomeCli,
            itemVendaId: item.id,
          ),
        );
      }
    }
    out.sort((a, b) {
      final c = b.dataVenda.compareTo(a.dataVenda);
      if (c != 0) return c;
      return b.vendaId.compareTo(a.vendaId);
    });
    return out;
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

  /// Produtos que apareceram na mesma venda finalizada que [produtoOrigemId].
  List<ProdutoCoocorrenciaVenda> listarProdutosCompradosJunto(
    int produtoOrigemId, {
    int dias = 90,
    int limiteVendasAnalisadas = 500,
    int minimoVendasJuntas = 2,
    int limiteResultado = 12,
  }) {
    if (produtoOrigemId <= 0 || dias <= 0 || limiteResultado <= 0) {
      return const [];
    }

    final fim = DateTime.now().toUtc();
    final inicio = fim.subtract(Duration(days: dias));

    final qb = _db.itemVendaBox.query(
      ItemVenda_.produto.equals(produtoOrigemId),
    );
    qb.link(
      ItemVenda_.venda,
      Venda_.status
          .equals('finalizada')
          .and(Venda_.cancelada.equals(false))
          .and(Venda_.data.greaterOrEqualDate(inicio))
          .and(Venda_.data.lessOrEqualDate(fim)),
    );
    final queryOrigem = qb.build();
    try {
      final itensOrigem = queryOrigem.find();
      if (itensOrigem.isEmpty) return const [];

      final vendasComOrigem = <int, DateTime>{};
      for (final item in itensOrigem) {
        final liquida = item.quantidade - item.quantidadeDevolvida;
        if (liquida <= 0) continue;
        final vid = item.venda.targetId;
        if (vid <= 0) continue;
        final venda = item.venda.target ?? _db.vendaBox.get(vid);
        if (venda == null) continue;
        final anterior = vendasComOrigem[vid];
        if (anterior == null || venda.data.isAfter(anterior)) {
          vendasComOrigem[vid] = venda.data;
        }
      }
      if (vendasComOrigem.isEmpty) return const [];

      final vendaIds = vendasComOrigem.keys.toList()
        ..sort((a, b) => vendasComOrigem[b]!.compareTo(vendasComOrigem[a]!));
      final analisar = vendaIds.take(limiteVendasAnalisadas);

      final cooc = <int, ({int vendas, int qtdTotal})>{};
      for (final vid in analisar) {
        final qItens = _db.itemVendaBox
            .query(ItemVenda_.venda.equals(vid))
            .build();
        try {
          final qtyPorProduto = <int, int>{};
          for (final item in qItens.find()) {
            final pid = item.produto.targetId;
            if (pid <= 0 || pid == produtoOrigemId) continue;
            final liquida = item.quantidade - item.quantidadeDevolvida;
            if (liquida <= 0) continue;
            qtyPorProduto[pid] = (qtyPorProduto[pid] ?? 0) + liquida;
          }
          for (final e in qtyPorProduto.entries) {
            final prev = cooc[e.key];
            cooc[e.key] = (
              vendas: (prev?.vendas ?? 0) + 1,
              qtdTotal: (prev?.qtdTotal ?? 0) + e.value,
            );
          }
        } finally {
          qItens.close();
        }
      }

      final ranked = cooc.entries
          .where((e) => e.value.vendas >= minimoVendasJuntas)
          .map(
            (e) => ProdutoCoocorrenciaVenda(
              produtoId: e.key,
              vendasJuntas: e.value.vendas,
              quantidadeMedia: e.value.qtdTotal / e.value.vendas,
            ),
          )
          .toList()
        ..sort((a, b) {
          final cmp = b.vendasJuntas.compareTo(a.vendasJuntas);
          if (cmp != 0) return cmp;
          return b.quantidadeMedia.compareTo(a.quantidadeMedia);
        });

      return ranked.take(limiteResultado).toList();
    } finally {
      queryOrigem.close();
    }
  }

  int registrarVenda(
    List<ItemVendaInput> itensInput, {
    bool permitirVendaSemEstoque = true,
  }) {
    if (itensInput.isEmpty) {
      throw ArgumentError('A venda deve conter ao menos um item.');
    }
    for (final input in itensInput) {
      validarItemVendaInput(input);
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

        _estoque.baixarEstoqueVendaDiretaLegada(
          produto: produto,
          quantidade: input.quantidade,
          permitirVendaSemEstoque: permitirVendaSemEstoque,
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
    _notificarRedeAposEscrita(vendaId: novoId);
    return novoId;
  }

  int registrarOrcamento(
    List<ItemVendaInput> itensInput, {
    required DadosPagamentoOrcamento pagamento,
    required DadosEntregaOrcamento entrega,
    int? clienteId,
    int? vendedorId,
    double descontoEmReais = 0,
    bool permitirVendaSemEstoque = false,
    String? uuidLocal,
  }) {
    return registrarOrcamentoIdempotente(
      itensInput,
      pagamento: pagamento,
      entrega: entrega,
      clienteId: clienteId,
      vendedorId: vendedorId,
      descontoEmReais: descontoEmReais,
      permitirVendaSemEstoque: permitirVendaSemEstoque,
      uuidLocal: uuidLocal,
    ).id;
  }

  /// Janela em que a mesma [Venda.uuidLocal] reaproveita o orcamento.
  static const janelaIdempotenciaOrcamento = Duration(minutes: 5);

  /// Cria orcamento; se [uuidLocal] ja existir na janela, devolve o existente.
  ({int id, bool reutilizado}) registrarOrcamentoIdempotente(
    List<ItemVendaInput> itensInput, {
    required DadosPagamentoOrcamento pagamento,
    required DadosEntregaOrcamento entrega,
    int? clienteId,
    int? vendedorId,
    double descontoEmReais = 0,
    bool permitirVendaSemEstoque = false,
    String? uuidLocal,
  }) {
    if (itensInput.isEmpty) {
      throw ArgumentError('O orcamento deve conter ao menos um item.');
    }
    for (final input in itensInput) {
      validarItemVendaInput(input);
    }
    final key = (uuidLocal ?? '').trim();
    var descontoRegistrado = 0.0;
    var numeroOrcamentoRegistrado = 0;
    final resultado = _db.store.runInTransaction(TxMode.write, () {
      if (key.isNotEmpty) {
        final q = _db.vendaBox
            .query(Venda_.uuidLocal.equals(key, caseSensitive: true))
            .build();
        try {
          final lista = q.find();
          final limite = DateTime.now()
              .toUtc()
              .subtract(janelaIdempotenciaOrcamento);
          Venda? melhor;
          for (final v in lista) {
            final data = v.data.toUtc();
            if (data.isBefore(limite)) continue;
            if (melhor == null || data.isAfter(melhor.data.toUtc())) {
              melhor = v;
            }
          }
          if (melhor != null) {
            return (id: melhor.id, reutilizado: true);
          }
        } finally {
          q.close();
        }
      }
      final proximoNumero = _proximoNumeroOrcamento();
      final venda = Venda(
        status: 'orcamento',
        numeroOrcamento: proximoNumero,
        formaPagamento: 'dinheiro',
        quantidadeParcelas: 1,
        pagamentosJson: '',
        uuidLocal: key,
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
      descontoRegistrado = descAplicado;
      numeroOrcamentoRegistrado = proximoNumero;
      venda.lucroTotal = venda.total - custoTotal;
      _aplicarPagamentoNoOrcamento(
        venda,
        pagamento,
        totalOrcamento: venda.total,
      );
      _exigirClienteParaFiado(
        clienteId: clienteId,
        valorFiadoOperacao: LimiteCreditoHelper.valorFiadoNaVenda(venda),
      );
      _aplicarPlanoFiadoNoOrcamento(venda, planoFiado: pagamento.planoFiado);
      _exigirLimiteCredito(
        clienteId: clienteId,
        valorFiadoOperacao: LimiteCreditoHelper.valorFiadoNaVenda(venda),
      );
      final vendaId = _db.vendaBox.put(venda);
      venda.id = vendaId;

      for (final item in itens) {
        item.venda.target = venda;
        _db.itemVendaBox.put(item);
      }

      return (id: vendaId, reutilizado: false);
    });
    if (!resultado.reutilizado) {
      _notificarRedeAposEscrita(vendaId: resultado.id);
      if (descontoRegistrado > 0.004) {
        AuditoriaRegistrar.registrar(
          modulo: AuditoriaModulo.orcamento,
          acao: AuditoriaAcao.descontoOrcamento,
          entidade: 'orcamento',
          entidadeId: '${resultado.id}',
          resumo:
              'Desconto R\$ ${descontoRegistrado.toStringAsFixed(2)} no orcamento #$numeroOrcamentoRegistrado',
          detalhes: {
            'valorDesconto': descontoRegistrado,
            'numeroOrcamento': numeroOrcamentoRegistrado,
          },
        );
      }
    }
    return resultado;
  }

  int _obterOuCriarProdutoFreteRetiradaFutura() {
    return _estoque.obterOuCriarProdutoFreteRetiradaFutura();
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
    _notificarRedeAposEscrita(vendaId: novoId);
    return novoId;
  }

  /// Agrupa entregas de carreto na mesma viagem do caminhao (carga + ordem das paradas).
  /// Clientes podem ser diferentes; cada nota continua independente (fiado, POD, status).
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
      for (final v in vendas) {
        if (v.cliente.targetId <= 0) {
          throw StateError(
            'Pedido ${v.numeroOrcamento} sem cliente cadastrado. '
            'Cadastre o cliente antes de agrupar na viagem.',
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
    _notificarRedeAposEscrita(vendaIds: ids);
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
    final qGrupo = _db.vendaBox
        .query(Venda_.grupoEntregaFreteId.equals(grupoId))
        .build();
    try {
      _notificarRedeAposEscrita(vendaIds: qGrupo.findIds());
    } finally {
      qGrupo.close();
    }
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
    _notificarRedeAposEscrita(vendaIds: vendaIds);
  }

  static String _nomeMotoristaEntregaVenda(Venda venda) {
    if (venda.motoristaEntrega.trim().isNotEmpty) {
      return venda.motoristaEntrega.trim();
    }
    for (final linha in venda.observacaoEntrega.split('\n')) {
      final limpa = linha.trim();
      if (limpa.startsWith('Motorista:')) {
        final nome = limpa.substring('Motorista:'.length).trim();
        if (nome.isNotEmpty) return nome;
      }
    }
    return '';
  }

  /// Define a sequencia de paradas (1..n) do motorista no dia (sem agrupar viagem).
  void atualizarSequenciaEntregaMotorista(
    String motoristaEntrega,
    List<int> vendaIdsOrdenados,
  ) {
    final alvo = motoristaEntrega.trim().toLowerCase();
    if (alvo.isEmpty) {
      throw StateError('Informe o motorista.');
    }
    final ids = List<int>.from(vendaIdsOrdenados);
    if (ids.length < 2) return;
    _db.store.runInTransaction(TxMode.write, () {
      for (var i = 0; i < ids.length; i++) {
        final v = _db.vendaBox.get(ids[i]);
        if (v == null) {
          throw StateError('Venda ${ids[i]} nao encontrada.');
        }
        final mot = _nomeMotoristaEntregaVenda(v).toLowerCase();
        if (mot.isEmpty || mot != alvo) {
          throw StateError(
            'Pedido ${v.numeroOrcamento} nao pertence a este motorista.',
          );
        }
        v.ordemEntrega = i + 1;
        _db.vendaBox.put(v);
      }
    });
    _notificarRedeAposEscrita(vendaIds: ids);
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
    _notificarRedeAposEscrita(vendaIds: ids);
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

    _estoque.migrarEstoqueRetiradaFuturaParaCarretoItens(mae.itens);

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
    bool permitirVendaSemEstoque = false,
  }) {
    if (itensInput.isEmpty) {
      throw ArgumentError('O orcamento deve conter ao menos um item.');
    }
    for (final input in itensInput) {
      validarItemVendaInput(input);
    }
    var descontoRegistrado = 0.0;
    var numeroOrcamentoRegistrado = 0;
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

      // Remover itens antigos pela query — NAO usar venda.itens.clear():
      // clear()+put(venda) no Backlink zera ItemVenda.venda (ToOne) e some o
      // vinculo dos itens novos gravados logo abaixo.
      final antigos = listarItensPorVenda(vendaId);
      for (final antigo in antigos) {
        _estoque.liberarReservaEstoqueItemOrcamento(antigo);
      }
      final idsAntigos = antigos.map((i) => i.id).toList();
      if (idsAntigos.isNotEmpty) {
        _db.itemVendaBox.removeMany(idsAntigos);
      }

      double total = 0;
      double custoTotal = 0;
      final itensNovos = <ItemVenda>[];
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
        itensNovos.add(item);
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
      descontoRegistrado = descAplicado;
      numeroOrcamentoRegistrado = venda.numeroOrcamento;
      venda.lucroTotal = venda.total - custoTotal;
      _aplicarPagamentoNoOrcamento(
        venda,
        pagamento,
        totalOrcamento: venda.total,
      );
      _exigirClienteParaFiado(
        clienteId: venda.cliente.targetId,
        valorFiadoOperacao: LimiteCreditoHelper.valorFiadoNaVenda(venda),
      );
      _aplicarPlanoFiadoNoOrcamento(venda, planoFiado: pagamento.planoFiado);
      _exigirLimiteCredito(
        clienteId: venda.cliente.targetId,
        valorFiadoOperacao: LimiteCreditoHelper.valorFiadoNaVenda(venda),
        ignorarVendaId: vendaId,
      );
      _db.vendaBox.put(venda);
    });
    _notificarRedeAposEscrita(vendaId: vendaId);
    if (descontoRegistrado > 0.004) {
      AuditoriaRegistrar.registrar(
        modulo: AuditoriaModulo.orcamento,
        acao: AuditoriaAcao.descontoOrcamento,
        entidade: 'orcamento',
        entidadeId: '$vendaId',
        resumo:
            'Desconto R\$ ${descontoRegistrado.toStringAsFixed(2)} no orcamento #$numeroOrcamentoRegistrado',
        detalhes: {
          'valorDesconto': descontoRegistrado,
          'numeroOrcamento': numeroOrcamentoRegistrado,
        },
      );
    }
  }

  /// Preco promocional na data de fechamento; mantem desconto implicito ja aplicado.
  /// Linhas com [ItemVenda.precoUnitarioManual] (Ctrl+P no PDV) nao sao sobrescritas.
  void _reaplicarPromocoesAoFecharOrcamento(
    Venda venda,
    DateTime dataFechamento, {
    List<ItemVenda>? itens,
  }) {
    final promoSvc = PromocaoPrecoService(PromocaoRepository(_db));
    final descontoMantido = venda.descontoImplicitoTotal;
    final segmento = venda.cliente.target?.segmento;
    var somaItens = 0.0;
    var custo = 0.0;
    final lista = itens ?? _itensDaVendaGarantidos(venda);
    for (final item in lista) {
      final produto = item.produto.target;
      if (produto == null) continue;

      if (item.precoUnitarioManual) {
        somaItens += item.subtotal;
        custo += item.subtotalCusto;
        continue;
      }

      final tipoLista = item.precoTipo == PromocaoCadastro.precoTipoPromo
          ? 'preco1'
          : item.precoTipo;
      final r = promoSvc.resolver(
        produto,
        dataReferencia: dataFechamento,
        quantidade: item.quantidade,
        precoTipoLista: tipoLista,
        segmentoCliente: segmento,
      );
      var precoUnit = r.precoFinal;
      if (r.promocaoId > 0) {
        final promo = PromocaoRepository(_db).obterPorId(r.promocaoId);
        if (promo != null) {
          precoUnit = PromocaoCadastro.aplicarLevePagueNoPreco(
            tipoCampanha: promo.tipoCampanha,
            precoBasePromo: precoUnit,
            quantidade: item.quantidade,
            leveQuantidade: promo.leveQuantidade,
            pagueQuantidade: promo.pagueQuantidade,
          );
        }
      }

      // Legado: orcamento salvo antes da flag — preco divergente sem promo = manual.
      final divergente = (item.precoUnitario - precoUnit).abs() > 0.009;
      if (divergente && item.promocaoId == 0 && r.promocaoId == 0) {
        item.precoUnitarioManual = true;
        _db.itemVendaBox.put(item);
        somaItens += item.subtotal;
        custo += item.subtotalCusto;
        continue;
      }

      item.precoUnitario = precoUnit;
      item.precoTipo = r.precoTipo;
      item.promocaoId = r.promocaoId;
      item.promocaoNomeSnapshot = r.promocaoNome;
      _db.itemVendaBox.put(item);
      somaItens += item.subtotal;
      custo += item.subtotalCusto;
    }
    final bruto = somaItens + venda.valorFrete;
    venda.custoTotal = custo;
    venda.total = (bruto - descontoMantido).clamp(0, double.infinity);
    venda.lucroTotal = venda.total - custo;
  }

  /// Itens da venda via query (Backlink ObjectBox às vezes vem vazio no get).
  List<ItemVenda> _itensDaVendaGarantidos(Venda venda) {
    if (venda.id <= 0) {
      try {
        return List<ItemVenda>.from(venda.itens);
      } catch (_) {
        return const [];
      }
    }
    final via = listarItensDaVendaGarantidos(venda.id);
    if (via.isNotEmpty) return via;
    try {
      return List<ItemVenda>.from(venda.itens);
    } catch (_) {
      return const [];
    }
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

      final itens = _itensDaVendaGarantidos(venda);
      if (itens.isEmpty) {
        throw StateError('Orcamento $vendaId sem itens para finalizar.');
      }

      final filhoFreteRetirada = venda.vendaOrigemFreteRetiradaId > 0;

      if (!filhoFreteRetirada) {
        // So cabecalho explicito de futura: flag entregaPendente sozinha pode
        // estar stale em orcamento "leva agora" e nao deve bloquear a baixa.
        final cabecalhoEraFutura =
            venda.tipoEntrega == EntregaVendaHelper.tipoRetiradaFutura;
        _reaplicarPromocoesAoFecharOrcamento(
          venda,
          DateTime.now(),
          itens: itens,
        );
        // Cabecalho segue os itens (evita legado com header stale "carreto"
        // apagar venda mista que ainda tem "leva agora" nas linhas).
        venda.tipoEntrega = EntregaVendaHelper.resolverTipoEntregaVenda(
          itens.map((i) => i.tipoEntregaItem),
        );
        EntregaVendaHelper.aplicarLegadoTipoUnicoNosItensSeNecessario(
          venda,
          itens: itens,
        );
        // Apos legado (orcamento antigo), re-sincroniza cabecalho.
        venda.tipoEntrega = EntregaVendaHelper.resolverTipoEntregaVenda(
          itens.map((i) => i.tipoEntregaItem),
        );
        for (final item in itens) {
          _db.itemVendaBox.put(item);
        }
        venda.carretoReservaAteSaida = itens.any(
          (i) =>
              EntregaVendaHelper.tipoEfetivoItem(i) ==
              EntregaVendaHelper.tipoEntregaLoja,
        );
        venda.entregaPendente = itens.any(
          (i) =>
              EntregaVendaHelper.tipoEfetivoItem(i) ==
              EntregaVendaHelper.tipoRetiradaFutura,
        );

        // Snapshot do reservado antes — valida se a reserva realmente gravou.
        final reservadoAntes = <int, int>{};
        for (final item in itens) {
          final pid = item.produto.targetId;
          if (pid <= 0) continue;
          final p = _db.produtoBox.get(pid);
          if (p != null) reservadoAntes[pid] = p.estoqueReservado;
        }

        var qtdEsperadaReserva = 0;
        for (final item in itens) {
          final tipo = EntregaVendaHelper.tipoEfetivoItem(item);
          if (tipo == EntregaVendaHelper.tipoRetiradaFutura ||
              tipo == EntregaVendaHelper.tipoEntregaLoja) {
            qtdEsperadaReserva += item.quantidadeUnidadeEstoque;
          }
          _estoque.ajustarReservaEstoqueAoFinalizarItem(
            item: item,
            permitirVendaSemEstoque: permitirVendaSemEstoque,
          );
        }

        if (qtdEsperadaReserva > 0) {
          var somou = 0;
          for (final e in reservadoAntes.entries) {
            final p = _db.produtoBox.get(e.key);
            if (p == null) continue;
            somou += (p.estoqueReservado - e.value).clamp(0, 1 << 30);
          }
          if (somou < qtdEsperadaReserva) {
            final tipos = itens
                .map((i) => '${i.nomeProduto}:${i.tipoEntregaItem}')
                .join(', ');
            throw StateError(
              'Falha ao reservar estoque na finalizacao: '
              'esperado +$qtdEsperadaReserva no reservado, obteve +$somou. '
              'Itens=[$tipos] cabecalho=${venda.tipoEntrega}.',
            );
          }
        } else if (cabecalhoEraFutura) {
          throw StateError(
            'Venda marcada como retirada futura/pendente, mas nenhum item '
            'foi reservado. Verifique o tipo de entrega de cada item no PDV '
            '(Ctrl+F2 / tecla E). Cabecalho=${venda.tipoEntrega}.',
          );
        }
      }

      _exigirLimiteCredito(
        clienteId: venda.cliente.targetId,
        valorFiadoOperacao: LimiteCreditoHelper.valorFiadoNaVenda(venda),
      );

      final valorFiado = LimiteCreditoHelper.valorFiadoNaVenda(venda);
      if (valorFiado > 0.001) {
        final plano = PlanoFiadoCodec.decode(venda.planoFiadoJson);
        if (!PlanoFiadoCodec.validarContraValor(plano, valorFiado)) {
          throw StateError(
            'Orcamento fiado sem plano de parcelas valido. '
            'Edite o orcamento no PDV e defina as parcelas.',
          );
        }
      }

      venda.status = 'finalizada';
      venda.finalizadaEm = DateTime.now().toUtc();
      venda.cancelada = false;
      venda.motivoCancelamento = '';
      venda.canceladaPor = '';
      venda.canceladaEm = null;
      _marcarUltimaVendaNosProdutos(_db, itens);
      _estoque.registrarBaixaEstoqueCupomNaoFiscal(
        venda: venda,
        permitirVendaSemEstoque: permitirVendaSemEstoque,
        itens: itens,
      );

      // Garante que "leva agora" realmente saiu do fisico (nao ficou so reservado).
      for (final item in itens) {
        if (EntregaVendaHelper.tipoEfetivoItem(item) !=
            EntregaVendaHelper.tipoRetirada) {
          continue;
        }
        if (item.quantidade > 0 &&
            item.quantidadeJaRetirada < item.quantidade) {
          throw StateError(
            'Baixa incompleta em "${item.nomeProduto}" (leva agora): '
            'retirado ${item.quantidadeJaRetirada} de ${item.quantidade}. '
            'Tipo=${item.tipoEntregaItem} cabecalho=${venda.tipoEntrega}.',
          );
        }
      }

      _db.vendaBox.put(venda);
      titulos.gerarTitulosDaVenda(venda);

      if (filhoFreteRetirada) {
        _migrarVendaMaeRetiradaFuturaParaCarretoNaTransacao(venda);
      }
    });
    _registrarContadoresPromocaoAposFinalizar(vendaId);
    final produtoIds = listarItensPorVenda(vendaId)
        .map((i) => i.produto.targetId)
        .where((id) => id > 0)
        .toSet();
    _notificarRedeAposEscrita(
      vendaId: vendaId,
      estoqueAlterado: true,
      produtoIds: produtoIds,
    );
  }

  /// Reaplica baixa de estoque para venda ja documentada (idempotente).
  ///
  /// Usado em recuperacao manual quando a autorizacao fiscal e a baixa divergiram.
  void reprocessarBaixaEstoqueDocumentoVenda(
    int vendaId, {
    bool permitirVendaSemEstoque = true,
  }) {
    registrarBaixaEstoqueCupomNaoFiscal(
      vendaId,
      permitirVendaSemEstoque: permitirVendaSemEstoque,
    );
  }

  /// Alias legado — preferir [reprocessarBaixaEstoqueDocumentoVenda].
  void registrarCupomInternoPosAutorizacaoFiscal(
    int vendaId, {
    bool permitirVendaSemEstoque = true,
  }) {
    reprocessarBaixaEstoqueDocumentoVenda(
      vendaId,
      permitirVendaSemEstoque: permitirVendaSemEstoque,
    );
  }

  NfeSaidaFiscalRegistro? obterNfe55AutorizadaPorVenda(int vendaId) {
    final v = obterPorId(vendaId);
    if (v != null && v.nfe55Autorizada) {
      return NfeSaidaFiscalRegistro(
        id: 'venda_${vendaId}_sync',
        vendaId: vendaId,
        numeroOrcamento:
            v.numeroOrcamento > 0 ? v.numeroOrcamento : vendaId,
        clienteNome: v.cliente.target?.nomeRazao ?? '',
        referenciaFocus: v.nfeReferenciaFocus,
        statusFocus: v.nfeStatusFocus,
        emitidaEm: v.nfeEmitidaEm ?? v.data,
        statusSefaz: '100',
        chaveNfe: v.nfeChaveAcesso,
        numero: v.nfeNumero,
        serie: v.nfeSerie,
        protocolo: v.nfeProtocolo,
        urlDanfe: v.nfeUrlDanfe,
        urlXml: v.nfeUrlXml,
        valorTotal: v.total,
      );
    }
    return NfeSaidaFiscalStore(_db.storeDirectoryPath)
        .ultimaAutorizadaPorVenda(vendaId);
  }

  /// Vendas com qualquer registro NF-e 55 na venda (sync LAN).
  List<Venda> listarVendasComDadosNfe55({int limit = 200}) {
    if (limit <= 0) return const [];
    final query = _db.vendaBox
        .query(Venda_.nfeReferenciaFocus.notEquals(''))
        .order(Venda_.nfeEmitidaEm, flags: Order.descending)
        .build();
    try {
      query.limit = limit;
      return query.find();
    } finally {
      query.close();
    }
  }

  bool vendaTemNfe55Autorizada(int vendaId) {
    final v = obterPorId(vendaId);
    if (v == null) return false;
    if (v.nfe55Autorizada) return true;
    return NfeSaidaFiscalStore(_db.storeDirectoryPath)
            .ultimaAutorizadaPorVenda(vendaId) !=
        null;
  }

  void registrarNfe55Situacao({
    required int vendaId,
    required String referenciaFocus,
    String chaveAcesso = '',
    String numero = '',
    String serie = '',
    String protocolo = '',
    String urlDanfe = '',
    String urlXml = '',
    String statusFocus = '',
    String urlXmlCancelamento = '',
    DateTime? emitidaEm,
  }) {
    _db.store.runInTransaction(TxMode.write, () {
      final venda = _db.vendaBox.get(vendaId);
      if (venda == null) {
        throw StateError('Venda $vendaId nao encontrada.');
      }
      _preencherVendaNfe55Situacao(
        venda,
        referenciaFocus: referenciaFocus,
        chaveAcesso: chaveAcesso,
        numero: numero,
        serie: serie,
        protocolo: protocolo,
        urlDanfe: urlDanfe,
        urlXml: urlXml,
        statusFocus: statusFocus,
        urlXmlCancelamento: urlXmlCancelamento,
        emitidaEm: emitidaEm,
      );
      _db.vendaBox.put(venda);
    });
    _notificarRedeAposEscrita(vendaId: vendaId);
    final chave = chaveAcesso.trim();
    final xml = urlXml.trim();
    if (chave.length >= 40 && xml.isNotEmpty) {
      unawaited(
        NfeXmlLocalService.arquivarOuEnfileirar(
          storeDirectoryPath: _db.storeDirectoryPath,
          chaveAcesso: chave,
          urlXml: xml,
        ),
      );
    }
    final xmlCancel = urlXmlCancelamento.trim();
    if (chave.length >= 40 && xmlCancel.isNotEmpty) {
      unawaited(
        NfeXmlLocalService.arquivarOuEnfileirar(
          storeDirectoryPath: _db.storeDirectoryPath,
          chaveAcesso: chave,
          urlXml: xmlCancel,
          cancelada: true,
        ),
      );
    }
  }

  /// NF-e 55 autorizada; baixa idempotente (retirada imediata ja na finalizacao).
  void registrarNfe55SituacaoComBaixaEstoque({
    required int vendaId,
    required String referenciaFocus,
    String chaveAcesso = '',
    String numero = '',
    String serie = '',
    String protocolo = '',
    String urlDanfe = '',
    String urlXml = '',
    String statusFocus = '',
    String urlXmlCancelamento = '',
    DateTime? emitidaEm,
    bool permitirVendaSemEstoque = true,
  }) {
    _db.store.runInTransaction(TxMode.write, () {
      final venda = _db.vendaBox.get(vendaId);
      if (venda == null) {
        throw StateError('Venda $vendaId nao encontrada.');
      }
      _preencherVendaNfe55Situacao(
        venda,
        referenciaFocus: referenciaFocus,
        chaveAcesso: chaveAcesso,
        numero: numero,
        serie: serie,
        protocolo: protocolo,
        urlDanfe: urlDanfe,
        urlXml: urlXml,
        statusFocus: statusFocus,
        urlXmlCancelamento: urlXmlCancelamento,
        emitidaEm: emitidaEm,
      );
      _aplicarBaixaEstoqueDocumentoVendaNaTransacao(
        venda,
        permitirVendaSemEstoque: permitirVendaSemEstoque,
      );
      _db.vendaBox.put(venda);
    });
    _notificarRedeAposEscrita(vendaId: vendaId);
    final chave = chaveAcesso.trim();
    final xml = urlXml.trim();
    if (chave.length >= 40 && xml.isNotEmpty) {
      unawaited(
        NfeXmlLocalService.arquivarOuEnfileirar(
          storeDirectoryPath: _db.storeDirectoryPath,
          chaveAcesso: chave,
          urlXml: xml,
        ),
      );
    }
    final xmlCancel = urlXmlCancelamento.trim();
    if (chave.length >= 40 && xmlCancel.isNotEmpty) {
      unawaited(
        NfeXmlLocalService.arquivarOuEnfileirar(
          storeDirectoryPath: _db.storeDirectoryPath,
          chaveAcesso: chave,
          urlXml: xmlCancel,
          cancelada: true,
        ),
      );
    }
  }

  /// Baixa fisica de retirada imediata — somente ao cupom nao fiscal (idempotente).
  void registrarBaixaEstoqueCupomNaoFiscal(
    int vendaId, {
    bool permitirVendaSemEstoque = true,
  }) {
    Set<int>? produtoIds;
    _db.store.runInTransaction(TxMode.write, () {
      final venda = _db.vendaBox.get(vendaId);
      if (venda == null) {
        throw StateError('Venda $vendaId nao encontrada.');
      }
      final itens = _itensDaVendaGarantidos(venda);
      produtoIds = {
        for (final i in itens)
          if (i.produto.targetId > 0) i.produto.targetId,
      };
      _estoque.registrarBaixaEstoqueCupomNaoFiscal(
        venda: venda,
        permitirVendaSemEstoque: permitirVendaSemEstoque,
        itens: itens,
      );
    });
    _notificarRedeAposEscrita(
      vendaId: vendaId,
      estoqueAlterado: true,
      produtoIds: produtoIds,
    );
  }

  void _registrarContadoresPromocaoAposFinalizar(int vendaId) {
    final venda = _db.vendaBox.get(vendaId);
    if (venda == null) return;
    final porPromo = <int, int>{};
    for (final item in _itensDaVendaGarantidos(venda)) {
      if (item.promocaoId <= 0) continue;
      final q = item.quantidade - item.quantidadeDevolvida;
      if (q <= 0) continue;
      porPromo[item.promocaoId] = (porPromo[item.promocaoId] ?? 0) + q;
    }
    if (porPromo.isEmpty) return;
    final promoRepo = PromocaoRepository(_db);
    for (final e in porPromo.entries) {
      promoRepo.registrarVendaPromocao(e.key, e.value);
    }
  }

  void atualizarQuantidadeItemOrcamento(
    int vendaId,
    int itemId,
    int novaQuantidade, {
    bool permitirVendaSemEstoque = false,
  }) {
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
      final item = _itemPersistidoDaVenda(vendaId, itemId);
      if (item == null) {
        throw StateError('Item $itemId nao encontrado no orcamento.');
      }
      final totalAntes = venda.total;
      final brutoAntes = _calcularBrutoOrcamento(venda.id, venda.valorFrete);
      _estoque.liberarReservaEstoqueItemOrcamento(item);
      item.quantidade = novaQuantidade;
      _db.itemVendaBox.put(item);
      _recalcularTotaisVenda(
        venda,
        totalAntes: totalAntes,
        brutoAntes: brutoAntes,
      );
      _reescalarPagamentosMistoAposMudancaTotal(venda, totalAntes);
    });
    _notificarRedeAposEscrita(vendaId: vendaId);
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
      final item = _itemPersistidoDaVenda(vendaId, itemId);
      if (item == null) {
        throw StateError('Item $itemId nao encontrado no orcamento.');
      }
      final totalAntes = venda.total;
      final brutoAntes = _calcularBrutoOrcamento(venda.id, venda.valorFrete);
      _estoque.liberarReservaEstoqueItemOrcamento(item);
      _db.itemVendaBox.remove(itemId);
      final restantes = listarItensPorVenda(vendaId);
      if (restantes.isEmpty) {
        throw StateError('O orcamento precisa manter ao menos 1 item.');
      }
      _recalcularTotaisVenda(
        venda,
        totalAntes: totalAntes,
        brutoAntes: brutoAntes,
      );
      _reescalarPagamentosMistoAposMudancaTotal(venda, totalAntes);
    });
    _notificarRedeAposEscrita(vendaId: vendaId);
  }

  /// Inclui produto no orcamento pendente (caixa/PDV). Mescla linha se mesmo produto,
  /// [precoTipo] e [tipoEntregaItem].
  void adicionarItemAoOrcamento(
    int vendaId,
    ItemVendaInput input, {
    bool permitirVendaSemEstoque = false,
  }) {
    if (input.quantidade <= 0) {
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
      if (venda.cancelada) {
        throw StateError('Nao e possivel alterar orcamento cancelado.');
      }

      final produto = _db.produtoBox.get(input.produtoId);
      if (produto == null) {
        throw StateError('Produto ${input.produtoId} nao encontrado.');
      }

      final tipoNorm =
          EntregaVendaHelper.normalizarTipoItem(input.tipoEntregaItem);
      final totalAntes = venda.total;
      final brutoAntes = _calcularBrutoOrcamento(venda.id, venda.valorFrete);

      ItemVenda? existente;
      for (final item in listarItensPorVenda(vendaId)) {
        if (item.produto.targetId == input.produtoId &&
            item.precoTipo == input.precoTipo &&
            EntregaVendaHelper.normalizarTipoItem(item.tipoEntregaItem) ==
                tipoNorm) {
          existente = item;
          break;
        }
      }

      if (existente != null) {
        _estoque.liberarReservaEstoqueItemOrcamento(existente);
        existente.quantidade += input.quantidade;
        _db.itemVendaBox.put(existente);
      } else {
        final item = _criarItemVendaFromInput(input, produto);
        item.produto.target = produto;
        item.venda.target = venda;
        _db.itemVendaBox.put(item);
      }

      _recalcularTotaisVenda(
        venda,
        totalAntes: totalAntes,
        brutoAntes: brutoAntes,
      );
      _reescalarPagamentosMistoAposMudancaTotal(venda, totalAntes);
      _sincronizarCabecalhoTipoEntregaOrcamento(venda);
    });
    _notificarRedeAposEscrita(vendaId: vendaId);
  }

  /// Altera [ItemVenda.tipoEntregaItem] no orcamento e atualiza o cabecalho
  /// (`misto` quando houver tipos diferentes). Mescla com linha igual se existir.
  void atualizarTipoEntregaItemOrcamento(
    int vendaId,
    int itemId,
    String novoTipoEntregaItem,
  ) {
    final tipoNorm =
        EntregaVendaHelper.normalizarTipoItem(novoTipoEntregaItem);
    _db.store.runInTransaction(TxMode.write, () {
      final venda = _db.vendaBox.get(vendaId);
      if (venda == null) {
        throw StateError('Orcamento $vendaId nao encontrado.');
      }
      if (venda.status != 'orcamento') {
        throw StateError('Somente orcamentos podem ser alterados.');
      }
      if (venda.cancelada) {
        throw StateError('Nao e possivel alterar orcamento cancelado.');
      }
      final item = _itemPersistidoDaVenda(vendaId, itemId);
      if (item == null) {
        throw StateError('Item $itemId nao encontrado no orcamento.');
      }
      final tipoAtual =
          EntregaVendaHelper.normalizarTipoItem(item.tipoEntregaItem);
      if (tipoAtual == tipoNorm) {
        _sincronizarCabecalhoTipoEntregaOrcamento(venda);
        return;
      }

      ItemVenda? destino;
      for (final outro in listarItensPorVenda(vendaId)) {
        if (outro.id == itemId) continue;
        if (outro.produto.targetId != item.produto.targetId) continue;
        if (outro.precoTipo != item.precoTipo) continue;
        if (EntregaVendaHelper.normalizarTipoItem(outro.tipoEntregaItem) !=
            tipoNorm) {
          continue;
        }
        destino = outro;
        break;
      }

      if (destino != null) {
        destino.quantidade += item.quantidade;
        _db.itemVendaBox.put(destino);
        _db.itemVendaBox.remove(itemId);
      } else {
        item.tipoEntregaItem = tipoNorm;
        _db.itemVendaBox.put(item);
      }
      _sincronizarCabecalhoTipoEntregaOrcamento(venda);
    });
    _notificarRedeAposEscrita(vendaId: vendaId);
  }

  void _sincronizarCabecalhoTipoEntregaOrcamento(Venda venda) {
    final itens = listarItensPorVenda(venda.id);
    final tipos = itens.map((i) => i.tipoEntregaItem);
    venda.tipoEntrega = EntregaVendaHelper.resolverTipoEntregaVenda(tipos);
    venda.entregaPendente =
        EntregaVendaHelper.iterableTemRetiradaFutura(tipos);
    _db.vendaBox.put(venda);
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
    _notificarRedeAposEscrita(vendaId: vendaId);
  }

  void vincularVendedorNoOrcamento(int vendaId, int vendedorId) {
    if (vendedorId <= 0) {
      throw ArgumentError('Informe um vendedor valido.');
    }
    _db.store.runInTransaction(TxMode.write, () {
      final venda = _db.vendaBox.get(vendaId);
      if (venda == null) {
        throw StateError('Orcamento $vendaId nao encontrado.');
      }
      if (venda.status != 'orcamento') {
        throw StateError('Somente orcamentos podem ser alterados.');
      }
      final vendedor = _db.vendedorBox.get(vendedorId);
      if (vendedor == null) {
        throw StateError('Vendedor $vendedorId nao encontrado.');
      }
      venda.vendedor.target = vendedor;
      _db.vendaBox.put(venda);
    });
    _notificarRedeAposEscrita(vendaId: vendaId);
  }

  void registrarNfceEmitida({
    required int vendaId,
    required String chaveAcesso,
    String numero = '',
    String serie = '',
    String protocolo = '',
    String urlDanfe = '',
    String urlXml = '',
    String statusFocus = 'autorizado',
    String urlXmlCancelamento = '',
  }) {
    _db.store.runInTransaction(TxMode.write, () {
      final venda = _db.vendaBox.get(vendaId);
      if (venda == null) {
        throw StateError('Venda $vendaId nao encontrada.');
      }
      _preencherVendaNfceEmitida(
        venda,
        chaveAcesso: chaveAcesso,
        numero: numero,
        serie: serie,
        protocolo: protocolo,
        urlDanfe: urlDanfe,
        urlXml: urlXml,
        statusFocus: statusFocus,
        urlXmlCancelamento: urlXmlCancelamento,
      );
      _db.vendaBox.put(venda);
    });
    _notificarRedeAposEscrita(vendaId: vendaId);
    _arquivarXmlNfceEmitida(
      chaveAcesso: chaveAcesso,
      urlXml: urlXml,
    );
  }

  /// NFC-e autorizada; baixa de estoque e idempotente (ja ocorre na finalizacao).
  void registrarNfceEmitidaComBaixaEstoque({
    required int vendaId,
    required String chaveAcesso,
    String numero = '',
    String serie = '',
    String protocolo = '',
    String urlDanfe = '',
    String urlXml = '',
    String statusFocus = 'autorizado',
    String urlXmlCancelamento = '',
    bool permitirVendaSemEstoque = true,
  }) {
    _db.store.runInTransaction(TxMode.write, () {
      final venda = _db.vendaBox.get(vendaId);
      if (venda == null) {
        throw StateError('Venda $vendaId nao encontrada.');
      }
      _preencherVendaNfceEmitida(
        venda,
        chaveAcesso: chaveAcesso,
        numero: numero,
        serie: serie,
        protocolo: protocolo,
        urlDanfe: urlDanfe,
        urlXml: urlXml,
        statusFocus: statusFocus,
        urlXmlCancelamento: urlXmlCancelamento,
      );
      _aplicarBaixaEstoqueDocumentoVendaNaTransacao(
        venda,
        permitirVendaSemEstoque: permitirVendaSemEstoque,
      );
      _db.vendaBox.put(venda);
    });
    _notificarRedeAposEscrita(vendaId: vendaId);
    _arquivarXmlNfceEmitida(
      chaveAcesso: chaveAcesso,
      urlXml: urlXml,
    );
  }

  void _preencherVendaNfceEmitida(
    Venda venda, {
    required String chaveAcesso,
    String numero = '',
    String serie = '',
    String protocolo = '',
    String urlDanfe = '',
    String urlXml = '',
    String statusFocus = 'autorizado',
    String urlXmlCancelamento = '',
  }) {
    venda.nfceChaveAcesso = chaveAcesso.trim();
    venda.nfceNumero = numero.trim();
    venda.nfceSerie = serie.trim();
    venda.nfceProtocolo = protocolo.trim();
    venda.nfceUrlDanfe = FocusDocumentoFiscalUrl.normalizar(
      urlDanfe,
      apiBaseUrl: FiscalConfig.apiBaseUrl,
    );
    venda.nfceUrlXml = FocusDocumentoFiscalUrl.normalizar(
      urlXml,
      apiBaseUrl: FiscalConfig.apiBaseUrl,
    );
    venda.nfceStatusFocus = statusFocus.trim().isEmpty
        ? 'autorizado'
        : statusFocus.trim();
    venda.nfceUrlXmlCancelamento = urlXmlCancelamento.trim();
    venda.nfceEmitidaEm = DateTime.now().toUtc();
  }

  void _preencherVendaNfe55Situacao(
    Venda venda, {
    required String referenciaFocus,
    String chaveAcesso = '',
    String numero = '',
    String serie = '',
    String protocolo = '',
    String urlDanfe = '',
    String urlXml = '',
    String statusFocus = '',
    String urlXmlCancelamento = '',
    DateTime? emitidaEm,
  }) {
    venda.nfeReferenciaFocus = referenciaFocus.trim();
    venda.nfeChaveAcesso = chaveAcesso.trim();
    venda.nfeNumero = numero.trim();
    venda.nfeSerie = serie.trim();
    venda.nfeProtocolo = protocolo.trim();
    venda.nfeUrlDanfe = urlDanfe.trim();
    venda.nfeUrlXml = urlXml.trim();
    venda.nfeStatusFocus = statusFocus.trim().isEmpty
        ? venda.nfeStatusFocus
        : statusFocus.trim();
    venda.nfeUrlXmlCancelamento = urlXmlCancelamento.trim();
    if (emitidaEm != null) {
      venda.nfeEmitidaEm = emitidaEm.toUtc();
    } else if (venda.nfeEmitidaEm == null && chaveAcesso.isNotEmpty) {
      venda.nfeEmitidaEm = DateTime.now().toUtc();
    }
  }

  void _aplicarBaixaEstoqueDocumentoVendaNaTransacao(
    Venda venda, {
    required bool permitirVendaSemEstoque,
  }) {
    _estoque.registrarBaixaEstoqueCupomNaoFiscal(
      venda: venda,
      permitirVendaSemEstoque: permitirVendaSemEstoque,
      itens: _itensDaVendaGarantidos(venda),
    );
  }

  void _arquivarXmlNfceEmitida({
    required String chaveAcesso,
    required String urlXml,
  }) {
    final chave = chaveAcesso.trim();
    final xml = urlXml.trim();
    if (chave.length >= 40 && xml.isNotEmpty) {
      unawaited(
        NfceXmlLocalService.arquivarOuEnfileirar(
          storeDirectoryPath: _db.storeDirectoryPath,
          chaveAcesso: chave,
          urlXml: xml,
        ),
      );
    }
  }

  void registrarNfceCancelada({
    required int vendaId,
    String statusFocus = 'cancelado',
    String urlXmlCancelamento = '',
    String protocolo = '',
  }) {
    _db.store.runInTransaction(TxMode.write, () {
      final venda = _db.vendaBox.get(vendaId);
      if (venda == null) {
        throw StateError('Venda $vendaId nao encontrada.');
      }
      venda.nfceStatusFocus = statusFocus.trim().isEmpty
          ? 'cancelado'
          : statusFocus.trim();
      if (protocolo.trim().isNotEmpty) {
        venda.nfceProtocolo = protocolo.trim();
      }
      venda.nfceUrlXmlCancelamento = urlXmlCancelamento.trim();
      _db.vendaBox.put(venda);
    });
    _notificarRedeAposEscrita(vendaId: vendaId);
    final venda = _db.vendaBox.get(vendaId);
    final chave = venda?.nfceChaveAcesso.trim() ?? '';
    final xmlCancel = urlXmlCancelamento.trim();
    if (chave.length >= 44 && xmlCancel.isNotEmpty) {
      unawaited(
        NfceXmlLocalService.arquivarOuEnfileirar(
          storeDirectoryPath: _db.storeDirectoryPath,
          chaveAcesso: chave,
          urlXml: xmlCancel,
          cancelada: true,
        ),
      );
    }
  }

  /// NFC-e enviada a Focus com status `processando_autorizacao` (reconsulta depois).
  void registrarNfcePendenteFocus({
    required int vendaId,
    required String referencia,
    String protocolo = '',
    String statusFocus = '',
  }) {
    final ref = referencia.trim();
    final prot = protocolo.trim();
    final status = statusFocus.trim().toLowerCase();
    final marcador = prot.isNotEmpty
        ? prot
        : 'focus_pendente:${status.isNotEmpty ? status : 'processando'}:$ref';
    _db.store.runInTransaction(TxMode.write, () {
      final venda = _db.vendaBox.get(vendaId);
      if (venda == null) {
        throw StateError('Venda $vendaId nao encontrada.');
      }
      if (venda.nfceChaveAcesso.trim().isEmpty) {
        venda.nfceProtocolo = marcador;
        venda.nfceStatusFocus = status.isNotEmpty
            ? status
            : 'processando_autorizacao';
      }
      _db.vendaBox.put(venda);
    });
    _notificarRedeAposEscrita(vendaId: vendaId);
  }

  void registrarNfceEmissaoEmAndamento({
    required int vendaId,
    required String deviceId,
    required String referencia,
  }) {
    _db.store.runInTransaction(TxMode.write, () {
      final venda = _db.vendaBox.get(vendaId);
      if (venda == null || venda.nfceEmitida) return;
      venda.nfceStatusFocus = FiscalEmissaoLock.statusEmAndamento;
      venda.nfceProtocolo =
          FiscalEmissaoLock.marcador(deviceId, referencia);
      _db.vendaBox.put(venda);
    });
    _notificarRedeAposEscrita(vendaId: vendaId);
  }

  void liberarNfceEmissaoEmAndamento(int vendaId) {
    _db.store.runInTransaction(TxMode.write, () {
      final venda = _db.vendaBox.get(vendaId);
      if (venda == null) return;
      if (venda.nfceStatusFocus.trim() != FiscalEmissaoLock.statusEmAndamento) {
        return;
      }
      venda.nfceStatusFocus = '';
      if (FiscalEmissaoLock.ehMarcadorEmissao(venda.nfceProtocolo)) {
        venda.nfceProtocolo = '';
      }
      _db.vendaBox.put(venda);
    });
    _notificarRedeAposEscrita(vendaId: vendaId);
  }

  void registrarNfeEmissaoEmAndamento({
    required int vendaId,
    required String deviceId,
    required String referencia,
  }) {
    _db.store.runInTransaction(TxMode.write, () {
      final venda = _db.vendaBox.get(vendaId);
      if (venda == null || venda.nfe55Autorizada) return;
      venda.nfeStatusFocus = FiscalEmissaoLock.statusEmAndamento;
      venda.nfeProtocolo = FiscalEmissaoLock.marcador(deviceId, referencia);
      _db.vendaBox.put(venda);
    });
    _notificarRedeAposEscrita(vendaId: vendaId);
  }

  void liberarNfeEmissaoEmAndamento(int vendaId) {
    _db.store.runInTransaction(TxMode.write, () {
      final venda = _db.vendaBox.get(vendaId);
      if (venda == null) return;
      if (venda.nfeStatusFocus.trim() != FiscalEmissaoLock.statusEmAndamento) {
        return;
      }
      venda.nfeStatusFocus = '';
      if (FiscalEmissaoLock.ehMarcadorEmissao(venda.nfeProtocolo)) {
        venda.nfeProtocolo = '';
      }
      _db.vendaBox.put(venda);
    });
    _notificarRedeAposEscrita(vendaId: vendaId);
  }

  /// Vendas finalizadas com NFC-e pendente na Focus (reconsulta no caixa).
  List<Venda> listarComNfcePendenteFocus({int limite = 80}) {
    final cond = Venda_.status
        .equals('finalizada')
        .and(Venda_.nfceChaveAcesso.equals(''))
        .and(Venda_.nfceUrlDanfe.equals(''));
    final query = _db.vendaBox
        .query(cond)
        .order(Venda_.id, flags: Order.descending)
        .build();
    try {
      // Overfetch: filtro final usa getter calculado.
      query.limit = (limite * 4).clamp(limite, 400);
      return query
          .find()
          .where((v) => v.nfceProcessandoPendenteFocus)
          .take(limite)
          .toList();
    } finally {
      query.close();
    }
  }

  /// Vendas PIX/cartao finalizadas sem NFC-e (falha ou emissao pulada no caixa).
  List<Venda> listarComNfcePendenteEmissao({
    int limite = 200,
    DateTime? desde,
  }) {
    final cond = Venda_.status
        .equals('finalizada')
        .and(Venda_.cancelada.equals(false))
        .and(Venda_.nfceChaveAcesso.equals(''))
        .and(Venda_.nfceUrlDanfe.equals(''))
        .and(
          Venda_.formaPagamento.oneOf([
            'pix',
            'cartao_credito',
            'cartao_debito',
            'transferencia',
            'misto',
          ]),
        );
    final query = _db.vendaBox
        .query(cond)
        .order(Venda_.id, flags: Order.descending)
        .build();
    try {
      final desdeUtc = desde?.toUtc();
      query.limit = (limite * 4).clamp(limite, 800);
      return query
          .find()
          .where((v) {
            if (desdeUtc != null) {
              final ref = VendaFinalizacaoCaixaHelper.momentoFinalizacao(v);
              if (ref.toUtc().isBefore(desdeUtc)) return false;
            }
            return VendaNfceObrigatoriaHelper.ehPendenteEmissao(v);
          })
          .take(limite)
          .toList();
    } finally {
      query.close();
    }
  }

  int contarComNfcePendenteEmissao() {
    final lista = listarComNfcePendenteEmissao(limite: 500);
    return lista.length;
  }

  /// NFC-e aguardando SEFAZ no periodo da venda (nao entra no ZIP do fechamento).
  List<Venda> listarNfcePendenteFocusNoPeriodo({
    required DateTime inicio,
    required DateTime fim,
  }) {
    final inicioUtc = DateTime(inicio.year, inicio.month, inicio.day).toUtc();
    final fimUtc = DateTime(
      fim.year,
      fim.month,
      fim.day,
      23,
      59,
      59,
      999,
    ).toUtc();
    final cond = Venda_.status
        .equals('finalizada')
        .and(Venda_.nfceChaveAcesso.equals(''))
        .and(Venda_.nfceUrlDanfe.equals(''))
        .and(Venda_.data.greaterOrEqualDate(inicioUtc))
        .and(Venda_.data.lessOrEqualDate(fimUtc));
    final query = _db.vendaBox
        .query(cond)
        .order(Venda_.id, flags: Order.descending)
        .build();
    try {
      return query.find().where((v) => v.nfceProcessandoPendenteFocus).toList();
    } finally {
      query.close();
    }
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
    _notificarRedeAposEscrita(vendaId: vendaId);
  }

  /// Itens da venda cujo produto foi excluido ou nunca vinculado.
  List<ItemVenda> listarItensSemProdutoVinculado(int vendaId) {
    return ItemVendaProdutoOrfaoHelper.filtrarOrfaos(
      listarItensDaVendaGarantidos(vendaId),
      obterProduto: (id) => _db.produtoBox.get(id),
    );
  }

  /// Revincula linhas da venda a produtos existentes no cadastro.
  void revincularItensAoProduto({
    required int vendaId,
    required Map<int, int> itemIdParaProdutoId,
  }) {
    if (itemIdParaProdutoId.isEmpty) return;
    _db.store.runInTransaction(TxMode.write, () {
      final venda = _db.vendaBox.get(vendaId);
      if (venda == null) {
        throw StateError('Venda $vendaId nao encontrada.');
      }
      if (venda.cancelada) {
        throw StateError('Venda cancelada nao pode ser alterada.');
      }
      for (final entry in itemIdParaProdutoId.entries) {
        final itemId = entry.key;
        final produtoId = entry.value;
        if (itemId <= 0 || produtoId <= 0) {
          throw StateError('itemId e produtoId devem ser positivos.');
        }
        final item = _itemPersistidoDaVenda(vendaId, itemId);
        if (item == null) {
          throw StateError('Item $itemId nao encontrado na venda $vendaId.');
        }
        final produto = _db.produtoBox.get(produtoId);
        if (produto == null) {
          throw StateError('Produto $produtoId nao encontrado.');
        }
        item.produto.target = produto;
        _db.itemVendaBox.put(item);
      }
    });
    _notificarRedeAposEscrita(vendaId: vendaId);
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
      _reescalarPagamentosMistoAposMudancaTotal(venda, totalAntesDesconto);
      _db.vendaBox.put(venda);
    });
    _notificarRedeAposEscrita(vendaId: vendaId);
  }

  /// Altera forma de pagamento de um orcamento (autorizado no caixa pelo gerente).
  void alterarPagamentoOrcamento(
    int vendaId,
    DadosPagamentoOrcamento pagamento,
  ) {
    _db.store.runInTransaction(TxMode.write, () {
      final venda = _db.vendaBox.get(vendaId);
      if (venda == null) {
        throw StateError('Orcamento $vendaId nao encontrado.');
      }
      if (venda.status != 'orcamento') {
        throw StateError('Somente orcamentos podem ter pagamento alterado.');
      }
      _aplicarPagamentoNoOrcamento(
        venda,
        pagamento,
        totalOrcamento: venda.total,
      );
      _exigirClienteParaFiado(
        clienteId: venda.cliente.targetId,
        valorFiadoOperacao: LimiteCreditoHelper.valorFiadoNaVenda(venda),
      );
      _aplicarPlanoFiadoNoOrcamento(venda, planoFiado: pagamento.planoFiado);
      _exigirLimiteCredito(
        clienteId: venda.cliente.targetId,
        valorFiadoOperacao: LimiteCreditoHelper.valorFiadoNaVenda(venda),
        ignorarVendaId: vendaId,
      );
      _db.vendaBox.put(venda);
    });
    _notificarRedeAposEscrita(vendaId: vendaId);
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
    _notificarRedeAposEscrita(vendaId: vendaId);
  }

  List<Venda> listarEntregas({
    String? statusEntrega,
    String bairroTermo = '',
    DateTime? inicio,
    DateTime? fim,
  }) {
    return listarEntregasFiltradas(
      FiltroListagemEntregas(
        statusEntrega: statusEntrega ?? 'todos',
        bairroTermo: bairroTermo,
        inicio: inicio,
        fim: fim,
      ),
    );
  }

  /// Hidratacao LAN/celular: todas as abertas + ate [limitEntregues] ja entregues.
  List<Venda> listarEntregasParaHidratacaoApi({int limitEntregues = 500}) {
    final todas = listarEntregasFiltradas(
      const FiltroListagemEntregas(statusEntrega: 'todos'),
    );
    return EntregaListaApi.priorizarParaHidratacao(
      todas,
      limitEntregues: limitEntregues,
    );
  }

  /// Agenda de carretos do mes (vendas + orcamentos com data marcada).
  ///
  /// [incluirProdutos]: mapeia itens (leve; usa nome ja gravado no ItemVenda).
  AgendaCarretoOcupacaoMes ocupacaoAgendaCarretoMes(
    DateTime mesRef, {
    dynamic clienteRepository,
    bool incluirProdutos = true,
  }) {
    final mes = DateTime(mesRef.year, mesRef.month);
    final inicio = DateTime(mes.year, mes.month, 1);
    final fim = DateTime(mes.year, mes.month + 1, 0, 23, 59, 59, 999);
    // Padding UTC para fuso.
    final iniUtc = inicio.toUtc().subtract(const Duration(hours: 14));
    final fimUtc = fim.toUtc().add(const Duration(hours: 14));

    final query = _db.vendaBox
        .query(
          Venda_.cancelada
              .equals(false)
              .and(Venda_.dataEntregaMarcada.greaterOrEqualDate(iniUtc))
              .and(Venda_.dataEntregaMarcada.lessOrEqualDate(fimUtc)),
        )
        .order(Venda_.dataEntregaMarcada)
        .build();
    final itens = <AgendaCarretoOcupacaoItem>[];
    final qtd = <String, int>{};
    try {
      for (final venda in query.find()) {
        if (!AgendaCarretoOcupacaoHelper.contaNaAgenda(venda)) continue;
        final marcada = venda.dataEntregaMarcada;
        if (marcada == null) continue;
        final diaLocal = AgendaCarretoOcupacaoMes.soDia(marcada);
        if (diaLocal.year != mes.year || diaLocal.month != mes.month) {
          continue;
        }
        final produtos = incluirProdutos
            ? AgendaCarretoOcupacaoHelper.mapearProdutos(
                venda,
                listarItensDaVendaGarantidos(venda.id),
              )
            : const <AgendaCarretoProdutoLinha>[];
        final item = AgendaCarretoOcupacaoHelper.itemDeVenda(
          venda,
          clienteRepository: clienteRepository,
          produtos: produtos,
        );
        itens.add(item);
        qtd.update(item.dataChave, (n) => n + 1, ifAbsent: () => 1);
      }
    } finally {
      query.close();
    }
    itens.sort((a, b) {
      final byData = a.dataChave.compareTo(b.dataChave);
      if (byData != 0) return byData;
      return a.numero.compareTo(b.numero);
    });
    return AgendaCarretoOcupacaoMes(
      ano: mes.year,
      mes: mes.month,
      quantidadePorDia: qtd,
      itens: itens,
    );
  }

  /// Consulta ObjectBox (carreto/misto finalizado) + filtros em memoria.
  List<Venda> listarEntregasFiltradas(FiltroListagemEntregas filtro) {
    final candidatas = _consultarEntregasCarretoNoBanco(
      statusEntrega: filtro.statusEntrega,
      inicio: filtro.inicio,
      fim: filtro.fim,
      dataMarcadaInicio: filtro.dataMarcadaInicio,
      dataMarcadaFim: filtro.dataMarcadaFim,
    );
    return _aplicarFiltrosEntregasEmMemoria(candidatas, filtro);
  }

  /// Pagina sobre o mesmo conjunto de [listarEntregasFiltradas] (ordenado por data desc).
  List<Venda> listarEntregasPaginadas(
    FiltroListagemEntregas filtro, {
    int offset = 0,
    int limit = 50,
  }) {
    if (limit <= 0) return const [];
    final todas = listarEntregasFiltradas(filtro);
    if (offset >= todas.length) return const [];
    final fim = offset + limit;
    return todas.sublist(
      offset,
      fim > todas.length ? todas.length : fim,
    );
  }

  /// Lista + contadores de resumo em uma unica passagem no banco.
  ResultadoListagemEntregas carregarListagemEntregasComResumo({
    required FiltroListagemEntregas filtroLista,
    required FiltroListagemEntregas filtroContagem,
  }) {
    final baseContagem = _consultarEntregasCarretoNoBanco(
      statusEntrega: filtroContagem.statusEntrega,
      inicio: filtroContagem.inicio,
      fim: filtroContagem.fim,
      dataMarcadaInicio: filtroContagem.dataMarcadaInicio,
      dataMarcadaFim: filtroContagem.dataMarcadaFim,
    );
    final paraContagem =
        _aplicarFiltrosEntregasEmMemoria(baseContagem, filtroContagem);
    var atrasadas = 0;
    var pendentesHoje = 0;
    for (final v in paraContagem) {
      if (EntregaFiltroUtil.ehAtrasada(v)) atrasadas++;
      if (EntregaFiltroUtil.ehAgendaHoje(v)) pendentesHoje++;
    }

    final candidatasLista = _consultarEntregasCarretoNoBanco(
      statusEntrega: filtroLista.statusEntrega,
      inicio: filtroLista.inicio,
      fim: filtroLista.fim,
      dataMarcadaInicio: filtroLista.dataMarcadaInicio,
      dataMarcadaFim: filtroLista.dataMarcadaFim,
    );
    final lista = _aplicarFiltrosEntregasEmMemoria(candidatasLista, filtroLista);
    lista.sort(_ordenarEntregasPorPrioridadeEData);

    return ResultadoListagemEntregas(
      entregas: lista,
      atrasadas: atrasadas,
      pendentesHoje: pendentesHoje,
    );
  }

  List<Venda> _consultarEntregasCarretoNoBanco({
    required String statusEntrega,
    DateTime? inicio,
    DateTime? fim,
    DateTime? dataMarcadaInicio,
    DateTime? dataMarcadaFim,
  }) {
    var cond = Venda_.status
        .equals('finalizada')
        .and(Venda_.cancelada.equals(false))
        .and(
          Venda_.tipoEntrega.equals(EntregaVendaHelper.tipoEntregaLoja).or(
            Venda_.tipoEntrega.equals(EntregaVendaHelper.tipoMisto),
          ),
        );
    final statuses = EntregaFiltroUtil.statusesDoFiltro(statusEntrega);
    if (statuses != null) {
      final lista = statuses.toList();
      cond = cond.and(
        lista.length == 1
            ? Venda_.statusEntrega.equals(lista.first)
            : Venda_.statusEntrega.oneOf(lista),
      );
    }
    final inicioUtc = inicio?.toUtc();
    final fimUtc = fim?.toUtc();
    if (inicioUtc != null) {
      cond = cond.and(Venda_.data.greaterOrEqualDate(inicioUtc));
    }
    if (fimUtc != null) {
      cond = cond.and(Venda_.data.lessOrEqualDate(fimUtc));
    }
    if (dataMarcadaInicio != null) {
      cond = cond.and(
        Venda_.dataEntregaMarcada.greaterOrEqualDate(
          dataMarcadaInicio.toUtc(),
        ),
      );
    }
    if (dataMarcadaFim != null) {
      cond = cond.and(
        Venda_.dataEntregaMarcada.lessOrEqualDate(dataMarcadaFim.toUtc()),
      );
    }

    final query = _db.vendaBox
        .query(cond)
        .order(Venda_.data, flags: Order.descending)
        .build();
    try {
      final vendas = query.find();
      return vendas
          .where(EntregaVendaHelper.vendaTemItensCarreto)
          .toList(growable: false);
    } finally {
      query.close();
    }
  }

  List<Venda> _aplicarFiltrosEntregasEmMemoria(
    List<Venda> candidatas,
    FiltroListagemEntregas filtro,
  ) {
    return EntregaFiltroUtil.aplicarEmMemoria(candidatas, filtro);
  }

  static int _ordenarEntregasPorPrioridadeEData(Venda a, Venda b) {
    int peso(String p) => switch (p) {
          'urgente' => 3,
          'agendada' => 2,
          _ => 1,
        };
    final byPri = peso(b.prioridadeEntrega).compareTo(peso(a.prioridadeEntrega));
    if (byPri != 0) return byPri;
    return b.data.compareTo(a.data);
  }

  /// Cancela todas as vendas de carreto da aba Entregas e limpa conferencia/historico.
  /// As vendas permanecem no sistema (canceladas), mas somem da aba Entregas.
  ///
  /// Com [forcarQuandoBloqueado], pedidos que nao passam em [cancelarVenda] (ex. retirada
  /// parcial ou devolucao) sao marcados cancelados sem estorno — apenas para limpeza de teste.
  ResultadoLimpezaAbaEntregas limparAbaEntregasCancelandoVendas({
    String motivo = 'Limpeza da aba Entregas',
    String canceladaPor = CanceladaPorRotulo.manutencao,
    bool forcarQuandoBloqueado = false,
  }) {
    final vendas = listarTodas()
        .where(
          (v) =>
              v.status == 'finalizada' &&
              !v.cancelada &&
              EntregaVendaHelper.vendaTemItensCarreto(v),
        )
        .toList();

    final falhas = <String>[];
    var canceladas = 0;
    var forcadas = 0;
    for (final v in vendas) {
      try {
        cancelarVenda(
          v.id,
          motivo: motivo,
          canceladaPor: canceladaPor,
          omitirAuditoriaIndividual: true,
        );
        canceladas++;
      } catch (e) {
        if (forcarQuandoBloqueado) {
          try {
            _cancelarVendaSomenteFlagLimpezaTeste(
              v.id,
              motivo: '$motivo (forcado — sem estorno)',
              canceladaPor: canceladaPor,
            );
            forcadas++;
          } catch (e2) {
            falhas.add('Pedido ${v.numeroOrcamento} (id ${v.id}): $e2');
          }
        } else {
          falhas.add('Pedido ${v.numeroOrcamento} (id ${v.id}): $e');
        }
      }
    }

    var historicosRemovidos = 0;
    final conferenciasRemovidas = _db.conferenciaCargaRomaneioBox.removeAll();

    _db.store.runInTransaction(TxMode.write, () {
      for (final v in vendas) {
        final q = _db.historicoEntregaBox
            .query(HistoricoEntrega_.venda.equals(v.id))
            .build();
        try {
          for (final h in q.find()) {
            _db.historicoEntregaBox.remove(h.id);
            historicosRemovidos++;
          }
        } finally {
          q.close();
        }
      }
    });

    if (canceladas > 0 ||
        forcadas > 0 ||
        conferenciasRemovidas > 0 ||
        historicosRemovidos > 0) {
      _notificarRedeAposEscrita(vendaId: 0);
    }

    return ResultadoLimpezaAbaEntregas(
      canceladas: canceladas,
      forcadas: forcadas,
      falhas: falhas,
      conferenciasRemovidas: conferenciasRemovidas,
      historicosRemovidos: historicosRemovidos,
    );
  }

  /// Marca venda cancelada sem estorno (uso exclusivo em limpeza de teste da aba Entregas).
  void _cancelarVendaSomenteFlagLimpezaTeste(
    int vendaId, {
    required String motivo,
    required String canceladaPor,
  }) {
    _db.store.runInTransaction(TxMode.write, () {
      final venda = _db.vendaBox.get(vendaId);
      if (venda == null) {
        throw StateError('Venda $vendaId nao encontrada.');
      }
      if (venda.cancelada) return;
      venda.cancelada = true;
      venda.motivoCancelamento = motivo.trim();
      venda.canceladaPor = canceladaPor.trim();
      venda.canceladaEm = DateTime.now();
      _db.vendaBox.put(venda);
    });
    _notificarRedeAposEscrita(vendaId: vendaId);
  }

  void atualizarStatusEntrega(
    int vendaId,
    String novoStatus, {
    String? complementoEntregaJson,
    bool retornouParaLoja = false,
  }) {
    _db.store.runInTransaction(TxMode.write, () {
      final venda = _db.vendaBox.get(vendaId);
      if (venda == null) {
        throw StateError('Venda/Orcamento $vendaId nao encontrado.');
      }
      _aplicarMudancaStatusEntregaEmVenda(
        venda,
        novoStatus,
        complementoEntregaJson: complementoEntregaJson,
      );
      _db.vendaBox.put(venda);
    });
    if (novoStatus == 'reagendada' && retornouParaLoja) {
      _aplicarRetornoCargaParaLoja(vendaId);
    }
    final estoqueMudou = novoStatus == 'entregue_complemento_pendente' ||
        novoStatus == 'entregue' ||
        (novoStatus == 'reagendada' && retornouParaLoja);
    _notificarRedeAposEscrita(
      vendaId: vendaId,
      estoqueAlterado: estoqueMudou,
      produtoIds: estoqueMudou ? _produtoIdsPorVendaId(vendaId) : null,
    );
  }

  void _aplicarMudancaStatusEntregaEmVenda(
    Venda venda,
    String novoStatus, {
    String? complementoEntregaJson,
  }) {
    if (!EntregaVendaHelper.vendaTemItensCarreto(venda)) {
      throw StateError(
        'Somente pedidos de entrega podem ter status de entrega.',
      );
    }
    final statusAnterior = venda.statusEntrega;
    if (statusAnterior == novoStatus) return;
    EntregaStatusTransicao.garantirPermitida(statusAnterior, novoStatus);

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
      _estoque.creditarEstoqueComplementoFaltaNaIda(venda, linhas);
    } else if (novoStatus == 'entregue') {
      final linhasComplemento = statusAnterior == 'entregue_complemento_pendente'
          ? ComplementoEntregaCodec.decode(venda.complementoEntregaJson)
          : const <LinhaComplementoEntrega>[];
      venda.statusEntrega = novoStatus;
      venda.complementoEntregaJson = '';
      if (linhasComplemento.isNotEmpty) {
        _estoque.baixarEstoqueComplementoEntregaAoConcluir(
          venda,
          linhasComplemento,
        );
      }
    } else {
      venda.statusEntrega = novoStatus;
    }
  }

  void _putHistoricoStatusEmVenda({
    required Venda venda,
    required String statusAnterior,
    required String statusNovo,
    required String usuario,
  }) {
    final item = HistoricoEntrega(
      statusAnterior: statusAnterior,
      statusNovo: statusNovo,
      usuario: usuario.trim().isEmpty ? 'sistema' : usuario.trim(),
      dataHora: DateTime.now(),
    );
    item.venda.target = venda;
    _db.historicoEntregaBox.put(item);
  }

  void _putOcorrenciaEmVenda({
    required Venda venda,
    required String status,
    required String motivo,
    required String usuario,
  }) {
    final motivoLimpo = motivo.trim();
    if (motivoLimpo.isEmpty) return;
    final quem = usuario.trim().isEmpty ? 'sistema' : usuario.trim();
    _anexarLinhaObservacaoEntregaEmVenda(venda, status, motivoLimpo, quem);
    _putHistoricoStatusEmVenda(
      venda: venda,
      statusAnterior: motivoLimpo,
      statusNovo: status,
      usuario: quem,
    );
  }

  void _aplicarRetornoCargaParaLoja(int vendaId) {
    final venda = _db.vendaBox.get(vendaId);
    if (venda == null || !venda.cargaSaiu) return;
    atualizarChecklistCargaEntrega(vendaId, saiu: false);
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
    _notificarRedeAposEscrita(vendaId: vendaId);
  }

  void atualizarLojaOrigemMercadoria(
    int vendaId,
    String origem, {
    Map<int, String>? origemPorItem,
  }) {
    _db.store.runInTransaction(TxMode.write, () {
      final venda = _db.vendaBox.get(vendaId);
      if (venda == null) {
        throw StateError('Venda/Orcamento $vendaId nao encontrado.');
      }
      _aplicarOrigensMercadoria(
        venda,
        origemPadrao: origem,
        origemPorItem: origemPorItem,
      );
      _db.vendaBox.put(venda);
    });
    _lembrarOrigens(origem, origemPorItem);
    _notificarRedeAposEscrita(vendaId: vendaId);
  }

  /// Motorista solicita / patio confirma itens para buscar nesta loja.
  ///
  /// [quantidadePorItem]: recorte por linha (ex.: 1 de 3 sacos).
  /// Omitido = linha inteira (comportamento antigo).
  void atualizarBuscarNaLoja(
    int vendaId, {
    required String acao,
    required List<int> itemIds,
    required String usuario,
    bool permitirVendaSemEstoque = true,
    Map<int, int>? quantidadePorItem,
  }) {
    final ids = itemIds.where((id) => id > 0).toSet().toList();
    if (ids.isEmpty) {
      throw StateError('Informe ao menos um item da carga.');
    }
    final acaoN = acao.trim().toLowerCase();
    if (acaoN != BuscarNaLoja.solicitar &&
        acaoN != BuscarNaLoja.confirmar &&
        acaoN != BuscarNaLoja.cancelar) {
      throw StateError('Acao invalida para buscar nesta loja.');
    }

    var estoqueMudou = false;
    String motivoOcorrencia = '';
    _db.store.runInTransaction(TxMode.write, () {
      final venda = _db.vendaBox.get(vendaId);
      if (venda == null) {
        throw StateError('Venda/Orcamento $vendaId nao encontrado.');
      }
      if (!EntregaVendaHelper.vendaTemItensCarreto(venda)) {
        throw StateError('Somente entregas da loja podem buscar material aqui.');
      }
      if (venda.cancelada ||
          venda.statusEntrega == 'entregue' ||
          venda.statusEntrega == 'entregue_complemento_pendente' ||
          venda.statusEntrega == 'cancelada') {
        throw StateError(
          'Nao e possivel alterar origem desta entrega no status atual.',
        );
      }

      final afetados = <ItemVenda>[];
      final recemSeparados = <ItemVenda>[];
      final recemDesistidos = <ItemVenda>[];
      final nomes = <String>[];
      for (final id in ids) {
        final item = _db.itemVendaBox.get(id);
        if (item == null || item.venda.targetId != venda.id) {
          throw StateError('Item $id nao pertence a esta entrega.');
        }
        if (acaoN == BuscarNaLoja.solicitar) {
          if (BuscarNaLoja.ehSeparado(item.buscarNaLojaStatus)) continue;
          if (!BuscarNaLoja.ehSolicitado(item.buscarNaLojaStatus) &&
              !BuscarNaLoja.podeSolicitarItem(venda, item)) {
            continue;
          }
          final q = BuscarNaLoja.clampQuantidade(
            venda,
            item,
            quantidadePorItem?[id] ??
                (item.quantidadeBuscarNaLoja > 0
                    ? item.quantidadeBuscarNaLoja
                    : BuscarNaLoja.qtdCarga(venda, item)),
          );
          if (q <= 0) continue;
          item.quantidadeBuscarNaLoja = q;
          item.buscarNaLojaStatus = BuscarNaLoja.solicitado;
          _db.itemVendaBox.put(item);
          afetados.add(item);
          nomes.add(
            '${BuscarNaLoja.rotuloQuantidade(venda, item)} ${item.nomeProduto}',
          );
        } else if (acaoN == BuscarNaLoja.cancelar) {
          final estavaSeparado =
              BuscarNaLoja.ehSeparado(item.buscarNaLojaStatus);
          if (!BuscarNaLoja.ehSolicitado(item.buscarNaLojaStatus) &&
              !estavaSeparado) {
            continue;
          }
          if (estavaSeparado) recemDesistidos.add(item);
          afetados.add(item);
          nomes.add(
            estavaSeparado
                ? '${BuscarNaLoja.rotuloQuantidade(venda, item)} ${item.nomeProduto}'
                : item.nomeProduto,
          );
        } else {
          if (BuscarNaLoja.ehSeparado(item.buscarNaLojaStatus)) {
            afetados.add(item);
            continue;
          }
          if (!BuscarNaLoja.ehSolicitado(item.buscarNaLojaStatus)) {
            throw StateError(
              '"${item.nomeProduto}" ainda nao foi pedido pelo motorista.',
            );
          }
          item.lojaOrigemMercadoria =
              BuscarNaLoja.origemAposConfirmar(venda, item);
          item.buscarNaLojaStatus = BuscarNaLoja.separado;
          _db.itemVendaBox.put(item);
          afetados.add(item);
          recemSeparados.add(item);
          nomes.add(
            '${BuscarNaLoja.rotuloQuantidade(venda, item)} ${item.nomeProduto}',
          );
        }
      }
      if (afetados.isEmpty) {
        throw StateError('Nenhum item da carga se aplica a essa acao.');
      }

      if (acaoN == BuscarNaLoja.cancelar) {
        if (recemDesistidos.isNotEmpty &&
            venda.cargaSaiu &&
            venda.carretoReservaAteSaida &&
            venda.status == 'finalizada') {
          _estoque.estornarFisicoCarretoBuscarNaLoja(
            venda,
            itens: recemDesistidos,
          );
          estoqueMudou = true;
        }
        for (final item in afetados) {
          item.lojaOrigemMercadoria = LojaOrigemMercadoria.outraLoja;
          item.buscarNaLojaStatus = '';
          item.quantidadeBuscarNaLoja = 0;
          _db.itemVendaBox.put(item);
        }
      }

      venda.lojaOrigemMercadoria = LojaOrigemMercadoria.resumo(
        venda.itens.map((i) => i.lojaOrigemMercadoria),
      );

      if (acaoN == BuscarNaLoja.confirmar &&
          recemSeparados.isNotEmpty &&
          venda.cargaSaiu &&
          venda.carretoReservaAteSaida &&
          venda.status == 'finalizada') {
        _estoque.baixarFisicoCarretoAposSaiuOrigemLocal(
          venda,
          itens: recemSeparados,
          permitirVendaSemEstoque: permitirVendaSemEstoque,
        );
        estoqueMudou = true;
      }

      _db.vendaBox.put(venda);

      final quem = usuario.trim().isEmpty ? 'sistema' : usuario.trim();
      if (acaoN == BuscarNaLoja.solicitar) {
        motivoOcorrencia =
            'Motorista: outra loja nao tem. Buscar aqui: ${nomes.join(', ')}';
      } else if (acaoN == BuscarNaLoja.cancelar) {
        motivoOcorrencia = recemDesistidos.isNotEmpty
            ? (venda.cargaSaiu
                ? 'Motorista desistiu apos separacao (devolveu estoque desta loja): '
                    '${nomes.join(', ')}'
                : 'Motorista desistiu apos separacao (chegou na outra loja): '
                    '${nomes.join(', ')}')
            : 'Motorista cancelou buscar nesta loja: ${nomes.join(', ')}';
      } else {
        motivoOcorrencia = venda.cargaSaiu
            ? 'Patio separou nesta loja (baixa estoque): ${nomes.join(', ')}'
            : 'Patio vai separar nesta loja: ${nomes.join(', ')}';
      }
      if (nomes.isNotEmpty) {
        _anexarLinhaObservacaoEntregaEmVenda(
          venda,
          HistoricoEntregaEventos.buscarNaLoja,
          motivoOcorrencia,
          quem,
        );
        final hist = HistoricoEntrega(
          statusAnterior: motivoOcorrencia,
          statusNovo: HistoricoEntregaEventos.buscarNaLoja,
          usuario: quem,
          dataHora: DateTime.now(),
        );
        hist.venda.target = venda;
        _db.historicoEntregaBox.put(hist);
        _db.vendaBox.put(venda);
      }
    });
    _notificarRedeAposEscrita(
      vendaId: vendaId,
      estoqueAlterado: estoqueMudou,
      produtoIds: estoqueMudou ? _produtoIdsPorVendaId(vendaId) : null,
    );
  }

  void atualizarChecklistCargaEntrega(
    int vendaId, {
    bool? separado,
    bool? carregado,
    bool? saiu,
    bool permitirVendaSemEstoque = true,
    bool exigirConferenciaPatio = false,
    String? lojaOrigemMercadoria,
    Map<int, String>? origemPorItem,
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
      if (lojaOrigemMercadoria != null || origemPorItem != null) {
        _aplicarOrigensMercadoria(
          venda,
          origemPadrao: lojaOrigemMercadoria,
          origemPorItem: origemPorItem,
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
          _preencherOrigemPadraoCarretoSeVazio(venda);
          if (exigirConferenciaPatio) {
            final vendasEscopo = _vendasEscopoConferenciaCarreto(venda);
            ConferenciaCargaValidacao.validarAntesMarcarSaiu(
              repository: _conferenciaCarga,
              vendasEscopo: vendasEscopo,
            );
          }
          _estoque.validarEstoqueAntesDespachoCarreto(
            venda,
            permitirVendaSemEstoque: permitirVendaSemEstoque,
          );
          _estoque.baixarEstoqueCarretoAoMarcarSaida(
            venda,
            permitirVendaSemEstoque: permitirVendaSemEstoque,
          );
        } else if (saiuAntes && !saiuDepois) {
          _estoque.estornarBaixaEstoqueCarretoAoDesmarcarSaida(
            venda,
            complementoEntregaJson: venda.complementoEntregaJson,
          );
        }
      }

      _db.vendaBox.put(venda);
    });
    _lembrarOrigens(lojaOrigemMercadoria, origemPorItem);
    final estoqueMudou = saiu != null;
    _notificarRedeAposEscrita(
      vendaId: vendaId,
      estoqueAlterado: estoqueMudou,
      produtoIds: estoqueMudou ? _produtoIdsPorVendaId(vendaId) : null,
    );
  }

  /// Checklist Separado+Carregado+Saiu e status `saiu_entrega`.
  ///
  /// Motorista na outra loja: [exigirConferenciaPatio] = false (nao exige
  /// marcar SKU nesta loja). Pedidos do mesmo grupo saem juntos.
  void liberarSaidaCarreto(
    int vendaId, {
    required String usuario,
    bool exigirConferenciaPatio = false,
    bool incluirGrupo = true,
    bool permitirVendaSemEstoque = true,
  }) {
    final raiz = _db.vendaBox.get(vendaId);
    if (raiz == null) {
      throw StateError('Venda/Orcamento $vendaId nao encontrado.');
    }
    if (!EntregaVendaHelper.vendaTemItensCarreto(raiz)) {
      throw StateError('Somente entregas da loja podem liberar saida.');
    }
    final alvos = incluirGrupo
        ? _vendasEscopoConferenciaCarreto(raiz)
        : [raiz];
    final ids = <int>[];
    for (final v in alvos) {
      if (v.id <= 0) continue;
      if (v.cargaSaiu && v.statusEntrega == 'saiu_entrega') continue;
      if (!EntregaFluxoService.podeLiberarSaida(v)) {
        if (v.id == vendaId) {
          throw StateError(
            'Nao e possivel liberar saida no status "${v.statusEntrega}".',
          );
        }
        continue;
      }
      ids.add(v.id);
    }
    if (ids.isEmpty) return;
    final quem = usuario.trim().isEmpty ? 'motorista' : usuario.trim();
    for (final id in ids) {
      atualizarChecklistCargaEntrega(
        id,
        separado: true,
        carregado: true,
        saiu: true,
        exigirConferenciaPatio: exigirConferenciaPatio,
        permitirVendaSemEstoque: permitirVendaSemEstoque,
      );
      var atual = _db.vendaBox.get(id);
      if (atual == null) continue;
      final statusAnterior = atual.statusEntrega;
      if (atual.statusEntrega == 'pendente' ||
          atual.statusEntrega == 'reagendada') {
        atualizarStatusEntrega(id, 'roteirizada');
        atual = _db.vendaBox.get(id);
        if (atual == null) continue;
      }
      if (atual.statusEntrega == 'roteirizada') {
        atualizarStatusEntrega(id, 'saiu_entrega');
      }
      registrarHistoricoStatusEntrega(
        vendaId: id,
        statusAnterior: statusAnterior,
        statusNovo: 'saiu_entrega',
        usuario: quem,
      );
      registrarOcorrenciaEntrega(
        vendaId: id,
        status: 'saiu_entrega',
        motivo: exigirConferenciaPatio
            ? 'Saida liberada no patio.'
            : 'Motorista liberou a saida pelo celular.',
        usuario: quem,
      );
    }
  }

  void _aplicarOrigensMercadoria(
    Venda venda, {
    String? origemPadrao,
    Map<int, String>? origemPorItem,
  }) {
    final padrao = origemPadrao == null
        ? null
        : LojaOrigemMercadoria.normalizar(origemPadrao);
    final aplicarPadraoEmTodos =
        padrao != null && (origemPorItem == null || origemPorItem.isEmpty);
    for (final item in venda.itens) {
      String? nova;
      if (origemPorItem != null && origemPorItem.containsKey(item.id)) {
        nova = LojaOrigemMercadoria.normalizar(origemPorItem[item.id]);
      } else if (aplicarPadraoEmTodos) {
        nova = padrao;
      }
      if (nova != null) {
        item.lojaOrigemMercadoria = nova;
        _db.itemVendaBox.put(item);
      }
    }
    venda.lojaOrigemMercadoria = LojaOrigemMercadoria.resumo(
      venda.itens.map((i) => i.lojaOrigemMercadoria),
    );
  }

  /// Na saida, item sem origem gravada segue o padrao do carreto (outra loja).
  void _preencherOrigemPadraoCarretoSeVazio(Venda venda) {
    var mudou = false;
    for (final item in venda.itens) {
      if (item.lojaOrigemMercadoria.trim().isNotEmpty) continue;
      item.lojaOrigemMercadoria = LojaOrigemMercadoria.outraLoja;
      _db.itemVendaBox.put(item);
      mudou = true;
    }
    if (mudou || venda.lojaOrigemMercadoria.trim().isEmpty) {
      venda.lojaOrigemMercadoria = LojaOrigemMercadoria.resumo(
        venda.itens.map((i) => i.lojaOrigemMercadoria),
      );
    }
  }

  void _lembrarOrigens(String? origemPadrao, Map<int, String>? origemPorItem) {
    final nomes = <String>[
      if (origemPadrao != null) origemPadrao,
      ...?origemPorItem?.values,
    ];
    for (final n in nomes) {
      final v = LojaOrigemMercadoria.normalizar(n);
      if (v.isEmpty ||
          LojaOrigemMercadoria.ehMisto(v) ||
          LojaOrigemMercadoria.ehLocal(v)) {
        continue;
      }
      unawaited(LojaOrigemRedeStore().lembrar(v));
    }
  }

  List<Venda> _vendasEscopoConferenciaCarreto(Venda venda) {
    final grupoId = venda.grupoEntregaFreteId;
    if (grupoId <= 0) return [venda];
    final query = _db.vendaBox
        .query(Venda_.grupoEntregaFreteId.equals(grupoId))
        .build();
    try {
      final grupo = query.find().where(
        (v) =>
            v.status == 'finalizada' &&
            !v.cancelada &&
            EntregaVendaHelper.vendaTemItensCarreto(v),
      ).toList();
      return grupo.isEmpty ? [venda] : grupo;
    } finally {
      query.close();
    }
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
    _notificarRedeAposEscrita(vendaId: vendaId);
  }

  /// Define o mesmo motorista em varias entregas de carreto (ex.: lote sem motorista).
  int atualizarMotoristaEntregaEmLote(
    Iterable<int> vendaIds,
    String motorista,
  ) {
    final nome = motorista.trim();
    if (nome.isEmpty) {
      throw StateError('Informe o motorista.');
    }
    var alteradas = 0;
    _db.store.runInTransaction(TxMode.write, () {
      for (final id in vendaIds) {
        if (id <= 0) continue;
        final venda = _db.vendaBox.get(id);
        if (venda == null) continue;
        if (!EntregaVendaHelper.vendaTemItensCarreto(venda)) continue;
        venda.motoristaEntrega = nome;
        _db.vendaBox.put(venda);
        alteradas++;
      }
    });
    if (alteradas > 0) _notificarRedeAposEscrita(vendaIds: vendaIds);
    return alteradas;
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
    _notificarRedeAposEscrita(vendaId: vendaId);
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
    _notificarRedeAposEscrita(vendaId: 0);
    return n;
  }

  /// Grava POD (recebido por + foto opcional) sem alterar status.
  void registrarPodEntrega({
    required int vendaId,
    required String recebidoPor,
    required String usuarioLogin,
    String fotoPathLocal = '',
    String fotoPathServidor = '',
  }) {
    final nome = recebidoPor.trim();
    if (nome.isEmpty) {
      throw StateError('Informe quem recebeu a entrega.');
    }
    _db.store.runInTransaction(TxMode.write, () {
      final venda = _db.vendaBox.get(vendaId);
      if (venda == null) {
        throw StateError('Venda $vendaId nao encontrada.');
      }
      venda.podRecebidoPor = nome;
      venda.podRegistradoPor =
          usuarioLogin.trim().isEmpty ? 'sistema' : usuarioLogin.trim();
      venda.podRegistradoEm = DateTime.now();
      venda.podFotoPath = fotoPathLocal.trim();
      venda.podFotoPathServidor = fotoPathServidor.trim();
      _db.vendaBox.put(venda);
    });
    _notificarRedeAposEscrita(vendaId: vendaId);
  }

  /// Baixa atomica do modo motorista (POD + entregue + historico). Idempotente.
  Venda baixarEntregaMotorista({
    required int vendaId,
    required String recebidoPor,
    required String usuarioLogin,
    String fotoPathLocal = '',
    String fotoPathServidor = '',
    String statusAnterior = '',
  }) {
    final nome = recebidoPor.trim();
    if (nome.isEmpty) {
      throw StateError('Informe quem recebeu a entrega.');
    }
    final finalizada = _db.store.runInTransaction(TxMode.write, () {
      final venda = _db.vendaBox.get(vendaId);
      if (venda == null) {
        throw StateError('Venda $vendaId nao encontrada.');
      }
      if (venda.statusEntrega == 'entregue') {
        final temFotoNova = fotoPathServidor.trim().isNotEmpty;
        final faltaFoto = venda.podFotoPathServidor.trim().isEmpty;
        if (temFotoNova && faltaFoto) {
          venda.podRecebidoPor =
              nome.isNotEmpty ? nome : venda.podRecebidoPor;
          venda.podRegistradoPor =
              usuarioLogin.trim().isEmpty ? 'sistema' : usuarioLogin.trim();
          venda.podRegistradoEm = DateTime.now();
          venda.podFotoPath = fotoPathLocal.trim();
          venda.podFotoPathServidor = fotoPathServidor.trim();
          _db.vendaBox.put(venda);
        }
        return venda;
      }
      EntregaStatusTransicao.garantirPermitida(venda.statusEntrega, 'entregue');
      final anterior = statusAnterior.trim().isNotEmpty
          ? statusAnterior.trim()
          : venda.statusEntrega;
      venda.podRecebidoPor = nome;
      venda.podRegistradoPor =
          usuarioLogin.trim().isEmpty ? 'sistema' : usuarioLogin.trim();
      venda.podRegistradoEm = DateTime.now();
      venda.podFotoPath = fotoPathLocal.trim();
      venda.podFotoPathServidor = fotoPathServidor.trim();
      _aplicarMudancaStatusEntregaEmVenda(venda, 'entregue');
      _putHistoricoStatusEmVenda(
        venda: venda,
        statusAnterior: anterior,
        statusNovo: 'entregue',
        usuario: usuarioLogin,
      );
      final temFoto = fotoPathLocal.trim().isNotEmpty ||
          fotoPathServidor.trim().isNotEmpty;
      _putOcorrenciaEmVenda(
        venda: venda,
        status: HistoricoEntregaEventos.podEntrega,
        motivo:
            'Recebido por: $nome${temFoto ? ' (com foto no servidor)' : ''}',
        usuario: usuarioLogin,
      );
      _db.vendaBox.put(venda);
      return venda;
    });
    // Terminais so atualizam PDV/estoque no evento WS `produto`. Sem isso,
    // a quantidade fica stale ate reiniciar (o PC1 le o ObjectBox na hora).
    _notificarRedeAposEscrita(
      vendaId: vendaId,
      estoqueAlterado: true,
      produtoIds: _produtoIdsPorVendaId(vendaId),
    );
    return finalizada;
  }

  /// Insucesso no modo motorista: status [reagendada] + motivo para a loja.
  Venda registrarNaoEntregueMotorista({
    required int vendaId,
    required String motivoCodigo,
    String motivoDetalhe = '',
    required String usuarioLogin,
    String statusAnterior = '',
    bool retornouParaLoja = false,
  }) {
    if (!EntregaNaoEntregueMotivo.valido(motivoCodigo)) {
      throw ArgumentError('Motivo de nao entrega invalido.');
    }
    final snapshot = _db.vendaBox.get(vendaId);
    if (snapshot == null) {
      throw StateError('Venda $vendaId nao encontrada.');
    }
    final jaReagendada = snapshot.statusEntrega == 'reagendada';
    final finalizada = jaReagendada
        ? snapshot
        : _db.store.runInTransaction(TxMode.write, () {
            final venda = _db.vendaBox.get(vendaId);
            if (venda == null) {
              throw StateError('Venda $vendaId nao encontrada.');
            }
            if (venda.statusEntrega == 'reagendada') {
              return venda;
            }
            EntregaStatusTransicao.garantirPermitida(
              venda.statusEntrega,
              'reagendada',
            );
            final anterior = statusAnterior.trim().isNotEmpty
                ? statusAnterior.trim()
                : venda.statusEntrega;
            _aplicarMudancaStatusEntregaEmVenda(venda, 'reagendada');
            _putHistoricoStatusEmVenda(
              venda: venda,
              statusAnterior: anterior,
              statusNovo: 'reagendada',
              usuario: usuarioLogin,
            );
            final cargaTxt = retornouParaLoja
                ? ' Carga retornou para a loja.'
                : ' Carga permanece no caminhao.';
            _putOcorrenciaEmVenda(
              venda: venda,
              status: HistoricoEntregaEventos.naoEntregue,
              motivo: EntregaNaoEntregueMotivo.textoOcorrencia(
                    motivoCodigo,
                    motivoDetalhe,
                  ) +
                  cargaTxt,
              usuario: usuarioLogin,
            );
            _db.vendaBox.put(venda);
            return venda;
          });
    if (retornouParaLoja) {
      _aplicarRetornoCargaParaLoja(vendaId);
    }
    if (!jaReagendada) {
      _notificarRedeAposEscrita(vendaId: vendaId);
    }
    return finalizada;
  }

  /// Entregas ativas do motorista (roteirizada / saiu) para o modo motorista.
  List<Venda> listarEntregasModoMotorista(String nomeMotorista) {
    final alvo = nomeMotorista.trim().toLowerCase();
    if (alvo.isEmpty) return const [];
    final todas = listarEntregasFiltradas(
      const FiltroListagemEntregas(statusEntrega: 'todos'),
    );
    final ativos = <String>{
      'roteirizada',
      'saiu_entrega',
      'entregue_complemento_pendente',
    };
    return todas
        .where((v) {
          if (!ativos.contains(v.statusEntrega)) return false;
          return v.motoristaEntrega.trim().toLowerCase() == alvo;
        })
        .toList()
      ..sort((a, b) {
        final oa = a.ordemEntrega;
        final ob = b.ordemEntrega;
        if (oa > 0 && ob > 0 && oa != ob) return oa.compareTo(ob);
        return a.id.compareTo(b.id);
      });
  }

  void registrarHistoricoStatusEntrega({
    required int vendaId,
    required String statusAnterior,
    required String statusNovo,
    required String usuario,
  }) {
    final novo = statusNovo.trim();
    if (HistoricoEntregaEventos.ehEventoRetirada(novo)) {
      throw StateError(
        'Retirada so pode ser registrada pelo documento de expedicao '
        '(baixa de patio), nao por historico de status.',
      );
    }
    _db.store.runInTransaction(TxMode.write, () {
      final venda = _db.vendaBox.get(vendaId);
      if (venda == null) return;
      final item = HistoricoEntrega(
        statusAnterior: statusAnterior,
        statusNovo: novo,
        usuario: usuario.trim().isEmpty ? 'sistema' : usuario.trim(),
        dataHora: DateTime.now(),
      );
      item.venda.target = venda;
      _db.historicoEntregaBox.put(item);
    });
    _notificarRedeAposEscrita(vendaId: vendaId);
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
    String? detalhesEstruturados,
  }) {
    final motivoLimpo = motivo.trim();
    if (motivoLimpo.isEmpty) return;
    final detalhe = (detalhesEstruturados ?? '').trim();
    if (HistoricoEntregaEventos.ehEventoRetirada(status)) {
      if (RetiradaParcialEvento.tryParse(detalhe) == null) {
        throw StateError(
          'Retirada so pode ser registrada pelo documento de expedicao '
          '(baixa de patio).',
        );
      }
    }
    final quem = usuario.trim().isEmpty ? 'sistema' : usuario.trim();
    _db.store.runInTransaction(TxMode.write, () {
      final venda = _db.vendaBox.get(vendaId);
      if (venda == null) return;
      _anexarLinhaObservacaoEntregaEmVenda(venda, status, motivoLimpo, quem);
      final hist = HistoricoEntrega(
        statusAnterior: detalhe.isNotEmpty ? detalhe : motivoLimpo,
        statusNovo: status,
        usuario: quem,
        dataHora: DateTime.now(),
      );
      hist.venda.target = venda;
      _db.historicoEntregaBox.put(hist);
      _db.vendaBox.put(venda);
    });
    _notificarRedeAposEscrita(vendaId: vendaId);
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
        // Alinha itens + cabecalho: so setar entregaPendente sem mudar tipos
        // fazia o legado no caixa promover "leva agora" a reserva.
        final itens = listarItensPorVenda(vendaId);
        for (final item in itens) {
          if (EntregaVendaHelper.normalizarTipoItem(item.tipoEntregaItem) ==
              EntregaVendaHelper.tipoRetirada) {
            item.tipoEntregaItem = EntregaVendaHelper.tipoRetiradaFutura;
            _db.itemVendaBox.put(item);
          }
        }
        venda.tipoEntrega = EntregaVendaHelper.resolverTipoEntregaVenda(
          itens.map((i) => i.tipoEntregaItem),
        );
        venda.entregaPendente = true;
        _db.vendaBox.put(venda);
        return;
      }

      if (venda.status != 'finalizada') {
        throw StateError(
          'Somente orcamentos ou vendas finalizadas podem ser marcados como retirada futura.',
        );
      }

      _estoque.recomporEstoqueAoMarcarEntregaPendente(venda);

      venda.entregaPendente = true;
      _db.vendaBox.put(venda);
    });
    _notificarRedeAposEscrita(vendaId: vendaId);
  }

  int _proximoNumeroOrcamento() {
    final query = _db.vendaBox
        .query()
        .order(Venda_.numeroOrcamento, flags: Order.descending)
        .build();
    try {
      query.limit = 1;
      final maior = query.findFirst()?.numeroOrcamento ?? 0;
      return maior + 1;
    } finally {
      query.close();
    }
  }

  double _calcularBrutoOrcamento(int vendaId, double valorFrete) {
    final query =
        _db.itemVendaBox.query(ItemVenda_.venda.equals(vendaId)).build();
    try {
      var subtotal = 0.0;
      for (final item in query.find()) {
        subtotal += item.subtotal;
      }
      return subtotal + (valorFrete > 0 ? valorFrete : 0);
    } finally {
      query.close();
    }
  }

  /// Recalcula [Venda.total] a partir dos itens persistidos.
  /// Preserva desconto implicito (ex.: PDV) quando [totalAntes] e [brutoAntes]
  /// sao informados antes de alterar linhas do orcamento.
  void _recalcularTotaisVenda(
    Venda venda, {
    double? totalAntes,
    double? brutoAntes,
  }) {
    final query =
        _db.itemVendaBox.query(ItemVenda_.venda.equals(venda.id)).build();
    try {
      final itens = query.find();
      var subtotal = 0.0;
      var custoTotal = 0.0;
      for (final item in itens) {
        subtotal += item.subtotal;
        custoTotal += item.subtotalCusto;
      }
      final brutoDepois =
          subtotal + (venda.valorFrete > 0 ? venda.valorFrete : 0);
      final preservarDesconto =
          totalAntes != null && brutoAntes != null && brutoAntes > 0.001;
      final descontoImplicito = preservarDesconto
          ? (brutoAntes - totalAntes).clamp(0.0, double.infinity)
          : 0.0;
      venda.total = preservarDesconto
          ? (brutoDepois - descontoImplicito).clamp(0.0, double.infinity)
          : brutoDepois;
      venda.custoTotal = custoTotal;
      venda.lucroTotal = venda.total - custoTotal;
      _db.vendaBox.put(venda);
    } finally {
      query.close();
    }
  }

  /// Mantem soma do misto alinhada ao novo [Venda.total] apos ajuste de itens/desconto.
  void _reescalarPagamentosMistoAposMudancaTotal(
    Venda venda,
    double totalAntes,
  ) {
    if (totalAntes <= 0.001 ||
        venda.formaPagamento != 'misto' ||
        venda.pagamentosJson.trim().isEmpty) {
      return;
    }
    final linhas = PagamentoOrcamentoCodec.decode(venda.pagamentosJson);
    if (linhas.length < 2) return;
    final fator = venda.total / totalAntes;
    final escaladas = linhas
        .map(
          (l) => PagamentoOrcamentoLinha(
            meio: l.meio,
            valor: l.valor * fator,
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
    }
    venda.pagamentosJson = PagamentoOrcamentoCodec.encode(escaladas);
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
    final filtrado = _quantidadesRetiradaPositivas(quantidadePorItemVendaId);
    final usuarioLimpo = usuario.trim().isEmpty ? 'sistema' : usuario.trim();
    final quemRetirou = retiradoPor?.trim() ?? '';
    final linhasEvento = <RetiradaParcialLinhaEvento>[];
    var documento = '';
    var numeroOrcamento = 0;

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
      numeroOrcamento = venda.numeroOrcamento;
      documento = _rotuloDocumentoRetirada(venda);

      for (final e in filtrado.entries) {
        final item = _itemDaVendaParaRetirada(e.key, vendaId);
        if (EntregaVendaHelper.tipoEfetivoItem(item) !=
            EntregaVendaHelper.tipoRetiradaFutura) {
          throw StateError(
            '"${item.nomeProduto}" nao e retirada futura (ja foi leva agora ou carreto).',
          );
        }
        linhasEvento.add(
          _baixarItemRetiradaFormal(
            item: item,
            qRet: e.value,
            usuario: usuarioLimpo,
            permitirSemConferenciaEstoque: permitirSemConferenciaEstoque,
          ),
        );
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
    final vendaPos = _db.vendaBox.get(vendaId);
    _notificarRedeAposEscrita(
      vendaId: vendaId,
      estoqueAlterado: true,
      produtoIds: vendaPos == null ? null : _produtoIdsDaVenda(vendaPos),
    );

    _gravarDocumentoRetirada(
      vendaId: vendaId,
      numeroOrcamento: numeroOrcamento,
      documento: documento,
      tipo: RetiradaParcialEvento.tipoFutura,
      status: HistoricoEntregaEventos.retiradaFutura,
      usuario: usuarioLimpo,
      retiradoPor: quemRetirou,
      linhas: linhasEvento,
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
    final filtrado = _quantidadesRetiradaPositivas(quantidadePorItemVendaId);
    final usuarioLimpo = usuario.trim().isEmpty ? 'sistema' : usuario.trim();
    final quemRetirou = retiradoPor?.trim() ?? '';
    final linhasEvento = <RetiradaParcialLinhaEvento>[];
    var documento = '';
    var numeroOrcamento = 0;

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
      if (!EntregaVendaHelper.vendaTemItensCarreto(venda)) {
        throw StateError(
          'Esta venda nao tem itens de carreto para retirada na loja.',
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
      numeroOrcamento = venda.numeroOrcamento;
      documento = _rotuloDocumentoRetirada(venda);

      for (final e in filtrado.entries) {
        final item = _itemDaVendaParaRetirada(e.key, vendaId);
        if (EntregaVendaHelper.tipoEfetivoItem(item) !=
            EntregaVendaHelper.tipoEntregaLoja) {
          throw StateError(
            '"${item.nomeProduto}" nao e carreto; use retirada futura na listagem.',
          );
        }
        if (EntregaVendaHelper.itemMigradoRetiradaFuturaParaCarreto(item)) {
          throw StateError(
            '"${item.nomeProduto}" migrou de retirada futura: use retirada futura na listagem.',
          );
        }
        linhasEvento.add(
          _baixarItemRetiradaFormal(
            item: item,
            qRet: e.value,
            usuario: usuarioLimpo,
            permitirSemConferenciaEstoque: permitirSemConferenciaEstoque,
          ),
        );
      }

      _db.vendaBox.put(venda);
    });
    final vendaPosCarreto = _db.vendaBox.get(vendaId);
    _notificarRedeAposEscrita(
      vendaId: vendaId,
      estoqueAlterado: true,
      produtoIds: vendaPosCarreto == null
          ? null
          : _produtoIdsDaVenda(vendaPosCarreto),
    );

    _gravarDocumentoRetirada(
      vendaId: vendaId,
      numeroOrcamento: numeroOrcamento,
      documento: documento,
      tipo: RetiradaParcialEvento.tipoLojaCarreto,
      status: HistoricoEntregaEventos.retiradaLojaPreSaida,
      usuario: usuarioLimpo,
      retiradoPor: quemRetirou,
      linhas: linhasEvento,
    );
  }

  Map<int, int> _quantidadesRetiradaPositivas(Map<int, int> origem) {
    final filtrado = <int, int>{};
    for (final e in origem.entries) {
      if (e.value > 0) filtrado[e.key] = e.value;
    }
    if (filtrado.isEmpty) {
      throw StateError('Informe ao menos uma quantidade a retirar.');
    }
    return filtrado;
  }

  ItemVenda _itemDaVendaParaRetirada(int itemId, int vendaId) {
    final item = _db.itemVendaBox.get(itemId);
    if (item == null) {
      throw StateError('Item de venda $itemId nao encontrado.');
    }
    if (item.venda.targetId != vendaId) {
      throw StateError('Item $itemId nao pertence a esta venda.');
    }
    return item;
  }

  String _rotuloDocumentoRetirada(Venda venda) {
    if (venda.numeroOrcamento > 0) {
      return 'Orcamento #${venda.numeroOrcamento}';
    }
    return 'Venda id ${venda.id}';
  }

  RetiradaParcialLinhaEvento _baixarItemRetiradaFormal({
    required ItemVenda item,
    required int qRet,
    required String usuario,
    required bool permitirSemConferenciaEstoque,
  }) {
    SaldoRetiradaItem.validarRetirada(
      nomeProduto: item.nomeProduto,
      quantidade: item.quantidade,
      quantidadeJaRetirada: item.quantidadeJaRetirada,
      quantidadeDevolvida: item.quantidadeDevolvida,
      quantidadeSolicitada: qRet,
    );
    final produto = item.produto.target;
    if (produto == null) {
      throw StateError('Produto do item ${item.id} nao encontrado.');
    }
    final jaAntes = item.quantidadeJaRetirada;
    _estoque.baixarReservaEFisicoRetirada(
      item: item,
      quantidade: qRet,
      tipo: TipoMovimentoEstoque.retiradaParcialCliente,
      permitirSemConferenciaEstoque: permitirSemConferenciaEstoque,
      usuarioLogin: usuario,
    );
    item.quantidadeJaRetirada += qRet;
    _db.itemVendaBox.put(item);
    return RetiradaParcialLinhaEvento(
      itemVendaId: item.id,
      nomeProduto: item.nomeProduto,
      quantidade: qRet,
      vendido: item.quantidade,
      jaRetiradaAntes: jaAntes,
      quantidadeDevolvida: item.quantidadeDevolvida,
    );
  }

  void _gravarDocumentoRetirada({
    required int vendaId,
    required int numeroOrcamento,
    required String documento,
    required String tipo,
    required String status,
    required String usuario,
    required String retiradoPor,
    required List<RetiradaParcialLinhaEvento> linhas,
  }) {
    final agora = DateTime.now().toUtc();
    final evento = RetiradaParcialEvento(
      vendaId: vendaId,
      numeroOrcamento: numeroOrcamento,
      documento: documento,
      tipo: tipo,
      usuario: usuario,
      retiradoPor: retiradoPor,
      dataHora: agora,
      linhas: linhas,
    );
    registrarOcorrenciaEntrega(
      vendaId: vendaId,
      status: status,
      motivo: evento.textoHumano,
      usuario: usuario,
      detalhesEstruturados: evento.encode(),
    );
    AuditoriaRegistrar.registrar(
      modulo: AuditoriaModulo.venda,
      acao: AuditoriaAcao.retiradaParcial,
      usuarioLogin: usuario,
      entidade: 'venda',
      entidadeId: '$vendaId',
      resumo: evento.textoHumano,
      detalhes: {
        'documento': documento,
        'tipo': tipo,
        'retiradoPor': retiradoPor,
        'linhas': linhas.map((l) => l.toJson()).toList(),
      },
      dataHora: agora,
    );
  }

  /// Motivo que impede [cancelarVenda], ou null se puder seguir.
  /// Use antes do cancelamento fiscal na SEFAZ para evitar nota cancelada e venda viva.
  String? mensagemBloqueioCancelamentoVenda(int vendaId) {
    final venda = _db.vendaBox.get(vendaId);
    if (venda == null) return 'Venda $vendaId nao encontrada.';
    if (venda.cancelada) return 'Venda $vendaId ja esta cancelada.';
    if (venda.status == 'orcamento') return null;
    final itens = _itensDaVendaGarantidos(venda);
    if (EntregaVendaHelper.vendaTemRetiradaPatioQueBloqueiaCancelamento(
      venda,
      itens: itens,
    )) {
      return 'Nao e possivel cancelar: ja houve retirada de mercadoria '
          '(retirada futura/carreto) nesta venda. Use devolucao/troca.';
    }
    if (itens.any((i) => i.quantidadeDevolvida > 0)) {
      return 'Nao e possivel cancelar: existem devolucoes/trocas registradas '
          'nesta venda.';
    }
    return null;
  }

  void cancelarVenda(
    int vendaId, {
    String motivo = '',
    String canceladaPor = '',
    bool omitirAuditoriaIndividual = false,
    UsuarioSistema? usuarioExecutor,
  }) {
    if (usuarioExecutor != null) {
      OperacaoPermissaoGuard.exigirCancelarVendas(usuarioExecutor);
    }
    final motivoLimpo = motivo.trim();
    final usuarioCancelamento = canceladaPor.trim();
    var statusAntes = '';
    var numeroOrcamento = 0;
    _db.store.runInTransaction(TxMode.write, () {
      final venda = _db.vendaBox.get(vendaId);
      if (venda == null) {
        throw StateError('Venda $vendaId nao encontrada.');
      }
      statusAntes = venda.status;
      numeroOrcamento = venda.numeroOrcamento;
      if (venda.cancelada) {
        throw StateError('Venda $vendaId ja esta cancelada.');
      }

      final itens = _itensDaVendaGarantidos(venda);
      // "Leva agora" marca quantidadeJaRetirada na baixa do cupom — isso NAO
      // bloqueia cancelar (ha estorno). So bloqueia retirada formal de patio.
      if (venda.status != 'orcamento' &&
          EntregaVendaHelper.vendaTemRetiradaPatioQueBloqueiaCancelamento(
            venda,
            itens: itens,
          )) {
        throw StateError(
          'Nao e possivel cancelar: ja houve retirada de mercadoria '
          '(retirada futura/carreto) nesta venda. Use devolucao/troca.',
        );
      }

      if (venda.status != 'orcamento' &&
          itens.any((i) => i.quantidadeDevolvida > 0)) {
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
        _estoque.liberarReservaEstoqueOrcamento(venda);
        venda.cancelada = true;
        venda.motivoCancelamento = motivoLimpo;
        venda.canceladaPor = usuarioCancelamento;
        venda.canceladaEm = DateTime.now();
        _db.vendaBox.put(venda);
        return;
      }

      _estoque.estornarEstoqueAoCancelarVenda(venda);

      venda.cancelada = true;
      venda.motivoCancelamento = motivoLimpo;
      venda.canceladaPor = usuarioCancelamento;
      venda.canceladaEm = DateTime.now();
      _db.vendaBox.put(venda);
      if (venda.status == 'finalizada') {
        titulos.cancelarPorVenda(vendaId);
        // O que o cliente pagou com vale volta para o vale, senao ele perde
        // o credito por causa de uma venda que nem existe mais.
        _vales.estornarUsosDaVenda(vendaId);
      }
    });
    final vendaPos = _db.vendaBox.get(vendaId);
    _notificarRedeAposEscrita(
      vendaId: vendaId,
      estoqueAlterado: true,
      produtoIds: vendaPos == null ? null : _produtoIdsDaVenda(vendaPos),
    );
    if (!omitirAuditoriaIndividual) {
      _registrarAuditoriaCancelamentoVenda(
        vendaId: vendaId,
        status: statusAntes,
        numeroOrcamento: numeroOrcamento,
        motivo: motivoLimpo,
        canceladaPor: usuarioCancelamento,
      );
    }
  }

  void _registrarAuditoriaCancelamentoVenda({
    required int vendaId,
    required String status,
    required int numeroOrcamento,
    required String motivo,
    required String canceladaPor,
  }) {
    if (status == 'orcamento') {
      AuditoriaRegistrar.registrar(
        modulo: AuditoriaModulo.orcamento,
        acao: AuditoriaAcao.cancelar,
        usuarioLogin: canceladaPor,
        entidade: 'orcamento',
        entidadeId: '$vendaId',
        resumo: 'Orcamento #$numeroOrcamento cancelado',
        detalhes: {
          if (motivo.isNotEmpty) 'motivo': motivo,
          'numeroOrcamento': numeroOrcamento,
        },
      );
      return;
    }
    AuditoriaRegistrar.registrar(
      modulo: AuditoriaModulo.venda,
      acao: AuditoriaAcao.cancelar,
      usuarioLogin: canceladaPor,
      entidade: 'venda',
      entidadeId: '$vendaId',
      resumo: 'Venda cancelada (status: $status)',
      detalhes: {
        if (motivo.isNotEmpty) 'motivo': motivo,
        'status': status,
      },
    );
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
        _estoque.aplicarEntradaDevolucao(
          venda: venda,
          item: item,
          produto: produto,
          qtd: e.quantidade,
        );
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
          _estoque.baixarEstoqueSaidaTroca(
            produto: p,
            quantidade: s.quantidade,
            permitirVendaSemEstoque: permitirVendaSemEstoque,
          );
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
    _notificarRedeAposEscrita(vendaId: vendaOrigemId);
    AuditoriaRegistrar.registrar(
      modulo: AuditoriaModulo.venda,
      acao: tipoLimpo == 'troca'
          ? AuditoriaAcao.troca
          : AuditoriaAcao.devolucao,
      usuarioLogin: registradoPor,
      entidade: 'venda',
      entidadeId: '$vendaOrigemId',
      resumo:
          '${tipoLimpo == 'troca' ? 'Troca' : 'Devolucao'} venda #$vendaOrigemId '
          '(registro #$registroId)',
      detalhes: {
        'registroDevolucaoId': registroId,
        'motivo': motivoLimpo,
        'itensDevolvidos': filtradas.length,
        if (tipoLimpo == 'troca')
          'itensSaida': saidasTroca.where((s) => s.quantidade > 0).length,
      },
    );
    return registroId;
  }

  /// Orcamento na fila do caixa com a diferenca que o cliente paga na troca.
  /// Nao baixa estoque de novo: as pecas ja sairam no registro da troca.
  ({int orcamentoId, int numeroOrcamento, bool reutilizado})
      registrarOrcamentoComplementoTroca({
    required int vendaOrigemId,
    required int registroDevolucaoId,
    required double valor,
    String formaPagamento = 'dinheiro',
    int quantidadeParcelas = 1,
  }) {
    final valorLimpo = TrocaDiferencaCaixa.arredondar(valor);
    if (!TrocaDiferencaCaixa.clientePaga(valorLimpo)) {
      throw StateError('Nao ha diferenca a receber no caixa.');
    }
    if (registroDevolucaoId <= 0) {
      throw StateError('Registro de troca invalido.');
    }
    final uuid = TrocaDiferencaCaixa.uuidOrcamento(registroDevolucaoId);

    final resultado = _db.store.runInTransaction(TxMode.write, () {
      final qExistente = _db.vendaBox
          .query(Venda_.uuidLocal.equals(uuid, caseSensitive: true))
          .build();
      try {
        final ja = qExistente.findFirst();
        if (ja != null) {
          return (
            orcamentoId: ja.id,
            numeroOrcamento: ja.numeroOrcamento,
            reutilizado: true,
          );
        }
      } finally {
        qExistente.close();
      }

      final origem = _db.vendaBox.get(vendaOrigemId);
      if (origem == null) {
        throw StateError('Venda $vendaOrigemId nao encontrada.');
      }
      final produtoId = _estoque.obterOuCriarProdutoComplementoTroca();
      final produto = _db.produtoBox.get(produtoId);
      if (produto == null) {
        throw StateError('Produto interno de complemento de troca nao encontrado.');
      }

      final refOrigem = origem.numeroOrcamento > 0
          ? '${origem.numeroOrcamento}'
          : '$vendaOrigemId';
      final proximoNumero = _proximoNumeroOrcamento();
      final venda = Venda(
        status: 'orcamento',
        numeroOrcamento: proximoNumero,
        formaPagamento: 'dinheiro',
        quantidadeParcelas: 1,
        tipoEntrega: EntregaVendaHelper.tipoRetirada,
        valorFrete: 0,
        entregaPendente: false,
        uuidLocal: uuid,
        observacaoEntrega:
            'Complemento de troca da venda $refOrigem (registro #$registroDevolucaoId).',
      );
      final cliId = origem.cliente.targetId;
      if (cliId != 0) {
        final cli = origem.cliente.target ?? _db.clienteBox.get(cliId);
        if (cli != null) {
          venda.cliente.target = cli;
        }
      }
      final vendId = origem.vendedor.targetId;
      if (vendId != 0) {
        final vend = origem.vendedor.target ?? _db.vendedorBox.get(vendId);
        if (vend != null) {
          venda.vendedor.target = vend;
        }
      }

      final item = ItemVenda(
        nomeProduto: 'Complemento troca venda $refOrigem',
        quantidade: 1,
        precoTipo: 'preco1',
        precoUnitario: valorLimpo,
        precoCustoUnitario: 0,
        tipoEntregaItem: EntregaVendaHelper.tipoRetirada,
      );
      item.produto.target = produto;
      venda.total = valorLimpo;
      venda.custoTotal = 0;
      venda.lucroTotal = valorLimpo;
      final meio = TrocaDiferencaCaixa.normalizarMeio(formaPagamento);
      _aplicarPagamentoNoOrcamento(
        venda,
        DadosPagamentoOrcamento(
          formaPagamento: meio,
          quantidadeParcelas:
              TrocaDiferencaCaixa.parcelasCredito(meio, quantidadeParcelas),
        ),
        totalOrcamento: valorLimpo,
      );
      final vendaId = _db.vendaBox.put(venda);
      venda.id = vendaId;
      item.venda.target = venda;
      _db.itemVendaBox.put(item);
      return (
        orcamentoId: vendaId,
        numeroOrcamento: proximoNumero,
        reutilizado: false,
      );
    });
    _notificarRedeAposEscrita(vendaId: resultado.orcamentoId);
    return resultado;
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
    final pcLuc = <int, double>{};
    final pVendaFat = <int, double>{};
    final pVendaLuc = <int, double>{};
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
      pcLuc[clienteId] = (pcLuc[clienteId] ?? 0) + luc;
      if (vidOrigem > 0) {
        pVendaFat[vidOrigem] = (pVendaFat[vidOrigem] ?? 0) + fat;
        pVendaLuc[vidOrigem] = (pVendaLuc[vidOrigem] ?? 0) + luc;
      }
    }
    return ImpactosDevolucaoTrocaPeriodo(
      impactoFaturamentoTotal: fatT,
      impactoLucroTotal: lucT,
      porVendedorFaturamento: pvFat,
      porVendedorLucro: pvLuc,
      porClienteFaturamento: pcFat,
      porClienteLucro: pcLuc,
      porVendaFaturamento: pVendaFat,
      porVendaLucro: pVendaLuc,
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

  /// Resumo leve para a listagem (chip Dev/Troca no terminal).
  ({bool tem, double valorDevolvido, double valorTroca})
      resumoDevolucaoTrocaListagem(int vendaId) {
    final dev = valorReferenciaDevolvidoAcumuladoVenda(vendaId);
    final troca = valorSaidaTrocaAcumuladoVenda(vendaId);
    return (
      tem: dev > 0.005 || troca > 0.005,
      valorDevolvido: dev,
      valorTroca: troca,
    );
  }

  /// Historico global de transicoes e eventos de entrega (filtro em memoria).
  List<HistoricoEntrega> listarHistoricoEntregaGlobal({
    DateTime? inicio,
    DateTime? fim,
    String termoBusca = '',
  }) {
    final q = _db.historicoEntregaBox
        .query()
        .order(HistoricoEntrega_.dataHora, flags: Order.descending)
        .build();
    try {
      var lista = q.find();
      if (inicio != null) {
        final ini = DateTime(inicio.year, inicio.month, inicio.day);
        lista = lista
            .where((h) => !h.dataHora.toLocal().isBefore(ini))
            .toList();
      }
      if (fim != null) {
        final f = DateTime(fim.year, fim.month, fim.day, 23, 59, 59, 999);
        lista = lista.where((h) => !h.dataHora.toLocal().isAfter(f)).toList();
      }
      final termo = termoBusca.trim().toLowerCase();
      if (termo.isNotEmpty) {
        lista = lista.where((h) {
          final venda = h.venda.target;
          final numOrc = venda?.numeroOrcamento ?? 0;
          final rotulo = HistoricoEntregaEventos.rotulo(h.statusNovo);
          return h.usuario.toLowerCase().contains(termo) ||
              h.statusAnterior.toLowerCase().contains(termo) ||
              h.statusNovo.toLowerCase().contains(termo) ||
              rotulo.toLowerCase().contains(termo) ||
              '$numOrc'.contains(termo);
        }).toList();
      }
      return lista;
    } finally {
      q.close();
    }
  }

}
