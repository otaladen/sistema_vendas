import 'package:objectbox/objectbox.dart';

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
  });

  @Id()
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

  final produto = ToOne<Produto>();
  final venda = ToOne<Venda>();

  double get subtotal => quantidade * precoUnitario;
  double get subtotalCusto => quantidade * precoCustoUnitario;
  double get lucro => subtotal - subtotalCusto;

  /// Unidades ainda nao retiradas quando a venda esta com retirada futura.
  int get quantidadePendenteRetirada {
    final p = quantidade - quantidadeJaRetirada;
    return p < 0 ? 0 : p;
  }

  /// Para carreto com reserva ate a saida (venda nativa, nao migrada de retirada
  /// futura): unidades que ainda seguem para o envio apos retirada na loja.
  int get quantidadeAindaNoCarretoAntesSaida {
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
