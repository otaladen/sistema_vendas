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

  static String rotulo(String status) {
    switch (status) {
      case devolucao:
        return 'Devolucao registrada';
      case troca:
        return 'Troca registrada';
      case retiradaFutura:
        return 'Retirada futura';
      case retiradaLojaPreSaida:
        return 'Retirada na loja (pre-saida)';
      case complementoPendente:
        return 'Complemento pendente';
      case podEntrega:
        return 'Comprovante de entrega (POD)';
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
}
