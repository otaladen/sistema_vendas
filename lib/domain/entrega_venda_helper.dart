import '../model/item_venda.dart';
import '../model/venda.dart';

/// Tipos de entrega por item e na venda (inclui [tipoMisto] no cabecalho).
class EntregaVendaHelper {
  EntregaVendaHelper._();

  static const String tipoRetirada = 'retirada';
  static const String tipoRetiradaFutura = 'retirada_futura';
  static const String tipoEntregaLoja = 'entrega_loja';
  static const String tipoMisto = 'misto';

  static const List<String> tiposItem = [
    tipoRetirada,
    tipoRetiradaFutura,
    tipoEntregaLoja,
  ];

  static String normalizarTipoItem(String? valor) {
    switch (valor) {
      case tipoEntregaLoja:
      case tipoRetiradaFutura:
        return valor!;
      default:
        return tipoRetirada;
    }
  }

  static String proximoTipoItem(String atual) {
    switch (normalizarTipoItem(atual)) {
      case tipoRetirada:
        return tipoRetiradaFutura;
      case tipoRetiradaFutura:
        return tipoEntregaLoja;
      default:
        return tipoRetirada;
    }
  }

  static String resolverTipoEntregaVenda(Iterable<String> tiposItens) {
    final set = tiposItens.map(normalizarTipoItem).toSet();
    if (set.isEmpty) return tipoRetirada;
    if (set.length == 1) return set.first;
    return tipoMisto;
  }

  static bool iterableTemCarreto(Iterable<String> tiposItens) {
    return tiposItens.any((t) => normalizarTipoItem(t) == tipoEntregaLoja);
  }

  static bool iterableTemRetiradaFutura(Iterable<String> tiposItens) {
    return tiposItens.any((t) => normalizarTipoItem(t) == tipoRetiradaFutura);
  }

  static bool vendaTemItensCarreto(Venda venda, {List<ItemVenda>? itens}) {
    try {
      final lista = itens ?? List<ItemVenda>.from(venda.itens);
      if (lista.isNotEmpty) {
        return lista.any(
          (i) => normalizarTipoItem(i.tipoEntregaItem) == tipoEntregaLoja,
        );
      }
    } catch (_) {}
    return venda.tipoEntrega == tipoEntregaLoja;
  }

  static bool vendaTemItensRetiradaFutura(Venda venda, {List<ItemVenda>? itens}) {
    try {
      final lista = itens ?? List<ItemVenda>.from(venda.itens);
      if (lista.isNotEmpty) {
        return lista.any(
          (i) => normalizarTipoItem(i.tipoEntregaItem) == tipoRetiradaFutura,
        );
      }
    } catch (_) {}
    return venda.tipoEntrega == tipoRetiradaFutura && venda.entregaPendente;
  }

  /// Itens "leva agora" com quantidade ainda nao baixada no cupom interno.
  static bool vendaTemItensRetiradaImediataPendenteCupom(
    Venda venda, {
    List<ItemVenda>? itens,
  }) {
    try {
      final lista = itens ?? List<ItemVenda>.from(venda.itens);
      return lista.any(
        (i) =>
            tipoEfetivoItem(i) == tipoRetirada &&
            i.quantidade > 0 &&
            i.quantidadeJaRetirada < i.quantidade,
      );
    } catch (_) {
      return false;
    }
  }

