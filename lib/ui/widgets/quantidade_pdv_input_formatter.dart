import 'package:flutter/services.dart';

import '../../domain/quantidade_venda_util.dart';

/// Aceita inteiros ou ate 3 casas decimais (5,75 / 5.750) no PDV.
class QuantidadePdvInputFormatter extends TextInputFormatter {
  const QuantidadePdvInputFormatter({required this.fracionada});

  final bool fracionada;

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    if (QuantidadeVendaUtil.textoQuantidadeValido(
      newValue.text,
      fracionada: fracionada,
    )) {
      return newValue;
    }
    return oldValue;
  }
}
