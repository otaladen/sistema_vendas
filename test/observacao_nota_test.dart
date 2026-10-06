import 'package:flutter_test/flutter_test.dart';
import 'package:sistema_vendas/data/sync/sync_entity_codec.dart';
import 'package:sistema_vendas/domain/observacao_nota.dart';
import 'package:sistema_vendas/domain/venda_documento_rotulo_helper.dart';
import 'package:sistema_vendas/model/venda.dart';

void main() {
  test('observacaoNota entra nas informacoes adicionais da nota fiscal', () {
    final venda = Venda(
      status: 'finalizada',
      numeroControle: 42,
      observacaoNota: 'Tinta cor RAL 9003',
    );
    expect(
      VendaDocumentoRotuloHelper.observacaoFiscalNota(venda),
      contains('Tinta cor RAL 9003'),
    );
  });

  test('resumoLista encurta linha longa', () {
    final long = 'A' * 100;
    expect(ObservacaoNota.resumoLista(long, maxCaracteres: 20).endsWith('…'),
        isTrue);
  });

  test('linhasRodapeCupom mantem caixa natural', () {
    final venda = Venda(observacaoNota: 'Vai querer por no saco');
    expect(
      ObservacaoNota.linhasRodapeCupom(venda),
      ['Vai querer por no saco'],
    );
  });

  test('codec de sync preserva observacaoNota', () {
    final venda = Venda(observacaoNota: 'Telha colonial');
    final copia = SyncEntityCodec.vendaCabecaDeMap(
      SyncEntityCodec.vendaParaMap(venda),
    );
    expect(ObservacaoNota.linhasImpressao(copia), ['TELHA COLONIAL']);
  });
}
