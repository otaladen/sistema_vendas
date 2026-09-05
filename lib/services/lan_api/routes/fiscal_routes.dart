import 'dart:convert';

import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';

import '../../../config/focus_nfe_runtime.dart';
import '../../../data/nfe_entrada_repository.dart';
import '../../../data/sync/estoque_local_refresh_hub.dart';
import '../../../data/sync/sync_entity_codec.dart';
import '../../../data/sync/sync_entity_codec_extras.dart';
import '../../../data/sync/sync_refresh_hub.dart';
import '../../../data/venda_repository.dart';
import '../../../domain/conferencia_nfe_opcoes.dart';
import '../../../domain/fiscal/fiscal_pendencias_resumo.dart';
import '../../../model/auditoria_evento.dart';
import '../../../model/item_nota_temporario.dart';
import '../../../services/devolucao_fornecedor_fiscal_service.dart';
import '../../../services/focus_nfe_service.dart';
import '../../../services/nfce_reconciliacao_service.dart';
import '../../../services/xml_nfe_parser_service.dart';
import '../lan_api_deps.dart';
import '../lan_api_fechamento.dart';
import '../lan_api_json.dart';
import '../lan_api_nfce_emit.dart';
import '../lan_api_nfe_emit.dart';

void registerFiscalRoutes(Router router, LanApiDeps d) {
  Future<Response> listarNfeImportadasHandler(Request r) async {
    final q = (r.url.queryParameters['q'] ?? '').trim().toLowerCase();
    final tipoData =
        (r.url.queryParameters['tipoData'] ?? 'importacao').toLowerCase();
    final ordenacao =
        (r.url.queryParameters['ordenacao'] ?? 'importacaoDesc').trim();
    final periodoInicio = DateTime.tryParse(
      r.url.queryParameters['periodoInicio'] ?? '',
    )?.toUtc();
    final periodoFim = DateTime.tryParse(
      r.url.queryParameters['periodoFim'] ?? '',
    )?.toUtc();

    var items = d.nfeEntradaRepository.listarImportacoesNfeDesc();

    DateTime soData(DateTime dt) {
      final l = dt.toLocal();
      return DateTime(l.year, l.month, l.day);
    }

    if (periodoInicio != null || periodoFim != null) {
      final ini = periodoInicio == null ? null : soData(periodoInicio.toLocal());
      final fim = periodoFim == null ? null : soData(periodoFim.toLocal());
      items = items.where((reg) {
        final alvo = tipoData == 'emissao'
            ? reg.dataEmissao
            : reg.dataHoraImportacao;
        final d = soData(alvo);
        if (ini != null && d.isBefore(ini)) return false;
        if (fim != null && d.isAfter(fim)) return false;
        return true;
      }).toList();
    }

    if (q.isNotEmpty) {
      final soDig = q.replaceAll(RegExp(r'\D'), '');
      items = items.where((reg) {
        if (soDig.length >= 3) {
          if (reg.chaveAcesso.contains(soDig)) return true;
          final cnpj = reg.cnpjFornecedor.replaceAll(RegExp(r'\D'), '');
          if (cnpj.contains(soDig)) return true;
        }
        if (reg.nomeFornecedor.toLowerCase().contains(q)) return true;
        if (reg.cnpjFornecedor.toLowerCase().contains(q)) return true;
        if (reg.numeroNota > 0 && reg.numeroNota.toString().contains(q)) {
          return true;
        }
        if (reg.chaveAcesso.toLowerCase().contains(q)) return true;
        return false;
      }).toList();
    }

    int cmpStr(String a, String b) =>
        a.toLowerCase().trim().compareTo(b.toLowerCase().trim());
    switch (ordenacao) {
      case 'importacaoAsc':
        items.sort((a, b) => a.dataHoraImportacao.compareTo(b.dataHoraImportacao));
        break;
      case 'emissaoDesc':
        items.sort((a, b) => b.dataEmissao.compareTo(a.dataEmissao));
        break;
      case 'emissaoAsc':
        items.sort((a, b) => a.dataEmissao.compareTo(b.dataEmissao));
        break;
      case 'fornecedorAsc':
        items.sort(
          (a, b) => cmpStr(
            a.nomeFornecedor.isEmpty ? 'ZZZ' : a.nomeFornecedor,
            b.nomeFornecedor.isEmpty ? 'ZZZ' : b.nomeFornecedor,
          ),
        );
        break;
      case 'numeroNotaDesc':
        items.sort((a, b) => b.numeroNota.compareTo(a.numeroNota));
        break;
      case 'itensDesc':
        items.sort((a, b) => b.quantidadeItens.compareTo(a.quantidadeItens));
        break;
      case 'importacaoDesc':
      default:
        items.sort(
          (a, b) => b.dataHoraImportacao.compareTo(a.dataHoraImportacao),
        );
        break;
    }

    DateTime? ultima;
    final fornecedores = <String>{};
    for (final reg in items) {
      if (ultima == null || reg.dataHoraImportacao.isAfter(ultima)) {
        ultima = reg.dataHoraImportacao;
      }
      final c = reg.cnpjFornecedor.replaceAll(RegExp(r'\D'), '');
      if (c.isNotEmpty) {
        fornecedores.add(c);
      } else {
        final n = reg.nomeFornecedor.trim().toLowerCase();
        if (n.isNotEmpty) fornecedores.add('n:$n');
      }
    }

    return lanApiJson({
      'items': items.map(SyncEntityCodecExtras.nfeImportadaParaMap).toList(),
      'meta': {
        'totalNotas': items.length,
        'ultimaImportacao': ultima?.toUtc().toIso8601String(),
        'fornecedoresDistintos': fornecedores.length,
      },
    });
  }

  router.get('/api/nfe-entrada', listarNfeImportadasHandler);
  router.get('/api/nfe-importadas', listarNfeImportadasHandler);
  router.get('/api/nfe/historico', listarNfeImportadasHandler);
  router.get('/api/entradas', listarNfeImportadasHandler);

  Future<Response> detalheNfeImportadaHandler(Request _, String id) async {
    final registroId = int.tryParse(id) ?? 0;
    if (registroId <= 0) {
      return lanApiJson({'error': 'id invalido'}, status: 400);
    }
    final item = d.nfeEntradaRepository.obterImportacaoPorId(registroId);
    if (item == null) {
      return lanApiJson({'error': 'nao encontrado'}, status: 404);
    }
    final historico =
        d.nfeEntradaRepository.listarHistoricoPorChaveNfe(item.chaveAcesso);
    return lanApiJson({
      'ok': true,
      'item': SyncEntityCodecExtras.nfeImportadaParaMap(item),
      'itens': historico.map((h) {
        final p = h.produto.target;
        final nome = (p?.nome.trim().isNotEmpty == true)
            ? p!.nome
            : (p?.descricao.trim().isNotEmpty == true
                ? p!.descricao
                : 'Produto #${h.produto.targetId}');
        return {
          ...SyncEntityCodecExtras.historicoEntradaParaMap(h),
          'produtoNome': nome,
          'produtoCodigoInterno': p?.codigoInterno ?? '',
        };
      }).toList(),
      'temXml': d.nfeEntradaRepository.lerXmlImportacao(item.chaveAcesso) != null,
    });
  }

  router.get('/api/nfe-importadas/<id|[0-9]+>', detalheNfeImportadaHandler);
  router.get('/api/nfe/detalhes/<id|[0-9]+>', detalheNfeImportadaHandler);
  router.get('/api/nfe-entrada/<id|[0-9]+>', detalheNfeImportadaHandler);

  Future<Response> xmlNfeImportadaHandler(Request _, String id) async {
    final registroId = int.tryParse(id) ?? 0;
    if (registroId <= 0) {
      return lanApiJson({'error': 'id invalido'}, status: 400);
    }
    final item = d.nfeEntradaRepository.obterImportacaoPorId(registroId);
    if (item == null) {
      return lanApiJson({'error': 'nao encontrado'}, status: 404);
    }
    final xml = d.nfeEntradaRepository.lerXmlImportacao(item.chaveAcesso);
    if (xml == null || xml.trim().isEmpty) {
      return lanApiJson({'error': 'xml nao encontrado'}, status: 404);
    }
    final chave = item.chaveAcesso.replaceAll(RegExp(r'\D'), '');
    return Response.ok(
      xml,
      headers: {
        'content-type': 'application/xml; charset=utf-8',
        'content-disposition': 'attachment; filename="nfe_$chave.xml"',
        'cache-control': 'private, no-store',
      },
    );
  }

  router.get('/api/nfe-importadas/<id|[0-9]+>/xml', xmlNfeImportadaHandler);
  router.get('/api/nfe-entrada/<id|[0-9]+>/xml', xmlNfeImportadaHandler);
  router.get('/api/nfe/<id|[0-9]+>/xml', xmlNfeImportadaHandler);

  Map<String, dynamic> validacaoEstornoParaMap(
    ValidacaoEstornoNfe v, {
    int qtdContasPagar = 0,
  }) =>
      {
        'podeEstornar': v.podeEstornar,
        'motivoBloqueio': v.motivoBloqueio,
        'qtdContasPagar': qtdContasPagar,
        'linhas': v.linhas
            .map(
              (l) => {
                'nomeProduto': l.nomeProduto,
                'quantidadeEstorno': l.quantidadeEstorno,
                'estoqueAtual': l.estoqueAtual,
                'rotuloEstorno': l.rotuloEstorno,
                'rotuloEstoqueAtual': l.rotuloEstoqueAtual,
              },
            )
            .toList(),
      };

  Future<Response> validarEstornoNfeImportadaHandler(
    Request _,
    String id,
  ) async {
    final registroId = int.tryParse(id) ?? 0;
    if (registroId <= 0) {
      return lanApiJson({'error': 'id invalido'}, status: 400);
    }
    final item = d.nfeEntradaRepository.obterImportacaoPorId(registroId);
    if (item == null) {
      return lanApiJson({'error': 'nao encontrado'}, status: 404);
    }
    final validacao =
        d.nfeEntradaRepository.validarEstornoImportacao(registroId);
    final qtdContas = d.nfeEntradaRepository
        .listarContasPagarPorChaveNfe(item.chaveAcesso)
        .length;
    return lanApiJson({
      'ok': true,
      'item': SyncEntityCodecExtras.nfeImportadaParaMap(item),
      ...validacaoEstornoParaMap(validacao, qtdContasPagar: qtdContas),
    });
  }

  Future<Response> estornarNfeImportadaHandler(Request _, String id) async {
    final registroId = int.tryParse(id) ?? 0;
    if (registroId <= 0) {
      return lanApiJson({'error': 'id invalido'}, status: 400);
    }
    final item = d.nfeEntradaRepository.obterImportacaoPorId(registroId);
    if (item == null) {
      return lanApiJson({'error': 'nao encontrado'}, status: 404);
    }
    final validacao =
        d.nfeEntradaRepository.validarEstornoImportacao(registroId);
    final qtdContas = d.nfeEntradaRepository
        .listarContasPagarPorChaveNfe(item.chaveAcesso)
        .length;
    if (!validacao.podeEstornar) {
      return lanApiJson({
        'ok': false,
        'error': validacao.motivoBloqueio ?? 'Estorno bloqueado.',
        'mensagem': validacao.motivoBloqueio ?? 'Estorno bloqueado.',
        ...validacaoEstornoParaMap(validacao, qtdContasPagar: qtdContas),
      }, status: 409);
    }
    try {
      final produtoIds =
          d.nfeEntradaRepository.estornarImportacaoNfe(registroId);
      d.notificar('nfe_importada', ids: [registroId]);
      d.notificar('produto', ids: produtoIds);
      d.notificar('estoque', ids: produtoIds);
      d.notificar('conta_pagar');
      d.notificar('financeiro');
      return lanApiJson({
        'ok': true,
        'id': registroId,
        'mensagem':
            'Importacao estornada. Estoque e custo medio revertidos'
            '${qtdContas > 0 ? '; $qtdContas titulo(s) a pagar removido(s)' : ''}'
            '. A nota pode ser importada de novo.',
        'produtoIds': produtoIds,
        'qtdContasPagarRemovidas': qtdContas,
      });
    } catch (e) {
      return lanApiJson({
        'ok': false,
        'error': '$e',
        'mensagem': '$e',
      }, status: 400);
    }
  }

  router.get(
    '/api/nfe-importadas/<id|[0-9]+>/validar-estorno',
    validarEstornoNfeImportadaHandler,
  );
  router.get(
    '/api/nfe-entrada/<id|[0-9]+>/validar-estorno',
    validarEstornoNfeImportadaHandler,
  );
  router.post(
    '/api/nfe-importadas/<id|[0-9]+>/estornar',
    estornarNfeImportadaHandler,
  );
  router.post(
    '/api/nfe-entrada/<id|[0-9]+>/estornar',
    estornarNfeImportadaHandler,
  );
  router.post(
    '/api/entradas/<id|[0-9]+>/estornar',
    estornarNfeImportadaHandler,
  );

  Future<Response> linhasDevolucaoFornecedorHandler(
    Request _,
    String id,
  ) async {
    final registroId = int.tryParse(id) ?? 0;
    if (registroId <= 0) {
      return lanApiJson({'error': 'id invalido'}, status: 400);
    }
    final item = d.nfeEntradaRepository.obterImportacaoPorId(registroId);
    if (item == null) {
      return lanApiJson({'error': 'nao encontrado'}, status: 404);
    }
    final svc = DevolucaoFornecedorFiscalService(
      produtoRepository: d.produtoRepository,
    );
    final linhas = svc.carregarLinhas(item.chaveAcesso);
    return lanApiJson({
      'ok': true,
      'item': SyncEntityCodecExtras.nfeImportadaParaMap(item),
      'temXml': d.nfeEntradaRepository.lerXmlImportacao(item.chaveAcesso) != null,
      'linhas': linhas.map(DevolucaoFornecedorFiscalService.linhaParaMap).toList(),
      'historico': svc
          .listarHistoricoPorChave(item.chaveAcesso)
          .map((e) => e.toJson())
          .toList(),
    });
  }

  router.get(
    '/api/nfe-importadas/<id|[0-9]+>/devolucao-linhas',
    linhasDevolucaoFornecedorHandler,
  );
  router.get(
    '/api/nfe-entrada/<id|[0-9]+>/devolucao-linhas',
    linhasDevolucaoFornecedorHandler,
  );

  Future<Response> emitirDevolucaoFornecedorHandler(
    Request r,
    String id,
  ) async {
    final registroId = int.tryParse(id) ?? 0;
    if (registroId <= 0) {
      return lanApiJson({'error': 'id invalido'}, status: 400);
    }
    final item = d.nfeEntradaRepository.obterImportacaoPorId(registroId);
    if (item == null) {
      return lanApiJson({'error': 'nao encontrado'}, status: 404);
    }
    final body = await lanApiReadJsonMap(r) ?? <String, dynamic>{};
    final motivo = (body['motivo'] ?? 'Devolucao de mercadoria ao fornecedor')
        .toString();
    final itensRaw = body['itens'];
    final itens = <Map<String, dynamic>>[];
    if (itensRaw is List) {
      for (final e in itensRaw) {
        if (e is Map) itens.add(Map<String, dynamic>.from(e));
      }
    }
    if (itens.isEmpty) {
      return lanApiJson(
        {'error': 'Informe ao menos um item com quantidade > 0.'},
        status: 400,
      );
    }
    final svc = DevolucaoFornecedorFiscalService(
      produtoRepository: d.produtoRepository,
    );
    final res = await svc.emitirDePayload(
      chaveNotaCompra: item.chaveAcesso,
      motivo: motivo,
      itens: itens,
    );
    if (!res.sucesso) {
      return lanApiJson({'ok': false, 'error': res.mensagem}, status: 400);
    }
    final produtoIds = res.produtoIdsBaixados;
    if (produtoIds.isNotEmpty) {
      d.notificar('produto', ids: produtoIds);
      EstoqueLocalRefreshHub.instance.notificar(ids: produtoIds);
    }
    d.notificar('nfe_importada');
    d.notificar('historico_entrada');
    SyncRefreshHub.instance.notificarDadosAtualizados();
    return lanApiJson({
      'ok': true,
      'autorizada': res.autorizada,
      'mensagem': res.mensagem,
      'chaveNfe': res.chaveNfe,
      'urlDanfe': res.urlDanfe,
      'urlXml': res.urlXml,
      'referencia': res.referencia,
      'numero': res.numero,
      'serie': res.serie,
      'produtoIds': produtoIds,
    });
  }

  router.post(
    '/api/nfe-importadas/<id|[0-9]+>/emitir-devolucao-fornecedor',
    emitirDevolucaoFornecedorHandler,
  );
  router.post(
    '/api/nfe-entrada/<id|[0-9]+>/emitir-devolucao-fornecedor',
    emitirDevolucaoFornecedorHandler,
  );

  Future<Response> responderReconsultaDevolucao(
    DevolucaoFornecedorReconsultaResultado res,
  ) async {
    if (!res.sucesso) {
      return lanApiJson({'ok': false, 'error': res.mensagem}, status: 400);
    }
    if (res.produtoIds.isNotEmpty) {
      d.notificar('produto', ids: res.produtoIds);
      EstoqueLocalRefreshHub.instance.notificar(ids: res.produtoIds);
    }
    d.notificar('nfe_importada');
    d.notificar('historico_entrada');
    SyncRefreshHub.instance.notificarDadosAtualizados();
    return lanApiJson({
      'ok': true,
      'autorizada': res.autorizada,
      'rejeitada': res.rejeitada,
      'estoqueBaixadoAgora': res.estoqueBaixadoAgora,
      'mensagem': res.mensagem,
      'status': res.registro?.rotuloStatus ?? '',
      'statusFocus': res.registro?.statusFocus ?? '',
      'produtoIds': res.produtoIds,
      'registro': res.registro?.toJson(),
    });
  }

  router.post('/api/nfe-importadas/reconsultar-devolucao-fornecedor', (
    Request r,
  ) async {
    final body = await lanApiReadJsonMap(r) ?? <String, dynamic>{};
    final referencia = (body['referencia'] ?? '').toString().trim();
    if (referencia.isEmpty) {
      return lanApiJson({'error': 'referencia obrigatoria'}, status: 400);
    }
    final svc = DevolucaoFornecedorFiscalService(
      produtoRepository: d.produtoRepository,
    );
    final res = await svc.reconsultar(referencia);
    return responderReconsultaDevolucao(res);
  });

  router.post(
    '/api/nfe-importadas/reconsultar-devolucao-fornecedor-processando',
    (Request _) async {
      final svc = DevolucaoFornecedorFiscalService(
        produtoRepository: d.produtoRepository,
      );
      final lote = await svc.reconsultarPendentes();
      if (lote.produtoIds.isNotEmpty) {
        d.notificar('produto', ids: lote.produtoIds);
        EstoqueLocalRefreshHub.instance.notificar(ids: lote.produtoIds);
      }
      d.notificar('nfe_importada');
      d.notificar('historico_entrada');
      SyncRefreshHub.instance.notificarDadosAtualizados();
      return lanApiJson({
        'ok': true,
        'total': lote.total,
        'autorizadas': lote.autorizadas,
        'rejeitadas': lote.rejeitadas,
        'estoqueBaixado': lote.estoqueBaixado,
        'produtoIds': lote.produtoIds,
      });
    },
  );

  router.get('/api/nfe-saida', (Request r) {
    final limit = lanApiQueryInt(r, 'limit', fallback: 300);
    return lanApiJson(lanApiListarNfeSaida(d, limit: limit.clamp(1, 1000)));
  });

  router.post('/api/nfe-saida/reconsultar', (Request r) async {
    final body = await lanApiReadJsonMap(r) ?? <String, dynamic>{};
    final result = await lanApiReconsultarNfeSaida(
      d,
      referencia: (body['referencia'] ?? '').toString(),
    );
    final status =
        (result['status'] as int?) ?? (result['ok'] == true ? 200 : 400);
    return lanApiJson(result, status: status);
  });

  router.post('/api/nfe-saida/reconsultar-processando', (Request _) async {
    final result = await lanApiReconsultarNfeSaidaProcessando(d);
    return lanApiJson(result);
  });

  router.post('/api/nfe-saida/cancelar', (Request r) async {
    final body = await lanApiReadJsonMap(r) ?? <String, dynamic>{};
    final result = await lanApiCancelarNfeSaida(
      d,
      referencia: (body['referencia'] ?? '').toString(),
      justificativa: (body['justificativa'] ?? '').toString(),
    );
    final status =
        (result['status'] as int?) ?? (result['ok'] == true ? 200 : 400);
    return lanApiJson(result, status: status);
  });

  /// Alias: cancelamento fiscal de venda (NFC-e/NF-e + ERP).
  router.post('/api/fiscal/cancelar-venda', (Request r) async {
    final body = await lanApiReadJsonMap(r) ?? <String, dynamic>{};
    final vendaId = (body['vendaId'] as num?)?.toInt() ??
        int.tryParse((body['id'] ?? '').toString()) ??
        0;
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

  router.post('/api/nfe-saida/carta-correcao', (Request r) async {
    final body = await lanApiReadJsonMap(r) ?? <String, dynamic>{};
    final result = await lanApiCartaCorrecaoNfeSaida(
      d,
      referencia: (body['referencia'] ?? '').toString(),
      correcao: (body['correcao'] ?? body['texto'] ?? '').toString(),
    );
    final status =
        (result['status'] as int?) ?? (result['ok'] == true ? 200 : 400);
    return lanApiJson(result, status: status);
  });

  router.get('/api/fiscal/pendencias', (_) {
    final emissao = d.vendaRepository.listarComNfcePendenteEmissao();
    final sefaz = d.vendaRepository.listarComNfcePendenteFocus();
    final resumo = FiscalPendenciasResumoService.contar(
      vendaRepository: d.vendaRepository,
    );
    return lanApiJson({
      // Legado: terminals antigos leem so `items`.
      'items': emissao.map(SyncEntityCodec.vendaParaMap).toList(),
      'pendentesEmissao': emissao.map(SyncEntityCodec.vendaParaMap).toList(),
      'pendentesSefaz': sefaz.map(SyncEntityCodec.vendaParaMap).toList(),
      'meta': {
        'nfcePendenteEmissao': resumo.nfcePendenteEmissao,
        'nfceAguardandoSefaz': resumo.nfceAguardandoSefaz,
        'nfeProcessando': resumo.nfeProcessando,
        'nfeRejeitadas': resumo.nfeRejeitadas,
        'total': resumo.total,
      },
    });
  });

  NfceReconciliacaoService nfceRecon() => NfceReconciliacaoService(
        vendaRepository: d.vendaRepository,
        focusNfe: FocusNfeService(config: criarFocusNfeConfigPadrao()),
      );

  router.post('/api/vendas/<id|[0-9]+>/reconsultar-nfce', (
    Request _,
    String id,
  ) async {
    final vendaId = int.tryParse(id) ?? 0;
    if (vendaId <= 0) {
      return lanApiJson({'error': 'id invalido'}, status: 400);
    }
    final venda = d.vendaRepository.obterPorId(vendaId);
    if (venda == null) {
      return lanApiJson({'error': 'venda nao encontrada'}, status: 404);
    }
    try {
      final r = await nfceRecon().reconsultarVenda(venda);
      d.notificar('venda');
      d.notificar('produto');
      d.notificar('fiscal', ids: [vendaId]);
      SyncRefreshHub.instance.notificarDadosAtualizados();
      return lanApiJson({
        'ok': r.tipo != NfceReconciliacaoTipo.erro,
        'tipo': r.tipo.name,
        'mensagem': r.mensagem,
        'vendaId': r.vendaId,
        'cupomInternoRegistrado': r.cupomInternoRegistrado,
      });
    } catch (e) {
      return lanApiJson({'ok': false, 'error': '$e'}, status: 400);
    }
  });

  router.post('/api/fiscal/nfce/reconsultar-todas', (Request _) async {
    try {
      final lote = await nfceRecon().reconsultarTodasPendentes();
      d.notificar('venda');
      d.notificar('produto');
      SyncRefreshHub.instance.notificarDadosAtualizados();
      return lanApiJson({
        'ok': true,
        'total': lote.total,
        'autorizadas': lote.autorizadas,
        'aindaProcessando': lote.aindaProcessando,
        'atualizadas': lote.atualizadas,
      });
    } catch (e) {
      return lanApiJson({'ok': false, 'error': '$e'}, status: 400);
    }
  });

  router.get('/api/fiscal/fechamento', (Request r) {
    final mes = lanApiQueryInt(r, 'mes', fallback: DateTime.now().month);
    final ano = lanApiQueryInt(r, 'ano', fallback: DateTime.now().year);
    if (mes < 1 || mes > 12) {
      return lanApiJson({'error': 'mes invalido (1-12)'}, status: 400);
    }
    return lanApiJson(lanApiPacoteFechamento(d: d, mes: mes, ano: ano));
  });

  router.get('/api/fiscal/relatorio-mensal', (Request r) {
    final mes = lanApiQueryInt(r, 'mes', fallback: DateTime.now().month);
    final ano = lanApiQueryInt(r, 'ano', fallback: DateTime.now().year);
    if (mes < 1 || mes > 12) {
      return lanApiJson({'error': 'mes invalido (1-12)'}, status: 400);
    }
    return lanApiJson(lanApiRelatorioFiscalMensal(d: d, mes: mes, ano: ano));
  });

  router.get('/api/fiscal/fechamento/zip', (Request r) async {
    final mes = lanApiQueryInt(r, 'mes', fallback: DateTime.now().month);
    final ano = lanApiQueryInt(r, 'ano', fallback: DateTime.now().year);
    if (mes < 1 || mes > 12) {
      return lanApiJson({'error': 'mes invalido (1-12)'}, status: 400);
    }
    final forcar = r.url.queryParameters['forcar'] == '1' ||
        r.url.queryParameters['forcar'] == 'true';
    final result = await lanApiGerarFechamentoArquivos(
      d: d,
      mes: mes,
      ano: ano,
      forcar: forcar,
    );
    if (result['ok'] != true) {
      final status = (result['status'] as int?) ?? 400;
      return lanApiJson(
        {'ok': false, 'error': result['error'] ?? 'Falha ao gerar ZIP'},
        status: status,
      );
    }
    final bytes = result['zipBytes'];
    final nome = (result['nomeBaseArquivo'] ?? 'fechamento').toString();
    if (bytes is! List<int>) {
      return lanApiJson({'error': 'ZIP vazio'}, status: 500);
    }
    return Response.ok(
      bytes,
      headers: {
        'content-type': 'application/zip',
        'content-disposition': 'attachment; filename="$nome.zip"',
        'x-fechamento-mes': '$mes',
        'x-fechamento-ano': '$ano',
        'x-fechamento-nome': nome,
      },
    );
  });

  router.get('/api/fiscal/fechamento/excel', (Request r) async {
    final mes = lanApiQueryInt(r, 'mes', fallback: DateTime.now().month);
    final ano = lanApiQueryInt(r, 'ano', fallback: DateTime.now().year);
    if (mes < 1 || mes > 12) {
      return lanApiJson({'error': 'mes invalido (1-12)'}, status: 400);
    }
    final forcar = r.url.queryParameters['forcar'] == '1' ||
        r.url.queryParameters['forcar'] == 'true';
    final result = await lanApiGerarFechamentoArquivos(
      d: d,
      mes: mes,
      ano: ano,
      forcar: forcar,
    );
    if (result['ok'] != true) {
      final status = (result['status'] as int?) ?? 400;
      return lanApiJson(
        {'ok': false, 'error': result['error'] ?? 'Falha ao gerar Excel'},
        status: status,
      );
    }
    final bytes = result['excelBytes'];
    final nome = (result['nomeBaseArquivo'] ?? 'fechamento').toString();
    if (bytes is! List<int>) {
      return lanApiJson({'error': 'Excel vazio'}, status: 500);
    }
    return Response.ok(
      bytes,
      headers: {
        'content-type':
            'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
        'content-disposition': 'attachment; filename="$nome.xlsx"',
        'x-fechamento-mes': '$mes',
        'x-fechamento-ano': '$ano',
        'x-fechamento-nome': nome,
      },
    );
  });

  router.post('/api/fiscal/fechamento/enviar-email', (Request r) async {
    final mes = lanApiQueryInt(r, 'mes', fallback: DateTime.now().month);
    final ano = lanApiQueryInt(r, 'ano', fallback: DateTime.now().year);
    if (mes < 1 || mes > 12) {
      return lanApiJson({'error': 'mes invalido (1-12)'}, status: 400);
    }
    final forcar = r.url.queryParameters['forcar'] == '1' ||
        r.url.queryParameters['forcar'] == 'true';
    final result = await lanApiEnviarFechamentoContador(
      d: d,
      mes: mes,
      ano: ano,
      forcar: forcar,
    );
    if (result['ok'] != true) {
      final status = (result['status'] as int?) ?? 400;
      return lanApiJson(
        {'ok': false, 'error': result['error'] ?? 'Falha ao enviar e-mail'},
        status: status,
      );
    }
    return lanApiJson(result);
  });

  router.post('/api/vendas/<id|[0-9]+>/emitir-nfce', (Request r, String id) async {
    final body = await lanApiReadJsonMap(r) ?? <String, dynamic>{};
    final result = await lanApiEmitirNfce(
      d: d,
      vendaId: int.parse(id),
      permitirVendaSemEstoque: body['permitirVendaSemEstoque'] != false,
    );
    final status = (result['status'] as int?) ?? (result['ok'] == true ? 200 : 400);
    return lanApiJson(result, status: status);
  });

  router.post('/api/vendas/<id|[0-9]+>/emitir-nfe', (Request r, String id) async {
    final body = await lanApiReadJsonMap(r) ?? <String, dynamic>{};
    final destRaw = body['destinatario'];
    final logRaw = body['logistica'];
    final result = await lanApiEmitirNfe(
      d: d,
      vendaId: int.parse(id),
      destinatarioJson: destRaw is Map
          ? Map<String, dynamic>.from(destRaw)
          : null,
      logisticaJson:
          logRaw is Map ? Map<String, dynamic>.from(logRaw) : null,
      permitirVendaSemEstoque: body['permitirVendaSemEstoque'] != false,
    );
    final status =
        (result['status'] as int?) ?? (result['ok'] == true ? 200 : 400);
    return lanApiJson(result, status: status);
  });

  /// Entrada unificada (Terminal / auditoria): `{ vendaId, tipo: nfce|nfe, ... }`.
  router.post('/api/fiscal/emitir', (Request r) async {
    final body = await lanApiReadJsonMap(r) ?? <String, dynamic>{};
    final vendaId = (body['vendaId'] as num?)?.toInt() ?? 0;
    if (vendaId <= 0) {
      return lanApiJson(
        {'ok': false, 'error': 'vendaId obrigatorio'},
        status: 400,
      );
    }
    final tipo = (body['tipo'] ?? body['documento'] ?? 'nfce')
        .toString()
        .trim()
        .toLowerCase();
    final Map<String, dynamic> result;
    if (tipo == 'nfe' || tipo == 'nfe55' || tipo == '55') {
      final destRaw = body['destinatario'];
      final logRaw = body['logistica'];
      result = await lanApiEmitirNfe(
        d: d,
        vendaId: vendaId,
        destinatarioJson: destRaw is Map
            ? Map<String, dynamic>.from(destRaw)
            : null,
        logisticaJson:
            logRaw is Map ? Map<String, dynamic>.from(logRaw) : null,
        permitirVendaSemEstoque: body['permitirVendaSemEstoque'] != false,
      );
    } else if (tipo == 'nfce' || tipo == '65') {
      result = await lanApiEmitirNfce(
        d: d,
        vendaId: vendaId,
        permitirVendaSemEstoque: body['permitirVendaSemEstoque'] != false,
      );
    } else {
      return lanApiJson(
        {
          'ok': false,
          'error': 'tipo invalido (use nfce ou nfe)',
        },
        status: 400,
      );
    }
    // Rejeicao SEFAZ / validacao: 422 quando houver mensagem fiscal tipica.
    var status =
        (result['status'] as int?) ?? (result['ok'] == true ? 200 : 400);
    if (result['ok'] != true && status == 400) {
      final err = (result['error'] ?? result['mensagem'] ?? '')
          .toString()
          .toLowerCase();
      if (err.contains('rejeic') ||
          err.contains('sefaz') ||
          err.contains('ncm') ||
          err.contains('csosn') ||
          err.contains('cst')) {
        status = 422;
        result['status'] = 422;
      }
    }
    return lanApiJson(result, status: status);
  });

  router.get('/api/relatorios/vendas-dia', (Request r) {
    final dia = lanApiQueryDate(r, 'dia') ?? DateTime.now().toUtc();
    final inicio = DateTime.utc(dia.year, dia.month, dia.day);
    final fim = inicio.add(const Duration(days: 1));
    final vendas = d.vendaRepository
        .listarListagemVendasCompleto(
          FiltroListagemVendas(
            textoBusca: '',
            dataInicioUtc: inicio,
            dataFimUtc: fim,
            filtroCancelamento: 'ativas',
            canceladaPorFiltro: 'todos',
            formaPagamento: 'todos',
            tipoEntrega: 'todos',
            entregaPendente: 'todos',
          ),
        )
        .toList();
    var total = 0.0;
    var qtd = 0;
    for (final v in vendas) {
      if (v.cancelada) continue;
      qtd++;
      total += v.total;
    }
    return lanApiJson({
      'dia': inicio.toIso8601String(),
      'quantidade': qtd,
      'total': total,
      'items': vendas
          .where((v) => !v.cancelada)
          .map(SyncEntityCodec.vendaParaMap)
          .toList(),
    });
  });

  router.post('/api/nfe-entrada/verificar-chave', (Request r) async {
    final body = await lanApiReadJsonMap(r);
    final chave = (body?['chaveAcesso'] ?? '').toString();
    final ja = d.nfeEntradaRepository.chaveNfeJaImportada(chave);
    return lanApiJson({'ok': true, 'jaImportada': ja});
  });

  Future<Response> lerXmlNfeHandler(Request r) async {
    final body = await lanApiReadJsonMap(r);
    final xml = (body?['xml'] ?? '').toString();
    if (xml.trim().isEmpty) {
      return lanApiJson({'error': 'xml obrigatorio'}, status: 400);
    }
    try {
      final nfe = XmlParserService.parseNfeXmlString(xml);
      final ja = d.nfeEntradaRepository.chaveNfeJaImportada(nfe.chaveAcesso);
      final sugestoes =
          d.nfeEntradaRepository.prepararSugestoesConferencia(nfe);
      return lanApiJson({
        'ok': true,
        'jaImportada': ja,
        'chaveAcesso': nfe.chaveAcesso,
        'numero': nfe.numeroNota,
        'dataEmissao': nfe.dataEmissao.toUtc().toIso8601String(),
        'emitenteCnpj': nfe.emitente.cnpj,
        'emitenteRazao': nfe.emitente.razaoSocial,
        'nfe': _nfeParseParaMap(nfe),
        'sugestoes': sugestoes.map(_sugestaoConferenciaParaMap).toList(),
      });
    } catch (e) {
      return lanApiJson({'error': '$e'}, status: 400);
    }
  }

  Future<Response> processarEntradaNfeHandler(Request r) async {
    final body = await lanApiReadJsonMap(r);
    final xml = (body?['xml'] ?? '').toString();
    final linhasRaw = body?['linhas'];
    if (xml.trim().isEmpty || linhasRaw is! List) {
      return lanApiJson({'error': 'xml e linhas obrigatorios'}, status: 400);
    }
    try {
      final nfe = XmlParserService.parseNfeXmlString(xml);
      final opcoesRaw = body?['opcoes'];
      final opcoes = opcoesRaw is Map
          ? ConferenciaNfeOpcoes(
              lancarEstoque: opcoesRaw['lancarEstoque'] != false,
              gerarContasPagar: opcoesRaw['gerarContasPagar'] != false,
              atualizarPrecoCusto: opcoesRaw['atualizarPrecoCusto'] == true,
              atualizarPrecosVenda: opcoesRaw['atualizarPrecosVenda'] == true,
            )
          : const ConferenciaNfeOpcoes();
      final porNumero = {for (final i in nfe.itens) i.numeroItem: i};
      final linhas = <ConferenciaNfeLinhaConfirmacao>[];
      for (final raw in linhasRaw.whereType<Map>()) {
        final m = Map<String, dynamic>.from(raw);
        final numItem = (m['numeroItem'] as num?)?.toInt() ?? 0;
        final item = porNumero[numItem];
        if (item == null) {
          return lanApiJson(
            {'error': 'item $numItem nao encontrado no XML'},
            status: 400,
          );
        }
        final pid = (m['produtoExistenteId'] as num?)?.toInt();
        final loteOverride = (m['numeroLote'] ?? '').toString().trim();
        final valOverride = DateTime.tryParse(
          (m['dataValidade'] ?? '').toString(),
        )?.toUtc();
        linhas.add(
          ConferenciaNfeLinhaConfirmacao(
            item: item,
            fatorConversao: (m['fatorConversao'] as num?)?.toDouble() ?? 1,
            unidadeInterna: (m['unidadeInterna'] ?? 'UN').toString(),
            embalagemMultiplica: m['embalagemMultiplica'] != false,
            confirmarConversaoEmbalagem:
                m['confirmarConversaoEmbalagem'] == true,
            produtoExistenteId: pid,
            numeroLote: loteOverride.isNotEmpty ? loteOverride : item.numeroLote,
            dataValidade: valOverride ?? item.dataValidade,
          ),
        );
      }
      final produtoIds = d.nfeEntradaRepository.confirmarEntrada(
        nfe: nfe,
        linhas: linhas,
        opcoes: opcoes,
        margemMinimaVendaPercentual:
            (body?['margemMinimaVendaPercentual'] as num?)?.toDouble() ?? 20,
        xmlOriginal: xml,
      );
      // Reidrata estoque/custos nos terminais (inclui produtos novos).
      d.notificar(
        'produto',
        ids: produtoIds.isEmpty ? null : produtoIds,
      );
      d.notificar('nfe_importada');
      if (opcoes.gerarContasPagar) {
        d.notificar('conta_pagar');
      }
      return lanApiJson({
        'ok': true,
        'chaveAcesso': nfe.chaveAcesso,
        'produtoIds': produtoIds,
      });
    } catch (e) {
      return lanApiJson({'error': '$e'}, status: 400);
    }
  }

  // Aliases solicitados + rotas legadas.
  router.post('/api/nfe/ler-xml', lerXmlNfeHandler);
  router.post('/api/entradas/xml/parse', lerXmlNfeHandler);
  router.post('/api/nfe-entrada/preparar', lerXmlNfeHandler);

  router.post('/api/nfe/processar-entrada', processarEntradaNfeHandler);
  router.post('/api/entradas/salvar', processarEntradaNfeHandler);
  router.post('/api/nfe-entrada/confirmar', processarEntradaNfeHandler);

  router.post('/api/nfe-entrada/<id|[0-9]+>/solicitar-devolucao', (
    Request r,
    String id,
  ) async {
    final body = await lanApiReadJsonMap(r) ?? <String, dynamic>{};
    final registro = d.nfeEntradaRepository.obterImportacaoPorId(int.parse(id));
    if (registro == null) {
      return lanApiJson({'error': 'importacao nao encontrada'}, status: 404);
    }
    // Registra solicitacao na auditoria para o PC servidor processar/emitir.
    try {
      final box = d.objectBox.auditoriaEventoBox;
      box.put(
        AuditoriaEvento(
          modulo: 'fiscal',
          acao: 'solicitar_devolucao_fornecedor',
          usuarioLogin: (body['usuarioLogin'] ?? '').toString(),
          entidade: 'nfe_importada',
          entidadeId: id,
          resumo:
              'Solicitacao de devolucao NF-e ${registro.chaveAcesso} '
              'pelo terminal ${(body['terminalId'] ?? '').toString()}',
          detalhesJson: jsonEncode(body),
        ),
      );
      d.notificar('auditoria');
      return lanApiJson({
        'ok': true,
        'mensagem':
            'Solicitacao registrada no servidor. Conclua a emissao fiscal no PC1 se necessario.',
        'chaveAcesso': registro.chaveAcesso,
      });
    } catch (e) {
      return lanApiJson({'error': '$e'}, status: 400);
    }
  });
}

Map<String, dynamic> _nfeParseParaMap(NfeXmlParseResult nfe) => {
      'chaveAcesso': nfe.chaveAcesso,
      'numeroNota': nfe.numeroNota,
      'dataEmissao': nfe.dataEmissao.toUtc().toIso8601String(),
      'valorTotalNota': nfe.valorTotalNota,
      'emitente': {
        'cnpj': nfe.emitente.cnpj,
        'razaoSocial': nfe.emitente.razaoSocial,
        'nomeFantasia': nfe.emitente.nomeFantasia,
        'inscricaoEstadual': nfe.emitente.inscricaoEstadual,
        'logradouro': nfe.emitente.logradouro,
        'numero': nfe.emitente.numero,
        'complemento': nfe.emitente.complemento,
        'bairro': nfe.emitente.bairro,
        'municipio': nfe.emitente.municipio,
        'codigoMunicipioIbge': nfe.emitente.codigoMunicipioIbge,
        'uf': nfe.emitente.uf,
        'cep': nfe.emitente.cep,
        'telefone': nfe.emitente.telefone,
        'email': nfe.emitente.email,
      },
      'itens': nfe.itens.map(_itemNotaParaMap).toList(),
      'duplicatas': nfe.duplicatas
          .map(
            (d) => {
              'numeroParcela': d.numeroParcela,
              'dataVencimento': d.dataVencimento.toUtc().toIso8601String(),
              'valorParcela': d.valorParcela,
            },
          )
          .toList(),
    };

Map<String, dynamic> _itemNotaParaMap(ItemNotaTemporario i) => {
      'numeroItem': i.numeroItem,
      'codigo': i.codigo,
      'descricao': i.descricao,
      'unidadeComercial': i.unidadeComercial,
      'quantidadeComercial': i.quantidadeComercial,
      'valorUnitarioComercial': i.valorUnitarioComercial,
      'unidadeTributavel': i.unidadeTributavel,
      'quantidadeTributavel': i.quantidadeTributavel,
      'valorUnitarioTributavel': i.valorUnitarioTributavel,
      'codigoBarras': i.codigoBarras,
      'ncm': i.ncm,
      'cfop': i.cfop,
      'icmsOrigem': i.icmsOrigem,
      'icmsSituacaoTributaria': i.icmsSituacaoTributaria,
      'icmsBaseCalculo': i.icmsBaseCalculo,
      'icmsAliquota': i.icmsAliquota,
      'icmsValor': i.icmsValor,
      'icmsBaseCalculoSt': i.icmsBaseCalculoSt,
      'icmsAliquotaSt': i.icmsAliquotaSt,
      'icmsValorSt': i.icmsValorSt,
      'ipiValor': i.ipiValor,
      'numeroLote': i.numeroLote,
      if (i.dataValidade != null)
        'dataValidade': i.dataValidade!.toUtc().toIso8601String(),
    };

Map<String, dynamic> _sugestaoConferenciaParaMap(SugestaoLinhaConferencia s) => {
      'produtoNovo': s.produtoNovo,
      'produtoExistenteId': s.produtoExistenteId,
      'fatorInicial': s.fatorInicial,
      'unidadeInternaInicial': s.unidadeInternaInicial,
      'embalagemMultiplicaInicial': s.embalagemMultiplicaInicial,
      'tipoMatch': s.tipoMatch.name,
      'item': _itemNotaParaMap(s.item),
    };
