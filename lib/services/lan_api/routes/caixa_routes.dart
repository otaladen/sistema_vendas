import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';
import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';

import '../../../data/app_config_repository.dart';
import '../../../data/caixa_auditoria_repository.dart';
import '../../../data/caixa_sessao_repository.dart';
import '../../../data/sync/caixa_local_refresh_hub.dart';
import '../../../data/sync/caixa_status_hub.dart';
import '../../../domain/leitura_parcial_caixa.dart';
import '../../../model/caixa_sessao.dart';
import '../lan_api_deps.dart';
import '../lan_api_json.dart';

/// Propaga WS + refresh local no PC1 (mesmo processo da API).
void _avisarCaixaMudou(LanApiDeps d) {
  d.notificar('caixa_sessoes');
  d.notificar('caixa');
  try {
    CaixaLocalRefreshHub.instance.notificar();
  } catch (_) {}
  try {
    // ignore: unawaited_futures
    CaixaStatusHub.instance.sincronizarDoRepositorio();
  } catch (_) {}
}

CaixaSessao? _primeiraAberta(Map<String, CaixaSessao> mapa) {
  for (final s in mapa.values) {
    if (s.aberto) return s;
  }
  return null;
}

CaixaSessao? _sessaoAbertaPara(
  Map<String, CaixaSessao> mapa, {
  required String terminalId,
  required bool umCaixa,
}) {
  return CaixaSessaoRepository.sessaoAbertaPara(
    mapa,
    terminalId: terminalId,
    umCaixaAbertoPorLoja: umCaixa,
  );
}

CaixaSessao _fecharSessao(CaixaSessao alvo) {
  return alvo.copyWith(
    aberto: false,
    operador: '',
    limparAbertura: true,
    fundoTroco: 0,
    suprimentos: 0,
    sangrias: 0,
    atualizadoEm: DateTime.now(),
  );
}

