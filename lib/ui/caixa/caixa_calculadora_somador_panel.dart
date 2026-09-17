import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

/// Utilitários de valor no padrão PT-BR (campo de caixa).
class CaixaValorPtBr {
  CaixaValorPtBr._();

  static final NumberFormat _campo = NumberFormat('#,##0.00', 'pt_BR');
  static final NumberFormat _moeda = NumberFormat.currency(
    locale: 'pt_BR',
    symbol: r'R$',
  );

  static String textoCampo(double valor) => _campo.format(valor);

  static String textoMoeda(double valor) => _moeda.format(valor);

  static double? parse(String texto) {
    final normalizado = texto.trim().replaceAll('.', '').replaceAll(',', '.');
    if (normalizado.isEmpty) return null;
    return double.tryParse(normalizado);
  }

  /// Aceita expressões como `15 + 15 + 2,50` ou um único valor.
  static double? parseExpressaoSoma(String texto) {
    final partes = texto.split('+');
    var total = 0.0;
    var algum = false;
    for (final parte in partes) {
      final t = parte.trim();
      if (t.isEmpty) continue;
      final v = parse(t);
      if (v == null) return null;
      total += v;
      algum = true;
    }
    return algum ? total : null;
  }
}

/// Painel flutuante / conteúdo de diálogo: fita de soma + contagem de cédulas.
class CaixaCalculadoraSomadorPanel extends StatefulWidget {
  const CaixaCalculadoraSomadorPanel({
    super.key,
    required this.onFechar,
    required this.onTransferir,
    required this.destinoDisponivel,
    this.compacto = false,
  });

  final VoidCallback onFechar;
  final void Function(double valor) onTransferir;
  final bool destinoDisponivel;
  final bool compacto;

  @override
  State<CaixaCalculadoraSomadorPanel> createState() =>
      _CaixaCalculadoraSomadorPanelState();
}

