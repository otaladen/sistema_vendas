import 'package:flutter/material.dart';

import 'pdv_mobile_ui.dart';

/// Estrutura de colunas compartilhada entre cabecalho e linha do carrinho PDV.
abstract final class PdvCarrinhoLinhaColunas {
  PdvCarrinhoLinhaColunas._();

  static const double paddingHorizontal = 8;
  static const double paddingSubtotalDireita = 4;
  static const double larguraEntrega = 56;
  static const double larguraCodigo = 60;
  static const double larguraUnidadeMedida = 48;
  static const double larguraUnitario = 68;
  static const double larguraSubtotal = 76;
  static const double larguraBotaoTabela = 28;
  static const double larguraCampoQuantidade = 36;
  static const double larguraProdutoMinimaConfortavel = 200;

  static double larguraFixaDireita({required bool alvosTouchAmplos}) {
    return larguraSubtotal +
        paddingSubtotalDireita +
        larguraGrupoQuantidade(alvosTouchAmplos: alvosTouchAmplos) +
        larguraGrupoAcoes(alvosTouchAmplos: alvosTouchAmplos);
  }

  static double larguraMinimaParaColunaUnitario({
    required bool alvosTouchAmplos,
  }) {
    return paddingHorizontal * 2 +
        larguraEntrega +
        larguraCodigo +
        larguraUnidadeMedida +
        larguraUnitario +
        larguraFixaDireita(alvosTouchAmplos: alvosTouchAmplos) +
        larguraProdutoMinimaConfortavel;
  }

  static bool cabeColunaUnitario({
    required double larguraDisponivel,
    required bool alvosTouchAmplos,
  }) {
    return larguraDisponivel >=
        larguraMinimaParaColunaUnitario(alvosTouchAmplos: alvosTouchAmplos);
  }

  static double minAcaoDe({required bool alvosTouchAmplos}) {
    if (pdvPlataformaCelular) return 32;
    return alvosTouchAmplos ? 36 : 32;
  }

  static double larguraGrupoQuantidade({required bool alvosTouchAmplos}) {
    final minAcao = minAcaoDe(alvosTouchAmplos: alvosTouchAmplos);
    return minAcao + larguraCampoQuantidade + minAcao;
  }

  static double larguraGrupoAcoes({required bool alvosTouchAmplos}) {
    final minAcao = minAcaoDe(alvosTouchAmplos: alvosTouchAmplos);
    return larguraBotaoTabela + minAcao + minAcao;
  }

  static Widget linha({
    required Widget entrega,
    required Widget codigo,
    required Widget unidadeMedida,
    required Widget produto,
    required Widget subtotal,
    required Widget grupoQuantidade,
    required Widget tabelaPreco,
    required Widget acoes,
    Widget? unitario,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        SizedBox(
          width: larguraEntrega,
          child: Align(
            alignment: Alignment.centerLeft,
            child: entrega,
          ),
        ),
        SizedBox(
          width: larguraCodigo,
          child: Align(
            alignment: Alignment.center,
            child: codigo,
          ),
        ),
        SizedBox(
          width: larguraUnidadeMedida,
          child: Align(
            alignment: Alignment.center,
            child: unidadeMedida,
          ),
        ),
        Expanded(child: produto),
        if (unitario != null)
          SizedBox(
            width: larguraUnitario,
            child: Align(
              alignment: Alignment.centerRight,
              child: unitario,
            ),
          ),
        Padding(
          padding: const EdgeInsets.only(right: paddingSubtotalDireita),
          child: SizedBox(
            width: larguraSubtotal,
            child: Align(
              alignment: Alignment.centerRight,
              child: subtotal,
            ),
          ),
        ),
        grupoQuantidade,
        SizedBox(
          width: larguraBotaoTabela,
          child: Center(child: tabelaPreco),
        ),
        acoes,
      ],
    );
  }

  static Widget slotAcao({
    required double tamanhoMinimo,
    required Widget child,
  }) {
    return SizedBox(
      width: tamanhoMinimo,
      height: tamanhoMinimo,
      child: child,
    );
  }

  static Widget grupoQuantidadeDe({
    required bool alvosTouchAmplos,
    required Widget diminuir,
    required Widget quantidade,
    required Widget aumentar,
  }) {
    final minAcao = minAcaoDe(alvosTouchAmplos: alvosTouchAmplos);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        slotAcao(tamanhoMinimo: minAcao, child: diminuir),
        SizedBox(
          width: larguraCampoQuantidade,
          child: Center(child: quantidade),
        ),
        slotAcao(tamanhoMinimo: minAcao, child: aumentar),
      ],
    );
  }

  static Widget acoesDe({
    required bool alvosTouchAmplos,
    required Widget dividir,
    required Widget remover,
  }) {
    final minAcao = minAcaoDe(alvosTouchAmplos: alvosTouchAmplos);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        slotAcao(tamanhoMinimo: minAcao, child: dividir),
        slotAcao(tamanhoMinimo: minAcao, child: remover),
      ],
    );
  }

  static Widget acoesCabecalhoDe({
    required bool alvosTouchAmplos,
    required Widget rotulo,
  }) {
    final minAcao = minAcaoDe(alvosTouchAmplos: alvosTouchAmplos);
    return SizedBox(
      width: minAcao * 2,
      child: Center(child: rotulo),
    );
  }
}