/// Sessoes de caixa compartilhadas entre PC servidor e terminais leves.
void registerCaixaRoutes(Router router, LanApiDeps d) {
  final repo = CaixaSessaoRepository();
  final configRepo = AppConfigRepository();

  router.get('/api/caixa/sessoes', (_) async {
    final mapa = await repo.listarTodasSessoes();
    final aberta = _primeiraAberta(mapa);
    final config = await configRepo.carregarEmpresaConfig();
    return lanApiJson({
      'umCaixaAbertoPorLoja': config.umCaixaAbertoPorLoja,
      'aberta': aberta?.toMap(),
      'terminais': mapa.map((k, v) => MapEntry(k, v.toMap())),
      'abertosCount': mapa.values.where((s) => s.aberto).length,
    });
  });

  /// Sessao ativa para o terminal: libera operacao (importar/vender) conforme
  /// regra um-caixa-por-loja ou multi-caixa por terminal.
  router.get('/api/caixa/sessao-ativa', (Request r) async {
    final terminalId =
        (r.url.queryParameters['terminalId'] ?? '').toString().trim();
    final mapa = await repo.listarTodasSessoes();
    final config = await configRepo.carregarEmpresaConfig();
    final umCaixa = config.umCaixaAbertoPorLoja;
    final abertaLoja = _primeiraAberta(mapa);
    final minha = terminalId.isEmpty ? null : mapa[terminalId];

    CaixaSessao? sessao;
    var operacaoLiberada = false;
    var aderido = false;
    var motivo = 'caixa_fechado';

    if (umCaixa) {
      if (abertaLoja != null && abertaLoja.aberto) {
        sessao = abertaLoja;
        operacaoLiberada = true;
        aderido = terminalId.isNotEmpty && abertaLoja.terminalId != terminalId;
        motivo = aderido ? 'aderido_loja' : 'aberto_neste_terminal';
      }
    } else {
      if (minha != null && minha.aberto) {
        sessao = minha;
        operacaoLiberada = true;
        motivo = 'aberto_neste_terminal';
      } else if (abertaLoja != null) {
        sessao = abertaLoja;
        motivo = 'aberto_outro_terminal';
      }
    }

    return lanApiJson({
      'umCaixaAbertoPorLoja': umCaixa,
      'operacaoLiberada': operacaoLiberada,
      'aderido': aderido,
      'motivo': motivo,
      'sessao': sessao?.toMap(),
      'aberta': abertaLoja?.toMap(),
      'terminais': mapa.map((k, v) => MapEntry(k, v.toMap())),
      'abertosCount': mapa.values.where((s) => s.aberto).length,
    });
  });

  router.post('/api/caixa/sessoes/abrir', (Request r) async {
    try {
      final body = await lanApiReadJsonMap(r);
      if (body == null) {
        return lanApiJson({'error': 'JSON invalido'}, status: 400);
      }
      final terminalId = (body['terminalId'] ?? '').toString().trim();
      final operador = (body['operador'] ?? '').toString().trim();
      final fundo = (body['fundoTroco'] as num?)?.toDouble() ?? 0;
      if (terminalId.isEmpty || operador.isEmpty) {
        return lanApiJson(
          {'error': 'terminalId e operador obrigatorios'},
          status: 400,
        );
      }
      final config = await configRepo.carregarEmpresaConfig();
      final resultado = await repo.abrirSessaoAtomica(
        terminalId: terminalId,
        operador: operador,
        fundoTroco: fundo,
        umCaixaAbertoPorLoja: config.umCaixaAbertoPorLoja,
      );
      _avisarCaixaMudou(d);
      final sessao = resultado['sessao'] as CaixaSessao;
      final terminais =
          resultado['terminais'] as Map<String, CaixaSessao>;
      return lanApiJson({
        'ok': true,
        'jaAberto': resultado['jaAberto'] == true,
        'sessao': sessao.toMap(),
        'terminais': terminais.map((k, v) => MapEntry(k, v.toMap())),
      });
    } on ArgumentError catch (e) {
      return lanApiJson({'error': e.message}, status: 400);
    } on StateError catch (e) {
      final msg = '$e';
      if (msg.contains('caixa_ja_aberto:')) {
        final resto = msg.split('caixa_ja_aberto:').last;
        final partes = resto.split('|');
        final tid = partes.isNotEmpty ? partes.first.trim() : '';
        final op = partes.length > 1 ? partes[1].trim() : '';
        return lanApiJson({
          'error': 'caixa_ja_aberto',
          'message':
              'Somente um caixa pode ficar aberto por loja. '
              'Terminal $tid esta aberto'
              '${op.isNotEmpty ? ' (operador: $op)' : ''}. '
              'Aderira automaticamente a sessao existente.',
          'sessaoAberta': {
            'terminalId': tid,
            'operador': op,
            'aberto': true,
          },
        }, status: 409);
      }
      return lanApiJson({'error': msg}, status: 409);
    } catch (e) {
      return lanApiJson(
        {'ok': false, 'error': 'Falha ao abrir caixa', 'code': 'caixa_abrir'},
        status: 500,
      );
    }
  });

  /// Fecha a sessao do terminal, ou (com forcar / um-caixa) a sessao aberta da loja.
  router.post('/api/caixa/sessoes/fechar', (Request r) async {
    try {
      final body = await lanApiReadJsonMap(r);
      if (body == null) {
        return lanApiJson({'error': 'JSON invalido'}, status: 400);
      }
      final terminalId = (body['terminalId'] ?? '').toString().trim();
      final forcar = body['forcar'] == true;
      if (terminalId.isEmpty) {
        return lanApiJson({'error': 'terminalId obrigatorio'}, status: 400);
      }
      final config = await configRepo.carregarEmpresaConfig();
      final resultado = await repo.fecharSessaoAtomica(
        terminalId: terminalId,
        forcar: forcar,
        umCaixaAbertoPorLoja: config.umCaixaAbertoPorLoja,
      );
      _avisarCaixaMudou(d);
      final terminais =
          resultado['terminais'] as Map<String, CaixaSessao>;
      final sessao = resultado['sessao'] as CaixaSessao?;
      return lanApiJson({
        'ok': true,
        'jaFechado': resultado['jaFechado'] == true,
        if (sessao != null) 'sessao': sessao.toMap(),
        'terminais': terminais.map((k, v) => MapEntry(k, v.toMap())),
        'fechadasCount': resultado['fechadasCount'] ??
            terminais.values.where((s) => !s.aberto).length,
      });
    } on ArgumentError catch (e) {
      return lanApiJson({'error': e.message}, status: 400);
    } on StateError catch (e) {
      final msg = '$e';
      if (msg.contains('caixa_outro_terminal:')) {
        final resto = msg.split('caixa_outro_terminal:').last;
        final partes = resto.split('|');
        final tid = partes.isNotEmpty ? partes.first.trim() : '';
        final op = partes.length > 1 ? partes[1].trim() : '';
        return lanApiJson({
          'error': 'caixa_outro_terminal',
          'message':
              'Caixa aberto em $tid'
              '${op.isNotEmpty ? ' ($op)' : ''}. '
              'Confirme o fechamento remoto.',
          'sessaoAberta': {
            'terminalId': tid,
            'operador': op,
            'aberto': true,
          },
        }, status: 409);
      }
      return lanApiJson({'error': msg}, status: 409);
    } catch (e) {
      return lanApiJson(
        {'ok': false, 'error': 'Falha ao fechar caixa', 'code': 'caixa_fechar'},
        status: 500,
      );
    }
  });

  /// Forca o fechamento de TODAS as sessoes abertas (desbloqueio de orfaos).
  router.post('/api/caixa/sessoes/reset', (Request r) async {
    final body = await lanApiReadJsonMap(r) ?? <String, dynamic>{};
    final motivo = (body['motivo'] ?? 'reset_admin').toString();
    final mapa = await repo.listarTodasSessoes();
    var fechadas = 0;
    for (final s in mapa.values) {
      if (!s.aberto) continue;
      await repo.salvarSessaoLocal(_fecharSessao(s), propagarRede: true);
      fechadas++;
    }
    _avisarCaixaMudou(d);
    final atualizado = await repo.listarTodasSessoes();
    return lanApiJson({
      'ok': true,
      'fechadas': fechadas,
      'motivo': motivo,
      'terminais': atualizado.map((k, v) => MapEntry(k, v.toMap())),
      'abertosCount': atualizado.values.where((s) => s.aberto).length,
    });
  });

  /// Leitura parcial: totais de vendas/pagamentos desde a abertura, sem fechar.
  router.get('/api/caixa/leitura-parcial', (Request r) async {
    try {
      final terminalId =
          (r.url.queryParameters['terminalId'] ?? '').toString().trim();
      final mapa = await repo.listarTodasSessoes();
      final config = await configRepo.carregarEmpresaConfig();
      final aberta = _sessaoAbertaPara(
        mapa,
        terminalId: terminalId,
        umCaixa: config.umCaixaAbertoPorLoja,
      );
      if (aberta == null || !aberta.aberto) {
        return lanApiJson({'error': 'caixa nao aberto'}, status: 409);
      }
      final abertura = aberta.aberturaEm;
      final agora = DateTime.now();
      final totais = d.vendaRepository.totaisMeiosPagamentoVendasFinalizadas(
        inicio: abertura,
        fim: agora,
      );
      final resumo = d.vendaRepository.resumoVendasFinalizadasNoPeriodo(
        inicio: abertura,
        fim: agora,
      );
      final recList = d.vendaRepository.recebimentos.listarNoPeriodo(
        inicio: abertura ?? agora,
        fim: agora,
      );
      var recTotal = 0.0;
      var recDinheiro = 0.0;
      var recPix = 0.0;
      var recDebito = 0.0;
      var recCredito = 0.0;
      for (final rec in recList) {
        recTotal += rec.valorTotal;
        switch (rec.formaPagamento) {
          case 'pix':
            recPix += rec.valorTotal;
            break;
          case 'cartao_debito':
            recDebito += rec.valorTotal;
            break;
          case 'cartao_credito':
            recCredito += rec.valorTotal;
            break;
          case 'dinheiro':
            recDinheiro += rec.valorTotal;
            break;
          default:
            break;
        }
      }
      final snap = LeituraParcialCaixaSnapshot.montar(
        fundoTroco: aberta.fundoTroco,
        suprimentos: aberta.suprimentos,
        sangrias: aberta.sangrias,
        vendasDinheiro: totais.dinheiro,
        vendasPix: totais.pix,
        vendasDebito: totais.debito,
        vendasCredito: totais.credito,
        vendasVale: totais.vale,
        recDinheiro: recDinheiro,
        recPix: recPix,
        recDebito: recDebito,
        recCredito: recCredito,
        recTotal: recTotal,
        recQuantidade: recList.length,
        totalVendas: resumo.totalVendas,
        quantidadeVendas: resumo.quantidadeVendas,
        aberturaEm: abertura,
        terminalId: aberta.terminalId,
        operador: aberta.operador,
      );
      return lanApiJson(snap.toJson());
    } catch (e) {
      return lanApiJson({'error': '$e'}, status: 500);
    }
  });

  /// Atualiza operador/fundo da sessao aberta (sangria/suprimento via /movimentacao).
  router.post('/api/caixa/sessoes/atualizar', (Request r) async {
    final body = await lanApiReadJsonMap(r);
    if (body == null) {
      return lanApiJson({'error': 'JSON invalido'}, status: 400);
    }
    final terminalId = (body['terminalId'] ?? '').toString().trim();
    if (terminalId.isEmpty) {
      return lanApiJson({'error': 'terminalId obrigatorio'}, status: 400);
    }
    final mapa = await repo.listarTodasSessoes();
    final config = await configRepo.carregarEmpresaConfig();
    final atual = _sessaoAbertaPara(
      mapa,
      terminalId: terminalId,
      umCaixa: config.umCaixaAbertoPorLoja,
    );
    if (atual == null || !atual.aberto) {
      return lanApiJson({'error': 'caixa nao aberto neste terminal'}, status: 409);
    }
    final sessao = atual.copyWith(
      operador: (body['operador'] as String?)?.trim().isNotEmpty == true
          ? (body['operador'] as String).trim()
          : atual.operador,
      fundoTroco: (body['fundoTroco'] as num?)?.toDouble() ?? atual.fundoTroco,
      atualizadoEm: DateTime.now(),
    );
    await repo.salvarSessaoLocal(sessao, propagarRede: true);
    _avisarCaixaMudou(d);
    return lanApiJson({'ok': true, 'sessao': sessao.toMap()});
  });

  /// Incremento atomico de suprimento/sangria (evita lost update entre terminais).
  router.post('/api/caixa/sessoes/movimentacao', (Request r) async {
    final body = await lanApiReadJsonMap(r);
    if (body == null) {
      return lanApiJson({'error': 'JSON invalido'}, status: 400);
    }
    final terminalId = (body['terminalId'] ?? '').toString().trim();
    if (terminalId.isEmpty) {
      return lanApiJson({'error': 'terminalId obrigatorio'}, status: 400);
    }
    final tipo = (body['tipo'] ?? '').toString().trim().toLowerCase();
    final valor = (body['valor'] as num?)?.toDouble() ?? 0;
    if (valor <= 0) {
      return lanApiJson({'error': 'valor deve ser maior que zero'}, status: 400);
    }
    if (tipo != 'suprimento' && tipo != 'sangria') {
      return lanApiJson(
        {'error': 'tipo deve ser suprimento ou sangria'},
        status: 400,
      );
    }
    final config = await configRepo.carregarEmpresaConfig();
    try {
      final sessao = await repo.registrarMovimentacao(
        terminalId: terminalId,
        deltaSuprimento: tipo == 'suprimento' ? valor : 0,
        deltaSangria: tipo == 'sangria' ? valor : 0,
        umCaixaAbertoPorLoja: config.umCaixaAbertoPorLoja,
        propagarRede: true,
      );
      _avisarCaixaMudou(d);
      return lanApiJson({'ok': true, 'sessao': sessao.toMap()});
    } on StateError catch (e) {
      return lanApiJson({'error': '$e'}, status: 409);
    } catch (e) {
      return lanApiJson({'error': '$e'}, status: 400);
    }
  });

  /// Auditoria local do caixa no PC1 (SharedPreferences do servidor).
  /// Terminais leves leem/escrevem aqui em vez do prefs local.
  router.get('/api/caixa/auditoria', (Request r) async {
    final evento = (r.url.queryParameters['evento'] ?? '').trim();
    final limit = lanApiQueryInt(r, 'limit', fallback: 300).clamp(1, 500);
    final repo = CaixaAuditoriaRepository();
    var items = await repo.listarTodos();
    if (evento.isNotEmpty) {
      items = items.where((e) => e.evento == evento).toList();
    }
    if (items.length > limit) {
      items = items.take(limit).toList();
    }
    return lanApiJson({
      'items': items
          .map(
            (e) => {
              'em': e.em.toIso8601String(),
              'evento': e.evento,
              'usuario': e.usuario,
              'operadorCaixa': e.operadorCaixa,
              'detalhes': e.detalhes,
            },
          )
          .toList(),
    });
  });

  router.get('/api/relatorios/historico-fechamento-caixa', (Request r) async {
    final limit = lanApiQueryInt(r, 'limit', fallback: 300).clamp(1, 500);
    final repo = CaixaAuditoriaRepository();
    var items = await repo.listarFechamentos();
    if (items.length > limit) {
      items = items.take(limit).toList();
    }
    return lanApiJson({
      'items': items
          .map(
            (e) => {
              'em': e.em.toIso8601String(),
              'evento': e.evento,
              'usuario': e.usuario,
              'operadorCaixa': e.operadorCaixa,
              'detalhes': e.detalhes,
            },
          )
          .toList(),
    });
  });

  router.post('/api/caixa/auditoria', (Request r) async {
    final body = await lanApiReadJsonMap(r);
    if (body == null) {
      return lanApiJson({'error': 'JSON invalido'}, status: 400);
    }
    final evento = (body['evento'] ?? '').toString().trim();
    if (evento.isEmpty) {
      return lanApiJson({'error': 'evento obrigatorio'}, status: 400);
    }
    final detalhesRaw = body['detalhes'];
    final detalhes = detalhesRaw is Map
        ? Map<String, dynamic>.from(detalhesRaw)
        : <String, dynamic>{};
    final registro = <String, dynamic>{
      'em': (body['em'] ?? DateTime.now().toIso8601String()).toString(),
      'usuario': (body['usuario'] ?? '').toString(),
      'operadorCaixa': (body['operadorCaixa'] ?? '').toString(),
      'evento': evento,
      'detalhes': detalhes,
    };
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(CaixaAuditoriaRepository.chavePrefs);
    List<dynamic> lista = [];
    if (raw != null && raw.trim().isNotEmpty) {
      try {
        final decoded = jsonDecode(raw);
        if (decoded is List) lista = List<dynamic>.from(decoded);
      } catch (_) {}
    }
    lista.add(registro);
    if (lista.length > 300) {
      lista = lista.sublist(lista.length - 300);
    }
    await prefs.setString(
      CaixaAuditoriaRepository.chavePrefs,
      jsonEncode(lista),
    );
    return lanApiJson({'ok': true});
  });

  /// Substitui o log unificado (expurgo/manutencao no terminal).
  router.post('/api/caixa/auditoria/substituir', (Request r) async {
    final body = await lanApiReadJsonMap(r);
    if (body == null) {
      return lanApiJson({'error': 'JSON invalido'}, status: 400);
    }
    final raw = body['items'];
    if (raw is! List) {
      return lanApiJson({'error': 'items obrigatorio'}, status: 400);
    }
    final items = raw
        .whereType<Map>()
        .map((e) => Map<String, dynamic>.from(e))
        .toList();
    await CaixaAuditoriaRepository().substituirTodos(items);
    return lanApiJson({'ok': true, 'total': items.length});
  });
}
