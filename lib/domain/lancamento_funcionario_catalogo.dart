/// Tipos de lancamento financeiro do funcionario (folha simplificada).
class LancamentoFuncionarioCatalogo {
  LancamentoFuncionarioCatalogo._();

  static const String vale = 'vale';
  static const String desconto = 'desconto';
  static const String bonus = 'bonus';
  static const String observacao = 'observacao';

  static const Map<String, String> tipos = {
    vale: 'Vale / adiantamento',
    desconto: 'Desconto (lancamento)',
    bonus: 'Bonus / credito',
    observacao: 'Observacao (sem valor)',
  };

  static List<String> get idsTipos => tipos.keys.toList();

  static String rotulo(String id) => tipos[id] ?? id;

  static bool reduzLiquido(String tipo) => tipo == vale || tipo == desconto;

  static bool aumentaLiquido(String tipo) => tipo == bonus;

  static bool exigeValor(String tipo) => tipo != observacao;
}
