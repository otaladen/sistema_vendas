import 'dart:convert';

import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';

import '../../../data/sync/entrega_local_refresh_hub.dart';
import '../../../data/sync/sync_entity_codec.dart';
import '../../../data/sync/sync_entity_codec_extras.dart';
import '../../../data/app_config_repository.dart';
import '../../../data/loja_origem_rede_store.dart';
import '../../../data/venda_repository.dart';
import '../../../domain/entregas/loja_origem_mercadoria.dart';
import '../../../domain/entregas/buscar_na_loja.dart';
import '../../../domain/entrega_pod_nome_arquivo.dart';
import '../../../domain/entrega_status_transicao.dart';
import '../../../domain/pagamento_orcamento.dart';
import '../../../domain/plano_fiado.dart';
import '../../../model/venda.dart';
import '../../../services/auditoria_registrar.dart';
import '../../../services/entrega_pod_paths.dart';
import '../lan_api_caixa_guard.dart';
import '../lan_api_deps.dart';
import '../lan_api_json.dart';
import '../lan_api_nfe_emit.dart';

void registerVendasRoutes(Router router, LanApiDeps d) {
  Map<String, dynamic> vendaListagemParaMap(Venda v) {
    final m = SyncEntityCodec.vendaParaMap(v);
    final r = d.vendaRepository.resumoDevolucaoTrocaListagem(v.id);
    m['temDevolucaoTroca'] = r.tem;
    m['valorDevolvido'] = r.valorDevolvido;
    m['valorTroca'] = r.valorTroca;
    return m;
  }

  String idempotencyKeyOrcamento(Request r, Map<String, dynamic>? body) {
    final doBody = (body?['uuidLocal'] ?? body?['idempotencyKey'] ?? '')
        .toString()
        .trim();
    if (doBody.isNotEmpty) return doBody;
    final h = r.headers['idempotency-key'] ??
        r.headers['Idempotency-Key'] ??
        r.headers['x-idempotency-key'] ??
        '';
    return h.trim();
  }

  Response conflitoStatusEntrega(EntregaStatusConflitoException e) {
    return lanApiJson({'error': e.message, 'code': e.code}, status: 409);
  }

  router.get('/api/orcamentos', (Request r) {
    final items = d.vendaRepository.listarOrcamentosPendentes(
      desde: lanApiQueryDate(r, 'desde'),
      ate: lanApiQueryDate(r, 'ate'),
      limit: lanApiQueryInt(r, 'limit', fallback: 120),
    );
    return lanApiJson({
      'items': items.map(SyncEntityCodec.vendaParaMap).toList(),
    });
  });
  router.get('/api/orcamentos/por-numero', (Request r) {
    final item = d.vendaRepository.buscarOrcamentoPendentePorNumero(
      lanApiQueryInt(r, 'n'),
    );
    return lanApiJson({
      'item': item == null ? null : SyncEntityCodec.vendaParaMap(item),
    });
  });
  router.post('/api/orcamentos', (Request r) async {
    final body = await lanApiReadJsonMap(r);
    final itensRaw = body?['itens'];
    final pagamentoRaw = body?['pagamento'];
    if (itensRaw is! List || itensRaw.isEmpty || pagamentoRaw is! Map) {
      return lanApiJson({
        'error': 'itens e pagamento obrigatorios',
      }, status: 400);
    }
    try {
      final itens = itensRaw.whereType<Map>().map((raw) {
        final m = Map<String, dynamic>.from(raw);
        return ItemVendaInput(
          produtoId: (m['produtoId'] as num?)?.toInt() ?? 0,
          quantidade: (m['quantidade'] as num?)?.toInt() ?? 0,
          precoUnitario: (m['precoUnitario'] as num?)?.toDouble() ?? 0,
          precoTipo: (m['precoTipo'] ?? 'preco1').toString(),
          tipoEntregaItem: (m['tipoEntregaItem'] ?? '').toString(),
          promocaoId: (m['promocaoId'] as num?)?.toInt() ?? 0,
          promocaoNomeSnapshot: (m['promocaoNomeSnapshot'] ?? '').toString(),
          precoUnitarioManual: m['precoUnitarioManual'] == true,
        );
      }).toList();
      final pagamentoMap = Map<String, dynamic>.from(pagamentoRaw);
      final linhasRaw = pagamentoMap['linhasMisto'];
      final planoRaw = pagamentoMap['planoFiado'];
      final pagamento = DadosPagamentoOrcamento(
        formaPagamento: (pagamentoMap['formaPagamento'] ?? 'dinheiro')
            .toString(),
        quantidadeParcelas:
            (pagamentoMap['quantidadeParcelas'] as num?)?.toInt() ?? 1,
        linhasMisto: linhasRaw is List
            ? linhasRaw
                  .whereType<Map>()
                  .map(
                    (e) => PagamentoOrcamentoLinha.fromJson(
                      Map<String, dynamic>.from(e),
                    ),
                  )
                  .toList()
            : null,
        planoFiado: planoRaw is List
            ? PlanoFiadoCodec.decode(jsonEncode(planoRaw))
            : null,
      );
      final entregaMap = body?['entrega'] is Map
          ? Map<String, dynamic>.from(body!['entrega'] as Map)
          : <String, dynamic>{};
      final entrega = DadosEntregaOrcamento(
        tipoEntrega: (entregaMap['tipoEntrega'] ?? 'retirada').toString(),
        valorFrete: (entregaMap['valorFrete'] as num?)?.toDouble() ?? 0,
        enderecoEntrega: (entregaMap['enderecoEntrega'] ?? '').toString(),
        observacaoEntrega: (entregaMap['observacaoEntrega'] ?? '').toString(),
        prioridadeEntrega: (entregaMap['prioridadeEntrega'] ?? 'normal')
            .toString(),
        janelaEntrega: (entregaMap['janelaEntrega'] ?? 'nao_definida')
            .toString(),
        dataEntregaMarcada: DateTime.tryParse(
          (entregaMap['dataEntregaMarcada'] ?? '').toString(),
        )?.toUtc(),
      );
      final idResult = d.vendaRepository.registrarOrcamentoIdempotente(
        itens,
        pagamento: pagamento,
        entrega: entrega,
        clienteId: (body?['clienteId'] as num?)?.toInt(),
        vendedorId: (body?['vendedorId'] as num?)?.toInt(),
        descontoEmReais: (body?['descontoEmReais'] as num?)?.toDouble() ?? 0,
        permitirVendaSemEstoque: body?['permitirVendaSemEstoque'] == true,
        uuidLocal: idempotencyKeyOrcamento(r, body),
      );
      final id = idResult.id;
      final venda = d.vendaRepository.obterPorId(id);
      if (!idResult.reutilizado) {
        d.notificar('venda');
      }
      return lanApiJson({
        'ok': true,
        'id': id,
        'numeroOrcamento': venda?.numeroOrcamento ?? 0,
        'idempotentReuse': idResult.reutilizado,
        'uuidLocal': venda?.uuidLocal ?? '',
        'item': venda == null ? null : SyncEntityCodec.vendaParaMap(venda),
      });
    } catch (e) {
      return lanApiJson({'error': '$e'}, status: 400);
    }
  });

  Future<Response> atualizarOrcamentoHandler(Request r, String id) async {
    final body = await lanApiReadJsonMap(r);
    final itensRaw = body?['itens'];
    final pagamentoRaw = body?['pagamento'];
    if (itensRaw is! List || itensRaw.isEmpty || pagamentoRaw is! Map) {
      return lanApiJson({
        'error': 'itens e pagamento obrigatorios',
      }, status: 400);
    }
    try {
      final itens = itensRaw.whereType<Map>().map((raw) {
        final m = Map<String, dynamic>.from(raw);
        return ItemVendaInput(
          produtoId: (m['produtoId'] as num?)?.toInt() ?? 0,
          quantidade: (m['quantidade'] as num?)?.toInt() ?? 0,
          precoUnitario: (m['precoUnitario'] as num?)?.toDouble() ?? 0,
          precoTipo: (m['precoTipo'] ?? 'preco1').toString(),
          tipoEntregaItem: (m['tipoEntregaItem'] ?? '').toString(),
          promocaoId: (m['promocaoId'] as num?)?.toInt() ?? 0,
          promocaoNomeSnapshot: (m['promocaoNomeSnapshot'] ?? '').toString(),
          precoUnitarioManual: m['precoUnitarioManual'] == true,
        );
      }).toList();
      final pagamentoMap = Map<String, dynamic>.from(pagamentoRaw);
      final linhasRaw = pagamentoMap['linhasMisto'];
      final planoRaw = pagamentoMap['planoFiado'];
      final pagamento = DadosPagamentoOrcamento(
        formaPagamento: (pagamentoMap['formaPagamento'] ?? 'dinheiro')
            .toString(),
        quantidadeParcelas:
            (pagamentoMap['quantidadeParcelas'] as num?)?.toInt() ?? 1,
        linhasMisto: linhasRaw is List
            ? linhasRaw
                  .whereType<Map>()
                  .map(
                    (e) => PagamentoOrcamentoLinha.fromJson(
                      Map<String, dynamic>.from(e),
                    ),
                  )
                  .toList()
            : null,
        planoFiado: planoRaw is List
            ? PlanoFiadoCodec.decode(jsonEncode(planoRaw))
            : null,
      );
      final entregaMap = body?['entrega'] is Map
          ? Map<String, dynamic>.from(body!['entrega'] as Map)
          : <String, dynamic>{};
      final entrega = DadosEntregaOrcamento(
        tipoEntrega: (entregaMap['tipoEntrega'] ?? 'retirada').toString(),
        valorFrete: (entregaMap['valorFrete'] as num?)?.toDouble() ?? 0,
        enderecoEntrega: (entregaMap['enderecoEntrega'] ?? '').toString(),
        observacaoEntrega: (entregaMap['observacaoEntrega'] ?? '').toString(),
        prioridadeEntrega: (entregaMap['prioridadeEntrega'] ?? 'normal')
            .toString(),
        janelaEntrega: (entregaMap['janelaEntrega'] ?? 'nao_definida')
            .toString(),
        dataEntregaMarcada: DateTime.tryParse(
          (entregaMap['dataEntregaMarcada'] ?? '').toString(),
        )?.toUtc(),
      );
      final vendaId = int.parse(id);
      d.vendaRepository.atualizarOrcamento(
        vendaId,
        itens,
        pagamento: pagamento,
        entrega: entrega,
        clienteId: (body?['clienteId'] as num?)?.toInt(),
        vendedorId: (body?['vendedorId'] as num?)?.toInt(),
        descontoEmReais: (body?['descontoEmReais'] as num?)?.toDouble() ?? 0,
        permitirVendaSemEstoque: body?['permitirVendaSemEstoque'] == true,
      );
      final venda = d.vendaRepository.obterPorId(vendaId);
      d.notificar('venda');
      d.notificar('produto');
      return lanApiJson({
        'ok': true,
        'id': vendaId,
        'item': venda == null ? null : SyncEntityCodec.vendaParaMap(venda),
      });
    } catch (e) {
      return lanApiJson({'error': '$e'}, status: 400);
    }
  }

  router.put('/api/orcamentos/<id|[0-9]+>', atualizarOrcamentoHandler);
  router.post('/api/orcamentos/<id|[0-9]+>', atualizarOrcamentoHandler);

  router.get('/api/vendas', (Request r) {
    final limit = lanApiQueryInt(r, 'limit', fallback: 120).clamp(1, 5000);
    final offset = lanApiQueryInt(r, 'offset', fallback: 0).clamp(0, 1000000);
    final status = (r.url.queryParameters['status'] ?? 'todas').trim();
    final desde = lanApiQueryDate(r, 'desde') ?? lanApiQueryDate(r, 'inicio');
    final ate = lanApiQueryDate(r, 'ate') ?? lanApiQueryDate(r, 'fim');
    final clienteId = lanApiQueryInt(r, 'clienteId');
    if (status != 'orcamento' && status != 'finalizada' && status != 'todas') {
      return lanApiJson({'error': 'status invalido'}, status: 400);
    }
    if (clienteId > 0) {
      final compras = d.vendaRepository.listarComprasFinalizadasPorCliente(
        clienteId,
        inicio: desde,
        fim: ate,
      );
      final total = compras.length;
      final totalValor = compras.fold<double>(0, (s, v) => s + v.total);
      final fimFatia = (offset + limit) > total ? total : offset + limit;
      final cortadas =
          offset >= total ? <Venda>[] : compras.sublist(offset, fimFatia);
      return lanApiJson({
        'items': cortadas.map(SyncEntityCodec.vendaParaMap).toList(),
        'total': total,
        'totalValor': totalValor,
        'offset': offset,
        'limit': limit,
      });
    }
    if (status == 'orcamento') {
      final items = d.vendaRepository.listarOrcamentosPendentes(
        desde: desde,
        ate: ate,
      );
      final total = items.length;
      final totalValor = items.fold<double>(0, (s, v) => s + v.total);
      final fimFatia = (offset + limit) > total ? total : offset + limit;
      final pagina =
          offset >= total ? <Venda>[] : items.sublist(offset, fimFatia);
      return lanApiJson({
        'items': pagina.map(SyncEntityCodec.vendaParaMap).toList(),
        'total': total,
        'totalValor': totalValor,
        'offset': offset,
        'limit': limit,
      });
    }
    final q = r.url.queryParameters;
    final filtroCancelamento = (q['filtroCancelamento'] ?? q['cancelamento'] ?? '')
        .trim();
    final cancelamento =
        filtroCancelamento.isEmpty ? 'ativas' : filtroCancelamento;
    final busca = (q['busca'] ?? q['q'] ?? '').trim();
    final pagina = d.vendaRepository.listarListagemVendasPaginaComTotal(
      FiltroListagemVendas(
        textoBusca: busca,
        dataInicioUtc: desde,
        dataFimUtc: ate,
        filtroCancelamento: cancelamento,
        canceladaPorFiltro: (q['canceladaPor'] ?? 'todos').trim().isEmpty
            ? 'todos'
            : (q['canceladaPor'] ?? 'todos').trim(),
        formaPagamento: (q['formaPagamento'] ?? 'todos').trim().isEmpty
            ? 'todos'
            : (q['formaPagamento'] ?? 'todos').trim(),
        tipoEntrega: (q['tipoEntrega'] ?? 'todos').trim().isEmpty
            ? 'todos'
            : (q['tipoEntrega'] ?? 'todos').trim(),
        entregaPendente: (q['entregaPendente'] ?? 'todos').trim().isEmpty
            ? 'todos'
            : (q['entregaPendente'] ?? 'todos').trim(),
        filtroFiscal: (q['filtroFiscal'] ?? 'todos').trim().isEmpty
            ? 'todos'
            : (q['filtroFiscal'] ?? 'todos').trim(),
      ),
      offset: offset,
      limite: limit,
    );
    return lanApiJson({
      'items': pagina.vendas.map(vendaListagemParaMap).toList(),
      'total': pagina.total,
      'totalValor': pagina.totalValor,
      'offset': offset,
      'limit': limit,
    });
  });
  router.get('/api/vendas/<id|[0-9]+>', (Request _, String id) {
    final item = d.vendaRepository.obterPorId(int.parse(id));
    return item == null
        ? lanApiJson({'error': 'nao encontrado'}, status: 404)
        : lanApiJson({'item': SyncEntityCodec.vendaParaMap(item)});
  });
  router.get('/api/vendas/<id|[0-9]+>/itens', (Request _, String id) {
    // Query + fallback ToMany: backlink às vezes nao indexa e a query vem vazia.
    final items =
        d.vendaRepository.listarItensDaVendaGarantidos(int.parse(id));
    return lanApiJson({
      'items': items
          .map(
            (i) => {
              'id': i.id,
              'nomeProduto': i.nomeProduto,
              'quantidade': i.quantidade,
              'quantidadeJaRetirada': i.quantidadeJaRetirada,
              'quantidadeNoCarreto': i.quantidadeNoCarreto,
              'quantidadeDevolvida': i.quantidadeDevolvida,
              'tipoEntregaItem': i.tipoEntregaItem,
              'precoTipo': i.precoTipo,
              'precoUnitario': i.precoUnitario,
              'precoCustoUnitario': i.precoCustoUnitario,
              'promocaoId': i.promocaoId,
              'promocaoNomeSnapshot': i.promocaoNomeSnapshot,
              'precoUnitarioManual': i.precoUnitarioManual,
              'lojaOrigemMercadoria': i.lojaOrigemMercadoria,
              'buscarNaLojaStatus': i.buscarNaLojaStatus,
              'quantidadeBuscarNaLoja': i.quantidadeBuscarNaLoja,
              'produtoId': i.produto.targetId,
            },
          )
          .toList(),
    });
  });
  router.post('/api/vendas/<id|[0-9]+>/finalizar', (
    Request r,
    String id,
  ) async {
    final body = await lanApiReadJsonMap(r) ?? <String, dynamic>{};
    final bloqueio = await lanApiExigirCaixaAberto(r, body: body);
    if (bloqueio != null) return bloqueio;
    try {
      final vendaId = int.parse(id);
      d.vendaRepository.converterOrcamentoParaVenda(
        vendaId,
        permitirVendaSemEstoque: body['permitirVendaSemEstoque'] != false,
      );
      final recebido = (body['valorRecebidoCaixa'] as num?)?.toDouble();
      final troco = (body['valorTrocoCaixa'] as num?)?.toDouble();
      if ((recebido ?? 0) > 0.009 || (troco ?? 0) > 0.009) {
        d.vendaRepository.registrarRecebidoTrocoCaixa(
          vendaId: vendaId,
          valorRecebido: recebido ?? 0,
          valorTroco: troco ?? 0,
        );
      }
      // venda+produto (com ids) ja propagados por VendaRepository / SyncWriteTrigger.
      final produtoIds = d.vendaRepository
          .listarItensPorVenda(vendaId)
          .map((i) => i.produto.targetId)
          .where((pid) => pid > 0)
          .toSet()
          .toList();
      d.notificar('venda');
      d.notificar('produto', ids: produtoIds.isEmpty ? null : produtoIds);
      d.notificar('entrega');
      final item = d.vendaRepository.obterPorId(vendaId);
      return lanApiJson({
        'ok': true,
        'item': item == null ? null : SyncEntityCodec.vendaParaMap(item),
      });
    } catch (e) {
      return lanApiJson({'error': '$e'}, status: 400);
    }
  });

  router.post('/api/vendas/<id|[0-9]+>/cancelar', (Request r, String id) async {
    final body = await lanApiReadJsonMap(r) ?? <String, dynamic>{};
    try {
      final vendaId = int.parse(id);
      d.vendaRepository.cancelarVenda(
        vendaId,
        motivo: (body['motivo'] ?? '').toString(),
        canceladaPor: (body['canceladaPor'] ?? '').toString(),
      );
      // produto (com ids) ja propagado por VendaRepository / SyncWriteTrigger.
      d.notificar('venda');
      d.notificar('titulo_receber');
      final item = d.vendaRepository.obterPorId(vendaId);
      return lanApiJson({
        'ok': true,
        'item': item == null ? null : SyncEntityCodec.vendaParaMap(item),
      });
    } catch (e) {
      return lanApiJson({'error': '$e'}, status: 400);
    }
  });

  /// Cancelamento com NFC-e/NF-e autorizada: SEFAZ (Focus) + ERP no PC1.
  router.post('/api/vendas/<id|[0-9]+>/cancelar-fiscal', (
    Request r,
    String id,
  ) async {
    final body = await lanApiReadJsonMap(r) ?? <String, dynamic>{};
    final vendaId = int.tryParse(id) ?? 0;
    final result = await lanApiCancelarVendaFiscal(
      d,
      vendaId: vendaId,
      justificativa: (body['justificativa'] ?? '').toString(),
      motivo: (body['motivo'] ?? '').toString(),
      canceladaPor: (body['canceladaPor'] ?? '').toString(),
    );
    final status =
        (result['status'] as int?) ?? (result['ok'] == true ? 200 : 400);
    return lanApiJson(result, status: status);
  });

  Response orcamentoMutado(int vendaId) {
    d.notificar('venda');
    d.notificar('produto');
    final item = d.vendaRepository.obterPorId(vendaId);
    return lanApiJson({
      'ok': true,
      'id': vendaId,
      'item': item == null ? null : SyncEntityCodec.vendaParaMap(item),
    });
  }

  DadosPagamentoOrcamento pagamentoDeMap(Map<String, dynamic> pagamentoMap) {
    final linhasRaw = pagamentoMap['linhasMisto'];
    final planoRaw = pagamentoMap['planoFiado'];
    return DadosPagamentoOrcamento(
      formaPagamento: (pagamentoMap['formaPagamento'] ?? 'dinheiro').toString(),
      quantidadeParcelas:
          (pagamentoMap['quantidadeParcelas'] as num?)?.toInt() ?? 1,
      linhasMisto: linhasRaw is List
          ? linhasRaw
                .whereType<Map>()
                .map(
                  (e) => PagamentoOrcamentoLinha.fromJson(
                    Map<String, dynamic>.from(e),
                  ),
                )
                .toList()
          : null,
      planoFiado: planoRaw is List
          ? PlanoFiadoCodec.decode(jsonEncode(planoRaw))
          : null,
    );
  }

  router.post('/api/orcamentos/<id|[0-9]+>/vincular-cliente', (
    Request r,
    String id,
  ) async {
    final body = await lanApiReadJsonMap(r) ?? <String, dynamic>{};
    try {
      final vendaId = int.parse(id);
      final raw = body['clienteId'];
      final clienteId = raw == null ? null : (raw as num).toInt();
      d.vendaRepository.vincularClienteNoOrcamento(
        vendaId,
        clienteId != null && clienteId > 0 ? clienteId : null,
      );
      return orcamentoMutado(vendaId);
    } catch (e) {
      return lanApiJson({'error': '$e'}, status: 400);
    }
  });

  router.post('/api/orcamentos/<id|[0-9]+>/vincular-vendedor', (
    Request r,
    String id,
  ) async {
    final body = await lanApiReadJsonMap(r) ?? <String, dynamic>{};
    try {
      final vendaId = int.parse(id);
      final vendedorId = (body['vendedorId'] as num?)?.toInt() ?? 0;
      if (vendedorId <= 0) {
        return lanApiJson({'error': 'vendedorId obrigatorio'}, status: 400);
      }
      d.vendaRepository.vincularVendedorNoOrcamento(vendaId, vendedorId);
      return orcamentoMutado(vendaId);
    } catch (e) {
      return lanApiJson({'error': '$e'}, status: 400);
    }
  });

  router.post('/api/orcamentos/<id|[0-9]+>/desconto', (
    Request r,
    String id,
  ) async {
    final body = await lanApiReadJsonMap(r) ?? <String, dynamic>{};
    final bloqueio = await lanApiExigirCaixaAberto(
      r,
      body: body,
      mensagem: 'Nao e possivel alterar o orcamento com o caixa fechado.',
    );
    if (bloqueio != null) return bloqueio;
    if (body['exigeGerente'] == true) {
      final gerente = await lanApiExigirGerente(d, body);
      if (gerente != null) return gerente;
    }
    try {
      final vendaId = int.parse(id);
      final valor = (body['valor'] as num?)?.toDouble() ?? 0;
      d.vendaRepository.aplicarDescontoNoOrcamento(vendaId, valor);
      return orcamentoMutado(vendaId);
    } catch (e) {
      return lanApiJson({'error': '$e'}, status: 400);
    }
  });

  router.post('/api/orcamentos/<id|[0-9]+>/itens', (Request r, String id) async {
    final body = await lanApiReadJsonMap(r) ?? <String, dynamic>{};
    final bloqueio = await lanApiExigirCaixaAberto(
      r,
      body: body,
      mensagem: 'Nao e possivel alterar o orcamento com o caixa fechado.',
    );
    if (bloqueio != null) return bloqueio;
    final itemRaw = body['item'];
    if (itemRaw is! Map) {
      return lanApiJson({'error': 'item obrigatorio'}, status: 400);
    }
    try {
      final vendaId = int.parse(id);
      final m = Map<String, dynamic>.from(itemRaw);
      d.vendaRepository.adicionarItemAoOrcamento(
        vendaId,
        ItemVendaInput(
          produtoId: (m['produtoId'] as num?)?.toInt() ?? 0,
          quantidade: (m['quantidade'] as num?)?.toInt() ?? 0,
          precoUnitario: (m['precoUnitario'] as num?)?.toDouble() ?? 0,
          precoTipo: (m['precoTipo'] ?? 'preco1').toString(),
          tipoEntregaItem: (m['tipoEntregaItem'] ?? '').toString(),
          promocaoId: (m['promocaoId'] as num?)?.toInt() ?? 0,
          promocaoNomeSnapshot: (m['promocaoNomeSnapshot'] ?? '').toString(),
          precoUnitarioManual: m['precoUnitarioManual'] == true,
        ),
        permitirVendaSemEstoque: body['permitirVendaSemEstoque'] == true,
      );
      return orcamentoMutado(vendaId);
    } catch (e) {
      return lanApiJson({'error': '$e'}, status: 400);
    }
  });

  router.post(
    '/api/orcamentos/<id|[0-9]+>/itens/<itemId|[0-9]+>/quantidade',
    (Request r, String id, String itemId) async {
      final body = await lanApiReadJsonMap(r) ?? <String, dynamic>{};
      final bloqueio = await lanApiExigirCaixaAberto(
        r,
        body: body,
        mensagem: 'Nao e possivel alterar o orcamento com o caixa fechado.',
      );
      if (bloqueio != null) return bloqueio;
      try {
        final vendaId = int.parse(id);
        d.vendaRepository.atualizarQuantidadeItemOrcamento(
          vendaId,
          int.parse(itemId),
          (body['quantidade'] as num?)?.toInt() ?? 0,
          permitirVendaSemEstoque: body['permitirVendaSemEstoque'] == true,
        );
        return orcamentoMutado(vendaId);
      } catch (e) {
        return lanApiJson({'error': '$e'}, status: 400);
      }
    },
  );

  router.post(
    '/api/orcamentos/<id|[0-9]+>/itens/<itemId|[0-9]+>/tipo-entrega',
    (Request r, String id, String itemId) async {
      final body = await lanApiReadJsonMap(r) ?? <String, dynamic>{};
      final bloqueio = await lanApiExigirCaixaAberto(
        r,
        body: body,
        mensagem: 'Nao e possivel alterar o orcamento com o caixa fechado.',
      );
      if (bloqueio != null) return bloqueio;
      try {
        final vendaId = int.parse(id);
        d.vendaRepository.atualizarTipoEntregaItemOrcamento(
          vendaId,
          int.parse(itemId),
          (body['tipoEntregaItem'] ?? '').toString(),
        );
        return orcamentoMutado(vendaId);
      } catch (e) {
        return lanApiJson({'error': '$e'}, status: 400);
      }
    },
  );

  router.post(
    '/api/orcamentos/<id|[0-9]+>/itens/<itemId|[0-9]+>/remover',
    (Request r, String id, String itemId) async {
      final body = await lanApiReadJsonMap(r) ?? <String, dynamic>{};
      final bloqueio = await lanApiExigirCaixaAberto(
        r,
        body: body,
        mensagem: 'Nao e possivel alterar o orcamento com o caixa fechado.',
      );
      if (bloqueio != null) return bloqueio;
      final gerente = await lanApiExigirGerente(d, body);
      if (gerente != null) return gerente;
      try {
        final vendaId = int.parse(id);
        d.vendaRepository.removerItemOrcamento(vendaId, int.parse(itemId));
        return orcamentoMutado(vendaId);
      } catch (e) {
        return lanApiJson({'error': '$e'}, status: 400);
      }
    },
  );

  router.post('/api/orcamentos/<id|[0-9]+>/pagamento', (
    Request r,
    String id,
  ) async {
    final body = await lanApiReadJsonMap(r) ?? <String, dynamic>{};
    final bloqueio = await lanApiExigirCaixaAberto(
      r,
      body: body,
      mensagem: 'Nao e possivel alterar o orcamento com o caixa fechado.',
    );
    if (bloqueio != null) return bloqueio;
    final gerente = await lanApiExigirGerente(d, body);
    if (gerente != null) return gerente;
    final pagamentoRaw = body['pagamento'];
    if (pagamentoRaw is! Map) {
      return lanApiJson({'error': 'pagamento obrigatorio'}, status: 400);
    }
    try {
      final vendaId = int.parse(id);
      d.vendaRepository.alterarPagamentoOrcamento(
        vendaId,
        pagamentoDeMap(Map<String, dynamic>.from(pagamentoRaw)),
      );
      return orcamentoMutado(vendaId);
    } catch (e) {
      return lanApiJson({'error': '$e'}, status: 400);
    }
  });

  router.post('/api/orcamentos/<id|[0-9]+>/pagamentos-misto', (
    Request r,
    String id,
  ) async {
    final body = await lanApiReadJsonMap(r) ?? <String, dynamic>{};
    final bloqueio = await lanApiExigirCaixaAberto(
      r,
      body: body,
      mensagem: 'Nao e possivel alterar o orcamento com o caixa fechado.',
    );
    if (bloqueio != null) return bloqueio;
    final linhasRaw = body['linhas'];
    if (linhasRaw is! List || linhasRaw.isEmpty) {
      return lanApiJson({'error': 'linhas obrigatorias'}, status: 400);
    }
    try {
      final vendaId = int.parse(id);
      final linhas = linhasRaw
          .whereType<Map>()
          .map(
            (e) => PagamentoOrcamentoLinha.fromJson(
              Map<String, dynamic>.from(e),
            ),
          )
          .toList();
      d.vendaRepository.substituirPagamentosMistoOrcamento(vendaId, linhas);
      return orcamentoMutado(vendaId);
    } catch (e) {
      return lanApiJson({'error': '$e'}, status: 400);
    }
  });

  router.get('/api/entregas', (Request r) {
    final limit = lanApiQueryInt(r, 'limit', fallback: 500);
    return lanApiJson({
      'items': d.vendaRepository
          .listarEntregasParaHidratacaoApi(limitEntregues: limit)
          .map(SyncEntityCodec.vendaParaMap)
          .toList(),
    });
  });

  router.get('/api/entregas/lojas-origem', (_) async {
    try {
      final cfg = await AppConfigRepository().carregarEmpresaConfig();
      final extras = await LojaOrigemRedeStore().listar();
      final lojaAtual = cfg.nomeLoja.trim();
      return lanApiJson({
        'lojaAtual': lojaAtual,
        'opcoes': [
          for (final n in LojaOrigemMercadoria.opcoesPadrao(
            nomeLojaAtual: lojaAtual,
            extras: extras,
          ))
            {'id': n, 'rotulo': n, 'local': false},
          {
            'id': LojaOrigemMercadoria.local,
            'rotulo': LojaOrigemMercadoria.rotulo(
              LojaOrigemMercadoria.local,
              nomeLojaAtual: lojaAtual,
            ),
            'local': true,
          },
        ],
      });
    } catch (e) {
      return lanApiJson({'error': '$e'}, status: 500);
    }
  });

  /// Baixa atomica do modo motorista (POD + status entregue). Idempotente.
  router.post('/api/entregas/baixa', (Request r) async {
    final body = await lanApiReadJsonMap(r);
    if (body == null) {
      return lanApiJson({'error': 'JSON invalido'}, status: 400);
    }
    final vendaId = (body['vendaId'] as num?)?.toInt() ??
        int.tryParse((body['id'] ?? '').toString()) ??
        0;
    if (vendaId <= 0) {
      return lanApiJson({'error': 'vendaId obrigatorio'}, status: 400);
    }
    final recebidoPor = (body['recebidoPor'] ?? '').toString().trim();
    if (recebidoPor.isEmpty) {
      return lanApiJson({'error': 'recebidoPor obrigatorio'}, status: 400);
    }
    try {
      final item = d.vendaRepository.baixarEntregaMotorista(
        vendaId: vendaId,
        recebidoPor: recebidoPor,
        usuarioLogin: (body['usuarioLogin'] ?? '').toString(),
        fotoPathLocal: (body['fotoPathLocal'] ?? '').toString(),
        fotoPathServidor: (body['fotoPathServidor'] ?? '').toString(),
        statusAnterior: (body['statusAnterior'] ?? '').toString(),
      );
      d.notificar('entrega', ids: [vendaId]);
      d.notificar('venda', ids: [vendaId]);
      d.notificar(
        'produto',
        ids: item.itens
            .map((i) => i.produto.targetId)
            .where((id) => id > 0)
            .toList(),
      );
      return lanApiJson({
        'ok': true,
        'item': SyncEntityCodec.vendaParaMap(item),
      });
    } on EntregaStatusConflitoException catch (e) {
      return conflitoStatusEntrega(e);
    } on StateError catch (e) {
      final msg = e.message;
      final notFound = msg.toLowerCase().contains('nao encontrada');
      return lanApiJson({'error': msg}, status: notFound ? 404 : 400);
    } catch (e) {
      return lanApiJson({'error': '$e'}, status: 400);
    }
  });

  /// Insucesso do motorista (ausente / endereco / recusou) → reagendada.
  router.post('/api/entregas/nao-entregue', (Request r) async {
    final body = await lanApiReadJsonMap(r);
    if (body == null) {
      return lanApiJson({'error': 'JSON invalido'}, status: 400);
    }
    final vendaId = (body['vendaId'] as num?)?.toInt() ??
        int.tryParse((body['id'] ?? '').toString()) ??
        0;
    if (vendaId <= 0) {
      return lanApiJson({'error': 'vendaId obrigatorio'}, status: 400);
    }
    final motivoCodigo = (body['motivoCodigo'] ?? '').toString().trim();
    if (motivoCodigo.isEmpty) {
      return lanApiJson({'error': 'motivoCodigo obrigatorio'}, status: 400);
    }
    try {
      final item = d.vendaRepository.registrarNaoEntregueMotorista(
        vendaId: vendaId,
        motivoCodigo: motivoCodigo,
        motivoDetalhe: (body['motivoDetalhe'] ?? '').toString(),
        usuarioLogin: (body['usuarioLogin'] ?? '').toString(),
        statusAnterior: (body['statusAnterior'] ?? '').toString(),
        retornouParaLoja: body['retornouParaLoja'] == true,
      );
      d.notificar('entrega', ids: [vendaId]);
      d.notificar('venda', ids: [vendaId]);
      if (body['retornouParaLoja'] == true) {
        d.notificar(
          'produto',
          ids: item.itens
              .map((i) => i.produto.targetId)
              .where((pid) => pid > 0)
              .toList(),
        );
      }
      return lanApiJson({
        'ok': true,
        'item': SyncEntityCodec.vendaParaMap(item),
      });
    } on EntregaStatusConflitoException catch (e) {
      return conflitoStatusEntrega(e);
    } on ArgumentError catch (e) {
      return lanApiJson({'error': '${e.message}'}, status: 400);
    } on StateError catch (e) {
      final msg = e.message;
      final notFound = msg.toLowerCase().contains('nao encontrada');
      return lanApiJson({'error': msg}, status: notFound ? 404 : 400);
    } catch (e) {
      return lanApiJson({'error': '$e'}, status: 400);
    }
  });

  router.post('/api/entregas/pod-foto', (Request r) async {
    final body = await lanApiReadJsonMap(r);
    final fileName = (body?['fileName'] ?? '').toString().trim();
    final b64 = (body?['contentBase64'] ?? '').toString().trim();
    if (!EntregaPodNomeArquivo.valido(fileName)) {
      return lanApiJson({'error': 'nome de arquivo invalido'}, status: 400);
    }
    if (b64.isEmpty) {
      return lanApiJson({'error': 'contentBase64 obrigatorio'}, status: 400);
    }
    try {
      final bytes = base64Decode(b64);
      final path = await EntregaPodPaths.gravarJpegServidor(
        fileName: fileName,
        bytes: bytes,
      );
      return lanApiJson({
        'ok': true,
        'path': path,
        'fileName': fileName,
      });
    } on FormatException {
      return lanApiJson({'error': 'contentBase64 invalido'}, status: 400);
    } catch (e) {
      final msg = '$e';
      final status = msg.contains('indisponivel') ? 503 : 400;
      return lanApiJson({'error': msg}, status: status);
    }
  });

  router.get('/api/entregas/pod-foto/<fileName>', (
    Request _,
    String fileName,
  ) {
    final nome = Uri.decodeComponent(fileName).trim();
    if (!EntregaPodNomeArquivo.valido(nome)) {
      return lanApiJson({'error': 'nome de arquivo invalido'}, status: 400);
    }
    final file = EntregaPodPaths.arquivoServidorDe(nome);
    if (file == null) {
      return lanApiJson({'error': 'pasta de fotos POD indisponivel'}, status: 503);
    }
    if (!file.existsSync()) {
      return lanApiJson({'error': 'foto nao encontrada'}, status: 404);
    }
    return Response.ok(
      file.readAsBytesSync(),
      headers: {
        'content-type': 'image/jpeg',
        'cache-control': 'private, max-age=86400',
      },
    );
  });

  /// Ocupacao mensal da agenda de carretos (PDV checkout / terminais leves).
  /// Query: mes=YYYY-MM; produtos=0 para omitir itens (calendario mais leve).
  router.get('/api/entregas/ocupacao', (Request r) {
    final mesRaw = (r.url.queryParameters['mes'] ?? '').trim();
    final produtosRaw =
        (r.url.queryParameters['produtos'] ?? '1').trim().toLowerCase();
    final incluirProdutos =
        produtosRaw != '0' && produtosRaw != 'false' && produtosRaw != 'nao';
    DateTime mesRef = DateTime.now();
    if (mesRaw.isNotEmpty) {
      final partes = mesRaw.split('-');
      if (partes.length >= 2) {
        final y = int.tryParse(partes[0]);
        final m = int.tryParse(partes[1]);
        if (y != null && m != null && m >= 1 && m <= 12) {
          mesRef = DateTime(y, m);
        }
      }
    }
    try {
      final ocupacao = d.vendaRepository.ocupacaoAgendaCarretoMes(
        mesRef,
        clienteRepository: d.clienteRepository,
        incluirProdutos: incluirProdutos,
      );
      return lanApiJson(ocupacao.paraMap());
    } catch (e) {
      return lanApiJson({'error': '$e'}, status: 500);
    }
  });
  router.post('/api/entregas/<id|[0-9]+>/status', (Request r, String id) async {
    final body = await lanApiReadJsonMap(r);
    final statusEntrega = (body?['statusEntrega'] ?? '').toString().trim();
    if (statusEntrega.isEmpty) {
      return lanApiJson({'error': 'statusEntrega obrigatorio'}, status: 400);
    }
    try {
      d.vendaRepository.atualizarStatusEntrega(
        int.parse(id),
        statusEntrega,
        complementoEntregaJson: body?['complementoEntregaJson']?.toString(),
        retornouParaLoja: body?['retornouParaLoja'] == true,
      );
      d.notificar('entrega');
      d.notificar('venda');
      final estoqueMudou = statusEntrega == 'entregue_complemento_pendente' ||
          statusEntrega == 'entregue' ||
          (statusEntrega == 'reagendada' &&
              body?['retornouParaLoja'] == true);
      if (estoqueMudou) {
        d.notificar(
          'produto',
          ids: d.vendaRepository
              .listarItensPorVenda(int.parse(id))
              .map((i) => i.produto.targetId)
              .where((pid) => pid > 0)
              .toList(),
        );
      }
      final item = d.vendaRepository.obterPorId(int.parse(id));
      return lanApiJson({
        'ok': true,
        'item': item == null ? null : SyncEntityCodec.vendaParaMap(item),
      });
    } on EntregaStatusConflitoException catch (e) {
      return conflitoStatusEntrega(e);
    } catch (e) {
      return lanApiJson({'error': '$e'}, status: 400);
    }
  });

  router.post('/api/entregas/<id|[0-9]+>/campos', (Request r, String id) async {
    final body = await lanApiReadJsonMap(r) ?? <String, dynamic>{};
    try {
      final vendaId = int.parse(id);
      if (body.containsKey('motoristaEntrega')) {
        d.vendaRepository.atualizarMotoristaEntrega(
          vendaId,
          (body['motoristaEntrega'] ?? '').toString(),
        );
      }
      if (body.containsKey('dataEntregaMarcada')) {
        final raw = body['dataEntregaMarcada'];
        DateTime? data;
        if (raw != null && raw.toString().trim().isNotEmpty) {
          data = DateTime.tryParse(raw.toString())?.toUtc();
        }
        d.vendaRepository.atualizarDataEntregaMarcada(vendaId, data);
      }
      if (body.containsKey('prioridadeEntrega')) {
        d.vendaRepository.atualizarPrioridadeEntrega(
          vendaId,
          (body['prioridadeEntrega'] ?? 'normal').toString(),
        );
      }
      final origemItens = LojaOrigemMercadoria.mapOrigemItensDeJson(
        body['lojaOrigemItens'],
      );
      if (body.containsKey('lojaOrigemMercadoria') &&
          !body.containsKey('cargaSeparada') &&
          !body.containsKey('cargaCarregada') &&
          !body.containsKey('cargaSaiu') &&
          origemItens.isEmpty) {
        d.vendaRepository.atualizarLojaOrigemMercadoria(
          vendaId,
          (body['lojaOrigemMercadoria'] ?? '').toString(),
        );
      }
      if (origemItens.isNotEmpty &&
          !body.containsKey('cargaSeparada') &&
          !body.containsKey('cargaCarregada') &&
          !body.containsKey('cargaSaiu')) {
        d.vendaRepository.atualizarLojaOrigemMercadoria(
          vendaId,
          (body['lojaOrigemMercadoria'] ?? '').toString(),
          origemPorItem: origemItens,
        );
      }
      if (body.containsKey('cargaSeparada') ||
          body.containsKey('cargaCarregada') ||
          body.containsKey('cargaSaiu')) {
        d.vendaRepository.atualizarChecklistCargaEntrega(
          vendaId,
          separado: body.containsKey('cargaSeparada')
              ? body['cargaSeparada'] == true
              : null,
          carregado: body.containsKey('cargaCarregada')
              ? body['cargaCarregada'] == true
              : null,
          saiu: body.containsKey('cargaSaiu') ? body['cargaSaiu'] == true : null,
          lojaOrigemMercadoria: body.containsKey('lojaOrigemMercadoria')
              ? (body['lojaOrigemMercadoria'] ?? '').toString()
              : null,
          origemPorItem: origemItens.isEmpty ? null : origemItens,
        );
      }
      d.notificar('entrega');
      d.notificar('venda');
      if (body.containsKey('cargaSaiu')) {
        d.notificar(
          'produto',
          ids: d.vendaRepository
              .listarItensPorVenda(vendaId)
              .map((i) => i.produto.targetId)
              .where((pid) => pid > 0)
              .toList(),
        );
      }
      final item = d.vendaRepository.obterPorId(vendaId);
      return lanApiJson({
        'ok': true,
        'item': item == null ? null : SyncEntityCodec.vendaParaMap(item),
      });
    } catch (e) {
      return lanApiJson({'error': '$e'}, status: 400);
    }
  });

  router.post('/api/entregas/<id|[0-9]+>/liberar-saida', (
    Request r,
    String id,
  ) async {
    final body = await lanApiReadJsonMap(r) ?? <String, dynamic>{};
    try {
      final vendaId = int.parse(id);
      var permitir = body['permitirVendaSemEstoque'] != false;
      try {
        final cfg = await AppConfigRepository().carregarEmpresaConfig();
        permitir = cfg.permitirVendaSemEstoque;
      } catch (_) {}
      d.vendaRepository.liberarSaidaCarreto(
        vendaId,
        usuario: (body['usuario'] ?? '').toString(),
        exigirConferenciaPatio: body['exigirConferenciaPatio'] == true,
        incluirGrupo: body['incluirGrupo'] != false,
        permitirVendaSemEstoque: permitir,
      );
      d.notificar('entrega');
      d.notificar('venda');
      d.notificar(
        'produto',
        ids: d.vendaRepository
            .listarItensPorVenda(vendaId)
            .map((i) => i.produto.targetId)
            .where((pid) => pid > 0)
            .toList(),
      );
      final item = d.vendaRepository.obterPorId(vendaId);
      return lanApiJson({
        'ok': true,
        'item': item == null ? null : SyncEntityCodec.vendaParaMap(item),
      });
    } catch (e) {
      return lanApiJson({'error': '$e'}, status: 400);
    }
  });

  router.post('/api/entregas/<id|[0-9]+>/buscar-na-loja', (
    Request r,
    String id,
  ) async {
    final body = await lanApiReadJsonMap(r) ?? <String, dynamic>{};
    final acao = (body['acao'] ?? '').toString();
    final rawIds = body['itemIds'];
    final itemIds = <int>[];
    if (rawIds is List) {
      for (final e in rawIds) {
        final n = (e as num?)?.toInt() ?? int.tryParse('$e') ?? 0;
        if (n > 0) itemIds.add(n);
      }
    }
    try {
      final vendaId = int.parse(id);
      var permitir = body['permitirVendaSemEstoque'] != false;
      try {
        final cfg = await AppConfigRepository().carregarEmpresaConfig();
        permitir = cfg.permitirVendaSemEstoque;
      } catch (_) {}
      d.vendaRepository.atualizarBuscarNaLoja(
        vendaId,
        acao: acao,
        itemIds: itemIds,
        usuario: (body['usuario'] ?? '').toString(),
        permitirVendaSemEstoque: permitir,
        quantidadePorItem: BuscarNaLoja.parseQuantidades(body['quantidades']),
      );
      d.notificar('entrega');
      d.notificar('venda');
      d.notificar(
        'produto',
        ids: d.vendaRepository
            .listarItensPorVenda(vendaId)
            .map((i) => i.produto.targetId)
            .where((pid) => pid > 0)
            .toList(),
      );
      final item = d.vendaRepository.obterPorId(vendaId);
      return lanApiJson({
        'ok': true,
        'item': item == null ? null : SyncEntityCodec.vendaParaMap(item),
      });
    } catch (e) {
      return lanApiJson({'error': '$e'}, status: 400);
    }
  });

  router.post('/api/entregas/grupo', (Request r) async {
    final body = await lanApiReadJsonMap(r) ?? <String, dynamic>{};
    final idsRaw = body['ids'];
    if (idsRaw is! List || idsRaw.isEmpty) {
      return lanApiJson({'error': 'ids obrigatorios'}, status: 400);
    }
    try {
      final ids = idsRaw
          .map((e) => (e as num).toInt())
          .where((id) => id > 0)
          .toSet();
      d.vendaRepository.definirGrupoEntregaLogistica(
        ids,
        motoristaEntrega: (body['motoristaEntrega'] ?? '').toString(),
      );
      d.notificar('entrega');
      d.notificar('venda');
      return lanApiJson({'ok': true, 'count': ids.length});
    } catch (e) {
      return lanApiJson({'error': '$e'}, status: 400);
    }
  });

  router.post('/api/entregas/grupo/limpar', (Request r) async {
    final body = await lanApiReadJsonMap(r) ?? <String, dynamic>{};
    final idsRaw = body['ids'];
    if (idsRaw is! List || idsRaw.isEmpty) {
      return lanApiJson({'error': 'ids obrigatorios'}, status: 400);
    }
    try {
      final ids = idsRaw
          .map((e) => (e as num).toInt())
          .where((id) => id > 0)
          .toSet();
      d.vendaRepository.limparGrupoEntregaLogisticaEm(ids);
      d.notificar('entrega');
      d.notificar('venda');
      return lanApiJson({'ok': true, 'count': ids.length});
    } catch (e) {
      return lanApiJson({'error': '$e'}, status: 400);
    }
  });

  router.post('/api/entregas/grupo/motorista', (Request r) async {
    final body = await lanApiReadJsonMap(r) ?? <String, dynamic>{};
    final grupoId = (body['grupoId'] as num?)?.toInt() ?? 0;
    final motorista = (body['motoristaEntrega'] ?? body['motorista'] ?? '')
        .toString()
        .trim();
    if (grupoId <= 0) {
      return lanApiJson({'error': 'grupoId obrigatorio'}, status: 400);
    }
    if (motorista.isEmpty) {
      return lanApiJson({'error': 'motoristaEntrega obrigatorio'}, status: 400);
    }
    try {
      d.vendaRepository.definirMotoristaEntregaNoGrupo(grupoId, motorista);
      d.notificar('entrega');
      d.notificar('venda');
      return lanApiJson({'ok': true, 'grupoId': grupoId});
    } catch (e) {
      return lanApiJson({'error': '$e'}, status: 400);
    }
  });

  router.post('/api/entregas/grupo/sequencia', (Request r) async {
    final body = await lanApiReadJsonMap(r) ?? <String, dynamic>{};
    final grupoId = (body['grupoId'] as num?)?.toInt() ?? 0;
    final idsRaw = body['ids'] ?? body['vendaIdsOrdenados'];
    if (grupoId <= 0) {
      return lanApiJson({'error': 'grupoId obrigatorio'}, status: 400);
    }
    if (idsRaw is! List || idsRaw.isEmpty) {
      return lanApiJson({'error': 'ids obrigatorios'}, status: 400);
    }
    try {
      final ids = idsRaw.map((e) => (e as num).toInt()).where((id) => id > 0).toList();
      d.vendaRepository.atualizarSequenciaEntregaNoGrupo(grupoId, ids);
      d.notificar('entrega');
      d.notificar('venda');
      return lanApiJson({'ok': true, 'grupoId': grupoId, 'count': ids.length});
    } catch (e) {
      return lanApiJson({'error': '$e'}, status: 400);
    }
  });

  router.post('/api/entregas/motorista/sequencia', (Request r) async {
    final body = await lanApiReadJsonMap(r) ?? <String, dynamic>{};
    final motorista =
        (body['motoristaEntrega'] ?? body['motorista'] ?? '').toString().trim();
    final idsRaw = body['ids'] ?? body['vendaIdsOrdenados'];
    if (motorista.isEmpty) {
      return lanApiJson({'error': 'motoristaEntrega obrigatorio'}, status: 400);
    }
    if (idsRaw is! List || idsRaw.isEmpty) {
      return lanApiJson({'error': 'ids obrigatorios'}, status: 400);
    }
    try {
      final ids = idsRaw.map((e) => (e as num).toInt()).where((id) => id > 0).toList();
      d.vendaRepository.atualizarSequenciaEntregaMotorista(motorista, ids);
      d.notificar('entrega');
      d.notificar('venda');
      return lanApiJson({'ok': true, 'count': ids.length});
    } catch (e) {
      return lanApiJson({'error': '$e'}, status: 400);
    }
  });

  router.get('/api/entregas/<id|[0-9]+>/historico', (Request r, String id) {
    try {
      final vendaId = int.parse(id);
      final items = d.vendaRepository.listarHistoricoEntrega(vendaId);
      return lanApiJson({
        'vendaId': vendaId,
        'items':
            items.map(SyncEntityCodecExtras.historicoEntregaParaMap).toList(),
      });
    } catch (e) {
      return lanApiJson({'error': '$e'}, status: 400);
    }
  });

  /// Proof of Delivery (recebido por + foto opcional).
  router.post('/api/entregas/<id|[0-9]+>/pod', (Request r, String id) async {
    final body = await lanApiReadJsonMap(r) ?? <String, dynamic>{};
    final recebidoPor = (body['recebidoPor'] ?? '').toString().trim();
    if (recebidoPor.isEmpty) {
      return lanApiJson({'error': 'recebidoPor obrigatorio'}, status: 400);
    }
    try {
      final vendaId = int.parse(id);
      d.vendaRepository.registrarPodEntrega(
        vendaId: vendaId,
        recebidoPor: recebidoPor,
        usuarioLogin: (body['usuarioLogin'] ?? '').toString(),
        fotoPathLocal: (body['fotoPathLocal'] ?? '').toString(),
        fotoPathServidor: (body['fotoPathServidor'] ?? '').toString(),
      );
      final motivoOcorrencia = (body['ocorrenciaMotivo'] ?? '').toString().trim();
      if (motivoOcorrencia.isNotEmpty) {
        d.vendaRepository.registrarOcorrenciaEntrega(
          vendaId: vendaId,
          status: (body['ocorrenciaStatus'] ?? 'pod_entrega').toString(),
          motivo: motivoOcorrencia,
          usuario: (body['usuarioLogin'] ?? '').toString(),
        );
      }
      d.notificar('entrega');
      d.notificar('venda');
      final item = d.vendaRepository.obterPorId(vendaId);
      return lanApiJson({
        'ok': true,
        'item': item == null ? null : SyncEntityCodec.vendaParaMap(item),
      });
    } catch (e) {
      return lanApiJson({'error': '$e'}, status: 400);
    }
  });

  router.post(
      '/api/entregas/<id|[0-9]+>/ocorrencia', (Request r, String id) async {
    final body = await lanApiReadJsonMap(r) ?? <String, dynamic>{};
    final status = (body['status'] ?? '').toString().trim();
    if (status.isEmpty) {
      return lanApiJson({'error': 'status obrigatorio'}, status: 400);
    }
    try {
      d.vendaRepository.registrarOcorrenciaEntrega(
        vendaId: int.parse(id),
        status: status,
        motivo: (body['motivo'] ?? '').toString(),
        usuario: (body['usuario'] ?? '').toString(),
      );
      d.notificar('entrega');
      d.notificar('venda');
      return lanApiJson({'ok': true});
    } catch (e) {
      return lanApiJson({'error': '$e'}, status: 400);
    }
  });

  router.post(
      '/api/entregas/<id|[0-9]+>/historico-status',
      (Request r, String id) async {
    final body = await lanApiReadJsonMap(r) ?? <String, dynamic>{};
    final statusAnterior = (body['statusAnterior'] ?? '').toString();
    final statusNovo = (body['statusNovo'] ?? '').toString().trim();
    if (statusNovo.isEmpty) {
      return lanApiJson({'error': 'statusNovo obrigatorio'}, status: 400);
    }
    try {
      d.vendaRepository.registrarHistoricoStatusEntrega(
        vendaId: int.parse(id),
        statusAnterior: statusAnterior,
        statusNovo: statusNovo,
        usuario: (body['usuario'] ?? '').toString(),
      );
      d.notificar('entrega');
      d.notificar('venda');
      return lanApiJson({'ok': true});
    } catch (e) {
      return lanApiJson({'error': '$e'}, status: 400);
    }
  });

  /// Retirada parcial (futura ou loja/carreto antes da saida).
  router.post(
      '/api/entregas/<id|[0-9]+>/retirada-parcial',
      (Request r, String id) async {
    final body = await lanApiReadJsonMap(r) ?? <String, dynamic>{};
    final tipo = (body['tipo'] ?? 'futura').toString().trim();
    final qRaw = body['quantidades'];
    if (qRaw is! Map) {
      return lanApiJson({'error': 'quantidades obrigatorio'}, status: 400);
    }
    final map = <int, int>{};
    qRaw.forEach((k, v) {
      final itemId = int.tryParse(k.toString()) ?? (k is num ? k.toInt() : 0);
      final q = (v as num?)?.toInt() ?? 0;
      if (itemId > 0 && q > 0) map[itemId] = q;
    });
    if (map.isEmpty) {
      return lanApiJson(
        {'error': 'Informe ao menos uma quantidade a retirar.'},
        status: 400,
      );
    }
    try {
      final vendaId = int.parse(id);
      final usuarioBody = (body['usuario'] ?? '').toString().trim();
      final usuario = usuarioBody.isNotEmpty
          ? usuarioBody
          : AuditoriaRegistrar.usuarioSessao;
      final retiradoPor = (body['retiradoPor'] ?? '').toString().trim();
      if (tipo == 'loja_carreto') {
        d.vendaRepository.registrarRetiradaParcialLojaCarretoAntesSaida(
          vendaId,
          map,
          usuario: usuario,
          retiradoPor: retiradoPor.isEmpty ? null : retiradoPor,
        );
      } else {
        d.vendaRepository.registrarRetiradaParcial(
          vendaId,
          map,
          usuario: usuario,
          retiradoPor: retiradoPor.isEmpty ? null : retiradoPor,
        );
      }
      d.notificar('entrega');
      d.notificar('venda');
      d.notificar('produto');
      final item = d.vendaRepository.obterPorId(vendaId);
      return lanApiJson({
        'ok': true,
        'item': item == null ? null : SyncEntityCodec.vendaParaMap(item),
      });
    } catch (e) {
      return lanApiJson({'error': '$e'}, status: 400);
    }
  });

  router.get('/api/entregas/conferencia', (Request r) {
    final escopo = (r.url.queryParameters['escopo'] ?? '').trim();
    if (escopo.isEmpty) {
      return lanApiJson({'error': 'escopo obrigatorio'}, status: 400);
    }
    final mapa = d.conferenciaCargaRepository.mapaPorEscopo(escopo);
    return lanApiJson({
      'escopo': escopo,
      'items': mapa.entries
          .map((e) => {'chaveProduto': e.key, 'conferido': e.value})
          .toList(),
    });
  });

  router.post('/api/entregas/conferencia', (Request r) async {
    final body = await lanApiReadJsonMap(r) ?? <String, dynamic>{};
    final escopo = (body['escopoViagem'] ?? '').toString().trim();
    final chave = (body['chaveProduto'] ?? '').toString().trim();
    if (escopo.isEmpty || chave.isEmpty) {
      return lanApiJson(
        {'error': 'escopoViagem e chaveProduto obrigatorios'},
        status: 400,
      );
    }
    try {
      d.conferenciaCargaRepository.salvarConferencia(
        escopoViagem: escopo,
        chaveProduto: chave,
        conferido: body['conferido'] == true,
        usuarioLogin: (body['usuarioLogin'] ?? '').toString(),
      );
      d.notificar('conferencia_carga');
      EntregaLocalRefreshHub.instance.notificar();
      return lanApiJson({'ok': true});
    } catch (e) {
      return lanApiJson({'error': '$e'}, status: 400);
    }
  });

  /// Vincula cliente em venda **finalizada** (ex.: frete carreto sem cliente).
  router.post('/api/vendas/<id|[0-9]+>/vincular-cliente', (
    Request r,
    String id,
  ) async {
    final body = await lanApiReadJsonMap(r) ?? <String, dynamic>{};
    final clienteId = (body['clienteId'] as num?)?.toInt() ?? 0;
    if (clienteId <= 0) {
      return lanApiJson({'error': 'clienteId obrigatorio'}, status: 400);
    }
    try {
      final vendaId = int.parse(id);
      d.vendaRepository.vincularClienteVendaFinalizada(vendaId, clienteId);
      d.notificar('venda');
      d.notificar('entrega');
      final item = d.vendaRepository.obterPorId(vendaId);
      return lanApiJson({
        'ok': true,
        'item': item == null ? null : SyncEntityCodec.vendaParaMap(item),
      });
    } catch (e) {
      return lanApiJson({'error': '$e'}, status: 400);
    }
  });

  /// Revincula itens de venda finalizada a produtos do catalogo (cadastro excluido).
  router.post('/api/vendas/<id|[0-9]+>/revincular-itens-produto', (
    Request r,
    String id,
  ) async {
    final body = await lanApiReadJsonMap(r) ?? <String, dynamic>{};
    final raw = body['vinculos'];
    if (raw is! List || raw.isEmpty) {
      return lanApiJson({'error': 'vinculos obrigatorio'}, status: 400);
    }
    final vinculos = <int, int>{};
    for (final entry in raw) {
      if (entry is! Map) continue;
      final itemId = (entry['itemId'] as num?)?.toInt() ?? 0;
      final produtoId = (entry['produtoId'] as num?)?.toInt() ?? 0;
      if (itemId <= 0 || produtoId <= 0) {
        return lanApiJson(
          {'error': 'itemId e produtoId devem ser positivos'},
          status: 400,
        );
      }
      vinculos[itemId] = produtoId;
    }
    if (vinculos.isEmpty) {
      return lanApiJson({'error': 'Nenhum vinculo valido.'}, status: 400);
    }
    try {
      final vendaId = int.parse(id);
      d.vendaRepository.revincularItensAoProduto(
        vendaId: vendaId,
        itemIdParaProdutoId: vinculos,
      );
      d.notificar('venda');
      return lanApiJson({'ok': true, 'revinculados': vinculos.length});
    } catch (e) {
      return lanApiJson({'error': '$e'}, status: 400);
    }
  });

  /// Orcamento filho de frete para retirada futura (carreto).
  router.post('/api/vendas/<id|[0-9]+>/orcamento-frete', (
    Request r,
    String id,
  ) async {
    final body = await lanApiReadJsonMap(r) ?? <String, dynamic>{};
    try {
      final vendaMaeId = int.parse(id);
      final valorFrete = (body['valorFreteCobrado'] as num?)?.toDouble() ?? 0;
      final pag = body['pagamento'];
      final pagamento = DadosPagamentoOrcamento(
        formaPagamento: (pag is Map
                ? (pag['formaPagamento'] ?? 'dinheiro')
                : 'dinheiro')
            .toString(),
        quantidadeParcelas: pag is Map
            ? ((pag['quantidadeParcelas'] as num?)?.toInt() ?? 1)
            : 1,
      );
      final dataRaw = (body['dataEntregaMarcada'] ?? '').toString();
      final dataEntrega = DateTime.tryParse(dataRaw) ?? DateTime.now();
      final novoId = d.vendaRepository.registrarOrcamentoFreteRetiradaFutura(
        vendaMaeId: vendaMaeId,
        valorFreteCobrado: valorFrete,
        pagamento: pagamento,
        enderecoEntrega: (body['enderecoEntrega'] ?? '').toString(),
        observacaoEntrega: (body['observacaoEntrega'] ?? '').toString(),
        prioridadeEntrega: (body['prioridadeEntrega'] ?? 'normal').toString(),
        janelaEntrega: (body['janelaEntrega'] ?? 'nao_definida').toString(),
        dataEntregaMarcada: dataEntrega,
        vendedorId: (body['vendedorId'] as num?)?.toInt(),
      );
      d.notificar('venda');
      d.notificar('entrega');
      final item = d.vendaRepository.obterPorId(novoId);
      return lanApiJson({
        'ok': true,
        'id': novoId,
        'item': item == null ? null : SyncEntityCodec.vendaParaMap(item),
      });
    } catch (e) {
      return lanApiJson({'error': '$e'}, status: 400);
    }
  });

  /// Devolucao / troca (estoque + registro) no PC servidor.
  router.post('/api/vendas/<id|[0-9]+>/devolucao-troca', (
    Request r,
    String id,
  ) async {
    final body = await lanApiReadJsonMap(r) ?? <String, dynamic>{};
    try {
      final vendaOrigemId = int.parse(id);
      final entradasRaw = body['entradas'];
      final entradas = <LinhaDevolucaoEntradaInput>[];
      if (entradasRaw is List) {
        for (final e in entradasRaw) {
          if (e is! Map) continue;
          final itemId = (e['itemVendaId'] as num?)?.toInt() ?? 0;
          final q = (e['quantidade'] as num?)?.toInt() ?? 0;
          if (itemId > 0 && q > 0) {
            entradas.add(
              LinhaDevolucaoEntradaInput(itemVendaId: itemId, quantidade: q),
            );
          }
        }
      }
      final saidasRaw = body['saidasTroca'];
      final saidas = <LinhaTrocaSaidaInput>[];
      if (saidasRaw is List) {
        for (final s in saidasRaw) {
          if (s is! Map) continue;
          final produtoId = (s['produtoId'] as num?)?.toInt() ?? 0;
          final q = (s['quantidade'] as num?)?.toInt() ?? 0;
          if (produtoId <= 0 || q <= 0) continue;
          saidas.add(
            LinhaTrocaSaidaInput(
              produtoId: produtoId,
              quantidade: q,
              precoUnitario: (s['precoUnitario'] as num?)?.toDouble() ?? 0,
              precoTipo: (s['precoTipo'] ?? 'preco1').toString(),
              precoCustoUnitario:
                  (s['precoCustoUnitario'] as num?)?.toDouble() ?? 0,
            ),
          );
        }
      }
      final registroId = d.vendaRepository.registrarDevolucaoOuTroca(
        vendaOrigemId: vendaOrigemId,
        tipo: (body['tipo'] ?? 'devolucao').toString(),
        motivo: (body['motivo'] ?? '').toString(),
        observacaoFinanceira: (body['observacaoFinanceira'] ?? '').toString(),
        registradoPor: (body['registradoPor'] ?? 'sistema').toString(),
        entradas: entradas,
        saidasTroca: saidas,
        permitirVendaSemEstoque: body['permitirVendaSemEstoque'] != false,
      );
      d.notificar('venda');
      d.notificar('produto');
      d.notificar('entrega');
      final item = d.vendaRepository.obterPorId(vendaOrigemId);
      return lanApiJson({
        'ok': true,
        'registroId': registroId,
        'item': item == null ? null : SyncEntityCodec.vendaParaMap(item),
      });
    } catch (e) {
      return lanApiJson({'error': '$e'}, status: 400);
    }
  });

  /// Diferenca da troca: orcamento na fila do caixa (sem nova baixa de estoque).
  router.post('/api/vendas/<id|[0-9]+>/complemento-troca', (
    Request r,
    String id,
  ) async {
    final body = await lanApiReadJsonMap(r) ?? <String, dynamic>{};
    try {
      final vendaOrigemId = int.parse(id);
      final criado = d.vendaRepository.registrarOrcamentoComplementoTroca(
        vendaOrigemId: vendaOrigemId,
        registroDevolucaoId: (body['registroId'] as num?)?.toInt() ?? 0,
        valor: (body['valor'] as num?)?.toDouble() ?? 0,
        formaPagamento: (body['formaPagamento'] ?? 'dinheiro').toString(),
        quantidadeParcelas:
            (body['quantidadeParcelas'] as num?)?.toInt() ?? 1,
      );
      d.notificar('venda');
      final item = d.vendaRepository.obterPorId(criado.orcamentoId);
      return lanApiJson({
        'ok': true,
        'orcamentoId': criado.orcamentoId,
        'numeroOrcamento': criado.numeroOrcamento,
        'reutilizado': criado.reutilizado,
        'item': item == null ? null : SyncEntityCodec.vendaParaMap(item),
      });
    } catch (e) {
      return lanApiJson({'error': '$e'}, status: 400);
    }
  });
}
