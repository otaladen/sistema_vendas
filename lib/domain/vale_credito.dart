import 'dart:math';

/// Situacao do vale no momento da consulta.
enum ValeCreditoSituacao { aberto, parcial, usado, cancelado, vencido }

extension ValeCreditoSituacaoRotulo on ValeCreditoSituacao {
  String get rotulo {
    switch (this) {
      case ValeCreditoSituacao.aberto:
        return 'Aberto';
      case ValeCreditoSituacao.parcial:
        return 'Usado em parte';
      case ValeCreditoSituacao.usado:
        return 'Usado';
      case ValeCreditoSituacao.cancelado:
        return 'Cancelado';
      case ValeCreditoSituacao.vencido:
        return 'Vencido';
    }
  }

  bool get gastavel =>
      this == ValeCreditoSituacao.aberto || this == ValeCreditoSituacao.parcial;
}

/// Codigo do vale: e a chave que o balconista digita no caixa.
///
/// Vale hibrido — o codigo impresso vale por si (portador), e quando a venda
/// tem cliente o vale tambem fica amarrado ao cadastro, para ser recuperado
/// sem o comprovante em maos.
abstract final class ValeCreditoCodigo {
  /// Crockford base32: sem I, L, O e U. Assim "0/O" e "1/I/L" nao se perdem
  /// na leitura de um cupom termico ou numa anotacao a mao.
  static const alfabeto = '0123456789ABCDEFGHJKMNPQRSTVWXYZ';

  static const prefixo = 'VL';

  static const tamanho = 8;

  static String gerar({Random? random}) {
    final rnd = random ?? Random.secure();
    final buffer = StringBuffer();
    for (var i = 0; i < tamanho; i++) {
      buffer.write(alfabeto[rnd.nextInt(alfabeto.length)]);
    }
    return buffer.toString();
  }

  /// Aceita o que o balconista digitar: minusculas, espacos, hifens, com ou
  /// sem prefixo, e as trocas classicas de O por 0 e de I/L por 1.
  static String normalizar(String bruto) {
    var t = bruto.toUpperCase().replaceAll(RegExp('[^A-Z0-9]'), '');
    if (t.startsWith(prefixo)) t = t.substring(prefixo.length);
    final buffer = StringBuffer();
    for (final c in t.split('')) {
      switch (c) {
        case 'O':
          buffer.write('0');
        case 'I':
        case 'L':
          buffer.write('1');
        case 'U':
          buffer.write('V');
        default:
          buffer.write(c);
      }
    }
    return buffer.toString();
  }

  static bool valido(String codigo) {
    final n = normalizar(codigo);
    if (n.length != tamanho) return false;
    return n.split('').every(alfabeto.contains);
  }

  /// Como o codigo aparece no comprovante e na tela: `VL-A3K9-2PQ7`.
  static String formatar(String codigo) {
    final n = normalizar(codigo);
    if (n.length != tamanho) return n;
    return '$prefixo-${n.substring(0, 4)}-${n.substring(4)}';
  }
}

/// Centavos evitam o erro de ponto flutuante ao somar resgates parciais.
abstract final class ValeCreditoValor {
  static const eps = 0.005;

  static int emCentavos(double reais) => (reais * 100).round();

  static double emReais(int centavos) => centavos / 100;

  static bool zerado(double v) => v.abs() < eps;

  static bool positivo(double v) => v >= eps;
}

/// Resposta a pergunta "posso usar este vale nesta venda, e por quanto?".
class ValeCreditoAvaliacao {
  const ValeCreditoAvaliacao._({
    required this.podeUsar,
    required this.valorAplicavel,
    required this.motivo,
  });

  factory ValeCreditoAvaliacao.negada(String motivo) =>
      ValeCreditoAvaliacao._(
        podeUsar: false,
        valorAplicavel: 0,
        motivo: motivo,
      );

  factory ValeCreditoAvaliacao.permitida(double valorAplicavel) =>
      ValeCreditoAvaliacao._(
        podeUsar: true,
        valorAplicavel: valorAplicavel,
        motivo: '',
      );

  final bool podeUsar;

  /// Quanto do saldo cabe nesta venda; o resto continua no vale.
  final double valorAplicavel;

  /// Por que nao pode usar. Vazio quando [podeUsar].
  final String motivo;
}

abstract final class ValeCreditoRegras {
  static double saldo({
    required double valorOriginal,
    required double valorUtilizado,
  }) {
    final c = ValeCreditoValor.emCentavos(valorOriginal) -
        ValeCreditoValor.emCentavos(valorUtilizado);
    return ValeCreditoValor.emReais(c < 0 ? 0 : c);
  }

  /// Vence no fim do dia da validade, nao na virada da meia-noite: o cliente
  /// que chega no ultimo dia a tarde ainda gasta.
  static bool vencido({DateTime? validade, DateTime? agora}) {
    if (validade == null) return false;
    final limite = DateTime(
      validade.year,
      validade.month,
      validade.day,
      23,
      59,
      59,
    );
    return (agora ?? DateTime.now()).isAfter(limite);
  }

  static ValeCreditoSituacao situacao({
    required double valorOriginal,
    required double valorUtilizado,
    required bool cancelado,
    DateTime? validade,
    DateTime? agora,
  }) {
    if (cancelado) return ValeCreditoSituacao.cancelado;
    final s = saldo(
      valorOriginal: valorOriginal,
      valorUtilizado: valorUtilizado,
    );
    if (!ValeCreditoValor.positivo(s)) return ValeCreditoSituacao.usado;
    if (vencido(validade: validade, agora: agora)) {
      return ValeCreditoSituacao.vencido;
    }
    return ValeCreditoValor.positivo(valorUtilizado)
        ? ValeCreditoSituacao.parcial
        : ValeCreditoSituacao.aberto;
  }

  static ValeCreditoAvaliacao avaliarResgate({
    required double valorOriginal,
    required double valorUtilizado,
    required bool cancelado,
    required double totalAPagar,
    DateTime? validade,
    DateTime? agora,
  }) {
    final sit = situacao(
      valorOriginal: valorOriginal,
      valorUtilizado: valorUtilizado,
      cancelado: cancelado,
      validade: validade,
      agora: agora,
    );
    switch (sit) {
      case ValeCreditoSituacao.cancelado:
        return ValeCreditoAvaliacao.negada('Vale cancelado.');
      case ValeCreditoSituacao.usado:
        return ValeCreditoAvaliacao.negada('Vale ja foi usado por completo.');
      case ValeCreditoSituacao.vencido:
        return ValeCreditoAvaliacao.negada('Vale vencido.');
      case ValeCreditoSituacao.aberto:
      case ValeCreditoSituacao.parcial:
        break;
    }
    if (!ValeCreditoValor.positivo(totalAPagar)) {
      return ValeCreditoAvaliacao.negada('Nao ha valor a pagar para abater.');
    }
    final s = saldo(
      valorOriginal: valorOriginal,
      valorUtilizado: valorUtilizado,
    );
    return ValeCreditoAvaliacao.permitida(s <= totalAPagar ? s : totalAPagar);
  }
}
