import '../../model/item_venda.dart';
import '../../model/produto.dart';
import '../../model/venda.dart';
import '../entrega_venda_helper.dart';
import '../produto_embalagem.dart';
import 'loja_origem_mercadoria.dart';

/// Opcao do dropdown "Buscar na nossa loja" (valor persistido + rotulo).
class OpcaoQuantidadeBuscarNaLoja {
  const OpcaoQuantidadeBuscarNaLoja({
    required this.armazenado,
    required this.rotulo,
  });

  final int armazenado;
  final String rotulo;
}

/// Motorista na outra loja pede para buscar o item nesta prateleira.
///
/// Nao misturar com complemento (falta na casa do cliente).
abstract final class BuscarNaLoja {
  BuscarNaLoja._();

  static const solicitar = 'solicitar';
  static const confirmar = 'confirmar';
  static const cancelar = 'cancelar';

  static const solicitado = 'solicitado';
  static const separado = 'separado';

  static bool ehSolicitado(String? status) =>
      (status ?? '').trim() == solicitado;

  static bool ehSeparado(String? status) => (status ?? '').trim() == separado;

  static bool temPendente(Venda venda, [Iterable<ItemVenda>? itens]) {
    for (final item in itens ?? _itens(venda)) {
      if (ehSolicitado(item.buscarNaLojaStatus)) return true;
    }
    return false;
  }

  static int contarPedidosPendentes(
    Iterable<Venda> vendas, [
    Iterable<ItemVenda> Function(Venda venda)? itensDe,
  ]) {
    var n = 0;
    for (final v in vendas) {
      if (temPendente(v, itensDe?.call(v))) n++;
    }
    return n;
  }

  static List<ItemVenda> pendentesDaVenda(
    Venda venda, [
    Iterable<ItemVenda>? itens,
  ]) {
    return [
      for (final item in itens ?? _itens(venda))
        if (ehSolicitado(item.buscarNaLojaStatus)) item,
    ];
  }

  static String? resumoPendentes(Venda venda, [Iterable<ItemVenda>? itens]) {
    final linhas = <String>[];
    for (final item in pendentesDaVenda(venda, itens)) {
      linhas.add('${rotuloQuantidade(venda, item)} ${item.nomeProduto}');
    }
    if (linhas.isEmpty) return null;
    return 'Buscar nesta loja: ${linhas.join('; ')}';
  }

  static bool podeSolicitarItem(Venda venda, ItemVenda item) {
    if (!_entregaAberta(venda)) return false;
    if (!EntregaVendaHelper.itemEntraNaCargaEntrega(venda, item)) return false;
    if (_qtd(venda, item) <= 0) return false;
    if (ehSeparado(item.buscarNaLojaStatus)) return false;
    final origem = LojaOrigemMercadoria.origemEfetiva(
      origemItem: item.lojaOrigemMercadoria,
      origemVenda: venda.lojaOrigemMercadoria,
      cargaSaiu: venda.cargaSaiu,
    );
    return !LojaOrigemMercadoria.ehLocal(origem);
  }

  static bool podeCancelarItem(Venda venda, ItemVenda item) {
    if (!_entregaAberta(venda)) return false;
    return ehSolicitado(item.buscarNaLojaStatus) ||
        ehSeparado(item.buscarNaLojaStatus);
  }

  static bool _entregaAberta(Venda venda) {
    if (venda.cancelada) return false;
    switch (venda.statusEntrega) {
      case 'entregue':
      case 'entregue_complemento_pendente':
      case 'cancelada':
        return false;
      default:
        return true;
    }
  }

  static int qtdCarga(Venda venda, ItemVenda item) => _qtd(venda, item);

  static int clampQuantidade(Venda venda, ItemVenda item, int quantidade) {
    final max = qtdCarga(venda, item);
    if (max <= 0) return 0;
    if (quantidade < 1) return 1;
    if (quantidade > max) return max;
    return quantidade;
  }

  static String rotuloQuantidade(
    Venda venda,
    ItemVenda item, {
    Produto? Function(int id)? obterProduto,
    int? quantidadeArmazenada,
  }) {
    final total = qtdCarga(venda, item);
    final q = quantidadeArmazenada != null
        ? clampQuantidade(venda, item, quantidadeArmazenada)
        : quantidadeEfetiva(venda, item);
    final produto = EntregaVendaHelper.produtoItemEntrega(
      item,
      obterProduto: obterProduto,
    );
    if (produto == null) {
      if (q >= total) return '${total}x';
      return '$q de $total';
    }
    final totalTxt = EntregaVendaHelper.textoQuantidadeRetiradaComUnidade(
      item,
      quantidadeArmazenada: total,
      obterProduto: obterProduto,
    );
    if (q >= total) return '${totalTxt}x';
    final qTxt = _textoQuantidadeExibicaoRelativa(
      venda,
      item,
      q,
      obterProduto: obterProduto,
    );
    return '$qTxt de $totalTxt';
  }

