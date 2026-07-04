/// Larguras fixas compartilhadas entre cabecalho e linhas da tabela de estoque.
abstract final class EstoqueTabelaColunas {
  EstoqueTabelaColunas._();

  static const double larguraSemaforo = 72;
  static const double larguraUn = 36;
  static const double larguraNum = 46;
  static const double larguraMedia = 54;
  static const double larguraPreco = 78;
  static const double larguraAcao = 44;
  static const double larguraProdutoMin = 240;
  static const double alturaCabecalho = 30;
  static const double alturaLinha = 46;

  static double larguraMinima({required bool verCusto}) {
    return larguraSemaforo +
        larguraProdutoMin +
        larguraUn +
        (larguraNum * 5) +
        larguraMedia +
        larguraPreco +
        (verCusto ? larguraPreco : 0) +
        larguraAcao;
  }
}
