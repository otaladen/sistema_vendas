import 'package:flutter_test/flutter_test.dart';
import 'package:sistema_vendas/data/nfe_saida_fiscal_store.dart';
import 'package:sistema_vendas/domain/fiscal/nfe_historico_csv_export.dart';

void main() {
  test('CSV contem cabecalho e linha', () {
    final csv = NfeHistoricoCsvExport.gerar([
      NfeSaidaFiscalRegistro(
        id: '1',
        vendaId: 5,
        numeroOrcamento: 50,
        clienteNome: 'Construtora; LTDA',
        referenciaFocus: 'venda_5_nfe',
        statusFocus: 'autorizado',
        emitidaEm: DateTime(2026, 5, 10, 14, 30),
        statusSefaz: '100',
        numero: '123',
        chaveNfe: '29260512345678901234567890123456789012345678',
        valorTotal: 1500.5,
      ),
    ]);
    expect(csv.startsWith('Data;Status;Venda'), isTrue);
    expect(csv, contains('Construtora'));
    expect(csv, contains('123'));
  });
}
