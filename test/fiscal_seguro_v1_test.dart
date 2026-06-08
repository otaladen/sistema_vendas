import 'package:flutter_test/flutter_test.dart';
import 'package:sistema_vendas/domain/fiscal/fiscal_emissao_lock.dart';
import 'package:sistema_vendas/model/venda.dart';
import 'package:sistema_vendas/services/focus_nfe_service.dart';

void main() {
  group('FiscalEmissaoLock', () {
    test('bloqueia outro dispositivo com lock recente', () {
      final venda = Venda(numeroOrcamento: 1)
        ..nfceStatusFocus = FiscalEmissaoLock.statusEmAndamento
        ..nfceProtocolo = FiscalEmissaoLock.marcador('pc-servidor', 'venda_1');

      expect(
        FiscalEmissaoLock.nfceBloqueadaPorOutroDispositivo(venda, 'pc-caixa'),
        isTrue,
      );
      expect(
        FiscalEmissaoLock.nfceBloqueadaPorOutroDispositivo(venda, 'pc-servidor'),
        isFalse,
      );
    });
  });

  group('FocusNfeService.pareceFalhaComunicacao', () {
    test('detecta timeout na mensagem', () {
      final r = FocusNfeEmissaoResultado.erro(
        'Falha de comunicacao com a Focus/SEFAZ (timeout ou rede)',
        httpStatusCode: 0,
      );
      expect(FocusNfeService.pareceFalhaComunicacao(r), isTrue);
    });

    test('ignora rejeicao fiscal explicita', () {
      final r = FocusNfeEmissaoResultado(
        autorizada: false,
        rejeitada: true,
        processando: false,
        mensagem: 'Rejeicao: CFOP invalido',
        httpStatusCode: 422,
      );
      expect(FocusNfeService.pareceFalhaComunicacao(r), isFalse);
    });

    test('ignora rejeicao SEFAZ de data-hora (nao dispara contingencia)', () {
      final r = FocusNfeEmissaoResultado(
        autorizada: false,
        rejeitada: true,
        processando: false,
        statusSefaz: '703',
        mensagem:
            'Data-Hora de Emissao posterior ao horario de recebimento (Offline)',
        httpStatusCode: 201,
      );
      expect(FocusNfeService.pareceFalhaComunicacao(r), isFalse);
    });
  });
}
