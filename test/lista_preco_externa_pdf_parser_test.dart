import 'package:flutter_test/flutter_test.dart';
import 'package:sistema_vendas/domain/lista_preco_externa.dart';
import 'package:sistema_vendas/domain/lista_preco_externa_pdf_parser.dart';

void main() {
  test('parseia linhas Codigo Produto Preco e milhar', () {
    const texto = '''
21/08/2026 COMPROU LEVOU
Pagina 1 TABELA DE PRECOS
Codigo Produto Preco
002748 Abracad borboleta p/gas 13-19mm 3,90
003197 Abracad nylon  200x3,6 0,40
008276 Bac acp celite fit plus c/assento 1.100,00
000075 Brita 01 cacamba 10m3 1.150,00
''';
    final r = ListaPrecoExternaPdfParser.parseTexto(texto);
    expect(r.nomeLoja, 'Comprou Levou');
    expect(r.dataLista, DateTime(2026, 8, 21));
    expect(r.itens.length, 4);

    final abr = r.itens.firstWhere((e) => e.codigo == '002748');
    expect(abr.preco, closeTo(3.90, 0.001));
    expect(abr.nome, contains('Abracad'));

    final bac = r.itens.firstWhere((e) => e.codigo == '008276');
    expect(bac.preco, closeTo(1100.0, 0.001));

    final brita = r.itens.firstWhere((e) => e.codigo == '000075');
    expect(brita.preco, closeTo(1150.0, 0.001));
  });

  test('parseia blocos Syncfusion (codigo/nome/preco em linhas)', () {
    const texto = '''
21/08/2026
COMPROU LEVOU
Pagina 1
TABELA DE PRECOS
Codigo
Produto
Preco
002748
Abracad borboleta p/gas 13-19mm
3,90
008276
Bac acp celite fit plus c/assento
1.100,00
''';
    final r = ListaPrecoExternaPdfParser.parseTexto(texto);
    expect(r.itens.length, 2);
    expect(r.itens.firstWhere((e) => e.codigo == '002748').preco,
        closeTo(3.9, 0.001));
    expect(r.itens.firstWhere((e) => e.codigo == '008276').preco,
        closeTo(1100, 0.001));
  });

  test('busca por palavras no nome', () {
    const texto = '''
21/08/2026 COMPROU LEVOU
002748 Abracad borboleta p/gas 13-19mm 3,90
000082 Broca aco rapido 5/16 9mm 17,90
000034 Areia 165,00
''';
    final parse = ListaPrecoExternaPdfParser.parseTexto(texto);
    final lista = ListaPrecoExterna(
      id: 't',
      nomeLoja: parse.nomeLoja,
      dataLista: parse.dataLista,
      importadoEm: DateTime.now(),
      arquivoOrigem: 't.pdf',
      itens: parse.itens,
      linhasIgnoradas: parse.linhasIgnoradas,
    );
    final hits = lista.buscar('broca 5/16');
    expect(hits.length, 1);
    expect(hits.first.codigo, '000082');
  });
}
