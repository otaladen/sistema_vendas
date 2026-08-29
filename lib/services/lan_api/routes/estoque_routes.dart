import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';

import '../../../data/reajuste_preco_repository.dart';
import '../../../data/sugestao_compra_repository.dart';
import '../../../data/lote_produto_repository.dart';
import '../../../services/compras_preditivas_service.dart';
import '../../../data/sync/estoque_local_refresh_hub.dart';
import '../../../data/sync/sync_entity_codec.dart';
import '../../../data/sync/sync_entity_codec_operacional.dart';
import '../../../domain/reajuste_preco_lote.dart';
import '../../../model/usuario_sistema.dart';
import '../../../services/estoque_diagnostico_service.dart';
import '../../../services/lote_fefo_service.dart';
import '../lan_api_deps.dart';
import '../lan_api_json.dart';

void registerEstoqueRoutes(Router router, LanApiDeps d) {
  router.post('/api/estoque/ajuste', (Request r) async {
    final body = await lanApiReadJsonMap(r);
    if (body == null) {
      return lanApiJson({'error': 'JSON invalido'}, status: 400);
    }
    final produtoId = (body['produtoId'] as num?)?.toInt() ?? 0;
    if (produtoId <= 0) {
      return lanApiJson({'error': 'produtoId obrigatorio'}, status: 400);
    }
    final novaQtdRaw = body['quantidadeAjustada'] ??
        body['novaQuantidadeFisica'] ??
        body['novaQuantidade'];
    final novaQtd = novaQtdRaw is num
        ? novaQtdRaw.toInt()
        : int.tryParse('$novaQtdRaw');
    if (novaQtd == null) {
      return lanApiJson(
        {'error': 'quantidadeAjustada/novaQuantidadeFisica obrigatoria'},
        status: 400,
      );
    }
    final motivo = (body['motivo'] ?? '').toString().trim();
    if (motivo.isEmpty) {
      return lanApiJson({'error': 'motivo obrigatorio'}, status: 400);
    }
    final usuarioLogin = (body['usuarioLogin'] ?? body['usuarioId'] ?? '')
        .toString()
        .trim();
    final numeroLote = (body['numeroLote'] ?? '').toString().trim();
    final dataValidade = DateTime.tryParse(
      (body['dataValidade'] ?? '').toString(),
    )?.toUtc();
    try {
      d.produtoRepository.ajustarEstoqueManual(
        produtoId: produtoId,
        novaQuantidadeFisica: novaQtd,
        motivo: motivo,
        usuarioLogin: usuarioLogin,
        numeroLote: numeroLote,
        dataValidade: dataValidade,
      );
      EstoqueLocalRefreshHub.instance.notificar(ids: [produtoId]);
      d.notificar('produto', ids: [produtoId]);
      final p = d.produtoRepository.obterPorId(produtoId);
      return lanApiJson({
        'ok': true,
        if (p != null) 'item': SyncEntityCodec.produtoParaMap(p),
      });
    } catch (e) {
      return lanApiJson({'error': '$e'}, status: 400);
    }
  });

  router.get('/api/estoque/ponto-pedido', (Request r) {
    try {
      final dias = lanApiQueryInt(r, 'dias', fallback: 60).clamp(1, 365);
      final items = ComprasPreditivasService(
        d.objectBox,
        diasHistoricoVendas: dias,
      ).montarItensPontoPedidoApi(dias: dias);
      return lanApiJson({
        'items': items.map((e) => e.toApiMap()).toList(),
      });
    } catch (e) {
      return lanApiJson({'error': '$e'}, status: 500);
    }
  });

  router.get('/api/estoque/sugestao-compra', (Request r) {
    try {
      final diasPeriodo =
          lanApiQueryInt(r, 'diasPeriodo', fallback: 60).clamp(1, 365);
      final diasCobertura =
          lanApiQueryInt(r, 'diasCobertura', fallback: 30).clamp(1, 365);
      final apenas = (r.url.queryParameters['apenasPrioritarios'] ?? 'true')
              .toLowerCase() !=
          'false';
      final fornecedor =
          (r.url.queryParameters['fornecedor'] ?? '').trim();
      final repo = SugestaoCompraRepository(d.objectBox);
      final linhas = repo.montarLinhas(
        diasPeriodoConsumo: diasPeriodo,
        diasCoberturaAlvo: diasCobertura,
        apenasComSugestaoOuRisco: apenas,
        fornecedorFiltro: fornecedor.isEmpty ? null : fornecedor,
      );
      return lanApiJson({
        'items': linhas.map(LinhaSugestaoCompra.toApiMap).toList(),
        'fornecedores': repo.indiceFornecedoresNfe().nomesOrdenados,
      });
    } catch (e) {
      return lanApiJson({'error': '$e'}, status: 500);
    }
  });

  router.get('/api/estoque/fornecedores-nfe', (Request r) {
    try {
      final indice =
          SugestaoCompraRepository(d.objectBox).indiceFornecedoresNfe();
      return lanApiJson(indice.toApiMap());
    } catch (e) {
      return lanApiJson({'error': '$e'}, status: 500);
    }
  });

  router.post('/api/estoque/reprocessar-baixa', (Request r) async {
    final body = await lanApiReadJsonMap(r) ?? <String, dynamic>{};
    final vendaId = (body['vendaId'] as num?)?.toInt() ?? 0;
    if (vendaId <= 0) {
      return lanApiJson({'error': 'vendaId obrigatorio'}, status: 400);
    }
    final permitir = body['permitirVendaSemEstoque'] != false;
    try {
      d.vendaRepository.reprocessarBaixaEstoqueDocumentoVenda(
        vendaId,
        permitirVendaSemEstoque: permitir,
      );
      EstoqueLocalRefreshHub.instance.notificar();
      d.notificar('produto');
      d.notificar('venda');
      return lanApiJson({'ok': true, 'vendaId': vendaId});
    } catch (e) {
      return lanApiJson({'error': '$e'}, status: 400);
    }
  });

  router.get('/api/estoque/movimentos', (Request r) {
    final produtoId = lanApiQueryInt(r, 'produtoId');
    final desde = lanApiQueryDate(r, 'desde');
    final ate = lanApiQueryDate(r, 'ate');
    // Kardex/relatorios no terminal leve pedem ate 5000.
    final limit = lanApiQueryInt(r, 'limit', fallback: 200).clamp(1, 5000);
    final List items;
    // Por produto: mesmos recentes do ObjectBox (DESC + limit).
    if (produtoId > 0 && desde == null && ate == null) {
      items = d.movimentoEstoqueRepository
          .listarPorProduto(produtoId, limite: limit)
          .map(SyncEntityCodecOperacional.movimentoEstoqueParaMap)
          .toList();
    } else {
      final periodo = d.movimentoEstoqueRepository.listarPorPeriodo(
        inicio: desde ?? DateTime.utc(1970),
        fim: ate ?? DateTime.now().toUtc(),
        produtoId: produtoId > 0 ? produtoId : null,
      );
      // listarPorPeriodo e ASC; terminal precisa dos mais recentes.
      final recentes = periodo.length <= limit
          ? periodo.reversed.toList()
          : periodo.reversed.take(limit).toList();
      items = recentes
          .map(SyncEntityCodecOperacional.movimentoEstoqueParaMap)
          .toList();
    }
    return lanApiJson({'items': items});
  });

  router.get(
    '/api/lista-compra',
    (_) => lanApiJson({
      'items': d.listaCompraRepository
          .listarTodos()
          .map(SyncEntityCodecOperacional.itemListaCompraParaMap)
          .toList(),
    }),
  );
  router.post('/api/lista-compra', (Request r) async {
    final body = await lanApiReadJsonMap(r);
    final item = body?['item'] is Map
        ? Map<String, dynamic>.from(body!['item'] as Map)
        : body;
    if (item == null) {
      return lanApiJson({'error': 'item obrigatorio'}, status: 400);
    }
    final produtoId = (item['produtoId'] as num?)?.toInt() ?? 0;
    final produto = produtoId > 0
        ? d.produtoRepository.obterPorId(produtoId)
        : null;
    if (produtoId > 0 && produto == null) {
      return lanApiJson({'error': 'produto nao encontrado'}, status: 404);
    }
    try {
      final salvo = d.listaCompraRepository.anotar(
        produto: produto,
        descricaoLivre: (item['descricaoLivre'] ?? '').toString(),
        quantidadeSugerida: (item['quantidadeSugerida'] as num?)?.toInt() ?? 0,
        unidade: (item['unidade'] ?? 'UN').toString(),
        fornecedorTexto: (item['fornecedorTexto'] ?? '').toString(),
        prioridade: (item['prioridade'] ?? 'normal').toString(),
        observacao: (item['observacao'] ?? '').toString(),
        origem: (item['origem'] ?? 'manual').toString(),
        criadoPor: (item['criadoPor'] ?? '').toString(),
      );
      d.notificar('item_lista_compra');
      return lanApiJson({
        'ok': true,
        'id': salvo.id,
        'item': SyncEntityCodecOperacional.itemListaCompraParaMap(salvo),
      });
    } catch (e) {
      return lanApiJson({'error': '$e'}, status: 400);
    }
  });

  router.get('/api/estoque/diagnostico', (_) {
    try {
      final resultado = EstoqueDiagnosticoService(d.objectBox).executar();
      return lanApiJson({
        'geradoEm': resultado.geradoEm.toUtc().toIso8601String(),
        'achados': resultado.achados
            .map(
              (a) => {
                'codigo': a.codigo.name,
                'severidade': a.severidade.name,
                'titulo': a.titulo,
                'detalhe': a.detalhe,
                'vendaId': a.vendaId,
                'produtoId': a.produtoId,
                'podeReprocessarBaixa': a.podeReprocessarBaixa,
              },
            )
            .toList(),
      });
    } catch (e) {
      return lanApiJson({'error': '$e'}, status: 500);
    }
  });

  router.get('/api/produtos/reajustes', (Request r) {
    final limit = lanApiQueryInt(r, 'limit', fallback: 100);
    final repo = ReajustePrecoRepository(d.objectBox, d.produtoRepository);
    return lanApiJson({
      'items': repo
          .listarHistorico(limite: limit)
          .map(SyncEntityCodecOperacional.reajustePrecoParaMap)
          .toList(),
    });
  });

  router.get('/api/produtos/reajustes/<id|[0-9]+>/itens', (Request _, String id) {
    final repo = ReajustePrecoRepository(d.objectBox, d.produtoRepository);
    return lanApiJson({
      'items': repo
          .listarItensDoReajuste(int.parse(id))
          .map(SyncEntityCodecOperacional.reajustePrecoItemParaMap)
          .toList(),
    });
  });

  router.post('/api/produtos/reajuste-lote', (Request r) async {
    final body = await lanApiReadJsonMap(r);
    if (body == null) {
      return lanApiJson({'error': 'JSON invalido'}, status: 400);
    }
    final linhasRaw = body['linhas'];
    if (linhasRaw is! List || linhasRaw.isEmpty) {
      return lanApiJson({'error': 'linhas obrigatorias'}, status: 400);
    }
    final paramsRaw = body['parametros'];
    if (paramsRaw is! Map) {
      return lanApiJson({'error': 'parametros obrigatorios'}, status: 400);
    }
    final login = (body['usuarioLogin'] ?? '').toString().trim();
    if (login.isEmpty) {
      return lanApiJson({'error': 'usuarioLogin obrigatorio'}, status: 400);
    }
    UsuarioSistema? usuario;
    for (final u in await d.usuarioRepository.listarTodos()) {
      if (u.login.trim().toLowerCase() == login.toLowerCase()) {
        usuario = u;
        break;
      }
    }
    usuario ??= UsuarioSistema(
      id: login,
      login: login,
      nome: (body['usuarioNome'] ?? login).toString(),
      senha: '',
    );
    try {
      final pm = Map<String, dynamic>.from(paramsRaw);
      final tabelas = ReajustePrecoParametros.tabelasFromCsv(
        (pm['tabelasCsv'] ?? 'preco1').toString(),
      );
      final parametros = ReajustePrecoParametros(
        modo: (pm['modo'] ?? '').toString() == 'margem'
            ? ReajustePrecoModo.margemFixaSobreCusto
            : ReajustePrecoModo.percentualSobrePrecoAtual,
        tabelas: tabelas.isEmpty
            ? {ReajusteTabelaPreco.preco1}
            : tabelas,
        percentualSobrePreco:
            (pm['percentualSobrePreco'] as num?)?.toDouble() ?? 0,
        margemPercentual: (pm['margemPercentual'] as num?)?.toDouble() ?? 0,
        baseCusto: (pm['baseCusto'] ?? '').toString() == 'custo_medio'
            ? ReajusteBaseCusto.custoMedio
            : ReajusteBaseCusto.custoDigitado,
        arredondamento: switch ((pm['arredondamento'] ?? 'centavos').toString()) {
          'dezena90' => ReajusteArredondamento.dezena90,
          'final99' => ReajusteArredondamento.final99,
          _ => ReajusteArredondamento.centavos,
        },
        naoAlterarSeAbaixoDoCusto: pm['protegerAbaixoCusto'] != false,
        somenteAtivos: pm['somenteAtivos'] != false,
        margemMinimaPercentual:
            (pm['margemMinimaPercentual'] as num?)?.toDouble() ?? 5,
      );
      final linhas = linhasRaw.whereType<Map>().map((raw) {
        final m = Map<String, dynamic>.from(raw);
        return ReajustePrecoLinhaPreview(
          produtoId: (m['produtoId'] as num?)?.toInt() ?? 0,
          codigoInterno: (m['codigoInterno'] ?? '').toString(),
          nome: (m['nome'] ?? '').toString(),
          precoCusto: (m['precoCusto'] as num?)?.toDouble() ?? 0,
          custoBaseCalculo: (m['custoBaseCalculo'] as num?)?.toDouble() ?? 0,
          preco1Antes: (m['preco1Antes'] as num?)?.toDouble() ?? 0,
          preco2Antes: (m['preco2Antes'] as num?)?.toDouble() ?? 0,
          preco3Antes: (m['preco3Antes'] as num?)?.toDouble() ?? 0,
          preco1Depois: (m['preco1Depois'] as num?)?.toDouble() ?? 0,
          preco2Depois: (m['preco2Depois'] as num?)?.toDouble() ?? 0,
          preco3Depois: (m['preco3Depois'] as num?)?.toDouble() ?? 0,
          seraAlterado: m['seraAlterado'] == true,
          exigeAutorizacaoGerente: m['exigeAutorizacaoGerente'] == true,
          motivoIgnorado: m['motivoIgnorado']?.toString(),
          motivoAutorizacao: m['motivoAutorizacao']?.toString(),
        );
      }).toList();
      final repo = ReajustePrecoRepository(d.objectBox, d.produtoRepository);
      final resultado = repo.aplicarLote(
        parametros: parametros,
        linhas: linhas,
        usuario: usuario,
        motivo: (body['motivo'] ?? '').toString(),
      );
      d.notificar('produto');
      d.notificar('reajuste_preco');
      return lanApiJson({
        'ok': true,
        'produtosGravados': resultado.produtosGravados,
        'ignorados': resultado.ignorados,
        'reajustePrecoId': resultado.reajustePrecoId,
      });
    } catch (e) {
      return lanApiJson({'error': '$e'}, status: 400);
    }
  });

  router.post('/api/produtos/reajustes/<id|[0-9]+>/estornar', (
    Request r,
    String id,
  ) async {
    final body = await lanApiReadJsonMap(r) ?? <String, dynamic>{};
    final login = (body['usuarioLogin'] ?? '').toString().trim();
    if (login.isEmpty) {
      return lanApiJson({'error': 'usuarioLogin obrigatorio'}, status: 400);
    }
    UsuarioSistema? usuario;
    for (final u in await d.usuarioRepository.listarTodos()) {
      if (u.login.trim().toLowerCase() == login.toLowerCase()) {
        usuario = u;
        break;
      }
    }
    usuario ??= UsuarioSistema(
      id: login,
      login: login,
      nome: (body['usuarioNome'] ?? login).toString(),
      senha: '',
    );
    try {
      final repo = ReajustePrecoRepository(d.objectBox, d.produtoRepository);
      final resultado = repo.estornar(
        reajusteId: int.parse(id),
        usuario: usuario,
      );
      d.notificar('produto');
      d.notificar('reajuste_preco');
      return lanApiJson({
        'ok': true,
        'produtosGravados': resultado.produtosGravados,
        'ignorados': resultado.ignorados,
        'reajustePrecoId': resultado.reajustePrecoId,
      });
    } catch (e) {
      return lanApiJson({'error': '$e'}, status: 400);
    }
  });

  router.get('/api/estoque/lotes', (Request r) {
    try {
      final produtoId =
          lanApiQueryInt(r, 'produtoId', fallback: 0);
      final repo = LoteProdutoRepository(d.objectBox);
      final list = produtoId > 0
          ? repo.listarPorProduto(produtoId)
          : repo.listarTodos();
      return lanApiJson({
        'items': list
            .map(SyncEntityCodecOperacional.loteProdutoParaMap)
            .toList(),
      });
    } catch (e) {
      return lanApiJson({'error': '$e'}, status: 400);
    }
  });

  router.get('/api/estoque/lotes/contagem', (_) {
    try {
      final c = LoteProdutoRepository(d.objectBox).contarSemaforo();
      return lanApiJson({
        'verde': c.verde,
        'amarelo': c.amarelo,
        'laranja': c.laranja,
        'vermelho': c.vermelho,
        'semValidade': c.semValidade,
        'criticosOuVencidos': c.criticosOuVencidos,
      });
    } catch (e) {
      return lanApiJson({'error': '$e'}, status: 400);
    }
  });

  router.get('/api/estoque/lotes/fefo/<id|[0-9]+>', (Request _, String id) {
    try {
      final produtoId = int.parse(id);
      final produto = d.produtoRepository.obterPorId(produtoId);
      if (produto == null) {
        return lanApiJson({'error': 'produto nao encontrado'}, status: 404);
      }
      final fefo = LoteFefoService(LoteProdutoRepository(d.objectBox));
      final lote = fefo.loteFefoAtual(produto);
      return lanApiJson({
        'controlaLoteValidade': produto.controlaLoteValidade,
        'estoqueVendavel': fefo.estoqueDisponivelPdv(produto),
        'emBotaFora': fefo.loteFefoEmBotaFora(produto),
        'percentualBotaFora': fefo.percentualBotaForaEfetivo(produto),
        if (lote != null) ...{
          'loteId': lote.id,
          'numeroLote': lote.numeroLote,
          if (lote.dataValidade != null)
            'dataValidade': lote.dataValidade!.toUtc().toIso8601String(),
          'diasParaVencer': lote.diasParaVencer,
        },
      });
    } catch (e) {
      return lanApiJson({'error': '$e'}, status: 400);
    }
  });

  router.post('/api/estoque/lotes/<id|[0-9]+>/desativar', (
    Request _,
    String id,
  ) {
    try {
      final loteId = int.parse(id);
      final repo = LoteProdutoRepository(d.objectBox);
      final lote = repo.obterPorId(loteId);
      if (lote == null) {
        return lanApiJson({'error': 'lote nao encontrado'}, status: 404);
      }
      lote.ativo = false;
      repo.gravar(lote);
      d.notificar('lote_produto', ids: [loteId]);
      return lanApiJson({
        'ok': true,
        'item': SyncEntityCodecOperacional.loteProdutoParaMap(lote),
      });
    } catch (e) {
      return lanApiJson({'error': '$e'}, status: 400);
    }
  });
}
