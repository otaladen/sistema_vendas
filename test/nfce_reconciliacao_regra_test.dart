import 'package:flutter_test/flutter_test.dart';
import 'package:sistema_vendas/model/venda.dart';

void main() {
  group('NFC-e pendente Focus', () {
    test('identifica marcador focus_pendente', () {
      final venda = Venda(numeroOrcamento: 1)
        ..status = 'finalizada'
        ..nfceProtocolo = 'focus_pendente:processando:venda_42';

      expect(marcadaComNfcePendenteFocus(venda), isTrue);
    });

    test('ignora venda com NFC-e autorizada', () {
      final venda = Venda(numeroOrcamento: 2)
        ..status = 'finalizada'
        ..nfceChaveAcesso = '35260123456789012345678901234567890123456789';

      expect(marcadaComNfcePendenteFocus(venda), isFalse);
    });

    test('identifica status processando_autorizacao', () {
      final venda = Venda(numeroOrcamento: 3)
        ..status = 'finalizada'
        ..nfceStatusFocus = 'processando_autorizacao';

      expect(marcadaComNfcePendenteFocus(venda), isTrue);
    });
  });
}

bool marcadaComNfcePendenteFocus(Venda venda) {
  if (venda.nfceEmitida) return false;
  final status = venda.nfceStatusFocus.trim().toLowerCase();
  if (status == 'processando_autorizacao') return true;
  final protocolo = venda.nfceProtocolo.trim();
  if (protocolo.contains('focus_pendente')) return true;
  return false;
}
