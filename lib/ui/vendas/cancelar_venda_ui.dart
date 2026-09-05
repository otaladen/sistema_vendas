import 'package:flutter/material.dart';

import '../../data/api/venda_api_repository.dart';
import '../../data/venda_repository.dart';
import '../../domain/operacao_permissao_guard.dart';
import '../../model/usuario_sistema.dart';
import '../../model/venda.dart';
import '../../services/venda_fiscal_service.dart';
import '../fiscal/widgets/nfe_historico_acoes_dialog.dart';
import '../widgets/lan_api_feedback.dart';

enum CancelarVendaUiResultado {
  sucesso,
  naoAutorizado,
  canceladoPeloUsuario,
  erro,
}

/// Rotulo amigavel da venda (numero do orcamento ou ID interno).
String rotuloVendaParaUsuario(Venda v) {
  if (v.numeroOrcamento > 0) return 'Venda ${v.numeroOrcamento}';
  return 'Venda ${v.id}';
}

/// Fluxo completo de cancelamento (autorizacao, fiscal SEFAZ, ERP).
class CancelarVendaUi {
  CancelarVendaUi._();

  static Future<(bool autorizado, UsuarioSistema? usuario)> autorizar({
    required BuildContext context,
    required dynamic usuarioRepository,
    required String usuarioAtual,
    required bool podeCancelarVendas,
  }) async {
    if (podeCancelarVendas) {
      final todos = await usuarioRepository.listarTodos() as List;
      for (final raw in todos) {
        if (raw is! UsuarioSistema) continue;
        final u = raw;
        if (u.login == usuarioAtual &&
            u.ativo &&
            OperacaoPermissaoGuard.podeCancelarVendas(u)) {
          return (true, u);
        }
      }
    }
    final loginController = TextEditingController();
    final senhaController = TextEditingController();
    final confirmar = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Autorizacao para cancelamento'),
          content: SizedBox(
            width: 420,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  'Informe usuario com permissao de cancelar vendas.',
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: loginController,
                  decoration: const InputDecoration(labelText: 'Login'),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: senhaController,
                  obscureText: true,
                  decoration: const InputDecoration(labelText: 'Senha'),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancelar'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Autorizar'),
            ),
          ],
        );
      },
    );
    if (confirmar != true) {
      loginController.dispose();
      senhaController.dispose();
      return (false, null);
    }
    final login = loginController.text.trim();
    final senha = senhaController.text.trim();
    loginController.dispose();
    senhaController.dispose();
    final usuario =
        await usuarioRepository.autenticar(login, senha) as UsuarioSistema?;
    final autorizado = usuario != null &&
        usuario.ativo &&
        OperacaoPermissaoGuard.podeCancelarVendas(usuario);
    if (!autorizado) {
      return (false, null);
    }
    return (true, usuario);
  }

  static Future<CancelarVendaUiResultado> executar({
    required BuildContext context,
    required dynamic vendaRepository,
    required dynamic clienteRepository,
    required dynamic usuarioRepository,
    required String usuarioAtual,
    required bool podeCancelarVendas,
    required Venda venda,
  }) async {
    if (venda.cancelada) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Venda ja esta cancelada.')),
      );
      return CancelarVendaUiResultado.erro;
    }

    final autorizado = await autorizar(
      context: context,
      usuarioRepository: usuarioRepository,
      usuarioAtual: usuarioAtual,
      podeCancelarVendas: podeCancelarVendas,
    );
    if (!context.mounted || !autorizado.$1 || autorizado.$2 == null) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Cancelamento nao autorizado.')),
        );
      }
      return CancelarVendaUiResultado.naoAutorizado;
    }

    final vendaAtual = vendaRepository.obterPorId(venda.id) ?? venda;
    final apiRepo =
        vendaRepository is VendaApiRepository ? vendaRepository : null;
    final viaApi = apiRepo != null;
    final VendaFiscalService? fiscalSvc;
    final bool exigeFiscal;
    if (vendaRepository is VendaRepository) {
      fiscalSvc = VendaFiscalService(
        vendaRepository: vendaRepository,
        clienteRepository: clienteRepository,
      );
      exigeFiscal = fiscalSvc.vendaExigeCancelamentoFiscal(vendaAtual);
      final bloqueio =
          vendaRepository.mensagemBloqueioCancelamentoVenda(vendaAtual.id);
      if (bloqueio != null) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(bloqueio)),
          );
        }
        return CancelarVendaUiResultado.erro;
      }
    } else {
      fiscalSvc = null;
      exigeFiscal =
          vendaAtual.nfceAutorizadaAtiva || vendaAtual.nfe55Autorizada;
    }

    String justificativaFiscal = '';
    if (exigeFiscal) {
      justificativaFiscal = await showNfeCancelamentoDialog(context) ?? '';
      if (!context.mounted || justificativaFiscal.isEmpty) {
        return CancelarVendaUiResultado.canceladoPeloUsuario;
      }
    }

    final motivoController = TextEditingController();
    final confirmar = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Confirmar cancelamento'),
          content: SizedBox(
            width: 460,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Cancelar ${rotuloVendaParaUsuario(vendaAtual)}?'),
                if (exigeFiscal) ...[
                  const SizedBox(height: 10),
                  Text(
                    vendaAtual.nfceAutorizadaAtiva && vendaAtual.nfe55Autorizada
                        ? 'A NFC-e e a NF-e serao canceladas na SEFAZ antes '
                            'de estornar estoque e fiado.'
                        : vendaAtual.nfceAutorizadaAtiva
                            ? 'A NFC-e sera cancelada na SEFAZ antes de estornar '
                                'estoque e fiado.'
                            : 'A NF-e sera cancelada na SEFAZ antes de estornar '
                                'estoque e fiado.',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Theme.of(context).colorScheme.error,
                        ),
                  ),
                ],
                const SizedBox(height: 8),
                TextField(
                  controller: motivoController,
                  maxLines: 2,
                  decoration: InputDecoration(
                    labelText: exigeFiscal
                        ? 'Observacao interna (opcional)'
                        : 'Motivo (opcional)',
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Voltar'),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: Theme.of(context).colorScheme.error,
                foregroundColor: Theme.of(context).colorScheme.onError,
              ),
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Confirmar cancelamento'),
            ),
          ],
        );
      },
    );
    final motivoExtra = motivoController.text.trim();
    motivoController.dispose();
    if (confirmar != true) {
      return CancelarVendaUiResultado.canceladoPeloUsuario;
    }

    final tinhaNfceAtiva = vendaAtual.nfceAutorizadaAtiva;

    if (exigeFiscal && viaApi) {
      if (!context.mounted) {
        return CancelarVendaUiResultado.canceladoPeloUsuario;
      }
      showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (_) => const AlertDialog(
          content: Row(
            children: [
              CircularProgressIndicator(),
              SizedBox(width: 16),
              Expanded(
                child: Text(
                  'Cancelando documento fiscal na SEFAZ (PC servidor)...',
                ),
              ),
            ],
          ),
        ),
      );

      try {
        final m = await apiRepo.cancelarVendaFiscalRemoto(
          vendaAtual.id,
          justificativa: justificativaFiscal,
          motivo: motivoExtra,
          canceladaPor: autorizado.$2!.login,
        );
        if (!context.mounted) return CancelarVendaUiResultado.sucesso;
        final msg = (m['mensagem'] ?? '').toString().trim();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              tinhaNfceAtiva && msg.isEmpty
                  ? 'NFC-e cancelada com sucesso!'
                  : msg.isNotEmpty
                      ? msg
                      : '${rotuloVendaParaUsuario(vendaAtual)} cancelada '
                          '(SEFAZ + ERP) por ${autorizado.$2!.login}.',
            ),
          ),
        );
        return CancelarVendaUiResultado.sucesso;
      } catch (e) {
        if (context.mounted) {
          LanApiFeedback.snackErro(
            context,
            e,
            prefixo: 'Cancelamento fiscal',
          );
        }
        return CancelarVendaUiResultado.erro;
      } finally {
        if (context.mounted) {
          Navigator.of(context, rootNavigator: true).pop();
        }
      }
    }

    if (exigeFiscal) {
      if (!context.mounted) {
        return CancelarVendaUiResultado.canceladoPeloUsuario;
      }
      showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (_) => const AlertDialog(
          content: Row(
            children: [
              CircularProgressIndicator(),
              SizedBox(width: 16),
              Expanded(child: Text('Cancelando documento fiscal na SEFAZ...')),
            ],
          ),
        ),
      );

      VendaFiscalOperacaoResultado fiscalRes;
      try {
        fiscalRes = await fiscalSvc!.cancelarDocumentosFiscaisVenda(
          venda: vendaAtual,
          justificativa: justificativaFiscal,
        );
      } catch (e) {
        if (context.mounted) {
          LanApiFeedback.snackErro(
            context,
            e,
            prefixo: 'Cancelamento fiscal',
          );
        }
        return CancelarVendaUiResultado.erro;
      } finally {
        if (context.mounted) {
          Navigator.of(context, rootNavigator: true).pop();
        }
      }

      if (!fiscalRes.sucesso) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                fiscalRes.mensagem.isNotEmpty
                    ? fiscalRes.mensagem
                    : 'Nao foi possivel cancelar o documento fiscal.',
              ),
            ),
          );
        }
        return CancelarVendaUiResultado.erro;
      }
    }

    final motivo = [
      if (justificativaFiscal.isNotEmpty) justificativaFiscal,
      if (motivoExtra.isNotEmpty) motivoExtra,
    ].join(' | ');

    try {
      final repo = vendaRepository;
      if (repo is VendaApiRepository) {
        await repo.cancelarVendaRemoto(
          vendaAtual.id,
          motivo: motivo,
          canceladaPor: autorizado.$2!.login,
        );
      } else {
        (repo as VendaRepository).cancelarVenda(
          vendaAtual.id,
          motivo: motivo,
          canceladaPor: autorizado.$2!.login,
          usuarioExecutor: autorizado.$2,
        );
      }
      if (!context.mounted) return CancelarVendaUiResultado.sucesso;
      final sufixoMotivo = motivo.isEmpty ? '' : ' Motivo: $motivo';
      final mensagemSucesso = tinhaNfceAtiva
          ? 'NFC-e cancelada com sucesso!'
          : '${rotuloVendaParaUsuario(vendaAtual)} cancelada por ${autorizado.$2!.login}.$sufixoMotivo';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(mensagemSucesso)),
      );
      return CancelarVendaUiResultado.sucesso;
    } catch (e) {
      if (context.mounted) {
        LanApiFeedback.snackErro(
          context,
          e,
          prefixo: 'Nao foi possivel cancelar venda',
        );
      }
      return CancelarVendaUiResultado.erro;
    }
  }
}
