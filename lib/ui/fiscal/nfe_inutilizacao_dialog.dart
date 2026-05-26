import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../services/auditoria_registrar.dart';
import '../../domain/auditoria_catalogo.dart';
import '../../services/fiscal_config_store.dart';
import '../../services/focus_nfe_service.dart';
import '../layout/app_layout.dart';

/// Inutilizacao de numeracao NF-e (POST Focus /v2/nfe/inutilizacao).
Future<void> showNfeInutilizacaoDialog({
  required BuildContext context,
  required FocusNfeService focusNfe,
  required String usuarioLogin,
}) {
  return showDialog<void>(
    context: context,
    useRootNavigator: true,
    builder: (ctx) => _NfeInutilizacaoDialog(
      focusNfe: focusNfe,
      usuarioLogin: usuarioLogin,
    ),
  );
}

class _NfeInutilizacaoDialog extends StatefulWidget {
  const _NfeInutilizacaoDialog({
    required this.focusNfe,
    required this.usuarioLogin,
  });

  final FocusNfeService focusNfe;
  final String usuarioLogin;

  @override
  State<_NfeInutilizacaoDialog> createState() => _NfeInutilizacaoDialogState();
}

class _NfeInutilizacaoDialogState extends State<_NfeInutilizacaoDialog> {
  final _serie = TextEditingController(text: '1');
  final _numIni = TextEditingController();
  final _numFim = TextEditingController();
  final _just = TextEditingController();
  bool _processando = false;

  @override
  void dispose() {
    _serie.dispose();
    _numIni.dispose();
    _numFim.dispose();
    _just.dispose();
    super.dispose();
  }

  Future<void> _confirmar() async {
    final ini = int.tryParse(_numIni.text.trim()) ?? 0;
    final fim = int.tryParse(_numFim.text.trim()) ?? 0;
    final just = _just.text.trim();
    if (just.length < 15) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Justificativa com no minimo 15 caracteres.'),
        ),
      );
      return;
    }
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Confirmar inutilizacao'),
        content: Text(
          'Inutilizar numeros $ini a $fim serie ${_serie.text.trim()}?\n\n'
          'Acao irreversivel na SEFAZ.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c, false),
            child: const Text('Voltar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(c, true),
            child: const Text('Confirmar'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;

    setState(() => _processando = true);
    final r = await widget.focusNfe.inutilizarNumeracaoNfe(
      cnpjEmitente: FiscalConfigStore.efetivo.cnpjEmitente,
      serie: _serie.text,
      numeroInicial: ini,
      numeroFinal: fim,
      justificativa: just,
    );
    if (!mounted) return;
    setState(() => _processando = false);

    if (r.sucesso) {
      AuditoriaRegistrar.registrar(
        modulo: AuditoriaModulo.fiscal,
        acao: AuditoriaAcao.nfeInutilizar,
        usuarioLogin: widget.usuarioLogin,
        resumo: 'Inutilizacao NF-e serie ${_serie.text} $ini-$fim',
        detalhes: {'serie': _serie.text, 'ini': ini, 'fim': fim},
      );
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            r.mensagem.isNotEmpty ? r.mensagem : 'Inutilizacao enviada.',
          ),
        ),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(r.mensagem)),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Inutilizar numeracao NF-e'),
      content: AdaptiveDialogContent(
        desktopWidth: 480,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'Use quando pulou numeros na serie e nao emitiu nota. '
              'Homologacao: apenas testes.',
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _serie,
              decoration: const InputDecoration(
                labelText: 'Serie',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _numIni,
                    keyboardType: TextInputType.number,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    decoration: const InputDecoration(
                      labelText: 'Numero inicial',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: TextField(
                    controller: _numFim,
                    keyboardType: TextInputType.number,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    decoration: const InputDecoration(
                      labelText: 'Numero final',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _just,
              maxLines: 4,
              decoration: const InputDecoration(
                labelText: 'Justificativa (min. 15 caracteres)',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _processando ? null : () => Navigator.pop(context),
          child: const Text('Fechar'),
        ),
        FilledButton(
          onPressed: _processando ? null : _confirmar,
          child: _processando
              ? const SizedBox(
                  width: 22,
                  height: 22,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('Inutilizar na SEFAZ'),
        ),
      ],
    );
  }
}
