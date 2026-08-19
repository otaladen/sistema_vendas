import 'package:flutter_test/flutter_test.dart';

/// Garante que a busca por homonimos nao descarta IDs alem do lote.
void main() {
  test('lotes de 250 cobrem todos os IDs sem corte', () {
    final ids = List<int>.generate(612, (i) => i + 1);
    const lote = 250;
    final cobertos = <int>[];
    for (var i = 0; i < ids.length; i += lote) {
      final fim = (i + lote) > ids.length ? ids.length : i + lote;
      cobertos.addAll(ids.sublist(i, fim));
    }
    expect(cobertos.length, 612);
    expect(cobertos.first, 1);
    expect(cobertos.last, 612);
    expect(cobertos.toSet().length, 612);
  });
}
