import 'dart:io';

import 'package:path/path.dart' as p;

import '../data/api/lan_api_event_hub.dart';
import '../data/app_config_repository.dart';
import 'configuracoes_service.dart';
import '../data/sync/sync_api_client.dart';
import '../domain/produto_imagem_nome_arquivo.dart';

/// Upload/download de fotos de produto via servidor LAN.
class ProdutoImagemLanService {
  ProdutoImagemLanService({
    required this.imagesDirectoryPath,
    AppConfigRepository? configRepository,
    SyncApiClient? apiClient,
  })  : _configRepository =
            configRepository ?? ConfiguracoesService.repositoryFallback(),
        _apiClientOverride = apiClient;

  final String imagesDirectoryPath;
  final AppConfigRepository _configRepository;
  final SyncApiClient? _apiClientOverride;

  static final Map<String, Future<String?>> _emAndamento = {};

  Future<SyncApiClient?> _clienteSync() async {
    if (_apiClientOverride != null) return _apiClientOverride;
    final config = await _configRepository.carregarEmpresaConfig();
    if (!config.redeSincronizacaoAtiva) return null;
    final url = config.redeServidorUrl.trim();
    if (url.isEmpty) return null;
    return SyncApiClient(baseUrl: url, syncToken: config.redeSyncToken);
  }

  /// Preferencia: API 8788 (terminais).
  Future<List<int>?> _baixarBytes(String nome) async {
    final lan = LanApiEventHub.instance.client;
    if (lan != null && lan.configurado) {
      final viaApi = await lan.downloadProdutoImagem(nome);
      if (viaApi != null && viaApi.isNotEmpty) return viaApi;
    }
    final sync = await _clienteSync();
    if (sync == null) return null;
    return sync.downloadProductImage(fileName: nome);
  }

  /// Resolve arquivo local (absoluto ou na pasta de imagens) ou baixa da rede.
  ///
  /// Se [baixarSeFaltar] for false, nao faz HTTP — so retorna path local se existir.
  Future<String?> resolverOuBaixar(
    String? fotoPath, {
    bool baixarSeFaltar = true,
  }) async {
    final raw = (fotoPath ?? '').trim();
    if (raw.isEmpty) return null;

    final local = _resolverLocal(raw);
    if (local != null) return local;
    if (!baixarSeFaltar) return null;

    final nome = ProdutoImagemNomeArquivo.extrairNomeParaLan(raw);
    if (nome == null) return null;

    final existente = _emAndamento[nome];
    if (existente != null) return existente;

    final future = _baixarArquivo(nome);
    _emAndamento[nome] = future;
    try {
      return await future;
    } finally {
      _emAndamento.remove(nome);
    }
  }

  /// Caminho local sincronamente (sem rede). Util para miniaturas de lista.
  String? resolverSomenteLocal(String? fotoPath) {
    final raw = (fotoPath ?? '').trim();
    if (raw.isEmpty) return null;
    return _resolverLocal(raw);
  }

