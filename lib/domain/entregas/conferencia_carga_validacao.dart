import '../../data/conferencia_carga_repository.dart';
import '../../model/venda.dart';
import '../entrega_venda_helper.dart';
import 'romaneio_carga_merge.dart';

/// Bloqueia "Saiu" no checklist quando o romaneio consolidado nao foi conferido.
abstract final class ConferenciaCargaValidacao {
  ConferenciaCargaValidacao._();

  static String escopoRomaneio(List<Venda> vendas) =>
      EntregaVendaHelper.escopoConferenciaCargaRomaneio(vendas);

  static void validarAntesMarcarSaiu({
    required ConferenciaCargaRepository repository,
    required List<Venda> vendasEscopo,
  }) {
    final escopo = escopoRomaneio(vendasEscopo);
    if (escopo.isEmpty) return;

    final linhas = RomaneioCargaMerge.montarLinhas(vendasEscopo);
    if (linhas.isEmpty) return;

    final mapa = repository.mapaPorEscopo(escopo);
    final pendentes = <String>[];
    for (final linha in linhas) {
      if (mapa[linha.chaveMerge] == true) continue;
      pendentes.add(
        '${linha.nomeProduto} · ${linha.quantidadeTotal} ${linha.unidade}',
      );
    }
    if (pendentes.isEmpty) return;

    throw StateError(
      'Nao foi possivel marcar "Saiu": conferencia de separacao incompleta.\n'
      'Marque todos os itens do romaneio no patio antes da saida do caminhao.\n'
      '${pendentes.join('\n')}',
    );
  }
}
