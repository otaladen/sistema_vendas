import 'package:flutter_test/flutter_test.dart';
import 'package:sistema_vendas/config/fiscal_config.dart';
import 'package:sistema_vendas/services/fiscal_config_store.dart';

void main() {
  test('FiscalConfigDados.fromConstantes herda padroes', () {
    final d = FiscalConfigDados.fromConstantes();
    expect(d.cnpjEmitente, FiscalConfig.cnpjEmitente);
    expect(d.ambiente, FiscalConfig.ambiente);
  });

  test('homologacao quando ambiente nao e producao', () {
    const d = FiscalConfigDados(
      apiBaseUrl: 'https://homologacao.focusnfe.com.br',
      apiToken: 'abc123456789',
      cnpjEmitente: '32662298000191',
      inscricaoEstadualEmitente: '025232204',
      regimeTributarioEmitente: 3,
      ufEmitente: 'BA',
      ambiente: 'homologacao',
    );
    expect(d.homologacao, isTrue);
    expect(d.configurado, isTrue);
  });
}
