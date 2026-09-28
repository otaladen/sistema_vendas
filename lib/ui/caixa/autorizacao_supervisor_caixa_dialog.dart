import 'dart:async';

import 'package:flutter/material.dart';

/// Fecha [dialogContext] somente depois que [autorizar] retorna verdadeiro.
///
/// Senha errada ou cancelamento devolvem false e deixam o dialogo de origem
/// aberto, para a contagem ja digitada no fechamento nao ser descartada.
Future<bool> popDialogoSomenteSeAutorizado({
  required BuildContext dialogContext,
  required Future<bool> Function() autorizar,
}) async {
  final ok = await autorizar();
  if (!dialogContext.mounted || !ok) return false;
  Navigator.pop(dialogContext, true);
  return true;
}

/// Login e senha de supervisor/administrador no fechamento do caixa.
///
/// Credencial recusada nao fecha este dialogo: o operador corrige a senha
/// sem perder os valores ja preenchidos no fechamento, que continua aberto
/// por baixo.
class AutorizacaoSupervisorCaixaDialog extends StatefulWidget {
  const AutorizacaoSupervisorCaixaDialog({
    super.key,
    required this.mensagem,
    required this.validarCredenciais,
    this.aoCredencialNegada,
  });

  final String mensagem;
  final Future<bool> Function(String login, String senha) validarCredenciais;
  final Future<void> Function()? aoCredencialNegada;

  @override
  State<AutorizacaoSupervisorCaixaDialog> createState() =>
      _AutorizacaoSupervisorCaixaDialogState();
}

class _AutorizacaoSupervisorCaixaDialogState
    extends State<AutorizacaoSupervisorCaixaDialog> {
  final _loginController = TextEditingController();
  final _senhaController = TextEditingController();
  final _senhaFocus = FocusNode();
  var _enviando = false;
  String? _erro;

  @override
  void dispose() {
    _loginController.dispose();
    _senhaController.dispose();
    _senhaFocus.dispose();
    super.dispose();
  }

  Future<void> _autorizar() async {
    if (_enviando) return;
    final login = _loginController.text.trim();
    final senha = _senhaController.text.trim();
    if (login.isEmpty || senha.isEmpty) {
      setState(() => _erro = 'Preencha login e senha.');
      return;
    }
    setState(() {
      _enviando = true;
      _erro = null;
    });
    bool ok = false;
    try {
      ok = await widget.validarCredenciais(login, senha);
    } catch (e) {
      debugPrint('Caixa: autenticar supervisor: $e');
      if (!mounted) return;
      setState(() {
        _enviando = false;
        _erro = 'Nao foi possivel validar as credenciais. Tente novamente.';
      });
      return;
    }
    if (!mounted) return;
    if (!ok) {
      try {
        await widget.aoCredencialNegada?.call();
      } catch (e) {
        debugPrint('Caixa: auditoria de fechamento negado: $e');
      }
      if (!mounted) return;
      _senhaController.clear();
      setState(() {
        _enviando = false;
        _erro = 'Credenciais sem permissao de supervisor/financeiro.';
      });
      _senhaFocus.requestFocus();
      return;
    }
    Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    final erro = _erro;
    return AlertDialog(
      title: const Text('Autorizacao de supervisor'),
      content: SingleChildScrollView(
        child: SizedBox(
          width: 420,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(widget.mensagem),
              if (erro != null) ...[
                const SizedBox(height: 10),
                Text(
                  erro,
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.error,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
              const SizedBox(height: 10),
              TextField(
                controller: _loginController,
                enabled: !_enviando,
                autofocus: true,
                textInputAction: TextInputAction.next,
                decoration: const InputDecoration(labelText: 'Login'),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _senhaController,
                focusNode: _senhaFocus,
                enabled: !_enviando,
                obscureText: true,
                textInputAction: TextInputAction.done,
                onSubmitted: (_) {
                  unawaited(_autorizar());
                },
                decoration: const InputDecoration(labelText: 'Senha'),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _enviando ? null : () => Navigator.of(context).pop(false),
          child: const Text('Cancelar'),
        ),
        ElevatedButton(
          onPressed: _enviando ? null : () => unawaited(_autorizar()),
          child: const Text('Autorizar'),
        ),
      ],
    );
  }
}
