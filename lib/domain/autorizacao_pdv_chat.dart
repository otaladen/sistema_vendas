import '../model/usuario_sistema.dart';
import 'perfil_usuario_preset.dart';
import 'permissao_usuario.dart';
import 'usuario_permissao_helper.dart';

/// Tipo da operacao que o PDV pede para o gerente autorizar no chat.
abstract final class AutorizacaoPdvChatTipo {
  AutorizacaoPdvChatTipo._();

  static const descontoAcimaTeto = 'desconto_acima_teto';
  static const precoUnitario = 'preco_unitario';
  static const margemPromocao = 'margem_promocao';

  static String rotulo(String tipo) {
    switch (tipo) {
      case descontoAcimaTeto:
        return 'Desconto acima do teto';
      case precoUnitario:
        return 'Alterar preco unitario';
      case margemPromocao:
        return 'Margem promocional';
      default:
        return tipo;
    }
  }
}

abstract final class AutorizacaoPdvChatStatus {
  AutorizacaoPdvChatStatus._();

  static const pendente = 'pendente';
  static const aprovada = 'aprovada';
  static const recusada = 'recusada';
  static const cancelada = 'cancelada';

  static bool ehFinal(String status) =>
      status == aprovada || status == recusada || status == cancelada;
}

/// Tipo de mensagem especial no mural interno.
const kMensagemInternaTipoAutorizacaoPdv = 'autorizacao_pdv';
const kMensagemInternaTipoTexto = 'texto';

/// Evento WS emitido quando o gerente responde a solicitacao.
const kEventoAutorizacaoPdvResposta = 'autorizacao_pdv_resposta';

/// Payload da solicitacao de autorizacao via chat interno.
class AutorizacaoPdvChatPayload {
  const AutorizacaoPdvChatPayload({
    required this.solicitacaoId,
    required this.tipoOperacao,
    required this.operadorLogin,
    required this.operadorNome,
    required this.timestamp,
    this.vendaId = 0,
    this.carrinhoId = '',
    this.valorOriginal = 0,
    this.valorSolicitado = 0,
    this.descricaoAcao = '',
    this.stationId = '',
    this.status = AutorizacaoPdvChatStatus.pendente,
    this.respondidoPor = '',
    this.respondidoEm,
    this.motivo = '',
  });

  final String solicitacaoId;
  final String tipoOperacao;
  final String operadorLogin;
  final String operadorNome;
  final DateTime timestamp;
  final int vendaId;
  final String carrinhoId;
  final double valorOriginal;
  final double valorSolicitado;
  final String descricaoAcao;
  final String stationId;
  final String status;
  final String respondidoPor;
  final DateTime? respondidoEm;
  final String motivo;

  bool get pendente => status == AutorizacaoPdvChatStatus.pendente;

  String get tituloCard => 'Solicitacao de Autorizacao - PDV';

  String textoResumoChat() {
    final acao = descricaoAcao.trim().isNotEmpty
        ? descricaoAcao.trim()
        : AutorizacaoPdvChatTipo.rotulo(tipoOperacao);
    final op = operadorNome.trim().isNotEmpty
        ? operadorNome.trim()
        : operadorLogin;
    return 'Solicitacao de Autorizacao - PDV: $acao. Operador: $op. @gerente';
  }

  Map<String, dynamic> toMap() => {
        'solicitacaoId': solicitacaoId,
        'tipoOperacao': tipoOperacao,
        'operadorLogin': operadorLogin,
        'operadorNome': operadorNome,
        'timestamp': timestamp.toUtc().toIso8601String(),
        'vendaId': vendaId,
        'carrinhoId': carrinhoId,
        'valorOriginal': valorOriginal,
        'valorSolicitado': valorSolicitado,
        'descricaoAcao': descricaoAcao,
        'stationId': stationId,
        'status': status,
        if (respondidoPor.isNotEmpty) 'respondidoPor': respondidoPor,
        if (respondidoEm != null)
          'respondidoEm': respondidoEm!.toUtc().toIso8601String(),
        if (motivo.isNotEmpty) 'motivo': motivo,
      };

