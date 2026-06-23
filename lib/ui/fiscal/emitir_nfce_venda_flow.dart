import 'package:flutter/material.dart';

import '../../config/fiscal_config.dart';
import '../../data/app_config_repository.dart';
import '../../data/cliente_repository.dart';
import '../../data/sync/sync_cursor_storage.dart';
import '../../data/venda_repository.dart';
import '../../data/vendedor_repository.dart';
import '../../domain/fiscal/abrir_danfe_focus.dart';
import '../../domain/fiscal/fiscal_emissao_lock.dart';
import '../../domain/fiscal/venda_documento_fiscal_mutex.dart';
import '../../domain/venda_documento_rotulo_helper.dart';
import '../../model/cliente.dart';
import '../../model/venda.dart';
import '../../model/vendedor.dart';
import '../../services/cupom_nao_fiscal_venda_pdf.dart';
import '../../services/focus_nfe_reconsulta_helper.dart';
import '../../services/focus_nfe_service.dart';
import '../../services/print_service.dart';
import '../cupom_venda_impressao_helper.dart';

/// Dependencias para emitir NFC-e de uma venda finalizada.
class EmitirNfceVendaDeps {
  const EmitirNfceVendaDeps({
    required this.vendaRepository,
    required this.clienteRepository,
    required this.vendedorRepository,
    required this.appConfigRepository,
    required this.printService,
    required this.focusNfeService,
  });

  final VendaRepository vendaRepository;
  final ClienteRepository clienteRepository;
  final VendedorRepository vendedorRepository;
  final AppConfigRepository appConfigRepository;
  final PrintService printService;
  final FocusNfeService focusNfeService;
}

enum EmissaoNfceVendaKind {
  sucesso,
  processando,
  erroApi,
  erroConfig,
  erroValidacao,
  erroGenerico,
}

class EmissaoNfceVendaResult {
  const EmissaoNfceVendaResult._({
    required this.kind,
    this.resultado,
    this.mensagem = '',
    this.vendaAtual,
  });

  final EmissaoNfceVendaKind kind;
  final FocusNfeEmissaoResultado? resultado;
  final String mensagem;
  final Venda? vendaAtual;

  factory EmissaoNfceVendaResult.sucesso({
    required FocusNfeEmissaoResultado resultado,
    required Venda vendaAtual,
  }) =>
      EmissaoNfceVendaResult._(
        kind: EmissaoNfceVendaKind.sucesso,
        resultado: resultado,
        vendaAtual: vendaAtual,
      );

  factory EmissaoNfceVendaResult.processando({
    required FocusNfeEmissaoResultado resultado,
    required Venda vendaAtual,
  }) =>
      EmissaoNfceVendaResult._(
        kind: EmissaoNfceVendaKind.processando,
        resultado: resultado,
        vendaAtual: vendaAtual,
      );

  factory EmissaoNfceVendaResult.erroApi(String mensagem, Venda vendaAtual) =>
      EmissaoNfceVendaResult._(
        kind: EmissaoNfceVendaKind.erroApi,
        mensagem: mensagem,
        vendaAtual: vendaAtual,
      );

  factory EmissaoNfceVendaResult.erroConfig(String mensagem) =>
      EmissaoNfceVendaResult._(
        kind: EmissaoNfceVendaKind.erroConfig,
        mensagem: mensagem,
      );

  factory EmissaoNfceVendaResult.erroValidacao(String mensagem) =>
      EmissaoNfceVendaResult._(
        kind: EmissaoNfceVendaKind.erroValidacao,
        mensagem: mensagem,
      );

  factory EmissaoNfceVendaResult.erroGenerico(String mensagem) =>
      EmissaoNfceVendaResult._(
        kind: EmissaoNfceVendaKind.erroGenerico,
        mensagem: mensagem,
      );
}

/// Regras e UI compartilhados para emitir NFC-e (caixa e listagem).
abstract final class EmitirNfceVendaFlow {
  EmitirNfceVendaFlow._();

  static bool podeEmitir(Venda venda) {
    if (venda.cancelada || venda.status != 'finalizada') return false;
    if (venda.itens.isEmpty) return false;
    if (VendaDocumentoFiscalMutex.bloqueiaNovaNfce(venda)) return false;
    if (venda.nfceEmissaoEmAndamento) return false;
    return true;
  }

