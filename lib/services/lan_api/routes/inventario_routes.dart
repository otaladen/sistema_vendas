import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';

import '../../../data/inventario_repository.dart';
import '../../../data/sync/estoque_local_refresh_hub.dart';
import '../../../domain/inventario_codec.dart';
import '../../../domain/inventario_contagem.dart';
import '../lan_api_deps.dart';
import '../lan_api_json.dart';

void registerInventarioRoutes(Router router, LanApiDeps d) {
  InventarioRepository repo() => d.inventarioRepository;

  router.get('/api/estoque/inventario', (_) async {
    try {
      final items = await repo().listarSessoes();
      return lanApiJson({
        'items': items.map(InventarioCodec.sessaoParaMap).toList(),
      });
    } catch (e) {
      return lanApiJson({'error': '$e'}, status: 500);
    }
  });

  router.get('/api/estoque/inventario/categorias', (_) async {
    try {
      final info = await repo().obterCategorias();
      return lanApiJson(info.toMap());
    } catch (e) {
      return lanApiJson({'error': '$e'}, status: 500);
    }
  });

  router.get('/api/estoque/inventario/contagem-filtro', (Request r) async {
    try {
      final total = await repo().contarProdutosNoFiltro(
        categoria: (r.url.queryParameters['categoria'] ?? '').trim(),
        subcategoria: (r.url.queryParameters['subcategoria'] ?? '').trim(),
      );
      return lanApiJson({'total': total});
    } catch (e) {
      return lanApiJson({'error': '$e'}, status: 400);
    }
  });

  router.post('/api/estoque/inventario', (Request r) async {
    final body = await lanApiReadJsonMap(r);
    if (body == null) {
      return lanApiJson({'error': 'JSON invalido'}, status: 400);
    }
    final nome = (body['nome'] ?? '').toString().trim();
    if (nome.isEmpty) {
      return lanApiJson({'error': 'nome obrigatorio'}, status: 400);
    }
    try {
      final sessao = await repo().criarSessao(
        nome: nome,
        categoria: (body['categoria'] ?? body['filtroCategoria'] ?? '')
            .toString(),
        subcategoria:
            (body['subcategoria'] ?? body['filtroSubcategoria'] ?? '')
                .toString(),
        contagemCega: body['contagemCega'] == true,
        criadoPor: (body['criadoPor'] ?? body['usuarioLogin'] ?? '')
            .toString(),
      );
      return lanApiJson({
        'ok': true,
        'id': sessao.id,
        'sessao': InventarioCodec.sessaoParaMap(sessao),
      });
    } catch (e) {
      return lanApiJson({'error': '$e'}, status: 400);
    }
  });

  router.get(
    '/api/estoque/inventario/<id|[0-9]+>',
    (Request _, String id) async {
      final sessao = await repo().obterSessao(int.parse(id));
      if (sessao == null) {
        return lanApiJson({'error': 'sessao nao encontrada'}, status: 404);
      }
      return lanApiJson({'sessao': InventarioCodec.sessaoParaMap(sessao)});
    },
  );

  router.get(
    '/api/estoque/inventario/<id|[0-9]+>/itens',
    (Request r, String id) async {
      try {
        final items = await repo().listarItens(
          int.parse(id),
          filtro: (r.url.queryParameters['filtro'] ?? 'todos').trim(),
          busca: (r.url.queryParameters['q'] ??
                  r.url.queryParameters['busca'] ??
                  '')
              .trim(),
        );
        return lanApiJson({
          'items': items.map(InventarioCodec.itemParaMap).toList(),
        });
      } catch (e) {
        return lanApiJson({'error': '$e'}, status: 400);
      }
    },
  );

  router.post(
    '/api/estoque/inventario/<id|[0-9]+>/contar',
    (Request r, String id) async {
      final body = await lanApiReadJsonMap(r);
      if (body == null) {
        return lanApiJson({'error': 'JSON invalido'}, status: 400);
      }
      final sessaoId = int.parse(id);
      final itemId = (body['itemId'] as num?)?.toInt() ?? 0;
      if (itemId <= 0) {
        return lanApiJson({'error': 'itemId obrigatorio'}, status: 400);
      }
      try {
        final rpo = repo();
        var qtd = (body['quantidadeArmazenada'] as num?)?.toInt();
        if (qtd == null) {
          final exib = body['quantidadeExibicao'] ?? body['quantidade'];
          if (exib == null) {
            return lanApiJson(
              {'error': 'quantidadeArmazenada ou quantidadeExibicao obrigatoria'},
              status: 400,
            );
          }
          final itemAtual = rpo.obterItem(itemId);
          if (itemAtual == null || itemAtual.sessaoId != sessaoId) {
            return lanApiJson({'error': 'item nao encontrado'}, status: 404);
          }
          final ctx = InventarioContagem.contextoProduto(
            itemAtual,
            rpo.produtoDe(itemAtual),
          );
          qtd = InventarioContagem.parseQuantidade('$exib', ctx);
          if (qtd == null) {
            return lanApiJson(
              {'error': 'quantidade invalida para a escala do produto'},
              status: 400,
            );
          }
        }
        final item = await rpo.registrarContagem(
          sessaoId: sessaoId,
          itemId: itemId,
          quantidadeArmazenada: qtd,
          usuarioLogin: (body['usuarioLogin'] ?? body['usuarioId'] ?? '')
              .toString(),
        );
        final sessao = await rpo.obterSessao(sessaoId);
        return lanApiJson({
          'ok': true,
          'item': InventarioCodec.itemParaMap(item),
          if (sessao != null) 'sessao': InventarioCodec.sessaoParaMap(sessao),
        });
      } catch (e) {
        return lanApiJson({'error': '$e'}, status: 400);
      }
    },
  );

  router.post(
    '/api/estoque/inventario/<id|[0-9]+>/contagem-cega',
    (Request r, String id) async {
      final body = await lanApiReadJsonMap(r) ?? <String, dynamic>{};
      try {
        final sessao = await repo().definirContagemCega(
          sessaoId: int.parse(id),
          contagemCega: body['contagemCega'] == true,
        );
        return lanApiJson({
          'ok': true,
          'sessao': InventarioCodec.sessaoParaMap(sessao),
        });
      } catch (e) {
        return lanApiJson({'error': '$e'}, status: 400);
      }
    },
  );

  router.post(
    '/api/estoque/inventario/<id|[0-9]+>/aplicar',
    (Request r, String id) async {
      final body = await lanApiReadJsonMap(r) ?? <String, dynamic>{};
      try {
        final resultado = await repo().aplicarAjustes(
          sessaoId: int.parse(id),
          usuarioLogin: (body['usuarioLogin'] ?? body['usuarioId'] ?? '')
              .toString(),
        );
        EstoqueLocalRefreshHub.instance.notificar();
        d.notificar('produto');
        d.notificar('inventario', ids: [int.parse(id)]);
        return lanApiJson(resultado.toMap());
      } catch (e) {
        return lanApiJson({'error': '$e'}, status: 400);
      }
    },
  );

  router.post(
    '/api/estoque/inventario/<id|[0-9]+>/cancelar',
    (Request r, String id) async {
      final body = await lanApiReadJsonMap(r) ?? <String, dynamic>{};
      try {
        final sessao = await repo().cancelarSessao(
          sessaoId: int.parse(id),
          usuarioLogin: (body['usuarioLogin'] ?? body['usuarioId'] ?? '')
              .toString(),
        );
        d.notificar('inventario', ids: [sessao.id]);
        return lanApiJson({
          'ok': true,
          'apagada': true,
          'id': sessao.id,
          'sessao': InventarioCodec.sessaoParaMap(sessao),
        });
      } catch (e) {
        return lanApiJson({'error': '$e'}, status: 400);
      }
    },
  );
}
