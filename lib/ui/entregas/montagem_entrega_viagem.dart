import '../../model/venda.dart';
import 'logistica_entregas.dart';

import '../../domain/entrega_venda_helper.dart';

/// Escopo persistido da conferencia de carga (`g:grupo` ou `s:vendaId`).
String escopoViagemLogistica(List<Venda> vendas) =>
    EntregaVendaHelper.escopoConferenciaCargaRomaneio(vendas);

/// Uma viagem (grupo mesmo carro) ou entrega avulsa para o painel de montagem.
class MontagemEntregaViagem {
  const MontagemEntregaViagem({
    required this.chave,
    required this.vendas,
  });

  final String chave;
  final List<Venda> vendas;

  bool get ehGrupo =>
      vendas.length >= 2 && vendas.first.grupoEntregaFreteId > 0;

  int get grupoId => ehGrupo ? vendas.first.grupoEntregaFreteId : 0;

  String get rotulo => ehGrupo
      ? rotuloGrupoLogistica(vendas)
      : 'Pedido ${vendas.first.numeroOrcamento}';

  String get motorista => nomeMotoristaEntrega(vendas.first);

  List<Venda> get vendasOrdenadas => ordenarBlocoMesmoCarro(vendas);
}

List<MontagemEntregaViagem> montagemViagensDoMotorista(
  List<Venda> entregas,
  String motoristaNome,
) {
  final filtradas = filtrarVendasMotorista(entregas, motoristaNome);
  final ordenadas = ordenarParadasMotoristaDia(filtradas);
  final blocos = blocosEntregaComCarretoAgrupado(ordenadas);
  return blocos
      .map(
        (b) => MontagemEntregaViagem(
          chave: escopoViagemLogistica(b),
          vendas: b,
        ),
      )
      .toList();
}

List<String> montagemMotoristasDasEntregas(List<Venda> entregas) {
  final nomes = entregas.map(nomeMotoristaEntrega).toSet().toList();
  nomes.sort((a, b) {
    if (a == 'Nao definido') return 1;
    if (b == 'Nao definido') return -1;
    return a.toLowerCase().compareTo(b.toLowerCase());
  });
  return nomes;
}

int montagemProgressoCargaViagem(List<Venda> vendas) {
  if (vendas.isEmpty) return 0;
  if (vendas.every((v) => v.cargaSaiu)) return 3;
  if (vendas.every((v) => v.cargaCarregada)) return 2;
  if (vendas.every((v) => v.cargaSeparada)) return 1;
  return vendas.where((v) => v.cargaSeparada || v.cargaCarregada || v.cargaSaiu).isEmpty
      ? 0
      : 1;
}

bool montagemChecklistViagemCompleto(List<Venda> vendas) =>
    vendas.isNotEmpty && vendas.every((v) => v.cargaSeparada && v.cargaCarregada && v.cargaSaiu);
