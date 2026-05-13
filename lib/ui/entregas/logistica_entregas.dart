import '../../model/venda.dart';

/// Mantem a ordem de [ordenadas]; vendas com o mesmo [grupoEntregaFreteId] > 0 ficam no mesmo bloco.
List<List<Venda>> blocosEntregaComCarretoAgrupado(List<Venda> ordenadas) {
  final vistos = <int>{};
  final blocos = <List<Venda>>[];
  for (final v in ordenadas) {
    final g = v.grupoEntregaFreteId;
    if (g <= 0) {
      blocos.add([v]);
      continue;
    }
    if (vistos.contains(g)) {
      continue;
    }
    vistos.add(g);
    blocos.add(
      ordenadas.where((x) => x.grupoEntregaFreteId == g).toList(),
    );
  }
  return blocos;
}

String rotuloGrupoLogistica(List<Venda> bloco) {
  final nums = bloco.map((v) {
    if (v.numeroOrcamento > 0) return '${v.numeroOrcamento}';
    return 'id ${v.id}';
  }).join(', ');
  return 'Mesmo carro · $nums';
}
