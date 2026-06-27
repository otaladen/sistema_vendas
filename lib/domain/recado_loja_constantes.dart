import 'perfil_usuario_preset.dart';

/// Prioridade de exibicao do recado interno.
abstract final class RecadoLojaPrioridade {
  static const normal = 'normal';
  static const importante = 'importante';
  static const urgente = 'urgente';

  static const todos = [normal, importante, urgente];

  static String rotulo(String id) {
    switch (id) {
      case importante:
        return 'Importante';
      case urgente:
        return 'Urgente';
      case normal:
      default:
        return 'Normal';
    }
  }
}

/// Destino do recado (Fase 1: todos ou um perfil).
abstract final class RecadoLojaDestino {
  static const todos = 'todos';
  static const perfil = 'perfil';

  static const perfisDisponiveis = [
    PerfilUsuarioPreset.vendedor,
    PerfilUsuarioPreset.caixa,
    PerfilUsuarioPreset.separador,
    PerfilUsuarioPreset.motorista,
    PerfilUsuarioPreset.comprador,
    PerfilUsuarioPreset.gerente,
    PerfilUsuarioPreset.dono,
  ];

  static String rotuloTipo(String tipo, String perfilId) {
    if (tipo == perfil) {
      return 'Perfil: ${perfilUsuarioFromId(perfilId).rotulo}';
    }
    return 'Toda a loja';
  }
}
