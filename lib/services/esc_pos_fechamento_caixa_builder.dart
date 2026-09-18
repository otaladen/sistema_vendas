import 'dart:typed_data';

import 'package:intl/intl.dart';

import '../data/app_config_repository.dart';
import 'esc_pos_commands.dart';
import 'esc_pos_text_layout.dart';

/// Dados para o relatorio termico de fechamento de caixa (X/Z).
class FechamentoCaixaEscPosDados {
  const FechamentoCaixaEscPosDados({
    required this.config,
    required this.operador,
    required this.aberturaEm,
    required this.fechamentoEm,
    required this.fundoTroco,
    required this.suprimentos,
    required this.sangrias,
    required this.esperadoDinheiro,
    required this.esperadoPix,
    required this.esperadoDebito,
    required this.esperadoCredito,
    required this.declaradoDinheiro,
    required this.declaradoPix,
    required this.declaradoDebito,
    required this.declaradoCredito,
    this.observacao = '',
  });

  final EmpresaConfig config;
  final String operador;
  final DateTime? aberturaEm;
  final DateTime fechamentoEm;
  final double fundoTroco;
  final double suprimentos;
  final double sangrias;
  final double esperadoDinheiro;
  final double esperadoPix;
  final double esperadoDebito;
  final double esperadoCredito;
  final double declaradoDinheiro;
  final double declaradoPix;
  final double declaradoDebito;
  final double declaradoCredito;
  final String observacao;

  double get diferencaTotal =>
      (declaradoDinheiro - esperadoDinheiro) +
      (declaradoPix - esperadoPix) +
      (declaradoDebito - esperadoDebito) +
      (declaradoCredito - esperadoCredito);
}

abstract final class EscPosFechamentoCaixaBuilder {
  EscPosFechamentoCaixaBuilder._();

  static final _moeda = NumberFormat('#,##0.00', 'pt_BR');
  static final _dt = DateFormat('dd/MM/yyyy HH:mm:ss');

  static String moeda(double v) => 'R\$ ${_moeda.format(v)}';

