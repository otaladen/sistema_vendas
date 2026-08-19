import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';

import '../../../data/caixa_sessao_repository.dart';
import '../../../data/sugestao_venda_metrica_repository.dart';
import '../../../data/sync/sync_entity_codec.dart';
import '../../../data/sync/sync_entity_codec_extras.dart';
import '../../../data/sync/sync_entity_codec_operacional.dart';
import '../../../data/venda_repository.dart';
import '../../../domain/financeiro_resumo.dart';
import '../../../domain/loja_ao_vivo_service.dart';
import '../../../model/usuario_sistema.dart';
import '../../../model/venda.dart';
import '../lan_api_deps.dart';
import '../lan_api_json.dart';

/// Dados agregados que o terminal leve usa nos relatorios / dashboard.
void registerRelatoriosRoutes(Router router, LanApiDeps d) {
  router.get('/api/devolucoes', (Request r) {
    final desde = lanApiQueryDate(r, 'desde') ?? DateTime.utc(1970);
    final ate = lanApiQueryDate(r, 'ate') ?? DateTime.now().toUtc();
    final items = d.vendaRepository.listarRegistrosDevolucaoPorPeriodo(
      PeriodoFiltro(inicio: desde, fim: ate),
    );
    return lanApiJson({
      'items': items.map((reg) {
        final m = SyncEntityCodecExtras.registroDevolucaoParaMap(reg);
        final origemId = reg.vendaOrigem.targetId;
        final origem = origemId > 0 ? d.objectBox.vendaBox.get(origemId) : null;
        m['impactoFaturamento'] =
            d.vendaRepository.impactoFaturamentoRegistro(reg);
        m['impactoLucro'] = d.vendaRepository.impactoLucroRegistro(reg);
        m['vendedorId'] = origem?.vendedor.targetId ?? 0;
        m['clienteId'] = origem?.cliente.targetId ?? 0;
        return m;
      }).toList(),
    });
  });

  router.get('/api/entregas/historico', (Request r) {
    final items = d.vendaRepository.listarHistoricoEntregaGlobal(
      inicio: lanApiQueryDate(r, 'desde'),
      fim: lanApiQueryDate(r, 'ate'),
      termoBusca: (r.url.queryParameters['termo'] ?? '').trim(),
    );
    return lanApiJson({
      'items':
          items.map(SyncEntityCodecExtras.historicoEntregaParaMap).toList(),
    });
  });

  router.get('/api/dashboard/resumo', (Request r) async {
    // Calendario local do servidor (nao UTC) — alinhado ao painel do PC.
    final ref = _diaCalendarioLocal(r, 'dia') ?? DateTime.now();
    final inicio = DateTime(ref.year, ref.month, ref.day);
    final fim = DateTime(ref.year, ref.month, ref.day, 23, 59, 59, 999);
    final vendedorIdRaw = r.url.queryParameters['vendedorId'];
    final vendedorId =
        vendedorIdRaw != null ? (int.tryParse(vendedorIdRaw) ?? 0) : null;
    // Mesma fonte da Listagem de vendas (periodo "hoje").
    final filtro = FiltroListagemVendas(
      textoBusca: '',
      dataInicioUtc: inicio.toUtc(),
      dataFimUtc: fim.toUtc(),
      filtroCancelamento: 'ativas',
      canceladaPorFiltro: 'todos',
      formaPagamento: 'todos',
      tipoEntrega: 'todos',
      entregaPendente: 'todos',
      filtroFiscal: 'todos',
      vendedorId: vendedorId,
    );
    final byId = <int, Venda>{
      for (final v in d.vendaRepository.listarListagemVendasCompleto(filtro))
        v.id: v,
    };
    for (final v in d.vendaRepository.listarVendasFinalizadasNoDiaLocal(ref)) {
      if (vendedorId != null && v.vendedor.targetId != vendedorId) continue;
      byId.putIfAbsent(v.id, () => v);
    }
    final lista = byId.values.toList();
    var faturamento = 0.0;
    for (final v in lista) {
      faturamento += v.total;
    }
    final contagem = d.vendaRepository.contarEntregasPainelResumo();
    var caixaAberto = false;
    var abertosCount = 0;
    try {
      final sessoes = await CaixaSessaoRepository().listarTodasSessoes();
      abertosCount = sessoes.values.where((s) => s.aberto).length;
      caixaAberto = abertosCount > 0;
    } catch (_) {}
    final fin = FinanceiroResumoService.montar(
      vendaRepository: d.vendaRepository,
      objectBox: d.objectBox,
    );
    return lanApiJson({
      'vendasHoje': lista.length,
      'faturamentoHoje': faturamento,
      'caixaAberto': caixaAberto,
      'caixaAbertosCount': abertosCount,
      'entregasEmAberto': contagem.emAberto,
      'entregasAtrasadas': contagem.atrasadas,
      'totalAReceber': fin.totalAReceber,
      'aReceberVencido': fin.aReceberVencido,
      'items': lista.map(SyncEntityCodec.vendaParaMap).toList(),
    });
  });

  /// Painel Loja ao vivo (KPIs + metas) — mesmo calculo do PC servidor.
  router.get('/api/loja-ao-vivo', (Request r) async {
    final login = (r.url.queryParameters['login'] ?? '').trim().toLowerCase();
    UsuarioSistema? usuario;
    if (login.isNotEmpty) {
      final todos = await d.usuarioRepository.listarTodos();
      for (final u in todos) {
        if (u.login.trim().toLowerCase() == login) {
          usuario = u;
          break;
        }
      }
    }
    usuario ??= const UsuarioSistema(
      id: 'api',
      login: 'api',
      nome: 'API',
      senha: '',
      ativo: true,
      admin: true,
      perfil: 'dono',
    );
    final snap = await LojaAoVivoService(
      vendaRepository: d.vendaRepository,
      produtoRepository: d.produtoRepository,
      vendedorRepository: d.vendedorRepository,
      objectBox: d.objectBox,
    ).carregar(usuario: usuario);
    return lanApiJson(snap.toMap());
  });

  router.get('/api/relatorios/metas-vendedores', (Request r) {
    final agora = DateTime.now();
    final diaQuery = lanApiQueryDate(r, 'dia');
    final diaRef = diaQuery == null
        ? agora
        : DateTime(diaQuery.year, diaQuery.month, diaQuery.day);
    final vendas = d.vendaRepository.listarVendasFinalizadasNoDiaLocal(diaRef);
    final mapFat = <int, double>{};
    for (final v in vendas) {
      final id = v.vendedor.targetId;
      if (id <= 0) continue;
      mapFat[id] = (mapFat[id] ?? 0) + v.total;
    }
    final inicioDia = DateTime(diaRef.year, diaRef.month, diaRef.day);
    final fimDia = DateTime(diaRef.year, diaRef.month, diaRef.day, 23, 59, 59, 999);
    final impactos = d.vendaRepository.calcularImpactosDevolucaoTrocaPeriodo(
      PeriodoFiltro(inicio: inicioDia, fim: fimDia),
    );
    for (final e in impactos.porVendedorFaturamento.entries) {
      if (e.key <= 0) continue;
      mapFat[e.key] = (mapFat[e.key] ?? 0) + e.value;
    }
    final diasNoMes = DateTime(agora.year, agora.month + 1, 0).day;
    final items = <Map<String, dynamic>>[];
    for (final w in d.vendedorRepository.listarTodos()) {
      if (!w.ativo || w.metaMensalValor <= 0.001) continue;
      final metaDiaria = w.metaMensalValor / diasNoMes;
      final nome =
          w.apelido.trim().isNotEmpty ? w.apelido.trim() : w.nomeCompleto;
      final realizado = mapFat[w.id] ?? 0;
      items.add({
        'vendedorId': w.id,
        'nome': nome,
        'metaDiaria': metaDiaria,
        'realizadoHoje': realizado,
        'percentual': metaDiaria > 0 ? (realizado / metaDiaria) * 100 : 0,
        'falta': (metaDiaria - realizado).clamp(0, double.infinity),
      });
    }
    items.sort(
      (a, b) => ((b['percentual'] as num).toDouble())
          .compareTo((a['percentual'] as num).toDouble()),
    );
    return lanApiJson({
      'dia': DateTime(diaRef.year, diaRef.month, diaRef.day).toIso8601String(),
      'items': items,
    });
  });

  router.get('/api/relatorios/sugestoes-venda', (Request r) {
    final desde = lanApiQueryDate(r, 'desde') ??
        DateTime.now().toUtc().subtract(const Duration(days: 30));
    final ate = lanApiQueryDate(r, 'ate') ?? DateTime.now().toUtc();
    final limit = lanApiQueryInt(r, 'limit', fallback: 200);
    final ranking = SugestaoVendaMetricaRepository(d.objectBox).listarRanking(
      inicio: desde,
      fim: ate,
      limite: limit,
    );
    return lanApiJson({
      'items': ranking
          .map(
            (l) => {
              'produtoOrigemId': l.produtoOrigemId,
              'produtoSugeridoId': l.produtoSugeridoId,
              'fonte': l.fonte,
              'exibicoes': l.exibicoes,
              'aceites': l.aceites,
              'ignorados': l.ignorados,
            },
          )
          .toList(),
    });
  });

  router.get('/api/auditoria', (Request r) {
    final limit = lanApiQueryInt(r, 'limit', fallback: 500);
    final desde = lanApiQueryDate(r, 'desde');
    final ate = lanApiQueryDate(r, 'ate');
    try {
      var items = d.objectBox.auditoriaEventoBox.getAll();
      if (desde != null) {
        items = items.where((e) => !e.dataHora.isBefore(desde)).toList();
      }
      if (ate != null) {
        final fim = DateTime.utc(ate.year, ate.month, ate.day, 23, 59, 59);
        items = items.where((e) => !e.dataHora.isAfter(fim)).toList();
      }
      items.sort((a, b) => b.dataHora.compareTo(a.dataHora));
      return lanApiJson({
        'items': items
            .take(limit)
            .map(SyncEntityCodecOperacional.auditoriaEventoParaMap)
            .toList(),
        'total': items.length,
      });
    } catch (e) {
      return lanApiJson({'error': '$e', 'items': []}, status: 501);
    }
  });
}

/// Extrai Y-M-D do query sem forcar fuso UTC (evita "hoje" errado no BR).
DateTime? _diaCalendarioLocal(Request r, String key) {
  final s = (r.url.queryParameters[key] ?? '').trim();
  if (s.isEmpty) return null;
  final m = RegExp(r'^(\d{4})-(\d{2})-(\d{2})').firstMatch(s);
  if (m != null) {
    final y = int.tryParse(m[1]!);
    final mo = int.tryParse(m[2]!);
    final d = int.tryParse(m[3]!);
    if (y != null && mo != null && d != null) {
      return DateTime(y, mo, d);
    }
  }
  final parsed = DateTime.tryParse(s);
  if (parsed == null) return null;
  final local = parsed.toLocal();
  return DateTime(local.year, local.month, local.day);
}
