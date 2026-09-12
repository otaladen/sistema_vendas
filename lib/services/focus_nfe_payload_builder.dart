import '../domain/pagamento_orcamento.dart';
import '../model/venda.dart';

/// Montagem e reconciliacao do grupo de pagamentos (vPag) no JSON Focus NFe.
class FocusNfePayloadBuilder {
  FocusNfePayloadBuilder._();

  static String formatarDecimal(num valor) => valor.toStringAsFixed(2);

  static int _centavos(double v) => (v * 100).round();

  static double _deCentavos(int c) => c / 100.0;

  static String codigoFormaPagamentoFocus(String meio) {
    switch (meio.trim().toLowerCase()) {
      case 'dinheiro':
        return '01';
      case 'cheque':
        return '02';
      case 'cartao_credito':
        return '03';
      case 'cartao_debito':
        return '04';
      case 'fiado':
      case 'credito_loja':
      case 'vale':
        return '05';
      case 'pix':
        return '17';
      case 'vale_alimentacao':
        return '10';
      case 'vale_refeicao':
        return '11';
      case 'boleto':
        return '15';
      default:
        return '99';
    }
  }

  /// Campos `formas_pagamento` e `valor_troco` (quando aplicavel).
  static Map<String, dynamic> camposPagamento(Venda venda, double valorTotalNota) {
    final pag = pagamentosDeVenda(venda, valorTotalNota);
    final out = <String, dynamic>{
      'formas_pagamento': pag.formas,
    };
    if (pag.troco > 0.009) {
      out['valor_troco'] = formatarDecimal(pag.troco);
    }
    return out;
  }

  static ({List<Map<String, dynamic>> formas, double troco}) pagamentosDeVenda(
    Venda venda,
    double valorTotalNota,
  ) {
    final meios = <String>[];
    final valores = <double>[];

    if (venda.formaPagamento == 'misto' &&
        venda.pagamentosJson.trim().isNotEmpty) {
      for (final l in PagamentoOrcamentoCodec.decode(venda.pagamentosJson)) {
        meios.add(l.meio);
        valores.add(l.valor);
      }
    } else {
      meios.add(venda.formaPagamento);
      valores.add(_valorPagamentoUnico(venda, valorTotalNota));
    }

    if (meios.isEmpty) {
      meios.add('dinheiro');
      valores.add(valorTotalNota);
    }

    var soma = _somaValores(valores);
    var troco = soma > valorTotalNota + 0.009 ? soma - valorTotalNota : 0.0;

    if (venda.valorTrocoCaixa > 0.009) {
      troco = venda.valorTrocoCaixa;
      final recebidoEsperado = valorTotalNota + troco;
      if (soma + 0.009 < recebidoEsperado && valores.length == 1) {
        valores[0] = recebidoEsperado;
        soma = recebidoEsperado;
      }
    }

    if (troco <= 0.009) {
      final diff = valorTotalNota - soma;
      if (diff > 0.009) {
        valores[valores.length - 1] += diff;
        soma = valorTotalNota;
      }
    }

    final formas = <Map<String, dynamic>>[];
    for (var i = 0; i < meios.length; i++) {
      formas.add({
        'forma_pagamento': codigoFormaPagamentoFocus(meios[i]),
        'valor_pagamento': formatarDecimal(valores[i]),
      });
    }

    if (troco > 0.009) {
      garantirPagamentoMinimoNota(formas, valorTotalNota);
    } else {
      ajustarCentavosFormasPagamento(formas, valorTotalNota);
    }

    final somaFinal = somaFormasPagamento(formas);
    if (somaFinal > valorTotalNota + 0.009) {
      troco = somaFinal - valorTotalNota;
    }

    return (formas: formas, troco: troco);
  }

  static double _valorPagamentoUnico(Venda venda, double valorTotalNota) {
    if (venda.formaPagamento.trim().toLowerCase() != 'dinheiro') {
      return valorTotalNota;
    }
    if (venda.valorRecebidoCaixa > valorTotalNota + 0.009) {
      return venda.valorRecebidoCaixa;
    }
    if (venda.valorTrocoCaixa > 0.009) {
      return valorTotalNota + venda.valorTrocoCaixa;
    }
    return valorTotalNota;
  }