  String? _resolverLocal(String raw) {
    // Caminho absoluto de outro SO (ex.: C:\... no Android) nunca existe aqui.
    if (_pareceCaminhoEstrangeiro(raw)) {
      final nome = ProdutoImagemNomeArquivo.extrairNomeParaLan(raw);
      if (nome == null) return null;
      if (imagesDirectoryPath.trim().isEmpty) return null;
      final rel = File(p.join(imagesDirectoryPath, nome));
      if (rel.existsSync()) return p.normalize(rel.path);
      return null;
    }

    final abs = File(p.normalize(raw));
    if (abs.existsSync()) return abs.path;

    final nome = ProdutoImagemNomeArquivo.extrairNomeParaLan(raw) ??
        p.basename(raw.replaceAll(r'\', '/'));
    if (nome.isEmpty || imagesDirectoryPath.trim().isEmpty) return null;
    final rel = File(p.join(imagesDirectoryPath, nome));
    if (rel.existsSync()) return p.normalize(rel.path);
    return null;
  }

  static bool _pareceCaminhoEstrangeiro(String raw) {
    final s = raw.trim();
    if (s.length >= 2 && s[1] == ':') return true; // C:\...
    if (s.startsWith(r'\\')) return true; // UNC Windows
    if (!Platform.isWindows && s.contains(r'\')) return true;
    return false;
  }

  Future<String?> _baixarArquivo(String nome) async {
    if (imagesDirectoryPath.trim().isEmpty) return null;
    final destino = p.join(imagesDirectoryPath, nome);
    if (File(destino).existsSync()) return p.normalize(destino);

    var bytes = await _baixarBytes(nome);
    // Uma retentativa curta (servidor ainda subindo / Wi-Fi oscilando).
    if (bytes == null || bytes.isEmpty) {
      await Future<void>.delayed(const Duration(milliseconds: 700));
      bytes = await _baixarBytes(nome);
    }
    if (bytes == null || bytes.isEmpty) return null;

    await Directory(imagesDirectoryPath).create(recursive: true);
    await File(destino).writeAsBytes(bytes, flush: true);
    return p.normalize(destino);
  }

  /// Resultado do download sob demanda (PDV).
  Future<({String? path, String? erro})> baixarComMotivo(String? fotoPath) async {
    final raw = (fotoPath ?? '').trim();
    if (raw.isEmpty) {
      return (path: null, erro: 'Produto sem foto cadastrada.');
    }
    final local = _resolverLocal(raw);
    if (local != null) return (path: local, erro: null);

    final nome = ProdutoImagemNomeArquivo.extrairNomeParaLan(raw);
    if (nome == null) {
      return (
        path: null,
        erro: 'Nome da foto invalido para a rede.',
      );
    }

    if (imagesDirectoryPath.trim().isEmpty) {
      return (
        path: null,
        erro: 'Pasta de cache de fotos nao configurada neste terminal.',
      );
    }

    final lan = LanApiEventHub.instance.client;
    final sync = lan != null && lan.configurado ? null : await _clienteSync();
    if ((lan == null || !lan.configurado) && sync == null) {
      return (
        path: null,
        erro: 'Sem conexao com o PC servidor para baixar a foto.',
      );
    }

    final path = await resolverOuBaixar(raw, baixarSeFaltar: true);
    if (path != null && path.isNotEmpty) {
      return (path: path, erro: null);
    }
    return (
      path: null,
      erro:
          'Foto nao encontrada no PC servidor. '
          'Confirme que o produto tem imagem no cadastro do servidor '
          'e que a API (porta 8788) esta ativa.',
    );
  }

  /// Envia foto local ao servidor (apos salvar produto no cadastro).
  Future<bool> enviarSeRedeAtiva(String? fotoPathLocal) async {
    final local = (fotoPathLocal ?? '').trim();
    if (local.isEmpty) return false;
    final arquivo = File(local);
    if (!arquivo.existsSync()) return false;

    final nome = ProdutoImagemNomeArquivo.extrairNomeParaLan(local);
    if (nome == null) return false;

    final bytes = await arquivo.readAsBytes();
    if (bytes.isEmpty) return false;

    // Preferencia: API 8788 (Terminal Leve).
    final lan = LanApiEventHub.instance.client;
    if (lan != null && lan.configurado) {
      try {
        final path = await lan.uploadProdutoImagem(
          fileName: nome,
          bytes: bytes,
        );
        if (path != null && path.isNotEmpty) return true;
      } catch (_) {}
    }

    final client = await _clienteSync();
    if (client == null) return false;
    final path = await client.uploadProductImage(
      fileName: nome,
      jpegBytes: bytes,
    );
    return path != null && path.isNotEmpty;
  }

  /// Publica fotos locais para o servidor LAN.
  ///
  /// No PC servidor: se a pasta do servidor for a mesma do app, nao precisa
  /// enviar nada (as fotos ja estao la). Se for outra pasta no mesmo PC, copia
  /// os arquivos no disco (evita falha do upload base64).
  Future<({int enviados, int ignorados, int falhas, String? detalhe})>
      publicarFotosNoServidor({
    int limitePorCiclo = 200,
    String? pastaServidorFallback,
  }) async {
    final dir = Directory(imagesDirectoryPath);
    if (!dir.existsSync()) {
      return (
        enviados: 0,
        ignorados: 0,
        falhas: 0,
        detalhe: 'Pasta local de fotos nao existe.',
      );
    }

    final arquivos = <File>[];
    try {
      for (final e in dir.listSync()) {
        if (e is! File) continue;
        final nome = p.basename(e.path);
        if (!ProdutoImagemNomeArquivo.validoParaLan(nome)) continue;
        arquivos.add(e);
      }
    } catch (e) {
      return (
        enviados: 0,
        ignorados: 0,
        falhas: 0,
        detalhe: 'Erro ao listar fotos: $e',
      );
    }
    if (arquivos.isEmpty) {
      return (
        enviados: 0,
        ignorados: 0,
        falhas: 0,
        detalhe: 'Nenhuma foto valida na pasta local.',
      );
    }

    final client = await _clienteSync();
    if (client == null) {
      return (
        enviados: 0,
        ignorados: 0,
        falhas: 0,
        detalhe: 'Rede desligada ou sem URL do servidor.',
      );
    }

    final meta = await client.obterMeta();
    var pastaServidor = (meta?['productImagesPath'] ?? '').toString().trim();
    if (pastaServidor.isEmpty) {
      pastaServidor = (pastaServidorFallback ?? '').trim();
    }
    final pastaLocal = p.normalize(Directory(imagesDirectoryPath).absolute.path);

    if (pastaServidor.isNotEmpty) {
      final pastaSrv = p.normalize(Directory(pastaServidor).absolute.path);
      if (_mesmaPasta(pastaLocal, pastaSrv)) {
        return (
          enviados: 0,
          ignorados: arquivos.length,
          falhas: 0,
          detalhe:
              '${arquivos.length} foto(s) ja estao na pasta do servidor. '
              'Reinicie o servidor pelo app e no celular toque em ver foto.',
        );
      }

      if (Platform.isWindows) {
        try {
          final destDir = Directory(pastaSrv);
          if (!destDir.existsSync()) destDir.createSync(recursive: true);
          var copiados = 0;
          var iguais = 0;
          var falhas = 0;
          for (final arq in arquivos.take(limitePorCiclo)) {
            final nome = p.basename(arq.path);
            final dest = File(p.join(pastaSrv, nome));
            try {
              if (dest.existsSync() && dest.lengthSync() == arq.lengthSync()) {
                iguais++;
                continue;
              }
              await arq.copy(dest.path);
              copiados++;
            } catch (_) {
              falhas++;
            }
          }
          return (
            enviados: copiados,
            ignorados: iguais,
            falhas: falhas,
            detalhe: falhas == 0
                ? 'Fotos copiadas para a pasta do servidor.'
                : 'Copia parcial ($falhas falha(s)).',
          );
        } catch (e) {
          // Segue para HTTP.
        }
      }
    }

    limparCacheEnviosSessao();
    String? primeiroErro;
    final r = await enviarFotosLocaisPendentes(
      arquivos.map((f) => f.path),
      limitePorCiclo: limitePorCiclo,
      onPrimeiroErro: (m) => primeiroErro ??= m,
    );
    return (
      enviados: r.enviados,
      ignorados: r.ignorados,
      falhas: r.falhas,
      detalhe: primeiroErro ??
          (r.falhas > 0
              ? 'Upload HTTP falhou em ${r.falhas} arquivo(s).'
              : null),
    );
  }

  static bool _mesmaPasta(String a, String b) {
    final na = a.replaceAll('/', r'\').toLowerCase().trim();
    final nb = b.replaceAll('/', r'\').toLowerCase().trim();
    return na == nb;
  }

  /// Sobe fotos que existem nesta maquina para o servidor LAN.
  Future<({int enviados, int ignorados, int falhas})> enviarFotosLocaisPendentes(
    Iterable<String> fotoPaths, {
    int limitePorCiclo = 60,
    void Function(String motivo)? onPrimeiroErro,
  }) async {
    final client = await _clienteSync();
    if (client == null) {
      onPrimeiroErro?.call('Rede desligada ou sem URL do servidor.');
      return (enviados: 0, ignorados: 0, falhas: 0);
    }

    final nomesUnicos = <String>{};
    for (final raw in fotoPaths) {
      final nome = ProdutoImagemNomeArquivo.extrairNomeParaLan(raw);
      if (nome != null) nomesUnicos.add(nome);
    }
    if (nomesUnicos.isEmpty) {
      return (enviados: 0, ignorados: 0, falhas: 0);
    }

    var enviados = 0;
    var ignorados = 0;
    var falhas = 0;
    var processados = 0;

    for (final nome in nomesUnicos) {
      if (processados >= limitePorCiclo) break;
      processados++;
      if (_enviadosNestaSessao.contains(nome)) {
        ignorados++;
        continue;
      }

      final local = _resolverLocal(nome) ??
          _resolverLocal(p.join(imagesDirectoryPath, nome));
      if (local == null) {
        ignorados++;
        continue;
      }

      try {
        final bytes = await File(local).readAsBytes();
        if (bytes.isEmpty) {
          falhas++;
          onPrimeiroErro?.call('Arquivo vazio: $nome');
          continue;
        }
        if (bytes.length > 5 * 1024 * 1024) {
          falhas++;
          onPrimeiroErro?.call('Arquivo muito grande (>5MB): $nome');
          continue;
        }
        final ok = await client.uploadProductImage(
          fileName: nome,
          jpegBytes: bytes,
          onErro: onPrimeiroErro,
        );
        if (ok != null && ok.isNotEmpty) {
          _enviadosNestaSessao.add(nome);
          enviados++;
        } else {
          falhas++;
        }
      } catch (e) {
        falhas++;
        onPrimeiroErro?.call('$e');
      }
    }

    return (enviados: enviados, ignorados: ignorados, falhas: falhas);
  }

  static final Set<String> _enviadosNestaSessao = {};

  /// Limpa marca de "ja enviado" (forca reenvio ao servidor).
  static void limparCacheEnviosSessao() => _enviadosNestaSessao.clear();

  /// Baixa fotos referenciadas que ainda nao existem nesta maquina.
  Future<int> prefetchFotosFaltantes(
    Iterable<String> fotoPaths, {
    int limitePorCiclo = 40,
  }) async {
    final nomes = <String>{};
    for (final raw in fotoPaths) {
      final nome = ProdutoImagemNomeArquivo.extrairNomeParaLan(raw);
      if (nome == null) continue;
      if (_resolverLocal(nome) != null ||
          _resolverLocal(p.join(imagesDirectoryPath, nome)) != null) {
        continue;
      }
      nomes.add(nome);
    }
    if (nomes.isEmpty) return 0;

    var ok = 0;
    for (final nome in nomes.take(limitePorCiclo)) {
      final path = await resolverOuBaixar(nome);
      if (path != null && path.isNotEmpty) ok++;
    }
    return ok;
  }

  /// Envia todos os arquivos de imagem da pasta local ao servidor.
  Future<({int enviados, int ignorados, int falhas})>
      enviarPastaLocalCompleta({int limitePorCiclo = 80}) async {
    final r = await publicarFotosNoServidor(limitePorCiclo: limitePorCiclo);
    return (
      enviados: r.enviados,
      ignorados: r.ignorados,
      falhas: r.falhas,
    );
  }
}