  factory AutorizacaoPdvChatPayload.fromMap(Map<String, dynamic> map) {
    DateTime parseDt(Object? raw) {
      if (raw is DateTime) return raw.toUtc();
      return DateTime.tryParse('$raw')?.toUtc() ?? DateTime.now().toUtc();
    }

    int parseInt(Object? raw) {
      if (raw is num) return raw.toInt();
      return int.tryParse('$raw') ?? 0;
    }

    double parseDouble(Object? raw) {
      if (raw is num) return raw.toDouble();
      return double.tryParse('$raw') ?? 0;
    }

    final respEm = map['respondidoEm'];
    return AutorizacaoPdvChatPayload(
      solicitacaoId: (map['solicitacaoId'] ?? '').toString().trim(),
      tipoOperacao: (map['tipoOperacao'] ?? AutorizacaoPdvChatTipo.descontoAcimaTeto)
          .toString()
          .trim(),
      operadorLogin: (map['operadorLogin'] ?? '').toString().trim(),
      operadorNome: (map['operadorNome'] ?? '').toString().trim(),
      timestamp: parseDt(map['timestamp']),
      vendaId: parseInt(map['vendaId']),
      carrinhoId: (map['carrinhoId'] ?? '').toString().trim(),
      valorOriginal: parseDouble(map['valorOriginal']),
      valorSolicitado: parseDouble(map['valorSolicitado']),
      descricaoAcao: (map['descricaoAcao'] ?? '').toString().trim(),
      stationId: (map['stationId'] ?? '').toString().trim(),
      status: (map['status'] ?? AutorizacaoPdvChatStatus.pendente)
          .toString()
          .trim(),
      respondidoPor: (map['respondidoPor'] ?? '').toString().trim(),
      respondidoEm: respEm == null || '$respEm'.isEmpty ? null : parseDt(respEm),
      motivo: (map['motivo'] ?? '').toString().trim(),
    );
  }

  AutorizacaoPdvChatPayload copyWith({
    String? status,
    String? respondidoPor,
    DateTime? respondidoEm,
    String? motivo,
  }) {
    return AutorizacaoPdvChatPayload(
      solicitacaoId: solicitacaoId,
      tipoOperacao: tipoOperacao,
      operadorLogin: operadorLogin,
      operadorNome: operadorNome,
      timestamp: timestamp,
      vendaId: vendaId,
      carrinhoId: carrinhoId,
      valorOriginal: valorOriginal,
      valorSolicitado: valorSolicitado,
      descricaoAcao: descricaoAcao,
      stationId: stationId,
      status: status ?? this.status,
      respondidoPor: respondidoPor ?? this.respondidoPor,
      respondidoEm: respondidoEm ?? this.respondidoEm,
      motivo: motivo ?? this.motivo,
    );
  }
}

class AutorizacaoPdvChatResposta {
  const AutorizacaoPdvChatResposta({
    required this.solicitacaoId,
    required this.status,
    required this.respondidoPor,
    this.motivo = '',
  });

  final String solicitacaoId;
  final String status;
  final String respondidoPor;
  final String motivo;

  bool get aprovada => status == AutorizacaoPdvChatStatus.aprovada;
  bool get recusada => status == AutorizacaoPdvChatStatus.recusada;
  bool get cancelada => status == AutorizacaoPdvChatStatus.cancelada;

  factory AutorizacaoPdvChatResposta.fromMap(Map<String, dynamic> map) {
    return AutorizacaoPdvChatResposta(
      solicitacaoId: (map['solicitacaoId'] ?? '').toString().trim(),
      status: (map['status'] ?? '').toString().trim(),
      respondidoPor: (map['respondidoPor'] ?? '').toString().trim(),
      motivo: (map['motivo'] ?? '').toString().trim(),
    );
  }
}

/// Quem pode Aprovar/Recusar o card no chat (Gerente/Admin ou permissao da acao).
bool usuarioPodeResponderAutorizacaoPdvChat(
  UsuarioSistema u, {
  String tipoOperacao = AutorizacaoPdvChatTipo.descontoAcimaTeto,
}) {
  if (!u.ativo) return false;
  if (u.admin) return true;
  final perfil = perfilUsuarioFromId(u.perfil);
  if (perfil == PerfilUsuarioPreset.gerente ||
      perfil == PerfilUsuarioPreset.dono) {
    return true;
  }
  switch (tipoOperacao) {
    case AutorizacaoPdvChatTipo.precoUnitario:
      return UsuarioPermissaoHelper.tem(
        u,
        PermissaoUsuario.alterarPrecoUnitarioPdv,
      );
    case AutorizacaoPdvChatTipo.margemPromocao:
      return UsuarioPermissaoHelper.podeAutorizarMargemPromocao(u);
    case AutorizacaoPdvChatTipo.descontoAcimaTeto:
    default:
      return UsuarioPermissaoHelper.tem(u, PermissaoUsuario.alterarPrecoPdv);
  }
}
