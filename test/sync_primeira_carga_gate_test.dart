import 'package:flutter_test/flutter_test.dart';
import 'package:sistema_vendas/data/sync/sync_primeira_carga.dart';

void main() {
  test('indicadores de sync opcional: servidor nunca e candidato', () {
    expect(
      SyncPrimeiraCarga.deveForcarGateCliente(
        redeModoServidor: true,
        redeSincronizacaoAtiva: true,
        redeServidorUrl: '',
        bancoVazio: true,
      ),
      isFalse,
    );
  });

  test('banco vazio sem URL: nao e candidato a pull (use o ERP normalmente)', () {
    expect(
      SyncPrimeiraCarga.deveForcarGateCliente(
        redeModoServidor: false,
        redeSincronizacaoAtiva: true,
        redeServidorUrl: '',
        bancoVazio: true,
      ),
      isFalse,
    );
  });

  test('cliente com URL e banco vazio: sync inicial faz sentido (opcional)', () {
    expect(
      SyncPrimeiraCarga.deveForcarGateCliente(
        redeModoServidor: false,
        redeSincronizacaoAtiva: true,
        redeServidorUrl: 'http://192.168.1.10:8787',
        bancoVazio: true,
      ),
      isTrue,
    );
  });
}
