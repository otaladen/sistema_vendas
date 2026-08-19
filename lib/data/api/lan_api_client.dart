import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:web_socket_channel/web_socket_channel.dart';

import '../../model/cliente.dart';
import '../../model/fornecedor_nfe.dart';
import '../../model/item_venda.dart';
import '../../model/mensagem_interna.dart';
import '../../model/produto.dart';
import '../../model/venda.dart';
import '../../model/vendedor.dart';
import '../../domain/entregas/agenda_carreto_ocupacao.dart';
import '../../domain/pagamento_orcamento.dart';
import '../../domain/venda_relacao_safe.dart';
import '../sync/sync_auth.dart';
import '../sync/sync_entity_codec.dart';
import '../sync/sync_entity_codec_extras.dart';
import '../venda_repository.dart';
import 'lan_api_parse_isolate.dart';

/// Erro tipado da LAN API (rede, timeout ou JSON invalido).
class LanApiException implements Exception {
  LanApiException(
    this.message, {
    this.cause,
    this.code,
    this.details,
  });

  final String message;
  final Object? cause;
  /// Codigo estruturado da API (ex.: [sku_duplicado]).
  final String? code;
  final Map<String, dynamic>? details;

  @override
  String toString() => message;
}

/// Cliente HTTP/WS da API de negocio do PC Servidor (`/api/*`).
class LanApiClient {
  LanApiClient({
    required String baseUrl,
    this.syncToken = '',
  }) : _base = _norm(baseUrl);

  final String _base;
  final String syncToken;

  static String _norm(String raw) {
    var s = raw.trim();
    if (s.isEmpty) return '';
    if (!s.contains('://')) s = 'http://$s';
    while (s.endsWith('/')) {
      s = s.substring(0, s.length - 1);
    }
    return s;
  }

  bool get configurado => _base.isNotEmpty;

  Uri _uri(String path, [Map<String, String>? q]) {
    final p = path.startsWith('/') ? path : '/$path';
    return Uri.parse('$_base$p').replace(queryParameters: q);
  }

  Map<String, String> _headers({bool json = true}) {
    final h = <String, String>{};
    if (json) h['content-type'] = 'application/json';
    // Sempre injeta o token configurado (servidor exige em /api/*).
    final t = syncToken.trim();
    if (t.isNotEmpty) h[SyncAuth.headerName] = t;
    return h;
  }

  /// Timeouts mais generosos para 4G / Tailscale (oscilacao de rede).
  /// [timeoutHealth] ≈ connect; leitura/escrita ≈ receive.
  static const Duration timeoutLeitura = Duration(seconds: 10);
  static const Duration timeoutEscrita = Duration(seconds: 10);
  /// Baixa do motorista: Tailscale/4G oscila; nao trava a rota.
  static const Duration timeoutBaixaMotorista = Duration(seconds: 5);
  /// JPEG do POD pela LAN (:8788).
  static const Duration timeoutPodFoto = Duration(seconds: 30);
  /// Finalizacao de venda / pagamento no PDV (evita falso erro durante SEFAZ).
  static const Duration timeoutFinalizacao = Duration(seconds: 15);
  static const Duration timeoutHealth = Duration(seconds: 8);
  static const Duration timeoutFiscal = Duration(seconds: 120);
  static const Duration timeoutFechamento = Duration(minutes: 5);
  /// Backup completo do banco no PC servidor + download do ZIP.
  static const Duration timeoutBackup = Duration(minutes: 10);

  /// Mensagem amigavel para falha de rede no celular (Tailscale / 4G).
  static const msgRedeInstavelMotorista =
      'Sinal instavel. Verifique se o Tailscale esta ativo e tente novamente.';

  Never _rethrowRede(
    Object e,
    String path,
    String verbo, {
    bool sinalizarRede = true,
  }) {
    if (e is LanApiException) {
      if (sinalizarRede) _sinalizarOfflineSeRede(e.cause);
      throw e;
    }
    if (e is TimeoutException) {
      if (sinalizarRede) _sinalizarOfflineSeRede(e);
      throw LanApiException(
        'API $verbo $path: tempo esgotado. '
        'Verifique Wi-Fi/Tailscale e se o PC servidor esta ligado.',
        cause: e,
      );
    }
    if (e is SocketException) {
      if (sinalizarRede) _sinalizarOfflineSeRede(e);
      throw LanApiException(
        'API $verbo $path: sem conexao com o PC servidor (${e.message}). '
        'No celular: confirme o Tailscale ativo.',
        cause: e,
      );
    }
    if (e is FormatException) {
      throw LanApiException(
        'API $verbo $path: resposta JSON invalida.',
        cause: e,
      );
    }
    if (e is http.ClientException) {
      if (sinalizarRede) _sinalizarOfflineSeRede(e);
      throw LanApiException(
        'API $verbo $path: falha de rede (${e.message}).',
        cause: e,
      );
    }
    throw LanApiException('API $verbo $path: $e', cause: e);
  }

  void _sinalizarOfflineSeRede(Object? cause) {
    if (cause is SocketException ||
        cause is TimeoutException ||
        cause is http.ClientException) {
      onFalhaRede?.call();
    }
  }

  /// Notifica UI (ex.: [LanApiEventHub]) quando a rede cai / volta.
  void Function()? onFalhaRede;
  void Function()? onSucessoRede;

  Future<Map<String, dynamic>> _getJson(
    String path, {
    Map<String, String>? query,
    Duration? timeout,
  }) async {
    try {
      final r = await http
          .get(_uri(path, query), headers: _headers())
          .timeout(timeout ?? timeoutLeitura);
      if (r.statusCode == 401 || r.statusCode == 403) {
        throw LanApiException('API recusou o token (HTTP ${r.statusCode}).');
      }
      if (r.statusCode != 200) {
        throw LanApiException(
          'API GET $path HTTP ${r.statusCode}: ${r.body}',
        );
      }
      final d = jsonDecode(r.body);
      if (d is! Map) {
        throw LanApiException('Resposta invalida em $path');
      }
      onSucessoRede?.call();
      return Map<String, dynamic>.from(d);
    } catch (e) {
      _rethrowRede(e, path, 'GET');
    }
  }

  Future<Map<String, dynamic>> _postJson(
    String path,
    Map<String, dynamic> body, {
    Duration? timeout,
    bool aceitarErroJson = false,
    Map<String, String>? extraHeaders,
    bool sinalizarStatusRede = true,
  }) async {
    try {
      final r = await http
          .post(
            _uri(path),
            headers: {
              ..._headers(),
              if (extraHeaders != null) ...extraHeaders,
            },
            body: jsonEncode(body),
          )
          .timeout(timeout ?? timeoutEscrita);
      if (r.statusCode == 401 || r.statusCode == 403) {
        throw LanApiException('API recusou o token (HTTP ${r.statusCode}).');
      }
      if (r.statusCode < 200 || r.statusCode >= 300) {
        if (aceitarErroJson && r.body.trim().isNotEmpty) {
          try {
            final d = jsonDecode(r.body);
            if (d is Map) {
              onSucessoRede?.call();
              return Map<String, dynamic>.from(d);
            }
          } catch (_) {}
        }
        var detalhe = r.body;
        String? code;
        Map<String, dynamic>? details;
        try {
          final d = jsonDecode(r.body);
          if (d is Map) {
            details = Map<String, dynamic>.from(d);
            if (d['error'] != null) {
              detalhe = d['error'].toString();
            }
            final c = d['code']?.toString().trim();
            if (c != null && c.isNotEmpty) code = c;
          }
        } catch (_) {}
        throw LanApiException(detalhe, code: code, details: details);
      }
      if (r.body.trim().isEmpty) {
        onSucessoRede?.call();
        return {'ok': true};
      }
      final d = jsonDecode(r.body);
      if (d is! Map) {
        onSucessoRede?.call();
        return {'ok': true};
      }
      onSucessoRede?.call();
      return Map<String, dynamic>.from(d);
    } catch (e) {
      _rethrowRede(e, path, 'POST', sinalizarRede: sinalizarStatusRede);
    }
  }

  Future<({List<int> bytes, String? filename})> _getBytes(
    String path, {
    Map<String, String>? query,
    Duration? timeout,
  }) async {
    try {
      final r = await http
          .get(_uri(path, query), headers: _headers(json: false))
          .timeout(timeout ?? timeoutFechamento);
      if (r.statusCode == 401 || r.statusCode == 403) {
        throw LanApiException('API recusou o token (HTTP ${r.statusCode}).');
      }
      if (r.statusCode != 200) {
        var detalhe = r.body;
        try {
          final d = jsonDecode(r.body);
          if (d is Map && d['error'] != null) {
            detalhe = d['error'].toString();
          }
        } catch (_) {}
        throw LanApiException('API GET $path HTTP ${r.statusCode}: $detalhe');
      }
      onSucessoRede?.call();
      final cd = r.headers['content-disposition'] ?? '';
      String? filename;
      final m = RegExp(r'filename="?([^";]+)"?').firstMatch(cd);
      if (m != null) filename = m.group(1);
      return (bytes: r.bodyBytes, filename: filename);
    } catch (e) {
      _rethrowRede(e, path, 'GET');
    }
  }

  Future<Map<String, dynamic>> _putJson(
    String path,
    Map<String, dynamic> body,
  ) async {
    try {
      final r = await http
          .put(
            _uri(path),
            headers: _headers(),
            body: jsonEncode(body),
          )
          .timeout(timeoutEscrita);
      if (r.statusCode == 401 || r.statusCode == 403) {
        throw LanApiException('API recusou o token (HTTP ${r.statusCode}).');
      }
      if (r.statusCode < 200 || r.statusCode >= 300) {
        throw LanApiException(
          'API PUT $path HTTP ${r.statusCode}: ${r.body}',
        );
      }
      if (r.body.trim().isEmpty) {
        onSucessoRede?.call();
        return {'ok': true};
      }
      final d = jsonDecode(r.body);
      if (d is! Map) {
        onSucessoRede?.call();
        return {'ok': true};
      }
      onSucessoRede?.call();
      return Map<String, dynamic>.from(d);
    } catch (e) {
      _rethrowRede(e, path, 'PUT');
    }
  }

  /// Presenca dos terminais/celular na API (mesmo snapshot do rodape do servidor).
  Future<Map<String, dynamic>?> obterPresenca() async {
    if (!configurado) return null;
    try {
      final m = await _getJson('/api/presence');
      if (m['activeCount'] is! num && m['ok'] != true) return null;
      return m;
    } catch (_) {
      return null;
    }
  }

  Future<bool> healthOk() async {
    if (!configurado) return false;
    try {
      final r = await http
          .get(_uri('/api/health'), headers: _headers())
          .timeout(timeoutHealth);
      if (r.statusCode != 200) return false;
      final d = jsonDecode(r.body);
      if (d is! Map) return false;
      final ok = d['ok'] == true;
      if (ok) {
        onSucessoRede?.call();
      } else {
        onFalhaRede?.call();
      }
      return ok;
    } catch (_) {
      onFalhaRede?.call();
      return false;
    }
  }

  /// Status de usuarios no PC servidor (terminal leve).
  Future<Map<String, dynamic>> authStatus() => _getJson('/api/auth/status');

  Future<Map<String, dynamic>> listarUsuarios() => _getJson('/api/usuarios');

