import '../../domain/entregas/carga_atual_venda.dart';
import '../../model/venda.dart';

/// Viagens previstas no pedido (1 sem plano de cargas).
int relatorioViagensTotal(Venda venda) {
  final cargas = CargaAtualVenda.cargas(venda);
  return cargas.isEmpty ? 1 : cargas.length;
}

int relatorioViagensFeitas(Venda venda) {
  final cargas = CargaAtualVenda.cargas(venda);
  if (cargas.isNotEmpty) return cargas.where((c) => c.entregue).length;
  final s = venda.statusEntrega;
  return s == 'entregue' || s == 'entregue_complemento_pendente' ? 1 : 0;
}

/// "Carga 2/3", "3 cargas" (todas entregues) ou vazio sem plano.
String relatorioRotuloCargas(Venda venda) {
  final cargas = CargaAtualVenda.cargas(venda);
  if (cargas.isEmpty) return '';
  return CargaAtualVenda.rotulo(venda) ?? '${cargas.length} cargas';
}

bool relatorioEntregaStatusFinalizado(String status) {
  return status == 'entregue' || status == 'cancelada';
}

bool relatorioEntregaEhAtrasada(Venda venda) {
  if (relatorioEntregaStatusFinalizado(venda.statusEntrega)) return false;
  final marcada = venda.dataEntregaMarcada?.toLocal();
  if (marcada == null) return false;
  final hoje = DateTime.now();
  final baseHoje = DateTime(hoje.year, hoje.month, hoje.day);
  final baseMarcada = DateTime(marcada.year, marcada.month, marcada.day);
  return baseMarcada.isBefore(baseHoje);
}

bool relatorioEntregaEhAgendaHoje(Venda venda) {
  if (relatorioEntregaStatusFinalizado(venda.statusEntrega)) return false;
  final marcada = venda.dataEntregaMarcada?.toLocal();
  if (marcada == null) return false;
  final hoje = DateTime.now();
  final baseHoje = DateTime(hoje.year, hoje.month, hoje.day);
  final baseMarcada = DateTime(marcada.year, marcada.month, marcada.day);
  return baseMarcada == baseHoje;
}

String relatorioRotuloStatusEntrega(String status) {
  switch (status) {
    case 'pendente':
      return 'Pendente';
    case 'roteirizada':
      return 'No patio';
    case 'saiu_entrega':
      return 'Saiu para entrega';
    case 'entregue_complemento_pendente':
      return 'Entregue c/ complemento';
    case 'entregue':
      return 'Entregue';
    case 'reagendada':
      return 'Reagendada';
    case 'cancelada':
      return 'Cancelada';
    default:
      return status;
  }
}
