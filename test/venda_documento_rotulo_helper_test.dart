import 'package:flutter_test/flutter_test.dart';
import 'package:sistema_vendas/domain/venda_documento_rotulo_helper.dart';
import 'package:sistema_vendas/model/venda.dart';

void main() {
  test('status resumido sem fiscal mostra so fiscal pendente', () {
    final venda = Venda()
      ..numeroOrcamento = 157
      ..estoqueBaixadoCupom = true;

    final s = VendaDocumentoRotuloHelper.statusOperacionalResumidoLista(venda);
    expect(s, 'Fiscal pendente');
    expect(s.contains('Estoque OK'), isFalse);
  });

  test('status resumido concluida quando fiscal e estoque ok', () {
    final venda = Venda()
      ..numeroOrcamento = 148
      ..nfceChaveAcesso = '35260612345678901234567890123456789012345678'
      ..nfceNumero = '8'
      ..estoqueBaixadoCupom = true;

    final s = VendaDocumentoRotuloHelper.statusOperacionalResumidoLista(venda);
    expect(s, 'Concluída');
  });

  test('status resumido alerta estoque pendente', () {
    final venda = Venda()
      ..numeroOrcamento = 148
      ..nfceChaveAcesso = '35260612345678901234567890123456789012345678'
      ..estoqueBaixadoCupom = false;

    final s = VendaDocumentoRotuloHelper.statusOperacionalResumidoLista(venda);
    expect(s, 'Estoque pendente');
  });
}
