import '../data/caixa_sessao_repository.dart';
import '../data/objectbox.dart';
import '../data/produto_repository.dart';
import '../data/sync/caixa_status_hub.dart';
import '../data/venda_repository.dart';
import '../data/vendedor_repository.dart';
import '../domain/filtro_listagem_entregas.dart';
import '../domain/permissao_usuario.dart';
import '../domain/usuario_permissao_helper.dart';
import '../model/caixa_sessao.dart';
import '../model/usuario_sistema.dart';
import '../model/venda.dart';
import '../model/vendedor.dart';
import '../domain/dashboard_alertas.dart';
import '../ui/relatorios/relatorio_entregas_helper.dart';
import '../ui/relatorios/relatorio_horarios_pico_helper.dart';
import '../ui/relatorios/relatorio_helpers.dart';
import '../ui/relatorios/relatorio_periodo.dart';

/// Snapshot operacional para o painel Loja ao Vivo.
class LojaAoVivoSnapshot {
  const LojaAoVivoSnapshot({
    required this.vendasHoje,
    required this.faturamentoHoje,
    required this.horaPicoHoje,
    required this.vendasHoraPico,
    required this.caixaAberto,
    required this.caixaOperador,
    required this.caixaTerminalId,
    required this.outroTerminalCaixaAberto,
    required this.entregasAtrasadas,
    required this.entregasEmAberto,
    required this.estoqueCritico,
    required this.estoqueZerado,
    required this.fiadoVencido,
    required this.orcamentosAbertos,
    required this.metasVendedores,
    required this.atualizadoEm,
  });

  final int vendasHoje;
  final double faturamentoHoje;
  final int horaPicoHoje;
  final int vendasHoraPico;
  final bool caixaAberto;
  final String caixaOperador;
  final String caixaTerminalId;
  final bool outroTerminalCaixaAberto;
  final int entregasAtrasadas;
  final int entregasEmAberto;
  final int estoqueCritico;
  final int estoqueZerado;
  final double fiadoVencido;
  final int orcamentosAbertos;
  final List<MetaVendedorDiaria> metasVendedores;
  final DateTime atualizadoEm;

  Map<String, dynamic> toMap() => {
        'vendasHoje': vendasHoje,
        'faturamentoHoje': faturamentoHoje,
        'horaPicoHoje': horaPicoHoje,
        'vendasHoraPico': vendasHoraPico,
        'caixaAberto': caixaAberto,
        'caixaOperador': caixaOperador,
        'caixaTerminalId': caixaTerminalId,
        'outroTerminalCaixaAberto': outroTerminalCaixaAberto,
        'entregasAtrasadas': entregasAtrasadas,
        'entregasEmAberto': entregasEmAberto,
        'estoqueCritico': estoqueCritico,
        'estoqueZerado': estoqueZerado,
        'fiadoVencido': fiadoVencido,
        'orcamentosAbertos': orcamentosAbertos,
        'metasVendedores': metasVendedores.map((m) => m.toMap()).toList(),
        'atualizadoEm': atualizadoEm.toIso8601String(),
      };

  static LojaAoVivoSnapshot fromMap(Map<String, dynamic> m) {
    final metasRaw = m['metasVendedores'];
    final metas = <MetaVendedorDiaria>[];
    if (metasRaw is List) {
      for (final e in metasRaw) {
        if (e is Map) {
          metas.add(MetaVendedorDiaria.fromMap(Map<String, dynamic>.from(e)));
        }
      }
    }
    return LojaAoVivoSnapshot(
      vendasHoje: (m['vendasHoje'] as num?)?.toInt() ?? 0,
      faturamentoHoje: (m['faturamentoHoje'] as num?)?.toDouble() ?? 0,
      horaPicoHoje: (m['horaPicoHoje'] as num?)?.toInt() ?? 0,
      vendasHoraPico: (m['vendasHoraPico'] as num?)?.toInt() ?? 0,
      caixaAberto: CaixaSessao.boolFrom(m['caixaAberto']),
      caixaOperador: (m['caixaOperador'] ?? '').toString(),
      caixaTerminalId: (m['caixaTerminalId'] ?? '').toString(),
      outroTerminalCaixaAberto:
          CaixaSessao.boolFrom(m['outroTerminalCaixaAberto']),
      entregasAtrasadas: (m['entregasAtrasadas'] as num?)?.toInt() ?? 0,
      entregasEmAberto: (m['entregasEmAberto'] as num?)?.toInt() ?? 0,
      estoqueCritico: (m['estoqueCritico'] as num?)?.toInt() ?? 0,
      estoqueZerado: (m['estoqueZerado'] as num?)?.toInt() ?? 0,
      fiadoVencido: (m['fiadoVencido'] as num?)?.toDouble() ?? 0,
      orcamentosAbertos: (m['orcamentosAbertos'] as num?)?.toInt() ?? 0,
      metasVendedores: metas,
      atualizadoEm: DateTime.tryParse((m['atualizadoEm'] ?? '').toString()) ??
          DateTime.now(),
    );
  }
}

