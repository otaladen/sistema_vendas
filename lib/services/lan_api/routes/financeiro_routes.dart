import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';

import '../../../data/models/conta_pagar.dart';
import '../../../data/sync/sync_entity_codec_extras.dart';
import '../../../data/sync/sync_entity_codec_operacional.dart';
import '../../../domain/financeiro_resumo.dart';
import '../../../domain/recebimento_fiado_codec.dart';
import '../../../domain/tesouraria_semanal.dart';
import '../lan_api_deps.dart';
import '../lan_api_json.dart';

void registerFinanceiroRoutes(Router router, LanApiDeps d) {
  Future<Response> removerContaPagarHandler(String id) async {
    final contaId = int.tryParse(id) ?? 0;
    if (contaId <= 0) {
      return lanApiJson({'error': 'id invalido'}, status: 400);
    }
    final conta = d.objectBox.contaPagarBox.get(contaId);
    if (conta == null) {
      return lanApiJson({'error': 'conta a pagar nao encontrada'}, status: 404);
    }
    if (conta.status == ContaPagarStatus.pago) {
      return lanApiJson({
        'error':
            'Nao e possivel remover: titulo ja esta quitado/pago. '
            'Estorne o pagamento antes de excluir.',
      }, status: 409);
    }
    try {
      final ok = d.contaPagarRepository.remover(contaId);
      if (!ok) {
        return lanApiJson({
          'error': 'conta a pagar nao encontrada',
        }, status: 404);
      }
      d.notificar('conta_pagar', ids: [contaId]);
      d.notificar('financeiro');
      return lanApiJson({'ok': true, 'id': contaId});
    } catch (e) {
      return lanApiJson({'error': '$e'}, status: 400);
    }
  }

  Map<String, dynamic> payloadRecebimento(int recebimentoId) {
    final rec = d.vendaRepository.recebimentos.obterPorId(recebimentoId);
    if (rec == null) {
      return {'ok': true, 'id': recebimentoId};
    }
    final alocacoes = RecebimentoFiadoCodec.decode(rec.alocacoesJson);
    final titulosAlocados = <Map<String, dynamic>>[];
    for (final a in alocacoes) {
      final t = d.vendaRepository.titulos.obterPorId(a.tituloId);
      if (t == null) continue;
      titulosAlocados.add({
        ...SyncEntityCodecExtras.tituloReceberParaMap(t),
        'valorAlocado': a.valor,
      });
    }
    final clienteId = rec.cliente.targetId;
    final saldoRestante = clienteId > 0
        ? d.vendaRepository.saldoFiadoEmAbertoCliente(clienteId)
        : 0.0;
    return {
      'ok': true,
      'id': recebimentoId,
      'item': SyncEntityCodecExtras.recebimentoFiadoParaMap(rec),
      'titulosAlocados': titulosAlocados,
      'saldoRestanteCliente': saldoRestante,
    };
  }

  router.get('/api/titulos', (_) {
    final items = d.vendaRepository.titulos.listarTodosAbertos();
    return lanApiJson({
      'items': items
          .map(
            (l) => {
              ...SyncEntityCodecExtras.tituloReceberParaMap(l.titulo),
              'numeroOrcamento': l.numeroOrcamento,
              'nomeCliente': l.nomeCliente,
              'diasAtraso': l.diasAtraso,
            },
          )
          .toList(),
    });
  });

  /// Titulos quitados por cliente (extrato / recibo no terminal leve).
  router.get('/api/titulos/quitados', (Request r) {
    final clienteId =
        int.tryParse(r.url.queryParameters['clienteId'] ?? '') ?? 0;
    if (clienteId <= 0) {
      return lanApiJson({'error': 'clienteId obrigatorio'}, status: 400);
    }
    final limite =
        int.tryParse(r.url.queryParameters['limit'] ?? '') ?? 100;
    final items = d.vendaRepository.titulos.listarQuitadosPorCliente(
      clienteId,
      limite: limite.clamp(1, 500),
    );
    return lanApiJson({
      'items': items.map(SyncEntityCodecExtras.tituloReceberParaMap).toList(),
    });
  });

  /// Recebimentos de fiado por cliente.
  router.get('/api/recebimentos', (Request r) {
    final clienteId =
        int.tryParse(r.url.queryParameters['clienteId'] ?? '') ?? 0;
    if (clienteId <= 0) {
      return lanApiJson({'error': 'clienteId obrigatorio'}, status: 400);
    }
    final items = d.vendaRepository.recebimentos.listarPorCliente(clienteId);
    return lanApiJson({
      'items':
          items.map(SyncEntityCodecExtras.recebimentoFiadoParaMap).toList(),
    });
  });

  router.get('/api/recebimentos/<id|[0-9]+>', (Request _, String id) {
    final recebimentoId = int.tryParse(id) ?? 0;
    if (recebimentoId <= 0) {
      return lanApiJson({'error': 'id invalido'}, status: 400);
    }
    final payload = payloadRecebimento(recebimentoId);
    if (payload['item'] == null) {
      return lanApiJson({'error': 'nao encontrado'}, status: 404);
    }
    return lanApiJson(payload);
  });

  /// Saldo de fiado em aberto + dados de limite do cliente (terminal leve).
  router.get('/api/titulos/saldo-cliente/<id|[0-9]+>', (Request _, String id) {
    final clienteId = int.tryParse(id) ?? 0;
    if (clienteId <= 0) {
      return lanApiJson({'error': 'clienteId invalido'}, status: 400);
    }
    final saldo =
        d.vendaRepository.saldoFiadoEmAbertoCliente(clienteId);
    final exposicao = d.vendaRepository.exposicaoFiadoCliente(clienteId);
    final cliente = d.clienteRepository.obterPorId(clienteId);
    return lanApiJson({
      'clienteId': clienteId,
      'saldo': saldo,
      'exposicao': exposicao,
      'limiteCredito': cliente?.limiteCredito ?? 0,
      'bloqueadoFiado': cliente?.bloqueadoFiado ?? false,
      'motivoBloqueio': cliente?.motivoBloqueio ?? '',
      'nomeCliente': cliente?.nomeRazao ?? '',
    });
  });

  /// Validacao de limite de credito no PC servidor (fonte ObjectBox).
  router.post('/api/titulos/validar-limite', (Request r) async {
    final body = await lanApiReadJsonMap(r) ?? <String, dynamic>{};
    final clienteId = (body['clienteId'] as num?)?.toInt() ?? 0;
    final valor = (body['valorFiadoOperacao'] as num?)?.toDouble() ?? 0;
    final ignorar = (body['ignorarVendaId'] as num?)?.toInt();
    if (clienteId <= 0) {
      return lanApiJson({'error': 'clienteId obrigatorio'}, status: 400);
    }
    final v = d.vendaRepository.validarLimiteCredito(
      clienteId: clienteId,
      valorFiadoOperacao: valor,
      ignorarVendaId: ignorar,
    );
    return lanApiJson({
      'permitido': v.permitido,
      'mensagem': v.mensagem,
      'saldoEmAberto': v.saldoEmAberto,
      'limite': v.limite,
      'valorFiadoOperacao': v.valorFiadoOperacao,
      'saldoAposOperacao': v.saldoAposOperacao,
      'nomeCliente': v.nomeCliente,
    });
  });

  router.post('/api/titulos/receber-fifo', (Request r) async {
    final body = await lanApiReadJsonMap(r);
    final clienteId = (body?['clienteId'] as num?)?.toInt() ?? 0;
    final valor = (body?['valorRecebido'] as num?)?.toDouble() ?? 0;
    if (clienteId <= 0) {
      return lanApiJson({'error': 'clienteId obrigatorio'}, status: 400);
    }
    if (valor <= 0) {
      return lanApiJson({'error': 'valorRecebido obrigatorio'}, status: 400);
    }
    try {
      final recebimentoId =
          d.vendaRepository.recebimentos.registrarRecebimentoFifo(
        clienteId: clienteId,
        valorRecebido: valor,
        formaPagamento: (body?['formaPagamento'] ?? 'dinheiro').toString(),
        observacao: (body?['observacao'] ?? '').toString(),
      );
      d.notificar('titulo_receber');
      d.notificar('recebimento_fiado');
      return lanApiJson(payloadRecebimento(recebimentoId));
    } catch (e) {
      return lanApiJson({'error': '$e'}, status: 400);
    }
  });
  router.post('/api/titulos/<id|[0-9]+>/receber', (Request r, String id) async {
    final body = await lanApiReadJsonMap(r);
    final valor = (body?['valorRecebido'] as num?)?.toDouble() ?? 0;
    if (valor <= 0) {
      return lanApiJson({'error': 'valorRecebido obrigatorio'}, status: 400);
    }
    try {
      final recebimentoId = d.vendaRepository.recebimentos
          .registrarRecebimentoTitulo(
            tituloId: int.parse(id),
            valorRecebido: valor,
            formaPagamento: (body?['formaPagamento'] ?? 'dinheiro').toString(),
            observacao: (body?['observacao'] ?? '').toString(),
          );
      d.notificar('titulo_receber');
      d.notificar('recebimento_fiado');
      return lanApiJson(payloadRecebimento(recebimentoId));
    } catch (e) {
      return lanApiJson({'error': '$e'}, status: 400);
    }
  });

  router.get('/api/contas-pagar', (Request r) {
    d.contaPagarRepository.sincronizarPendenteParaAtrasado();
    final status = r.url.queryParameters['status'];
    return lanApiJson({
      'items': d.contaPagarRepository
          .listar(status: status, ordenarDesc: true)
          .map(SyncEntityCodecOperacional.contaPagarParaMap)
          .toList(),
    });
  });
  router.post('/api/contas-pagar', (Request r) async {
    final body = await lanApiReadJsonMap(r);
    final valor = (body?['valor'] as num?)?.toDouble() ?? 0;
    final vencimento = DateTime.tryParse(
      (body?['vencimento'] ?? '').toString(),
    );
    if (valor <= 0 || vencimento == null) {
      return lanApiJson({
        'error': 'valor e vencimento obrigatorios',
      }, status: 400);
    }
    try {
      final conta = await d.contaPagarRepository.criarManual(
        nomeFornecedor: (body?['nomeFornecedor'] ?? '').toString(),
        cnpj: body?['cnpj']?.toString(),
        valor: valor,
        vencimento: vencimento,
        numeroParcela: (body?['numeroParcela'] ?? '001/001').toString(),
        emissao: DateTime.tryParse((body?['emissao'] ?? '').toString()),
        observacaoNota: body?['observacaoNota']?.toString(),
      );
      d.notificar('conta_pagar');
      d.notificar('financeiro');
      return lanApiJson({
        'ok': true,
        'id': conta.id,
        'item': SyncEntityCodecOperacional.contaPagarParaMap(conta),
      });
    } catch (e) {
      return lanApiJson({'error': '$e'}, status: 400);
    }
  });
  router.post('/api/contas-pagar/<id|[0-9]+>/baixar', (
    Request r,
    String id,
  ) async {
    final body = await lanApiReadJsonMap(r);
    final conta = d.objectBox.contaPagarBox.get(int.parse(id));
    if (conta == null) {
      return lanApiJson({'error': 'nao encontrado'}, status: 404);
    }
    final valor =
        (body?['valorPago'] as num?)?.toDouble() ?? conta.valorParcela;
    final data =
        DateTime.tryParse((body?['dataPagamento'] ?? '').toString()) ??
        DateTime.now();
    try {
      final baixada = await d.contaPagarRepository.registrarBaixa(
        conta: conta,
        valorPago: valor,
        dataPagamento: data,
      );
      d.notificar('conta_pagar');
      d.notificar('financeiro');
      return lanApiJson({
        'ok': true,
        'item': SyncEntityCodecOperacional.contaPagarParaMap(baixada),
      });
    } catch (e) {
      return lanApiJson({'error': '$e'}, status: 400);
    }
  });

  /// Remove titulo pendente/atrasado (nao permite se ja estiver pago).
  router.post(
    '/api/contas-pagar/<id|[0-9]+>/remover',
    (Request _, String id) => removerContaPagarHandler(id),
  );

  /// Alias REST DELETE.
  router.delete(
    '/api/contas-pagar/<id|[0-9]+>',
    (Request _, String id) => removerContaPagarHandler(id),
  );

  router.get('/api/obrigacoes-mensais', (_) {
    return lanApiJson({
      'items': d.obrigacaoMensalFixaRepository
          .listar()
          .map(d.obrigacaoMensalFixaRepository.paraMap)
          .toList(),
    });
  });

  router.post('/api/obrigacoes-mensais', (Request r) async {
    final body = await lanApiReadJsonMap(r);
    final valor = (body?['valor'] as num?)?.toDouble() ?? 0;
    final dia = (body?['diaVencimento'] as num?)?.toInt() ?? 0;
    final descricao = (body?['descricao'] ?? '').toString();
    if (descricao.trim().isEmpty || valor <= 0 || dia < 1) {
      return lanApiJson({
        'error': 'descricao, valor e diaVencimento obrigatorios',
      }, status: 400);
    }
    try {
      final item = await d.obrigacaoMensalFixaRepository.salvar(
        id: (body?['id'] as num?)?.toInt() ?? 0,
        descricao: descricao,
        valor: valor,
        periodicidade: (body?['periodicidade'] ?? '').toString(),
        diaVencimento: dia,
        mesVencimento: (body?['mesVencimento'] as num?)?.toInt() ?? 1,
        cnpj: (body?['cnpj'] ?? '').toString(),
        ativo: body?['ativo'] != false,
      );
      d.notificar('conta_pagar');
      d.notificar('financeiro');
      return lanApiJson({
        'ok': true,
        'item': d.obrigacaoMensalFixaRepository.paraMap(item),
      });
    } catch (e) {
      return lanApiJson({'error': '$e'}, status: 400);
    }
  });

  router.post('/api/obrigacoes-mensais/<id|[0-9]+>/remover', (
    Request _,
    String id,
  ) {
    final oid = int.tryParse(id) ?? 0;
    if (oid <= 0) {
      return lanApiJson({'error': 'id invalido'}, status: 400);
    }
    final ok = d.obrigacaoMensalFixaRepository.remover(oid);
    if (!ok) {
      return lanApiJson({'error': 'nao encontrado'}, status: 404);
    }
    d.notificar('financeiro');
    return lanApiJson({'ok': true, 'id': oid});
  });

  router.post('/api/obrigacoes-mensais/gerar', (Request _) async {
    try {
      final criadas =
          await d.obrigacaoMensalFixaRepository.gerarPendenciasRecentes();
      if (criadas > 0) {
        d.notificar('conta_pagar');
        d.notificar('financeiro');
      }
      return lanApiJson({'ok': true, 'criadas': criadas});
    } catch (e) {
      return lanApiJson({'error': '$e'}, status: 400);
    }
  });

  router.get('/api/financeiro/resumo', (_) {
    final s = FinanceiroResumoService.montar(
      vendaRepository: d.vendaRepository,
      objectBox: d.objectBox,
    );
    return lanApiJson({
      'totalAReceber': s.totalAReceber,
      'aReceberVencido': s.aReceberVencido,
      'aReceberVenceHoje': s.aReceberVenceHoje,
      'aReceberProximos7': s.aReceberProximos7,
      'totalAPagarPendente': s.totalAPagarPendente,
      'aPagarAtrasado': s.aPagarAtrasado,
      'aPagarProximos7': s.aPagarProximos7,
      'qtdTitulosReceberAbertos': s.qtdTitulosReceberAbertos,
      'qtdContasPagarAbertas': s.qtdContasPagarAbertas,
      'qtdContasPagarAtrasadas': s.qtdContasPagarAtrasadas,
      'saldoCaixaEstimado': s.saldoCaixaEstimado,
      'caixaAberto': s.caixaAberto,
      'operadorCaixa': s.operadorCaixa,
      'saldoLiquidoProjetado': s.saldoLiquidoProjetado,
      'temAlertaCritico': s.temAlertaCritico,
      'semMovimentacaoFinanceira': s.semMovimentacaoFinanceira,
    });
  });
  router.get('/api/financeiro/tesouraria-semanal', (_) {
    final s = TesourariaSemanalService.montar(
      vendaRepository: d.vendaRepository,
      objectBox: d.objectBox,
    );
    String chaveDia(DateTime d) =>
        '${d.year.toString().padLeft(4, '0')}-'
        '${d.month.toString().padLeft(2, '0')}-'
        '${d.day.toString().padLeft(2, '0')}';
    final itensMap = <String, List<Map<String, dynamic>>>{};
    for (final e in s.itensPorDia.entries) {
      itensMap[chaveDia(e.key)] = e.value
          .map(
            (i) => {
              'tipo': i.tipo,
              'descricao': i.descricao,
              'valor': i.valor,
              'referencia': i.referencia,
              'realizado': i.realizado,
            },
          )
          .toList();
    }
    return lanApiJson({
      'dias': s.dias
          .map(
            (d) => {
              'dia': d.dia.toUtc().toIso8601String(),
              'entradasPrevistas': d.entradasPrevistas,
              'saidasPrevistas': d.saidasPrevistas,
              'entradasRealizadas': d.entradasRealizadas,
              'saidasRealizadas': d.saidasRealizadas,
              'qtdEntradasPrevistas': d.qtdEntradasPrevistas,
              'qtdSaidasPrevistas': d.qtdSaidasPrevistas,
              'qtdEntradasRealizadas': d.qtdEntradasRealizadas,
              'qtdSaidasRealizadas': d.qtdSaidasRealizadas,
              'saldoPrevisto': d.saldoPrevisto,
              'saldoRealizado': d.saldoRealizado,
            },
          )
          .toList(),
      'itensPorDia': itensMap,
      'totalEntradasPrevistas': s.totalEntradasPrevistas,
      'totalSaidasPrevistas': s.totalSaidasPrevistas,
      'totalEntradasRealizadas': s.totalEntradasRealizadas,
      'totalSaidasRealizadas': s.totalSaidasRealizadas,
      'saldoPrevistoSemana': s.saldoPrevistoSemana,
      'saldoRealizadoSemana': s.saldoRealizadoSemana,
    });
  });
}
