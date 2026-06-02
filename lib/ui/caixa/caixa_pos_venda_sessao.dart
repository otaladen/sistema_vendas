import '../../model/venda.dart';

/// Dados da venda recém-finalizada para a etapa fiscal (Fase 3).
class CaixaPosVendaSessao {
  const CaixaPosVendaSessao({
    required this.venda,
    required this.totalRecebido,
    required this.troco,
  });

  final Venda venda;
  final double totalRecebido;
  final double troco;

  CaixaPosVendaSessao copyWith({Venda? venda}) {
    return CaixaPosVendaSessao(
      venda: venda ?? this.venda,
      totalRecebido: totalRecebido,
      troco: troco,
    );
  }
}
