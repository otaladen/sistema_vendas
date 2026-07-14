/// Confirmação textual exigida para zerar o cadastro de produtos.
class ProdutoCadastroZerarConfirmacao {
  ProdutoCadastroZerarConfirmacao._();

  static const frase = 'ZERAR';

  static bool confirma(String digitado) =>
      digitado.trim().toUpperCase() == frase;
}
