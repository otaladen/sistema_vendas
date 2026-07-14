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

  static bool vendaTemItensCarreto(Venda venda) {
    if (venda.tipoEntrega == tipoEntregaLoja) return true;
    return venda.itens.any(
      (i) => normalizarTipoItem(i.tipoEntregaItem) == tipoEntregaLoja,
    );
  }

  static bool vendaTemItensRetiradaFutura(Venda venda) {
    if (venda.tipoEntrega == tipoRetiradaFutura && venda.entregaPendente) {
      return true;
    }
    return venda.itens.any(
      (i) => normalizarTipoItem(i.tipoEntregaItem) == tipoRetiradaFutura,
    );
  }

  /// Itens "leva agora" com quantidade ainda nao baixada no cupom interno.
  static bool vendaTemItensRetiradaImediataPendenteCupom(Venda venda) {
    return venda.itens.any(
      (i) =>
          tipoEfetivoItem(i) == tipoRetirada &&
          i.quantidade > 0 &&
          i.quantidadeJaRetirada < i.quantidade,
    );
  }

  /// Orcamentos antigos (tipo so no cabecalho): replica no item antes de finalizar.
  static void aplicarLegadoTipoUnicoNosItensSeNecessario(Venda venda) {
    if (venda.tipoEntrega == tipoMisto || venda.tipoEntrega == tipoRetirada) {
      return;
    }
    final todosPadraoRetirada = venda.itens.every(
      (i) => normalizarTipoItem(i.tipoEntregaItem) == tipoRetirada,
    );
    if (!todosPadraoRetirada) return;
    for (final item in venda.itens) {
      item.tipoEntregaItem = normalizarTipoItem(venda.tipoEntrega);
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
  static String textoEntregaCabecalhoVenda(Venda venda) {
    if (venda.tipoEntrega == tipoMisto) {
      final resumo = resumoContagem(venda.itens.map((i) => i.tipoEntregaItem));
      return resumo.isEmpty ? 'Venda mista' : 'Venda mista ($resumo)';
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
  static bool vendaTemItensMigradosRetiradaParaCarreto(Venda venda) {
    return venda.itens.any(itemMigradoRetiradaFuturaParaCarreto);
  }

  /// Cliente pode buscar na loja itens de carreto antes do romaneio sair.
  static bool vendaPermiteRetiradaLojaCarretoAntesSaida(Venda venda) {
    if (venda.cancelada || venda.status != 'finalizada') return false;
    if (!venda.carretoReservaAteSaida || venda.cargaSaiu) return false;
    return venda.itens.any((i) => i.quantidadeAindaNoCarretoAntesSaida > 0);
  }

  static bool vendaCarretoReservaNativaSemMigracao(Venda venda) {
    return venda.carretoReservaAteSaida &&
        vendaTemItensCarreto(venda) &&
        !vendaTemItensMigradosRetiradaParaCarreto(venda);
  }

  /// Mesma regra da tela Entregas / romaneio consolidado.
  static int quantidadeRomaneioCarga(Venda venda, ItemVenda item) {
    if (!itemEntraNaCargaEntrega(venda, item)) return 0;
    if (vendaTemItensMigradosRetiradaParaCarreto(venda)) {
      return item.quantidadeParaExibicaoEntrega(true);
    }
    if (vendaCarretoReservaNativaSemMigracao(venda)) {
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
