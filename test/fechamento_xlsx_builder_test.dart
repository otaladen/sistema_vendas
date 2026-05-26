import 'package:flutter_test/flutter_test.dart';
import 'package:sistema_vendas/services/fechamento_xlsx_builder.dart';

void main() {
  test('gera bytes xlsx com duas abas', () {
    final bytes = FechamentoXlsxBuilder.build(
      sheet1Name: 'Saidas',
      sheet1Rows: [
        ['Coluna', 'Valor'],
        ['Total', '100.50'],
      ],
      sheet2Name: 'Entradas',
      sheet2Rows: [
        ['Fornecedor', 'CNPJ'],
        ['ACME', '12345678000199'],
      ],
    );
    expect(bytes.length, greaterThan(200));
    expect(bytes[0], 0x50); // PK zip header
    expect(bytes[1], 0x4B);
  });
}
