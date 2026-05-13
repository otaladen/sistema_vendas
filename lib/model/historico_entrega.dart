import 'package:objectbox/objectbox.dart';

import 'venda.dart';

@Entity()
class HistoricoEntrega {
  HistoricoEntrega({
    this.id = 0,
    this.statusAnterior = '',
    this.statusNovo = '',
    this.usuario = '',
    DateTime? dataHora,
  }) : dataHora = dataHora ?? DateTime.now();

  @Id()
  int id;

  String statusAnterior;
  String statusNovo;
  String usuario;

  @Property(type: PropertyType.dateUtc)
  DateTime dataHora;

  final venda = ToOne<Venda>();
}

/// Valores sinteticos em [HistoricoEntrega.statusNovo] para eventos que nao sao transicao de status de roteiro.
class HistoricoEntregaEventos {
  HistoricoEntregaEventos._();

  static const devolucao = 'entrega_evento_devolucao';
  static const troca = 'entrega_evento_troca';
}
