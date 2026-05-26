import 'package:flutter_test/flutter_test.dart';
import 'package:sistema_vendas/data/nfe_saida_fiscal_store.dart';
import 'package:sistema_vendas/domain/fiscal/nfe_referencia_resolver.dart';
import 'package:sistema_vendas/model/venda.dart';

void main() {
  test('rejeitada reutiliza mesma referencia', () {
    final venda = Venda(id: 10, numeroOrcamento: 50);
    final ultima = NfeSaidaFiscalRegistro(
      id: '1',
      vendaId: 10,
      numeroOrcamento: 50,
      clienteNome: 'C',
      referenciaFocus: 'venda_10_nfe',
      statusFocus: 'erro_autorizacao',
      emitidaEm: DateTime.now(),
    );
    final ref = NfeReferenciaResolver.proximaParaEmissao(
      venda: venda,
      ultimaLocal: ultima,
      historicoVenda: [ultima],
    );
    expect(ref, 'venda_10_nfe');
  });

  test('autorizada gera sequencia _2', () {
    final venda = Venda(
      id: 10,
      numeroOrcamento: 50,
      nfeReferenciaFocus: 'venda_10_nfe',
      nfeStatusFocus: 'autorizado',
      nfeChaveAcesso: '29260512345678901234567890123456789012345678',
    );
    final auth = NfeSaidaFiscalRegistro(
      id: '1',
      vendaId: 10,
      numeroOrcamento: 50,
      clienteNome: 'C',
      referenciaFocus: 'venda_10_nfe',
      statusFocus: 'autorizado',
      emitidaEm: DateTime.now(),
      statusSefaz: '100',
    );
    final ref = NfeReferenciaResolver.proximaParaEmissao(
      venda: venda,
      ultimaLocal: auth,
      historicoVenda: [auth],
    );
    expect(ref, 'venda_10_nfe_2');
  });
}
