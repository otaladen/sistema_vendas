import 'package:path/path.dart' as p;

import '../data/app_config_repository.dart';
import '../data/venda_repository.dart';
import '../domain/entrega_pod_nome_arquivo.dart';
import '../model/historico_entrega.dart';
import 'entrega_pod_lan_service.dart';

/// Registra POD no banco e replica foto no servidor LAN (fase 2).
class EntregaPodFinalizacao {
  EntregaPodFinalizacao({
    AppConfigRepository? configRepository,
    EntregaPodLanService? lanService,
  })  : _configRepository = configRepository ?? AppConfigRepository(),
        _lanService = lanService;

  final AppConfigRepository _configRepository;
  final EntregaPodLanService? _lanService;

  Future<void> registrarPod({
    required VendaRepository vendaRepository,
    required int vendaId,
    required String recebidoPor,
    required String usuarioLogin,
    String fotoPathLocal = '',
    String fotoPathServidor = '',
  }) async {
    var pathServidor = fotoPathServidor.trim();
    final pathLocal = fotoPathLocal.trim();

    if (pathLocal.isNotEmpty) {
      final lan = _lanService ?? EntregaPodLanService(
        configRepository: _configRepository,
      );
      final enviado = await lan.enviarFotoSeRedeAtiva(
        arquivoLocal: pathLocal,
        nomeArquivo: EntregaPodNomeArquivo.extrairNomeArquivo(pathServidor) ??
            p.basename(pathLocal),
      );
      if (enviado != null && enviado.isNotEmpty) {
        pathServidor = enviado;
      } else if (pathServidor.isEmpty) {
        pathServidor = 'pod_entrega/${p.basename(pathLocal)}';
      }
    }

    vendaRepository.registrarPodEntrega(
      vendaId: vendaId,
      recebidoPor: recebidoPor,
      usuarioLogin: usuarioLogin,
      fotoPathLocal: pathLocal,
      fotoPathServidor: pathServidor,
    );
  }

  Future<void> registrarPodComHistorico({
    required VendaRepository vendaRepository,
    required int vendaId,
    required String recebidoPor,
    required String usuarioLogin,
    String fotoPathLocal = '',
    String fotoPathServidor = '',
    bool comFotoNoHistorico = false,
  }) async {
    await registrarPod(
      vendaRepository: vendaRepository,
      vendaId: vendaId,
      recebidoPor: recebidoPor,
      usuarioLogin: usuarioLogin,
      fotoPathLocal: fotoPathLocal,
      fotoPathServidor: fotoPathServidor,
    );
    vendaRepository.registrarOcorrenciaEntrega(
      vendaId: vendaId,
      status: HistoricoEntregaEventos.podEntrega,
      motivo:
          'Recebido por: $recebidoPor${comFotoNoHistorico ? ' (com foto)' : ''}',
      usuario: usuarioLogin,
    );
  }
}
