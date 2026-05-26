import 'package:objectbox/objectbox.dart';

import '../domain/entrega_venda_helper.dart';
import 'produto.dart';
import 'venda.dart';

@Entity()
class ItemVenda {
  ItemVenda({
    this.id = 0,
    required this.nomeProduto,
    required this.quantidade,
    this.quantidadeJaRetirada = 0,
    this.quantidadeNoCarreto = 0,
    this.quantidadeDevolvida = 0,
    this.tipoEntregaItem = 'retirada',
    this.precoTipo = 'preco1',
    required this.precoUnitario,
    required this.precoCustoUnitario,
    this.promocaoId = 0,
    this.promocaoNomeSnapshot = '',
  });

  @Id(assignable: true)
  int id;

  String nomeProduto;
  int quantidade;

  /// Quantidade ja entregue ao cliente em retiradas parciais (retirada futura).
  int quantidadeJaRetirada;

  /// Unidades nesta linha que seguem no carreto apos migrar retirada futura > carreto.
  /// Zero = nao aplicavel (ex.: venda nativa carreto usa [quantidade] na UI).
  int quantidadeNoCarreto;

  /// Devolvido/trocado acumulado (registros de devolucao ligados a esta venda).
  int quantidadeDevolvida;

  /// retirada | retirada_futura | entrega_loja (padrao: leva agora).
  String tipoEntregaItem;

  String precoTipo;
  double precoUnitario;
  double precoCustoUnitario;

  /// Campanha aplicada na linha (0 = sem promocao).
  int promocaoId;

  /// Nome da campanha no momento da venda (relatorios).
  String promocaoNomeSnapshot;

  final produto = ToOne<Produto>();
  final venda = ToOne<Venda>();

  double get subtotal => quantidade * precoUnitario;
  double get subtotalCusto => quantidade * precoCustoUnitario;
  double get lucro => subtotal - subtotalCusto;

  /// Unidades ainda nao retiradas (somente itens [retirada_futura]).
  int get quantidadePendenteRetirada {
    if (EntregaVendaHelper.tipoEfetivoItem(this) !=
        EntregaVendaHelper.tipoRetiradaFutura) {
      return 0;
    }
    final p = quantidade - quantidadeJaRetirada;
    return p < 0 ? 0 : p;
  }

  /// Carreto com reserva ate a saida: unidades que ainda seguem no romaneio
  /// (cliente pode buscar na loja antes do carro sair).
  int get quantidadeAindaNoCarretoAntesSaida {
    if (EntregaVendaHelper.tipoEfetivoItem(this) !=
        EntregaVendaHelper.tipoEntregaLoja) {
      return 0;
    }
    final p = quantidade - quantidadeDevolvida - quantidadeJaRetirada;
    return p < 0 ? 0 : p;
  }

  /// Quantidade a mostrar na tela de entregas (carga / caminhao).
  int quantidadeParaExibicaoEntrega(
    bool vendaUsaDestaqueCarreto, {
    bool carretoReservaNativoAntesSaida = false,
  }) {
    if (vendaUsaDestaqueCarreto) {
      return quantidadeNoCarreto;
    }
    if (carretoReservaNativoAntesSaida) {
      return quantidadeAindaNoCarretoAntesSaida;
    }
    return quantidade;
  }
}
