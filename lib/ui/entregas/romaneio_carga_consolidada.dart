import '../../domain/entregas/romaneio_carga_merge.dart';
import '../../domain/entrega_venda_helper.dart';
import '../../model/item_venda.dart';
import '../../model/produto.dart';
import '../../model/venda.dart';

/// Linha da carga total consolidada de um grupo (mesmo carro) no romaneio.
typedef RomaneioCargaConsolidadaLinha = RomaneioCargaLinha;

/// Percorre [vendasGrupo], soma quantidades por produto (regra unica de dominio).
List<RomaneioCargaConsolidadaLinha> romaneioMergeCargaGrupo(
  List<Venda> vendasGrupo,
  int Function(Venda venda, ItemVenda item) quantidadeEntrega, {
  Produto? Function(int id)? obterProduto,
}) {
  return RomaneioCargaMerge.montarLinhas(
    vendasGrupo,
    obterProduto: obterProduto,
  );
}

/// Explicacao quando [romaneioMergeCargaGrupo] retorna vazio mas o pedido esta na fila.
class MensagemCargaConsolidadaVazia {
  const MensagemCargaConsolidadaVazia({
    required this.titulo,
    required this.paragrafos,
    this.dicas = const [],
  });

  final String titulo;
  final List<String> paragrafos;
  final List<String> dicas;
}

MensagemCargaConsolidadaVazia explicarCargaConsolidadaSemItens(
  List<Venda> vendasGrupo,
  int Function(Venda venda, ItemVenda item) quantidadeEntrega,
) {
  final nums = vendasGrupo
      .map((v) => v.numeroOrcamento)
      .where((n) => n > 0)
      .toList();
  final rotuloPedidos = nums.isEmpty
      ? '${vendasGrupo.length} pedido(s)'
      : nums.length == 1
          ? 'Pedido ${nums.first}'
          : 'Pedidos ${nums.join(', ')}';

  var itensCarreto = 0;
  var itensComQtd = 0;
  var migrado = false;
  var linhasRetiradaLojaZeradas = 0;
  var linhasTotalmenteRetiradas = 0;

  for (final v in vendasGrupo) {
    if (EntregaVendaHelper.vendaTemItensMigradosRetiradaParaCarreto(
      v,
      itens: RomaneioCargaMerge.itensDaVendaSafe(v),
    )) {
      migrado = true;
    }
    for (final item in RomaneioCargaMerge.itensDaVendaSafe(v)) {
      if (!EntregaVendaHelper.itemEntraNaCargaEntrega(v, item)) continue;
      itensCarreto++;
      final q = quantidadeEntrega(v, item);
      if (q > 0) itensComQtd++;
      if (item.quantidade > 0 &&
          item.quantidadeJaRetirada >= item.quantidade) {
        linhasTotalmenteRetiradas++;
      }
      if (v.carretoReservaAteSaida &&
          !v.cargaSaiu &&
          item.quantidadeAindaNoCarretoAntesSaida <= 0 &&
          q <= 0) {
        linhasRetiradaLojaZeradas++;
      }
    }
  }

  if (itensCarreto == 0) {
    return MensagemCargaConsolidadaVazia(
      titulo: 'Nada para separar no patio',
      paragrafos: [
        '$rotuloPedidos aparece nas Entregas, mas nao ha linha de produto '
        'com entrega loja (carreto) para montar carga.',
        'Pode ser apenas frete/endereco ou itens so de retirada na loja.',
      ],
      dicas: const [
        'Confira no PDV o tipo de entrega de cada item.',
        'Rota, motorista e status de entrega continuam disponiveis.',
      ],
    );
  }

  if (migrado && itensComQtd == 0) {
    return MensagemCargaConsolidadaVazia(
      titulo: 'Retirada futura — sem saldo no carreto',
      paragrafos: [
        '$rotuloPedidos veio de retirada futura migrada para carreto.',
        'A quantidade pendente no caminhao ($itensCarreto item(ns) de carreto) '
        'esta zerada: cliente ja retirou ou o saldo foi consumido.',
      ],
      dicas: const [
        'Abra Itens do pedido para ver quantidade no carreto e ja retirada.',
        'Checklist de carga pode ser usado mesmo sem lista de separacao.',
      ],
    );
  }

  if (linhasRetiradaLojaZeradas > 0 &&
      linhasRetiradaLojaZeradas >= itensCarreto - itensComQtd) {
    return MensagemCargaConsolidadaVazia(
      titulo: 'Cliente ja retirou na loja',
      paragrafos: [
        '$rotuloPedidos: a mercadoria de carreto ja foi registrada como '
        'retirada na loja antes da saida do caminhao.',
        'Por isso nao ha quantidade para separar no patio agora.',
      ],
      dicas: const [
        'Use o atalho de retirada na loja / historico se precisar conferir.',
      ],
    );
  }

  if (linhasTotalmenteRetiradas > 0 && itensComQtd == 0) {
    return MensagemCargaConsolidadaVazia(
      titulo: 'Itens ja baixados / retirados',
      paragrafos: [
        '$rotuloPedidos: os itens de carreto constam no pedido, mas a '
        'quantidade disponivel para esta viagem esta zerada (retirada ou devolucao).',
      ],
      dicas: const [
        'Veja Itens do pedido e devolucoes registradas.',
      ],
    );
  }

  return MensagemCargaConsolidadaVazia(
    titulo: 'Sem quantidade para separar agora',
    paragrafos: [
      '$rotuloPedidos: ha $itensCarreto item(ns) de carreto, porem nenhum com '
      'quantidade > 0 para somar na carga consolidada.',
    ],
    dicas: const [
      'Abra Itens do pedido para conferir cada linha.',
      'Mapa da rota e romaneio do endereco ainda podem ser usados.',
    ],
  );
}
