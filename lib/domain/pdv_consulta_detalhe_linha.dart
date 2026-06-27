import '../model/produto.dart';

/// Texto da segunda linha (item selecionado) na consulta PDV.
abstract final class PdvConsultaDetalheLinhaUtil {
  PdvConsultaDetalheLinhaUtil._();

  static String montar(
    Produto produto, {
    int quantidadeNoOrcamento = 0,
  }) {
    final partes = <String>[];
    final sku = produto.codigoInterno.trim();
    if (sku.isNotEmpty) partes.add('SKU $sku');
    final ean = produto.codigoBarras.trim();
    if (ean.isNotEmpty) partes.add('EAN $ean');
    final marca = produto.marca.trim();
    if (marca.isNotEmpty) partes.add(marca);
    final loc = produto.localizacao.trim();
    if (loc.isNotEmpty) partes.add('Loc. $loc');
    if (produto.rotuloConversaoEmbalagem.isNotEmpty) {
      partes.add(produto.rotuloConversaoEmbalagem);
    }
    if (quantidadeNoOrcamento > 0) {
      partes.add('Orc. $quantidadeNoOrcamento');
    }
    return partes.join(' · ');
  }
}

/// Modo da lista quando a busca esta vazia.
enum PdvConsultaModoSugestao {
  misto,
  recentes,
  maisVendidos,
}
