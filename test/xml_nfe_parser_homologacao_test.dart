import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sistema_vendas/services/xml_nfe_parser_service.dart';

void main() {
  test('parse NF-e homologacao materiais construcao', () {
    final xml = File(
      'samples/nfe_entrada_homologacao_materiais_construcao.xml',
    ).readAsStringSync();
    final r = XmlParserService.parseNfeXmlString(xml);

    expect(r.chaveAcesso, '35260612345678000190550010000123451876543219');
    expect(r.numeroNota, 12345);
    expect(r.emitente.cnpj, '12345678000190');
    expect(r.emitente.razaoSocial, 'MATERIAIS BRASIL CONSTRUCAO LTDA');
    expect(r.itens.length, 2);

    final cimento = r.itens.first;
    expect(cimento.unidadeComercial, 'SC');
    expect(cimento.ncm, '25232910');
    expect(cimento.quantidadeComercial, 100);
    expect(cimento.codigoBarras, '7891033725025');

    final tubo = r.itens[1];
    expect(tubo.unidadeComercial, 'UN');
    expect(tubo.ncm, '39172300');
    expect(tubo.quantidadeComercial, 50);
    expect(tubo.codigoBarras, '7898068830508');

    expect(r.valorTotalNota, 4195.00);
    expect(r.duplicatas.length, 2);
    expect(r.duplicatas.first.valorParcela, closeTo(2097.50, 0.01));
  });
}
