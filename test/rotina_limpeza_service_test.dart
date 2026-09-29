import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sistema_vendas/data/auditoria_repository.dart';
import 'package:sistema_vendas/data/objectbox.dart';
import 'package:sistema_vendas/data/sugestao_venda_metrica_repository.dart';
import 'package:sistema_vendas/model/auditoria_evento.dart';
import 'package:sistema_vendas/model/sugestao_venda_metrica_evento.dart';
import 'package:sistema_vendas/services/rotina_limpeza_service.dart';

import 'helpers/objectbox_dll_for_tests.dart';

@Tags(['objectbox'])
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  SharedPreferences.setMockInitialValues({});
  final skipObjectBox = prepararObjectBoxDllParaTestes();

  group('rotina de limpeza', () {
    late Directory tempDir;
    late ObjectBox db;

    setUp(() {
      tempDir = Directory.systemTemp.createTempSync('sv_limpeza_obx_');
      db = ObjectBox.createForTest(tempDir);
    });

    tearDown(() {
      db.close();
      try {
        tempDir.deleteSync(recursive: true);
      } catch (_) {}
    });

    test('apaga metrica e auditoria anteriores a 90 dias', () {
      final antigo = DateTime.now().toUtc().subtract(const Duration(days: 120));
      final recente = DateTime.now().toUtc().subtract(const Duration(days: 2));

      db.sugestaoVendaMetricaEventoBox.putMany([
        SugestaoVendaMetricaEvento(
          produtoOrigemId: 1,
          produtoSugeridoId: 2,
          tipoEvento: 'exibiu',
          canal: 'pdv',
          fonte: 'agregado',
          dataHora: antigo,
        ),
        SugestaoVendaMetricaEvento(
          produtoOrigemId: 1,
          produtoSugeridoId: 3,
          tipoEvento: 'aceitou',
          canal: 'pdv',
          fonte: 'agregado',
          dataHora: recente,
        ),
      ]);
      db.auditoriaEventoBox.putMany([
        AuditoriaEvento(
          usuarioLogin: 'caixa',
          modulo: 'pdv',
          acao: 'teste',
          dataHora: antigo,
        ),
        AuditoriaEvento(
          usuarioLogin: 'caixa',
          modulo: 'pdv',
          acao: 'teste',
          dataHora: recente,
        ),
      ]);

      final metricas = SugestaoVendaMetricaRepository(db).purgarAnterioresA(
        RotinaLimpezaService.diasRetencaoMetricaSugestao,
      );
      final auditorias = AuditoriaRepository(db).purgarAnterioresARetencaoDias(
        90,
      );

      expect(metricas, 1);
      expect(auditorias, 1);
      expect(db.sugestaoVendaMetricaEventoBox.count(), 1);
      expect(db.auditoriaEventoBox.count(), 1);
      expect(
        db.sugestaoVendaMetricaEventoBox.getAll().single.produtoSugeridoId,
        3,
      );
    });
  }, skip: skipObjectBox);
}