  /// Orcamentos antigos (tipo so no cabecalho): replica no item antes de finalizar.
  ///
  /// Regras (nao promover "leva agora" a reserva por engano):
  /// - Cabecalho [tipoRetirada] ou [tipoMisto]: **nunca** altera itens.
  /// - Cabecalho unico futura/carreto + **todos** os itens ainda no padrao
  ///   "retirada" (tipo de item perdido no persist): replica o cabecalho.
  /// - Nao usar [Venda.entregaPendente] sozinho — flag stale em orcamento
  ///   "leva agora" convertia tudo em reserva sem baixa fisica.
  static void aplicarLegadoTipoUnicoNosItensSeNecessario(
    Venda venda, {
    Iterable<ItemVenda>? itens,
  }) {
    List<ItemVenda> lista;
    try {
      lista = (itens ?? venda.itens).toList();
    } catch (_) {
      return;
    }
    if (lista.isEmpty) return;

    final cabecalho = venda.tipoEntrega;
    if (cabecalho == tipoMisto || cabecalho == tipoRetirada) {
      return;
    }
    if (cabecalho != tipoRetiradaFutura && cabecalho != tipoEntregaLoja) {
      return;
    }

    final todosPadraoRetirada = lista.every(
      (i) => normalizarTipoItem(i.tipoEntregaItem) == tipoRetirada,
    );
    if (!todosPadraoRetirada) return;

    final tipoCabecalho = normalizarTipoItem(cabecalho);
    for (final item in lista) {
      item.tipoEntregaItem = tipoCabecalho;
    }
  }

  static String tipoEfetivoItem(ItemVenda item) {
    return normalizarTipoItem(item.tipoEntregaItem);
  }

  static String rotuloTipoItem(String tipo) {
    switch (normalizarTipoItem(tipo)) {
      case tipoEntregaLoja:
        return 'Carreto';
      case tipoRetiradaFutura:
        return 'Retirada futura';
      default:
        return 'Leva agora';
    }
  }

  /// Modalidade curta para PDF de orcamento (materiais de construcao).
  static String rotuloModalidadeOrcamentoPdf(String tipo) {
    switch (normalizarTipoItem(tipo)) {
      case tipoEntregaLoja:
        return '[ENTREGA/CARRETO]';
      case tipoRetiradaFutura:
        return '[RETIRADA FUTURA]';
      default:
        return '[RETIRA LOGO]';
    }
  }

  static String emojiTipoItem(String tipo) {
    switch (normalizarTipoItem(tipo)) {
      case tipoEntregaLoja:
        return '🚚';
      case tipoRetiradaFutura:
        return '🕒';
      default:
        return '📦';
    }
  }

  static String rotuloTipoEntregaVenda(String tipoEntrega) {
    switch (tipoEntrega) {
      case tipoEntregaLoja:
        return 'Carreto';
      case tipoRetiradaFutura:
        return 'Retirada futura';
      case tipoMisto:
        return 'Venda mista';
      case tipoRetirada:
      default:
        return 'Leva agora';
    }
  }

  /// Texto de entrega no cabecalho (PDF / listagens).
  ///
  /// Passe [itens] no Terminal Leve (ToMany detached quebra sem override).
  static String textoEntregaCabecalhoVenda(
    Venda venda, {
    Iterable<ItemVenda>? itens,
  }) {
    if (venda.tipoEntrega == tipoMisto) {
      try {
        final lista = itens ?? venda.itens;
        final resumo = resumoContagem(lista.map((i) => i.tipoEntregaItem));
        return resumo.isEmpty ? 'Venda mista' : 'Venda mista ($resumo)';
      } catch (_) {
        return 'Venda mista';
      }
    }
    return rotuloTipoEntregaVenda(venda.tipoEntrega);
  }

  /// Sufixo curto na linha do item em PDF (ex.: [Carreto]).
  static String sufixoEntregaItemPdf(ItemVenda item) {
    final rotulo = rotuloTipoItem(item.tipoEntregaItem);
    return ' [$rotulo]';
  }

  static String abreviacaoTipoItem(String tipo) {
    switch (normalizarTipoItem(tipo)) {
      case tipoEntregaLoja:
        return 'Car.';
      case tipoRetiradaFutura:
        return 'Fut.';
      default:
        return 'Lv.';
    }
  }

  /// Rotulo curto na linha do carrinho PDV (icone + texto).
  static String rotuloCurtoTipoItem(String tipo) {
    switch (normalizarTipoItem(tipo)) {
      case tipoEntregaLoja:
        return 'Carreto';
      case tipoRetiradaFutura:
        return 'Futura';
      default:
        return 'Leva';
    }
  }

