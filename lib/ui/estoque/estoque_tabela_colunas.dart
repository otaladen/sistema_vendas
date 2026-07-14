/// Larguras compartilhadas entre cabecalho e linhas da tabela de estoque.
///
/// Valores pensados para cabecalhos legiveis (Disp./Media/Custo + icone de
/// ordenacao) e quantidades tipicas de loja de materiais.
abstract final class EstoqueTabelaColunas {
  EstoqueTabelaColunas._();

  static const double larguraSemaforo = 80;
  static const double larguraUn = 44;
  static const double larguraNum = 68;
  static const double larguraMedia = 76;
  static const double larguraPreco = 96;
  static const double larguraMargem = 60;
  static const double larguraCobertura = 56;
  static const double larguraAcao = 48;
  static const double larguraProdutoMin = 220;
  static const double alturaCabecalho = 34;
  static const double alturaLinha = 48;

  static double larguraMinima({required bool verCusto}) {
    return larguraSemaforo +
        larguraProdutoMin +
        larguraUn +
        (larguraNum * 5) +
        larguraMedia +
        larguraPreco +
        (verCusto ? larguraPreco + larguraMargem : 0) +
        larguraCobertura +
        larguraAcao;
  }
}
