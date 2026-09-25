import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../domain/entregas/buscar_na_loja.dart';

/// Pergunta quanto buscar nesta loja. Retorna o valor persistido
/// (milésimos quando a linha e fracionada) ou `null` se cancelar.
Future<int?> mostrarBuscarNaLojaQuantidadeDialog(
  BuildContext context, {
  required String nomeProduto,
  required EntradaQuantidadeBuscarNaLoja entrada,
}) {
  return showDialog<int>(
    context: context,
    builder: (_) => BuscarNaLojaQuantidadeDialog(
      nomeProduto: nomeProduto,
      entrada: entrada,
    ),
  );
}

class BuscarNaLojaQuantidadeDialog extends StatefulWidget {
  const BuscarNaLojaQuantidadeDialog({
    super.key,
    required this.nomeProduto,
    required this.entrada,
  });

  final String nomeProduto;
  final EntradaQuantidadeBuscarNaLoja entrada;

  @override
  State<BuscarNaLojaQuantidadeDialog> createState() =>
      _BuscarNaLojaQuantidadeDialogState();
}

class _BuscarNaLojaQuantidadeDialogState
    extends State<BuscarNaLojaQuantidadeDialog> {
  late final TextEditingController _ctrl;

  EntradaQuantidadeBuscarNaLoja get _entrada => widget.entrada;

  @override
  void initState() {
    super.initState();
    _ctrl = TextEditingController(text: _entrada.textoInicial);
    _ctrl.selection = TextSelection(
      baseOffset: 0,
      extentOffset: _ctrl.text.length,
    );
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  void _buscarTodos() {
    setState(() {
      _ctrl.text = _entrada.textoTotal;
      _ctrl.selection = TextSelection.collapsed(offset: _ctrl.text.length);
    });
  }

  void _confirmar() {
    final arm = _entrada.armazenadoDe(_ctrl.text);
    if (arm == null) return;
    Navigator.pop(context, arm);
  }

  @override
  Widget build(BuildContext context) {
    final erro = _ctrl.text.isEmpty ? null : _entrada.validar(_ctrl.text);
    final valido = _entrada.armazenadoDe(_ctrl.text) != null;
    return AlertDialog(
      title: Text('Buscar na Loja - ${widget.nomeProduto.trim()}'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'A outra loja não tem a quantidade toda. '
            'De ${_entrada.textoTotalComUnidade}, quanto buscar nesta loja?',
          ),
          const SizedBox(height: 16),
          TextField(
            key: const ValueKey('buscar_na_loja_quantidade'),
            controller: _ctrl,
            autofocus: true,
            keyboardType: TextInputType.numberWithOptions(
              decimal: _entrada.aceitaDecimal,
            ),
            inputFormatters: [
              TextInputFormatter.withFunction(
                (antigo, novo) =>
                    _entrada.textoDigitacaoValido(novo.text) ? novo : antigo,
              ),
            ],
            decoration: InputDecoration(
              labelText: 'Quantidade',
              suffixText: _entrada.unidade.isEmpty ? null : _entrada.unidade,
              helperText: 'Máximo ${_entrada.textoTotalComUnidade}',
              errorText: erro,
              border: const OutlineInputBorder(),
            ),
            onChanged: (_) => setState(() {}),
            onSubmitted: (_) => _confirmar(),
          ),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: _buscarTodos,
            icon: const Icon(Icons.select_all),
            label: Text('Buscar Todos (${_entrada.textoTotalComUnidade})'),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          onPressed: valido ? _confirmar : null,
          child: const Text('Avisar pátio'),
        ),
      ],
    );
  }
}
