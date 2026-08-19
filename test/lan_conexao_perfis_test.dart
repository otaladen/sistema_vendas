import 'package:flutter_test/flutter_test.dart';

import 'package:sistema_vendas/data/api/lan_api_url.dart';
import 'package:sistema_vendas/data/api/lan_conexao_perfis.dart';

void main() {
  test('fromSyncUrl adiciona :8788 quando porta omitida', () {
    expect(LanApiUrl.fromSyncUrl('192.168.0.10'), 'http://192.168.0.10:8788');
    expect(LanApiUrl.fromSyncUrl('100.64.1.2'), 'http://100.64.1.2:8788');
    expect(
      LanApiUrl.fromSyncUrl('http://192.168.0.10'),
      'http://192.168.0.10:8788',
    );
  });

  test('fromSyncUrl forca porta da API mesmo se outra for digitada', () {
    expect(
      LanApiUrl.fromSyncUrl('http://192.168.0.10:9000'),
      'http://192.168.0.10:8788',
    );
  });

  test('pareceTailscale detecta CGNAT 100.64/10', () {
    expect(LanConexaoPerfisStore.pareceTailscale('http://100.64.1.2:8788'), isTrue);
    expect(LanConexaoPerfisStore.pareceTailscale('100.100.0.5'), isTrue);
    expect(LanConexaoPerfisStore.pareceTailscale('192.168.0.10'), isFalse);
    expect(LanConexaoPerfisStore.pareceTailscale('10.0.0.2'), isFalse);
  });
}
