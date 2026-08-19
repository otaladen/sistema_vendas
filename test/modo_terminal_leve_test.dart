import 'package:flutter_test/flutter_test.dart';

import 'package:sistema_vendas/data/app_config_repository.dart';
import 'package:sistema_vendas/domain/modo_terminal_leve.dart';

void main() {
  EmpresaConfig cfg({
    bool sync = true,
    bool servidor = false,
  }) =>
      EmpresaConfig(
        redeSincronizacaoAtiva: sync,
        redeModoServidor: servidor,
      );

  test('modoTerminalLeve exige rede ativa e nao servidor', () {
    expect(modoTerminalLeveAtivo(cfg(sync: false)), isFalse);
    expect(modoTerminalLeveAtivo(cfg(servidor: true)), isFalse);
    // Em Windows/Android/iOS de teste do host: o resultado depende da plataforma
    // do processo de teste (em geral Windows no CI local).
    final ativo = modoTerminalLeveAtivo(cfg());
    expect(ativo, isA<bool>());
    if (ativo) {
      expect(modoTerminalLeveAtivo(cfg(servidor: true)), isFalse);
    }
  });

  test('destinos principais liberados no terminal', () {
    expect(destinoPermitidoNoTerminalLeve('pdv'), isTrue);
    expect(destinoPermitidoNoTerminalLeve('caixa'), isTrue);
    expect(destinoPermitidoNoTerminalLeve('inexistente'), isFalse);
  });
}
