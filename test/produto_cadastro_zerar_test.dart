import 'package:flutter_test/flutter_test.dart';
import 'package:sistema_vendas/domain/produto_cadastro_zerar.dart';

void main() {
  test('confirmacao exige ZERAR (case-insensitive, trim)', () {
    expect(ProdutoCadastroZerarConfirmacao.confirma('ZERAR'), isTrue);
    expect(ProdutoCadastroZerarConfirmacao.confirma('zerar'), isTrue);
    expect(ProdutoCadastroZerarConfirmacao.confirma('  Zerar  '), isTrue);
    expect(ProdutoCadastroZerarConfirmacao.confirma('ZERAR '), isTrue);
    expect(ProdutoCadastroZerarConfirmacao.confirma('APAGAR'), isFalse);
    expect(ProdutoCadastroZerarConfirmacao.confirma(''), isFalse);
    expect(ProdutoCadastroZerarConfirmacao.confirma('ZERAR!'), isFalse);
  });
}
