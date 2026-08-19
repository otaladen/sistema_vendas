import 'dart:io';

import 'package:path/path.dart' as p;

import '../data/api/lan_api_client.dart';
import '../data/api/lan_api_event_hub.dart';
import '../domain/entrega_pod_nome_arquivo.dart';
import 'entrega_pod_paths.dart';

/// Upload/download de fotos POD pela API LAN do PC1 (`:8788`), via Tailscale.
class EntregaPodLanService {
  EntregaPodLanService({
    LanApiClient? lanClient,
  }) : _lanClient = lanClient;

  final LanApiClient? _lanClient;

  LanApiClient? get _lan =>
      _lanClient ?? LanApiEventHub.instance.client;

  /// Envia JPEG para o PC servidor pela LAN. Null se rede/arquivo indisponivel.
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

    final client = _lan;
    if (client == null || !client.configurado) return null;

    final bytes = await arquivo.readAsBytes();
    if (bytes.isEmpty) return null;
    return client.uploadPodFoto(fileName: nome, jpegBytes: bytes);
  }

  /// Resolve foto local, pasta do PC1 ou download LAN para cache.
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

    final noServidor = EntregaPodPaths.arquivoServidorDe(nome);
    if (noServidor != null && noServidor.existsSync()) {
      return noServidor.path;
    }

    final cacheDir = await EntregaPodPaths.diretorioCache();
    final destino = p.join(cacheDir.path, nome);
    if (File(destino).existsSync()) return destino;

    final client = _lan;
    if (client == null || !client.configurado) return null;

    final bytes = await client.downloadPodFoto(fileName: nome);
    if (bytes == null || bytes.isEmpty) return null;

    await File(destino).writeAsBytes(bytes, flush: true);
    return destino;
  }
}