  /// Texto do corpo do modal do motorista.
  static String textoIntroducaoModal(
    Venda venda,
    ItemVenda item, {
    Produto? Function(int id)? obterProduto,
  }) {
    final totalArm = qtdCarga(venda, item);
    final totalTxt = EntregaVendaHelper.textoQuantidadeRetiradaComUnidade(
      item,
      quantidadeArmazenada: totalArm,
      obterProduto: obterProduto,
    );
    return 'A outra loja não tem a quantidade toda. '
        'De $totalTxt, quantos buscar nesta loja?';
  }

  /// Opcoes do dropdown (1..N unidades reais ou passo 0,5 em M²/M³/KG).
  static List<OpcaoQuantidadeBuscarNaLoja> opcoesQuantidadeModal(
    Venda venda,
    ItemVenda item, {
    Produto? Function(int id)? obterProduto,
  }) {
    final totalArm = qtdCarga(venda, item);
    if (totalArm <= 0) return const [];

    final totalExib = EntregaVendaHelper.quantidadeRomaneioCargaExibicao(
      venda,
      item,
      obterProduto: obterProduto,
    );
    if (totalExib <= 0) return const [];

    final produto = EntregaVendaHelper.produtoItemEntrega(
      item,
      obterProduto: obterProduto,
    );
    final passoFracionado = produto != null &&
        !_modalIncrementoInteiroUnidade(produto) &&
        EntregaVendaHelper.retiradaEntradaFracionada(
          item,
          quantidadeArmazenadaReferencia: totalArm,
          obterProduto: obterProduto,
        );

    final opcoes = <OpcaoQuantidadeBuscarNaLoja>[];

    if (!passoFracionado) {
      final max = totalExib.round();
      if (max <= 1) {
        return [
          OpcaoQuantidadeBuscarNaLoja(
            armazenado: totalArm,
            rotulo: _rotuloOpcaoModal(
              venda,
              item,
              armazenado: totalArm,
              obterProduto: obterProduto,
            ),
          ),
        ];
      }
      for (var n = 1; n <= max; n++) {
        final arm = armazenadoDeQuantidadeExibicao(
          venda,
          item,
          n.toDouble(),
          obterProduto: obterProduto,
        );
        if (arm <= 0 || opcoes.any((o) => o.armazenado == arm)) continue;
        opcoes.add(
          OpcaoQuantidadeBuscarNaLoja(
            armazenado: arm,
            rotulo: _rotuloOpcaoModal(
              venda,
              item,
              armazenado: arm,
              obterProduto: obterProduto,
            ),
          ),
        );
      }
      return opcoes;
    }

    const passoExib = 0.5;
    var qExib = passoExib;
    while (qExib < totalExib - 1e-9) {
      final arm = armazenadoDeQuantidadeExibicao(
        venda,
        item,
        qExib,
        obterProduto: obterProduto,
      );
      if (arm > 0 && !opcoes.any((o) => o.armazenado == arm)) {
        opcoes.add(
          OpcaoQuantidadeBuscarNaLoja(
            armazenado: arm,
            rotulo: _rotuloOpcaoModal(
              venda,
              item,
              armazenado: arm,
              obterProduto: obterProduto,
            ),
          ),
        );
      }
      qExib += passoExib;
    }
    if (!opcoes.any((o) => o.armazenado == totalArm)) {
      opcoes.add(
        OpcaoQuantidadeBuscarNaLoja(
          armazenado: totalArm,
          rotulo: _rotuloOpcaoModal(
            venda,
            item,
            armazenado: totalArm,
            obterProduto: obterProduto,
          ),
        ),
      );
    }
    return opcoes;
  }

  /// Valor inicial do dropdown (persistido, clampado a uma opcao valida).
  static int armazenadoInicialModal(
    Venda venda,
    ItemVenda item, {
    Produto? Function(int id)? obterProduto,
  }) {
    final opcoes = opcoesQuantidadeModal(
      venda,
      item,
      obterProduto: obterProduto,
    );
    if (opcoes.isEmpty) return 0;
    final desejado = item.quantidadeBuscarNaLoja > 0
        ? clampQuantidade(venda, item, item.quantidadeBuscarNaLoja)
        : opcoes.last.armazenado;
    for (final o in opcoes) {
      if (o.armazenado == desejado) return desejado;
    }
    return opcoes.last.armazenado;
  }

