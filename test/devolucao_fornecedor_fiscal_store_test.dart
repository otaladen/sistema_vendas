import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sistema_vendas/data/devolucao_fornecedor_fiscal_store.dart';

void main() {
  DevolucaoFornecedorFiscalRegistro registro({
    String status = '',
    bool? estoqueBaixado,
    String itens = '[]',
    String ref = 'ref1',
  }) {
    return DevolucaoFornecedorFiscalRegistro(
      chaveNotaCompra: '35200112345678000199550010000000011000000011',
      referenciaFocus: ref,
      chaveNfe: '',
      statusFocus: status,
      itensBaixaJson: itens,
      estoqueBaixado: estoqueBaixado ?? false,
    );
  }

  test('legado autorizado sem campo infere estoqueBaixado', () {
    final r = DevolucaoFornecedorFiscalRegistro.fromJson({
      'statusFocus': 'autorizado',
      'itensBaixaJson': '[]',
    });
    expect(r.estoqueBaixado, isTrue);
    expect(r.autorizada, isTrue);
    expect(r.pendenteReconsulta, isFalse);
  });

  test('processando sem campo nao infere baixa', () {
    final r = DevolucaoFornecedorFiscalRegistro.fromJson({
      'statusFocus': 'processando_autorizacao',
    });
    expect(r.estoqueBaixado, isFalse);
    expect(r.processando, isTrue);
    expect(r.pendenteReconsulta, isTrue);
  });

  test('autorizada com flag false continua pendente de baixa', () {
    final r = DevolucaoFornecedorFiscalRegistro.fromJson({
      'statusFocus': 'autorizado',
      'estoqueBaixado': false,
    });
    expect(r.estoqueBaixado, isFalse);
    expect(r.pendenteReconsulta, isTrue);
  });

  test('toJson roundtrip preserva estoqueBaixado false', () {
    final r = registro(status: 'processando_autorizacao', estoqueBaixado: false);
    final again = DevolucaoFornecedorFiscalRegistro.fromJson(r.toJson());
    expect(again.estoqueBaixado, isFalse);
    expect(again.processando, isTrue);
  });

  test('quantidades: processando reserva e rejeitada libera', () async {
    final dir = await Directory.systemTemp.createTemp('devforn_fiscal');
    addTearDown(() {
      if (dir.existsSync()) dir.deleteSync(recursive: true);
    });
    final store = DevolucaoFornecedorFiscalStore(dir.path);
    final chave = '35200112345678000199550010000000011000000011';
    final item = jsonEncode([
      {'historicoEntradaId': 10, 'produtoId': 3, 'quantidade': 5},
    ]);

    store.salvar(
      registro(
        status: 'processando_autorizacao',
        itens: item,
        ref: 'a',
      ),
    );
    expect(store.quantidadesJaDevolvidasPorHistorico(chave)[10], 5);

    store.salvar(
      registro(
        status: 'erro_autorizacao',
        itens: item,
        ref: 'a',
      ),
    );
    expect(store.quantidadesJaDevolvidasPorHistorico(chave), isEmpty);
  });

  test('listarPendentesReconsulta pega processando e autorizada sem baixa',
      () async {
    final dir = await Directory.systemTemp.createTemp('devforn_pend');
    addTearDown(() {
      if (dir.existsSync()) dir.deleteSync(recursive: true);
    });
    final store = DevolucaoFornecedorFiscalStore(dir.path);
    store.salvar(registro(status: 'autorizado', estoqueBaixado: true, ref: 'ok'));
    store.salvar(
      registro(status: 'processando_autorizacao', ref: 'proc'),
    );
    store.salvar(
      registro(status: 'autorizado', estoqueBaixado: false, ref: 'stuck'),
    );
    final pend = store.listarPendentesReconsulta();
    expect(pend.map((e) => e.referenciaFocus), containsAll(['proc', 'stuck']));
    expect(pend.map((e) => e.referenciaFocus), isNot(contains('ok')));
  });
}
