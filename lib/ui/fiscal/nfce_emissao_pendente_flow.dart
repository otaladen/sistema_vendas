import 'package:flutter/material.dart';

import '../../config/focus_nfe_runtime.dart';
import '../../data/app_config_repository.dart';
import '../../data/cliente_repository.dart';
import '../../data/sync/sync_cursor_storage.dart';
import '../../data/venda_repository.dart';
import '../../domain/fiscal/fiscal_emissao_lock.dart';
import '../../domain/fiscal/venda_documento_fiscal_mutex.dart';
import '../../model/cliente.dart';
import '../../model/venda.dart';
import '../../services/focus_nfe_reconsulta_helper.dart';
import '../../services/focus_nfe_service.dart';

/// Emissao/reemissao de NFC-e a partir da fila de pendencias (fora do caixa).
abstract final class NfceEmissaoPendenteFlow {
  NfceEmissaoPendenteFlow._();

  static Future<bool> emitir(
    BuildContext context, {
    required Venda venda,
    required VendaRepository vendaRepository,
    required ClienteRepository clienteRepository,
    required AppConfigRepository appConfigRepository,
    required bool permitirVendaSemEstoque,
  }) async {
    if (!context.mounted) return false;
    var vendaAtual = vendaRepository.obterPorId(venda.id) ?? venda;
    final bloqueio = VendaDocumentoFiscalMutex.mensagemBloqueioNovaNfce(vendaAtual);
    if (bloqueio != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(bloqueio), duration: const Duration(seconds: 8)),
      );
      return false;
    }

    final focus = FocusNfeService(config: criarFocusNfeConfigPadrao());
    try {
      focus.validarConfiguracao();
    } catch (e) {
      if (!context.mounted) return false;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('$e')),
      );
      return false;
    }

    final deviceId = await SyncCursorStorage().obterOuCriarDeviceId();
    if (FiscalEmissaoLock.nfceBloqueadaPorOutroDispositivo(vendaAtual, deviceId)) {
      if (!context.mounted) return false;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Outro PC esta emitindo NFC-e desta venda. Aguarde e tente novamente.',
          ),
        ),
      );
      return false;
    }

    final refNfce = FocusNfeService.referenciaVendaNfce(vendaAtual);
    vendaRepository.registrarNfceEmissaoEmAndamento(
      vendaId: vendaAtual.id,
      deviceId: deviceId,
      referencia: refNfce,
    );

    if (!context.mounted) return false;
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      useRootNavigator: true,
      builder: (ctx) => const AlertDialog(
        title: Text('Emissao NFC-e'),
        content: Row(
          children: [
            CircularProgressIndicator(),
            SizedBox(width: 16),
            Expanded(child: Text('Comunicando com a SEFAZ...')),
          ],
        ),
      ),
    );

    Cliente? cliente;
    if (vendaAtual.cliente.targetId > 0) {
      cliente = clienteRepository.obterPorId(vendaAtual.cliente.targetId);
    }

    FocusNfeEmissaoResultado resultado;
    try {
      vendaAtual = vendaRepository.obterPorId(venda.id) ?? vendaAtual;
      resultado = await focus.emitirNfce(
        vendaAtual,
        cliente: cliente,
        entregaDomicilio: vendaAtual.tipoEntrega == 'entrega_loja' ||
            vendaAtual.enderecoEntrega.trim().isNotEmpty,
      );
      final ref = FocusNfeService.referenciaVendaNfce(vendaAtual);
      if (!resultado.autorizada && !resultado.processando) {
        resultado = await FocusNfeReconsultaHelper.recuperarSePossivel(
          original: resultado,
          reconsultar: () => focus.consultarNfce(ref),
        );
        if (FocusNfeService.pareceFalhaComunicacao(resultado) &&
            !resultado.autorizada &&
            !resultado.processando) {
          resultado = FocusNfeReconsultaHelper.comoProcessandoAposFalhaComunicacao(
            referencia: ref,
          );
        }
      }
    } catch (e) {
      vendaRepository.liberarNfceEmissaoEmAndamento(vendaAtual.id);
      if (context.mounted && Navigator.of(context, rootNavigator: true).canPop()) {
        Navigator.of(context, rootNavigator: true).pop();
      }
      if (!context.mounted) return false;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Erro ao emitir NFC-e: $e')),
      );
      return false;
    }

    if (context.mounted && Navigator.of(context, rootNavigator: true).canPop()) {
      Navigator.of(context, rootNavigator: true).pop();
    }
    if (!context.mounted) return false;

    if (resultado.autorizada) {
      try {
        vendaRepository.registrarNfceEmitidaComBaixaEstoque(
          vendaId: vendaAtual.id,
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
      } catch (e) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('NFC-e autorizada, mas falhou ao gravar: $e'),
            backgroundColor: Colors.orange.shade800,
          ),
        );
        return false;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            resultado.numero.isNotEmpty
                ? 'NFC-e ${resultado.numero} autorizada.'
                : 'NFC-e autorizada.',
          ),
          backgroundColor: Colors.green.shade700,
        ),
      );
      return true;
    }

    if (resultado.processando) {
      try {
        vendaRepository.registrarNfcePendenteFocus(
          vendaId: vendaAtual.id,
          referencia: resultado.referencia,
          protocolo: resultado.protocolo,
          statusFocus: resultado.statusFocus,
        );
      } catch (e) {
        vendaRepository.liberarNfceEmissaoEmAndamento(vendaAtual.id);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Falha ao salvar pendencia: $e')),
        );
        return false;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'NFC-e enviada — aguardando SEFAZ. Reconsulta automatica no caixa.',
          ),
        ),
      );
      return true;
    }

    vendaRepository.liberarNfceEmissaoEmAndamento(vendaAtual.id);
    final msg = resultado.mensagem.isEmpty
        ? 'A SEFAZ rejeitou a NFC-e.'
        : resultado.mensagem;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor: Colors.red.shade700,
        duration: const Duration(seconds: 8),
      ),
    );
    return false;
  }
}
