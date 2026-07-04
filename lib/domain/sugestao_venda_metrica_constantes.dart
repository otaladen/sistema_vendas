/// Tipos de evento de metrica de sugestao de venda.
abstract final class SugestaoVendaMetricaTipo {
  static const exibiu = 'exibiu';
  static const aceitou = 'aceitou';
  static const ignorou = 'ignorou';
}

/// Canal onde a sugestao foi apresentada.
abstract final class SugestaoVendaMetricaCanal {
  static const insights = 'insights';
  static const faixaCarrinho = 'faixa_carrinho';
}

/// Origem da sugestao (cadastro manual ou historico).
abstract final class SugestaoVendaMetricaFonte {
  static const cadastro = 'cadastro';
  static const historico = 'historico';

  static String deAgregado({required bool historico, required bool cadastrado}) {
    if (historico) return SugestaoVendaMetricaFonte.historico;
    if (cadastrado) return SugestaoVendaMetricaFonte.cadastro;
    return SugestaoVendaMetricaFonte.cadastro;
  }
}