class MetaVendedorDiaria {
  const MetaVendedorDiaria({
    required this.vendedorId,
    required this.nome,
    required this.metaDiaria,
    required this.realizadoHoje,
  });

  final int vendedorId;
  final String nome;
  final double metaDiaria;
  final double realizadoHoje;

  double get percentual =>
      metaDiaria <= 0.001 ? 0 : (realizadoHoje / metaDiaria).clamp(0, 2);

  Map<String, dynamic> toMap() => {
        'vendedorId': vendedorId,
        'nome': nome,
        'metaDiaria': metaDiaria,
        'realizadoHoje': realizadoHoje,
      };

  static MetaVendedorDiaria fromMap(Map<String, dynamic> m) =>
      MetaVendedorDiaria(
        vendedorId: (m['vendedorId'] as num?)?.toInt() ?? 0,
        nome: (m['nome'] ?? '').toString(),
        metaDiaria: (m['metaDiaria'] as num?)?.toDouble() ?? 0,
        realizadoHoje: (m['realizadoHoje'] as num?)?.toDouble() ?? 0,
      );
}

class LojaAoVivoService {
  LojaAoVivoService({
    required this.vendaRepository,
    required this.produtoRepository,
    required this.vendedorRepository,
    this.objectBox,
  });

  final VendaRepository vendaRepository;
  final ProdutoRepository produtoRepository;
  final VendedorRepository vendedorRepository;
  final ObjectBox? objectBox;

