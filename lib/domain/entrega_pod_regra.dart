/// Regras de quando solicitar ou exibir POD na expedicao.
abstract final class EntregaPodRegra {
  EntregaPodRegra._();

  static bool deveSolicitarPod({
    required String novoStatus,
    required String statusAnterior,
    required String podRecebidoPorAtual,
  }) {
    if (novoStatus != 'entregue') return false;
    if (podRecebidoPorAtual.trim().isEmpty) return true;
    return statusAnterior == 'entregue_complemento_pendente';
  }

  static bool temPodRegistrado(String podRecebidoPor) =>
      podRecebidoPor.trim().isNotEmpty;

  static bool temReferenciaFoto({
    required String podFotoPath,
    required String podFotoPathServidor,
  }) =>
      podFotoPath.trim().isNotEmpty || podFotoPathServidor.trim().isNotEmpty;
}
