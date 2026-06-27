import '../../model/venda.dart';

/// Ordena paradas do mesmo carro: [ordemEntrega] crescente; 0 ou igual vai ao desempate por id.
int compareVendaOrdemMesmoCarro(Venda a, Venda b) {
  final oa = a.ordemEntrega;
  final ob = b.ordemEntrega;
  if (oa > 0 && ob > 0 && oa != ob) return oa.compareTo(ob);
  if (oa > 0 && ob <= 0) return -1;
  if (oa <= 0 && ob > 0) return 1;
  return a.id.compareTo(b.id);
}

List<Venda> ordenarBlocoMesmoCarro(List<Venda> bloco) {
  final copy = List<Venda>.from(bloco);
  copy.sort(compareVendaOrdemMesmoCarro);
  return copy;
}

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
      ordenarBlocoMesmoCarro(
        ordenadas.where((x) => x.grupoEntregaFreteId == g).toList(),
      ),
    );
  }
  return blocos;
}

/// Nome do motorista na entrega (campo dedicado ou legado em observacao).
String nomeMotoristaEntrega(Venda venda) {
  if (venda.motoristaEntrega.trim().isNotEmpty) {
    return venda.motoristaEntrega.trim();
  }
  for (final linha in venda.observacaoEntrega.split('\n')) {
    final limpa = linha.trim();
    if (limpa.startsWith('Motorista:')) {
      final nome = limpa.substring('Motorista:'.length).trim();
      if (nome.isNotEmpty) return nome;
    }
  }
  return 'Nao definido';
}

/// Motorista informado no pedido (nao e o placeholder da UI).
bool motoristaLogisticaDefinido(String nomeMotorista) {
  final n = nomeMotorista.trim();
  return n.isNotEmpty && n != 'Nao definido';
}

int contarEntregasSemMotorista(List<Venda> entregas) => entregas
    .where((v) => !motoristaLogisticaDefinido(nomeMotoristaEntrega(v)))
    .length;

/// True quando ha 2+ clientes distintos entre as vendas (agrupamento multi-parada).
bool agrupamentoTemClientesDistintos(List<Venda> vendas) {
  if (vendas.length < 2) return false;
  final clientes = vendas.map((v) => v.cliente.targetId).where((id) => id > 0);
  return clientes.toSet().length > 1;
}

String rotuloGrupoLogistica(List<Venda> bloco) {
  final nums = bloco.map((v) {
    if (v.numeroOrcamento > 0) return '${v.numeroOrcamento}';
    return 'id ${v.id}';
  }).join(', ');
  final mot = nomeMotoristaEntrega(bloco.first);
  final prefixo = mot == 'Nao definido' ? 'Viagem' : '$mot — viagem';
  return '$prefixo · $nums';
}

/// Ordem para romaneio/rota do motorista: [ordemEntrega] global do dia, depois grupo.
int compararVendaRomaneioMotorista(Venda a, Venda b) {
  final oa = a.ordemEntrega;
  final ob = b.ordemEntrega;
  if (oa > 0 && ob > 0 && oa != ob) return oa.compareTo(ob);
  if (oa > 0 && ob <= 0) return -1;
  if (oa <= 0 && ob > 0) return 1;

  final ga = a.grupoEntregaFreteId;
  final gb = b.grupoEntregaFreteId;
  if (ga > 0 && ga == gb) return compareVendaOrdemMesmoCarro(a, b);
  if (ga > 0 && gb > 0 && ga != gb) return ga.compareTo(gb);
  if (ga > 0 && gb <= 0) return -1;
  if (ga <= 0 && gb > 0) return 1;
  return a.id.compareTo(b.id);
}

/// Paradas do motorista no dia, na ordem da rota (sem exigir agrupamento).
List<Venda> ordenarParadasMotoristaDia(List<Venda> paradas) {
  final copy = List<Venda>.from(paradas);
  copy.sort(compararVendaRomaneioMotorista);
  return copy;
}

List<Venda> filtrarVendasMotorista(List<Venda> base, String motorista) {
  final alvo = motorista.trim().toLowerCase();
  if (alvo.isEmpty) return const [];
  return base
      .where((v) => nomeMotoristaEntrega(v).toLowerCase() == alvo)
      .toList();
}

List<Venda> ordenarRomaneioMotorista(List<Venda> vendas) =>
    ordenarParadasMotoristaDia(vendas);

List<String> motoristasDistintosNasEntregas(List<Venda> entregas) {
  final set = <String>{};
  for (final v in entregas) {
    final m = nomeMotoristaEntrega(v);
    if (m != 'Nao definido') set.add(m);
  }
  final list = set.toList()
    ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
  return list;
}

/// Viagens (grupos) com 2+ pedidos ou grupo logico unico no dia filtrado.
List<List<Venda>> viagensAgrupadasNoDia(List<Venda> entregasDia) {
  return blocosEntregaComCarretoAgrupado(entregasDia)
      .where(
        (b) => b.length >= 2 && b.first.grupoEntregaFreteId > 0,
      )
      .toList();
}

int numeroParadaNaViagem(Venda venda, List<Venda> viagemOrdenada) {
  if (venda.grupoEntregaFreteId <= 0) return 0;
  if (venda.ordemEntrega > 0) return venda.ordemEntrega;
  final idx = viagemOrdenada.indexWhere((v) => v.id == venda.id);
  return idx < 0 ? 0 : idx + 1;
}
