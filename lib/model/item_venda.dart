import 'package:objectbox/objectbox.dart';

import '../domain/entrega_venda_helper.dart';
import '../domain/produto_embalagem.dart';
import '../domain/saldo_retirada_item.dart';
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
    this.loteConsumosJson = '',
    this.precoUnitarioManual = false,
    this.botaForaAplicado = false,
    this.percentualBotaForaAplicado = 0,
    this.lojaOrigemMercadoria = '',
    this.buscarNaLojaStatus = '',
    this.quantidadeBuscarNaLoja = 0,
    this.escalaQuantidade = escalaQuantidadeLegado,
  });

  static const int escalaQuantidadeLegado = 0;
  static const int escalaQuantidadeLiteral = 1;
  static const int escalaQuantidadeMilesimos = 1000;

  static int escalaDeFlag(bool? emMilesimos) => switch (emMilesimos) {
        true => escalaQuantidadeMilesimos,
        false => escalaQuantidadeLiteral,
        null => escalaQuantidadeLegado,
      };

  @Id(assignable: true)
  int id;

  String nomeProduto;
  int quantidade;

  /// Quantidade ja entregue ao cliente em baixas formais de patio.
  /// So mutar via [VendaRepository.registrarRetiradaParcial] (e fluxos de
  /// cupom/carreto equivalentes) — nunca por edicao manual ou payload solto.
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

  /// JSON: [{"loteId":1,"numeroLote":"001","dataValidade":"...","qtd":5}]
  String loteConsumosJson;

  /// Preco digitado/autorizado no PDV (Ctrl+P). Nao reaplicar catalogo/promo ao fechar.
  bool precoUnitarioManual;

  /// Desconto Bota-Fora aplicado automaticamente no PDV.
  bool botaForaAplicado;

  double percentualBotaForaAplicado;

  /// Loja de onde este item saiu de fato.
  /// Vazio (antes da saida) = padrao carreto: outra loja, sem baixa fisica aqui.
  String lojaOrigemMercadoria;

  /// Motorista pediu para buscar nesta loja: vazio | solicitado | separado.
  String buscarNaLojaStatus;

  /// Unidades desta linha que a outra loja nao tem (buscar nesta prateleira).
  /// Zero = linha inteira segue a origem gravada.
  int quantidadeBuscarNaLoja;

  /// Escala de [quantidade] e das quantidades derivadas (retirada, carreto...):
  /// [escalaQuantidadeMilesimos] (4200 = 4,2), [escalaQuantidadeLiteral]
  /// (1400 = 1400 UN) ou [escalaQuantidadeLegado] (itens antigos: heuristica).
  int escalaQuantidade;

  /// `null` = item legado sem escala gravada.
  bool? get quantidadeEmMilesimosPersistida => switch (escalaQuantidade) {
        escalaQuantidadeMilesimos => true,
        escalaQuantidadeLiteral => false,
        _ => null,
      };

  /// Escala definitiva (gravada ou deduzida pelo produto) para API/sync.
  bool get quantidadeEmMilesimosResolvida =>
      quantidadeEmMilesimosPersistida ??
      ProdutoEmbalagem.leituraArmazenadaEmMilesimos(
        produto: produtoOuNull,
        quantidadeArmazenada: quantidade,
      );

  final produto = ToOne<Produto>();
  final venda = ToOne<Venda>();

  /// Leitura segura: Terminal Leve / entidade detached nao tem ToOne inicializado.
  Produto? get produtoOuNull {
    try {
      return produto.target;
    } catch (_) {
      return null;
    }
  }

  double get quantidadeVendaEfetiva =>
      ProdutoEmbalagem.quantidadeVendaEfetivaItem(
        produto: produtoOuNull,
        quantidadeArmazenada: quantidade,
        emMilesimos: quantidadeEmMilesimosPersistida,
      );

  /// Quantidade em unidades de estoque ([Produto.unidade]) para baixa/reserva.
  int get quantidadeUnidadeEstoque =>
      ProdutoEmbalagem.unidadeEstoqueDeQuantidadeArmazenada(
        produto: produtoOuNull,
        quantidadeArmazenada: quantidade,
      );

  int quantidadeUnidadeEstoqueDe(int quantidadeArmazenada) =>
      ProdutoEmbalagem.unidadeEstoqueDeQuantidadeArmazenada(
        produto: produtoOuNull,
        quantidadeArmazenada: quantidadeArmazenada,
      );

  /// Quantidade formatada para listagens, cupom e detalhe da venda.
  String get quantidadeExibicaoVenda =>
      ProdutoEmbalagem.textoQuantidadeArmazenada(
        produto: produtoOuNull,
        quantidadeArmazenada: quantidade,
        emMilesimos: quantidadeEmMilesimosPersistida,
      );

  double get subtotal => quantidadeVendaEfetiva * precoUnitario;
  double get subtotalCusto => quantidadeVendaEfetiva * precoCustoUnitario;
  double get lucro => subtotal - subtotalCusto;

  /// Unidades ainda nao retiradas (somente itens [retirada_futura]).
  /// Desconta devolucao: o cliente nao pode retirar o que ja voltou ao estoque.
  int get quantidadePendenteRetirada {
    if (EntregaVendaHelper.tipoEfetivoItem(this) !=
        EntregaVendaHelper.tipoRetiradaFutura) {
      return 0;
    }
    return SaldoRetiradaItem.pendente(
      quantidade: quantidade,
      quantidadeJaRetirada: quantidadeJaRetirada,
      quantidadeDevolvida: quantidadeDevolvida,
    );
  }

  /// Carreto com reserva ate a saida: unidades que ainda seguem no romaneio
  /// (cliente pode buscar na loja antes do carro sair).
  int get quantidadeAindaNoCarretoAntesSaida {
    if (EntregaVendaHelper.tipoEfetivoItem(this) !=
        EntregaVendaHelper.tipoEntregaLoja) {
      return 0;
    }
    return SaldoRetiradaItem.pendente(
      quantidade: quantidade,
      quantidadeJaRetirada: quantidadeJaRetirada,
      quantidadeDevolvida: quantidadeDevolvida,
    );
  }

  /// Quantidade a mostrar na tela de entregas (carga / caminhao).
  ///
  /// Carreto: vendido liquido menos ja retirado na loja ([quantidadeJaRetirada]).
  /// Migracao retirada futura > carreto: [quantidadeNoCarreto].
  int quantidadeParaExibicaoEntrega(bool vendaUsaDestaqueCarreto) {
    if (vendaUsaDestaqueCarreto) {
      return quantidadeNoCarreto;
    }
    if (EntregaVendaHelper.tipoEfetivoItem(this) ==
        EntregaVendaHelper.tipoEntregaLoja) {
      return quantidadeAindaNoCarretoAntesSaida;
    }
    return quantidade;
  }
}
