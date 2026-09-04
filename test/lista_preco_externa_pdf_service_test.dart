import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sistema_vendas/services/lista_preco_externa_pdf_service.dart';

void main() {
  test('importa PDF Comprou Levou de exemplo (tools/2108.pdf)', () {
    final file = File(r'c:\Projetos\sistema_vendas\tools\2108.pdf');
    if (!file.existsSync()) {
      return; // ambiente sem o PDF de exemplo
    }
    final parse = ListaPrecoExternaPdfService.importarBytes(
      file.readAsBytesSync(),
      arquivoOrigem: '2108.pdf',
    );
    expect(parse.itens.length, greaterThan(5000));
    expect(parse.nomeLoja, 'Comprou Levou');
    expect(parse.dataLista.year, 2026);
    expect(parse.dataLista.month, 8);
    expect(parse.dataLista.day, 21);
    final amostra = parse.itens.where((e) => e.codigo == '002748');
    expect(amostra, isNotEmpty);
    expect(amostra.first.preco, closeTo(3.90, 0.001));
  });
}