  static Uint8List montar(
    FechamentoCaixaEscPosDados dados, {
    EscPosLarguraBobina largura = EscPosLarguraBobina.mm80,
    bool cortar = true,
  }) {
    final cols = largura.colunas;
    final out = BytesBuilder(copy: false);
    final cfg = dados.config;

    out.add(EscPosCommands.init);
    out.add(EscPosCommands.codePage850);

    out.add(EscPosCommands.alignCenter);
    out.add(EscPosCommands.boldOn);
    for (final l in EscPosTextLayout.wrap(cfg.nomeLoja.trim(), cols)) {
      out.add(EscPosCommands.line(l));
    }
    out.add(EscPosCommands.boldOff);

    out.add(EscPosCommands.doubleWidthOn);
    out.add(EscPosCommands.boldOn);
    const titulo = 'FECHAMENTO DE CAIXA (X/Z)';
    for (final l in EscPosTextLayout.wrapTituloExpandido(titulo, cols)) {
      out.add(EscPosCommands.line(l));
    }
    out.add(EscPosCommands.boldOff);
    out.add(EscPosCommands.normalSize);

    out.add(EscPosCommands.separator(cols));
    out.add(EscPosCommands.alignLeft);

    final op = dados.operador.trim().isEmpty ? '-' : dados.operador.trim();
    for (final l in EscPosTextLayout.wrap('Operador: $op', cols)) {
      out.add(EscPosCommands.line(l));
    }
    final ab = dados.aberturaEm == null
        ? '-'
        : _dt.format(dados.aberturaEm!.toLocal());
    for (final l in EscPosTextLayout.wrap('Abertura: $ab', cols)) {
      out.add(EscPosCommands.line(l));
    }
    for (final l in EscPosTextLayout.wrap(
      'Fechamento: ${_dt.format(dados.fechamentoEm.toLocal())}',
      cols,
    )) {
      out.add(EscPosCommands.line(l));
    }

    out.add(EscPosCommands.separator(cols));
    out.add(EscPosCommands.line(
      EscPosTextLayout.rotuloValor('Fundo inicial:', moeda(dados.fundoTroco), cols),
    ));
    out.add(EscPosCommands.line(
      EscPosTextLayout.rotuloValor('Suprimentos:', moeda(dados.suprimentos), cols),
    ));
    out.add(EscPosCommands.line(
      EscPosTextLayout.rotuloValor('Sangrias:', moeda(dados.sangrias), cols),
    ));

    out.add(EscPosCommands.separator(cols));
    out.add(EscPosCommands.boldOn);
    for (final l in EscPosTextLayout.wrap(
      'Conferencia por forma de pagamento',
      cols,
    )) {
      out.add(EscPosCommands.line(l));
    }
    out.add(EscPosCommands.boldOff);

    _formaPagamento(
      out,
      cols: cols,
      rotulo: 'Dinheiro',
      esperado: dados.esperadoDinheiro,
      declarado: dados.declaradoDinheiro,
    );
    _formaPagamento(
      out,
      cols: cols,
      rotulo: 'PIX',
      esperado: dados.esperadoPix,
      declarado: dados.declaradoPix,
    );
    _formaPagamento(
      out,
      cols: cols,
      rotulo: 'Cartao debito',
      esperado: dados.esperadoDebito,
      declarado: dados.declaradoDebito,
    );
    _formaPagamento(
      out,
      cols: cols,
      rotulo: 'Cartao credito',
      esperado: dados.esperadoCredito,
      declarado: dados.declaradoCredito,
    );

    out.add(EscPosCommands.separator(cols));
    _linhaDiferencaTotal(out, cols: cols, dif: dados.diferencaTotal);

    final obs = dados.observacao.trim();
    if (obs.isNotEmpty) {
      out.add(EscPosCommands.separator(cols));
      out.add(EscPosCommands.boldOn);
      out.add(EscPosCommands.line('Observacao:'));
      out.add(EscPosCommands.boldOff);
      for (final l in EscPosTextLayout.wrap(obs, cols)) {
        out.add(EscPosCommands.line(l));
      }
    }

    out.add(EscPosCommands.feed(3));
    if (cortar) out.add(EscPosCommands.cutPartial);
    return out.toBytes();
  }

  static void _formaPagamento(
    BytesBuilder out, {
    required int cols,
    required String rotulo,
    required double esperado,
    required double declarado,
  }) {
    out.add(EscPosCommands.line(''));
    out.add(EscPosCommands.boldOn);
    out.add(EscPosCommands.line(EscPosTextLayout.trunc(rotulo, cols)));
    out.add(EscPosCommands.boldOff);
    final dif = declarado - esperado;
    out.add(EscPosCommands.line(
      EscPosTextLayout.rotuloValor('  Esp:', moeda(esperado), cols),
    ));
    out.add(EscPosCommands.line(
      EscPosTextLayout.rotuloValor('  Dec:', moeda(declarado), cols),
    ));
    out.add(EscPosCommands.line(
      EscPosTextLayout.rotuloValor('  Dif:', moeda(dif), cols),
    ));
  }

  static void _linhaDiferencaTotal(
    BytesBuilder out, {
    required int cols,
    required double dif,
  }) {
    final valor = moeda(dif);
    final sufixo = dif.abs() < 0.01
        ? '(sem divergencia)'
        : dif > 0
            ? '(sobra)'
            : '(falta)';
    out.add(EscPosCommands.boldOn);
    out.add(EscPosCommands.line(
      EscPosTextLayout.rotuloValor('Diferenca total:', valor, cols),
    ));
    out.add(EscPosCommands.boldOff);
    for (final l in EscPosTextLayout.wrap(sufixo, cols)) {
      out.add(EscPosCommands.line(l));
    }
  }
}
