import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../domain/observacao_nota.dart';

Future<String?> mostrarNotaObservacaoDialog(
  BuildContext context, {
  required String observacaoInicial,
}) {
  return showDialog<String>(
    context: context,
    barrierDismissible: false,
    builder: (_) => NotaObservacaoDialog(observacaoInicial: observacaoInicial),
  );
}

class NotaObservacaoDialog extends StatefulWidget {
  const NotaObservacaoDialog({super.key, required this.observacaoInicial});

  final String observacaoInicial;

  static const keyCampo = Key('notaObsCampo');
  static const keySalvar = Key('notaObsSalvar');
  static const keyCancelar = Key('notaObsCancelar');

  @override
  State<NotaObservacaoDialog> createState() => _NotaObservacaoDialogState();
}

class _SalvarIntent extends Intent {
  const _SalvarIntent();
}

class _CancelarIntent extends Intent {
  const _CancelarIntent();
}

class _NotaObservacaoDialogState extends State<NotaObservacaoDialog> {
  late final TextEditingController _controller = TextEditingController(
    text: widget.observacaoInicial,
  );

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  List<String> get _linhas => ObservacaoNota.linhasDigitadas(_controller.text);

  bool _temSugestao(String sugestao) {
    final alvo = sugestao.toLowerCase();
    return _linhas.any((l) => l.toLowerCase() == alvo);
  }

  void _alternarSugestao(String sugestao) {
    final linhas = List<String>.from(_linhas);
    final alvo = sugestao.toLowerCase();
    if (linhas.any((l) => l.toLowerCase() == alvo)) {
      linhas.removeWhere((l) => l.toLowerCase() == alvo);
    } else {
      linhas.add(sugestao);
    }
    var texto = linhas.join('\n');
    if (texto.length > ObservacaoNota.limiteCaracteres) {
      texto = texto.substring(0, ObservacaoNota.limiteCaracteres);
    }
    _controller.value = TextEditingValue(
      text: texto,
      selection: TextSelection.collapsed(offset: texto.length),
    );
    setState(() {});
  }

  void _salvar() {
    Navigator.of(context).pop(ObservacaoNota.normalizar(_controller.text));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Shortcuts(
      shortcuts: const <ShortcutActivator, Intent>{
        SingleActivator(LogicalKeyboardKey.enter, control: true):
            _SalvarIntent(),
        SingleActivator(LogicalKeyboardKey.numpadEnter, control: true):
            _SalvarIntent(),
        SingleActivator(LogicalKeyboardKey.escape): _CancelarIntent(),
      },
      child: Actions(
        actions: <Type, Action<Intent>>{
          _SalvarIntent: CallbackAction<_SalvarIntent>(
            onInvoke: (_) {
              _salvar();
              return null;
            },
          ),
          _CancelarIntent: CallbackAction<_CancelarIntent>(
            onInvoke: (_) {
              Navigator.of(context).pop();
              return null;
            },
          ),
        },
        child: Dialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          clipBehavior: Clip.antiAlias,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 620),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Container(
                  color: scheme.secondaryContainer,
                  padding: const EdgeInsets.fromLTRB(18, 14, 12, 14),
                  child: Row(
                    children: [
                      Icon(
                        Icons.description_outlined,
                        color: scheme.onSecondaryContainer,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          'Observações da nota',
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w800,
                            color: scheme.onSecondaryContainer,
                          ),
                        ),
                      ),
                      IconButton(
                        tooltip: 'Fechar (Esc)',
                        onPressed: () => Navigator.of(context).pop(),
                        icon: Icon(
                          Icons.close,
                          color: scheme.onSecondaryContainer,
                        ),
                      ),
                    ],
                  ),
                ),
                Flexible(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(18, 16, 18, 8),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text(
                          'Detalhes do pedido para separacao, nota fiscal e '
                          'cupom — nao e instrucao de carreto.',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: scheme.onSurfaceVariant,
                          ),
                        ),
                        const SizedBox(height: 12),
                        TextField(
                          key: NotaObservacaoDialog.keyCampo,
                          controller: _controller,
                          autofocus: true,
                          minLines: 3,
                          maxLines: 7,
                          maxLength: ObservacaoNota.limiteCaracteres,
                          keyboardType: TextInputType.multiline,
                          textCapitalization: TextCapitalization.sentences,
                          onChanged: (_) => setState(() {}),
                          decoration: const InputDecoration(
                            labelText: 'Especificacao do material / pedido',
                            hintText:
                                'Ex.: tinta cor RAL 9003, telha colonial, '
                                'cliente pediu marca X...',
                            alignLabelWithHint: true,
                            border: OutlineInputBorder(),
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Sugestões rápidas',
                          style: theme.textTheme.labelLarge,
                        ),
                        const SizedBox(height: 6),
                        Wrap(
                          spacing: 6,
                          runSpacing: 6,
                          children: [
                            for (final s in ObservacaoNota.sugestoesRapidas)
                              FilterChip(
                                label: Text(s),
                                selected: _temSugestao(s),
                                visualDensity: VisualDensity.compact,
                                onSelected: (_) => _alternarSugestao(s),
                              ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
                const Divider(height: 1),
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
                  child: Wrap(
                    alignment: WrapAlignment.end,
                    spacing: 8,
                    children: [
                      OutlinedButton(
                        key: NotaObservacaoDialog.keyCancelar,
                        onPressed: () => Navigator.of(context).pop(),
                        child: const Text('Cancelar (Esc)'),
                      ),
                      FilledButton.icon(
                        key: NotaObservacaoDialog.keySalvar,
                        onPressed: _salvar,
                        icon: const Icon(Icons.check),
                        label: const Text('Salvar (Ctrl+Enter)'),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
