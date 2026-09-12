import 'package:flutter/material.dart';

import '../../config/focus_nfe_runtime.dart';
import '../../data/cliente_repository.dart';
import '../../data/sync/sync_cursor_storage.dart';
import '../../data/venda_repository.dart';
import '../../domain/fiscal/fiscal_emissao_lock.dart';
import '../../domain/fiscal/venda_documento_fiscal_mutex.dart';
import '../../domain/item_venda_produto_orfao.dart';
import '../../model/cliente.dart';
import '../../model/venda.dart';
import '../../services/configuracoes_service.dart';
import '../../services/focus_nfe_reconsulta_helper.dart';
import '../../services/focus_nfe_service.dart';
import 'revincular_produto_item_venda_flow.dart';

/// Emissao/reemissao de NFC-e a partir da fila de pendencias (fora do caixa).
abstract final class NfceEmissaoPendenteFlow {
  NfceEmissaoPendenteFlow._();

  static Future<bool> emitir(
    BuildContext context, {
    required Venda venda,
    required VendaRepository vendaRepository,
    required ClienteRepository clienteRepository,
    required bool permitirVendaSemEstoque,
    dynamic produtoRepository,
  }) async {
    for (var tentativa = 0; tentativa < 2; tentativa++) {
      if (!context.mounted) return false;

      if (produtoRepository != null && tentativa == 0) {
        final orfaos = vendaRepository.listarItensSemProdutoVinculado(venda.id);
        if (orfaos.isNotEmpty) {
          final resolvido = await RevincularProdutoItemVendaFlow.resolverOrfaosDaVenda(
            context,
            vendaId: venda.id,
            vendaRepository: vendaRepository,
            produtoRepository: produtoRepository,
          );
          if (!resolvido) return false;
        }
      }

      final resultado = await _tentarEmitir(
        context,
        venda: venda,
        vendaRepository: vendaRepository,
        clienteRepository: clienteRepository,
        permitirVendaSemEstoque: permitirVendaSemEstoque,
      );

      if (resultado == _EmissaoPendenteResultado.sucesso ||
          resultado == _EmissaoPendenteResultado.processando) {
        return true;
      }
      if (resultado == _EmissaoPendenteResultado.falhaDefinitiva) {
        return false;
      }

      if (produtoRepository == null || !context.mounted) return false;
      final resolvido = await RevincularProdutoItemVendaFlow.resolverOrfaosDaVenda(
        context,
        vendaId: venda.id,
        vendaRepository: vendaRepository,
        produtoRepository: produtoRepository,
        mensagemErro: _ultimaMensagemErro,
      );
      if (!resolvido) return false;
    }
    return false;
  }

  static String? _ultimaMensagemErro;

  static Future<_EmissaoPendenteResultado> _tentarEmitir(
    BuildContext context, {
    required Venda venda,
    required VendaRepository vendaRepository,
    required ClienteRepository clienteRepository,
    required bool permitirVendaSemEstoque,
  }) async {
    _ultimaMensagemErro = null;
    if (!context.mounted) return _EmissaoPendenteResultado.falhaDefinitiva;
    var vendaAtual = vendaRepository.obterPorId(venda.id) ?? venda;
    final bloqueio = VendaDocumentoFiscalMutex.mensagemBloqueioNovaNfce(vendaAtual);
    if (bloqueio != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(bloqueio), duration: const Duration(seconds: 8)),
      );
      return _EmissaoPendenteResultado.falhaDefinitiva;
    }

    await ConfiguracoesService.resolverFiscalGlobal();
    final focus = FocusNfeService(config: criarFocusNfeConfigPadrao());
    try {
      focus.validarConfiguracao();
    } catch (e) {
      if (!context.mounted) return _EmissaoPendenteResultado.falhaDefinitiva;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('$e')),
      );
      return _EmissaoPendenteResultado.falhaDefinitiva;
    }

    final deviceId = await SyncCursorStorage().obterOuCriarDeviceId();
    if (FiscalEmissaoLock.nfceBloqueadaPorOutroDispositivo(vendaAtual, deviceId)) {
      if (!context.mounted) return _EmissaoPendenteResultado.falhaDefinitiva;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Outro PC esta emitindo NFC-e desta venda. Aguarde e tente novamente.',
          ),
        ),
      );
      return _EmissaoPendenteResultado.falhaDefinitiva;
    }

    final refNfce = FocusNfeService.referenciaVendaNfce(vendaAtual);
    vendaRepository.registrarNfceEmissaoEmAndamento(
      vendaId: vendaAtual.id,
      deviceId: deviceId,
      referencia: refNfce,
    );

    if (!context.mounted) return _EmissaoPendenteResultado.falhaDefinitiva;
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
      if (!context.mounted) return _EmissaoPendenteResultado.falhaDefinitiva;
      final msg = '$e';
      _ultimaMensagemErro = msg;
      vendaRepository.registrarNfceErroEmissao(
        vendaId: vendaAtual.id,
        mensagem: msg,
      );
      if (ItemVendaProdutoOrfaoHelper.pareceErroSemProdutoVinculado(msg)) {
        return _EmissaoPendenteResultado.orfaosProduto;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Erro ao emitir NFC-e: $e')),
      );
      return _EmissaoPendenteResultado.falhaDefinitiva;
    }

    if (context.mounted && Navigator.of(context, rootNavigator: true).canPop()) {
      Navigator.of(context, rootNavigator: true).pop();
    }
    if (!context.mounted) return _EmissaoPendenteResultado.falhaDefinitiva;

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
          referenciaFocus: resultado.referencia.isNotEmpty
              ? resultado.referencia
              : FocusNfeService.referenciaVendaNfce(vendaAtual),
        );
      } catch (e) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('NFC-e autorizada, mas falhou ao gravar: $e'),
            backgroundColor: Colors.orange.shade800,
          ),
        );
        return _EmissaoPendenteResultado.falhaDefinitiva;
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
      return _EmissaoPendenteResultado.sucesso;
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
        return _EmissaoPendenteResultado.falhaDefinitiva;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'NFC-e enviada — aguardando SEFAZ. Reconsulta automatica no caixa.',
          ),
        ),
      );
      return _EmissaoPendenteResultado.processando;
    }

    vendaRepository.liberarNfceEmissaoEmAndamento(vendaAtual.id);
    final msg = resultado.mensagem.isEmpty
        ? 'A SEFAZ rejeitou a NFC-e.'
        : resultado.mensagem;
    _ultimaMensagemErro = msg;
    vendaRepository.registrarNfceErroEmissao(
      vendaId: vendaAtual.id,
      mensagem: msg,
      statusFocus: resultado.statusFocus.isNotEmpty
          ? resultado.statusFocus
          : 'erro_autorizacao',
    );
    if (ItemVendaProdutoOrfaoHelper.pareceErroSemProdutoVinculado(msg)) {
      return _EmissaoPendenteResultado.orfaosProduto;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor: Colors.red.shade700,
        duration: const Duration(seconds: 8),
      ),
    );
    return _EmissaoPendenteResultado.falhaDefinitiva;
  }
}

enum _EmissaoPendenteResultado {
  sucesso,
  processando,
  orfaosProduto,
  falhaDefinitiva,
}