  static Cliente? clienteDaVenda(
    Venda venda,
    ClienteRepository clienteRepository,
  ) {
    final ligado = venda.cliente.target;
    if (ligado != null) return ligado;
    final id = venda.cliente.targetId;
    if (id == 0) return null;
    return clienteRepository.obterPorId(id);
  }

  static Vendedor? vendedorDaVenda(
    Venda venda,
    VendedorRepository vendedorRepository,
  ) {
    final ligado = venda.vendedor.target;
    if (ligado != null) return ligado;
    final id = venda.vendedor.targetId;
    if (id == 0) return null;
    return vendedorRepository.obterPorId(id);
  }

  static Future<void> executar(
    BuildContext context, {
    required EmitirNfceVendaDeps deps,
    required Venda venda,
    VoidCallback? onConcluidoComSucesso,
    bool fluxoAutomaticoPosVenda = false,
  }) async {
    if (!context.mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    var vendaAtual = deps.vendaRepository.obterPorId(venda.id) ?? venda;

    while (context.mounted) {
      vendaAtual = deps.vendaRepository.obterPorId(venda.id) ?? vendaAtual;

      if (!podeEmitir(vendaAtual)) {
        final bloqueio =
            VendaDocumentoFiscalMutex.mensagemBloqueioNovaNfce(vendaAtual);
        messenger.showSnackBar(
          SnackBar(
            content: Text(
              bloqueio ??
                  'Nao e possivel emitir NFC-e para esta venda no momento.',
            ),
            duration: const Duration(seconds: 8),
          ),
        );
        return;
      }

      final deviceId = await SyncCursorStorage().obterOuCriarDeviceId();
      if (!context.mounted) return;

      if (FiscalEmissaoLock.nfceBloqueadaPorOutroDispositivo(
        vendaAtual,
        deviceId,
      )) {
        messenger.showSnackBar(
          const SnackBar(
            content: Text(
              'Outro PC esta emitindo NFC-e desta venda. '
              'Aguarde alguns minutos e tente novamente.',
            ),
            duration: Duration(seconds: 8),
          ),
        );
        return;
      }

      final refNfce = FocusNfeService.referenciaVendaNfce(vendaAtual);
      deps.vendaRepository.registrarNfceEmissaoEmAndamento(
        vendaId: vendaAtual.id,
        deviceId: deviceId,
        referencia: refNfce,
      );

      final rootNav = Navigator.of(context, rootNavigator: true);
      if (!context.mounted) return;

      showDialog<void>(
        context: context,
        useRootNavigator: true,
        barrierDismissible: false,
        builder: (ctx) {
          final theme = Theme.of(ctx);
          return PopScope(
            canPop: false,
            child: AlertDialog(
              title: const Text('Emissao NFC-e'),
              content: SizedBox(
                width: 360,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const CircularProgressIndicator(),
                    const SizedBox(height: 20),
                    Text(
                      'Comunicando com a SEFAZ através da Focus NFe...',
                      textAlign: TextAlign.center,
                      style: theme.textTheme.bodyMedium,
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      );
      await _aguardarEntreDialogos();

      EmissaoNfceVendaResult dialogResult;
      try {
        dialogResult = await _executarChamadaFiscal(deps, vendaAtual);
      } finally {
        if (rootNav.mounted && rootNav.canPop()) {
          rootNav.pop();
        }
      }

      await _aguardarEntreDialogos();
      if (!context.mounted) return;

      switch (dialogResult.kind) {
        case EmissaoNfceVendaKind.erroConfig:
          deps.vendaRepository.liberarNfceEmissaoEmAndamento(vendaAtual.id);
          messenger.showSnackBar(
            SnackBar(
              content: Text(dialogResult.mensagem),
              duration: const Duration(seconds: 8),
            ),
          );
          return;
        case EmissaoNfceVendaKind.erroValidacao:
          deps.vendaRepository.liberarNfceEmissaoEmAndamento(vendaAtual.id);
          messenger.showSnackBar(
            SnackBar(
              content: Text(dialogResult.mensagem),
              backgroundColor: Colors.orange.shade800,
              duration: const Duration(seconds: 8),
            ),
          );
          return;
        case EmissaoNfceVendaKind.erroApi:
        case EmissaoNfceVendaKind.erroGenerico:
          deps.vendaRepository.liberarNfceEmissaoEmAndamento(vendaAtual.id);
          final tentar = await _mostrarDialogoFalhaNfce(
            context,
            mensagem: dialogResult.mensagem,
          );
          await _aguardarEntreDialogos();
          if (!context.mounted) return;
          if (tentar == true) {
            vendaAtual = dialogResult.vendaAtual ??
                deps.vendaRepository.obterPorId(vendaAtual.id) ??
                vendaAtual;
            continue;
          }
          messenger.showSnackBar(
            SnackBar(
              content: Text('NFC-e nao emitida: ${dialogResult.mensagem}'),
              backgroundColor: Colors.red.shade700,
              duration: const Duration(seconds: 8),
            ),
          );
          return;
        case EmissaoNfceVendaKind.processando:
          final r = dialogResult.resultado!;
          final vSalvar = dialogResult.vendaAtual ?? vendaAtual;
          try {
            deps.vendaRepository.registrarNfcePendenteFocus(
              vendaId: vSalvar.id,
              referencia: r.referencia,
              protocolo: r.protocolo,
              statusFocus: r.statusFocus,
            );
          } catch (e) {
            messenger.showSnackBar(
              SnackBar(
                content: Text(
                  'NFC-e em processamento, mas falhou ao salvar pendencia: $e',
                ),
                backgroundColor: Colors.orange.shade800,
                duration: const Duration(seconds: 10),
              ),
            );
          }
          await showDialog<void>(
            context: context,
            useRootNavigator: true,
            builder: (ctx) {
              final theme = Theme.of(ctx);
              return AlertDialog(
                icon: Icon(
                  Icons.hourglass_top_outlined,
                  color: theme.colorScheme.primary,
                  size: 32,
                ),
                title: const Text('NFC-e em processamento'),
                content: Text(
                  r.mensagem.isEmpty
                      ? 'A nota foi enviada a Focus NFe e aguarda retorno da '
                          'SEFAZ.\n\n'
                          'Referencia: ${r.referencia}'
                      : '${r.mensagem}\n\n'
                          'Referencia: ${r.referencia}',
                  textAlign: TextAlign.center,
                ),
                actionsAlignment: MainAxisAlignment.center,
                actions: [
                  FilledButton(
                    onPressed: () => Navigator.pop(ctx),
                    child: const Text('Entendi'),
                  ),
                ],
              );
            },
          );
          onConcluidoComSucesso?.call();
          return;
        case EmissaoNfceVendaKind.sucesso:
          final r = dialogResult.resultado!;
          final vSalvar = dialogResult.vendaAtual ?? vendaAtual;
          final config =
              await deps.appConfigRepository.carregarEmpresaConfig();
          if (!context.mounted) return;

          try {
            deps.vendaRepository.registrarNfceEmitidaComBaixaEstoque(
              vendaId: vSalvar.id,
              chaveAcesso: r.chaveNfe,
              numero: r.numero,
              serie: r.serie,
              protocolo: r.protocolo,
              urlDanfe: r.urlDanfe,
              urlXml: r.urlXml,
              statusFocus: r.cancelada
                  ? 'cancelado'
                  : (r.statusFocus.isNotEmpty ? r.statusFocus : 'autorizado'),
              urlXmlCancelamento: r.urlXmlCancelamento,
              permitirVendaSemEstoque: config.permitirVendaSemEstoque,
            );
          } catch (e) {
            messenger.showSnackBar(
              SnackBar(
                content: Text(
                  'NFC-e autorizada, mas falhou ao gravar os dados fiscais: $e',
                ),
                backgroundColor: Colors.orange.shade800,
                duration: const Duration(seconds: 10),
              ),
            );
            return;
          }

          final vendaComNfce =
              deps.vendaRepository.obterPorId(vSalvar.id) ?? vSalvar;
          onConcluidoComSucesso?.call();

          final resumoPos =
              VendaDocumentoRotuloHelper.resumoPosAutorizacaoFiscal(
            vendaComNfce,
          );
          final estoqueOk = vendaComNfce.estoqueBaixadoCupom;

          if (fluxoAutomaticoPosVenda && estoqueOk) {
            messenger.showSnackBar(
              SnackBar(
                content: Text('$resumoPos — proxima venda.'),
                backgroundColor: Colors.green.shade700,
                duration: const Duration(seconds: 5),
              ),
            );
            return;
          }

          final detalhe = <String>[
            resumoPos,
            if (r.numero.isNotEmpty) 'Numero NFC-e: ${r.numero}',
            if (r.serie.isNotEmpty) 'Serie: ${r.serie}',
            if (r.chaveNfe.isNotEmpty) 'Chave: ${r.chaveNfe}',
            if (r.protocolo.isNotEmpty) 'Protocolo: ${r.protocolo}',
            if (r.mensagem.isNotEmpty) r.mensagem,
          ].join('\n');
          final temDanfe = r.urlDanfe.trim().isNotEmpty;

          await showDialog<void>(
            context: context,
            useRootNavigator: true,
            builder: (ctx) {
              final theme = Theme.of(ctx);
              return AlertDialog(
                icon: Icon(
                  Icons.check_circle_outline,
                  color: theme.colorScheme.primary,
                  size: 36,
                ),
                title: const Text('NFC-e autorizada'),
                content: SizedBox(
                  width: 420,
                  child: Text(
                    detalhe.isEmpty ? 'Nota autorizada pela SEFAZ.' : detalhe,
                  ),
                ),
                actionsAlignment: MainAxisAlignment.center,
                actions: [
                  FilledButton.icon(
                    onPressed: () async {
                      Navigator.pop(ctx);
                      await _imprimirCupomNfce(
                        context,
                        deps: deps,
                        venda: vendaComNfce,
                        config: config,
                      );
                    },
                    icon: const Icon(Icons.print_outlined),
                    label: const Text('Imprimir cupom NFC-e'),
                  ),
                  if (temDanfe)
                    TextButton.icon(
                      onPressed: () async {
                        Navigator.pop(ctx);
                        await abrirDanfeFocus(
                          context,
                          focusNfe: deps.focusNfeService,
                          urlSalva: vendaComNfce.nfceUrlDanfe,
                          venda: vendaComNfce,
                        );
                      },
                      icon: const Icon(Icons.picture_as_pdf_outlined),
                      label: const Text('DANFE Focus'),
                    ),
                  TextButton(
                    onPressed: () => Navigator.pop(ctx),
                    child: const Text('Fechar'),
                  ),
                ],
              );
            },
          );
          if (!context.mounted) return;
          messenger.showSnackBar(
            SnackBar(
              content: Text(
                estoqueOk
                    ? '$resumoPos. Imprima o cupom NFC-e se desejar.'
                    : '$resumoPos — verifique a baixa de estoque.',
              ),
              backgroundColor:
                  estoqueOk ? Colors.green.shade700 : Colors.orange.shade800,
              duration: const Duration(seconds: 8),
            ),
          );
          return;
      }
    }
  }

  static Future<void> _aguardarEntreDialogos() async {
    await Future<void>.delayed(Duration.zero);
    await Future<void>.delayed(const Duration(milliseconds: 80));
  }

  static String? _dicaCorrecaoFalhaNfce(String mensagem) {
    final m = mensagem.toLowerCase();
    if (m.contains('habilitad') && m.contains('nfce')) {
      return 'No painel Focus (ambiente de homologacao):\n\n'
          '1. Menu Empresas — cadastre o CNPJ de ${FiscalConfig.cnpjEmitente}.\n'
          '2. Na empresa, habilite NFC-e (modelo 65).\n'
          '3. Envie o certificado digital A1 (.pfx) e a senha.\n'
          '4. Confira CSC e ID CSC da SEFAZ.\n'
          '5. Cole o token em Configuracoes → Fiscal — Focus NFe.';
    }
    return null;
  }

  static Future<bool?> _mostrarDialogoFalhaNfce(
    BuildContext context, {
    required String mensagem,
  }) {
    final dica = _dicaCorrecaoFalhaNfce(mensagem);
    return showDialog<bool>(
      context: context,
      useRootNavigator: true,
      builder: (ctx) {
        final theme = Theme.of(ctx);
        return AlertDialog(
          icon: Icon(Icons.error_outline, color: theme.colorScheme.error, size: 32),
          title: const Text('NFC-e rejeitada'),
          content: SizedBox(
            width: 420,
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.errorContainer
                          .withValues(alpha: 0.45),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: theme.colorScheme.error.withValues(alpha: 0.35),
                      ),
                    ),
                    child: Text(
                      mensagem,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.onErrorContainer,
                      ),
                    ),
                  ),
                  if (dica != null) ...[
                    const SizedBox(height: 12),
                    Text(
                      dica,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                        height: 1.35,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
          actionsAlignment: MainAxisAlignment.center,
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Fechar'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Tentar reemitir'),
            ),
          ],
        );
      },
    );
  }

  static Future<EmissaoNfceVendaResult> _executarChamadaFiscal(
    EmitirNfceVendaDeps deps,
    Venda venda,
  ) async {
    final vendaAtual = deps.vendaRepository.obterPorId(venda.id) ?? venda;
    if (vendaAtual.itens.isEmpty) {
      return EmissaoNfceVendaResult.erroValidacao(
        'A venda nao possui itens para emitir NFC-e.',
      );
    }

    try {
      deps.focusNfeService.validarConfiguracao();
    } on FocusNfeConfigIncompletaException catch (e) {
      return EmissaoNfceVendaResult.erroConfig(e.message);
    }

    final cliente = clienteDaVenda(vendaAtual, deps.clienteRepository);

    try {
      var resultado = await deps.focusNfeService.emitirNfce(
        vendaAtual,
        cliente: cliente,
        entregaDomicilio: vendaAtual.tipoEntrega == 'entrega_loja' ||
            vendaAtual.enderecoEntrega.trim().isNotEmpty,
      );

      final ref = FocusNfeService.referenciaVendaNfce(vendaAtual);
      if (!resultado.autorizada && !resultado.processando) {
        resultado = await FocusNfeReconsultaHelper.recuperarSePossivel(
          original: resultado,
          reconsultar: () => deps.focusNfeService.consultarNfce(ref),
        );
        if (FocusNfeService.pareceFalhaComunicacao(resultado) &&
            !resultado.autorizada &&
            !resultado.processando) {
          resultado = FocusNfeReconsultaHelper.comoProcessandoAposFalhaComunicacao(
            referencia: ref,
          );
        }
      }

      if (resultado.autorizada) {
        return EmissaoNfceVendaResult.sucesso(
          resultado: resultado,
          vendaAtual: vendaAtual,
        );
      }
      if (resultado.processando) {
        return EmissaoNfceVendaResult.processando(
          resultado: resultado,
          vendaAtual: vendaAtual,
        );
      }

      final msg = resultado.mensagem.isEmpty
          ? 'A SEFAZ rejeitou a NFC-e sem mensagem detalhada.'
          : resultado.mensagem;
      return EmissaoNfceVendaResult.erroApi(msg, vendaAtual);
    } on FocusNfeValidacaoException catch (e) {
      return EmissaoNfceVendaResult.erroValidacao(e.message);
    } catch (e) {
      final ref = FocusNfeService.referenciaVendaNfce(vendaAtual);
      try {
        final consulta = await deps.focusNfeService.consultarNfce(ref);
        if (consulta.autorizada) {
          return EmissaoNfceVendaResult.sucesso(
            resultado: consulta,
            vendaAtual: vendaAtual,
          );
        }
        if (consulta.processando) {
          return EmissaoNfceVendaResult.processando(
            resultado: consulta,
            vendaAtual: vendaAtual,
          );
        }
      } catch (_) {}
      return EmissaoNfceVendaResult.erroGenerico('Erro ao emitir NFC-e: $e');
    }
  }

  static Future<void> _imprimirCupomNfce(
    BuildContext context, {
    required EmitirNfceVendaDeps deps,
    required Venda venda,
    required EmpresaConfig config,
  }) async {
    if (!context.mounted) return;
    final vendaAtual = deps.vendaRepository.obterPorId(venda.id) ?? venda;
    final infer =
        CupomNaoFiscalVendaPdf.inferirRecebidoTrocoSegundaVia(vendaAtual);
    final nomeArquivo =
        'nfce_venda_${vendaAtual.numeroOrcamento > 0 ? vendaAtual.numeroOrcamento : vendaAtual.id}.pdf';
    await mostrarFluxoImpressaoCupomVenda(
      context,
      printService: deps.printService,
      config: config,
      title: 'Cupom NFC-e',
      content:
          'Deseja imprimir o cupom fiscal desta venda? (Uma via — sem duplicar.)',
      gerarPdf: () => CupomNaoFiscalVendaPdf.gerar(
        venda: vendaAtual,
        config: config,
        cliente: clienteDaVenda(vendaAtual, deps.clienteRepository),
        vendedor: vendedorDaVenda(vendaAtual, deps.vendedorRepository),
        totalRecebido: infer.recebido,
        troco: infer.troco,
        segundaVia: false,
        dataCabecalhoVenda:
            vendaAtual.nfceEmitidaEm ?? vendaAtual.data,
      ),
      suggestedFileName: nomeArquivo,
    );
  }
}
