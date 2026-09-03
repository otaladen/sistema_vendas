/// Parse da barra de pesquisa do PDV (`termo+`, `N termo`, etc.).
class PdvPesquisaComando {
  const PdvPesquisaComando({
    required this.termoBusca,
    this.quantidadeDireta,
    this.adicaoDireta = false,
  });

  final String termoBusca;
  final double? quantidadeDireta;
  final bool adicaoDireta;

  static PdvPesquisaComando parse(String textoOriginal) {
    final texto = textoOriginal.trim();
    if (texto.isEmpty) {
      return const PdvPesquisaComando(termoBusca: '');
    }

    final addDireto = RegExp(r'^\s*(.+?)\s*\+\s*$').firstMatch(texto);
    if (addDireto != null) {
      return PdvPesquisaComando(
        termoBusca: addDireto.group(1)!.trim(),
        adicaoDireta: true,
      );
    }

    final quantidadeDireta =
        RegExp(r'^\s*(\d{1,6}(?:[.,]\d{1,3})?)\s+(.+)$').firstMatch(texto);
    if (quantidadeDireta != null) {
      final bruto = quantidadeDireta.group(1)!;
      final qtd = double.tryParse(bruto.replaceAll(',', '.'));
      var termo = quantidadeDireta.group(2)!.trim();
      termo = termo.replaceFirst(RegExp(r'^de\s+', caseSensitive: false), '');
      if (qtd != null && qtd > 0 && qtd.isFinite && termo.isNotEmpty) {
        return PdvPesquisaComando(
          termoBusca: termo,
          quantidadeDireta: qtd,
        );
      }
    }

    return PdvPesquisaComando(termoBusca: texto);
  }
}
