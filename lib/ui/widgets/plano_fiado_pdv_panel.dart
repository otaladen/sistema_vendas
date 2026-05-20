import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../domain/plano_fiado.dart';

/// Painel para definir parcelas e vencimentos do fiado no PDV.
class PlanoFiadoPdvPanel extends StatefulWidget {
  const PlanoFiadoPdvPanel({
    super.key,
    required this.valorFiado,
    this.parcelasIniciais,
    required this.onChanged,
  });

  final double valorFiado;
  final List<PlanoFiadoParcela>? parcelasIniciais;
  final ValueChanged<List<PlanoFiadoParcela>> onChanged;

  @override
  State<PlanoFiadoPdvPanel> createState() => _PlanoFiadoPdvPanelState();
}

class _PlanoFiadoPdvPanelState extends State<PlanoFiadoPdvPanel> {
  static final _fmtData = DateFormat('dd/MM/yyyy');
  static final _fmtMoeda = NumberFormat.currency(locale: 'pt_BR', symbol: 'R\$');

  late int _quantidade;
  late DateTime _primeiroVencimento;
  late List<double> _valores;
  late List<DateTime> _vencimentos;
  /// Força recriação dos TextFormField após dividir igual ou mudar parcelas.
  int _versaoCampos = 0;

  @override
  void initState() {
    super.initState();
    _carregarInicial();
  }

  @override
  void didUpdateWidget(covariant PlanoFiadoPdvPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if ((oldWidget.valorFiado - widget.valorFiado).abs() > 0.02) {
      _carregarInicial();
    }
  }

  void _carregarInicial() {
    final ini = widget.parcelasIniciais;
    if (ini != null &&
        ini.isNotEmpty &&
        PlanoFiadoCodec.validarContraValor(ini, widget.valorFiado)) {
      _quantidade = ini.length;
      _primeiroVencimento = ini.first.vencimento.toLocal();
      _valores = ini.map((p) => p.valor).toList();
      _vencimentos = ini.map((p) => p.vencimento.toLocal()).toList();
    } else {
      _quantidade = 1;
      _primeiroVencimento = DateTime.now().add(const Duration(days: 30));
      final gerado = PlanoFiadoCodec.gerarParcelasIguais(
        valorTotal: widget.valorFiado,
        quantidade: _quantidade,
        primeiroVencimento: _primeiroVencimento,
      );
      _valores = gerado.map((p) => p.valor).toList();
      _vencimentos = gerado.map((p) => p.vencimento.toLocal()).toList();
    }
    _versaoCampos++;
    WidgetsBinding.instance.addPostFrameCallback((_) => _notificar());
  }

  void _regenerarParcelasIguais() {
    final gerado = PlanoFiadoCodec.gerarParcelasIguais(
      valorTotal: widget.valorFiado,
      quantidade: _quantidade,
      primeiroVencimento: _primeiroVencimento,
    );
    setState(() {
      _versaoCampos++;
      _valores = gerado.map((p) => p.valor).toList();
      _vencimentos = gerado.map((p) => p.vencimento.toLocal()).toList();
    });
    _notificar();
  }

  List<PlanoFiadoParcela> _montarParcelas() {
    final out = <PlanoFiadoParcela>[];
    for (var i = 0; i < _quantidade; i++) {
      out.add(
        PlanoFiadoParcela(
          numero: i + 1,
          valor: _valores[i],
          vencimento: _vencimentos[i],
        ),
      );
    }
    return out;
  }

  void _notificar() {
    widget.onChanged(_montarParcelas());
  }

  Future<void> _escolherData(int indice) async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _vencimentos[indice],
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
      locale: const Locale('pt', 'BR'),
    );
    if (picked == null) return;
    setState(() => _vencimentos[indice] = picked);
    _notificar();
  }

  Future<void> _escolherPrimeiroVencimento() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _primeiroVencimento,
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
      locale: const Locale('pt', 'BR'),
    );
    if (picked == null) return;
    setState(() => _primeiroVencimento = picked);
    _regenerarParcelasIguais();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final soma = _valores.fold<double>(0, (a, b) => a + b);
    final diff = (soma - widget.valorFiado).abs();
    final somaOk = diff <= 0.02;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: theme.colorScheme.primaryContainer.withValues(alpha: 0.25),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: theme.colorScheme.primary.withValues(alpha: 0.4)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Plano de quitação do fiado (${_fmtMoeda.format(widget.valorFiado)})',
            style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: DropdownButtonFormField<int>(
                  initialValue: _quantidade,
                  decoration: const InputDecoration(
                    labelText: 'Parcelas',
                    isDense: true,
                  ),
                  items: List.generate(
                    12,
                    (i) => DropdownMenuItem(value: i + 1, child: Text('${i + 1}x')),
                  ),
                  onChanged: (v) {
                    if (v == null) return;
                    setState(() => _quantidade = v);
                    _regenerarParcelasIguais();
                  },
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                flex: 2,
                child: OutlinedButton.icon(
                  onPressed: _escolherPrimeiroVencimento,
                  icon: const Icon(Icons.event_outlined, size: 18),
                  label: Text('1º venc.: ${_fmtData.format(_primeiroVencimento)}'),
                ),
              ),
              const SizedBox(width: 8),
              TextButton(
                onPressed: _regenerarParcelasIguais,
                child: const Text('Dividir igual'),
              ),
            ],
          ),
          const SizedBox(height: 6),
          ...List.generate(_quantidade, (i) {
            return Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Row(
                children: [
                  SizedBox(
                    width: 28,
                    child: Text(
                      '${i + 1}.',
                      style: theme.textTheme.bodySmall?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  SizedBox(
                    width: 100,
                    child: TextFormField(
                      // Inclui quantidade no key: ao mudar 1x→2x o campo
                      // precisa recriar; senão initialValue fica obsoleto (ex.: 45+22,50).
                      key: ValueKey(
                        'pf-$i-$_quantidade-$_versaoCampos-${widget.valorFiado.toStringAsFixed(2)}',
                      ),
                      initialValue: _valores[i].toStringAsFixed(2).replaceAll('.', ','),
                      decoration: const InputDecoration(
                        labelText: 'Valor',
                        isDense: true,
                      ),
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      onChanged: (t) {
                        final v = double.tryParse(
                              t.replaceAll('.', '').replaceAll(',', '.'),
                            ) ??
                            0;
                        _valores[i] = v;
                        _notificar();
                      },
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => _escolherData(i),
                      child: Text(_fmtData.format(_vencimentos[i])),
                    ),
                  ),
                ],
              ),
            );
          }),
          Text(
            somaOk
                ? 'Soma das parcelas: ${_fmtMoeda.format(soma)}'
                : 'Soma ${_fmtMoeda.format(soma)} difere do fiado ${_fmtMoeda.format(widget.valorFiado)}',
            style: theme.textTheme.bodySmall?.copyWith(
              color: somaOk ? theme.colorScheme.primary : theme.colorScheme.error,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}
