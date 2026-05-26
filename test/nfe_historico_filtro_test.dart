import 'package:flutter_test/flutter_test.dart';
import 'package:sistema_vendas/data/nfe_saida_fiscal_store.dart';
import 'package:sistema_vendas/domain/fiscal/nfe_historico_filtro.dart';

NfeSaidaFiscalRegistro _reg({
  required String id,
  required String cliente,
  required String statusFocus,
  String statusSefaz = '',
  String chave = '',
  DateTime? emitidaEm,
  int vendaId = 1,
  int orcamento = 100,
}) {
  return NfeSaidaFiscalRegistro(
    id: id,
    vendaId: vendaId,
    numeroOrcamento: orcamento,
    clienteNome: cliente,
    referenciaFocus: 'ref_$id',
    statusFocus: statusFocus,
    emitidaEm: emitidaEm ?? DateTime(2026, 5, 10),
    statusSefaz: statusSefaz,
    chaveNfe: chave,
  );
}

void main() {
  test('filtro por status autorizada', () {
    final lista = [
      _reg(id: '1', cliente: 'A', statusFocus: 'autorizado', statusSefaz: '100'),
      _reg(id: '2', cliente: 'B', statusFocus: 'erro_autorizacao'),
    ];
    final f = const NfeHistoricoFiltro(
      status: NfeHistoricoStatusFiltro.autorizada,
    );
    final out = NfeHistoricoFiltroUtil.aplicar(lista, f);
    expect(out.length, 1);
    expect(out.first.id, '1');
  });

  test('filtro por texto e chave numerica', () {
    final lista = [
      _reg(
        id: '1',
        cliente: 'Construtora X',
        statusFocus: 'autorizado',
        chave: '29260512345678901234567890123456789012345678',
      ),
      _reg(id: '2', cliente: 'Outro', statusFocus: 'autorizado'),
    ];
    final out = NfeHistoricoFiltroUtil.aplicar(
      lista,
      const NfeHistoricoFiltro(textoBusca: '29260512345678'),
    );
    expect(out.length, 1);
    expect(out.first.clienteNome, 'Construtora X');
  });

  test('filtro por periodo', () {
    final lista = [
      _reg(
        id: '1',
        cliente: 'A',
        statusFocus: 'autorizado',
        emitidaEm: DateTime(2026, 5, 1),
      ),
      _reg(
        id: '2',
        cliente: 'B',
        statusFocus: 'autorizado',
        emitidaEm: DateTime(2026, 6, 1),
      ),
    ];
    final out = NfeHistoricoFiltroUtil.aplicar(
      lista,
      NfeHistoricoFiltro(
        dataInicio: DateTime(2026, 5, 15),
        dataFim: DateTime(2026, 5, 31),
      ),
    );
    expect(out, isEmpty);
  });
}
