import '../model/cliente.dart';
import '../model/item_venda.dart';
import '../model/produto.dart';
import '../model/venda.dart';
import 'produto_embalagem.dart';
import 'quantidade_venda_util.dart';

/// Linha do bloco de entrega impresso; [destaque] = negrito (bairro, referencia, obs).
class LinhaEntregaImpressao {
  const LinhaEntregaImpressao(this.texto, {this.destaque = false});

  final String texto;
  final bool destaque;
}

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

  /// Retirada formal de patio em futura/carreto — impede cancelamento simples.
  ///
  /// Em "leva agora", [ItemVenda.quantidadeJaRetirada] e preenchido na baixa do
  /// cupom/finalizacao; isso **nao** bloqueia cancelar NFC-e/venda (ha estorno).
  static bool vendaTemRetiradaPatioQueBloqueiaCancelamento(
    Venda venda, {
    List<ItemVenda>? itens,
  }) {
    try {
      final lista = itens ?? List<ItemVenda>.from(venda.itens);
      for (final i in lista) {
        if (i.quantidadeJaRetirada <= 0) continue;
        final tipo = tipoEfetivoItem(i);
        if (tipo == tipoRetiradaFutura || tipo == tipoEntregaLoja) {
          return true;
        }
      }
    } catch (_) {}
    return false;
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
  ///
  /// Retorna o valor **persistido** (pode estar em milésimos se o produto for
  /// fracionado). Para UI/valor monetario use [quantidadeRomaneioCargaExibicao]
  /// e [textoQuantidadeRomaneioCarga].
  static int quantidadeRomaneioCarga(
    Venda venda,
    ItemVenda item, {
    List<ItemVenda>? itens,
  }) {
    if (!itemEntraNaCargaEntrega(venda, item)) return 0;
    if (vendaTemItensMigradosRetiradaParaCarreto(venda, itens: itens)) {
      return item.quantidadeParaExibicaoEntrega(true);
    }
    return item.quantidadeParaExibicaoEntrega(false);
  }

  /// Produto da linha (ToOne ou [obterProduto] no terminal leve / motorista).
  static Produto? produtoItemEntrega(
    ItemVenda item, {
    Produto? Function(int id)? obterProduto,
  }) {
    final vinculado = item.produtoOuNull;
    if (vinculado != null) return vinculado;
    if (obterProduto == null) return null;
    try {
      final id = item.produto.targetId;
      if (id > 0) return obterProduto(id);
    } catch (_) {}
    return null;
  }

  /// Itens que o motorista deve carregar/entregar (carreto liquido > 0).
  static List<ItemVenda> itensCargaMotorista(
    Venda venda,
    Iterable<ItemVenda> itens,
  ) {
    final lista = itens.toList();
    return [
      for (final item in lista)
        if (itemEntraNaCargaEntrega(venda, item) &&
            quantidadeRomaneioCarga(venda, item, itens: lista) > 0)
          item,
    ];
  }

  /// Quantidade romaneio com unidade de venda (regra unica Entregas + motorista).
  ///
  /// Ex.: `30 UN`, `18,9 M2`. Use [obterProduto] no terminal leve quando o ToOne
  /// do item vier vazio.
  static String textoQuantidadeRomaneioComUnidade(
    Venda venda,
    ItemVenda item, {
    List<ItemVenda>? itens,
    Produto? Function(int id)? obterProduto,
  }) {
    final raw = quantidadeRomaneioCarga(venda, item, itens: itens);
    if (raw <= 0) return '0';
    return ProdutoEmbalagem.formatarQuantidadeItemImpressaoComUnidade(
      produto: produtoItemEntrega(item, obterProduto: obterProduto),
      quantidadeArmazenada: raw,
      emMilesimos: item.quantidadeEmMilesimosPersistida,
    );
  }

  /// Alias historico (modo motorista).
  static String textoQuantidadeCargaMotoristaComUnidade(
    Venda venda,
    ItemVenda item, {
    List<ItemVenda>? itens,
    Produto? Function(int id)? obterProduto,
  }) =>
      textoQuantidadeRomaneioComUnidade(
        venda,
        item,
        itens: itens,
        obterProduto: obterProduto,
      );

  /// Linha padrao de item na carga: `30 UN — Trelica H8`.
  static String textoLinhaItemRomaneioCarga(
    Venda venda,
    ItemVenda item, {
    List<ItemVenda>? itens,
    Produto? Function(int id)? obterProduto,
  }) {
    final q = textoQuantidadeRomaneioComUnidade(
      venda,
      item,
      itens: itens,
      obterProduto: obterProduto,
    );
    return '$q — ${item.nomeProduto.trim()}';
  }

  /// Quantidade do romaneio na unidade de venda (2; 18,9; 0,5) — nao milésimos.
  static double quantidadeRomaneioCargaExibicao(
    Venda venda,
    ItemVenda item, {
    List<ItemVenda>? itens,
    Produto? Function(int id)? obterProduto,
  }) {
    final raw = quantidadeRomaneioCarga(venda, item, itens: itens);
    if (raw <= 0) return 0;
    return ProdutoEmbalagem.quantidadeVendaEfetivaItem(
      produto: produtoItemEntrega(item, obterProduto: obterProduto),
      quantidadeArmazenada: raw,
      emMilesimos: item.quantidadeEmMilesimosPersistida,
    );
  }

  /// Texto da quantidade para Entregas / romaneio (com unidade quando possivel).
  static String textoQuantidadeRomaneioCarga(
    Venda venda,
    ItemVenda item, {
    List<ItemVenda>? itens,
    Produto? Function(int id)? obterProduto,
  }) =>
      textoQuantidadeRomaneioComUnidade(
        venda,
        item,
        itens: itens,
        obterProduto: obterProduto,
      );

  /// Subtotal da linha na carga (qtd de exibicao × preco unitario).
  static double subtotalRomaneioCarga(
    Venda venda,
    ItemVenda item, {
    List<ItemVenda>? itens,
    Produto? Function(int id)? obterProduto,
  }) {
    return quantidadeRomaneioCargaExibicao(
          venda,
          item,
          itens: itens,
          obterProduto: obterProduto,
        ) *
        item.precoUnitario;
  }

  /// True se [quantidadeArmazenada] desta linha usa escala milésimos.
  static bool quantidadeRomaneioUsaEscalaFracionada(
    ItemVenda item, {
    Produto? Function(int id)? obterProduto,
    int? quantidadeArmazenada,
  }) {
    if (item.quantidadeEmMilesimosPersistida == true) return true;
    final p = produtoItemEntrega(item, obterProduto: obterProduto);
    if (p == null) return false;
    final raw = quantidadeArmazenada ?? item.quantidade;
    if (raw <= 0) return false;
    return ProdutoEmbalagem.leituraUsaEscalaFracionada(p, raw) ||
        ProdutoEmbalagem.estoqueUsaEscalaFracionada(p);
  }

  /// Saldo pendente / quantidade retirada com unidade (modal Registrar retirada).
  static String textoQuantidadeRetiradaComUnidade(
    ItemVenda item, {
    required int quantidadeArmazenada,
    Produto? Function(int id)? obterProduto,
  }) {
    return ProdutoEmbalagem.formatarQuantidadeItemImpressaoComUnidade(
      produto: produtoItemEntrega(item, obterProduto: obterProduto),
      quantidadeArmazenada: quantidadeArmazenada,
      emMilesimos: item.quantidadeEmMilesimosPersistida,
    );
  }

  /// Valor sugerido no campo Qtd (unidade de venda, ex.: `10,72`).
  static String textoEntradaQuantidadeRetirada(
    ItemVenda item, {
    required int quantidadeArmazenada,
    Produto? Function(int id)? obterProduto,
  }) {
    return ProdutoEmbalagem.formatarQuantidadeItemImpressao(
      produto: produtoItemEntrega(item, obterProduto: obterProduto),
      quantidadeArmazenada: quantidadeArmazenada,
      emMilesimos: item.quantidadeEmMilesimosPersistida,
    );
  }

  /// Campo Qtd aceita decimais quando o saldo usa milésimos (M², etc.).
  static bool retiradaEntradaFracionada(
    ItemVenda item, {
    required int quantidadeArmazenadaReferencia,
    Produto? Function(int id)? obterProduto,
  }) {
    if (item.quantidadeEmMilesimosPersistida == true) return true;
    final p = produtoItemEntrega(item, obterProduto: obterProduto);
    if (p == null) return false;
    if (ProdutoEmbalagem.leituraUsaEscalaFracionada(
      p,
      quantidadeArmazenadaReferencia,
    )) {
      return true;
    }
    return ProdutoEmbalagem.estoqueUsaEscalaFracionada(p);
  }

  /// Converte texto do campo Qtd para valor persistido ([ItemVenda.quantidade]).
  /// Retorna `null` se vazio, invalido ou acima de [pendenteArmazenado].
  static int? parseQuantidadeRetiradaEntrada(
    ItemVenda item, {
    required String texto,
    required int pendenteArmazenado,
    Produto? Function(int id)? obterProduto,
  }) {
    final t = texto.trim();
    if (t.isEmpty) return null;
    if (pendenteArmazenado <= 0) return null;

    final p = produtoItemEntrega(item, obterProduto: obterProduto);
    if (p == null) {
      final q = int.tryParse(t);
      if (q == null || q <= 0 || q > pendenteArmazenado) return null;
      return q;
    }

    final fracionada = retiradaEntradaFracionada(
      item,
      quantidadeArmazenadaReferencia: pendenteArmazenado,
      obterProduto: obterProduto,
    );
    final v = QuantidadeVendaUtil.parseEntradaPdv(t, fracionada: fracionada);
    if (v == null || v <= 0) return null;

    final armazenado = fracionada
        ? QuantidadeVendaUtil.paraArmazenamento(v, fracionada: true)
        : v.round();
    if (armazenado <= 0 || armazenado > pendenteArmazenado) return null;
    return armazenado;
  }

  /// Formata soma persistida do romaneio consolidado para exibicao.
  static String formatarQuantidadeRomaneioConsolidada(
    int quantidadeArmazenadaTotal, {
    required bool escalaFracionada,
  }) {
    if (quantidadeArmazenadaTotal <= 0) return '0';
    final q = QuantidadeVendaUtil.valorExibicao(
      quantidadeArmazenadaTotal,
      fracionada: escalaFracionada,
    );
    return QuantidadeVendaUtil.formatarExibicao(
      q,
      fracionada: escalaFracionada,
    );
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

  static const String rotuloBlocoEntregaImpressao =
      'DADOS PARA ENTREGA / CARRETO';

  static const String tituloBlocoEntregaImpressao =
      '--- $rotuloBlocoEntregaImpressao ---';

  static final RegExp _carimboDataLog = RegExp(r'\[\d{2}/\d{2}/\d{4}[^\]]*\]');

  static final List<RegExp> _linhasLogInterno = [
    RegExp(r'^[A-Z]+(?:_[A-Z]+)+\b'),
    RegExp(r'^Quem retirou\s*:', caseSensitive: false),
    RegExp(r'^Retirada\s*\([^)]*\)\s*:', caseSensitive: false),
    RegExp(r'^Retirada \S+ em .+\.$', caseSensitive: false),
    RegExp(r'^Patio (separou|vai separar)\b', caseSensitive: false),
  ];

  /// Linhas de [Venda.observacaoEntrega] digitadas na venda, sem o historico
  /// que o patio/entregas anexa ao mesmo campo (`[dd/MM/yyyy HH:mm] STATUS
  /// por ...`). O campo gravado nao muda: telas internas ainda leem o log.
  static List<String> observacaoEntregaParaCliente(String observacao) {
    final out = <String>[];
    for (final raw in observacao.split('\n')) {
      var t = raw.trim();
      final carimbo = _carimboDataLog.firstMatch(t);
      if (carimbo != null) t = t.substring(0, carimbo.start).trim();
      if (t.isEmpty) continue;
      if (_linhasLogInterno.any((re) => re.hasMatch(t))) continue;
      out.add(t);
    }
    return out;
  }

  /// Telefone BR para comprovantes: `(71) 98225-0887` / `(71) 3222-1234`.
  static String formatarTelefoneImpressao(String telefone) {
    final bruto = telefone.trim();
    var d = bruto.replaceAll(RegExp(r'\D'), '');
    if (d.startsWith('55') && (d.length == 12 || d.length == 13)) {
      d = d.substring(2);
    }
    if (d.startsWith('0') && (d.length == 11 || d.length == 12)) {
      d = d.substring(1);
    }
    switch (d.length) {
      case 11:
        return '(${d.substring(0, 2)}) ${d.substring(2, 7)}-${d.substring(7)}';
      case 10:
        return '(${d.substring(0, 2)}) ${d.substring(2, 6)}-${d.substring(6)}';
      case 9:
        return '${d.substring(0, 5)}-${d.substring(5)}';
      case 8:
        return '${d.substring(0, 4)}-${d.substring(4)}';
      default:
        return bruto;
    }
  }

  /// Aliases legados do cabecalho (`carreto`, `entrega`, etc.).
  static bool tipoEntregaEhCarreto(String? tipo) {
    switch (tipo?.trim().toLowerCase()) {
      case tipoEntregaLoja:
      case 'carreto':
      case 'entrega':
      case 'a_entregar':
      case 'a entregar':
        return true;
      default:
        return false;
    }
  }

  /// Bloco de endereco/contato so quando ha carreto com entrega definida.
  /// Orcamentos em cotacao (frete estimado sem endereco) nao imprimem este bloco.
  static bool vendaDeveImprimirBlocoEntrega(
    Venda venda, {
    List<ItemVenda>? itens,
  }) {
    if (statusEntregaEhCotacao(venda.statusEntrega)) return false;
    if (vendaTemItensCarreto(venda, itens: itens)) return true;
    return tipoEntregaEhCarreto(venda.tipoEntrega);
  }

  /// Linhas de corpo do bloco (nome, telefone, endereco, obs.).
  static List<String> linhasBlocoEntregaImpressao({
    required Venda venda,
    Cliente? cliente,
    List<ItemVenda>? itens,
  }) =>
      linhasBlocoEntregaImpressaoDetalhadas(
        venda: venda,
        cliente: cliente,
        itens: itens,
      ).map((l) => l.texto).toList();

  /// Igual a [linhasBlocoEntregaImpressao], com bairro e referencia/obs
  /// marcados para impressao em destaque.
  static List<LinhaEntregaImpressao> linhasBlocoEntregaImpressaoDetalhadas({
    required Venda venda,
    Cliente? cliente,
    List<ItemVenda>? itens,
  }) {
    if (!vendaDeveImprimirBlocoEntrega(venda, itens: itens)) {
      return const [];
    }

    final obsCliente = observacaoEntregaParaCliente(venda.observacaoEntrega);
    final linhas = <LinhaEntregaImpressao>[];
    final nome = cliente?.nomeRazao.trim() ?? '';
    if (nome.isNotEmpty) {
      linhas.add(LinhaEntregaImpressao('Nome: $nome'));
    }

    final tel = cliente?.telefone.trim() ?? '';
    if (tel.isNotEmpty) {
      linhas.add(
        LinhaEntregaImpressao(
          'Telefone/WhatsApp: ${formatarTelefoneImpressao(tel)}',
        ),
      );
    }

    final enderecoGravado = venda.enderecoEntrega.trim();
    if (enderecoGravado.isNotEmpty) {
      linhas.addAll(_linhasEnderecoGravado(enderecoGravado));
    } else {
      final padrao = cliente?.enderecoPadraoEntrega();
      if (padrao != null) {
        final ruaNumero = [
          padrao.endereco.trim(),
          padrao.numero.trim(),
        ].where((p) => p.isNotEmpty).join(', ');
        if (ruaNumero.isNotEmpty) {
          linhas.add(LinhaEntregaImpressao('Endereco: $ruaNumero'));
        }
        if (padrao.bairro.trim().isNotEmpty) {
          linhas.add(
            LinhaEntregaImpressao(
              'BAIRRO: ${padrao.bairro.trim().toUpperCase()}',
              destaque: true,
            ),
          );
        }
        final cidadeUf = [
          padrao.cidade.trim(),
          padrao.uf.trim(),
        ].where((p) => p.isNotEmpty).join(' - ');
        if (cidadeUf.isNotEmpty) {
          linhas.add(LinhaEntregaImpressao('Cidade: $cidadeUf'));
        }
        final refCliente = padrao.referencia.trim();
        if (refCliente.isNotEmpty &&
            !obsCliente.any((l) => l.contains(refCliente))) {
          linhas.add(
            LinhaEntregaImpressao('REFERENCIA: $refCliente', destaque: true),
          );
        }
      }
    }

    for (final t in obsCliente) {
      linhas.add(
        LinhaEntregaImpressao(
          t.toLowerCase().startsWith('obs') ? t : 'OBS/REFERENCIA: $t',
          destaque: true,
        ),
      );
    }

    if (linhas.isEmpty) {
      linhas.add(
        LinhaEntregaImpressao(
          'Modalidade: ${rotuloTipoEntregaVenda(venda.tipoEntrega)}',
        ),
      );
    }

    return linhas;
  }

  /// Endereco gravado no formato de [EnderecoCliente.resumo]
  /// (`Rua, n | Bairro | Cidade - UF | CEP: ...`); texto livre fica em uma linha.
  static List<LinhaEntregaImpressao> _linhasEnderecoGravado(String endereco) {
    final partes = endereco
        .split('|')
        .map((p) => p.trim())
        .where((p) => p.isNotEmpty)
        .toList();
    final bairroProvavel = partes.length >= 3 &&
        !partes[1].toUpperCase().startsWith('CEP');
    if (!bairroProvavel) {
      return [LinhaEntregaImpressao('Endereco: $endereco')];
    }
    return [
      LinhaEntregaImpressao('Endereco: ${partes[0]}'),
      LinhaEntregaImpressao(
        'BAIRRO: ${partes[1].toUpperCase()}',
        destaque: true,
      ),
      LinhaEntregaImpressao('Cidade: ${partes.sublist(2).join(' | ')}'),
    ];
  }

  /// Divisorias + titulo + corpo (estimativa para altura do PDF).
  static int contarLinhasBlocoEntregaImpressao({
    required Venda venda,
    Cliente? cliente,
    List<ItemVenda>? itens,
  }) {
    final corpo = linhasBlocoEntregaImpressao(
      venda: venda,
      cliente: cliente,
      itens: itens,
    );
    if (corpo.isEmpty) return 0;
    return 3 + corpo.length;
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

  static bool statusEntregaEhCotacao(String status) =>
      status.trim().toLowerCase() == 'cotacao';

  /// Carreto sem endereco — bloqueia finalizacao no caixa (cotacao ou incompleto).
  static bool orcamentoCarretoSemEnderecoParaFinalizar(
    Venda venda, {
    List<ItemVenda>? itens,
  }) {
    if (!vendaTemItensCarreto(venda, itens: itens)) return false;
    return venda.enderecoEntrega.trim().isEmpty;
  }

  static String mensagemBloqueioFinalizacaoCarretoCotacao(Venda venda) {
    if (statusEntregaEhCotacao(venda.statusEntrega)) {
      return 'Este orcamento foi salvo como cotacao (frete estimado sem endereco). '
          'Abra no PDV, selecione o cliente e informe o endereco de entrega '
          'antes de finalizar no caixa.';
    }
    return 'Orcamento com carreto exige endereco de entrega. '
        'Edite no PDV antes de finalizar.';
  }
}