  Future<Map<String, dynamic>> salvarUsuario({
    required Map<String, dynamic> usuario,
    String? senhaPlainNova,
    String alteradoPorLogin = '',
    String resumoExtra = '',
  }) =>
      _postJson('/api/usuarios/salvar', {
        'usuario': usuario,
        if (senhaPlainNova != null && senhaPlainNova.isNotEmpty)
          'senhaPlainNova': senhaPlainNova,
        if (alteradoPorLogin.trim().isNotEmpty)
          'alteradoPorLogin': alteradoPorLogin.trim(),
        if (resumoExtra.trim().isNotEmpty) 'resumoExtra': resumoExtra.trim(),
      });

  Future<Map<String, dynamic>> removerUsuario({
    required String id,
    String removidoPorLogin = '',
  }) =>
      _postJson('/api/usuarios/$id/remover', {
        if (removidoPorLogin.trim().isNotEmpty)
          'removidoPorLogin': removidoPorLogin.trim(),
      });

  Future<Map<String, dynamic>> obterEmpresaConfig() =>
      _getJson('/api/empresa/config');

  Future<Map<String, dynamic>> salvarEmpresaConfigRemoto(
    Map<String, dynamic> config,
  ) =>
      _postJson('/api/empresa/config', {'config': config});

  Future<Map<String, dynamic>> obterEmpresaFiscal() =>
      _getJson('/api/empresa/fiscal');

  /// Login contra o banco de usuarios do PC servidor.
  /// Retorna null se usuario/senha invalidos (nao e falha de rede).
  Future<Map<String, dynamic>?> authLogin({
    required String login,
    required String senha,
  }) async {
    try {
      final r = await http
          .post(
            _uri('/api/auth/login'),
            headers: _headers(),
            body: jsonEncode({'login': login, 'senha': senha}),
          )
          .timeout(timeoutEscrita);
      if (r.statusCode == 403) {
        throw LanApiException('API recusou o token (HTTP 403).');
      }
      if (r.statusCode == 401) {
        onSucessoRede?.call();
        return null;
      }
      if (r.statusCode < 200 || r.statusCode >= 300) {
        throw LanApiException(
          'API POST /api/auth/login HTTP ${r.statusCode}: ${r.body}',
        );
      }
      final d = jsonDecode(r.body);
      if (d is! Map) {
        throw LanApiException('Resposta invalida em /api/auth/login');
      }
      onSucessoRede?.call();
      final map = Map<String, dynamic>.from(d);
      if (map['ok'] != true) return null;
      return map;
    } catch (e) {
      _rethrowRede(e, '/api/auth/login', 'POST');
    }
  }

  Future<List<Produto>> listarProdutos({
    String q = '',
    int limit = 200,
    int offset = 0,
    bool somenteAtivos = true,
    bool somenteInativos = false,
  }) async {
    try {
      final r = await http
          .get(
            _uri('/api/produtos', {
              if (q.trim().isNotEmpty) 'q': q.trim(),
              'limit': '$limit',
              if (offset > 0) 'offset': '$offset',
              'somenteAtivos': somenteAtivos ? 'true' : 'false',
              if (somenteInativos) 'somenteInativos': 'true',
            }),
            headers: _headers(),
          )
          .timeout(timeoutLeitura);
      if (r.statusCode == 401 || r.statusCode == 403) {
        throw LanApiException('API recusou o token (HTTP ${r.statusCode}).');
      }
      if (r.statusCode != 200) {
        throw LanApiException(
          'API GET /api/produtos HTTP ${r.statusCode}: ${r.body}',
        );
      }
      onSucessoRede?.call();
      final maps = await lanApiDecodificarListaItens(r.body);
      return maps.map(SyncEntityCodec.produtoDeMap).toList(growable: false);
    } catch (e) {
      _rethrowRede(e, '/api/produtos', 'GET');
    }
  }

  Future<String> proximoSkuProduto({int? ignorarProdutoId}) async {
    final m = await _getJson(
      '/api/produtos/proximo-sku',
      query: {
        if (ignorarProdutoId != null && ignorarProdutoId > 0)
          'ignorarId': '$ignorarProdutoId',
      },
    );
    return (m['sku'] ?? '').toString();
  }

  Future<Produto?> obterProduto(int id) async {
    if (id <= 0) return null;
    try {
      final m = await _getJson('/api/produtos/$id');
      final item = m['item'];
      if (item is! Map) return null;
      return SyncEntityCodec.produtoDeMap(Map<String, dynamic>.from(item));
    } catch (_) {
      return null;
    }
  }

  Future<List<Map<String, dynamic>>> listarHistoricoEntradaProduto(
    int produtoId, {
    int limit = 100,
  }) async {
    final m = await _getJson(
      '/api/produtos/$produtoId/historico-entrada',
      query: {'limit': '$limit'},
    );
    final items = m['items'];
    if (items is! List) return const [];
    return items
        .whereType<Map>()
        .map((e) => Map<String, dynamic>.from(e))
        .toList(growable: false);
  }

  Future<List<Map<String, dynamic>>> listarSugestoesVendaProduto(
    int produtoId,
  ) async {
    final m = await _getJson('/api/produtos/$produtoId/sugestoes-venda');
    final items = m['items'];
    if (items is! List) return const [];
    return items
        .whereType<Map>()
        .map((e) => Map<String, dynamic>.from(e))
        .toList(growable: false);
  }

  Future<void> salvarSugestoesVendaProduto(
    int produtoId,
    List<Map<String, dynamic>> items,
  ) async {
    await _postJson('/api/produtos/$produtoId/sugestoes-venda', {
      'items': items,
    });
  }

  Future<int> salvarProduto(Produto p) async {
    final m = await _postJson('/api/produtos', {
      'produto': SyncEntityCodec.produtoParaMap(p),
    });
    return (m['id'] as num?)?.toInt() ?? 0;
  }

  /// Upload de foto para o PC1 (`POST /api/produtos/imagem`).
  Future<String?> uploadProdutoImagem({
    required String fileName,
    required List<int> bytes,
  }) async {
    final m = await _postJson(
      '/api/produtos/imagem',
      {
        'fileName': fileName,
        'contentBase64': base64Encode(bytes),
      },
      timeout: const Duration(seconds: 90),
    );
    if (m['ok'] != true) return null;
    final path = (m['path'] ?? m['fileName'] ?? fileName).toString().trim();
    return path.isEmpty ? null : path;
  }

  Future<List<Cliente>> listarClientes({String q = '', int limit = 100}) async {
    final m = await _getJson('/api/clientes', query: {
      if (q.trim().isNotEmpty) 'q': q.trim(),
      'limit': '$limit',
    });
    final list = m['items'];
    if (list is! List) return [];
    return list
        .whereType<Map>()
        .map((e) => SyncEntityCodec.clienteDeMap(Map<String, dynamic>.from(e)))
        .toList();
  }

  Future<Cliente?> obterCliente(int id) async {
    if (id <= 0) return null;
    try {
      final m = await _getJson('/api/clientes/$id');
      final item = m['item'];
      if (item is! Map) return null;
      return SyncEntityCodec.clienteDeMap(Map<String, dynamic>.from(item));
    } catch (_) {
      return null;
    }
  }

  Future<int> salvarCliente(Cliente c) async {
    final m = await _postJson('/api/clientes', {
      'cliente': SyncEntityCodec.clienteParaMap(c),
    });
    return (m['id'] as num?)?.toInt() ?? 0;
  }

  Future<bool> removerCliente(int id) async {
    final m = await _postJson('/api/clientes/$id/remover', {});
    return m['ok'] == true;
  }

  Future<List<FornecedorNfe>> listarFornecedores({
    String q = '',
    int limit = 200,
    bool apenasAtivos = false,
  }) async {
    final m = await _getJson('/api/fornecedores', query: {
      if (q.trim().isNotEmpty) 'q': q.trim(),
      'limit': '$limit',
      if (apenasAtivos) 'apenasAtivos': 'true',
    });
    final list = m['items'];
    if (list is! List) return [];
    return list
        .whereType<Map>()
        .map(
          (e) => SyncEntityCodecExtras.fornecedorNfeDeMap(
            Map<String, dynamic>.from(e),
          ),
        )
        .toList();
  }

  Future<FornecedorNfe?> obterFornecedor(int id) async {
    if (id <= 0) return null;
    try {
      final m = await _getJson('/api/fornecedores/$id');
      final item = m['item'];
      if (item is! Map) return null;
      return SyncEntityCodecExtras.fornecedorNfeDeMap(
        Map<String, dynamic>.from(item),
      );
    } catch (_) {
      return null;
    }
  }

  Future<int> salvarFornecedor(FornecedorNfe f) async {
    final m = await _postJson('/api/fornecedores', {
      'fornecedor': SyncEntityCodecExtras.fornecedorNfeParaMap(f),
    });
    return (m['id'] as num?)?.toInt() ?? 0;
  }

  Future<bool> removerFornecedor(int id) async {
    final m = await _postJson('/api/fornecedores/$id/remover', {});
    return m['ok'] == true;
  }

  Future<bool> removerVendedor(int id) async {
    final m = await _postJson('/api/vendedores/$id/remover', {});
    return m['ok'] == true;
  }

  Future<bool> removerMotorista(int id) async {
    final m = await _postJson('/api/motoristas/$id/remover', {});
    return m['ok'] == true;
  }

  Future<bool> removerFuncionario(int id) async {
    final m = await _postJson('/api/funcionarios/$id/remover', {});
    return m['ok'] == true;
  }

  Future<List<Vendedor>> listarVendedores() async {
    final m = await _getJson('/api/vendedores');
    final list = m['items'];
    if (list is! List) return [];
    return list
        .whereType<Map>()
        .map((e) => SyncEntityCodec.vendedorDeMap(Map<String, dynamic>.from(e)))
        .toList();
  }

  Future<List<Venda>> listarOrcamentos({int limit = 120}) async {
    final m = await _getJson('/api/orcamentos', query: {'limit': '$limit'});
    return _vendasDeLista(m['items']);
  }

  Future<Venda?> obterVenda(int id) async {
    if (id <= 0) return null;
    try {
      final m = await _getJson('/api/vendas/$id');
      final item = m['item'];
      if (item is! Map) return null;
      return vendaCompletaDeMap(Map<String, dynamic>.from(item));
    } catch (_) {
      return null;
    }
  }

  Future<List<ItemVenda>> listarItensVenda(int vendaId) async {
    final m = await _getJson('/api/vendas/$vendaId/itens');
    final list = m['items'];
    if (list is! List) return [];
    final venda = Venda(id: vendaId);
    return list.whereType<Map>().map((raw) {
      final e = Map<String, dynamic>.from(raw);
      final produtoId = (e['produtoId'] as num?)?.toInt() ?? 0;
      final item = ItemVenda(
        id: (e['id'] as num?)?.toInt() ?? 0,
        nomeProduto: (e['nomeProduto'] ?? '').toString(),
        quantidade: (e['quantidade'] as num?)?.toInt() ?? 0,
        quantidadeJaRetirada:
            (e['quantidadeJaRetirada'] as num?)?.toInt() ?? 0,
        quantidadeNoCarreto: (e['quantidadeNoCarreto'] as num?)?.toInt() ?? 0,
        quantidadeDevolvida: (e['quantidadeDevolvida'] as num?)?.toInt() ?? 0,
        tipoEntregaItem: (e['tipoEntregaItem'] ?? 'retirada').toString(),
        precoTipo: (e['precoTipo'] ?? 'preco1').toString(),
        precoUnitario: (e['precoUnitario'] as num?)?.toDouble() ?? 0,
        precoCustoUnitario: (e['precoCustoUnitario'] as num?)?.toDouble() ?? 0,
        promocaoId: (e['promocaoId'] as num?)?.toInt() ?? 0,
        promocaoNomeSnapshot: (e['promocaoNomeSnapshot'] ?? '').toString(),
        lojaOrigemMercadoria: (e['lojaOrigemMercadoria'] ?? '').toString(),
        buscarNaLojaStatus: (e['buscarNaLojaStatus'] ?? '').toString(),
        quantidadeBuscarNaLoja:
            (e['quantidadeBuscarNaLoja'] as num?)?.toInt() ?? 0,
      );
      item.venda.target = venda;
      if (produtoId > 0) {
        item.produto.targetId = produtoId;
      }
      return item;
    }).toList();
  }

