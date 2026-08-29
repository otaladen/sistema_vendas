import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';

import '../../../data/sync/sync_entity_codec_extras.dart';
import '../../../data/vale_credito_repository.dart';
import '../../../model/vale_credito.dart';
import '../lan_api_deps.dart';
import '../lan_api_json.dart';

/// Alem do codec de sync, o terminal precisa do nome do cliente para mostrar
/// de quem e o vale sem ter que buscar o cadastro.
Map<String, dynamic> _valeParaMap(ValeCredito v) {
  final m = SyncEntityCodecExtras.valeCreditoParaMap(v);
  m['clienteNome'] = v.cliente.target?.rotuloExibicao() ?? '';
  return m;
}

void registerValesRoutes(Router router, LanApiDeps d) {
  final ValeCreditoRepository repo = d.valeCreditoRepository;

  router.get('/api/vales/codigo/<codigo>', (Request r, String codigo) {
    final vale = repo.buscarPorCodigo(codigo);
    if (vale == null) {
      return lanApiJson({'error': 'Vale nao encontrado.'}, status: 404);
    }
    return lanApiJson({'item': _valeParaMap(vale)});
  });

  router.get('/api/vales/cliente/<id|[0-9]+>', (Request r, String id) {
    final clienteId = int.tryParse(id) ?? 0;
    final somenteGastaveis = r.url.queryParameters['gastaveis'] != 'false';
    final itens = somenteGastaveis
        ? repo.listarGastaveisDoCliente(clienteId)
        : repo.listarPorCliente(clienteId);
    return lanApiJson({'items': itens.map(_valeParaMap).toList()});
  });

  router.post('/api/vales', (Request r) async {
    final body = await lanApiReadJsonMap(r);
    if (body == null) {
      return lanApiJson({'error': 'JSON invalido'}, status: 400);
    }
    try {
      final temValidade = body.containsKey('validadeDias');
      final vale = repo.emitir(
        valor: (body['valor'] as num?)?.toDouble() ?? 0,
        emitidoPor: (body['emitidoPor'] ?? 'sistema').toString(),
        vendaOrigemId: (body['vendaOrigemId'] as num?)?.toInt() ?? 0,
        registroDevolucaoId:
            (body['registroDevolucaoId'] as num?)?.toInt() ?? 0,
        clienteId: (body['clienteId'] as num?)?.toInt() ?? 0,
        numeroVendaOrigem: (body['numeroVendaOrigem'] as num?)?.toInt() ?? 0,
        observacao: (body['observacao'] ?? '').toString(),
        validadeDias: temValidade
            ? (body['validadeDias'] as num?)?.toInt()
            : ValeCreditoRepository.validadeDiasPadrao,
      );
      d.notificar('vale_credito', ids: [vale.id]);
      return lanApiJson({'ok': true, 'item': _valeParaMap(vale)});
    } catch (e) {
      return lanApiJson({'error': '$e'}, status: 400);
    }
  });

  router.post('/api/vales/<id|[0-9]+>/resgatar', (Request r, String id) async {
    final body = await lanApiReadJsonMap(r) ?? <String, dynamic>{};
    try {
      final valeId = int.parse(id);
      final uso = repo.resgatar(
        valeId: valeId,
        valor: (body['valor'] as num?)?.toDouble() ?? 0,
        registradoPor: (body['registradoPor'] ?? 'sistema').toString(),
        vendaId: (body['vendaId'] as num?)?.toInt() ?? 0,
        numeroVenda: (body['numeroVenda'] as num?)?.toInt() ?? 0,
      );
      d.notificar('vale_credito', ids: [valeId]);
      final vale = repo.obterPorId(valeId);
      return lanApiJson({
        'ok': true,
        'usoId': uso.id,
        'item': vale == null ? null : _valeParaMap(vale),
      });
    } on StateError catch (e) {
      return lanApiJson({'error': e.message}, status: 400);
    } catch (e) {
      return lanApiJson({'error': '$e'}, status: 400);
    }
  });

  router.post('/api/vales/<id|[0-9]+>/cancelar', (Request r, String id) async {
    final body = await lanApiReadJsonMap(r) ?? <String, dynamic>{};
    try {
      final valeId = int.parse(id);
      final vale = repo.cancelar(
        valeId: valeId,
        motivo: (body['motivo'] ?? '').toString(),
        canceladoPor: (body['canceladoPor'] ?? 'sistema').toString(),
      );
      d.notificar('vale_credito', ids: [valeId]);
      return lanApiJson({'ok': true, 'item': _valeParaMap(vale)});
    } on StateError catch (e) {
      return lanApiJson({'error': e.message}, status: 400);
    } catch (e) {
      return lanApiJson({'error': '$e'}, status: 400);
    }
  });

  /// Devolve ao vale o que foi gasto numa venda cancelada.
  router.post('/api/vales/estornar-venda/<id|[0-9]+>', (
    Request r,
    String id,
  ) async {
    try {
      final vendaId = int.parse(id);
      final total = repo.estornarUsosDaVenda(vendaId);
      d.notificar('vale_credito');
      return lanApiJson({'ok': true, 'estornado': total});
    } catch (e) {
      return lanApiJson({'error': '$e'}, status: 400);
    }
  });
}
