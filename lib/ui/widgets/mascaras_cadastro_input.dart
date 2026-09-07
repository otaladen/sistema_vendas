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

class CnpjInputFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final digits = somenteDigitos(newValue.text);
    final truncated = digits.length > 14 ? digits.substring(0, 14) : digits;
    final masked = _maskCnpj(truncated);
    return TextEditingValue(
      text: masked,
      selection: TextSelection.collapsed(offset: masked.length),
    );
  }

  static String _maskCnpj(String value) {
    if (value.length <= 2) return value;
    if (value.length <= 5) {
      return '${value.substring(0, 2)}.${value.substring(2)}';
    }
    if (value.length <= 8) {
      return '${value.substring(0, 2)}.${value.substring(2, 5)}.${value.substring(5)}';
    }
    if (value.length <= 12) {
      return '${value.substring(0, 2)}.${value.substring(2, 5)}.${value.substring(5, 8)}/${value.substring(8)}';
    }
    return '${value.substring(0, 2)}.${value.substring(2, 5)}.${value.substring(5, 8)}/${value.substring(8, 12)}-${value.substring(12)}';
  }
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

/// Mascara `dd/MM/yyyy` (8 digitos).
class DataDdMmYyyyInputFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final digits = somenteDigitos(newValue.text);
    final truncated = digits.length > 8 ? digits.substring(0, 8) : digits;
    final masked = _mask(truncated);
    return TextEditingValue(
      text: masked,
      selection: TextSelection.collapsed(offset: masked.length),
    );
  }

  static String _mask(String value) {
    if (value.length <= 2) return value;
    if (value.length <= 4) {
      return '${value.substring(0, 2)}/${value.substring(2)}';
    }
    return '${value.substring(0, 2)}/${value.substring(2, 4)}/${value.substring(4)}';
  }
}

/// Interpreta `dd/MM/yyyy`. Retorna null se incompleto ou invalido.
DateTime? parseDataDdMmYyyy(String texto, {DateTime? naoDepoisDe}) {
  final d = somenteDigitos(texto);
  if (d.length != 8) return null;
  final dia = int.tryParse(d.substring(0, 2));
  final mes = int.tryParse(d.substring(2, 4));
  final ano = int.tryParse(d.substring(4, 8));
  if (dia == null || mes == null || ano == null) return null;
  if (ano < 1900 || mes < 1 || mes > 12 || dia < 1) return null;
  final dt = DateTime(ano, mes, dia);
  if (dt.year != ano || dt.month != mes || dt.day != dia) return null;
  final limite = naoDepoisDe ?? DateTime.now();
  final limiteDia = DateTime(limite.year, limite.month, limite.day);
  if (dt.isAfter(limiteDia)) return null;
  return dt;
}

/// Mascara NCM fiscal: 8 digitos no formato `9999.99.99`.
class NcmInputFormatter extends TextInputFormatter {
  static const int maxDigitos = 8;

  /// Formata [digitos] (com ou sem mascara) para exibicao.
  static String formatar(String digitos) {
    final d = somenteDigitos(digitos);
    if (d.isEmpty) return '';
    if (d.length <= 4) return d;
    if (d.length <= 6) {
      return '${d.substring(0, 4)}.${d.substring(4)}';
    }
    final t = d.length > maxDigitos ? d.substring(0, maxDigitos) : d;
    return '${t.substring(0, 4)}.${t.substring(4, 6)}.${t.substring(6)}';
  }

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final digits = somenteDigitos(newValue.text);
    final truncated =
        digits.length > maxDigitos ? digits.substring(0, maxDigitos) : digits;
    final masked = formatar(truncated);
    return TextEditingValue(
      text: masked,
      selection: TextSelection.collapsed(offset: masked.length),
    );
  }
}

/// Mascara CEST: 7 digitos no formato `99.999.99`.
class CestInputFormatter extends TextInputFormatter {
  static const int maxDigitos = 7;

  static String formatar(String digitos) {
    final d = somenteDigitos(digitos);
    if (d.isEmpty) return '';
    if (d.length <= 2) return d;
    if (d.length <= 5) {
      return '${d.substring(0, 2)}.${d.substring(2)}';
    }
    final t = d.length > maxDigitos ? d.substring(0, maxDigitos) : d;
    return '${t.substring(0, 2)}.${t.substring(2, 5)}.${t.substring(5)}';
  }

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final digits = somenteDigitos(newValue.text);
    final truncated =
        digits.length > maxDigitos ? digits.substring(0, maxDigitos) : digits;
    final masked = formatar(truncated);
    return TextEditingValue(
      text: masked,
      selection: TextSelection.collapsed(offset: masked.length),
    );
  }
}

/// GTIN/EAN: somente digitos (ate 14, tamanho usual de codigo de barras).
class GtinInputFormatter extends TextInputFormatter {
  static const int maxDigitos = 14;

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final digits = somenteDigitos(newValue.text);
    final truncated =
        digits.length > maxDigitos ? digits.substring(0, maxDigitos) : digits;
    return TextEditingValue(
      text: truncated,
      selection: TextSelection.collapsed(offset: truncated.length),
    );
  }
}

/// CFOP de venda: somente digitos (ate 4).
class CfopInputFormatter extends TextInputFormatter {
  static const int maxDigitos = 4;

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final digits = somenteDigitos(newValue.text);
    final truncated =
        digits.length > maxDigitos ? digits.substring(0, maxDigitos) : digits;
    return TextEditingValue(
      text: truncated,
      selection: TextSelection.collapsed(offset: truncated.length),
    );
  }
}

void aplicarMascaraNcm(TextEditingController c, NcmInputFormatter fmt) {
  final d = somenteDigitos(c.text);
  c.value = fmt.formatEditUpdate(
    TextEditingValue.empty,
    TextEditingValue(text: d),
  );
}

void aplicarMascaraCest(TextEditingController c, CestInputFormatter fmt) {
  final d = somenteDigitos(c.text);
  c.value = fmt.formatEditUpdate(
    TextEditingValue.empty,
    TextEditingValue(text: d),
  );
}

void aplicarMascaraCfop(TextEditingController c, CfopInputFormatter fmt) {
  final d = somenteDigitos(c.text);
  c.value = fmt.formatEditUpdate(
    TextEditingValue.empty,
    TextEditingValue(text: d),
  );
}

void aplicarMascaraGtin(TextEditingController c, GtinInputFormatter fmt) {
  final d = somenteDigitos(c.text);
  c.value = fmt.formatEditUpdate(
    TextEditingValue.empty,
    TextEditingValue(text: d),
  );
}