  Future<int> criarOrcamento(Map<String, dynamic> body) async {
    final key = (body['uuidLocal'] ?? body['idempotencyKey'] ?? '')
        .toString()
        .trim();
    final m = await _postJson(
      '/api/orcamentos',
      body,
      extraHeaders: key.isEmpty ? null : {'Idempotency-Key': key},
    );
    return (m['id'] as num?)?.toInt() ?? 0;
  }

  Future<void> atualizarOrcamento(int id, Map<String, dynamic> body) async {
    await _putJson('/api/orcamentos/$id', body);
  }

  Future<Map<String, dynamic>> meta() => _getJson('/api/meta');

  /// GET `/api/produtos/imagem/<fileName>` — bytes da foto no PC servidor.
  Future<List<int>?> downloadProdutoImagem(String fileName) async {
    if (!configurado) return null;
    final nome = fileName.trim();
    if (nome.isEmpty) return null;
    Future<List<int>?> tentar(String pathSuffix) async {
      try {
        final r = await http
            .get(
              _uri('/api/produtos/imagem/$pathSuffix'),
              headers: _headers(json: false),
            )
            .timeout(const Duration(seconds: 60));
        if (r.statusCode != 200 || r.bodyBytes.isEmpty) return null;
        final ct = r.headers['content-type'] ?? '';
        if (ct.contains('application/json')) return null;
        onSucessoRede?.call();
        return r.bodyBytes;
      } catch (_) {
        return null;
      }
    }

    return await tentar(nome) ?? await tentar(Uri.encodeComponent(nome));
  }

  Future<Map<String, dynamic>> emitirNfce(
    int vendaId, {
    bool permitirVendaSemEstoque = true,
  }) =>
      _postJson(
        '/api/vendas/$vendaId/emitir-nfce',
        {'permitirVendaSemEstoque': permitirVendaSemEstoque},
        timeout: timeoutFiscal,
        aceitarErroJson: true,
      );

  Future<Map<String, dynamic>> emitirNfe(
    int vendaId, {
    Map<String, dynamic>? destinatario,
    Map<String, dynamic>? logistica,
    bool permitirVendaSemEstoque = true,
  }) =>
      _postJson(
        '/api/vendas/$vendaId/emitir-nfe',
        {
          if (destinatario != null) 'destinatario': destinatario,
          if (logistica != null) 'logistica': logistica,
          'permitirVendaSemEstoque': permitirVendaSemEstoque,
        },
        timeout: timeoutFiscal,
        aceitarErroJson: true,
      );

  Future<Map<String, dynamic>> obterFechamentoFiscal({
    required int mes,
    required int ano,
  }) =>
      _getJson(
        '/api/fiscal/fechamento',
        query: {'mes': '$mes', 'ano': '$ano'},
        timeout: timeoutFiscal,
      );

  /// KPIs do relatorio mensal (sem pacote completo de XMLs).
  Future<Map<String, dynamic>> obterRelatorioFiscalMensal({
    required int mes,
    required int ano,
  }) =>
      _getJson(
        '/api/fiscal/relatorio-mensal',
        query: {'mes': '$mes', 'ano': '$ano'},
        timeout: timeoutFiscal,
      );

  Future<({List<int> bytes, String filename})> baixarFechamentoZip({
    required int mes,
    required int ano,
    bool forcar = false,
  }) async {
    final r = await _getBytes(
      '/api/fiscal/fechamento/zip',
      query: {
        'mes': '$mes',
        'ano': '$ano',
        if (forcar) 'forcar': '1',
      },
      timeout: timeoutFechamento,
    );
    final nome = r.filename ??
        'fechamento_contabilidade_${mes.toString().padLeft(2, '0')}_$ano.zip';
    return (bytes: r.bytes, filename: nome);
  }

  Future<({List<int> bytes, String filename})> baixarFechamentoExcel({
    required int mes,
    required int ano,
    bool forcar = false,
  }) async {
    final r = await _getBytes(
      '/api/fiscal/fechamento/excel',
      query: {
        'mes': '$mes',
        'ano': '$ano',
        if (forcar) 'forcar': '1',
      },
      timeout: timeoutFechamento,
    );
    final nome = r.filename ??
        'fechamento_contabilidade_${mes.toString().padLeft(2, '0')}_$ano.xlsx';
    return (bytes: r.bytes, filename: nome);
  }

  Future<Map<String, dynamic>> backupRemotoStatus() =>
      _getJson('/api/backup/status', timeout: timeoutLeitura);

  Future<Map<String, dynamic>> criarBackupRemoto() => _postJson(
        '/api/backup/criar',
        const {},
        timeout: timeoutBackup,
      );

  /// Baixa o ZIP do ultimo backup do servidor e grava em [destinoPath].
  Future<({String filename, int bytes})> baixarBackupZipParaArquivo(
    String destinoPath,
  ) async {
    final client = http.Client();
    try {
      final req = http.Request('GET', _uri('/api/backup/zip'));
      req.headers.addAll(_headers(json: false));
      final res = await client.send(req).timeout(timeoutBackup);
      if (res.statusCode == 401 || res.statusCode == 403) {
        throw LanApiException('API recusou o token (HTTP ${res.statusCode}).');
      }
      if (res.statusCode != 200) {
        final corpo = await res.stream.bytesToString();
        var detalhe = corpo;
        try {
          final d = jsonDecode(corpo);
          if (d is Map && d['error'] != null) {
            detalhe = d['error'].toString();
          }
        } catch (_) {}
        throw LanApiException(
          'API GET /api/backup/zip HTTP ${res.statusCode}: $detalhe',
        );
      }
      onSucessoRede?.call();
      final cd = res.headers['content-disposition'] ?? '';
      String? filename;
      final m = RegExp(r'filename="?([^";]+)"?').firstMatch(cd);
      if (m != null) filename = m.group(1);
      final file = File(destinoPath);
      await file.parent.create(recursive: true);
      final sink = file.openWrite();
      try {
        await sink.addStream(res.stream);
        await sink.flush();
      } finally {
        await sink.close();
      }
      if (!file.existsSync() || file.lengthSync() < 64) {
        throw LanApiException('Arquivo de backup baixado esta vazio.');
      }
      return (
        filename: filename ?? destinoPath.replaceAll('\\', '/').split('/').last,
        bytes: file.lengthSync(),
      );
    } catch (e) {
      _rethrowRede(e, '/api/backup/zip', 'GET');
    } finally {
      client.close();
    }
  }

  /// Gera o pacote no PC servidor e envia ZIP+Excel ao e-mail do contador.
  Future<Map<String, dynamic>> enviarFechamentoContador({
    required int mes,
    required int ano,
    bool forcar = false,
  }) async {
    try {
      final r = await http
          .post(
            _uri('/api/fiscal/fechamento/enviar-email', {
              'mes': '$mes',
              'ano': '$ano',
              if (forcar) 'forcar': '1',
            }),
            headers: _headers(),
            body: jsonEncode({}),
          )
          .timeout(timeoutFechamento);
      if (r.statusCode == 401 || r.statusCode == 403) {
        throw LanApiException('API recusou o token (HTTP ${r.statusCode}).');
      }
      if (r.statusCode < 200 || r.statusCode >= 300) {
        var detalhe = r.body;
        try {
          final d = jsonDecode(r.body);
          if (d is Map && d['error'] != null) {
            detalhe = d['error'].toString();
          }
        } catch (_) {}
        throw LanApiException(detalhe);
      }
      if (r.body.trim().isEmpty) {
        onSucessoRede?.call();
        return {'ok': true};
      }
      final d = jsonDecode(r.body);
      if (d is! Map) {
        onSucessoRede?.call();
        return {'ok': true};
      }
      onSucessoRede?.call();
      return Map<String, dynamic>.from(d);
    } catch (e) {
      _rethrowRede(e, '/api/fiscal/fechamento/enviar-email', 'POST');
    }
  }

  Future<List<Map<String, dynamic>>> listarNfeSaida({int limit = 300}) async {
    final m = await listarNfeSaidaPainel(limit: limit);
    final list = m['items'];
    if (list is! List) return [];
    return list
        .whereType<Map>()
        .map((e) => Map<String, dynamic>.from(e))
        .toList();
  }

  /// Painel completo: historico + pendencias + meta (KPIs).
  Future<Map<String, dynamic>> listarNfeSaidaPainel({int limit = 300}) =>
      _getJson(
        '/api/nfe-saida',
        query: {'limit': '$limit'},
        timeout: timeoutFiscal,
      );

  Future<Map<String, dynamic>> reconsultarNfeSaida(String referencia) =>
      _postJson(
        '/api/nfe-saida/reconsultar',
        {'referencia': referencia},
        timeout: timeoutFiscal,
        aceitarErroJson: true,
      );

  Future<Map<String, dynamic>> reconsultarNfeSaidaProcessando() => _postJson(
        '/api/nfe-saida/reconsultar-processando',
        {},
        timeout: timeoutFiscal,
        aceitarErroJson: true,
      );

  Future<Map<String, dynamic>> cancelarNfeSaida({
    required String referencia,
    required String justificativa,
  }) =>
      _postJson(
        '/api/nfe-saida/cancelar',
        {
          'referencia': referencia,
          'justificativa': justificativa,
        },
        timeout: timeoutFiscal,
        aceitarErroJson: true,
      );

  Future<Map<String, dynamic>> cartaCorrecaoNfeSaida({
    required String referencia,
    required String correcao,
  }) =>
      _postJson(
        '/api/nfe-saida/carta-correcao',
        {
          'referencia': referencia,
          'correcao': correcao,
        },
        timeout: timeoutFiscal,
        aceitarErroJson: true,
      );

  Future<List<Map<String, dynamic>>> listarRelatorioVendasDia({
    DateTime? dia,
  }) async {
    final m = await _getJson('/api/relatorios/vendas-dia', query: {
      if (dia != null) 'dia': dia.toUtc().toIso8601String(),
    });
    final list = m['items'];
    if (list is! List) return [];
    return list
        .whereType<Map>()
        .map((e) => Map<String, dynamic>.from(e))
        .toList();
  }

  Future<void> finalizarVenda(
    int id, {
    required bool permitirVendaSemEstoque,
    String? terminalId,
  }) async {
    await _postJson(
      '/api/vendas/$id/finalizar',
      {
        'permitirVendaSemEstoque': permitirVendaSemEstoque,
        if (terminalId != null && terminalId.trim().isNotEmpty)
          'terminalId': terminalId.trim(),
      },
      timeout: timeoutFinalizacao,
    );
  }