  Future<LojaAoVivoSnapshot> carregar({required UsuarioSistema usuario}) async {
    final verTotal =
        UsuarioPermissaoHelper.podeVerFaturamentoTotalLoja(usuario);
    final verMetasTodos =
        UsuarioPermissaoHelper.podeVerMetasVendedoresLoja(usuario);
    final verCaixa = UsuarioPermissaoHelper.tem(
      usuario,
      PermissaoUsuario.acessarCaixa,
    );
    final verEntregas =
        UsuarioPermissaoHelper.podeAcessarModuloEntregas(usuario);
    final verEstoque =
        UsuarioPermissaoHelper.tem(usuario, PermissaoUsuario.estoque);
    final verFinanceiro =
        UsuarioPermissaoHelper.tem(usuario, PermissaoUsuario.financeiro);
    final verOrcamentos =
        UsuarioPermissaoHelper.podeVerOrcamentosDashboard(usuario);

    final agora = DateTime.now();
    // Mesma regra do KPI "Vendas hoje" (finalizadaEm / dia civil local).
    late final List<Venda> vendasHojeBrutas;
    try {
      vendasHojeBrutas =
          List<Venda>.from(vendaRepository.listarVendasFinalizadasNoDiaLocal(agora));
    } catch (_) {
      final limites = calcularLimitesPeriodo(preset: 'hoje');
      vendasHojeBrutas =
          relatorioVendasFinalizadasPeriodo(vendaRepository, limites);
    }
    final vendasHoje = verTotal
        ? vendasHojeBrutas
        : vendasHojeBrutas
            .where((v) => v.vendedor.targetId == usuario.vendedorId)
            .toList();
    final limitesHoje = calcularLimitesPeriodo(preset: 'hoje');
    ImpactosDevolucaoTrocaPeriodo? impactosHoje;
    try {
      impactosHoje = vendaRepository.calcularImpactosDevolucaoTrocaPeriodo(
        relatorioPeriodoFiltro(limitesHoje),
      );
    } catch (_) {
      impactosHoje = null;
    }
    var faturamento = vendasHoje.fold<double>(0, (s, v) => s + v.total);
    if (impactosHoje != null) {
      if (verTotal) {
        faturamento += impactosHoje.impactoFaturamentoTotal;
      } else {
        faturamento +=
            impactosHoje.porVendedorFaturamento[usuario.vendedorId] ?? 0;
      }
    }
    final pico = relatorioCalcularHorariosPico(vendasHoje);

    final sessaoRepo = CaixaSessaoRepository();
    final terminalLocal = await sessaoRepo.obterTerminalId();
    final todasSessoes = await sessaoRepo.listarTodasSessoes();
    CaixaSessao? abertaLoja;
    for (final s in todasSessoes.values) {
      if (s.aberto) {
        abertaLoja = s;
        break;
      }
    }
    final hub = CaixaStatusHub.instance;
    final caixaAberto = verCaixa && (hub.lojaAberta || abertaLoja != null);
    final caixaOperador = !verCaixa
        ? ''
        : (hub.operador.isNotEmpty
            ? hub.operador
            : (abertaLoja?.operador ?? ''));
    final caixaTerminalId = !verCaixa
        ? ''
        : (hub.terminalId.isNotEmpty
            ? hub.terminalId
            : (abertaLoja?.terminalId ?? ''));
    final abertos = todasSessoes.values.where((s) => s.aberto).length;
    final outroAberto = verCaixa &&
        (abertos > 1 ||
            (abertaLoja != null &&
                abertaLoja.terminalId != terminalLocal &&
                abertos == 1));

    const filtroEnt = FiltroListagemEntregas(statusEntrega: 'todos');
    final entRes = verEntregas
        ? vendaRepository.carregarListagemEntregasComResumo(
            filtroLista: filtroEnt,
            filtroContagem: filtroEnt.paraContagemResumo(),
          )
        : null;
    final emAberto = entRes == null
        ? 0
        : entRes.entregas
            .where((v) => !relatorioEntregaStatusFinalizado(v.statusEntrega))
            .length;

    var fiadoVencido = 0.0;
    if (verFinanceiro) {
      vendaRepository.titulos.migrarTitulosLegadoSeNecessario();
      final titulosAbertos = vendaRepository.titulos.listarTodosAbertos();
      fiadoVencido = titulosAbertos
          .where(ContasReceberHelper.ehVencido)
          .fold<double>(0, (s, l) => s + l.titulo.saldo);
    }

    var critico = 0;
    var zerado = 0;
    if (verEstoque) {
      final produtos = produtoRepository.listarTodos();
      for (final p in produtos) {
        if (!p.ativo) continue;
        if (p.estoqueExibicao <= 0) {
          zerado++;
        } else if (p.estoqueExibicao < p.quantidadeMinima) {
          critico++;
        }
      }
    }

    final orcs = verOrcamentos
        ? vendaRepository.listarOrcamentosPendentes()
        : const <Venda>[];
    final metasBrutas = _calcularMetas(
      verMetasTodos ? vendasHojeBrutas : vendasHoje,
      vendedorRepository.listarTodos(),
      impactosHoje,
    );
    final metas = verMetasTodos
        ? metasBrutas
        : metasBrutas
            .where((m) => m.vendedorId == usuario.vendedorId)
            .toList();

    return LojaAoVivoSnapshot(
      vendasHoje: vendasHoje.length,
      faturamentoHoje: faturamento,
      horaPicoHoje: pico.horaPico,
      vendasHoraPico: pico.vendasNaHoraPico,
      caixaAberto: caixaAberto,
      caixaOperador: caixaOperador,
      caixaTerminalId: caixaTerminalId,
      outroTerminalCaixaAberto: outroAberto,
      entregasAtrasadas: entRes?.atrasadas ?? 0,
      entregasEmAberto: emAberto,
      estoqueCritico: critico,
      estoqueZerado: zerado,
      fiadoVencido: fiadoVencido,
      orcamentosAbertos: orcs.length,
      metasVendedores: metas,
      atualizadoEm: agora,
    );
  }

  List<MetaVendedorDiaria> _calcularMetas(
    List<Venda> vendasHoje,
    List<Vendedor> vendedores,
    ImpactosDevolucaoTrocaPeriodo? impactosHoje,
  ) {
    final agora = DateTime.now();
    final diasNoMes = DateTime(agora.year, agora.month + 1, 0).day;
    final mapFat = <int, double>{};
    for (final v in vendasHoje) {
      final id = v.vendedor.targetId;
      mapFat[id] = (mapFat[id] ?? 0) + v.total;
    }
    if (impactosHoje != null) {
      for (final e in impactosHoje.porVendedorFaturamento.entries) {
        mapFat[e.key] = (mapFat[e.key] ?? 0) + e.value;
      }
    }
    final out = <MetaVendedorDiaria>[];
    for (final w in vendedores) {
      if (!w.ativo || w.metaMensalValor <= 0.001) continue;
      final metaDiaria = w.metaMensalValor / diasNoMes;
      final nome =
          w.apelido.trim().isNotEmpty ? w.apelido.trim() : w.nomeCompleto;
      out.add(
        MetaVendedorDiaria(
          vendedorId: w.id,
          nome: nome,
          metaDiaria: metaDiaria,
          realizadoHoje: mapFat[w.id] ?? 0,
        ),
      );
    }
    out.sort((a, b) => b.realizadoHoje.compareTo(a.realizadoHoje));
    return out;
  }
}
