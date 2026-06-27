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
  /// Auto enquanto digita: evita "a", "ar" fecharem a consulta cedo demais.
  static bool permiteAutoEnquantoDigita(
    String termo, {
    required bool matchCodigoBarras,
  }) {
    if (matchCodigoBarras) return true;
    final t = termo.trim();
    if (t.length < 3) return false;
    if (t.contains('%')) return false;
    return true;
  }
}