  Future<List<Venda>> listarVendas({
    String status = 'finalizada',
    int limit = 200,
    int offset = 0,
    DateTime? desde,
    DateTime? ate,
    int? clienteId,
    String? filtroCancelamento,
    String? formaPagamento,
    String? tipoEntrega,
    String? entregaPendente,
    String? filtroFiscal,
    String? busca,
    String? canceladaPor,
  }) async {
    final pagina = await listarVendasPagina(
      status: status,
      limit: limit,
      offset: offset,
      desde: desde,
      ate: ate,
      clienteId: clienteId,
      filtroCancelamento: filtroCancelamento,
      formaPagamento: formaPagamento,
      tipoEntrega: tipoEntrega,
      entregaPendente: entregaPendente,
      filtroFiscal: filtroFiscal,
      busca: busca,
      canceladaPor: canceladaPor,
    );
    return pagina.vendas;
  }

  Future<ListagemVendasPagina> listarVendasPagina({
    String status = 'finalizada',
    int limit = 200,
    int offset = 0,
    DateTime? desde,
    DateTime? ate,
    int? clienteId,
    String? filtroCancelamento,
    String? formaPagamento,
    String? tipoEntrega,
    String? entregaPendente,
    String? filtroFiscal,
    String? busca,
    String? canceladaPor,
  }) async {
    try {
      final r = await http
          .get(
            _uri('/api/vendas', {
              'status': status,
              'limit': '$limit',
              if (offset > 0) 'offset': '$offset',
              if (desde != null) 'desde': desde.toUtc().toIso8601String(),
              if (ate != null) 'ate': ate.toUtc().toIso8601String(),
              if (clienteId != null && clienteId > 0) 'clienteId': '$clienteId',
              if (filtroCancelamento != null &&
                  filtroCancelamento.trim().isNotEmpty)
                'filtroCancelamento': filtroCancelamento.trim(),
              if (formaPagamento != null &&
                  formaPagamento.trim().isNotEmpty &&
                  formaPagamento != 'todos')
                'formaPagamento': formaPagamento.trim(),
              if (tipoEntrega != null &&
                  tipoEntrega.trim().isNotEmpty &&
                  tipoEntrega != 'todos')
                'tipoEntrega': tipoEntrega.trim(),
              if (entregaPendente != null &&
                  entregaPendente.trim().isNotEmpty &&
                  entregaPendente != 'todos')
                'entregaPendente': entregaPendente.trim(),
              if (filtroFiscal != null &&
                  filtroFiscal.trim().isNotEmpty &&
                  filtroFiscal != 'todos')
                'filtroFiscal': filtroFiscal.trim(),
              if (busca != null && busca.trim().isNotEmpty) 'busca': busca.trim(),
              if (canceladaPor != null &&
                  canceladaPor.trim().isNotEmpty &&
                  canceladaPor != 'todos')
                'canceladaPor': canceladaPor.trim(),
            }),
            headers: _headers(),
          )
          .timeout(timeoutLeitura);
      if (r.statusCode != 200) {
        throw LanApiException(
          'API GET /api/vendas HTTP ${r.statusCode}: ${r.body}',
        );
      }
      onSucessoRede?.call();
      return _listarVendasPaginaCorpo(r.body);
    } catch (e) {
      _rethrowRede(e, '/api/vendas', 'GET');
    }
  }

  Future<List<Venda>> listarEntregas({int limit = 500}) async {
    try {
      final r = await http
          .get(
            _uri('/api/entregas', {'limit': '$limit'}),
            headers: _headers(),
          )
          .timeout(timeoutLeitura);
      if (r.statusCode != 200) {
        throw LanApiException(
          'API GET /api/entregas HTTP ${r.statusCode}: ${r.body}',
        );
      }
      onSucessoRede?.call();
      return _listarVendasCorpo(r.body);
    } catch (e) {
      _rethrowRede(e, '/api/entregas', 'GET');
    }
  }

  /// Agenda mensal de carretos (contagem + detalhe por dia).
  /// [incluirProdutos]: false = so calendario; true = itens com qtd/nome/unidade.
  Future<AgendaCarretoOcupacaoMes> obterOcupacaoAgendaCarreto(
    DateTime mesRef, {
    bool incluirProdutos = true,
  }) async {
    final mes =
        '${mesRef.year}-${mesRef.month.toString().padLeft(2, '0')}';
    final m = await _getJson(
      '/api/entregas/ocupacao',
      query: {
        'mes': mes,
        'produtos': incluirProdutos ? '1' : '0',
      },
    );
    return AgendaCarretoOcupacaoMes.deMap(m);
  }

  static List<Venda> _vendasDeLista(Object? raw) {
    if (raw is! List) return [];
    // growable: caches do terminal fazem insert/remove (ex.: salvar orcamento).
    return raw
        .whereType<Map>()
        .map((e) => vendaCompletaDeMap(Map<String, dynamic>.from(e)))
        .toList();
  }

  Future<List<Venda>> _listarVendasCorpo(String corpoJson) async {
    final pagina = await _listarVendasPaginaCorpo(corpoJson);
    return pagina.vendas;
  }

  Future<ListagemVendasPagina> _listarVendasPaginaCorpo(String corpoJson) async {
    final meta = await lanApiDecodificarListaItensComMeta(corpoJson);
    return ListagemVendasPagina(
      vendas: meta.items.map(vendaCompletaDeMap).toList(),
      total: meta.total,
      totalValor: meta.totalValor,
    );
  }

  /// Itens extraidos do JSON quando ToMany/Backlink detached nao aceita .add().
  static final Expando<List<ItemVenda>> itensExtraidos =
      Expando<List<ItemVenda>>();

  /// Resumo Dev/Troca enviado na listagem leve (`GET /api/vendas`).
  static final Expando<({double dev, double troca})> devolucaoListagem =
      Expando();

  /// Cabecalho + itens + vinculos (cliente/vendedor) para telas e relatorios.
  static Venda vendaCompletaDeMap(Map<String, dynamic> m) {
    final venda = SyncEntityCodec.vendaCabecaDeMap(m);
    venda.cliente.targetId = (m['clienteId'] as num?)?.toInt() ?? 0;
    venda.vendedor.targetId = (m['vendedorId'] as num?)?.toInt() ?? 0;
    final carregados = <ItemVenda>[];
    final itens = m['itens'];
    if (itens is List) {
      for (final raw in itens.whereType<Map>()) {
        final im = Map<String, dynamic>.from(raw);
        final item = SyncEntityCodec.itemDeMap(im)
          ..id = (im['id'] as num?)?.toInt() ?? 0
          ..produto.targetId = (im['produtoId'] as num?)?.toInt() ?? 0;
        try {
          item.venda.target = venda;
        } catch (_) {}
        try {
          venda.itens.add(item);
        } catch (_) {
          // ToMany Backlink detached: usa [itensExtraidos].
        }
        carregados.add(item);
      }
    }
    if (carregados.isNotEmpty) {
      itensExtraidos[venda] = carregados;
    }
    final dev = (m['valorDevolvido'] as num?)?.toDouble() ?? 0;
    final troca = (m['valorTroca'] as num?)?.toDouble() ?? 0;
    if (m['temDevolucaoTroca'] == true || dev > 0.005 || troca > 0.005) {
      devolucaoListagem[venda] = (dev: dev, troca: troca);
    }
    VendaRelacaoSafe.aplicarSnapshotDoMap(venda, m);
    return venda;
  }

  Future<void> atualizarStatusEntrega(
    int id,
    String statusEntrega, {
    String? complementoEntregaJson,
    bool retornouParaLoja = false,
  }) async {
    await _postJson('/api/entregas/$id/status', {
      'statusEntrega': statusEntrega,
      if (complementoEntregaJson != null)
        'complementoEntregaJson': complementoEntregaJson,
      if (retornouParaLoja) 'retornouParaLoja': true,
    });
  }

  /// Baixa atomica do modo motorista. Timeout curto (Tailscale/4G).
  Future<Map<String, dynamic>> baixarEntregaMotorista({
    required int vendaId,
    required String recebidoPor,
    required String usuarioLogin,
    String fotoPathLocal = '',
    String fotoPathServidor = '',
    String statusAnterior = '',
  }) =>
      _postJson(
        '/api/entregas/baixa',
        {
          'vendaId': vendaId,
          'recebidoPor': recebidoPor,
          'usuarioLogin': usuarioLogin,
          'fotoPathLocal': fotoPathLocal,
          'fotoPathServidor': fotoPathServidor,
          if (statusAnterior.trim().isNotEmpty) 'statusAnterior': statusAnterior,
        },
        timeout: timeoutBaixaMotorista,
        sinalizarStatusRede: false,
      );

  Future<Map<String, dynamic>> registrarNaoEntregueMotorista({
    required int vendaId,
    required String motivoCodigo,
    String motivoDetalhe = '',
    required String usuarioLogin,
    String statusAnterior = '',
    bool retornouParaLoja = false,
  }) =>
      _postJson(
        '/api/entregas/nao-entregue',
        {
          'vendaId': vendaId,
          'motivoCodigo': motivoCodigo,
          'motivoDetalhe': motivoDetalhe,
          'usuarioLogin': usuarioLogin,
          'retornouParaLoja': retornouParaLoja,
          if (statusAnterior.trim().isNotEmpty) 'statusAnterior': statusAnterior,
        },
        timeout: timeoutBaixaMotorista,
        sinalizarStatusRede: false,
      );

  /// POST `/api/entregas/pod-foto` — JPEG em base64 para a pasta do PC1.
  Future<String?> uploadPodFoto({
    required String fileName,
    required List<int> jpegBytes,
  }) async {
    final m = await _postJson(
      '/api/entregas/pod-foto',
      {
        'fileName': fileName,
        'contentBase64': base64Encode(jpegBytes),
      },
      timeout: timeoutPodFoto,
      sinalizarStatusRede: false,
    );
    if (m['ok'] != true) return null;
    final path = (m['path'] ?? '').toString().trim();
    return path.isEmpty ? null : path;
  }

  /// GET `/api/entregas/pod-foto/<fileName>` — JPEG do PC1.
  Future<List<int>?> downloadPodFoto({required String fileName}) async {
    final nome = fileName.trim();
    if (nome.isEmpty) return null;
    try {
      final r = await _getBytes(
        '/api/entregas/pod-foto/${Uri.encodeComponent(nome)}',
        timeout: timeoutPodFoto,
      );
      if (r.bytes.isEmpty) return null;
      return r.bytes;
    } catch (_) {
      return null;
    }
  }

  Future<Map<String, dynamic>> registrarPodEntrega(
    int vendaId, {
    required String recebidoPor,
    required String usuarioLogin,
    String fotoPathLocal = '',
    String fotoPathServidor = '',
    String ocorrenciaMotivo = '',
    String ocorrenciaStatus = 'pod_entrega',
  }) =>
      _postJson('/api/entregas/$vendaId/pod', {
        'recebidoPor': recebidoPor,
        'usuarioLogin': usuarioLogin,
        'fotoPathLocal': fotoPathLocal,
        'fotoPathServidor': fotoPathServidor,
        if (ocorrenciaMotivo.trim().isNotEmpty) 'ocorrenciaMotivo': ocorrenciaMotivo,
        if (ocorrenciaMotivo.trim().isNotEmpty) 'ocorrenciaStatus': ocorrenciaStatus,
      });

  Future<void> registrarOcorrenciaEntrega(
    int vendaId, {
    required String status,
    String motivo = '',
    String usuario = '',
  }) async {
    await _postJson('/api/entregas/$vendaId/ocorrencia', {
      'status': status,
      'motivo': motivo,
      'usuario': usuario,
    });
  }

