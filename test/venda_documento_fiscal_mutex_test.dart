import 'package:flutter_test/flutter_test.dart';
import 'package:sistema_vendas/domain/fiscal/venda_documento_fiscal_mutex.dart';
import 'package:sistema_vendas/model/venda.dart';

void main() {
  test('bloqueia NFC-e quando NF-e 55 ja autorizada', () {
    final venda = Venda()
      ..nfeStatusFocus = 'autorizado'
      ..nfeChaveAcesso = '29260632662298000191550010000000011234567890';

    expect(VendaDocumentoFiscalMutex.bloqueiaNovaNfce(venda), isTrue);
    expect(
      VendaDocumentoFiscalMutex.mensagemBloqueioNovaNfce(venda),
      contains('NF-e modelo 55'),
    );
  });

  test('bloqueia NF-e quando NFC-e ja emitida', () {
    final venda = Venda()
      ..nfceChaveAcesso = '29260632662298000191650010000000051626070139';

    expect(VendaDocumentoFiscalMutex.bloqueiaNovaNfe55(venda), isTrue);
    expect(
      VendaDocumentoFiscalMutex.mensagemBloqueioNovaNfe55(venda),
      contains('NFC-e'),
    );
  });

  test('permite NFC-e quando venda sem documento fiscal', () {
    final venda = Venda();
    expect(VendaDocumentoFiscalMutex.bloqueiaNovaNfce(venda), isFalse);
    expect(VendaDocumentoFiscalMutex.bloqueiaNovaNfe55(venda), isFalse);
  });
}
