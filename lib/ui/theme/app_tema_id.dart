import 'package:flutter/material.dart';

/// Paletas disponiveis no seletor "Temas" (estilo Chacal, modernizado).
enum AppTemaId {
  verde('verde', 'Verde', Color(0xFF009688)),
  azul('azul', 'Azul', Color(0xFF1565C0)),
  neutro('neutro', 'Neutro', Color(0xFF546E7A)),
  laranja('laranja', 'Laranja', Color(0xFFE65100)),
  escuro('escuro', 'Escuro', Color(0xFF26A69A));

  const AppTemaId(this.codigo, this.rotulo, this.corDestaque);

  final String codigo;
  final String rotulo;
  final Color corDestaque;

  bool get isDark => this == AppTemaId.escuro;

  static AppTemaId fromCodigo(String? raw) {
    if (raw == null || raw.trim().isEmpty) return AppTemaId.verde;
    final normalizado = raw.trim().toLowerCase();
    for (final tema in AppTemaId.values) {
      if (tema.codigo == normalizado) return tema;
    }
    return AppTemaId.verde;
  }
}
