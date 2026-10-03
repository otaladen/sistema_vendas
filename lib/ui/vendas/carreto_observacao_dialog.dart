import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../domain/entregas/observacao_carreto.dart';

/// Abre o modal de observacoes do carreto.
///
/// [observacaoInicial] e o texto editavel (sem historico do patio; ver
/// [ObservacaoCarreto.textoEditavel]). Devolve o texto normalizado ao salvar
/// ou `null` ao cancelar.
Future<String?> mostrarCarretoObservacaoDialog(
  BuildContext context, {
  required String observacaoInicial,
  String clienteNome = '',
  String enderecoResumo = '',
}) {
  return showDialog<String>(
    context: context,
    barrierDismissible: false,
    builder: (_) => CarretoObservacaoDialog(
      observacaoInicial: observacaoInicial,
      clienteNome: clienteNome,
      enderecoResumo: enderecoResumo,
    ),
  );
}

class CarretoObservacaoDialog extends StatefulWidget {
  const CarretoObservacaoDialog({
    super.key,
    required this.observacaoInicial,
    this.clienteNome = '',
    this.enderecoResumo = '',
  });

  final String observacaoInicial;
  final String clienteNome;
  final String enderecoResumo;

  static const keyCampo = Key('carretoObsCampo');
  static const keySalvar = Key('carretoObsSalvar');
  static const keyCancelar = Key('carretoObsCancelar');
  static const keyLimpar = Key('carretoObsLimpar');
  static const keyPreview = Key('carretoObsPreview');

  @override
  State<CarretoObservacaoDialog> createState() =>
      _CarretoObservacaoDialogState();
}

class _SalvarIntent extends Intent {
  const _SalvarIntent();
}

class _CancelarIntent extends Intent {
  const _CancelarIntent();
}

class _CarretoObservacaoDialogState extends State<CarretoObservacaoDialog> {
  late final TextEditingController _controller = TextEditingController(
    text: widget.observacaoInicial,
  );

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  List<String> get _linhas => ObservacaoCarreto.normalizar(
    _controller.text,
  ).split('\n').where((l) => l.isNotEmpty).toList();

  bool _temSugestao(String sugestao) {
    final alvo = sugestao.toLowerCase();
    return _linhas.any((l) => l.toLowerCase() == alvo);
  }

  void _alternarSugestao(String sugestao) {
    final linhas = _linhas;
    final alvo = sugestao.toLowerCase();
    if (linhas.any((l) => l.toLowerCase() == alvo)) {
      linhas.removeWhere((l) => l.toLowerCase() == alvo);
    } else {
      linhas.add(sugestao);
    }
    var texto = linhas.join('\n');
    if (texto.length > ObservacaoCarreto.limiteCaracteres) {
      texto = texto.substring(0, ObservacaoCarreto.limiteCaracteres);
    }
    _controller.value = TextEditingValue(
      text: texto,
      selection: TextSelection.collapsed(offset: texto.length),
    );
    setState(() {});
  }

