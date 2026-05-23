import 'dart:io';

import 'package:flutter/widgets.dart';

import 'package:sistema_vendas/data/objectbox.dart';
import 'package:sistema_vendas/data/venda_repository.dart';

/// Uso (na raiz do projeto):
///   flutter run -t tool/limpar_entregas_teste.dart -d windows
///
/// Cancela todas as vendas de carreto que aparecem na aba Entregas e limpa
/// conferencia/historico de entrega (banco local deste PC).
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  stdout.writeln('Abrindo banco ObjectBox...');
  final ob = await ObjectBox.create();
  final repo = VendaRepository(ob);

  final antes = repo.listarEntregas();
  stdout.writeln('Entregas na aba antes: ${antes.length}');

  final r = repo.limparAbaEntregasCancelandoVendas(
    motivo: 'Limpeza automatica — teste aba Entregas',
    canceladaPor: 'ferramenta_limpar_entregas',
    forcarQuandoBloqueado: true,
  );

  final depois = repo.listarEntregas();
  stdout.writeln('Canceladas: ${r.canceladas}');
  if (r.forcadas > 0) {
    stdout.writeln('Forcadas (sem estorno): ${r.forcadas}');
  }
  stdout.writeln('Conferencias removidas: ${r.conferenciasRemovidas}');
  stdout.writeln('Historicos removidos: ${r.historicosRemovidos}');
  stdout.writeln('Entregas na aba depois: ${depois.length}');
  if (r.falhas.isNotEmpty) {
    stdout.writeln('Falhas (${r.falhas.length}):');
    for (final f in r.falhas) {
      stdout.writeln('  - $f');
    }
  }

  ob.store.close();
  stdout.writeln('Concluido.');
  exit(0);
}
