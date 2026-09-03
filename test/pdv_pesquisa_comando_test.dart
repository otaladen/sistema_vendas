import 'package:flutter_test/flutter_test.dart';
import 'package:sistema_vendas/ui/pdv_pesquisa_comando.dart';

void main() {
  group('PdvPesquisaComando.parse', () {
    test('2 de areia extrai quantidade e busca areia', () {
      final cmd = PdvPesquisaComando.parse('2 de areia');
      expect(cmd.quantidadeDireta, 2);
      expect(cmd.termoBusca, 'areia');
      expect(cmd.adicaoDireta, isFalse);
    });

    test('5,75 areia extrai quantidade fracionada', () {
      final cmd = PdvPesquisaComando.parse('5,75 areia');
      expect(cmd.quantidadeDireta, closeTo(5.75, 0.0001));
      expect(cmd.termoBusca, 'areia');
    });

    test('5.75 parafuso aceita ponto decimal', () {
      final cmd = PdvPesquisaComando.parse('5.75 parafuso');
      expect(cmd.quantidadeDireta, closeTo(5.75, 0.0001));
      expect(cmd.termoBusca, 'parafuso');
    });

    test('areia+ e adicao direta', () {
      final cmd = PdvPesquisaComando.parse('areia+');
      expect(cmd.termoBusca, 'areia');
      expect(cmd.adicaoDireta, isTrue);
    });
  });
}
