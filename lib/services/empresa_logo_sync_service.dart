import 'dart:io';
import 'dart:typed_data';

import '../data/api/lan_api_client.dart';
import '../data/api/lan_api_event_hub.dart';
import '../data/app_config_repository.dart';
import 'configuracoes_service.dart';
import 'empresa_logo_service.dart';

/// Baixa ou publica a logomarca via `/api/empresa/logo`.
class EmpresaLogoSyncService {
  EmpresaLogoSyncService({
    AppConfigRepository? configRepository,
  }) : _configRepository =
            configRepository ?? ConfiguracoesService.repositoryFallback();

  final AppConfigRepository _configRepository;

  static final Map<String, Future<void>> _emAndamento = {};

  LanApiClient? _cliente() {
    final hub = LanApiEventHub.instance.client;
    if (hub != null && hub.configurado) return hub;
    final g = ConfiguracoesService.tryGlobal;
    final c = g?.lanApiClient;
    if (c is LanApiClient && c.configurado) return c;
    return null;
  }

  /// Apos pull de `empresa_config` ou evento WS — atualiza arquivo local.
  Future<void> sincronizarArquivoSeNecessario() async {
    const chave = 'logo_sync';
    final existente = _emAndamento[chave];
    if (existente != null) {
      await existente;
      return;
    }
    final fut = _sincronizarArquivoSeNecessarioImpl();
    _emAndamento[chave] = fut;
    try {
      await fut;
    } finally {
      _emAndamento.remove(chave);
    }
  }

  Future<void> _sincronizarArquivoSeNecessarioImpl() async {
    final cfg = await _configRepository.carregarEmpresaConfig();
    final hashRemoto = cfg.logoHash.trim();
    if (hashRemoto.isEmpty) {
      await _limparLocal(cfg);
      return;
    }
    final pathLocal = cfg.logoPath.trim();
    final arquivoOk = pathLocal.isNotEmpty && File(pathLocal).existsSync();
    final hashLocal = await EmpresaLogoService.hashArquivo(cfg.logoPath);
    if (hashLocal == hashRemoto && arquivoOk) return;

    final client = _cliente();
    if (client == null) return;

    final bytes = await client.downloadEmpresaLogo();
    if (bytes == null || bytes.isEmpty) return;
    final hashBaixado = EmpresaLogoService.hashBytes(
      Uint8List.fromList(bytes),
    );
    if (hashBaixado != hashRemoto) return;

    final gravado = await EmpresaLogoService.gravarTerminalLocal(
      Uint8List.fromList(bytes),
    );
    await _configRepository.salvarEmpresaConfig(
      cfg.copyWith(logoPath: gravado.path, logoHash: hashRemoto),
      propagarRede: false,
    );
  }

  Future<void> _limparLocal(EmpresaConfig cfg) async {
    await EmpresaLogoService.removerTerminalLocal();
    if (cfg.logoPath.trim().isNotEmpty || cfg.logoHash.isNotEmpty) {
      await _configRepository.salvarEmpresaConfig(
        cfg.copyWith(logoPath: '', logoHash: ''),
        propagarRede: false,
      );
    }
  }

  /// Publica bytes no servidor (PC1) ou grava localmente se nao houver rede.
  Future<String> publicar({
    required Uint8List? bytes,
    required bool modoServidor,
  }) async {
    if (bytes == null || bytes.isEmpty) {
      await EmpresaLogoService.removerServidor();
      if (modoServidor) {
        final cfg = await _configRepository.carregarEmpresaConfig();
        await _configRepository.salvarEmpresaConfig(
          cfg.copyWith(logoPath: '', logoHash: ''),
          propagarRede: true,
        );
        return '';
      }
      final client = _cliente();
      if (client != null) {
        await client.removerEmpresaLogo();
      }
      await _limparLocal(await _configRepository.carregarEmpresaConfig());
      return '';
    }

    if (modoServidor) {
      final gravado = await EmpresaLogoService.gravarServidor(bytes);
      final cfg = await _configRepository.carregarEmpresaConfig();
      await _configRepository.salvarEmpresaConfig(
        cfg.copyWith(logoPath: gravado.path, logoHash: gravado.hash),
        propagarRede: true,
      );
      return gravado.hash;
    }

    final client = _cliente();
    if (client == null) {
      final gravado = await EmpresaLogoService.gravarTerminalLocal(bytes);
      final cfg = await _configRepository.carregarEmpresaConfig();
      await _configRepository.salvarEmpresaConfig(
        cfg.copyWith(logoPath: gravado.path, logoHash: gravado.hash),
        propagarRede: false,
      );
      return gravado.hash;
    }

    final resp = await client.uploadEmpresaLogo(bytes);
    final hash = (resp['logoHash'] ?? '').toString().trim();
    final gravado = await EmpresaLogoService.gravarTerminalLocal(bytes);
    final cfg = await _configRepository.carregarEmpresaConfig();
    await _configRepository.salvarEmpresaConfig(
      cfg.copyWith(
        logoPath: gravado.path,
        logoHash: hash.isNotEmpty ? hash : gravado.hash,
      ),
      propagarRede: false,
    );
    return hash.isNotEmpty ? hash : gravado.hash;
  }
}
