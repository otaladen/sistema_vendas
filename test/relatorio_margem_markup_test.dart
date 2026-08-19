import 'package:flutter_test/flutter_test.dart';
import 'package:sistema_vendas/domain/relatorio_margem_markup.dart';

void main() {
  test('margem e markup com CMV positivo', () {
    final map = <String, RelatorioMargemLinha>{};
    RelatorioMargemMarkup.acumular(
      map,
      chave: 'cimento',
      nome: 'Cimento',
      receita: 150,
      cmv: 100,
    );
    final l = map['cimento']!;
    expect(l.lucro, 50);
    expect(l.margemPct, closeTo(33.333, 0.01));
    expect(l.markup, closeTo(0.5, 0.0001));
    expect(l.markupPct, closeTo(50, 0.01));
  });

  test('nao divide por zero sem receita ou CMV', () {
    final vazia = RelatorioMargemLinha(chave: 'x', nome: 'X');
    expect(vazia.margemPct, 0);
    expect(vazia.markup, 0);
  });

  test('ordenarPorLucro ignora receita residual', () {
    final a = RelatorioMargemLinha(chave: 'a', nome: 'A')
      ..receita = 200
      ..cmv = 50;
    final b = RelatorioMargemLinha(chave: 'b', nome: 'B')
      ..receita = 80
      ..cmv = 10;
    final c = RelatorioMargemLinha(chave: 'c', nome: 'C');
    final r = RelatorioMargemMarkup.ordenarPorLucro([a, b, c]);
    expect(r.map((e) => e.chave), ['a', 'b']);
  });
}
