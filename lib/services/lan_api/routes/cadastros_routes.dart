import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';

import '../../../data/produto_repository.dart';
import '../../../data/produto_sugestao_venda_repository.dart';
import '../../../data/sync/sync_entity_codec.dart';
import '../../../data/sync/sync_entity_codec_extras.dart';
import '../../../data/sync/sync_entity_codec_operacional.dart';
import '../../../domain/catalogo_produto_revision.dart';
import '../../../domain/produto_imagem_nome_arquivo.dart';
import '../../../model/kit_orcamento.dart';
import '../../../model/produto.dart';
import '../../../model/promocao.dart';
import '../../../model/promocao_combo_item.dart';
import '../../../model/promocao_item.dart';
import '../lan_api_deps.dart';
import '../lan_api_json.dart';

void registerCadastrosRoutes(Router router, LanApiDeps d) {
  router.get('/api/produtos/catalogo-meta', (_) {
    try {
      final count = d.produtoRepository.listarTodos().length;
      return lanApiJson(
        CatalogoProdutoRevision.paraMap(quantidadeProdutos: count),
      );
    } catch (e) {
      return lanApiJson({'error': '$e'}, status: 500);
    }
  });

  router.get('/api/produtos', (Request r) {
    final q = (r.url.queryParameters['q'] ?? '').trim();
    final limit = lanApiQueryInt(r, 'limit', fallback: 200);
    final offset = lanApiQueryInt(r, 'offset', fallback: 0);
    final somenteInativos =
        (r.url.queryParameters['somenteInativos'] ?? '').toLowerCase() ==
            'true' ||
        r.url.queryParameters['somenteInativos'] == '1';
    final ativosRaw = (r.url.queryParameters['somenteAtivos'] ?? '').trim();
    // Padrao PDV: so ativos. Cadastro: somenteAtivos=false.
    final somenteAtivos = somenteInativos
        ? false
        : ativosRaw.isEmpty ||
            (ativosRaw.toLowerCase() != 'false' && ativosRaw != '0');
    final List<Produto> items;
    if (q.isEmpty) {
      items = d.produtoRepository.listarPaginado(
        offset: offset,
        limit: limit,
        somenteAtivos: somenteAtivos,
        somenteInativos: somenteInativos,
      );
    } else {
      items = d.produtoRepository.pesquisar(
        q,
        offset: offset,
        somenteAtivos: somenteAtivos && !somenteInativos,
        somenteInativos: somenteInativos,
        limite: limit,
      );
    }
    return lanApiJson({
      'items': items.map(SyncEntityCodec.produtoParaMap).toList(),
    });
  });
  router.get('/api/produtos/proximo-sku', (Request r) {
    final ignorar = int.tryParse(r.url.queryParameters['ignorarId'] ?? '') ?? 0;
    final sku = d.produtoRepository.proximoSkuAutomatico(
      ignorarProdutoId: ignorar > 0 ? ignorar : null,
    );
    return lanApiJson({'ok': true, 'sku': sku});
  });
  router.get('/api/produtos/<id|[0-9]+>', (Request _, String id) {
    final item = d.produtoRepository.obterPorId(int.parse(id));
    return item == null
        ? lanApiJson({'error': 'nao encontrado'}, status: 404)
        : lanApiJson({'item': SyncEntityCodec.produtoParaMap(item)});
  });

  /// Historico de compras (NF-e) do produto — Terminal Leve / Kardex comercial.
  router.get('/api/produtos/<id|[0-9]+>/historico-entrada', (
    Request r,
    String id,
  ) {
    final produtoId = int.tryParse(id) ?? 0;
    if (produtoId <= 0) {
      return lanApiJson({'error': 'id invalido'}, status: 400);
    }
    final limit = lanApiQueryInt(r, 'limit', fallback: 100).clamp(1, 500);
    final items = d.produtoRepository
        .listarHistoricoEntradaPorProduto(produtoId)
        .take(limit)
        .toList();
    return lanApiJson({
      'items': items
          .map(SyncEntityCodecExtras.historicoEntradaParaMap)
          .toList(),
    });
  });

  router.get('/api/produtos/<id|[0-9]+>/sugestoes-venda', (
    Request _,
    String id,
  ) {
    final produtoId = int.tryParse(id) ?? 0;
    if (produtoId <= 0) {
      return lanApiJson({'error': 'id invalido'}, status: 400);
    }
    final repo = ProdutoSugestaoVendaRepository(d.objectBox);
    final items = repo.listarPorProdutoOrigem(produtoId, somenteAtivas: false);
    return lanApiJson({
      'items': items
          .map(SyncEntityCodecOperacional.produtoSugestaoVendaParaMap)
          .toList(),
    });
  });

  router.post('/api/produtos/<id|[0-9]+>/sugestoes-venda', (
    Request r,
    String id,
  ) async {
    final produtoId = int.tryParse(id) ?? 0;
    if (produtoId <= 0) {
      return lanApiJson({'error': 'id invalido'}, status: 400);
    }
    final body = await lanApiReadJsonMap(r);
    final raw = body?['items'];
    if (raw is! List) {
      return lanApiJson({'error': 'items obrigatorios'}, status: 400);
    }
    try {
      final sugestoes = raw.whereType<Map>().map((e) {
        final m = Map<String, dynamic>.from(e);
        return SyncEntityCodecOperacional.produtoSugestaoVendaDeMap({
          ...m,
          'produtoOrigemId': produtoId,
        });
      }).toList();
      ProdutoSugestaoVendaRepository(d.objectBox)
          .substituirDoProduto(produtoId, sugestoes);
      d.notificar('produto_sugestao_venda');
      return lanApiJson({'ok': true, 'id': produtoId, 'count': sugestoes.length});
    } catch (e) {
      return lanApiJson({'error': '$e'}, status: 400);
    }
  });

  /// JPEG/PNG do catalogo — usado pelo terminal leve na consulta PDV.
  router.get('/api/produtos/imagem/<fileName>', (Request _, String fileName) {
    final nome = Uri.decodeComponent(fileName).trim();
    if (!ProdutoImagemNomeArquivo.validoParaLan(nome)) {
      return lanApiJson({'error': 'nome de arquivo invalido'}, status: 400);
    }
    final dir = d.produtoRepository.productImagesDirPath.trim();
    if (dir.isEmpty) {
      return lanApiJson({'error': 'pasta de fotos indisponivel'}, status: 503);
    }
    final file = File(p.normalize(p.join(dir, nome)));
    final dirNorm = p.normalize(Directory(dir).absolute.path);
    if (!p.isWithin(dirNorm, p.normalize(file.absolute.path))) {
      return lanApiJson({'error': 'caminho invalido'}, status: 400);
    }
    if (!file.existsSync()) {
      return lanApiJson({'error': 'foto nao encontrada'}, status: 404);
    }
    final lower = nome.toLowerCase();
    final ct = lower.endsWith('.png')
        ? 'image/png'
        : lower.endsWith('.webp')
            ? 'image/webp'
            : 'image/jpeg';
    return Response.ok(
      file.readAsBytesSync(),
      headers: {
        'content-type': ct,
        'cache-control': 'private, max-age=86400',
      },
    );
  });

  /// Upload de foto do catalogo (Terminal Leve → PC1).
  router.post('/api/produtos/imagem', (Request r) async {
    final body = await lanApiReadJsonMap(r);
    final fileName = (body?['fileName'] ?? '').toString().trim();
    final b64 = (body?['contentBase64'] ?? '').toString().trim();
    if (!ProdutoImagemNomeArquivo.validoParaLan(fileName)) {
      return lanApiJson({'error': 'nome de arquivo invalido'}, status: 400);
    }
    if (b64.isEmpty) {
      return lanApiJson({'error': 'contentBase64 obrigatorio'}, status: 400);
    }
    final dir = d.produtoRepository.productImagesDirPath.trim();
    if (dir.isEmpty) {
      return lanApiJson({'error': 'pasta de fotos indisponivel'}, status: 503);
    }
    try {
      final bytes = base64Decode(b64);
      if (bytes.isEmpty) {
        return lanApiJson({'error': 'imagem vazia'}, status: 400);
      }
      await Directory(dir).create(recursive: true);
      final file = File(p.normalize(p.join(dir, fileName)));
      final dirNorm = p.normalize(Directory(dir).absolute.path);
      if (!p.isWithin(dirNorm, p.normalize(file.absolute.path))) {
        return lanApiJson({'error': 'caminho invalido'}, status: 400);
      }
      await file.writeAsBytes(bytes, flush: true);
      d.notificar('produto');
      return lanApiJson({'ok': true, 'fileName': fileName, 'path': fileName});
    } catch (e) {
      return lanApiJson({'error': '$e'}, status: 400);
    }
  });

  router.post('/api/produtos', (Request r) async {
    final body = await lanApiReadJsonMap(r);
    final raw = body?['produto'];
    if (raw is! Map) {
      return lanApiJson({'error': 'produto obrigatorio'}, status: 400);
    }
    try {
      final id = d.produtoRepository.salvar(
        SyncEntityCodec.produtoDeMap(Map<String, dynamic>.from(raw)),
      );
      d.notificar('produto', ids: id > 0 ? [id] : null);
      return lanApiJson({'ok': true, 'id': id});
    } on ProdutoSkuDuplicadoException catch (e) {
      return lanApiJson({
        'error': '$e',
        'code': 'sku_duplicado',
        'sku': e.sku,
        'produtoExistenteId': e.produtoExistenteId,
        'produtoExistenteNome': e.produtoExistenteNome,
      }, status: 409);
    } catch (e) {
      return lanApiJson({'error': '$e'}, status: 400);
    }
  });

  router.post('/api/produtos/<id|[0-9]+>/remover', (Request r, String id) async {
    try {
      final produtoId = int.parse(id);
      final ok = d.produtoRepository.remover(produtoId);
      if (!ok) {
        return lanApiJson({'error': 'produto nao encontrado'}, status: 404);
      }
      d.notificar('produto', ids: [produtoId]);
      return lanApiJson({'ok': true, 'id': produtoId});
    } catch (e) {
      return lanApiJson({'error': '$e'}, status: 400);
    }
  });

  router.get('/api/clientes', (Request r) {
    final q = (r.url.queryParameters['q'] ?? '').trim();
    final limit = lanApiQueryInt(r, 'limit', fallback: 100);
    final items = q.isEmpty
        ? d.clienteRepository.listarPaginado(limit: limit)
        : d.clienteRepository.pesquisar(q).take(limit).toList();
    return lanApiJson({
      'items': items.map(SyncEntityCodec.clienteParaMap).toList(),
    });
  });
  router.get('/api/clientes/<id|[0-9]+>', (Request _, String id) {
    final item = d.clienteRepository.obterPorId(int.parse(id));
    return item == null
        ? lanApiJson({'error': 'nao encontrado'}, status: 404)
        : lanApiJson({'item': SyncEntityCodec.clienteParaMap(item)});
  });
  router.post('/api/clientes', (Request r) async {
    final body = await lanApiReadJsonMap(r);
    final raw = body?['cliente'];
    if (raw is! Map) {
      return lanApiJson({'error': 'cliente obrigatorio'}, status: 400);
    }
    try {
      final id = d.clienteRepository.salvar(
        SyncEntityCodec.clienteDeMap(Map<String, dynamic>.from(raw)),
      );
      d.notificar('cliente');
      return lanApiJson({'ok': true, 'id': id});
    } catch (e) {
      return lanApiJson({'error': '$e'}, status: 400);
    }
  });
  router.post('/api/clientes/<id|[0-9]+>/remover', (Request r, String id) async {
    try {
      final clienteId = int.parse(id);
      final cliente = d.clienteRepository.obterPorId(clienteId);
      if (cliente == null) {
        return lanApiJson({'error': 'cliente nao encontrado'}, status: 404);
      }
      final saldo = d.vendaRepository.saldoFiadoEmAbertoCliente(clienteId);
      if (saldo > 0.001) {
        return lanApiJson({
          'error':
              'Cliente possui titulos em aberto (saldo R\$ ${saldo.toStringAsFixed(2).replaceAll('.', ',')}). Quite o fiado antes de excluir.',
        }, status: 409);
      }
      final ok = d.clienteRepository.remover(clienteId);
      if (!ok) {
        return lanApiJson({'error': 'nao foi possivel excluir o cliente'}, status: 400);
      }
      d.notificar('cliente');
      return lanApiJson({'ok': true, 'id': clienteId});
    } catch (e) {
      return lanApiJson({'error': '$e'}, status: 400);
    }
  });

  router.get('/api/fornecedores', (Request r) {
    final q = (r.url.queryParameters['q'] ?? '').trim();
    final limit = lanApiQueryInt(r, 'limit', fallback: 200);
    final apenasAtivos =
        (r.url.queryParameters['apenasAtivos'] ?? '').toLowerCase() == 'true' ||
            r.url.queryParameters['apenasAtivos'] == '1';
    final items = q.isEmpty
        ? d.fornecedorRepository.listarTodos(apenasAtivos: apenasAtivos)
        : d.fornecedorRepository
            .pesquisar(q, apenasAtivos: apenasAtivos)
            .take(limit)
            .toList();
    final limited =
        q.isEmpty ? items.take(limit).toList() : items;
    return lanApiJson({
      'items': limited
          .map(SyncEntityCodecExtras.fornecedorNfeParaMap)
          .toList(),
    });
  });
  router.get('/api/fornecedores/<id|[0-9]+>', (Request _, String id) {
    final item = d.fornecedorRepository.obterPorId(int.parse(id));
    return item == null
        ? lanApiJson({'error': 'nao encontrado'}, status: 404)
        : lanApiJson({
            'item': SyncEntityCodecExtras.fornecedorNfeParaMap(item),
          });
  });
  router.post('/api/fornecedores', (Request r) async {
    final body = await lanApiReadJsonMap(r);
    final raw = body?['fornecedor'];
    if (raw is! Map) {
      return lanApiJson({'error': 'fornecedor obrigatorio'}, status: 400);
    }
    try {
      final id = d.fornecedorRepository.salvar(
        SyncEntityCodecExtras.fornecedorNfeDeMap(
          Map<String, dynamic>.from(raw),
        ),
      );
      d.notificar('fornecedor_nfe', ids: [id]);
      return lanApiJson({'ok': true, 'id': id});
    } catch (e) {
      return lanApiJson({'error': '$e'}, status: 400);
    }
  });
  router.post('/api/fornecedores/<id|[0-9]+>/remover', (Request r, String id) async {
    try {
      final fornecedorId = int.parse(id);
      final existente = d.fornecedorRepository.obterPorId(fornecedorId);
      if (existente == null) {
        return lanApiJson({'error': 'fornecedor nao encontrado'}, status: 404);
      }
      final ok = d.fornecedorRepository.remover(fornecedorId);
      if (!ok) {
        return lanApiJson({'error': 'nao foi possivel excluir'}, status: 400);
      }
      d.notificar('fornecedor_nfe', ids: [fornecedorId]);
      return lanApiJson({'ok': true, 'id': fornecedorId});
    } catch (e) {
      return lanApiJson({'error': '$e'}, status: 400);
    }
  });

  router.get(
    '/api/vendedores',
    (_) => lanApiJson({
      'items': d.vendedorRepository
          .listarTodos()
          .map(SyncEntityCodec.vendedorParaMap)
          .toList(),
    }),
  );
  router.get('/api/vendedores/<id|[0-9]+>', (Request _, String id) {
    final item = d.vendedorRepository.obterPorId(int.parse(id));
    return item == null
        ? lanApiJson({'error': 'nao encontrado'}, status: 404)
        : lanApiJson({'item': SyncEntityCodec.vendedorParaMap(item)});
  });
  router.post('/api/vendedores/autenticar-pin', (Request r) async {
    final body = await lanApiReadJsonMap(r);
    final pin = (body?['pin'] ?? body?['senha'] ?? '').toString().trim();
    if (pin.isEmpty) {
      return lanApiJson({'ok': false, 'error': 'pin obrigatorio'}, status: 400);
    }
    final vendedor = d.vendedorRepository.autenticarPorSenhaPdv(pin);
    if (vendedor == null) {
      // 200 + ok:false (nao usar 401 — conflita com recusa de token da API).
      return lanApiJson({
        'ok': false,
        'error': 'PIN invalido ou ambiguo',
      });
    }
    return lanApiJson({
      'ok': true,
      'vendedor': SyncEntityCodec.vendedorParaMap(vendedor),
    });
  });
  router.post('/api/vendedores', (Request r) async {
    final body = await lanApiReadJsonMap(r);
    final raw = body?['vendedor'];
    if (raw is! Map) {
      return lanApiJson({'error': 'vendedor obrigatorio'}, status: 400);
    }
    try {
      final id = d.vendedorRepository.salvar(
        SyncEntityCodec.vendedorDeMap(Map<String, dynamic>.from(raw)),
      );
      d.notificar('vendedor');
      return lanApiJson({'ok': true, 'id': id});
    } catch (e) {
      return lanApiJson({'error': '$e'}, status: 400);
    }
  });
  router.post('/api/vendedores/<id|[0-9]+>/remover', (Request r, String id) async {
    try {
      final vendedorId = int.parse(id);
      final vendas =
          d.vendaRepository.contarVendasFinalizadasPorVendedor(vendedorId);
      if (vendas > 0) {
        return lanApiJson({
          'error':
              'Nao e possivel remover: vendedor tem $vendas venda(s) finalizada(s). Desative o cadastro em vez de apagar.',
        }, status: 409);
      }
      final ok = d.vendedorRepository.remover(vendedorId);
      if (!ok) {
        return lanApiJson({'error': 'vendedor nao encontrado'}, status: 404);
      }
      d.notificar('vendedor');
      return lanApiJson({'ok': true, 'id': vendedorId});
    } catch (e) {
      return lanApiJson({'error': '$e'}, status: 400);
    }
  });

  router.get(
    '/api/motoristas',
    (_) => lanApiJson({
      'items': d.motoristaRepository
          .listarTodos()
          .map(SyncEntityCodecExtras.motoristaParaMap)
          .toList(),
    }),
  );
  router.get('/api/motoristas/<id|[0-9]+>', (Request _, String id) {
    final item = d.motoristaRepository.obterPorId(int.parse(id));
    return item == null
        ? lanApiJson({'error': 'nao encontrado'}, status: 404)
        : lanApiJson({'item': SyncEntityCodecExtras.motoristaParaMap(item)});
  });
  Future<Response> salvarMotoristaHandler(Request r) async {
    final body = await lanApiReadJsonMap(r);
    final raw = body?['motorista'];
    if (raw is! Map) {
      return lanApiJson({'error': 'motorista obrigatorio'}, status: 400);
    }
    try {
      final id = d.motoristaRepository.salvar(
        SyncEntityCodecExtras.motoristaDeMap(Map<String, dynamic>.from(raw)),
      );
      d.notificar('motorista');
      return lanApiJson({'ok': true, 'id': id});
    } catch (e) {
      return lanApiJson({'error': '$e'}, status: 400);
    }
  }

  router.post('/api/motoristas/salvar', salvarMotoristaHandler);
  router.post('/api/motoristas', salvarMotoristaHandler);
  router.post('/api/motoristas/<id|[0-9]+>/remover', (Request r, String id) async {
    try {
      final motoristaId = int.parse(id);
      final motorista = d.motoristaRepository.obterPorId(motoristaId);
      if (motorista == null) {
        return lanApiJson({'error': 'motorista nao encontrado'}, status: 404);
      }
      for (final f in d.funcionarioRepository.listarTodos()) {
        if (f.motoristaId == motoristaId) {
          return lanApiJson({
            'error':
                'Nao e possivel remover: motorista vinculado ao funcionario '
                '"${f.nomeCompleto}". Desvincule em Cadastros > Funcionarios '
                'ou desative o motorista.',
          }, status: 409);
        }
      }
      final ok = d.motoristaRepository.remover(motoristaId);
      if (!ok) {
        return lanApiJson({'error': 'nao foi possivel excluir'}, status: 400);
      }
      d.notificar('motorista');
      return lanApiJson({'ok': true, 'id': motoristaId});
    } catch (e) {
      return lanApiJson({'error': '$e'}, status: 400);
    }
  });

  router.get(
    '/api/funcionarios',
    (_) => lanApiJson({
      'items': d.funcionarioRepository
          .listarTodos()
          .map(SyncEntityCodecExtras.funcionarioParaMap)
          .toList(),
    }),
  );
  router.get('/api/funcionarios/<id|[0-9]+>', (Request _, String id) {
    final item = d.funcionarioRepository.obterPorId(int.parse(id));
    return item == null
        ? lanApiJson({'error': 'nao encontrado'}, status: 404)
        : lanApiJson({'item': SyncEntityCodecExtras.funcionarioParaMap(item)});
  });
  Future<Response> salvarFuncionarioHandler(Request r) async {
    final body = await lanApiReadJsonMap(r);
    final raw = body?['funcionario'];
    if (raw is! Map) {
      return lanApiJson({'error': 'funcionario obrigatorio'}, status: 400);
    }
    try {
      final id = d.funcionarioRepository.salvar(
        SyncEntityCodecExtras.funcionarioDeMap(Map<String, dynamic>.from(raw)),
      );
      d.notificar('funcionario');
      return lanApiJson({'ok': true, 'id': id});
    } catch (e) {
      return lanApiJson({'error': '$e'}, status: 400);
    }
  }

  // Padrao Usuarios/Vendedores: /salvar. Mantem POST /api/funcionarios (legado).
  router.post('/api/funcionarios/salvar', salvarFuncionarioHandler);
  router.post('/api/funcionarios', salvarFuncionarioHandler);
  router.post(
      '/api/funcionarios/<id|[0-9]+>/remover', (Request r, String id) async {
    try {
      final funcionarioId = int.parse(id);
      final f = d.funcionarioRepository.obterPorId(funcionarioId);
      if (f == null) {
        return lanApiJson({'error': 'funcionario nao encontrado'}, status: 404);
      }
      if (f.vendedorId > 0) {
        final vendas = d.vendaRepository
            .contarVendasFinalizadasPorVendedor(f.vendedorId);
        if (vendas > 0) {
          return lanApiJson({
            'error':
                'Nao e possivel remover: vendedor vinculado tem $vendas venda(s) no PDV. Desative o funcionario em vez de apagar.',
          }, status: 409);
        }
      }
      final ok = d.funcionarioRepository.remover(funcionarioId);
      if (!ok) {
        return lanApiJson({'error': 'nao foi possivel excluir'}, status: 400);
      }
      d.notificar('funcionario');
      return lanApiJson({'ok': true, 'id': funcionarioId});
    } catch (e) {
      return lanApiJson({'error': '$e'}, status: 400);
    }
  });

  router.get('/api/lancamentos-rh', (Request r) {
    final funcionarioId = lanApiQueryInt(r, 'funcionarioId');
    if (funcionarioId > 0) {
      return lanApiJson({
        'items': d.funcionarioRepository.lancamentos
            .listarPorFuncionario(funcionarioId)
            .map(SyncEntityCodecExtras.lancamentoFuncionarioParaMap)
            .toList(),
      });
    }
    // Sem filtro: lista geral (bootstrap do terminal leve).
    final todos = <Map<String, dynamic>>[];
    for (final f in d.funcionarioRepository.listarTodos()) {
      for (final l
          in d.funcionarioRepository.lancamentos.listarPorFuncionario(f.id)) {
        todos.add(SyncEntityCodecExtras.lancamentoFuncionarioParaMap(l));
      }
    }
    return lanApiJson({'items': todos});
  });
  router.post('/api/lancamentos-rh', (Request r) async {
    final body = await lanApiReadJsonMap(r);
    final raw = body?['lancamento'];
    var funcionarioId = (body?['funcionarioId'] as num?)?.toInt() ?? 0;
    if (funcionarioId <= 0 && raw is Map) {
      funcionarioId = (raw['funcionarioId'] as num?)?.toInt() ?? 0;
    }
    if (raw is! Map || funcionarioId <= 0) {
      return lanApiJson({
        'error': 'funcionarioId e lancamento obrigatorios',
      }, status: 400);
    }
    try {
      final id = d.funcionarioRepository.lancamentos.salvar(
        SyncEntityCodecExtras.lancamentoFuncionarioDeMap(
          Map<String, dynamic>.from(raw),
        ),
        funcionarioId,
      );
      d.notificar('lancamento_funcionario');
      return lanApiJson({'ok': true, 'id': id});
    } catch (e) {
      return lanApiJson({'error': '$e'}, status: 400);
    }
  });
  router.post(
    '/api/lancamentos-rh/<id|[0-9]+>/estornar',
    (Request r, String id) async {
      try {
        final lancId = int.parse(id);
        final existente = d.funcionarioRepository.lancamentos.obterPorId(lancId);
        if (existente == null) {
          return lanApiJson({'error': 'lancamento nao encontrado'}, status: 404);
        }
        d.funcionarioRepository.lancamentos.estornar(lancId);
        d.notificar('lancamento_funcionario');
        return lanApiJson({'ok': true, 'id': lancId});
      } catch (e) {
        return lanApiJson({'error': '$e'}, status: 400);
      }
    },
  );
  router.get('/api/fechamentos-rh', (Request r) {
    final funcionarioId = lanApiQueryInt(r, 'funcionarioId');
    final items = funcionarioId > 0
        ? d.funcionarioRepository.fechamentos.listarPorFuncionario(
            funcionarioId,
          )
        : d.funcionarioRepository.fechamentos.listarPorMes(
            lanApiQueryDate(r, 'mes') ?? DateTime.now(),
          );
    return lanApiJson({
      'items': items.map(SyncEntityCodecExtras.fechamentoRhParaMap).toList(),
    });
  });
  router.post('/api/fechamentos-rh', (Request r) async {
    final body = await lanApiReadJsonMap(r);
    final raw = body?['fechamento'];
    if (raw is! Map) {
      return lanApiJson({'error': 'fechamento obrigatorio'}, status: 400);
    }
    try {
      final id = d.funcionarioRepository.fechamentos.salvar(
        SyncEntityCodecExtras.fechamentoRhDeMap(Map<String, dynamic>.from(raw)),
      );
      d.notificar('fechamento_rh_funcionario');
      return lanApiJson({'ok': true, 'id': id});
    } catch (e) {
      return lanApiJson({'error': '$e'}, status: 400);
    }
  });

  router.get(
    '/api/kits',
    (_) => lanApiJson({
      'items': d.kitOrcamentoRepository
          .listarPorNome()
          .map(SyncEntityCodecExtras.kitParaMap)
          .toList(),
    }),
  );
  router.get('/api/kits/<id|[0-9]+>', (Request _, String id) {
    final item = d.kitOrcamentoRepository.obterPorId(int.parse(id));
    return item == null
        ? lanApiJson({'error': 'nao encontrado'}, status: 404)
        : lanApiJson({'item': SyncEntityCodecExtras.kitParaMap(item)});
  });
  Future<Response> salvarKitHandler(Request r) async {
    final body = await lanApiReadJsonMap(r);
    final rawKit = body?['kit'];
    final rawItens = body?['itens'];
    if (rawKit is! Map || rawItens is! List) {
      return lanApiJson({'error': 'kit e itens obrigatorios'}, status: 400);
    }
    try {
      final km = Map<String, dynamic>.from(rawKit);
      final kit = KitOrcamento(
        id: (km['id'] as num?)?.toInt() ?? 0,
        nome: (km['nome'] ?? '').toString(),
        descricao: (km['descricao'] ?? '').toString(),
        ativo: km['ativo'] != false,
        criadoEm: DateTime.tryParse((km['criadoEm'] ?? '').toString())?.toUtc(),
      );
      final itens = rawItens.whereType<Map>().map((raw) {
        final m = Map<String, dynamic>.from(raw);
        final item = KitOrcamentoItem(
          quantidade: (m['quantidade'] as num?)?.toInt() ?? 0,
          ordem: (m['ordem'] as num?)?.toInt() ?? 0,
        );
        item.produto.targetId = (m['produtoId'] as num?)?.toInt() ?? 0;
        return item;
      }).toList();
      d.kitOrcamentoRepository.salvar(kit, itens);
      d.notificar('kit_orcamento');
      return lanApiJson({'ok': true, 'id': kit.id});
    } catch (e) {
      return lanApiJson({'error': '$e'}, status: 400);
    }
  }

  router.post('/api/kits/salvar', salvarKitHandler);
  router.post('/api/kits', salvarKitHandler);

  router.post('/api/kits/<id|[0-9]+>/remover', (Request r, String id) async {
    final kitId = int.tryParse(id) ?? 0;
    if (kitId <= 0) {
      return lanApiJson({'error': 'id invalido'}, status: 400);
    }
    try {
      final existente = d.kitOrcamentoRepository.obterPorId(kitId);
      if (existente == null) {
        return lanApiJson({'error': 'kit nao encontrado'}, status: 404);
      }
      d.kitOrcamentoRepository.remover(kitId);
      d.notificar('kit_orcamento');
      return lanApiJson({'ok': true, 'id': kitId});
    } catch (e) {
      return lanApiJson({'error': '$e'}, status: 400);
    }
  });

  router.get(
    '/api/promocoes',
    (_) => lanApiJson({
      'items': d.promocaoRepository
          .listarPorNome()
          .map(SyncEntityCodecExtras.promocaoParaMap)
          .toList(),
    }),
  );
  router.get('/api/promocoes/<id|[0-9]+>', (Request _, String id) {
    final item = d.promocaoRepository.obterPorId(int.parse(id));
    return item == null
        ? lanApiJson({'error': 'nao encontrado'}, status: 404)
        : lanApiJson({'item': SyncEntityCodecExtras.promocaoParaMap(item)});
  });
  Future<Response> salvarPromocaoHandler(Request r) async {
    final body = await lanApiReadJsonMap(r);
    final rawPromo = body?['promocao'];
    if (rawPromo is! Map) {
      return lanApiJson({'error': 'promocao obrigatoria'}, status: 400);
    }
    try {
      final m = Map<String, dynamic>.from(rawPromo);
      final promo = Promocao(
        id: (m['id'] as num?)?.toInt() ?? 0,
        nome: (m['nome'] ?? '').toString(),
        descricao: (m['descricao'] ?? '').toString(),
        dataInicio:
            DateTime.tryParse((m['dataInicio'] ?? '').toString())?.toUtc() ??
            DateTime.now().toUtc(),
        dataFim:
            DateTime.tryParse((m['dataFim'] ?? '').toString())?.toUtc() ??
            DateTime.now().toUtc(),
        ativa: m['ativa'] != false,
        prioridade: (m['prioridade'] as num?)?.toInt() ?? 0,
        tipoRegra: (m['tipoRegra'] ?? 'preco_fixo').toString(),
        valorRegra: (m['valorRegra'] as num?)?.toDouble() ?? 0,
        segmentoCliente: (m['segmentoCliente'] ?? '').toString(),
        tipoCampanha: (m['tipoCampanha'] ?? 'produto').toString(),
        margemMinimaPercentual:
            (m['margemMinimaPercentual'] as num?)?.toDouble() ?? 0,
        limiteQuantidadeTotal:
            (m['limiteQuantidadeTotal'] as num?)?.toInt() ?? 0,
        quantidadeVendidaPromo:
            (m['quantidadeVendidaPromo'] as num?)?.toInt() ?? 0,
        leveQuantidade: (m['leveQuantidade'] as num?)?.toInt() ?? 0,
        pagueQuantidade: (m['pagueQuantidade'] as num?)?.toInt() ?? 0,
        precoCombo: (m['precoCombo'] as num?)?.toDouble() ?? 0,
        criadoEm: DateTime.tryParse((m['criadoEm'] ?? '').toString())?.toUtc(),
      );
      final itens = (body?['itens'] as List? ?? const []).whereType<Map>().map((
        raw,
      ) {
        final i = Map<String, dynamic>.from(raw);
        return PromocaoItem(
          produtoAlvoId: (i['produtoAlvoId'] as num?)?.toInt() ?? 0,
          categoria: (i['categoria'] ?? '').toString(),
          subcategoria: (i['subcategoria'] ?? '').toString(),
          quantidadeMinima: (i['quantidadeMinima'] as num?)?.toInt() ?? 1,
          quantidadeMaximaPromo:
              (i['quantidadeMaximaPromo'] as num?)?.toInt() ?? 0,
        );
      }).toList();
      final comboItens = (body?['comboItens'] as List? ?? const [])
          .whereType<Map>()
          .map((raw) {
            final i = Map<String, dynamic>.from(raw);
            return PromocaoComboItem(
              produtoAlvoId: (i['produtoAlvoId'] as num?)?.toInt() ?? 0,
              quantidade: (i['quantidade'] as num?)?.toInt() ?? 1,
            );
          })
          .toList();
      d.promocaoRepository.salvar(promo, itens, comboItens: comboItens);
      d.notificar('promocao');
      return lanApiJson({'ok': true, 'id': promo.id});
    } catch (e) {
      return lanApiJson({'error': '$e'}, status: 400);
    }
  }

  router.post('/api/promocoes/salvar', salvarPromocaoHandler);
  router.post('/api/promocoes', salvarPromocaoHandler);

  router.post('/api/promocoes/<id|[0-9]+>/status', (Request r, String id) async {
    final body = await lanApiReadJsonMap(r) ?? <String, dynamic>{};
    final promoId = int.tryParse(id) ?? 0;
    if (promoId <= 0) {
      return lanApiJson({'error': 'id invalido'}, status: 400);
    }
    try {
      final ativa = body['ativa'];
      final p = d.promocaoRepository.alterarStatus(
        promoId,
        ativa: ativa is bool ? ativa : null,
      );
      if (p == null) {
        return lanApiJson({'error': 'promocao nao encontrada'}, status: 404);
      }
      d.notificar('promocao');
      return lanApiJson({
        'ok': true,
        'id': p.id,
        'ativa': p.ativa,
        'promocao': SyncEntityCodecExtras.promocaoParaMap(p),
      });
    } catch (e) {
      return lanApiJson({'error': '$e'}, status: 400);
    }
  });

  router.post('/api/promocoes/<id|[0-9]+>/desativar', (
    Request r,
    String id,
  ) async {
    final promoId = int.tryParse(id) ?? 0;
    if (promoId <= 0) {
      return lanApiJson({'error': 'id invalido'}, status: 400);
    }
    try {
      final p = d.promocaoRepository.alterarStatus(promoId, ativa: false);
      if (p == null) {
        return lanApiJson({'error': 'promocao nao encontrada'}, status: 404);
      }
      d.notificar('promocao');
      return lanApiJson({'ok': true, 'id': p.id, 'ativa': p.ativa});
    } catch (e) {
      return lanApiJson({'error': '$e'}, status: 400);
    }
  });

  router.post('/api/promocoes/<id|[0-9]+>/remover', (
    Request r,
    String id,
  ) async {
    final promoId = int.tryParse(id) ?? 0;
    if (promoId <= 0) {
      return lanApiJson({'error': 'id invalido'}, status: 400);
    }
    try {
      final existente = d.promocaoRepository.obterPorId(promoId);
      if (existente == null) {
        return lanApiJson({'error': 'promocao nao encontrada'}, status: 404);
      }
      d.promocaoRepository.excluir(promoId);
      d.notificar('promocao');
      return lanApiJson({'ok': true, 'id': promoId});
    } catch (e) {
      return lanApiJson({'error': '$e'}, status: 400);
    }
  });
}
