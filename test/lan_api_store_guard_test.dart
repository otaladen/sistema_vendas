import 'package:flutter_test/flutter_test.dart';

import 'package:sistema_vendas/data/objectbox_lifecycle_hub.dart';
import 'package:sistema_vendas/domain/sessao_operacional_guard.dart';
import 'package:sistema_vendas/services/lan_api/lan_api_store_guard.dart';

void main() {
  test('health, presence e stream ficam livres durante backup', () {
    expect(LanApiStoreGuard.caminhoLivreDuranteBackup('api/health'), isTrue);
    expect(LanApiStoreGuard.caminhoLivreDuranteBackup('api/presence'), isTrue);
    expect(LanApiStoreGuard.caminhoLivreDuranteBackup('api/stream'), isTrue);
    expect(LanApiStoreGuard.caminhoLivreDuranteBackup('api/vendas'), isFalse);
    expect(LanApiStoreGuard.caminhoLivreDuranteBackup('api/caixa/sessao'), isFalse);
  });

  test('detecta Bad state Store is closed', () {
    expect(
      LanApiStoreGuard.erroStoreFechada(
        StateError('Bad state: Store is closed'),
      ),
      isTrue,
    );
    expect(LanApiStoreGuard.erroStoreFechada('sku duplicado'), isFalse);
  });

  test('body 503 usa code store_unavailable', () {
    final body = LanApiStoreGuard.bodyJson();
    expect(body['ok'], isFalse);
    expect(body['code'], LanApiStoreGuard.code);
    expect(body['error'], contains('backup'));
  });

  test('reabrir store incrementa geracao', () {
    ObjectBoxLifecycleHub.storeFechadaParaCopia = true;
    final antes = ObjectBoxLifecycleHub.geracaoStore;
    ObjectBoxLifecycleHub.notificarStoreReaberta();
    expect(ObjectBoxLifecycleHub.acessoLocalSuspenso, isFalse);
    expect(ObjectBoxLifecycleHub.geracaoStore, antes + 1);
  });

  test('operacaoCriticaAtiva considera PDV local e terminais WS', () {
    SessaoOperacionalGuard.atualizarTerminaisWs(0);
    while (SessaoOperacionalGuard.pdvEmUso) {
      SessaoOperacionalGuard.marcarPdvFechado();
    }
    expect(SessaoOperacionalGuard.operacaoCriticaAtiva, isFalse);

    SessaoOperacionalGuard.atualizarTerminaisWs(2);
    expect(SessaoOperacionalGuard.terminaisConectados, isTrue);
    expect(SessaoOperacionalGuard.operacaoCriticaAtiva, isTrue);

    SessaoOperacionalGuard.atualizarTerminaisWs(0);
    expect(SessaoOperacionalGuard.operacaoCriticaAtiva, isFalse);

    SessaoOperacionalGuard.marcarPdvAberto();
    expect(SessaoOperacionalGuard.operacaoCriticaAtiva, isTrue);
    SessaoOperacionalGuard.marcarPdvFechado();
    expect(SessaoOperacionalGuard.operacaoCriticaAtiva, isFalse);
  });
}
