import '../model/venda.dart';
import 'venda_documento_rotulo_helper.dart';
import 'venda_finalizacao_caixa_helper.dart';

/// Prioridade de busca numerica na Listagem de Vendas.
///
/// Digitos puros (ex.: `1255`) mostram so o numero visivel na listagem:
/// 0 = coluna # (controle interno).
/// 1 = NFC-e / NF-e autorizada, inclusive com zeros a esquerda.
/// O id interno do banco nao conta quando o controle exibido e outro.
abstract final class ListagemVendasBuscaRelevancia {
  ListagemVendasBuscaRelevancia._();

  static final _somenteDigitos = RegExp(r'^\d+$');
  static final _naoDigitos = RegExp(r'\D');

  static const int scoreControleExato = 0;
  static const int scoreDocumentoExato = 1;
  static const int scoreParcial = 2;

  /// `true` quando o operador digitou so numeros (ex.: `892`).
  static bool buscaSomenteNumeros(String textoBusca) =>
      numeroBusca(textoBusca) != null;

  static int? numeroBusca(String textoBusca) {
    final t = textoBusca.trim();
    if (t.isEmpty || !_somenteDigitos.hasMatch(t)) return null;
    return int.tryParse(t);
  }

  /// Controle, ID ou numero fiscal iguais a [textoBusca].
  static bool correspondeExato(Venda venda, String textoBusca) {
    final n = numeroBusca(textoBusca);
    if (n == null) return false;
    return _controleExato(venda, n) || _documentoExato(venda, n);
  }

  /// Remove vendas que so contem a sequencia (chave, produto, numero parcial).
  /// Sem busca numerica, devolve [vendas].
  static List<Venda> somenteCorrespondenciasExatas(
    List<Venda> vendas, {
    required String textoBusca,
  }) {
    if (numeroBusca(textoBusca) == null) return vendas;
    return vendas.where((v) => correspondeExato(v, textoBusca)).toList();
  }

  static int score(Venda venda, String textoBusca) {
    final n = numeroBusca(textoBusca);
    if (n == null) return scoreParcial;
    if (_controleExato(venda, n)) return scoreControleExato;
    if (_documentoExato(venda, n)) return scoreDocumentoExato;
    return scoreParcial;
  }

  /// Compara so a faixa de relevancia (0 se a busca nao for numerica).
  static int compararScore(Venda a, Venda b, String textoBusca) {
    if (numeroBusca(textoBusca) == null) return 0;
    return score(a, textoBusca).compareTo(score(b, textoBusca));
  }

  /// Reordena a listagem filtrada: Controle/ID exato, documento exato, resto
  /// por data de finalizacao decrescente. Sem busca numerica, devolve [vendas].
  static List<Venda> ordenar(
    List<Venda> vendas, {
    required String textoBusca,
  }) {
    if (numeroBusca(textoBusca) == null) return vendas;
    final copia = [...vendas];
    copia.sort((a, b) {
      final relev = compararScore(a, b, textoBusca);
      if (relev != 0) return relev;
      return VendaFinalizacaoCaixaHelper.momentoFinalizacao(b).compareTo(
        VendaFinalizacaoCaixaHelper.momentoFinalizacao(a),
      );
    });
    return copia;
  }

  static bool _controleExato(Venda venda, int n) {
    if (n <= 0) return false;
    final interno = VendaDocumentoRotuloHelper.numeroControleInterno(venda);
    if (interno > 0) return interno == n;
    return venda.id == n;
  }

  static bool _documentoExato(Venda venda, int n) {
    if (_numeroDocumentoIgual(venda.nfceNumero, n)) return true;
    if (!venda.nfe55Autorizada) return false;
    return _numeroDocumentoIgual(venda.nfeNumero, n);
  }

  static bool _numeroDocumentoIgual(String bruto, int n) {
    final d = bruto.replaceAll(_naoDigitos, '');
    if (d.isEmpty) return false;
    return int.tryParse(d) == n;
  }
}