  Future<void> registrarHistoricoStatusEntrega(
    int vendaId, {
    required String statusAnterior,
    required String statusNovo,
    String motivo = '',
    String usuario = '',
  }) async {
    await _postJson('/api/entregas/$vendaId/historico-status', {
      'statusAnterior': statusAnterior,
      'statusNovo': statusNovo,
      'motivo': motivo,
      'usuario': usuario,
    });
  }

  Future<Map<String, dynamic>> registrarRetiradaParcial(
    int vendaId, {
    required Map<int, int> quantidades,
    required String usuario,
    String? retiradoPor,
    String tipo = 'futura',
  }) =>
      _postJson('/api/entregas/$vendaId/retirada-parcial', {
        'tipo': tipo,
        'quantidades': {
          for (final e in quantidades.entries) '${e.key}': e.value,
        },
        'usuario': usuario,
        if (retiradoPor != null && retiradoPor.trim().isNotEmpty)
          'retiradoPor': retiradoPor.trim(),
      });

  Future<List<Map<String, dynamic>>> listarTitulosAbertos() async {
    final m = await _getJson('/api/titulos');
    final list = m['items'];
    if (list is! List) return [];
    return list
        .whereType<Map>()
        .map((e) => Map<String, dynamic>.from(e))
        .toList();
  }

  Future<Map<String, dynamic>> saldoFiadoCliente(int clienteId) =>
      _getJson('/api/titulos/saldo-cliente/$clienteId');

  Future<Map<String, dynamic>> validarLimiteCredito({
    required int clienteId,
    required double valorFiadoOperacao,
    int? ignorarVendaId,
  }) =>
      _postJson('/api/titulos/validar-limite', {
        'clienteId': clienteId,
        'valorFiadoOperacao': valorFiadoOperacao,
        if (ignorarVendaId != null) 'ignorarVendaId': ignorarVendaId,
      });

  Future<Map<String, dynamic>> receberTitulo(
    int id, {
    required double valorRecebido,
    String formaPagamento = 'dinheiro',
    String observacao = '',
  }) =>
      _postJson('/api/titulos/$id/receber', {
        'valorRecebido': valorRecebido,
        'formaPagamento': formaPagamento,
        'observacao': observacao,
      });

  Future<Map<String, dynamic>> receberTitulosFifo({
    required int clienteId,
    required double valorRecebido,
    String formaPagamento = 'dinheiro',
    String observacao = '',
  }) =>
      _postJson('/api/titulos/receber-fifo', {
        'clienteId': clienteId,
        'valorRecebido': valorRecebido,
        'formaPagamento': formaPagamento,
        'observacao': observacao,
      });

  Future<Map<String, dynamic>> obterRecebimento(int id) =>
      _getJson('/api/recebimentos/$id');

  Future<List<Map<String, dynamic>>> listarRecebimentosPorCliente(
    int clienteId,
  ) async {
    final m = await _getJson('/api/recebimentos', query: {
      'clienteId': '$clienteId',
    });
    final items = m['items'];
    if (items is! List) return const [];
    return items
        .whereType<Map>()
        .map((e) => Map<String, dynamic>.from(e))
        .toList(growable: false);
  }

  Future<List<Map<String, dynamic>>> listarTitulosQuitadosPorCliente(
    int clienteId, {
    int limit = 100,
  }) async {
    final m = await _getJson('/api/titulos/quitados', query: {
      'clienteId': '$clienteId',
      'limit': '$limit',
    });
    final items = m['items'];
    if (items is! List) return const [];
    return items
        .whereType<Map>()
        .map((e) => Map<String, dynamic>.from(e))
        .toList(growable: false);
  }

  Future<void> cancelarVenda(
    int id, {
    String motivo = '',
    String canceladaPor = '',
  }) =>
      _postJson('/api/vendas/$id/cancelar', {
        'motivo': motivo,
        'canceladaPor': canceladaPor,
      });

  /// Cancela NFC-e/NF-e na SEFAZ e a venda no ERP (PC1). Timeout fiscal longo.
  Future<Map<String, dynamic>> cancelarVendaFiscal(
    int id, {
    required String justificativa,
    String motivo = '',
    String canceladaPor = '',
  }) =>
      _postJson(
        '/api/vendas/$id/cancelar-fiscal',
        {
          'justificativa': justificativa,
          'motivo': motivo,
          'canceladaPor': canceladaPor,
        },
        timeout: timeoutFiscal,
        aceitarErroJson: true,
      );

  Future<Map<String, dynamic>> vincularClienteVendaFinalizada(
    int id,
    int clienteId,
  ) =>
      _postJson('/api/vendas/$id/vincular-cliente', {
        'clienteId': clienteId,
      });

  Future<Map<String, dynamic>> registrarOrcamentoFreteRetiradaFutura({
    required int vendaMaeId,
    required double valorFreteCobrado,
    required DadosPagamentoOrcamento pagamento,
    required String enderecoEntrega,
    required String observacaoEntrega,
    required String prioridadeEntrega,
    required String janelaEntrega,
    required DateTime dataEntregaMarcada,
    int? vendedorId,
  }) =>
      _postJson('/api/vendas/$vendaMaeId/orcamento-frete', {
        'valorFreteCobrado': valorFreteCobrado,
        'pagamento': {
          'formaPagamento': pagamento.formaPagamento,
          'quantidadeParcelas': pagamento.quantidadeParcelas,
        },
        'enderecoEntrega': enderecoEntrega,
        'observacaoEntrega': observacaoEntrega,
        'prioridadeEntrega': prioridadeEntrega,
        'janelaEntrega': janelaEntrega,
        'dataEntregaMarcada': dataEntregaMarcada.toIso8601String(),
        if (vendedorId != null) 'vendedorId': vendedorId,
      });

  Future<Map<String, dynamic>> registrarDevolucaoOuTroca({
    required int vendaOrigemId,
    required String tipo,
    required String motivo,
    required String observacaoFinanceira,
    required String registradoPor,
    required List<Map<String, dynamic>> entradas,
    required List<Map<String, dynamic>> saidasTroca,
    bool permitirVendaSemEstoque = true,
  }) =>
      _postJson('/api/vendas/$vendaOrigemId/devolucao-troca', {
        'tipo': tipo,
        'motivo': motivo,
        'observacaoFinanceira': observacaoFinanceira,
        'registradoPor': registradoPor,
        'entradas': entradas,
        'saidasTroca': saidasTroca,
        'permitirVendaSemEstoque': permitirVendaSemEstoque,
      });

  Future<void> vincularClienteOrcamento(int id, int? clienteId) => _postJson(
        '/api/orcamentos/$id/vincular-cliente',
        {'clienteId': clienteId},
      );

  Future<void> vincularVendedorOrcamento(int id, int vendedorId) => _postJson(
        '/api/orcamentos/$id/vincular-vendedor',
        {'vendedorId': vendedorId},
      );

  Map<String, dynamic> _authCaixaBody({
    String? terminalId,
    String? gerenteLogin,
    String? gerenteSenha,
    bool? exigeGerente,
  }) =>
      {
        if (terminalId != null && terminalId.trim().isNotEmpty)
          'terminalId': terminalId.trim(),
        if (gerenteLogin != null && gerenteLogin.trim().isNotEmpty)
          'gerenteLogin': gerenteLogin.trim(),
        if (gerenteSenha != null && gerenteSenha.isNotEmpty)
          'gerenteSenha': gerenteSenha,
        if (exigeGerente == true) 'exigeGerente': true,
      };

  Future<void> aplicarDescontoOrcamento(
    int id,
    double valor, {
    String? terminalId,
    String? gerenteLogin,
    String? gerenteSenha,
    bool exigeGerente = false,
  }) =>
      _postJson('/api/orcamentos/$id/desconto', {
        'valor': valor,
        ..._authCaixaBody(
          terminalId: terminalId,
          gerenteLogin: gerenteLogin,
          gerenteSenha: gerenteSenha,
          exigeGerente: exigeGerente,
        ),
      });

  Future<void> adicionarItemOrcamento(
    int id,
    Map<String, dynamic> item, {
    bool permitirVendaSemEstoque = false,
    String? terminalId,
  }) =>
      _postJson('/api/orcamentos/$id/itens', {
        'item': item,
        'permitirVendaSemEstoque': permitirVendaSemEstoque,
        ..._authCaixaBody(terminalId: terminalId),
      });

  Future<void> atualizarQuantidadeItemOrcamento(
    int id,
    int itemId,
    int quantidade, {
    bool permitirVendaSemEstoque = false,
    String? terminalId,
  }) =>
      _postJson('/api/orcamentos/$id/itens/$itemId/quantidade', {
        'quantidade': quantidade,
        'permitirVendaSemEstoque': permitirVendaSemEstoque,
        ..._authCaixaBody(terminalId: terminalId),
      });

  Future<void> removerItemOrcamento(
    int id,
    int itemId, {
    String? terminalId,
    String? gerenteLogin,
    String? gerenteSenha,
  }) =>
      _postJson('/api/orcamentos/$id/itens/$itemId/remover', {
        ..._authCaixaBody(
          terminalId: terminalId,
          gerenteLogin: gerenteLogin,
          gerenteSenha: gerenteSenha,
        ),
      });

  Future<void> alterarPagamentoOrcamento(
    int id,
    DadosPagamentoOrcamento pagamento, {
    String? terminalId,
    String? gerenteLogin,
    String? gerenteSenha,
  }) =>
      _postJson('/api/orcamentos/$id/pagamento', {
        'pagamento': {
          'formaPagamento': pagamento.formaPagamento,
          'quantidadeParcelas': pagamento.quantidadeParcelas,
          'linhasMisto': pagamento.linhasMisto?.map((e) => e.toJson()).toList(),
          'planoFiado':
              pagamento.planoFiado?.map((e) => e.toJson()).toList(),
        },
        ..._authCaixaBody(
          terminalId: terminalId,
          gerenteLogin: gerenteLogin,
          gerenteSenha: gerenteSenha,
        ),
      });

  Future<void> substituirPagamentosMistoOrcamento(
    int id,
    List<PagamentoOrcamentoLinha> linhas, {
    String? terminalId,
  }) =>
      _postJson('/api/orcamentos/$id/pagamentos-misto', {
        'linhas': linhas.map((e) => e.toJson()).toList(),
        ..._authCaixaBody(terminalId: terminalId),
      });

  Future<bool> removerProduto(int id) async {
    final m = await _postJson('/api/produtos/$id/remover', {});
    return m['ok'] == true;
  }

  Future<List<Map<String, dynamic>>> listarContasPagar({String? status}) async {
    final m = await _getJson('/api/contas-pagar', query: {
      if (status != null && status.isNotEmpty) 'status': status,
    });
    final list = m['items'];
    if (list is! List) return [];
    return list
        .whereType<Map>()
        .map((e) => Map<String, dynamic>.from(e))
        .toList();
  }

  Future<Map<String, dynamic>> criarContaPagar(Map<String, dynamic> body) =>
      _postJson('/api/contas-pagar', body);

  Future<Map<String, dynamic>> baixarContaPagar(
    int id, {
    required double valorPago,
    DateTime? dataPagamento,
  }) =>
      _postJson('/api/contas-pagar/$id/baixar', {
        'valorPago': valorPago,
        if (dataPagamento != null)
          'dataPagamento': dataPagamento.toUtc().toIso8601String(),
      });

  Future<bool> removerContaPagar(int id) async {
    final m = await _postJson('/api/contas-pagar/$id/remover', {});
    return m['ok'] == true;
  }

