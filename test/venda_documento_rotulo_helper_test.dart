import 'package:flutter_test/flutter_test.dart';
import 'package:sistema_vendas/domain/venda_documento_rotulo_helper.dart';
import 'package:sistema_vendas/model/venda.dart';

void main() {
  test('status resumido sem fiscal mostra so fiscal pendente', () {
    final venda = Venda()
      ..status = 'finalizada'
      ..numeroOrcamento = 157
      ..numeroControle = 157
      ..estoqueBaixadoCupom = true;

    final s = VendaDocumentoRotuloHelper.statusOperacionalResumidoLista(venda);
    expect(s, 'Fiscal pendente');
    expect(s.contains('Estoque OK'), isFalse);
  });

  test('status resumido concluida quando fiscal e estoque ok', () {
    final venda = Venda()
      ..status = 'finalizada'
      ..numeroOrcamento = 148
      ..numeroControle = 148
      ..nfceChaveAcesso = '35260612345678901234567890123456789012345678'
      ..nfceNumero = '8'
      ..estoqueBaixadoCupom = true;

    final s = VendaDocumentoRotuloHelper.statusOperacionalResumidoLista(venda);
    expect(s, 'Concluída');
  });

  test('status resumido alerta estoque pendente', () {
    final venda = Venda()
      ..status = 'finalizada'
      ..numeroOrcamento = 148
      ..numeroControle = 148
      ..nfceChaveAcesso = '35260612345678901234567890123456789012345678'
      ..estoqueBaixadoCupom = false;

    final s = VendaDocumentoRotuloHelper.statusOperacionalResumidoLista(venda);
    expect(s, 'Estoque pendente');
  });

  test('orcamento aberto nunca aparece como fiscal pendente nem controle', () {
    final orc = Venda()
      ..status = 'orcamento'
      ..numeroOrcamento = 452
      ..numeroControle = 0
      ..estoqueBaixadoCupom = false;

    expect(VendaDocumentoRotuloHelper.ehOrcamentoAberto(orc), isTrue);
    expect(VendaDocumentoRotuloHelper.numeroControleInterno(orc), 0);
    expect(VendaDocumentoRotuloHelper.rotuloOrcamento(orc), 'Orc. 452');
    expect(VendaDocumentoRotuloHelper.rotuloControleInterno(orc), 'Orc. 452');
    expect(
      VendaDocumentoRotuloHelper.statusOperacionalResumidoLista(orc),
      'Orçamento',
    );
    expect(
      VendaDocumentoRotuloHelper.statusOperacionalLista(orc),
      'Orc. 452 · em aberto',
    );
    expect(
      VendaDocumentoRotuloHelper.rotuloIdentificacaoLista(orc),
      'Orc. 452',
    );
    expect(VendaDocumentoRotuloHelper.badgeNumeroCurto(orc), '452');
  });

  test('venda finalizada usa numeroControle e nao o numero do orcamento', () {
    final venda = Venda()
      ..status = 'finalizada'
      ..numeroOrcamento = 452
      ..numeroControle = 310
      ..estoqueBaixadoCupom = true;

    expect(VendaDocumentoRotuloHelper.numeroControleInterno(venda), 310);
    expect(
      VendaDocumentoRotuloHelper.rotuloControleInterno(venda),
      'Controle 310',
    );
    expect(VendaDocumentoRotuloHelper.badgeNumeroCurto(venda), '310');
    expect(
      VendaDocumentoRotuloHelper.statusOperacionalResumidoLista(venda),
      'Fiscal pendente',
    );
  });

  test('venda legada sem numeroControle cai no numeroOrcamento', () {
    final venda = Venda()
      ..status = 'finalizada'
      ..numeroOrcamento = 148
      ..numeroControle = 0
      ..estoqueBaixadoCupom = true;

    expect(VendaDocumentoRotuloHelper.numeroControleInterno(venda), 148);
    expect(
      VendaDocumentoRotuloHelper.rotuloControleInterno(venda),
      'Controle 148',
    );
  });
}