  /// Item de venda que migrou de retirada futura para carreto (apos frete).
  static bool itemMigradoRetiradaFuturaParaCarreto(ItemVenda item) {
    return tipoEfetivoItem(item) == tipoRetiradaFutura &&
        item.quantidadeNoCarreto > 0;
  }

  /// Venda com itens migrados retirada futura > carreto (nao usar retirada na loja nativa).
  static bool vendaTemItensMigradosRetiradaParaCarreto(
    Venda venda, {
    List<ItemVenda>? itens,
  }) {
    try {
      final lista = itens ?? List<ItemVenda>.from(venda.itens);
      return lista.any(itemMigradoRetiradaFuturaParaCarreto);
    } catch (_) {
      return false;
    }
  }

  /// Cliente pode buscar na loja itens de carreto antes do romaneio sair.
  static bool vendaPermiteRetiradaLojaCarretoAntesSaida(
    Venda venda, {
    List<ItemVenda>? itens,
  }) {
    if (venda.cancelada || venda.status != 'finalizada') return false;
    if (!venda.carretoReservaAteSaida || venda.cargaSaiu) return false;
    try {
      final lista = itens ?? List<ItemVenda>.from(venda.itens);
      return lista.any((i) => i.quantidadeAindaNoCarretoAntesSaida > 0);
    } catch (_) {
      return false;
    }
  }

  static bool vendaCarretoReservaNativaSemMigracao(
    Venda venda, {
    List<ItemVenda>? itens,
  }) {
    return venda.carretoReservaAteSaida &&
        vendaTemItensCarreto(venda, itens: itens) &&
        !vendaTemItensMigradosRetiradaParaCarreto(venda, itens: itens);
  }

  /// Mesma regra da tela Entregas / romaneio consolidado.
  static int quantidadeRomaneioCarga(
    Venda venda,
    ItemVenda item, {
    List<ItemVenda>? itens,
  }) {
    if (!itemEntraNaCargaEntrega(venda, item)) return 0;
    if (vendaTemItensMigradosRetiradaParaCarreto(venda, itens: itens)) {
      return item.quantidadeParaExibicaoEntrega(true);
    }
    if (vendaCarretoReservaNativaSemMigracao(venda, itens: itens)) {
      return item.quantidadeParaExibicaoEntrega(
        false,
        carretoReservaNativoAntesSaida: true,
      );
    }
    return item.quantidadeParaExibicaoEntrega(false);
  }

  /// Escopo persistido da conferencia (`g:grupo` ou `s:vendaId`).
  static String escopoConferenciaCargaRomaneio(List<Venda> vendas) {
    if (vendas.isEmpty) return '';
    if (vendas.length >= 2 && vendas.first.grupoEntregaFreteId > 0) {
      return 'g:${vendas.first.grupoEntregaFreteId}';
    }
    return 's:${vendas.first.id}';
  }

  /// Itens que entram na carga / tela Entregas (carreto ou migrado retirada futura).
  static bool itemEntraNaCargaEntrega(Venda venda, ItemVenda item) {
    if (itemMigradoRetiradaFuturaParaCarreto(item)) return true;
    return tipoEfetivoItem(item) == tipoEntregaLoja;
  }

  static String resumoContagem(Iterable<String> tiposItens) {
    var retirada = 0;
    var futura = 0;
    var carreto = 0;
    for (final t in tiposItens) {
      switch (normalizarTipoItem(t)) {
        case tipoEntregaLoja:
          carreto++;
          break;
        case tipoRetiradaFutura:
          futura++;
          break;
        default:
          retirada++;
      }
    }
    final partes = <String>[];
    if (retirada > 0) partes.add('$retirada leva agora');
    if (futura > 0) partes.add('$futura retirada futura');
    if (carreto > 0) partes.add('$carreto carreto');
    return partes.join(' · ');
  }
}
