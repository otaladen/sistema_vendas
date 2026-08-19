import 'package:flutter_test/flutter_test.dart';

import 'package:sistema_vendas/domain/uuid_v4.dart';

void main() {
  test('gerarUuidV4 produz formato UUID v4', () {
    final u = gerarUuidV4();
    expect(
      u,
      matches(
        RegExp(
          r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
        ),
      ),
    );
    expect(gerarUuidV4(), isNot(u));
  });
}
