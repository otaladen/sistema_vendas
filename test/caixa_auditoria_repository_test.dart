import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sistema_vendas/data/caixa_auditoria_repository.dart';
import 'package:sistema_vendas/data/objectbox.dart';

import 'helpers/objectbox_dll_for_tests.dart';

@Tags(['objectbox'])
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  SharedPreferences.setMockInitialValues({});
  final skipObjectBox = prepararObjectBoxDllParaTestes();

  test('enriquece detalhes com data, hora, operador, valor e tipo', () {
    final em = DateTime(2026, 9, 4, 15, 7, 9);
    final det = CaixaAuditoriaRepository.enriquecerDetalhes(
      evento: 'sangria',
      em: em,
      operador: 'Maria',
      detalhes: {'valor': 50.5, 'observacao': 'troco'},
    );
    expect(det['tipo'], 'sangria');
    expect(det['operador'], 'Maria');
    expect(det['valor'], 50.5);
    expect(det['data'], '2026-09-04');
    expect(det['hora'], '15:07:09');
  });

  test('deduplica fechamentos repetidos do mesmo turno', () {
    final em = DateTime(2026, 9, 5, 13, 5, 1);
    final dup = CaixaAuditoriaRegistro(
      em: em,
      evento: 'fechamento_caixa',
      usuario: 'a',
      operadorCaixa: 'otaladen',
      detalhes: {
        'aberturaEm': '2026-09-05T13:05:00.000Z',
        'operador': 'otaladen',
      },
    );
    final dup2 = CaixaAuditoriaRegistro(
      em: DateTime(2026, 9, 5, 13, 5, 8),
      evento: 'fechamento_caixa',
      usuario: 'b',
      operadorCaixa: 'otaladen',
      detalhes: {
        'aberturaEm': '2026-09-05T13:05:00.000Z',
        'operador': 'otaladen',
      },
    );
    final out = CaixaAuditoriaRepository.deduplicarRegistros([dup, dup2]);
    expect(out.length, 1);
  });

  test('valor do fechamento usa declaradoDinheiro quando valor ausente', () {
    expect(
      CaixaAuditoriaRepository.valorDoEvento('fechamento_caixa', {
        'declaradoDinheiro': 320.0,
      }),
      320.0,
    );
  });

  group(
    'caixa auditoria ObjectBox',
    skip: skipObjectBox,
    () {
      late Directory tempDir;
      late ObjectBox db;
      late CaixaAuditoriaRepository repo;

      setUp(() {
        tempDir = Directory.systemTemp.createTempSync('sv_caixa_aud_');
        db = ObjectBox.createForTest(tempDir);
        repo = CaixaAuditoriaRepository(db: db);
      });

      tearDown(() {
        db.close();
        try {
          tempDir.deleteSync(recursive: true);
        } catch (_) {}
      });

      test('grava suprimento, sangria e fechamento persistentes', () async {
        final em = DateTime(2026, 9, 4, 10, 30, 0);
        repo.gravarObjectBox(
          em: em,
          evento: 'suprimento',
          usuario: 'admin',
          operadorCaixa: 'Joao',
          detalhes: {'valor': 100},
        );
        repo.gravarObjectBox(
          em: em.add(const Duration(minutes: 5)),
          evento: 'sangria',
          usuario: 'admin',
          operadorCaixa: 'Joao',
          detalhes: {'valor': 40},
        );
        repo.gravarObjectBox(
          em: em.add(const Duration(hours: 8)),
          evento: 'fechamento_caixa',
          usuario: 'admin',
          operadorCaixa: 'Joao',
          detalhes: {
            'declaradoDinheiro': 250,
            'diferencaTotal': 2,
          },
        );
        repo.gravarObjectBox(
          em: em,
          evento: 'abertura_caixa',
          usuario: 'admin',
          operadorCaixa: 'Joao',
          detalhes: {'fundoTroco': 80},
        );

        expect(db.caixaAuditoriaEventoBox.count(), 3);
        final todos = await repo.listarTodos();
        expect(todos.map((e) => e.evento), containsAll(['suprimento', 'sangria', 'fechamento_caixa']));
        expect(todos.where((e) => e.evento == 'abertura_caixa'), isEmpty);

        final fechamentos = await repo.listarFechamentos();
        expect(fechamentos, hasLength(1));
        expect(fechamentos.first.operadorCaixa, 'Joao');
        expect(fechamentos.first.valor, 250);
        expect(fechamentos.first.detalhes['tipo'], 'fechamento_caixa');
        expect(fechamentos.first.detalhes['data'], '2026-09-04');
        expect(fechamentos.first.detalhes['hora'], '18:30:00');
      });
    },
  );
}
