import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import '../data/app_config_repository.dart';
import '../data/sync/sync_api_client.dart';
import '../domain/entrega_pod_nome_arquivo.dart';
import '../services/entrega_pod_paths.dart';

/// Upload/download de fotos POD via servidor LAN (fase 2).
class EntregaPodLanService {
  EntregaPodLanService({
    required AppConfigRepository configRepository,
    SyncApiClient? apiClient,
  })  : _configRepository = configRepository,
        _apiClientOverride = apiClient;

  final AppConfigRepository _configRepository;
  final SyncApiClient? _apiClientOverride;

  Future<SyncApiClient?> _cliente() async {
    if (_apiClientOverride != null) return _apiClientOverride;
    final config = await _configRepository.carregarEmpresaConfig();
    if (!config.redeSincronizacaoAtiva) return null;
    final url = config.redeServidorUrl.trim();
    if (url.isEmpty) return null;
    return SyncApiClient(baseUrl: url, syncToken: config.redeSyncToken);
  }

  /// Envia JPEG para o PC servidor se a rede sync estiver ativa.
  Future<String?> enviarFotoSeRedeAtiva({
    required String arquivoLocal,
    String? nomeArquivo,
  }) async {
    final arquivo = File(arquivoLocal);
    if (!arquivo.existsSync()) return null;

    final nome = nomeArquivo ??
        EntregaPodNomeArquivo.extrairNomeArquivo(arquivoLocal) ??
        p.basename(arquivoLocal);
    if (!EntregaPodNomeArquivo.valido(nome)) return null;

    final client = await _cliente();
    if (client == null) return null;

    final bytes = await arquivo.readAsBytes();
    final path = await client.uploadPodFoto(
      fileName: nome,
      jpegBytes: bytes,
    );
    return path ?? '${EntregaPodPaths.subpastaServidor}/$nome';
  }

  /// Baixa foto do servidor para cache local e retorna o caminho.
  Future<String?> baixarParaCache({
    required String podFotoPathServidor,
    String? podFotoPathLocal,
  }) async {
    final local = podFotoPathLocal?.trim() ?? '';
    if (local.isNotEmpty) {
      final f = File(local);
      if (f.existsSync()) return local;
    }

    final nome = EntregaPodNomeArquivo.extrairNomeArquivo(podFotoPathServidor);
    if (nome == null) return null;

    final cacheDir = await EntregaPodPaths.diretorioCache();
    final destino = p.join(cacheDir.path, nome);
    if (File(destino).existsSync()) return destino;

    final client = await _cliente();
    if (client == null) return null;

    final bytes = await client.downloadPodFoto(fileName: nome);
    if (bytes == null || bytes.isEmpty) return null;

    await File(destino).writeAsBytes(bytes, flush: true);
    return destino;
  }
}
