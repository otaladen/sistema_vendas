import 'package:flutter_test/flutter_test.dart';
import 'package:sistema_vendas/data/nfe_saida_fiscal_store.dart';
import 'package:sistema_vendas/domain/fiscal/nfe_carta_correcao_registro.dart';
import 'package:sistema_vendas/domain/fiscal/nfe_historico_timeline.dart';

void main() {
  test('timeline inclui autorizada e CC-e', () {
    final r = NfeSaidaFiscalRegistro(
      id: '1',
      vendaId: 10,
      numeroOrcamento: 50,
      clienteNome: 'Cliente',
      referenciaFocus: 'venda_10_nfe',
      statusFocus: 'autorizado',
      emitidaEm: DateTime.now(),
      statusSefaz: '100',
      numero: '123',
      serie: '1',
      cartasCorrecao: [
        NfeCartaCorrecaoRegistro(
          numeroSequencia: 2,
          textoCorrecao: 'Correcao de teste',
          emitidaEm: DateTime.now(),
        ),
      ],
    );
    final itens = NfeHistoricoTimelineBuilder.fromRegistro(r);
    expect(itens.any((i) => i.titulo.contains('Autorizada')), isTrue);
    expect(itens.any((i) => i.titulo.contains('Carta de Correcao')), isTrue);
  });

  test('timeline rejeitada marca erro', () {
    final r = NfeSaidaFiscalRegistro(
      id: '2',
      vendaId: 11,
      numeroOrcamento: 51,
      clienteNome: 'Cliente',
      referenciaFocus: 'venda_11_nfe',
      statusFocus: 'erro_autorizacao',
      emitidaEm: DateTime.now(),
      mensagemSefaz: 'Rejeicao 999',
    );
    final itens = NfeHistoricoTimelineBuilder.fromRegistro(r);
    final rej = itens.firstWhere((i) => i.titulo == 'Rejeitada');
    expect(rej.erro, isTrue);
    expect(rej.subtitulo, contains('Rejeicao'));
  });
}