  Future<List<Map<String, dynamic>>> listarObrigacoesMensais() async {
    final m = await _getJson('/api/obrigacoes-mensais');
    final list = m['items'];
    if (list is! List) return [];
    return list
        .whereType<Map>()
        .map((e) => Map<String, dynamic>.from(e))
        .toList();
  }

  Future<Map<String, dynamic>> salvarObrigacaoMensal(
    Map<String, dynamic> body,
  ) =>
      _postJson('/api/obrigacoes-mensais', body);

  Future<bool> removerObrigacaoMensal(int id) async {
    final m = await _postJson('/api/obrigacoes-mensais/$id/remover', {});
    return m['ok'] == true;
  }

  Future<Map<String, dynamic>> gerarObrigacoesMensais() =>
      _postJson('/api/obrigacoes-mensais/gerar', {});

  Future<Map<String, dynamic>> financeiroResumo() =>
      _getJson('/api/financeiro/resumo');

  Future<Map<String, dynamic>> tesourariaSemanal() =>
      _getJson('/api/financeiro/tesouraria-semanal');

  Future<Map<String, dynamic>> obterDashboardResumo({
    DateTime? dia,
    int? vendedorId,
  }) {
    final d = dia ?? DateTime.now();
    final diaLocal =
        '${d.year.toString().padLeft(4, '0')}-'
        '${d.month.toString().padLeft(2, '0')}-'
        '${d.day.toString().padLeft(2, '0')}';
    return _getJson('/api/dashboard/resumo', query: {
      'dia': diaLocal,
      if (vendedorId != null) 'vendedorId': '$vendedorId',
    });
  }

  /// Snapshot do painel Loja ao vivo (filtrado pelas permissoes do login).
  Future<Map<String, dynamic>> obterLojaAoVivo({required String login}) =>
      _getJson('/api/loja-ao-vivo', query: {
        'login': login.trim(),
      });

  Future<List<Map<String, dynamic>>> listarMetasVendedores({DateTime? dia}) async {
    final d = dia ?? DateTime.now();
    final m = await _getJson('/api/relatorios/metas-vendedores', query: {
      'dia':
          '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}',
    });
    final list = m['items'];
    if (list is! List) return [];
    return list
        .whereType<Map>()
        .map((e) => Map<String, dynamic>.from(e))
        .toList();
  }

  Future<List<Map<String, dynamic>>> listarSugestoesVendaRanking({
    DateTime? desde,
    DateTime? ate,
    int limit = 200,
  }) async {
    final m = await _getJson('/api/relatorios/sugestoes-venda', query: {
      if (desde != null) 'desde': desde.toUtc().toIso8601String(),
      if (ate != null) 'ate': ate.toUtc().toIso8601String(),
      'limit': '$limit',
    });
    final list = m['items'];
    if (list is! List) return [];
    return list
        .whereType<Map>()
        .map((e) => Map<String, dynamic>.from(e))
        .toList();
  }

  Future<List<Map<String, dynamic>>> listarAuditoria({
    DateTime? desde,
    DateTime? ate,
    int limit = 500,
  }) async {
    final m = await _getJson('/api/auditoria', query: {
      if (desde != null) 'desde': desde.toUtc().toIso8601String(),
      if (ate != null) 'ate': ate.toUtc().toIso8601String(),
      'limit': '$limit',
    });
    final list = m['items'];
    if (list is! List) return [];
    return list
        .whereType<Map>()
        .map((e) => Map<String, dynamic>.from(e))
        .toList();
  }

  Future<Map<String, dynamic>> obterDiagnosticoEstoque() =>
      _getJson('/api/estoque/diagnostico');

  /// Meta leve do catalogo (revisao) para o Terminal Leve detectar desatualizacao.
  Future<Map<String, dynamic>> obterCatalogoProdutoMeta() =>
      _getJson('/api/produtos/catalogo-meta');

  Future<Map<String, dynamic>> obterLoteFefoProduto(int produtoId) =>
      _getJson('/api/estoque/lotes/fefo/$produtoId');

  Future<List<Map<String, dynamic>>> listarLotesEstoque({int produtoId = 0}) async {
    final m = await _getJson(
      '/api/estoque/lotes',
      query: {
        if (produtoId > 0) 'produtoId': '$produtoId',
      },
    );
    final list = m['items'];
    if (list is! List) return [];
    return list
        .whereType<Map>()
        .map((e) => Map<String, dynamic>.from(e))
        .toList();
  }

  Future<Map<String, dynamic>> contarLotesValidade() =>
      _getJson('/api/estoque/lotes/contagem');

  Future<Map<String, dynamic>> desativarLoteEstoque(int loteId) =>
      _postJson('/api/estoque/lotes/$loteId/desativar', const {});

  /// Ajuste manual de inventario no PC servidor (estoqueReal + kardex).
  Future<Map<String, dynamic>> ajustarEstoque({
    required int produtoId,
    required int quantidadeAjustada,
    required String motivo,
    String usuarioId = '',
    String usuarioLogin = '',
    String numeroLote = '',
    DateTime? dataValidade,
  }) =>
      _postJson('/api/estoque/ajuste', {
        'produtoId': produtoId,
        'quantidadeAjustada': quantidadeAjustada,
        'novaQuantidadeFisica': quantidadeAjustada,
        'motivo': motivo,
        if (usuarioId.trim().isNotEmpty) 'usuarioId': usuarioId.trim(),
        if (usuarioLogin.trim().isNotEmpty) 'usuarioLogin': usuarioLogin.trim(),
        if (usuarioId.trim().isEmpty && usuarioLogin.trim().isNotEmpty)
          'usuarioId': usuarioLogin.trim(),
        if (numeroLote.trim().isNotEmpty) 'numeroLote': numeroLote.trim(),
        if (dataValidade != null)
          'dataValidade': dataValidade.toUtc().toIso8601String(),
      });

  Future<Map<String, dynamic>> listarSessoesInventario() =>
      _getJson('/api/estoque/inventario');

  Future<Map<String, dynamic>> obterSessaoInventario(int id) =>
      _getJson('/api/estoque/inventario/$id');

  Future<Map<String, dynamic>> obterCategoriasInventario() =>
      _getJson('/api/estoque/inventario/categorias');

  Future<Map<String, dynamic>> contarProdutosInventario({
    String categoria = '',
    String subcategoria = '',
  }) =>
      _getJson('/api/estoque/inventario/contagem-filtro', query: {
        if (categoria.trim().isNotEmpty) 'categoria': categoria.trim(),
        if (subcategoria.trim().isNotEmpty) 'subcategoria': subcategoria.trim(),
      });

  Future<Map<String, dynamic>> criarSessaoInventario(
    Map<String, dynamic> body,
  ) =>
      _postJson('/api/estoque/inventario', body);

  Future<Map<String, dynamic>> listarItensInventario(
    int sessaoId, {
    String filtro = 'todos',
    String busca = '',
  }) =>
      _getJson('/api/estoque/inventario/$sessaoId/itens', query: {
        'filtro': filtro,
        if (busca.trim().isNotEmpty) 'q': busca.trim(),
      });

  Future<Map<String, dynamic>> contarItemInventario(
    int sessaoId, {
    required int itemId,
    required int quantidadeArmazenada,
    String usuarioLogin = '',
  }) =>
      _postJson('/api/estoque/inventario/$sessaoId/contar', {
        'itemId': itemId,
        'quantidadeArmazenada': quantidadeArmazenada,
        if (usuarioLogin.trim().isNotEmpty) 'usuarioLogin': usuarioLogin.trim(),
      });

  Future<Map<String, dynamic>> definirContagemCegaInventario(
    int sessaoId,
    bool contagemCega,
  ) =>
      _postJson('/api/estoque/inventario/$sessaoId/contagem-cega', {
        'contagemCega': contagemCega,
      });

  Future<Map<String, dynamic>> aplicarInventario(
    int sessaoId, {
    String usuarioLogin = '',
  }) =>
      _postJson('/api/estoque/inventario/$sessaoId/aplicar', {
        if (usuarioLogin.trim().isNotEmpty) 'usuarioLogin': usuarioLogin.trim(),
      });

  Future<Map<String, dynamic>> cancelarInventario(
    int sessaoId, {
    String usuarioLogin = '',
  }) =>
      _postJson('/api/estoque/inventario/$sessaoId/cancelar', {
        if (usuarioLogin.trim().isNotEmpty) 'usuarioLogin': usuarioLogin.trim(),
      });

  Future<List<Map<String, dynamic>>> listarPontoPedido({int dias = 60}) async {
    final m = await _getJson('/api/estoque/ponto-pedido', query: {
      'dias': '$dias',
    });
    final list = m['items'];
    if (list is! List) return [];
    return list
        .whereType<Map>()
        .map((e) => Map<String, dynamic>.from(e))
        .toList();
  }

  Future<List<Map<String, dynamic>>> listarSugestaoCompra({
    int diasPeriodo = 60,
    int diasCobertura = 30,
    bool apenasPrioritarios = true,
  }) async {
    final m = await _getJson('/api/estoque/sugestao-compra', query: {
      'diasPeriodo': '$diasPeriodo',
      'diasCobertura': '$diasCobertura',
      'apenasPrioritarios': '$apenasPrioritarios',
    });
    final list = m['items'];
    if (list is! List) return [];
    return list
        .whereType<Map>()
        .map((e) => Map<String, dynamic>.from(e))
        .toList();
  }

  Future<void> reprocessarBaixaEstoque({
    required int vendaId,
    bool permitirVendaSemEstoque = true,
  }) async {
    await _postJson('/api/estoque/reprocessar-baixa', {
      'vendaId': vendaId,
      'permitirVendaSemEstoque': permitirVendaSemEstoque,
    });
  }

  Future<List<Map<String, dynamic>>> listarReajustes({int limit = 100}) async {
    final m = await _getJson('/api/produtos/reajustes', query: {
      'limit': '$limit',
    });
    final list = m['items'];
    if (list is! List) return [];
    return list
        .whereType<Map>()
        .map((e) => Map<String, dynamic>.from(e))
        .toList();
  }

  Future<List<Map<String, dynamic>>> listarItensReajuste(int reajusteId) async {
    final m = await _getJson('/api/produtos/reajustes/$reajusteId/itens');
    final list = m['items'];
    if (list is! List) return [];
    return list
        .whereType<Map>()
        .map((e) => Map<String, dynamic>.from(e))
        .toList();
  }

  Future<Map<String, dynamic>> aplicarReajusteLote(
    Map<String, dynamic> body,
  ) =>
      _postJson(
        '/api/produtos/reajuste-lote',
        body,
        // Lotes grandes (milhares de SKUs) podem ultrapassar o timeout de escrita.
        timeout: const Duration(minutes: 3),
      );

  Future<Map<String, dynamic>> estornarReajuste(
    int reajusteId,
    Map<String, dynamic> body,
  ) =>
      _postJson(
        '/api/produtos/reajustes/$reajusteId/estornar',
        body,
        timeout: const Duration(minutes: 3),
      );

  Future<bool> verificarChaveNfe(String chaveAcesso) async {
    final m = await _postJson('/api/nfe-entrada/verificar-chave', {
      'chaveAcesso': chaveAcesso,
    });
    return m['jaImportada'] == true;
  }

  Future<Map<String, dynamic>> prepararNfeEntrada(String xml) =>
      _postJson(
        '/api/nfe/ler-xml',
        {'xml': xml},
        timeout: timeoutFiscal,
      );

