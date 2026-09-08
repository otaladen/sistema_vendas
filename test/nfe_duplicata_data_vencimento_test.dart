import 'package:flutter_test/flutter_test.dart';
import 'package:intl/intl.dart';
import 'package:sistema_vendas/model/item_nota_temporario.dart';

void main() {
  final nfData = DateFormat('dd/MM/yyyy');

  test('parseDataVencimento preserva dia civil YYYY-MM-DD', () {
    final dt = NfeDuplicataXml.parseDataVencimento('2026-09-28');
    expect(dt.year, 2026);
    expect(dt.month, 9);
    expect(dt.day, 28);
    expect(nfData.format(dt), '28/09/2026');
    expect(nfData.format(dt.toLocal()), '28/09/2026');
  });

  test('parseDataVencimento aceita prefixo ISO da API', () {
    final dt = NfeDuplicataXml.parseDataVencimento('2026-09-28T00:00:00.000Z');
    expect(nfData.format(dt), '28/09/2026');
  });

  test('parseDataVencimento aceita dd/MM/yyyy', () {
    final dt = NfeDuplicataXml.parseDataVencimento('28/09/2026');
    expect(nfData.format(dt), '28/09/2026');
  });
}
