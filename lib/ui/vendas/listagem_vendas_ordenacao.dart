import '../../domain/venda_documento_rotulo_helper.dart';
import '../../domain/venda_finalizacao_caixa_helper.dart';
import 'listagem_venda_item_ui.dart';

enum ListagemVendasColuna {
  controle,
  documento,
  status,
  data,
  cliente,
  vendedor,
  pagamento,
  entrega,
  total,
}

extension ListagemVendasColunaRotulo on ListagemVendasColuna {
  String get rotulo => switch (this) {
        ListagemVendasColuna.controle => 'Controle',
        ListagemVendasColuna.documento => 'Documento',
        ListagemVendasColuna.status => 'Status',
        ListagemVendasColuna.data => 'Data',
        ListagemVendasColuna.cliente => 'Cliente',
        ListagemVendasColuna.vendedor => 'Vendedor',
        ListagemVendasColuna.pagamento => 'Pagamento',
        ListagemVendasColuna.entrega => 'Entrega',
        ListagemVendasColuna.total => 'Total',
      };
}

List<ListagemVendaItemUi> ordenarItensListagemVendas(
  List<ListagemVendaItemUi> itens, {
  required ListagemVendasColuna coluna,
  required bool ascendente,
}) {
  final copia = [...itens];
  final fator = ascendente ? 1 : -1;

  int cmpStr(String a, String b) => a.toLowerCase().compareTo(b.toLowerCase());
  int cmpNum(num a, num b) => a.compareTo(b);

  int numeroControle(ListagemVendaItemUi item) {
    final n = VendaDocumentoRotuloHelper.numeroControleInterno(item.venda);
    return n > 0 ? n : item.venda.id;
  }

  copia.sort((a, b) {
    final r = switch (coluna) {
      ListagemVendasColuna.controle =>
        cmpNum(numeroControle(a), numeroControle(b)),
      ListagemVendasColuna.documento => cmpStr(a.titulo, b.titulo),
      ListagemVendasColuna.status => cmpStr(a.status, b.status),
      ListagemVendasColuna.data =>
        VendaFinalizacaoCaixaHelper.momentoFinalizacao(a.venda).compareTo(
          VendaFinalizacaoCaixaHelper.momentoFinalizacao(b.venda),
        ),
      ListagemVendasColuna.cliente => cmpStr(a.cliente, b.cliente),
      ListagemVendasColuna.vendedor => cmpStr(a.vendedor, b.vendedor),
      ListagemVendasColuna.pagamento => cmpStr(a.pagamento, b.pagamento),
      ListagemVendasColuna.entrega => cmpStr(a.entrega, b.entrega),
      ListagemVendasColuna.total => cmpNum(a.venda.total, b.venda.total),
    };
    return fator * r;
  });
  return copia;
}

bool colunaOrdenacaoPadraoAscendente(ListagemVendasColuna coluna) {
  return switch (coluna) {
    ListagemVendasColuna.documento ||
    ListagemVendasColuna.status ||
    ListagemVendasColuna.cliente ||
    ListagemVendasColuna.vendedor ||
    ListagemVendasColuna.pagamento ||
    ListagemVendasColuna.entrega =>
      true,
    _ => false,
  };
}
