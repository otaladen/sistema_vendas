import '../../config/focus_nfe_runtime.dart';
import '../../data/sync/estoque_local_refresh_hub.dart';
import '../../data/sync/sync_cursor_storage.dart';
import '../../data/sync/sync_refresh_hub.dart';
import '../../domain/fiscal/fiscal_emissao_lock.dart';
import '../../domain/fiscal/venda_documento_fiscal_mutex.dart';
import '../../model/cliente.dart';
import '../../services/focus_nfe_reconsulta_helper.dart';
import '../../services/focus_nfe_service.dart';
import 'lan_api_deps.dart';

/// Emissao NFC-e headless no processo do PC servidor (sem UI).
Future<Map<String, dynamic>> lanApiEmitirNfce({
  required LanApiDeps d,
  required int vendaId,
  bool permitirVendaSemEstoque = true,
}) async {
  final vendaRepo = d.vendaRepository;
  var venda = vendaRepo.obterPorId(vendaId);
  if (venda == null) {
    return {'ok': false, 'error': 'Venda $vendaId nao encontrada.', 'status': 404};
  }

  final bloqueio = VendaDocumentoFiscalMutex.mensagemBloqueioNovaNfce(venda);
  if (bloqueio != null) {
    return {'ok': false, 'error': bloqueio, 'status': 409};
  }

  final focus = FocusNfeService(config: criarFocusNfeConfigPadrao());
  try {
    focus.validarConfiguracao();
  } catch (e) {
    return {'ok': false, 'error': '$e', 'status': 400};
  }

  final deviceId = await SyncCursorStorage().obterOuCriarDeviceId();
  if (FiscalEmissaoLock.nfceBloqueadaPorOutroDispositivo(venda, deviceId)) {
    return {
      'ok': false,
      'error':
          'Outro PC esta emitindo NFC-e desta venda. Aguarde e tente novamente.',
      'status': 409,
    };
  }

  final refNfce = FocusNfeService.referenciaVendaNfce(venda);
  vendaRepo.registrarNfceEmissaoEmAndamento(
    vendaId: venda.id,
    deviceId: deviceId,
    referencia: refNfce,
  );

  Cliente? cliente;
  if (venda.cliente.targetId > 0) {
    cliente = d.clienteRepository.obterPorId(venda.cliente.targetId);
  }

  FocusNfeEmissaoResultado resultado;
  try {
    venda = vendaRepo.obterPorId(vendaId) ?? venda;
    resultado = await focus.emitirNfce(
      venda,
      cliente: cliente,
      entregaDomicilio: venda.tipoEntrega == 'entrega_loja' ||
          venda.enderecoEntrega.trim().isNotEmpty,
    );
    final ref = FocusNfeService.referenciaVendaNfce(venda);
    if (!resultado.autorizada && !resultado.processando) {
      resultado = await FocusNfeReconsultaHelper.recuperarSePossivel(
        original: resultado,
        reconsultar: () => focus.consultarNfce(ref),
      );
      if (FocusNfeService.pareceFalhaComunicacao(resultado) &&
          !resultado.autorizada &&
          !resultado.processando) {
        resultado =
            FocusNfeReconsultaHelper.comoProcessandoAposFalhaComunicacao(
          referencia: ref,
        );
      }
    }
  } catch (e) {
    vendaRepo.liberarNfceEmissaoEmAndamento(vendaId);
    final msg = 'Erro ao emitir NFC-e: $e';
    vendaRepo.registrarNfceErroEmissao(vendaId: vendaId, mensagem: msg);
    return {'ok': false, 'error': msg, 'status': 502};
  }

  if (resultado.autorizada) {
    try {
      vendaRepo.registrarNfceEmitidaComBaixaEstoque(
        vendaId: vendaId,
        chaveAcesso: resultado.chaveNfe,
        numero: resultado.numero,
        serie: resultado.serie,
        protocolo: resultado.protocolo,
        urlDanfe: resultado.urlDanfe,
        urlXml: resultado.urlXml,
        statusFocus: resultado.cancelada
            ? 'cancelado'
            : (resultado.statusFocus.isNotEmpty
                ? resultado.statusFocus
                : 'autorizado'),
        urlXmlCancelamento: resultado.urlXmlCancelamento,
        permitirVendaSemEstoque: permitirVendaSemEstoque,
      );
      d.notificar('venda');
      d.notificar('produto');
      d.notificar('fiscal', ids: [vendaId]);
      EstoqueLocalRefreshHub.instance.notificar();
      SyncRefreshHub.instance.notificarDadosAtualizados();
      return {
        'ok': true,
        'autorizada': true,
        'chaveNfe': resultado.chaveNfe,
        'numero': resultado.numero,
        'serie': resultado.serie,
        'protocolo': resultado.protocolo,
        'urlDanfe': resultado.urlDanfe,
        'urlXml': resultado.urlXml,
        'referencia': FocusNfeService.referenciaVendaNfce(
          vendaRepo.obterPorId(vendaId) ?? venda,
        ),
      };
    } catch (e) {
      return {
        'ok': false,
        'error': 'NFC-e autorizada, mas falhou ao gravar: $e',
        'status': 500,
        'autorizada': true,
        'chaveNfe': resultado.chaveNfe,
      };
    }
  }

  if (resultado.processando) {
    try {
      vendaRepo.registrarNfcePendenteFocus(
        vendaId: vendaId,
        referencia: resultado.referencia,
        protocolo: resultado.protocolo,
        statusFocus: resultado.statusFocus,
      );
      d.notificar('venda');
      d.notificar('fiscal', ids: [vendaId]);
      SyncRefreshHub.instance.notificarDadosAtualizados();
      return {
        'ok': true,
        'autorizada': false,
        'processando': true,
        'referencia': resultado.referencia,
        'protocolo': resultado.protocolo,
        'statusFocus': resultado.statusFocus,
        'mensagem': resultado.mensagem.isNotEmpty
            ? resultado.mensagem
            : 'Aguardando autorizacao da SEFAZ (em fila / processando).',
      };
    } catch (e) {
      vendaRepo.liberarNfceEmissaoEmAndamento(vendaId);
      return {'ok': false, 'error': '$e', 'status': 500};
    }
  }

  vendaRepo.liberarNfceEmissaoEmAndamento(vendaId);
  final erro = resultado.mensagem.isNotEmpty
      ? resultado.mensagem
      : 'NFC-e nao autorizada.';
  vendaRepo.registrarNfceErroEmissao(
    vendaId: vendaId,
    mensagem: erro,
    statusFocus: resultado.statusFocus.isNotEmpty
        ? resultado.statusFocus
        : 'erro_autorizacao',
  );
  d.notificar('venda');
  d.notificar('fiscal', ids: [vendaId]);
  SyncRefreshHub.instance.notificarDadosAtualizados();
  return {
    'ok': false,
    'error': erro,
    'status': 400,
    'statusFocus': resultado.statusFocus,
  };
}
