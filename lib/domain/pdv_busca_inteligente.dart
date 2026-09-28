import '../model/produto.dart';

/// Motivo da selecao automatica no PDV.
enum PdvBuscaAutoMotivo {
  codigoBarras,
  codigoInterno,
  unicoResultado,
}

/// Resultado da busca inteligente do PDV.
class PdvPesquisaResolvida {
  const PdvPesquisaResolvida({
    required this.produtos,
    required this.totalCorrespondencias,
    this.produtoAuto,
    this.motivoAuto,
  });

  final List<Produto> produtos;
  final int totalCorrespondencias;
  final Produto? produtoAuto;
  final PdvBuscaAutoMotivo? motivoAuto;

  bool get deveAutoSelecionar => produtoAuto != null;

  bool get ambiguo => totalCorrespondencias >= 2;

  static const vazia = PdvPesquisaResolvida(
    produtos: [],
    totalCorrespondencias: 0,
  );
}

/// Regras de quando auto-selecionar vs mostrar lista.
abstract final class PdvBuscaInteligenteHelper {
  /// Sem Enter, so adiciona sozinho o que veio do leitor de codigo de barras.
  /// Digitacao manual apenas filtra a lista, mesmo com resultado unico.
  static bool permiteAutoSemEnter(
    String termo, {
    required bool entradaViaLeitor,
  }) {
    if (!entradaViaLeitor) return false;
    final t = termo.trim();
    return t.isNotEmpty && !t.contains('%');
  }
}

/// Distingue leitor de codigo de barras (teclado emulado) de digitacao humana
/// pelo intervalo entre caracteres. Alimentar com cada mudanca do campo.
class DetectorEntradaLeitorCodigo {
  DetectorEntradaLeitorCodigo({
    this.intervaloMaximo = const Duration(milliseconds: 30),
    this.minimoCaracteres = 4,
    DateTime Function()? relogio,
  }) : _relogio = relogio ?? DateTime.now;

  final Duration intervaloMaximo;
  final int minimoCaracteres;
  final DateTime Function() _relogio;

  String _ultimoTexto = '';
  DateTime? _ultimoEm;

  /// Caracteres finais do campo que chegaram dentro de [intervaloMaximo] do anterior.
  int _rapidosConsecutivos = 0;

  void registrarTexto(String texto) {
    final agora = _relogio();
    final anterior = _ultimoTexto;
    final ultimoEm = _ultimoEm;
    _ultimoTexto = texto;
    _ultimoEm = agora;

    final acrescimo = texto.length - anterior.length;
    if (acrescimo <= 0 || !texto.startsWith(anterior)) {
      _rapidosConsecutivos = 0;
      return;
    }
    final rapido =
        ultimoEm != null && agora.difference(ultimoEm) < intervaloMaximo;
    // Lote de varios caracteres num unico evento: os internos sao simultaneos.
    _rapidosConsecutivos =
        (rapido ? _rapidosConsecutivos + 1 : 0) + (acrescimo - 1);
  }

  /// [termo] inteiro (exceto o 1o caractere, que chega apos uma pausa) veio em
  /// sequencia rapida.
  bool pareceLeitor(String termo) {
    final t = termo.trim();
    if (t.length < minimoCaracteres) return false;
    return _rapidosConsecutivos >= t.length - 1;
  }

  void reiniciar() {
    _ultimoTexto = '';
    _ultimoEm = null;
    _rapidosConsecutivos = 0;
  }
}
