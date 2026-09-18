import 'package:flutter_test/flutter_test.dart';
import 'package:sistema_vendas/data/app_config_repository.dart';
import 'package:sistema_vendas/services/esc_pos_commands.dart';
import 'package:sistema_vendas/services/esc_pos_fechamento_caixa_builder.dart';
import 'package:sistema_vendas/services/esc_pos_text_layout.dart';

List<String> _linhasTexto(List<int> bytes) {
  final out = <String>[];
  final current = <int>[];
  void flush() {
    if (current.isEmpty) return;
    out.add(String.fromCharCodes(current));
    current.clear();
  }

  var skip = 0;
  for (final b in bytes) {
    if (skip > 0) {
      skip--;
      continue;
    }
    if (b == 0x0A) {
      flush();
    } else if (b == 0x1B || b == 0x1D) {
      flush();
      skip = 1;
    } else if (b >= 32 && b < 127) {
      current.add(b);
    }
  }
  flush();
  return out.where((l) => l.trim().isNotEmpty).toList();
}

FechamentoCaixaEscPosDados _dados({String largura = '80'}) {
  return FechamentoCaixaEscPosDados(
    config: EmpresaConfig(
      nomeLoja: 'Comprou Levou Construcao Materiais LTDA',
      escPosLargura: largura,
    ),
    operador: 'Mayrena',
    aberturaEm: DateTime(2026, 9, 8, 8, 30),
    fechamentoEm: DateTime(2026, 9, 8, 18, 15),
    fundoTroco: 200,
    suprimentos: 50,
    sangrias: 30,
    esperadoDinheiro: 1500,
    esperadoPix: 800,
    esperadoDebito: 400,
    esperadoCredito: 300,
    declaradoDinheiro: 1500,
    declaradoPix: 800,
    declaradoDebito: 400,
    declaradoCredito: 300,
  );
}

void main() {
  test('rotuloValor mantem valor alinhado a direita dentro de 48 colunas', () {
    const cols = 48;
    final linha = EscPosTextLayout.rotuloValor(
      'Diferenca total:',
      'R\$ -0,00',
      cols,
    );
    expect(linha.length, lessThanOrEqualTo(cols));
    expect(linha.trimRight().endsWith('R\$ -0,00'), isTrue);
  });

  test('wrap quebra titulo longo de conferencia em 32 colunas (58mm)', () {
    const cols = 32;
    final partes = EscPosTextLayout.wrap(
      'Conferencia por forma de pagamento',
      cols,
    );
    expect(partes.length, greaterThan(1));
    for (final p in partes) {
      expect(p.length, lessThanOrEqualTo(cols));
    }
  });

  test('titulo expandido respeita no maximo 24 caracteres por linha (80mm)', () {
    const cols = 48;
    final max = EscPosTextLayout.maxCharsTituloExpandido(cols);
    expect(max, 24);
    final partes = EscPosTextLayout.wrapTituloExpandido(
      'FECHAMENTO DE CAIXA (X/Z)',
      cols,
    );
    for (final p in partes) {
      expect(p.length, lessThanOrEqualTo(max));
    }
  });

  test('fechamento 80mm nenhuma linha imprimivel passa de 48 colunas', () {
    final linhas = _linhasTexto(
      EscPosFechamentoCaixaBuilder.montar(
        _dados(),
        largura: EscPosLarguraBobina.mm80,
        cortar: false,
      ),
    );
    for (final l in linhas) {
      expect(
        l.length,
        lessThanOrEqualTo(48),
        reason: 'Linha estourou: "$l" (${l.length})',
      );
    }
    expect(linhas.join('\n'), contains('Conferencia por forma'));
    expect(linhas.join('\n'), contains('Diferenca total:'));
    expect(linhas.join('\n'), contains('(sem divergencia)'));
  });

  test('fechamento 58mm respeita 32 colunas', () {
    final linhas = _linhasTexto(
      EscPosFechamentoCaixaBuilder.montar(
        _dados(largura: '58'),
        largura: EscPosLarguraBobina.mm58,
        cortar: false,
      ),
    );
    for (final l in linhas) {
      expect(l.length, lessThanOrEqualTo(32), reason: 'Linha: "$l"');
    }
  });
}