  /// Converte quantidade escolhida na UI (unidade real) para milésimos/inteiro.
  static int armazenadoDeQuantidadeExibicao(
    Venda venda,
    ItemVenda item,
    double quantidadeExibicao, {
    Produto? Function(int id)? obterProduto,
  }) {
    if (quantidadeExibicao <= 0) return 0;
    final totalArm = qtdCarga(venda, item);
    if (totalArm <= 0) return 0;
    final totalExib = EntregaVendaHelper.quantidadeRomaneioCargaExibicao(
      venda,
      item,
      obterProduto: obterProduto,
    );
    if (totalExib <= 0) return 0;
    if (quantidadeExibicao >= totalExib - 1e-9) {
      return totalArm;
    }
    final arm = (quantidadeExibicao / totalExib * totalArm).round();
    return clampQuantidade(venda, item, arm);
  }

  static String _rotuloOpcaoModal(
    Venda venda,
    ItemVenda item, {
    required int armazenado,
    Produto? Function(int id)? obterProduto,
  }) {
    final totalArm = qtdCarga(venda, item);
    final totalTxt = EntregaVendaHelper.textoQuantidadeRetiradaComUnidade(
      item,
      quantidadeArmazenada: totalArm,
      obterProduto: obterProduto,
    );
    if (armazenado >= totalArm) {
      return 'Todos ($totalTxt)';
    }
    final qTxt = _textoQuantidadeExibicaoRelativa(
      venda,
      item,
      armazenado,
      obterProduto: obterProduto,
    );
    return '$qTxt de $totalTxt';
  }

  /// UN/SC/PC etc.: passo 1 na unidade de venda; demais usam 0,5 quando fracionado.
  static bool _modalIncrementoInteiroUnidade(Produto produto) {
    switch (ProdutoEmbalagem.normalizarUnidade(produto.unidade)) {
      case 'UN':
      case 'SC':
      case 'PC':
      case 'PC1':
      case 'CX':
      case 'PCT':
      case 'RL':
        return true;
      default:
        return false;
    }
  }

  static String _textoQuantidadeExibicaoRelativa(
    Venda venda,
    ItemVenda item,
    int armazenado, {
    Produto? Function(int id)? obterProduto,
  }) {
    final totalArm = qtdCarga(venda, item);
    if (armazenado <= 0 || totalArm <= 0) return '0';
    if (armazenado >= totalArm) {
      return EntregaVendaHelper.textoQuantidadeRetiradaComUnidade(
        item,
        quantidadeArmazenada: totalArm,
        obterProduto: obterProduto,
      );
    }
    final totalExib = EntregaVendaHelper.quantidadeRomaneioCargaExibicao(
      venda,
      item,
      obterProduto: obterProduto,
    );
    final qExib = armazenado / totalArm * totalExib;
    final produto = EntregaVendaHelper.produtoItemEntrega(
      item,
      obterProduto: obterProduto,
    );
    if (produto == null) {
      return qExib.round().toString();
    }
    final qTxt = ProdutoEmbalagem.formatarQuantidadeUnidadeVenda(produto, qExib);
    final u = ProdutoEmbalagem.normalizarUnidade(produto.unidade);
    return u.isEmpty ? qTxt : '$qTxt $u';
  }

  static int quantidadeEfetiva(Venda venda, ItemVenda item) {
    final total = qtdCarga(venda, item);
    if (total <= 0) return 0;
    if (item.quantidadeBuscarNaLoja <= 0) return total;
    return item.quantidadeBuscarNaLoja.clamp(1, total);
  }

  /// Confirmar no patio: linha inteira = desta loja; recorte = misto.
  static String origemAposConfirmar(Venda venda, ItemVenda item) {
    final total = qtdCarga(venda, item);
    final q = quantidadeEfetiva(venda, item);
    if (total > 0 && q < total) return LojaOrigemMercadoria.misto;
    return LojaOrigemMercadoria.local;
  }

  static Map<int, int> parseQuantidades(dynamic raw) {
    if (raw is! Map) return {};
    final out = <int, int>{};
    raw.forEach((k, v) {
      final id = int.tryParse(k.toString()) ?? 0;
      if (id <= 0) return;
      final q = (v is num) ? v.toInt() : int.tryParse('$v') ?? 0;
      if (q > 0) out[id] = q;
    });
    return out;
  }

  static int _qtd(Venda venda, ItemVenda item) =>
      EntregaVendaHelper.quantidadeRomaneioCarga(venda, item);

  static Iterable<ItemVenda> _itens(Venda venda) {
    try {
      return venda.itens;
    } catch (_) {
      return const <ItemVenda>[];
    }
  }
}
