import 'nfe_recebida.dart';

/// Filtros locais da listagem de NF-e recebidas.
class NfeRecebidasFiltro {
  const NfeRecebidasFiltro({
    this.textoBusca = '',
    this.dataInicio,
    this.dataFim,
  });

  final String textoBusca;
  final DateTime? dataInicio;
  final DateTime? dataFim;
}

abstract final class NfeRecebidasFiltroUtil {
  NfeRecebidasFiltroUtil._();

  static List<NfeRecebida> aplicar(
    List<NfeRecebida> origem,
    NfeRecebidasFiltro filtro,
  ) {
    final texto = filtro.textoBusca.trim().toLowerCase();
    final docBusca = texto.replaceAll(RegExp(r'\D'), '');

    return [
      for (final n in origem)
        if (_passaBusca(n, texto, docBusca) && _passaPeriodo(n, filtro)) n,
    ];
  }

  static bool _passaBusca(NfeRecebida n, String texto, String docBusca) {
    if (texto.isEmpty) return true;
    if (n.nomeEmitente.toLowerCase().contains(texto)) return true;
    if (n.chaveNfe.contains(texto.replaceAll(RegExp(r'\s'), ''))) return true;
    if (docBusca.length >= 4) {
      final cnpj = n.documentoEmitente.replaceAll(RegExp(r'\D'), '');
      if (cnpj.contains(docBusca)) return true;
    }
    return false;
  }

  static bool _passaPeriodo(NfeRecebida n, NfeRecebidasFiltro filtro) {
    final emissao = n.dataEmissao;
    if (emissao == null) {
      return filtro.dataInicio == null && filtro.dataFim == null;
    }
    final dia = DateTime(emissao.year, emissao.month, emissao.day);
    if (filtro.dataInicio != null) {
      final ini = DateTime(
        filtro.dataInicio!.year,
        filtro.dataInicio!.month,
        filtro.dataInicio!.day,
      );
      if (dia.isBefore(ini)) return false;
    }
    if (filtro.dataFim != null) {
      final fim = DateTime(
        filtro.dataFim!.year,
        filtro.dataFim!.month,
        filtro.dataFim!.day,
      );
      if (dia.isAfter(fim)) return false;
    }
    return true;
  }
}
