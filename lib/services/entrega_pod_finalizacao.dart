import 'package:path/path.dart' as p;

import '../data/api/venda_api_repository.dart';
import '../data/app_config_repository.dart';
import '../data/venda_repository.dart';
import '../domain/entrega_pod_nome_arquivo.dart';
import '../model/historico_entrega.dart';
import 'entrega_pod_lan_service.dart';

/// Registra POD no banco (PC1) ou via API (Terminal Leve) e replica foto na rede.
class EntregaPodFinalizacao {
  EntregaPodFinalizacao({
    AppConfigRepository? configRepository,
    EntregaPodLanService? lanService,
  }) : _lanService = lanService;

  final EntregaPodLanService? _lanService;

  Future<void> registrarPod({
    required dynamic vendaRepository,
    required int vendaId,
    required String recebidoPor,
    required String usuarioLogin,
    String fotoPathLocal = '',
    String fotoPathServidor = '',
    String ocorrenciaMotivo = '',
  }) async {
    var pathServidor = fotoPathServidor.trim();
    final pathLocal = fotoPathLocal.trim();

    if (pathLocal.isNotEmpty) {
      final lan = _lanService ?? EntregaPodLanService();
      final enviado = await lan.enviarFotoSeRedeAtiva(
        arquivoLocal: pathLocal,
        nomeArquivo: EntregaPodNomeArquivo.extrairNomeArquivo(pathServidor) ??
            p.basename(pathLocal),
      );
      if (enviado != null && enviado.isNotEmpty) {
        pathServidor = enviado;
      }
    }

    if (vendaRepository is VendaApiRepository) {
      await vendaRepository.registrarPodEntregaRemoto(
        vendaId: vendaId,
        recebidoPor: recebidoPor,
        usuarioLogin: usuarioLogin,
        fotoPathLocal: pathLocal,
        fotoPathServidor: pathServidor,
        ocorrenciaMotivo: ocorrenciaMotivo,
      );
      return;
    }

    (vendaRepository as VendaRepository).registrarPodEntrega(
      vendaId: vendaId,
      recebidoPor: recebidoPor,
      usuarioLogin: usuarioLogin,
      fotoPathLocal: pathLocal,
      fotoPathServidor: pathServidor,
    );
  }

  Future<void> registrarPodComHistorico({
    required dynamic vendaRepository,
    required int vendaId,
    required String recebidoPor,
    required String usuarioLogin,
    String fotoPathLocal = '',
    String fotoPathServidor = '',
    bool comFotoNoHistorico = false,
  }) async {
    final motivo =
        'Recebido por: $recebidoPor${comFotoNoHistorico ? ' (com foto)' : ''}';
    await registrarPod(
      vendaRepository: vendaRepository,
      vendaId: vendaId,
      recebidoPor: recebidoPor,
      usuarioLogin: usuarioLogin,
      fotoPathLocal: fotoPathLocal,
      fotoPathServidor: fotoPathServidor,
      ocorrenciaMotivo: vendaRepository is VendaApiRepository ? motivo : '',
    );
    if (vendaRepository is VendaApiRepository) {
      // Ocorrencia ja enviada no payload do POD quando motivo nao vazio.
      return;
    }
    (vendaRepository as VendaRepository).registrarOcorrenciaEntrega(
      vendaId: vendaId,
      status: HistoricoEntregaEventos.podEntrega,
      motivo: motivo,
      usuario: usuarioLogin,
    );
  }
}
