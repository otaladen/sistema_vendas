import 'package:objectbox/objectbox.dart';

import '../domain/retirada_parcial_evento.dart';
import '../domain/entregas/carreto_saida_produto_orfao.dart';
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
  static const naoEntregue = 'entrega_evento_nao_entregue';
  static const buscarNaLoja = 'entrega_evento_buscar_na_loja';
  static const carretoSaidaProdutoOrfao = 'carreto_saida_produto_orfao';

  static bool ehEventoOcorrencia(String statusNovo) {
    switch (statusNovo) {
      case devolucao:
      case troca:
      case retiradaFutura:
      case retiradaLojaPreSaida:
      case complementoPendente:
      case podEntrega:
      case naoEntregue:
      case buscarNaLoja:
      case carretoSaidaProdutoOrfao:
        return true;
      default:
        return false;
    }
  }

  static bool ehEventoRetirada(String statusNovo) {
    return statusNovo == retiradaFutura || statusNovo == retiradaLojaPreSaida;
  }

  /// Texto humano do detalhe (JSON estruturado nas baixas de patio).
  static String textoDetalhe(String statusNovo, String statusAnterior) {
    if (statusNovo == carretoSaidaProdutoOrfao) {
      final ev = CarretoSaidaProdutoOrfaoEvento.tryParse(statusAnterior);
      if (ev != null) return ev.textoHumano;
    }
    if (ehEventoRetirada(statusNovo)) {
      final ev = RetiradaParcialEvento.tryParse(statusAnterior);
      if (ev != null) return ev.textoHumano;
    }
    return statusAnterior;
  }

  static String textoStatusAnteriorParaExibicao(
    String statusNovo,
    String statusAnterior,
  ) {
    if (ehEventoRetirada(statusNovo)) {
      return textoDetalhe(statusNovo, statusAnterior);
    }
    return rotulo(statusAnterior);
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
      case naoEntregue:
        return 'Nao entregue';
      case buscarNaLoja:
        return 'Buscar nesta loja';
      case carretoSaidaProdutoOrfao:
        return 'Saida carreto (produto excluido)';
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
}
