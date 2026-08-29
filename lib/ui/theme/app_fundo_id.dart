import 'package:flutter/material.dart';

/// Planos de fundo pintados (sem foto): leves e legiveis sobre listas/PDV.
enum AppFundoId {
  liso(
    'liso',
    'Liso',
    'Cor solida do tema — o mais leve',
    Icons.crop_square_outlined,
  ),
  degrade(
    'degrade',
    'Degrade',
    'Lavagem forte na cor do tema, com manchas suaves',
    Icons.gradient,
  ),
  malha(
    'malha',
    'Malha',
    'Grade e pontos na area de trabalho',
    Icons.grid_4x4_outlined,
  ),
  faixa(
    'faixa',
    'Faixa',
    'Barra colorida na borda da tela de trabalho',
    Icons.view_sidebar_outlined,
  ),
  vinheta(
    'vinheta',
    'Vinheta',
    'Centro claro e cantos bem marcados na cor do tema',
    Icons.blur_circular_outlined,
  ),
  linhas(
    'linhas',
    'Linhas',
    'Riscado diagonal na cor do tema',
    Icons.texture,
  );

  const AppFundoId(this.codigo, this.rotulo, this.descricao, this.icone);

  final String codigo;
  final String rotulo;
  final String descricao;
  final IconData icone;

  bool get pintaCamada => this != AppFundoId.liso;

  static AppFundoId fromCodigo(String? raw) {
    if (raw == null || raw.trim().isEmpty) return AppFundoId.liso;
    final normalizado = raw.trim().toLowerCase();
    for (final fundo in AppFundoId.values) {
      if (fundo.codigo == normalizado) return fundo;
    }
    return AppFundoId.liso;
  }
}
