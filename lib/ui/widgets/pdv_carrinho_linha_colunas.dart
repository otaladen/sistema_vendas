import 'package:flutter/material.dart';

import 'pdv_mobile_ui.dart';

/// Estrutura de colunas compartilhada entre cabecalho e linha do carrinho PDV.
abstract final class PdvCarrinhoLinhaColunas {
  PdvCarrinhoLinhaColunas._();

  static const double paddingHorizontal = 4;
  static const double paddingSubtotalDireita = 2;
  static const double larguraEntrega = 56;
  static const double larguraCodigo = 60;
  static const double larguraUnidadeMedida = 44;
  static const double larguraUnitario = 86;
  static const double larguraSubtotal = 90;
  static const double larguraBotaoTabela = 28;
  static const double larguraCampoQuantidade = 26;
  static const int flexProduto = 4;
  static const double larguraProdutoMinimaConfortavel = 140;

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

  /// Alvos menores que [minAcaoDe] para caber o grupo QTD em ~70px.
  static double minAcaoQuantidadeDe({required bool alvosTouchAmplos}) {
    return alvosTouchAmplos ? 24 : 22;
  }

  static double larguraGrupoQuantidade({required bool alvosTouchAmplos}) {
    final minAcao = minAcaoQuantidadeDe(alvosTouchAmplos: alvosTouchAmplos);
    return minAcao + larguraCampoQuantidade + minAcao;
  }

  static Widget celulaMonetaria({
    required double largura,
    required Widget child,
    EdgeInsetsGeometry? padding,
  }) {
    return Padding(
      padding: padding ?? EdgeInsets.zero,
      child: SizedBox(
        width: largura,
        child: Align(
          alignment: Alignment.centerRight,
          child: FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerRight,
            child: child,
          ),
        ),
      ),
    );
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
        Expanded(flex: flexProduto, child: produto),
        if (unitario != null)
          celulaMonetaria(largura: larguraUnitario, child: unitario),
        celulaMonetaria(
          largura: larguraSubtotal,
          padding: const EdgeInsets.only(right: paddingSubtotalDireita),
          child: subtotal,
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
    final minAcao = minAcaoQuantidadeDe(alvosTouchAmplos: alvosTouchAmplos);
    return SizedBox(
      width: larguraGrupoQuantidade(alvosTouchAmplos: alvosTouchAmplos),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        mainAxisSize: MainAxisSize.min,
        children: [
          slotAcao(tamanhoMinimo: minAcao, child: diminuir),
          SizedBox(
            width: larguraCampoQuantidade,
            child: Center(child: quantidade),
          ),
          slotAcao(tamanhoMinimo: minAcao, child: aumentar),
        ],
      ),
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
