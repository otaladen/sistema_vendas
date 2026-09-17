import '../data/api/caixa_sessao_api.dart';
import '../data/api/lan_api_client.dart';
import '../data/caixa_auditoria_repository.dart';
import '../data/caixa_sessao_repository.dart';
import '../data/objectbox.dart';
import '../model/caixa_sessao.dart';
import 'sessao_caixa_referencia.dart';

/// Resultado paginado do catalogo de sessoes.
class SessaoCaixaCatalogoPagina {
  const SessaoCaixaCatalogoPagina({
    required this.sessoes,
    required this.totalEstimado,
    required this.proximoOffsetFechamentos,
    required this.temMais,
  });

  final List<SessaoCaixaReferencia> sessoes;
  final int totalEstimado;

  /// Offset para a proxima pagina de fechamentos (nao conta sessoes abertas).
  final int proximoOffsetFechamentos;
  final bool temMais;
}

/// Carrega sessoes de caixa sob demanda (nao traz milhares de uma vez).
abstract final class SessaoCaixaCatalogoLoader {
  SessaoCaixaCatalogoLoader._();

  static const int tamanhoPaginaPadrao = 40;

  /// Legado: evite em telas; prefira [carregarPagina].
  static Future<List<SessaoCaixaReferencia>> carregar({
    ObjectBox? objectBox,
    LanApiClient? lanApiClient,
    int limiteAuditoria = 500,
  }) async {
    final pagina = await carregarPagina(
      objectBox: objectBox,
      lanApiClient: lanApiClient,
      offset: 0,
      limit: limiteAuditoria,
    );
    return pagina.sessoes;
  }

  static Future<SessaoCaixaCatalogoPagina> carregarPagina({
    ObjectBox? objectBox,
    LanApiClient? lanApiClient,
    int offset = 0,
    int limit = tamanhoPaginaPadrao,
    DateTime? desde,
    bool incluirAbertas = true,
  }) async {
    final abertas = incluirAbertas && offset == 0
        ? await _sessoesAbertas(
            objectBox: objectBox,
            lanApiClient: lanApiClient,
          )
        : const <CaixaSessao>[];

    final List<CaixaAuditoriaRegistro> fechamentos;
    int total;
    if (lanApiClient != null && lanApiClient.configurado) {
      final raw = await lanApiClient.listarHistoricoFechamentoCaixa(
        limit: limit,
        offset: offset,
        desde: desde,
      );
      fechamentos = raw.map(CaixaAuditoriaRegistro.fromMap).toList();
      total = await lanApiClient.contarHistoricoFechamentoCaixa(desde: desde);
    } else {
      final repo = CaixaAuditoriaRepository(db: objectBox);
      fechamentos = await repo.listarFechamentosPaginado(
        offset: offset,
        limit: limit,
        desde: desde,
      );
      total = await repo.contarFechamentos(desde: desde);
    }

    final sessoes = await _montarSessoesDaPagina(
      objectBox: objectBox,
      fechamentos: fechamentos,
      sessoesAbertas: abertas,
      offset: offset,
    );
    final carregadosFechamentos = fechamentos.length;
    final temMais = offset + carregadosFechamentos < total;
    return SessaoCaixaCatalogoPagina(
      sessoes: sessoes,
      totalEstimado: total + (incluirAbertas && offset == 0 ? abertas.length : 0),
      proximoOffsetFechamentos: offset + carregadosFechamentos,
      temMais: temMais,
    );
  }

  static Future<List<SessaoCaixaReferencia>> _montarSessoesDaPagina({
    ObjectBox? objectBox,
    required List<CaixaAuditoriaRegistro> fechamentos,
    required List<CaixaSessao> sessoesAbertas,
    required int offset,
  }) async {
    final out = <SessaoCaixaReferencia>[];
    if (offset == 0) {
      for (final s in sessoesAbertas) {
        out.add(SessaoCaixaReferencia.deSessaoAberta(s, numero: 0));
      }
    }

    if (fechamentos.isEmpty) return out;

    final repo = CaixaAuditoriaRepository(db: objectBox);
    var maisAntigo = fechamentos.first.em;
    for (final f in fechamentos) {
      if (f.em.isBefore(maisAntigo)) maisAntigo = f.em;
    }
    final aberturas = await repo.listarAberturasCaixa(
      desde: maisAntigo.subtract(const Duration(days: 3)),
    );
    final fechamentosContexto = await repo.listarFechamentos();

    for (var i = 0; i < fechamentos.length; i++) {
      final f = fechamentos[i];
      final montadas = SessaoCaixaCatalogo.montarDeAuditoria([...aberturas, f]);
      SessaoCaixaReferencia? escolhida;
      final alvo = f.em.toUtc().millisecondsSinceEpoch;
      for (final s in montadas) {
        final fe = s.fechamentoEm;
        if (fe == null) continue;
        if ((fe.toUtc().millisecondsSinceEpoch - alvo).abs() <= 1000) {
          escolhida = s;
          break;
        }
      }
      out.add(
        SessaoCaixaReferencia.montarSessaoFechamento(
          fechamento: f,
          numero: fechamentos.length - i,
          aberturaPareada: escolhida?.aberturaEm,
          fechamentosContexto: fechamentosContexto,
        ),
      );
    }
    return out;
  }

  static Future<List<CaixaSessao>> _sessoesAbertas({
    ObjectBox? objectBox,
    LanApiClient? lanApiClient,
  }) async {
    if (lanApiClient != null && lanApiClient.configurado) {
      try {
        final snap = CaixaSessoesSnapshot.fromMap(
          await lanApiClient.listarCaixaSessoes(),
        );
        return snap.terminais.values.where((s) => s.aberto).toList();
      } catch (_) {
        return const [];
      }
    }
    final repo = CaixaSessaoRepository();
    final mapa = await repo.listarTodasSessoes();
    return mapa.values.where((s) => s.aberto).toList();
  }
}