class _CaixaCalculadoraSomadorPanelState
    extends State<CaixaCalculadoraSomadorPanel>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs;
  final _entradaController = TextEditingController();
  final _entradaFocus = FocusNode();
  final List<double> _fita = [];

  static const _cedulas = <double>[
    200,
    100,
    50,
    20,
    10,
    5,
    2,
  ];

  static const _moedas = <double>[
    1,
    0.50,
    0.25,
    0.10,
    0.05,
  ];

  final Map<double, TextEditingController> _qtdPorValor = {};

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 2, vsync: this);
    for (final v in [..._cedulas, ..._moedas]) {
      _qtdPorValor[v] = TextEditingController(text: '0');
    }
    _tabs.addListener(() {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _tabs.dispose();
    _entradaController.dispose();
    _entradaFocus.dispose();
    for (final c in _qtdPorValor.values) {
      c.dispose();
    }
    super.dispose();
  }

  double get _totalFita =>
      _fita.fold<double>(0, (s, v) => s + v);

  double get _totalCedulasMoedas {
    var total = 0.0;
    for (final entry in _qtdPorValor.entries) {
      final qtd = int.tryParse(entry.value.text.trim()) ?? 0;
      if (qtd <= 0) continue;
      total += qtd * entry.key;
    }
    return total;
  }

  double get _totalAtivo =>
      _tabs.index == 0 ? _totalFita : _totalCedulasMoedas;

  String get _textoFita {
    if (_fita.isEmpty) return '(vazio)';
    return _fita
        .map((v) => CaixaValorPtBr.textoCampo(v))
        .join(' + ');
  }

  void _adicionarEntrada() {
    final parsed =
        CaixaValorPtBr.parseExpressaoSoma(_entradaController.text);
    if (parsed == null || parsed <= 0) {
      return;
    }
    setState(() {
      _fita.add(parsed);
      _entradaController.clear();
    });
    _entradaFocus.requestFocus();
  }

  void _limparFita() {
    setState(_fita.clear);
  }

  void _limparCedulas() {
    setState(() {
      for (final c in _qtdPorValor.values) {
        c.text = '0';
      }
    });
  }

  String _rotuloDenominacao(double valor) {
    if (valor >= 1) {
      return 'R\$ ${valor.toStringAsFixed(valor == valor.roundToDouble() ? 0 : 2)}';
    }
    return 'R\$ ${CaixaValorPtBr.textoCampo(valor)}';
  }

  Widget _linhaQuantidade(double valor) {
    final controller = _qtdPorValor[valor]!;
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        children: [
          Expanded(
            flex: 2,
            child: Text(
              _rotuloDenominacao(valor),
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          ),
          SizedBox(
            width: 72,
            child: TextField(
              controller: controller,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              decoration: const InputDecoration(
                labelText: 'Qtd',
                isDense: true,
              ),
              onChanged: (_) => setState(() {}),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              CaixaValorPtBr.textoMoeda(
                (int.tryParse(controller.text.trim()) ?? 0) * valor,
              ),
              textAlign: TextAlign.end,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final largura = widget.compacto ? 360.0 : 420.0;

    return Material(
      elevation: 8,
      borderRadius: BorderRadius.circular(12),
      color: scheme.surface,
      clipBehavior: Clip.antiAlias,
      child: SizedBox(
        width: largura,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 10, 4, 0),
              child: Row(
                children: [
                  Icon(
                    Icons.calculate_outlined,
                    size: 22,
                    color: scheme.primary,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Calculadora / Somador de Caixa',
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: 'Fechar (F9)',
                    onPressed: widget.onFechar,
                    icon: const Icon(Icons.close),
                    visualDensity: VisualDensity.compact,
                  ),
                ],
              ),
            ),
            TabBar(
              controller: _tabs,
              tabs: const [
                Tab(text: 'Somador'),
                Tab(text: 'Cédulas e moedas'),
              ],
            ),
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 340),
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(12, 10, 12, 8),
                child: AnimatedBuilder(
                  animation: _tabs,
                  builder: (context, _) {
                    if (_tabs.index == 0) {
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Text(
                            'Fita de contagem',
                            style: theme.textTheme.labelLarge,
                          ),
                          const SizedBox(height: 4),
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              color: scheme.surfaceContainerHighest,
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(
                                color: scheme.outlineVariant,
                              ),
                            ),
                            child: Text(
                              _textoFita,
                              style: theme.textTheme.bodyMedium?.copyWith(
                                fontFeatures: const [
                                  FontFeature.tabularFigures(),
                                ],
                              ),
                            ),
                          ),
                          const SizedBox(height: 8),
                          TextField(
                            controller: _entradaController,
                            focusNode: _entradaFocus,
                            decoration: const InputDecoration(
                              labelText: 'Valor ou soma (Enter)',
                              hintText: 'Ex.: 15 + 15 + 2,50',
                              isDense: true,
                            ),
                            onSubmitted: (_) => _adicionarEntrada(),
                          ),
                          const SizedBox(height: 6),
                          Row(
                            children: [
                              TextButton.icon(
                                onPressed: _adicionarEntrada,
                                icon: const Icon(Icons.add, size: 18),
                                label: const Text('Adicionar'),
                              ),
                              TextButton(
                                onPressed:
                                    _fita.isEmpty ? null : _limparFita,
                                child: const Text('Limpar fita'),
                              ),
                            ],
                          ),
                        ],
                      );
                    }
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Cédulas',
                          style: theme.textTheme.labelLarge,
                        ),
                        const SizedBox(height: 4),
                        ..._cedulas.map(_linhaQuantidade),
                        const SizedBox(height: 8),
                        Text(
                          'Moedas',
                          style: theme.textTheme.labelLarge,
                        ),
                        const SizedBox(height: 4),
                        ..._moedas.map(_linhaQuantidade),
                        Align(
                          alignment: Alignment.centerRight,
                          child: TextButton(
                            onPressed:
                                _totalCedulasMoedas <= 0 ? null : _limparCedulas,
                            child: const Text('Zerar quantidades'),
                          ),
                        ),
                      ],
                    );
                  },
                ),
              ),
            ),
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    'TOTAL CALCULADO: ${CaixaValorPtBr.textoMoeda(_totalAtivo)}',
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w800,
                      color: scheme.primary,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                  if (!widget.destinoDisponivel) ...[
                    const SizedBox(height: 4),
                    Text(
                      'Abra fechamento, suprimento ou sangria (ou use o ícone '
                      'ao lado do valor) para transferir.',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                  const SizedBox(height: 8),
                  FilledButton.icon(
                    onPressed: _totalAtivo > 0 && widget.destinoDisponivel
                        ? () => widget.onTransferir(_totalAtivo)
                        : null,
                    icon: const Icon(Icons.input_outlined, size: 20),
                    label: const Text('Transferir para o Caixa'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

Future<void> showCaixaCalculadoraSomadorDialog(
  BuildContext context, {
  required void Function(double valor) onTransferir,
  required bool destinoDisponivel,
}) {
  return showDialog<void>(
    context: context,
    builder: (ctx) {
      return Dialog(
        insetPadding: const EdgeInsets.all(24),
        child: CaixaCalculadoraSomadorPanel(
          onFechar: () => Navigator.pop(ctx),
          onTransferir: (v) {
            onTransferir(v);
            Navigator.pop(ctx);
          },
          destinoDisponivel: destinoDisponivel,
        ),
      );
    },
  );
}
