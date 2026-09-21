import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sistema_vendas/data/mensagem_interna_repository.dart';
import 'package:sistema_vendas/domain/autorizacao_pdv_chat.dart';
import 'package:sistema_vendas/model/mensagem_interna.dart';

void main() {
  test('preservarNaRetencao mantem autorizacao PDV e payload de solicitacao', () {
    final auth = MensagemInterna(
      id: 1,
      vendedor: 'Maria',
      texto: 'Autorizacao',
      dataHora: DateTime.utc(2020, 1, 1),
      tipo: kMensagemInternaTipoAutorizacaoPdv,
      payload: {
        'solicitacaoId': 'abc-123',
        'status': AutorizacaoPdvChatStatus.pendente,
      },
    );
    expect(auth.preservarNaRetencao, isTrue);

    final texto = MensagemInterna(
      id: 2,
      vendedor: 'Joao',
      texto: 'Oi',
      dataHora: DateTime.utc(2020, 1, 1),
    );
    expect(texto.preservarNaRetencao, isFalse);
  });

  test('podar nao remove autorizacao PDV antiga ao estourar TTL', () async {
    final dir = await Directory.systemTemp.createTemp('chat_retencao_');
    addTearDown(() async {
      try {
        await dir.delete(recursive: true);
      } catch (_) {}
    });
    final repo = MensagemInternaRepository(
      storeDirectoryPath: dir.path,
      maxMensagens: 2,
      ttl: const Duration(hours: 1),
    );

    await repo.enviar(
      vendedor: 'Sistema',
      texto: 'Pedido de desconto',
      tipo: kMensagemInternaTipoAutorizacaoPdv,
      payload: {
        'solicitacaoId': 'sol-1',
        'status': AutorizacaoPdvChatStatus.pendente,
      },
    );
    for (var i = 0; i < 5; i++) {
      await repo.enviar(vendedor: 'A', texto: 'msg $i');
    }

    final historico = await repo.listarHistorico();
    expect(
      historico.any((m) => m.tipo == kMensagemInternaTipoAutorizacaoPdv),
      isTrue,
      reason: 'Autorizacao PDV deve permanecer apos poda',
    );
    expect(historico.any((m) => m.texto == 'msg 4'), isTrue);
    expect(historico.length, 2);

  });
}
