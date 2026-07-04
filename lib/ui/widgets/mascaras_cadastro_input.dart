import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

String somenteDigitos(String texto) => texto.replaceAll(RegExp(r'\D'), '');

/// Valida CPF brasileiro (11 digitos). Retorna true se [cpf] vazio.
bool cpfValidoOuVazio(String cpf) {
  final d = somenteDigitos(cpf);
  if (d.isEmpty) return true;
  if (d.length != 11) return false;
  if (RegExp(r'^(\d)\1{10}$').hasMatch(d)) return false;

  int calcDigito(String base, int pesoInicial) {
    var soma = 0;
    for (var i = 0; i < base.length; i++) {
      soma += int.parse(base[i]) * (pesoInicial - i);
    }
    final resto = soma % 11;
    return resto < 2 ? 0 : 11 - resto;
  }

  final d1 = calcDigito(d.substring(0, 9), 10);
  final d2 = calcDigito(d.substring(0, 9) + d1.toString(), 11);
  return d.endsWith('$d1$d2');
}

/// Valida CNPJ brasileiro (14 digitos). Retorna true se [cnpj] vazio.
bool cnpjValidoOuVazio(String cnpj) {
  final d = somenteDigitos(cnpj);
  if (d.isEmpty) return true;
  if (d.length != 14) return false;
  if (RegExp(r'^(\d)\1{13}$').hasMatch(d)) return false;

  int calcDigito(List<int> base, List<int> pesos) {
    var soma = 0;
    for (var i = 0; i < base.length; i++) {
      soma += base[i] * pesos[i];
    }
    final resto = soma % 11;
    return resto < 2 ? 0 : 11 - resto;
  }

  final nums = d.split('').map(int.parse).toList();
  final d1 = calcDigito(nums.sublist(0, 12), const [
    5, 4, 3, 2, 9, 8, 7, 6, 5, 4, 3, 2,
  ]);
  final d2 = calcDigito(nums.sublist(0, 13), const [
    6, 5, 4, 3, 2, 9, 8, 7, 6, 5, 4, 3, 2,
  ]);
  return nums[12] == d1 && nums[13] == d2;
}

/// Valida CPF ou CNPJ conforme [tipoPessoa] (`fisica` | `juridica`).
bool documentoCpfCnpjValidoOuVazio(String doc, {required String tipoPessoa}) {
  final d = somenteDigitos(doc);
  if (d.isEmpty) return true;
  if (tipoPessoa == 'juridica') {
    return cnpjValidoOuVazio(doc);
  }
  return cpfValidoOuVazio(doc);
}

class CpfInputFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final digits = somenteDigitos(newValue.text);
    final truncated = digits.length > 11 ? digits.substring(0, 11) : digits;
    final masked = _maskCpf(truncated);
    return TextEditingValue(
      text: masked,
      selection: TextSelection.collapsed(offset: masked.length),
    );
  }

  static String _maskCpf(String value) {
    if (value.length <= 3) return value;
    if (value.length <= 6) {
      return '${value.substring(0, 3)}.${value.substring(3)}';
    }
    if (value.length <= 9) {
      return '${value.substring(0, 3)}.${value.substring(3, 6)}.${value.substring(6)}';
    }
    return '${value.substring(0, 3)}.${value.substring(3, 6)}.${value.substring(6, 9)}-${value.substring(9)}';
  }
}

class CepInputFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final digits = somenteDigitos(newValue.text);
    final truncated = digits.length > 8 ? digits.substring(0, 8) : digits;
    final masked = truncated.length <= 5
        ? truncated
        : '${truncated.substring(0, 5)}-${truncated.substring(5)}';
    return TextEditingValue(
      text: masked,
      selection: TextSelection.collapsed(offset: masked.length),
    );
  }
}

class TelefoneInputFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final digits = somenteDigitos(newValue.text);
    final truncated = digits.length > 13 ? digits.substring(0, 13) : digits;
    final masked = _maskTelefone(truncated);
    return TextEditingValue(
      text: masked,
      selection: TextSelection.collapsed(offset: masked.length),
    );
  }

  static String _maskTelefone(String value) {
    if (value.isEmpty) return '';
    if (value.length > 11) {
      final ddi = value.substring(0, 2);
      final resto = value.substring(2);
      return '+$ddi ${_maskTelefoneLocal(resto)}';
    }
    return _maskTelefoneLocal(value);
  }

  static String _maskTelefoneLocal(String value) {
    if (value.isEmpty) return '';
    if (value.length <= 2) return '($value';
    if (value.length <= 6) {
      return '(${value.substring(0, 2)}) ${value.substring(2)}';
    }
    if (value.length <= 10) {
      return '(${value.substring(0, 2)}) ${value.substring(2, 6)}-${value.substring(6)}';
    }
    return '(${value.substring(0, 2)}) ${value.substring(2, 7)}-${value.substring(7)}';
  }
}

void aplicarMascaraCpf(TextEditingController c, CpfInputFormatter fmt) {
  final d = somenteDigitos(c.text);
  c.value = fmt.formatEditUpdate(
    TextEditingValue.empty,
    TextEditingValue(text: d),
  );
}

void aplicarMascaraCep(TextEditingController c, CepInputFormatter fmt) {
  final d = somenteDigitos(c.text);
  c.value = fmt.formatEditUpdate(
    TextEditingValue.empty,
    TextEditingValue(text: d),
  );
}

void aplicarMascaraTelefone(TextEditingController c, TelefoneInputFormatter fmt) {
  final d = somenteDigitos(c.text);
  c.value = fmt.formatEditUpdate(
    TextEditingValue.empty,
    TextEditingValue(text: d),
  );
}