  Future<Map<String, dynamic>> confirmarNfeEntrada(Map<String, dynamic> body) =>
      _postJson(
        '/api/nfe/processar-entrada',
        body,
        timeout: timeoutFiscal,
      );

  Future<Map<String, dynamic>> solicitarDevolucaoFornecedor(
    int importacaoId,
    Map<String, dynamic> body,
  ) =>
      _postJson(
        '/api/nfe-entrada/$importacaoId/solicitar-devolucao',
        body,
        timeout: timeoutFiscal,
        aceitarErroJson: true,
      );

  Future<Map<String, dynamic>> atualizarCamposEntrega(
    int vendaId,
    Map<String, dynamic> campos,
  ) =>
      _postJson('/api/entregas/$vendaId/campos', campos);

  Future<Map<String, dynamic>> liberarSaidaCarreto({
    required int vendaId,
    String usuario = '',
    bool incluirGrupo = true,
  }) =>
      _postJson('/api/entregas/$vendaId/liberar-saida', {
        'usuario': usuario,
        'incluirGrupo': incluirGrupo,
      });

  Future<Map<String, dynamic>> atualizarBuscarNaLoja({
    required int vendaId,
    required String acao,
    required List<int> itemIds,
    String usuario = '',
    Map<int, int>? quantidadePorItem,
  }) {
    final body = <String, dynamic>{
      'acao': acao,
      'itemIds': itemIds,
      'usuario': usuario,
    };
    if (quantidadePorItem != null && quantidadePorItem.isNotEmpty) {
      body['quantidades'] = {
        for (final e in quantidadePorItem.entries) '${e.key}': e.value,
      };
    }
    return _postJson('/api/entregas/$vendaId/buscar-na-loja', body);
  }

  Future<Map<String, dynamic>> listarLojasOrigemEntrega() =>
      _getJson('/api/entregas/lojas-origem');

  Future<Map<String, dynamic>> definirGrupoEntrega({
    required List<int> ids,
    String motoristaEntrega = '',
  }) =>
      _postJson('/api/entregas/grupo', {
        'ids': ids,
        'motoristaEntrega': motoristaEntrega,
      });

  Future<Map<String, dynamic>> limparGrupoEntrega({
    required List<int> ids,
  }) =>
      _postJson('/api/entregas/grupo/limpar', {'ids': ids});

  Future<Map<String, dynamic>> definirMotoristaGrupoEntrega({
    required int grupoId,
    required String motoristaEntrega,
  }) =>
      _postJson('/api/entregas/grupo/motorista', {
        'grupoId': grupoId,
        'motoristaEntrega': motoristaEntrega,
      });

  Future<Map<String, dynamic>> atualizarSequenciaGrupoEntrega({
    required int grupoId,
    required List<int> ids,
  }) =>
      _postJson('/api/entregas/grupo/sequencia', {
        'grupoId': grupoId,
        'ids': ids,
      });

  Future<Map<String, dynamic>> atualizarSequenciaMotoristaEntrega({
    required String motoristaEntrega,
    required List<int> ids,
  }) =>
      _postJson('/api/entregas/motorista/sequencia', {
        'motoristaEntrega': motoristaEntrega,
        'ids': ids,
      });

  Future<List<Map<String, dynamic>>> listarHistoricoEntregaPorVenda(
    int vendaId,
  ) async {
    final m = await _getJson('/api/entregas/$vendaId/historico');
    final list = m['items'];
    if (list is! List) return [];
    return list
        .whereType<Map>()
        .map((e) => Map<String, dynamic>.from(e))
        .toList();
  }

  Future<Map<String, dynamic>> obterConferenciaCarga(String escopo) =>
      _getJson('/api/entregas/conferencia', query: {'escopo': escopo});

  Future<Map<String, dynamic>> salvarConferenciaCarga({
    required String escopoViagem,
    required String chaveProduto,
    required bool conferido,
    String usuarioLogin = '',
  }) =>
      _postJson('/api/entregas/conferencia', {
        'escopoViagem': escopoViagem,
        'chaveProduto': chaveProduto,
        'conferido': conferido,
        'usuarioLogin': usuarioLogin,
      });

  Future<List<Map<String, dynamic>>> listarMovimentosEstoque({
    int? produtoId,
    DateTime? desde,
    DateTime? ate,
    int limit = 200,
  }) async {
    final m = await _getJson('/api/estoque/movimentos', query: {
      if (produtoId != null && produtoId > 0) 'produtoId': '$produtoId',
      if (desde != null) 'desde': desde.toUtc().toIso8601String(),
      if (ate != null) 'ate': ate.toUtc().toIso8601String(),
      'limit': '$limit',
    });
    final list = m['items'];
    if (list is! List) return [];
    return list
        .whereType<Map>()
        .map((e) => Map<String, dynamic>.from(e))
        .toList();
  }

  Future<List<Map<String, dynamic>>> listarListaCompra() async {
    final m = await _getJson('/api/lista-compra');
    final list = m['items'];
    if (list is! List) return [];
    return list
        .whereType<Map>()
        .map((e) => Map<String, dynamic>.from(e))
        .toList();
  }

  Future<Map<String, dynamic>> salvarListaCompra(Map<String, dynamic> body) =>
      _postJson('/api/lista-compra', body);

  Future<List<Map<String, dynamic>>> listarRecados() async {
    final m = await _getJson('/api/recados');
    final list = m['items'];
    if (list is! List) return [];
    return list
        .whereType<Map>()
        .map((e) => Map<String, dynamic>.from(e))
        .toList();
  }

  Future<List<Map<String, dynamic>>> listarRecadosNaoLidos({
    required String login,
  }) async {
    final m = await _getJson('/api/recados/nao-lidos', query: {
      'login': login.trim(),
    });
    final list = m['items'];
    if (list is! List) return [];
    return list
        .whereType<Map>()
        .map((e) => Map<String, dynamic>.from(e))
        .toList();
  }

  Future<Map<String, dynamic>> criarRecado(Map<String, dynamic> body) =>
      _postJson('/api/recados', body);

  Future<Map<String, dynamic>> marcarRecadoLido(
    int id, {
    required String login,
  }) =>
      _postJson('/api/recados/$id/lido', {'login': login});

  Future<Map<String, dynamic>> arquivarRecado(int id) =>
      _postJson('/api/recados/$id/arquivar', {});

  Future<List<MensagemInterna>> chatHistorico() async {
    final m = await _getJson('/api/chat/historico');
    final list = m['items'];
    if (list is! List) return [];
    return list
        .whereType<Map>()
        .map((e) => MensagemInterna.fromMap(Map<String, dynamic>.from(e)))
        .toList();
  }

  Future<MensagemInterna> chatEnviar({
    required String vendedor,
    required String texto,
    String clientId = '',
  }) async {
    final m = await _postJson('/api/chat/enviar', {
      'vendedor': vendedor,
      'texto': texto,
      if (clientId.trim().isNotEmpty) 'clientId': clientId.trim(),
    });
    final item = m['item'];
    if (item is Map) {
      return MensagemInterna.fromMap(Map<String, dynamic>.from(item));
    }
    throw LanApiException('Resposta invalida ao enviar recado do chat.');
  }

  Future<Map<String, dynamic>> apagarRecadosArquivados() =>
      _postJson('/api/recados/arquivados/apagar', {});

  Future<List<Map<String, dynamic>>> listarFuncionarios() async {
    final m = await _getJson('/api/funcionarios');
    final list = m['items'];
    if (list is! List) return [];
    return list
        .whereType<Map>()
        .map((e) => Map<String, dynamic>.from(e))
        .toList();
  }

  Future<int> salvarFuncionario(Map<String, dynamic> body) async {
    final m = await _postJson('/api/funcionarios/salvar', body);
    return (m['id'] as num?)?.toInt() ?? 0;
  }

  Future<List<Map<String, dynamic>>> listarLancamentosRh({
    int? funcionarioId,
  }) async {
    final m = await _getJson('/api/lancamentos-rh', query: {
      if (funcionarioId != null) 'funcionarioId': '$funcionarioId',
    });
    final list = m['items'];
    if (list is! List) return [];
    return list
        .whereType<Map>()
        .map((e) => Map<String, dynamic>.from(e))
        .toList();
  }

  Future<int> salvarLancamentoRh(Map<String, dynamic> body) async {
    final m = await _postJson('/api/lancamentos-rh', body);
    return (m['id'] as num?)?.toInt() ?? 0;
  }

  Future<void> estornarLancamentoRh(int id) async {
    await _postJson('/api/lancamentos-rh/$id/estornar', {});
  }

  Future<List<Map<String, dynamic>>> listarMotoristas() async {
    final m = await _getJson('/api/motoristas');
    final list = m['items'];
    if (list is! List) return [];
    return list
        .whereType<Map>()
        .map((e) => Map<String, dynamic>.from(e))
        .toList();
  }

  Future<int> salvarMotorista(Map<String, dynamic> body) async {
    final m = await _postJson('/api/motoristas/salvar', body);
    return (m['id'] as num?)?.toInt() ?? 0;
  }

  Future<List<Map<String, dynamic>>> listarKits() async {
    final m = await _getJson('/api/kits');
    final list = m['items'];
    if (list is! List) return [];
    return list
        .whereType<Map>()
        .map((e) => Map<String, dynamic>.from(e))
        .toList();
  }

  Future<Map<String, dynamic>> salvarKit(Map<String, dynamic> body) =>
      _postJson('/api/kits/salvar', body);

  Future<bool> removerKit(int id) async {
    final m = await _postJson('/api/kits/$id/remover', {});
    return m['ok'] == true;
  }

  Future<List<Map<String, dynamic>>> listarPromocoes() async {
    final m = await _getJson('/api/promocoes');
    final list = m['items'];
    if (list is! List) return [];
    return list
        .whereType<Map>()
        .map((e) => Map<String, dynamic>.from(e))
        .toList();
  }

  Future<Map<String, dynamic>> salvarPromocao(Map<String, dynamic> body) =>
      _postJson('/api/promocoes/salvar', body);

  Future<bool> removerPromocao(int id) async {
    final m = await _postJson('/api/promocoes/$id/remover', {});
    return m['ok'] == true;
  }

  Future<Map<String, dynamic>> alterarStatusPromocao(
    int id, {
    bool? ativa,
  }) =>
      _postJson('/api/promocoes/$id/status', {
        if (ativa != null) 'ativa': ativa,
      });

  Future<List<Map<String, dynamic>>> listarNfeEntrada({
    String q = '',
    String tipoData = 'importacao',
    DateTime? periodoInicio,
    DateTime? periodoFim,
    String ordenacao = 'importacaoDesc',
  }) async {
    final m = await listarNfeImportadas(
      q: q,
      tipoData: tipoData,
      periodoInicio: periodoInicio,
      periodoFim: periodoFim,
      ordenacao: ordenacao,
    );
    final list = m['items'];
    if (list is! List) return [];
    return list
        .whereType<Map>()
        .map((e) => Map<String, dynamic>.from(e))
        .toList();
  }

  /// Listagem filtrada + meta dos cards (`GET /api/nfe-importadas`).
  Future<Map<String, dynamic>> listarNfeImportadas({
    String q = '',
    String tipoData = 'importacao',
    DateTime? periodoInicio,
    DateTime? periodoFim,
    String ordenacao = 'importacaoDesc',
  }) async {
    return _getJson(
      '/api/nfe-importadas',
      query: {
        if (q.trim().isNotEmpty) 'q': q.trim(),
        'tipoData': tipoData,
        if (periodoInicio != null)
          'periodoInicio': periodoInicio.toUtc().toIso8601String(),
        if (periodoFim != null)
          'periodoFim': periodoFim.toUtc().toIso8601String(),
        'ordenacao': ordenacao,
      },
      timeout: timeoutFiscal,
    );
  }

