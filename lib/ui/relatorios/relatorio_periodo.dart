import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

/// Intervalo de datas para filtros de relatorio.
typedef LimitesPeriodo = (DateTime inicio, DateTime fim);

/// Calcula limites de periodo a partir de presets (uso sem widget).
LimitesPeriodo calcularLimitesPeriodo({
  String preset = 'mes_atual',
  DateTime? customInicio,
  DateTime? customFim,
}) {
  final now = DateTime.now();
  final fimDia = DateTime(now.year, now.month, now.day, 23, 59, 59, 999);
  switch (preset) {
    case 'hoje':
      final i = DateTime(now.year, now.month, now.day);
      return (i, fimDia);
    case 'ultimos_7':
      final i = DateTime(now.year, now.month, now.day).subtract(
        const Duration(days: 6),
      );
      return (i, fimDia);
    case 'ultimos_30':
      final i = DateTime(now.year, now.month, now.day).subtract(
        const Duration(days: 29),
      );
      return (i, fimDia);
    case 'mes_atual':
      return (DateTime(now.year, now.month, 1), fimDia);
    case 'mes_anterior':
      final i = DateTime(now.year, now.month - 1, 1);
      final f = DateTime(now.year, now.month, 0, 23, 59, 59, 999);
      return (i, f);
    case 'ano_atual':
      return (DateTime(now.year, 1, 1), fimDia);
    case 'personalizado':
      final a = customInicio ?? DateTime(now.year, now.month, now.day);
      final b = customFim ?? fimDia;
      final ini = DateTime(a.year, a.month, a.day);
      final f = DateTime(b.year, b.month, b.day, 23, 59, 59, 999);
      return (ini, f);
    default:
      return (DateTime(now.year, now.month, 1), fimDia);
  }
}

String formatarIntervaloPeriodo(LimitesPeriodo limites) {
  final fmt = DateFormat('dd/MM/yyyy');
  return '${fmt.format(limites.$1)} — ${fmt.format(limites.$2)}';
}

/// Seletor de periodo padrao para relatorios gerenciais.
class RelatorioSeletorPeriodo extends StatefulWidget {
  const RelatorioSeletorPeriodo({
    super.key,
    required this.onChanged,
    this.label = 'Periodo',
  });

  final void Function(LimitesPeriodo limites) onChanged;
  final String label;

  @override
  State<RelatorioSeletorPeriodo> createState() =>
      _RelatorioSeletorPeriodoState();
}

class _RelatorioSeletorPeriodoState extends State<RelatorioSeletorPeriodo> {
  String _preset = 'mes_atual';
  DateTime? _customInicio;
  DateTime? _customFim;

  void _emitir() {
    widget.onChanged(
      calcularLimitesPeriodo(
        preset: _preset,
        customInicio: _customInicio,
        customFim: _customFim,
      ),
    );
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _emitir());
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        DropdownButtonFormField<String>(
          key: ValueKey(_preset),
          initialValue: _preset,
          decoration: InputDecoration(labelText: widget.label, isDense: true),
          items: const [
            DropdownMenuItem(value: 'hoje', child: Text('Hoje')),
            DropdownMenuItem(value: 'ultimos_7', child: Text('Ultimos 7 dias')),
            DropdownMenuItem(
              value: 'ultimos_30',
              child: Text('Ultimos 30 dias'),
            ),
            DropdownMenuItem(value: 'mes_atual', child: Text('Mes atual')),
            DropdownMenuItem(
              value: 'mes_anterior',
              child: Text('Mes anterior'),
            ),
            DropdownMenuItem(value: 'ano_atual', child: Text('Ano atual')),
            DropdownMenuItem(
              value: 'personalizado',
              child: Text('Personalizado'),
            ),
          ],
          onChanged: (v) {
            if (v == null) return;
            setState(() => _preset = v);
            _emitir();
          },
        ),
        if (_preset == 'personalizado') ...[
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () async {
                    final d = await showDatePicker(
                      context: context,
                      initialDate: _customInicio ?? DateTime.now(),
                      firstDate: DateTime(2000),
                      lastDate: DateTime(2100),
                    );
                    if (d != null) {
                      setState(() => _customInicio = d);
                      _emitir();
                    }
                  },
                  icon: const Icon(Icons.calendar_today_outlined, size: 18),
                  label: Text(
                    _customInicio == null
                        ? 'Data inicial'
                        : DateFormat('dd/MM/yyyy').format(_customInicio!),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () async {
                    final d = await showDatePicker(
                      context: context,
                      initialDate: _customFim ?? DateTime.now(),
                      firstDate: DateTime(2000),
                      lastDate: DateTime(2100),
                    );
                    if (d != null) {
                      setState(() => _customFim = d);
                      _emitir();
                    }
                  },
                  icon: const Icon(Icons.event_outlined, size: 18),
                  label: Text(
                    _customFim == null
                        ? 'Data final'
                        : DateFormat('dd/MM/yyyy').format(_customFim!),
                  ),
                ),
              ),
            ],
          ),
        ],
      ],
    );
  }
}
