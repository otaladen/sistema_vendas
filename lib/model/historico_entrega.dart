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

  @Id(assignable: true)
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
  static const retiradaFutura = 'retirada_futura';
  static const retiradaLojaPreSaida = 'retirada_loja_pre_saida';
  static const complementoPendente = 'complemento_pendente';
  static const podEntrega = 'pod_entrega';

  static bool ehEventoOcorrencia(String statusNovo) {
    switch (statusNovo) {
      case devolucao:
      case troca:
      case retiradaFutura:
      case retiradaLojaPreSaida:
      case complementoPendente:
      case podEntrega:
        return true;
      default:
        return false;
    }
  }
}
