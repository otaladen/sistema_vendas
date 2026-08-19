import '../../domain/reajuste_preco_lote.dart';
import '../../model/reajuste_preco.dart';
import '../../model/reajuste_preco_item.dart';
import '../../model/usuario_sistema.dart';
import '../sync/sync_entity_codec_operacional.dart';
import 'produto_api_repository.dart';
import 'lan_api_client.dart';

/// Reajuste de precos em lote via API do PC servidor.
class ReajustePrecoApiRepository {
  ReajustePrecoApiRepository(this._client, this._produtoRepository);

  final LanApiClient _client;
  final dynamic _produtoRepository;

  List<ReajustePreco> _historico = [];
  bool _historicoCarregado = false;
  final Map<int, List<ReajustePrecoItem>> _itensPorReajuste = {};

  Future<void> _hidratarHistorico({int limite = 100}) async {
    final raw = await _client.listarReajustes(limit: limite);
    _historico = raw.map(SyncEntityCodecOperacional.reajustePrecoDeMap).toList();
    _historicoCarregado = true;
  }

  List<ReajustePreco> listarHistorico({int limite = 100}) {
    if (!_historicoCarregado) {
      throw StateError(
        'Historico de reajustes: chame hidratarHistorico() antes no terminal.',
      );
    }
    return _historico.take(limite).toList(growable: false);
  }

  Future<void> hidratarHistorico({int limite = 100}) async {
    await _hidratarHistorico(limite: limite);
  }

  ReajustePreco? obterPorId(int id) {
    for (final r in _historico) {
      if (r.id == id) return r;
    }
    return null;
  }

  List<ReajustePrecoItem> listarItensDoReajuste(int reajusteId) {
    final cache = _itensPorReajuste[reajusteId];
    if (cache != null) return cache;
    throw StateError(
      'Itens do reajuste: chame hidratarItensDoReajuste($reajusteId) antes.',
    );
  }

  Future<void> hidratarItensDoReajuste(int reajusteId) async {
    final raw = await _client.listarItensReajuste(reajusteId);
    _itensPorReajuste[reajusteId] = raw
        .map(SyncEntityCodecOperacional.reajustePrecoItemDeMap)
        .toList(growable: false);
  }

  Future<ReajustePrecoLoteAplicacaoResultado> aplicarLote({
    required ReajustePrecoParametros parametros,
    required List<ReajustePrecoLinhaPreview> linhas,
    required UsuarioSistema usuario,
    String motivo = '',
  }) async {
    final m = await _client.aplicarReajusteLote({
      'usuarioLogin': usuario.login,
      'usuarioNome': usuario.nome,
      'motivo': motivo,
      'parametros': {
        'modo': ReajustePrecoParametros.codigoModo(parametros.modo),
        'tabelasCsv': parametros.tabelasCsv,
        'percentualSobrePreco': parametros.percentualSobrePreco,
        'margemPercentual': parametros.margemPercentual,
        'baseCusto':
            ReajustePrecoParametros.codigoBaseCusto(parametros.baseCusto),
        'arredondamento': ReajustePrecoParametros.codigoArredondamento(
          parametros.arredondamento,
        ),
        'protegerAbaixoCusto': parametros.naoAlterarSeAbaixoDoCusto,
        'somenteAtivos': parametros.somenteAtivos,
        'margemMinimaPercentual': parametros.margemMinimaPercentual,
      },
      'linhas': linhas
          .map(
            (l) => {
              'produtoId': l.produtoId,
              'codigoInterno': l.codigoInterno,
              'nome': l.nome,
              'precoCusto': l.precoCusto,
              'custoBaseCalculo': l.custoBaseCalculo,
              'preco1Antes': l.preco1Antes,
              'preco2Antes': l.preco2Antes,
              'preco3Antes': l.preco3Antes,
              'preco1Depois': l.preco1Depois,
              'preco2Depois': l.preco2Depois,
              'preco3Depois': l.preco3Depois,
              'seraAlterado': l.seraAlterado,
              'exigeAutorizacaoGerente': l.exigeAutorizacaoGerente,
              'motivoIgnorado': l.motivoIgnorado,
              'motivoAutorizacao': l.motivoAutorizacao,
            },
          )
          .toList(),
    });
    await _produtoRepositoryHidratar();
    await _hidratarHistorico();
    return ReajustePrecoLoteAplicacaoResultado(
      produtosGravados: (m['produtosGravados'] as num?)?.toInt() ?? 0,
      ignorados: (m['ignorados'] as num?)?.toInt() ?? 0,
      reajustePrecoId: (m['reajustePrecoId'] as num?)?.toInt() ?? 0,
    );
  }

  Future<ReajustePrecoLoteAplicacaoResultado> estornar({
    required int reajusteId,
    required UsuarioSistema usuario,
  }) async {
    final m = await _client.estornarReajuste(reajusteId, {
      'usuarioLogin': usuario.login,
      'usuarioNome': usuario.nome,
    });
    await _produtoRepositoryHidratar();
    await _hidratarHistorico();
    _itensPorReajuste.remove(reajusteId);
    return ReajustePrecoLoteAplicacaoResultado(
      produtosGravados: (m['produtosGravados'] as num?)?.toInt() ?? 0,
      ignorados: (m['ignorados'] as num?)?.toInt() ?? 0,
      reajustePrecoId: (m['reajustePrecoId'] as num?)?.toInt() ?? reajusteId,
    );
  }

  Future<void> _produtoRepositoryHidratar() async {
    final repo = _produtoRepository;
    if (repo is ProdutoApiRepository) {
      await repo.hidratar();
    }
  }
}
