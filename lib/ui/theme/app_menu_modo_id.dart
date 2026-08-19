import 'package:flutter/material.dart';

/// Estilo visual do menu principal (independente do tema global de cores).
enum AppMenuModoId {
  classico(
    'classico',
    'Classico',
    'Menu lateral padrao do sistema',
    Icons.view_agenda_outlined,
  ),
  colorido(
    'colorido',
    'Colorido',
    'Lateral com fundo tintado e itens destacados',
    Icons.palette_outlined,
  ),
  vibrante(
    'vibrante',
    'Vibrante',
    'Lateral escura com cores solidas por modulo',
    Icons.grid_view_rounded,
  ),
  amplo(
    'amplo',
    'Amplo',
    'Lateral largo com gradiente e icones grandes',
    Icons.view_module_outlined,
  ),
  neon(
    'neon',
    'Neon',
    'Fundo escuro com brilho neon no item ativo',
    Icons.lightbulb_outline_rounded,
  ),
  pastel(
    'pastel',
    'Pastel',
    'Tons suaves e claros por modulo',
    Icons.wb_sunny_outlined,
  ),
  retro(
    'retro',
    'ERP compacto',
    'Menu estreito estilo retaguarda: letras pequenas e icones coloridos',
    Icons.computer_outlined,
  ),
  faixa(
    'faixa',
    'Faixa',
    'Barra colorida lateral em cada item',
    Icons.view_sidebar_outlined,
  );

  const AppMenuModoId(
    this.codigo,
    this.rotulo,
    this.descricao,
    this.icone,
  );

  final String codigo;
  final String rotulo;
  final String descricao;
  final IconData icone;

  static AppMenuModoId fromCodigo(String? raw) {
    if (raw == null || raw.trim().isEmpty) return AppMenuModoId.classico;
    final normalizado = raw.trim().toLowerCase();
    for (final modo in AppMenuModoId.values) {
      if (modo.codigo == normalizado) return modo;
    }
    return AppMenuModoId.classico;
  }
}