  Future<Map<String, dynamic>> obterNfeImportadaDetalhe(int id) =>
      _getJson('/api/nfe-importadas/$id', timeout: timeoutFiscal);

  Future<({List<int> bytes, String? filename})> baixarXmlNfeImportada(int id) =>
      _getBytes('/api/nfe-importadas/$id/xml', timeout: timeoutFiscal);

  Future<Map<String, dynamic>> obterLinhasDevolucaoFornecedor(int id) =>
      _getJson(
        '/api/nfe-importadas/$id/devolucao-linhas',
        timeout: timeoutFiscal,
      );

  Future<Map<String, dynamic>> emitirDevolucaoFornecedor(
    int id,
    Map<String, dynamic> body,
  ) =>
      _postJson(
        '/api/nfe-importadas/$id/emitir-devolucao-fornecedor',
        body,
        timeout: timeoutFiscal,
        aceitarErroJson: true,
      );

  Future<Map<String, dynamic>> reconsultarDevolucaoFornecedor(
    String referencia,
  ) =>
      _postJson(
        '/api/nfe-importadas/reconsultar-devolucao-fornecedor',
        {'referencia': referencia},
        timeout: timeoutFiscal,
        aceitarErroJson: true,
      );

  Future<Map<String, dynamic>> reconsultarDevolucaoFornecedorProcessando() =>
      _postJson(
        '/api/nfe-importadas/reconsultar-devolucao-fornecedor-processando',
        {},
        timeout: timeoutFiscal,
        aceitarErroJson: true,
      );

  Future<Map<String, dynamic>> validarEstornoNfeImportada(int id) =>
      _getJson(
        '/api/nfe-importadas/$id/validar-estorno',
        timeout: timeoutFiscal,
      );

  Future<Map<String, dynamic>> estornarNfeImportada(int id) => _postJson(
        '/api/nfe-importadas/$id/estornar',
        {},
        timeout: timeoutFiscal,
        aceitarErroJson: true,
      );

  /// Registros de devolucao/troca com impactos ja calculados pelo servidor.
  Future<List<Map<String, dynamic>>> listarDevolucoes({
    DateTime? desde,
    DateTime? ate,
  }) async {
    final m = await _getJson('/api/devolucoes', query: {
      if (desde != null) 'desde': desde.toUtc().toIso8601String(),
      if (ate != null) 'ate': ate.toUtc().toIso8601String(),
    });
    final list = m['items'];
    if (list is! List) return [];
    return list
        .whereType<Map>()
        .map((e) => Map<String, dynamic>.from(e))
        .toList();
  }

  Future<List<Map<String, dynamic>>> listarHistoricoEntregas({
    DateTime? desde,
    DateTime? ate,
    String termo = '',
  }) async {
    final m = await _getJson('/api/entregas/historico', query: {
      if (desde != null) 'desde': desde.toUtc().toIso8601String(),
      if (ate != null) 'ate': ate.toUtc().toIso8601String(),
      if (termo.trim().isNotEmpty) 'termo': termo.trim(),
    });
    final list = m['items'];
    if (list is! List) return [];
    return list
        .whereType<Map>()
        .map((e) => Map<String, dynamic>.from(e))
        .toList();
  }

  Future<Map<String, dynamic>> listarPendenciasFiscaisMap() =>
      _getJson('/api/fiscal/pendencias', timeout: timeoutFiscal);

  /// Compat: so a fila "NFC-e a emitir".
  Future<List<Venda>> listarPendenciasFiscais() async {
    final m = await listarPendenciasFiscaisMap();
    final list = m['pendentesEmissao'] ?? m['items'];
    return _vendasDeLista(list);
  }

  Future<Map<String, dynamic>> reconsultarNfce(int vendaId) => _postJson(
        '/api/vendas/$vendaId/reconsultar-nfce',
        {},
        timeout: timeoutFiscal,
        aceitarErroJson: true,
      );

  Future<Map<String, dynamic>> reconsultarTodasNfce() => _postJson(
        '/api/fiscal/nfce/reconsultar-todas',
        {},
        timeout: timeoutFiscal,
        aceitarErroJson: true,
      );

  Future<int> salvarVendedor(Map<String, dynamic> body) async {
    final m = await _postJson('/api/vendedores', body);
    return (m['id'] as num?)?.toInt() ?? 0;
  }

  /// Valida PIN do balcao no PC servidor. Retorna null se invalido/ambiguo.
  Future<Vendedor?> autenticarVendedorPin(String pin) async {
    final m = await _postJson('/api/vendedores/autenticar-pin', {
      'pin': pin.trim(),
    });
    if (m['ok'] != true) return null;
    final raw = m['vendedor'];
    if (raw is! Map) return null;
    return SyncEntityCodec.vendedorDeMap(Map<String, dynamic>.from(raw));
  }

  Future<Venda?> buscarOrcamentoPorNumero(int numero) async {
    final m = await _getJson(
      '/api/orcamentos/por-numero',
      query: {'n': '$numero'},
    );
    final item = m['item'];
    if (item is! Map) return null;
    return vendaCompletaDeMap(Map<String, dynamic>.from(item));
  }

  // --- Caixa (sessoes compartilhadas) ---

  Future<Map<String, dynamic>> listarCaixaSessoes() =>
      _getJson('/api/caixa/sessoes');

  Future<Map<String, dynamic>> sessaoAtivaCaixa({String? terminalId}) =>
      _getJson(
        '/api/caixa/sessao-ativa',
        query: {
          if (terminalId != null && terminalId.trim().isNotEmpty)
            'terminalId': terminalId.trim(),
        },
      );

  Future<Map<String, dynamic>> abrirCaixaSessao({
    required String terminalId,
    required String operador,
    double fundoTroco = 0,
  }) =>
      _postJson(
        '/api/caixa/sessoes/abrir',
        {
          'terminalId': terminalId,
          'operador': operador,
          'fundoTroco': fundoTroco,
        },
        aceitarErroJson: true,
      );

  Future<Map<String, dynamic>> fecharCaixaSessao({
    required String terminalId,
    bool forcar = false,
  }) =>
      _postJson(
        '/api/caixa/sessoes/fechar',
        {
          'terminalId': terminalId,
          'forcar': forcar,
        },
        aceitarErroJson: true,
      );

  Future<Map<String, dynamic>> resetCaixaSessoes({String motivo = 'reset_admin'}) =>
      _postJson(
        '/api/caixa/sessoes/reset',
        {'motivo': motivo},
        aceitarErroJson: true,
      );

  Future<Map<String, dynamic>> atualizarCaixaSessao({
    required String terminalId,
    String? operador,
    double? fundoTroco,
    double? suprimentos,
    double? sangrias,
  }) =>
      _postJson(
        '/api/caixa/sessoes/atualizar',
        {
          'terminalId': terminalId,
          if (operador != null) 'operador': operador,
          if (fundoTroco != null) 'fundoTroco': fundoTroco,
          if (suprimentos != null) 'suprimentos': suprimentos,
          if (sangrias != null) 'sangrias': sangrias,
        },
        aceitarErroJson: true,
      );

  Future<Map<String, dynamic>> movimentacaoCaixaSessao({
    required String terminalId,
    required String tipo,
    required double valor,
  }) =>
      _postJson(
        '/api/caixa/sessoes/movimentacao',
        {
          'terminalId': terminalId,
          'tipo': tipo,
          'valor': valor,
        },
        aceitarErroJson: true,
      );

  Future<Map<String, dynamic>> leituraParcialCaixa({String? terminalId}) =>
      _getJson(
        '/api/caixa/leitura-parcial',
        query: {
          if (terminalId != null && terminalId.trim().isNotEmpty)
            'terminalId': terminalId.trim(),
        },
      );

  Future<List<Map<String, dynamic>>> listarAuditoriaCaixa({
    String evento = '',
    int limit = 300,
  }) async {
    final m = await _getJson('/api/caixa/auditoria', query: {
      if (evento.trim().isNotEmpty) 'evento': evento.trim(),
      'limit': '$limit',
    });
    final list = m['items'];
    if (list is! List) return [];
    return list
        .whereType<Map>()
        .map((e) => Map<String, dynamic>.from(e))
        .toList();
  }

  Future<List<Map<String, dynamic>>> listarHistoricoFechamentoCaixa({
    int limit = 300,
  }) async {
    final m = await _getJson(
      '/api/relatorios/historico-fechamento-caixa',
      query: {'limit': '$limit'},
    );
    final list = m['items'];
    if (list is! List) return [];
    return list
        .whereType<Map>()
        .map((e) => Map<String, dynamic>.from(e))
        .toList();
  }

  Future<void> registrarAuditoriaCaixa({
    required String evento,
    String usuario = '',
    String operadorCaixa = '',
    Map<String, dynamic>? detalhes,
    DateTime? em,
  }) async {
    await _postJson('/api/caixa/auditoria', {
      'evento': evento,
      'usuario': usuario,
      'operadorCaixa': operadorCaixa,
      'em': (em ?? DateTime.now()).toIso8601String(),
      if (detalhes != null) 'detalhes': detalhes,
    });
  }

  Future<void> substituirAuditoriaCaixa(
    List<Map<String, dynamic>> items,
  ) async {
    await _postJson('/api/caixa/auditoria/substituir', {'items': items});
  }

  /// WebSocket de invalidacao: `{ type: entityChanged, entity: venda|produto|cliente }`.
  WebSocketChannel? abrirStream() {
    if (!configurado) return null;
    final base = Uri.parse(_base);
    final wsScheme = base.scheme == 'https' ? 'wss' : 'ws';
    final token = syncToken.trim();
    final ws = Uri(
      scheme: wsScheme,
      host: base.host,
      port: base.hasPort ? base.port : null,
      path: '/api/stream',
      queryParameters: {
        // Servidor exige token em /api/stream (mesmo middleware das rotas HTTP).
        SyncAuth.queryParam: token,
      },
    );
    return WebSocketChannel.connect(ws);
  }
}

/// Payload auxiliar para criar orcamento via API.
Map<String, dynamic> montarBodyOrcamentoApi({
  required List<Map<String, dynamic>> itens,
  required DadosPagamentoOrcamento pagamento,
  required Map<String, dynamic> entrega,
  int? clienteId,
  int? vendedorId,
  double descontoEmReais = 0,
  bool permitirVendaSemEstoque = false,
  String? uuidLocal,
}) {
  final key = (uuidLocal ?? '').trim();
  return {
    'itens': itens,
    'pagamento': {
      'formaPagamento': pagamento.formaPagamento,
      'quantidadeParcelas': pagamento.quantidadeParcelas,
      'linhasMisto': pagamento.linhasMisto?.map((e) => e.toJson()).toList(),
      'planoFiado': pagamento.planoFiado?.map((e) => e.toJson()).toList(),
    },
    'entrega': entrega,
    'clienteId': clienteId,
    'vendedorId': vendedorId,
    'descontoEmReais': descontoEmReais,
    'permitirVendaSemEstoque': permitirVendaSemEstoque,
    if (key.isNotEmpty) 'uuidLocal': key,
    if (key.isNotEmpty) 'idempotencyKey': key,
  };
}
