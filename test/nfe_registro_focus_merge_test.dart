import 'package:flutter_test/flutter_test.dart';
import 'package:sistema_vendas/data/nfe_saida_fiscal_store.dart';
import 'package:sistema_vendas/domain/fiscal/nfe_registro_focus_merge.dart';
import 'package:sistema_vendas/services/focus_nfe_service.dart';

void main() {
  test('mesclar preserva CC-e e logistica local', () {
    final base = NfeSaidaFiscalRegistro(
      id: '1',
      vendaId: 5,
      numeroOrcamento: 99,
      clienteNome: 'Loja',
      referenciaFocus: 'venda_5_nfe',
      statusFocus: 'autorizado',
      emitidaEm: DateTime(2026, 1, 1),
      statusSefaz: '100',
      volumes: 3,
      pesoBrutoKg: 12.5,
      urlPdfCartaCorrecao: 'http://cce/pdf',
      numeroCartaCorrecao: 1,
    );
    final resultado = FocusNfeEmissaoResultado(
      autorizada: false,
      rejeitada: false,
      processando: false,
      statusFocus: 'cancelado',
      statusSefaz: '135',
      urlXmlCancelamento: 'http://xml/cancel',
      mensagem: 'Cancelamento homologado',
      referencia: 'venda_5_nfe',
    );

    final m = mesclarRegistroComResultadoFocus(base, resultado);
    expect(m.cancelada, isTrue);
    expect(m.volumes, 3);
    expect(m.pesoBrutoKg, 12.5);
    expect(m.urlPdfCartaCorrecao, 'http://cce/pdf');
    expect(m.numeroCartaCorrecao, 1);
    expect(m.urlXmlEventoCancelamento, 'http://xml/cancel');
  });
}