  void _salvar() {
    Navigator.of(context).pop(ObservacaoCarreto.normalizar(_controller.text));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final largura = MediaQuery.sizeOf(context).width;
    final compacto = largura < 600;
    final subtitulo = [
      widget.clienteNome.trim(),
      widget.enderecoResumo.trim(),
    ].where((p) => p.isNotEmpty).join(' · ');

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
          insetPadding: compacto
              ? const EdgeInsets.symmetric(horizontal: 10, vertical: 16)
              : const EdgeInsets.symmetric(horizontal: 40, vertical: 24),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
          clipBehavior: Clip.antiAlias,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 620),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Container(
                  color: scheme.primaryContainer,
                  padding: const EdgeInsets.fromLTRB(18, 14, 12, 14),
                  child: Row(
                    children: [
                      Icon(
                        Icons.local_shipping_outlined,
                        color: scheme.onPrimaryContainer,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Observações do carreto',
                              style: theme.textTheme.titleMedium?.copyWith(
                                fontWeight: FontWeight.w800,
                                color: scheme.onPrimaryContainer,
                              ),
                            ),
                            if (subtitulo.isNotEmpty)
                              Text(
                                subtitulo,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: scheme.onPrimaryContainer,
                                ),
                              ),
                          ],
                        ),
                      ),
                      IconButton(
                        tooltip: 'Fechar (Esc)',
                        onPressed: () => Navigator.of(context).pop(),
                        icon: Icon(
                          Icons.close,
                          color: scheme.onPrimaryContainer,
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
                        TextField(
                          key: CarretoObservacaoDialog.keyCampo,
                          controller: _controller,
                          autofocus: true,
                          minLines: 3,
                          maxLines: 7,
                          maxLength: ObservacaoCarreto.limiteCaracteres,
                          keyboardType: TextInputType.multiline,
                          textCapitalization: TextCapitalization.sentences,
                          onChanged: (_) => setState(() {}),
                          decoration: const InputDecoration(
                            labelText: 'Instruções para o pátio e o motorista',
                            hintText:
                                'Ex.: portão azul, descarregar na garagem, '
                                'ligar antes de sair...',
                            alignLabelWithHint: true,
                            border: OutlineInputBorder(),
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Sugestões rápidas',
                          style: theme.textTheme.labelLarge,
                        ),
                        const SizedBox(height: 6),
                        Wrap(
                          spacing: 6,
                          runSpacing: 6,
                          children: [
                            for (final s in ObservacaoCarreto.sugestoesRapidas)
                              FilterChip(
                                label: Text(s),
                                selected: _temSugestao(s),
                                visualDensity: VisualDensity.compact,
                                onSelected: (_) => _alternarSugestao(s),
                              ),
                          ],
                        ),
                        const SizedBox(height: 14),
                        _PreviewImpressao(linhas: _linhas),
                      ],
                    ),
                  ),
                ),
                const Divider(height: 1),
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
                  child: Wrap(
                    alignment: WrapAlignment.end,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      TextButton.icon(
                        key: CarretoObservacaoDialog.keyLimpar,
                        onPressed: _controller.text.isEmpty
                            ? null
                            : () => setState(_controller.clear),
                        icon: const Icon(Icons.backspace_outlined, size: 18),
                        label: const Text('Limpar'),
                      ),
                      OutlinedButton(
                        key: CarretoObservacaoDialog.keyCancelar,
                        onPressed: () => Navigator.of(context).pop(),
                        child: const Text('Cancelar (Esc)'),
                      ),
                      FilledButton.icon(
                        key: CarretoObservacaoDialog.keySalvar,
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

/// Como o bloco sai no comprovante do patio e no romaneio.
class _PreviewImpressao extends StatelessWidget {
  const _PreviewImpressao({required this.linhas});

  final List<String> linhas;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    const mono = TextStyle(
      fontFamily: 'Courier New',
      fontFamilyFallback: ['Courier', 'monospace'],
      fontWeight: FontWeight.w800,
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Como sai no comprovante do pátio e no romaneio',
          style: theme.textTheme.labelLarge,
        ),
        const SizedBox(height: 6),
        Container(
          key: CarretoObservacaoDialog.keyPreview,
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: scheme.surfaceContainerLowest,
            border: Border.all(color: scheme.onSurface, width: 1.4),
            borderRadius: BorderRadius.circular(4),
          ),
          child: linhas.isEmpty
              ? Text(
                  'Sem observações: o bloco não é impresso.',
                  style: theme.textTheme.bodySmall?.copyWith(
                    fontStyle: FontStyle.italic,
                  ),
                )
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      ObservacaoCarreto.tituloImpressao,
                      style: mono.copyWith(fontSize: 14),
                    ),
                    const SizedBox(height: 4),
                    for (final l in linhas)
                      Text(
                        '> ${l.toUpperCase()}',
                        style: mono.copyWith(fontSize: 13),
                      ),
                  ],
                ),
        ),
      ],
    );
  }
}
