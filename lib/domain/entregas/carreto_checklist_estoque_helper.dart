import '../../model/item_venda.dart';
import '../../model/movimento_estoque.dart';
import '../../model/produto.dart';
import '../../model/venda.dart';
import '../entrega_venda_helper.dart';
import '../estoque/tipo_movimento_estoque.dart';
import '../venda_documento_rotulo_helper.dart';
import '../../services/gerenciador_estoque_service.dart';

/// Mensagens e kardex para falha ao marcar "Saiu" no checklist do carreto.
abstract final class CarretoChecklistEstoqueHelper {
  CarretoChecklistEstoqueHelper._();

  static bool ehErroAoMarcarSaiu(Object erro) {
    final msg = erro.toString();
    return msg.contains('Nao foi possivel marcar "Saiu"') ||
        msg.contains('Nao foi possivel baixar estoque do carreto');
  }

  static String tituloDialogoErroSaiu() => 'Nao foi possivel marcar "Saiu"';

  static String mensagemResumida(Object erro) {
    final bruto = erro.toString().replaceFirst('Bad state: ', '').trim();
    if (!ehErroAoMarcarSaiu(erro)) return bruto;
    return bruto;
  }

  static String orientacaoCorrecao() =>
      'Ao marcar "Saiu", o sistema baixa o estoque fisico e consome a reserva '
      'do carreto. Isso so funciona se a venda tiver reserva na finalizacao.\n\n'
      'O que fazer:\n'
      '1. Estoque → localize o produto → confira Fisico e Reservado.\n'
      '2. Estoque → Diagnostico → veja alertas de reserva de carreto.\n'
      '3. Revise o kardex abaixo (movimentos deste pedido).\n'
      '4. Se a reserva sumiu, ajuste o estoque com motivo documentado ou '
      'reprocesse a finalizacao com suporte.';

  /// Itens do pedido que ainda exigem estoque no romaneio.
  static List<({ItemVenda item, int quantidade, Produto? produto})>
      itensPendentesCarreto(Venda venda) {
    final lista = <({ItemVenda item, int quantidade, Produto? produto})>[];
    for (final item in venda.itens) {
      final q = GerenciadorEstoqueService.quantidadeItemParaEstoqueCarreto(item);
      if (q <= 0) continue;
      lista.add((item: item, quantidade: q, produto: item.produto.target));
    }
    return lista;
  }

  static List<String> resumirKardexPedido({
    required Venda venda,
    required List<MovimentoEstoque> Function(int produtoId) listarMovimentos,
    int limitePorProduto = 8,
  }) {
    final ref = VendaDocumentoRotuloHelper.rotuloControleInterno(venda);
    final linhas = <String>[];
    final vistos = <int>{};

    for (final par in itensPendentesCarreto(venda)) {
      final produto = par.produto;
      if (produto == null || produto.id <= 0) {
        linhas.add('${par.item.nomeProduto}: produto nao vinculado.');
        continue;
      }
      if (vistos.contains(produto.id)) continue;
      vistos.add(produto.id);

      linhas.add(
        '${produto.nome} — fisico ${produto.estoqueReal}, '
        'reservado ${produto.estoqueReservado} '
        '(pedido precisa ${par.quantidade})',
      );

      final movs = listarMovimentos(produto.id);
      final doPedido = movs
          .where((m) => _movimentoRelacionadoPedido(m, ref))
          .take(limitePorProduto)
          .toList();
      if (doPedido.isEmpty) {
        linhas.add('  Sem movimentos no kardex com referencia "$ref".');
        continue;
      }
      for (final m in doPedido) {
        linhas.add('  · ${_formatarMovimento(m)}');
      }
    }

    if (linhas.isEmpty) {
      linhas.add('Nenhum item de carreto pendente neste pedido.');
    }
    return linhas;
  }

  static bool _movimentoRelacionadoPedido(MovimentoEstoque m, String ref) {
    final doc = m.documentoReferencia.trim();
    if (doc.contains(ref)) return true;
    return false;
  }

  static String _formatarMovimento(MovimentoEstoque m) {
    final tipo = _rotuloTipo(m.tipoMovimento);
    final fis = m.deltaFisico == 0
        ? ''
        : ' fis ${m.deltaFisico > 0 ? '+' : ''}${m.deltaFisico}';
    final res = m.deltaReserva == 0
        ? ''
        : ' res ${m.deltaReserva > 0 ? '+' : ''}${m.deltaReserva}';
    final saldo =
        ' → fis ${m.saldoFisicoDepois}, res ${m.saldoReservaDepois}';
    final doc = m.documentoReferencia.trim();
    final ref = doc.isEmpty ? '' : ' ($doc)';
    return '$tipo$fis$res$saldo$ref';
  }

  static String _rotuloTipo(String nome) {
    for (final t in TipoMovimentoEstoque.values) {
      if (t.name == nome) {
        switch (t) {
          case TipoMovimentoEstoque.finalizacaoAjustaReserva:
            return 'Reserva na finalizacao';
          case TipoMovimentoEstoque.orcamentoReserva:
            return 'Reserva no orcamento';
          case TipoMovimentoEstoque.orcamentoLiberaReserva:
            return 'Liberou reserva';
          case TipoMovimentoEstoque.carretoSaida:
            return 'Saida carreto';
          case TipoMovimentoEstoque.carretoEstornoSaida:
            return 'Estorno saida carreto';
          case TipoMovimentoEstoque.retiradaParcialCliente:
            return 'Retirada na loja';
          case TipoMovimentoEstoque.ajusteManual:
            return 'Ajuste manual';
          case TipoMovimentoEstoque.cancelamentoVendaEstorno:
            return 'Cancelamento';
          default:
            return nome;
        }
      }
    }
    return nome.isEmpty ? 'movimento' : nome;
  }

  /// Usado pelo diagnostico de estoque: pedido aguarda saida mas reserva insuficiente.
  static List<String> problemasReservaCarretoPendente(Venda venda) {
    if (!venda.carretoReservaAteSaida ||
        venda.cargaSaiu ||
        venda.cancelada ||
        venda.status != 'finalizada' ||
        !EntregaVendaHelper.vendaTemItensCarreto(venda)) {
      return const [];
    }
    final falhas = <String>[];
    for (final par in itensPendentesCarreto(venda)) {
      final produto = par.produto;
      if (produto == null) {
        falhas.add('${par.item.nomeProduto}: produto nao vinculado.');
        continue;
      }
      if (produto.estoqueReservado < par.quantidade) {
        falhas.add(
          '${produto.nome}: reservado ${produto.estoqueReservado}, '
          'necessario ${par.quantidade} para despachar.',
        );
      }
      if (produto.estoqueReal < par.quantidade) {
        falhas.add(
          '${produto.nome}: fisico ${produto.estoqueReal}, '
          'necessario ${par.quantidade} para saida.',
        );
      }
    }
    return falhas;
  }
}