  /// Antes do POST Focus: corrige vPag < vNF (rejeicao SEFAZ).
  static void validarReconciliarPagamentosNoPayload(
    Map<String, dynamic> payload,
  ) {
    if (!payload.containsKey('formas_pagamento')) return;
    final total = double.tryParse(payload['valor_total']?.toString() ?? '');
    if (total == null) return;

    final formasRaw = payload['formas_pagamento'];
    if (formasRaw is! List || formasRaw.isEmpty) return;

    final formas = formasRaw
        .map((e) => Map<String, dynamic>.from(e as Map))
        .toList(growable: true);

    final troco =
        double.tryParse(payload['valor_troco']?.toString() ?? '') ?? 0;

    if (troco > 0.009) {
      garantirPagamentoMinimoNota(formas, total);
    } else {
      ajustarCentavosFormasPagamento(formas, total);
      if (somaFormasPagamento(formas) <= total + 0.009) {
        payload.remove('valor_troco');
      }
    }

    payload['formas_pagamento'] = formas;
    assertPagamentosConsistentes(payload);
  }

  /// Verifica consistencia apos reconciliacao (debug e testes).
  static void assertPagamentosConsistentes(Map<String, dynamic> payload) {
    final total = double.tryParse(payload['valor_total']?.toString() ?? '');
    if (total == null) return;
    final formasRaw = payload['formas_pagamento'];
    if (formasRaw is! List || formasRaw.isEmpty) return;

    final soma = formasRaw.fold<double>(
      0,
      (s, f) =>
          s +
          (double.tryParse(
                (f as Map)['valor_pagamento']?.toString() ?? '',
              ) ??
              0),
    );
    final troco =
        double.tryParse(payload['valor_troco']?.toString() ?? '') ?? 0;

    assert(
      soma + 0.009 >= total,
      'Focus NFe: soma dos pagamentos ($soma) menor que valor_total ($total)',
    );
    if (troco <= 0.009) {
      assert(
        (_centavos(soma) - _centavos(total)).abs() <= 0,
        'Focus NFe: soma dos pagamentos ($soma) difere de valor_total ($total)',
      );
    }
  }

  static double somaFormasPagamento(List<Map<String, dynamic>> formas) {
    var s = 0.0;
    for (final f in formas) {
      s += double.tryParse(f['valor_pagamento']?.toString() ?? '') ?? 0;
    }
    return s;
  }

  static void ajustarCentavosFormasPagamento(
    List<Map<String, dynamic>> formas,
    double valorTotalNota,
  ) {
    final totalCents = _centavos(valorTotalNota);
    var sumCents = 0;
    for (final f in formas) {
      sumCents +=
          _centavos(double.tryParse(f['valor_pagamento']?.toString() ?? '') ?? 0);
    }
    if (sumCents == totalCents) return;

    final last = formas.last;
    final lastCents = _centavos(
      double.tryParse(last['valor_pagamento']?.toString() ?? '') ?? 0,
    );
    final adjusted = lastCents + (totalCents - sumCents);
    last['valor_pagamento'] = formatarDecimal(_deCentavos(adjusted));
  }

  static void garantirPagamentoMinimoNota(
    List<Map<String, dynamic>> formas,
    double valorTotalNota,
  ) {
    final totalCents = _centavos(valorTotalNota);
    var sumCents = 0;
    for (final f in formas) {
      sumCents +=
          _centavos(double.tryParse(f['valor_pagamento']?.toString() ?? '') ?? 0);
    }
    if (sumCents >= totalCents) return;

    final last = formas.last;
    final lastCents = _centavos(
      double.tryParse(last['valor_pagamento']?.toString() ?? '') ?? 0,
    );
    last['valor_pagamento'] =
        formatarDecimal(_deCentavos(lastCents + (totalCents - sumCents)));
  }

  static double _somaValores(List<double> valores) {
    var s = 0.0;
    for (final v in valores) {
      s += v;
    }
    return s;
  }
}
