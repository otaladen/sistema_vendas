import '../../model/venda.dart';

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
      return 'Roteirizada';
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
