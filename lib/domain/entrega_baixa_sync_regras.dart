/// Regras da fila offline do motorista (POD + texto).
abstract final class EntregaBaixaSyncRegras {
  EntregaBaixaSyncRegras._();

  /// Sobe o JPEG pela LAN antes do POST de baixa, se ainda nao ha path no PC.
  ///
  /// [fotoPathServidor] so deve vir preenchido apos POST `/api/entregas/pod-foto`
  /// (ou gravacao local no PC). O caminho previsto `pod_entrega/venda_*.jpg`
  /// no celular nao conta — senao a fila pula o upload e o PC fica sem arquivo.
  static bool precisaEnviarFoto({
    required bool ehNaoEntregue,
    required String fotoPathLocal,
    required String fotoPathServidor,
    required bool arquivoLocalExiste,
  }) {
    if (ehNaoEntregue) return false;
    if (fotoPathServidor.trim().isNotEmpty) return false;
    if (fotoPathLocal.trim().isEmpty) return false;
    return arquivoLocalExiste;
  }

  /// So some da fila quando o PC confirmou o texto e, se havia foto, o path.
  static bool podeConfirmarRemocao({
    required bool servidorConfirmou,
    required bool ehNaoEntregue,
    required String fotoPathLocal,
    required String fotoPathServidor,
    required bool arquivoLocalExiste,
  }) {
    if (!servidorConfirmou) return false;
    if (ehNaoEntregue) return true;
    if (fotoPathLocal.trim().isEmpty) return true;
    if (fotoPathServidor.trim().isNotEmpty) return true;
    // Arquivo sumiu no aparelho: nao trava a fila para sempre.
    return !arquivoLocalExiste;
  }

  static String mensagemErroPermanente(Object e) {
    final m = '$e'.toLowerCase();
    if (m.contains('entrega_status_terminal') ||
        m.contains('ja foi marcada como entregue') ||
        m.contains('ja foi reagendada') ||
        m.contains('conflito')) {
      return 'A loja ja alterou esta entrega (reagendada ou ja baixada). '
          'Fale com a expedicao.';
    }
    if (m.contains('nao encontrada') || m.contains('nao encontrado')) {
      return 'Esta entrega nao foi encontrada no servidor. Fale com a expedicao.';
    }
    if (m.contains('cancelada')) {
      return 'Esta entrega foi cancelada na loja.';
    }
    return 'A loja recusou a baixa. Fale com a expedicao.';
  }
}
