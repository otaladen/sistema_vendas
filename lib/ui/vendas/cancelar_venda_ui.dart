import 'package:flutter/material.dart';

import '../../data/cliente_repository.dart';
import '../../data/usuario_repository.dart';
import '../../data/venda_repository.dart';
import '../../model/venda.dart';
import '../../services/venda_fiscal_service.dart';
import '../fiscal/widgets/nfe_historico_acoes_dialog.dart';

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

  static Future<(bool autorizado, String usuarioAutorizador)> autorizar({
    required BuildContext context,
    required UsuarioRepository usuarioRepository,
    required String usuarioAtual,
    required bool podeCancelarVendas,
  }) async {
    if (podeCancelarVendas) {
      return (true, usuarioAtual);
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
                  'Informe usuario com permissao (admin/financeiro/manutencao de caixa).',
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
      return (false, '');
    }
    final login = loginController.text.trim();
    final senha = senhaController.text.trim();
    loginController.dispose();
    senhaController.dispose();
    final usuario = await usuarioRepository.autenticar(login, senha);
    final autorizado = usuario != null &&
        usuario.ativo &&
        (usuario.admin ||
            usuario.podeFinanceiro ||
            usuario.podeManutencaoAuditoriaCaixa);
    if (!autorizado) {
      return (false, '');
    }
    return (true, usuario.login);
  }

  static Future<CancelarVendaUiResultado> executar({
    required BuildContext context,
    required VendaRepository vendaRepository,
    required ClienteRepository clienteRepository,
    required UsuarioRepository usuarioRepository,
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
    if (!context.mounted || !autorizado.$1) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Cancelamento nao autorizado.')),
        );
      }
      return CancelarVendaUiResultado.naoAutorizado;
    }

    final vendaAtual = vendaRepository.obterPorId(venda.id) ?? venda;
    final fiscalSvc = VendaFiscalService(
      vendaRepository: vendaRepository,
      clienteRepository: clienteRepository,
    );
    final exigeFiscal = fiscalSvc.vendaExigeCancelamentoFiscal(vendaAtual);

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

      final fiscalRes = await fiscalSvc.cancelarDocumentosFiscaisVenda(
        venda: vendaAtual,
        justificativa: justificativaFiscal,
      );

      if (context.mounted) Navigator.of(context).pop();

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
      vendaRepository.cancelarVenda(
        vendaAtual.id,
        motivo: motivo,
        canceladaPor: autorizado.$2,
      );
      if (!context.mounted) return CancelarVendaUiResultado.sucesso;
      final sufixoMotivo = motivo.isEmpty ? '' : ' Motivo: $motivo';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '${rotuloVendaParaUsuario(vendaAtual)} cancelada por ${autorizado.$2}.$sufixoMotivo',
          ),
        ),
      );
      return CancelarVendaUiResultado.sucesso;
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Nao foi possivel cancelar venda: $e')),
        );
      }
      return CancelarVendaUiResultado.erro;
    }
  }
}
