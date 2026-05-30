import '../data/caixa_sessao_repository.dart';
import '../data/objectbox.dart';
import '../data/produto_repository.dart';
import '../data/venda_repository.dart';
import '../data/vendedor_repository.dart';
import '../domain/filtro_listagem_entregas.dart';
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
}

class LojaAoVivoService {
  LojaAoVivoService({
    required this.vendaRepository,
    required this.produtoRepository,
    required this.vendedorRepository,
    required this.objectBox,
  });

  final VendaRepository vendaRepository;
  final ProdutoRepository produtoRepository;
  final VendedorRepository vendedorRepository;
  final ObjectBox objectBox;

  Future<LojaAoVivoSnapshot> carregar() async {
    final agora = DateTime.now();
    final limites = calcularLimitesPeriodo(preset: 'hoje');
    final vendasHoje =
        relatorioVendasFinalizadasPeriodo(vendaRepository, limites);
    final faturamento =
        vendasHoje.fold<double>(0, (s, v) => s + v.total);
    final pico = relatorioCalcularHorariosPico(vendasHoje);

    final sessaoRepo = CaixaSessaoRepository();
    final terminalLocal = await sessaoRepo.obterTerminalId();
    final sessaoLocal = await sessaoRepo.carregarSessaoLocal();
    final todasSessoes = await sessaoRepo.listarTodasSessoes();
    final outroAberto = todasSessoes.entries.any(
      (e) => e.key != terminalLocal && e.value.aberto,
    );

    const filtroEnt = FiltroListagemEntregas(statusEntrega: 'todos');
    final entRes = vendaRepository.carregarListagemEntregasComResumo(
      filtroLista: filtroEnt,
      filtroContagem: filtroEnt.paraContagemResumo(),
    );
    final emAberto = entRes.entregas
        .where((v) => !relatorioEntregaStatusFinalizado(v.statusEntrega))
        .length;

    vendaRepository.titulos.migrarTitulosLegadoSeNecessario();
    final titulosAbertos = vendaRepository.titulos.listarTodosAbertos();
    final fiadoVencido = titulosAbertos
        .where(ContasReceberHelper.ehVencido)
        .fold<double>(0, (s, l) => s + l.titulo.saldo);

    final produtos = produtoRepository.listarTodos();
    var critico = 0;
    var zerado = 0;
    for (final p in produtos) {
      if (!p.ativo) continue;
      if (p.estoqueReal <= 0) zerado++;
      else if (p.estoqueReal < p.quantidadeMinima) critico++;
    }

    final orcs = vendaRepository.listarOrcamentosPendentes();
    final metas = _calcularMetas(vendasHoje, vendedorRepository.listarTodos());

    return LojaAoVivoSnapshot(
      vendasHoje: vendasHoje.length,
      faturamentoHoje: faturamento,
      horaPicoHoje: pico.horaPico,
      vendasHoraPico: pico.vendasNaHoraPico,
      caixaAberto: sessaoLocal.aberto,
      caixaOperador: sessaoLocal.operador,
      caixaTerminalId: terminalLocal,
      outroTerminalCaixaAberto: outroAberto,
      entregasAtrasadas: entRes.atrasadas,
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
  ) {
    final agora = DateTime.now();
    final diasNoMes = DateTime(agora.year, agora.month + 1, 0).day;
    final mapFat = <int, double>{};
    for (final v in vendasHoje) {
      final id = v.vendedor.targetId;
      mapFat[id] = (mapFat[id] ?? 0) + v.total;
    }
    final out = <MetaVendedorDiaria>[];
    for (final w in vendedores) {
      if (!w.ativo || w.metaMensalValor <= 0.001) continue;
      final metaDiaria = w.metaMensalValor / diasNoMes;
      final nome = w.apelido.trim().isNotEmpty ? w.apelido.trim() : w.nomeCompleto;
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
