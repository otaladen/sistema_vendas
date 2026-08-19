import '../model/venda.dart';

/// Regras do fluxo simplificado de Entregas / Patio.
///
/// Operacao: definir motorista (auto-roteiriza) → motorista libera saida
/// no celular (carga na outra loja) → Entregue. Patio acompanha na aba Entregas.
abstract final class EntregaFluxoService {
  EntregaFluxoService._();

  /// Status elegiveis para o botao unico "Liberar Saida".
  static bool podeLiberarSaida(Venda venda) {
    switch (venda.statusEntrega) {
      case 'pendente':
      case 'reagendada':
      case 'roteirizada':
        return true;
      default:
        return false;
    }
  }

  /// Ja esta em rota (motorista ja liberou ou o patio liberou).
  static bool jaSaiuParaEntrega(Venda venda) =>
      venda.cargaSaiu || venda.statusEntrega == 'saiu_entrega';

  /// Pedidos da mesma viagem (grupo) para liberar juntos.
  static List<Venda> vendasMesmoDespacho(
    Venda alvo,
    Iterable<Venda> candidatas,
  ) {
    final grupo = alvo.grupoEntregaFreteId;
    if (grupo <= 0) return [alvo];
    final irmaos = candidatas
        .where((v) => v.id > 0 && v.grupoEntregaFreteId == grupo)
        .toList();
    return irmaos.isEmpty ? [alvo] : irmaos;
  }

  /// Ao vincular motorista/veiculo, sobe automaticamente para roteirizada
  /// (status interno; na tela continua no patio).
  static bool deveAutoRoteirizar({
    required String statusEntrega,
    required String motorista,
  }) {
    if (motorista.trim().isEmpty) return false;
    return statusEntrega == 'pendente' || statusEntrega == 'reagendada';
  }

  /// Proximo passo operacional apos saida do caminhao.
  static bool podeMarcarEntregue(Venda venda) =>
      venda.statusEntrega == 'saiu_entrega';
}
