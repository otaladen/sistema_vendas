import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../data/vale_credito_service.dart';
import '../../domain/vale_credito.dart';

/// Localiza o vale para gastar: pelo codigo do comprovante ou, quando a venda
/// tem cliente, pela lista do cadastro (para quem perdeu o papel).
Future<ValeCreditoResumo?> selecionarValeCredito(
  BuildContext context, {
  required ValeCreditoService servico,
  required double totalAPagar,
  int clienteId = 0,
  Set<int> jaUsados = const {},
}) {
  return showDialog<ValeCreditoResumo>(
    context: context,
    builder: (_) => _ValeBuscaDialog(
      servico: servico,
      totalAPagar: totalAPagar,
      clienteId: clienteId,
      jaUsados: jaUsados,
    ),
  );
}

class _ValeBuscaDialog extends StatefulWidget {
  const _ValeBuscaDialog({
    required this.servico,
    required this.totalAPagar,
    required this.clienteId,
    required this.jaUsados,
  });

  final ValeCreditoService servico;
  final double totalAPagar;
  final int clienteId;
  final Set<int> jaUsados;

  @override
  State<_ValeBuscaDialog> createState() => _ValeBuscaDialogState();
}

class _ValeBuscaDialogState extends State<_ValeBuscaDialog> {
  final _codigoController = TextEditingController();
  final _moeda = NumberFormat('#,##0.00', 'pt_BR');

  bool _buscando = false;
  String? _erro;
  List<ValeCreditoResumo> _doCliente = const [];
  bool _carregandoCliente = false;

  @override
  void initState() {
    super.initState();
    if (widget.clienteId > 0) _carregarDoCliente();
  }

  @override
  void dispose() {
    _codigoController.dispose();
    super.dispose();
  }

  String _fmt(double v) => 'R\$ ${_moeda.format(v)}';

  Future<void> _carregarDoCliente() async {
    setState(() => _carregandoCliente = true);
    try {
      final itens =
          await widget.servico.listarGastaveisDoCliente(widget.clienteId);
      if (!mounted) return;
      setState(() {
        _doCliente =
            itens.where((v) => !widget.jaUsados.contains(v.id)).toList();
        _carregandoCliente = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _carregandoCliente = false);
    }
  }

  Future<void> _buscarPorCodigo() async {
    final digitado = _codigoController.text.trim();
    if (digitado.isEmpty) {
      setState(() => _erro = 'Digite o codigo do vale.');
      return;
    }
    if (!ValeCreditoCodigo.valido(digitado)) {
      setState(() => _erro = 'Codigo incompleto. Confira o comprovante.');
      return;
    }
    setState(() {
      _buscando = true;
      _erro = null;
    });
    try {
      final vale = await widget.servico.buscarPorCodigo(digitado);
      if (!mounted) return;
      if (vale == null) {
        setState(() {
          _buscando = false;
          _erro = 'Nenhum vale com esse codigo.';
        });
        return;
      }
      setState(() => _buscando = false);
      _escolher(vale);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _buscando = false;
        _erro = '$e';
      });
    }
  }

  void _escolher(ValeCreditoResumo vale) {
    if (widget.jaUsados.contains(vale.id)) {
      setState(() => _erro = 'Este vale ja esta nesta venda.');
      return;
    }
    final avaliacao = vale.avaliar(widget.totalAPagar);
    if (!avaliacao.podeUsar) {
      setState(() => _erro = avaliacao.motivo);
      return;
    }
    Navigator.pop(context, vale);
  }

  @override
  Widget build(BuildContext context) {
    final tema = Theme.of(context);
    return AlertDialog(
      title: const Text('Usar vale de credito'),
      content: SizedBox(
        width: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              controller: _codigoController,
              autofocus: true,
              textCapitalization: TextCapitalization.characters,
              decoration: InputDecoration(
                labelText: 'Codigo do vale',
                hintText: 'VL-A3K9-2PQ7',
                errorText: _erro,
                suffixIcon: IconButton(
                  onPressed: _buscando ? null : _buscarPorCodigo,
                  icon: const Icon(Icons.search),
                  tooltip: 'Buscar',
                ),
              ),
              onSubmitted: (_) => _buscarPorCodigo(),
            ),
            if (_buscando) ...[
              const SizedBox(height: 12),
              const LinearProgressIndicator(),
            ],
            if (widget.clienteId > 0) ...[
              const SizedBox(height: 18),
              Text(
                'Vales deste cliente',
                style: tema.textTheme.titleSmall
                    ?.copyWith(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 6),
              if (_carregandoCliente)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 8),
                  child: LinearProgressIndicator(),
                )
              else if (_doCliente.isEmpty)
                Text(
                  'Nenhum vale em aberto no cadastro.',
                  style: tema.textTheme.bodySmall,
                )
              else
                ConstrainedBox(
                  constraints: const BoxConstraints(maxHeight: 220),
                  child: ListView.builder(
                    shrinkWrap: true,
                    itemCount: _doCliente.length,
                    itemBuilder: (_, i) {
                      final v = _doCliente[i];
                      final validade = v.dataValidade;
                      return ListTile(
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        leading: const Icon(Icons.confirmation_number_outlined),
                        title: Text(v.codigoFormatado),
                        subtitle: Text(
                          validade == null
                              ? 'Saldo ${_fmt(v.saldo)}'
                              : 'Saldo ${_fmt(v.saldo)} · vence '
                                  '${DateFormat('dd/MM/yyyy').format(validade)}',
                        ),
                        trailing: TextButton(
                          onPressed: () => _escolher(v),
                          child: const Text('Usar'),
                        ),
                      );
                    },
                  ),
                ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          onPressed: _buscando ? null : _buscarPorCodigo,
          child: const Text('Usar codigo'),
        ),
      ],
    );
  }
}
