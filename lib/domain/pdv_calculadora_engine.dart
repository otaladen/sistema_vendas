/// Motor da calculadora do PDV (operações encadeadas e percentual).
class PdvCalculadoraEngine {
  String buffer = '0';
  double? accumulator;
  String? pendingOp;
  bool waitingForOperand = false;

  /// Expressão visível, ex.: `15+15+15`.
  String formula = '';

  static double parseBuffer(String buffer) =>
      double.tryParse(buffer.replaceAll(',', '.')) ?? 0;

  static String formatNum(double v) {
    if (v.isNaN || v.isInfinite) return 'Erro';
    final rounded = (v * 1e10).roundToDouble() / 1e10;
    if ((rounded - rounded.roundToDouble()).abs() < 1e-9) {
      return rounded.round().toString();
    }
    var s = rounded.toStringAsFixed(6);
    while (s.contains('.') && (s.endsWith('0') || s.endsWith('.'))) {
      s = s.substring(0, s.length - 1);
    }
    return s;
  }

  static String opDisplay(String op) {
    switch (op) {
      case '+':
        return '+';
      case '-':
        return '-';
      case '*':
        return '×';
      case '/':
        return '÷';
      default:
        return op;
    }
  }

  static double compute(double a, double b, String op) {
    switch (op) {
      case '+':
        return a + b;
      case '-':
        return a - b;
      case '*':
        return a * b;
      case '/':
        return b == 0 ? double.nan : a / b;
      default:
        return b;
    }
  }

  /// Texto completo da fórmula (linha superior ou junto ao visor).
  String get expressaoVisivel {
    if (formula.isEmpty) return buffer;
    if (waitingForOperand) return formula;
    return '$formula$buffer';
  }

  void inputDigit(String d) {
    if (waitingForOperand || buffer == '0' || buffer == 'Erro') {
      buffer = d;
      waitingForOperand = false;
    } else {
      buffer += d;
    }
  }

  void inputDecimal() {
    if (waitingForOperand || buffer == 'Erro') {
      buffer = '0,';
      waitingForOperand = false;
      return;
    }
    if (!buffer.contains(',')) buffer += ',';
  }

  void inputOp(String op) {
    final v = parseBuffer(buffer);
    if (accumulator != null &&
        pendingOp != null &&
        !waitingForOperand &&
        buffer != 'Erro') {
      final operandText = buffer;
      accumulator = compute(accumulator!, v, pendingOp!);
      buffer = formatNum(accumulator!);
      formula += operandText + opDisplay(op);
    } else {
      accumulator = v;
      if (formula.isEmpty) {
        formula = buffer + opDisplay(op);
      } else if (waitingForOperand) {
        if (RegExp(r'[+\-×÷]$').hasMatch(formula)) {
          formula = formula.substring(0, formula.length - 1) + opDisplay(op);
        } else {
          formula += opDisplay(op);
        }
      } else {
        formula = buffer + opDisplay(op);
      }
    }
    pendingOp = op;
    waitingForOperand = true;
  }

  void equals() {
    if (pendingOp == null || accumulator == null) return;
    final v = parseBuffer(buffer);
    final r = compute(accumulator!, v, pendingOp!);
    if (!waitingForOperand) {
      formula += buffer;
    }
    formula += '=';
    buffer = formatNum(r);
    accumulator = null;
    pendingOp = null;
    waitingForOperand = true;
  }

  void clear() {
    buffer = '0';
    accumulator = null;
    pendingOp = null;
    waitingForOperand = false;
    formula = '';
  }

  void backspace() {
    if (waitingForOperand) return;
    if (buffer.length <= 1 || buffer == 'Erro') {
      buffer = '0';
      return;
    }
    buffer = buffer.substring(0, buffer.length - 1);
    if (buffer.isEmpty) buffer = '0';
  }

  /// Percentual: com operação pendente, aplica sobre o acumulador
  /// (ex.: `10 − 2%` → `9,8`).
  void percentual() {
    final raw = parseBuffer(buffer);
    if (accumulator != null &&
        pendingOp != null &&
        !waitingForOperand &&
        buffer != 'Erro') {
      final parcela = accumulator! * raw / 100;
      final r = compute(accumulator!, parcela, pendingOp!);
      formula += '$buffer%';
      buffer = formatNum(r);
      accumulator = null;
      pendingOp = null;
      waitingForOperand = true;
      return;
    }
    final v = raw / 100;
    buffer = formatNum(v);
    waitingForOperand = false;
  }
}
