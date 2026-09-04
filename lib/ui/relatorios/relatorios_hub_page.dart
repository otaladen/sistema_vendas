import 'dart:async';

import 'package:flutter/material.dart';

import '../../data/api/auditoria_api_repository.dart';
import '../../data/api/sugestao_venda_metrica_api_repository.dart';
import '../../data/api/venda_api_repository.dart';
import '../../data/app_config_repository.dart';
import '../../data/conta_pagar_repository.dart';
import '../../data/objectbox.dart';
import '../../data/auditoria_repository.dart';
import '../../data/sugestao_venda_metrica_repository.dart';
import '../../domain/permissao_usuario.dart';
import '../../domain/usuario_permissao_helper.dart';
import '../../model/usuario_sistema.dart';
import '../financeiro/relatorio_contas_pagar_page.dart';
import '../relatorio_fiados_page.dart';
import '../shell/main_menu_deps.dart';
import '../widgets/hub_nav_button.dart';
import '../widgets/relatorios/relatorio_hub_secao.dart';
import 'relatorio_comissao_vendedores_page.dart';
import '../theme/app_relatorio_cores.dart';
import 'relatorio_curva_abc_page.dart';
import 'relatorio_dashboard_executivo_page.dart';
import 'relatorio_devolucoes_page.dart';
import 'relatorio_entregas_resumo_page.dart';
import 'relatorio_historico_entregas_page.dart';
import 'relatorio_movimentacao_estoque_page.dart';
import 'relatorio_pendencias_entrega_page.dart';
import 'relatorio_estoque_minimo_page.dart';
import 'relatorio_historico_fechamento_page.dart';
import 'relatorio_horarios_pico_page.dart';
import 'relatorio_metas_vendedores_page.dart';
import 'relatorio_log_sistema_page.dart';
import 'relatorio_produtos_mais_vendidos_page.dart';
import 'relatorio_saidas_produto_page.dart';
import 'relatorio_sugestoes_venda_page.dart';
import 'relatorio_tabela_precos_page.dart';
import 'relatorio_vendas_promocao_page.dart';
import '../../data/promocao_repository.dart';
import 'relatorio_top_clientes_page.dart';
import 'relatorio_vendas_periodo_page.dart';
import 'relatorio_vendas_por_vendedor_page.dart';
import 'relatorio_margem_markup_page.dart';
import 'relatorio_performance_entregas_page.dart';
import '../fiscal/relatorio_fiscal_mensal_page.dart';
import '../sugestao_compra_page.dart';

/// Item do hub de relatorios (categoria + metadados para busca).
class _RelatorioHubItem {
  const _RelatorioHubItem({
    required this.categoriaId,
    required this.categoriaTitulo,
    required this.categoriaIcone,
    required this.icon,
    required this.relatorioCor,
    required this.titulo,
    required this.subtitulo,
    required this.palavrasChave,
    required this.onTap,
  });

  final String categoriaId;
  final String categoriaTitulo;
  final IconData categoriaIcone;
  final IconData icon;
  final AppRelatorioId relatorioCor;
  final String titulo;
  final String subtitulo;
  final List<String> palavrasChave;
  final VoidCallback onTap;
}

/// Hub de relatorios gerenciais (material de construcao) — categorizado + busca.
class RelatoriosPage extends StatefulWidget {
  const RelatoriosPage({
    super.key,
    required this.vendaRepository,
    required this.clienteRepository,
    required this.vendedorRepository,
    required this.produtoRepository,
    required this.appConfigRepository,
    required this.usuarioLogado,
    required this.usuarioAdmin,
    this.usuarioLogin = '',
    this.onAbrirModuloEntregas,
    this.onAbrirModuloCaixa,
  });

  final dynamic vendaRepository;
  final dynamic clienteRepository;
  final dynamic vendedorRepository;
  final dynamic produtoRepository;
  final AppConfigRepository appConfigRepository;
  final UsuarioSistema usuarioLogado;
  final bool usuarioAdmin;
  final String usuarioLogin;
  final VoidCallback? onAbrirModuloEntregas;
  final VoidCallback? onAbrirModuloCaixa;

  @override
  State<RelatoriosPage> createState() => _RelatoriosPageState();
}

class _RelatoriosPageState extends State<RelatoriosPage> {
  final _buscaController = TextEditingController();
  final _buscaFocus = FocusNode();

  static const _ordemCategorias = [
    'executivo',
    'financeiro',
    'vendas',
    'clientes',
    'produtos',
    'operacional',
  ];

  /// No terminal leve os relatorios trabalham sobre uma janela baixada da API.
  static const _mesesJanelaTerminal = 13;
  bool _carregandoJanela = false;
  String _erroJanela = '';

  @override
  void initState() {
    super.initState();
    if (widget.vendaRepository is VendaApiRepository) {
      unawaited(_carregarJanelaTerminal());
    }
  }

  Future<void> _carregarJanelaTerminal() async {
    final repo = widget.vendaRepository as VendaApiRepository;
    final hoje = DateTime.now();
    final inicio = DateTime(
      hoje.year,
      hoje.month - _mesesJanelaTerminal + 1,
      1,
    );
    setState(() {
      _carregandoJanela = true;
      _erroJanela = '';
    });
    try {
      await repo.garantirPeriodoRelatorioCarregado(inicio, hoje);
      if (!mounted) return;
      setState(() => _carregandoJanela = false);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _carregandoJanela = false;
        _erroJanela = '$e';
      });
    }
  }

  /// Nulo no terminal leve (sem banco local).
  ObjectBox? get _objectBoxLocal {
    try {
      final ob = widget.produtoRepository.objectBox;
      return ob is ObjectBox ? ob : null;
    } catch (_) {
      return null;
    }
  }

  void _abrirEmMigracao(String titulo) {
    Navigator.push<void>(
      context,
      MaterialPageRoute<void>(
        builder: (_) => _RelatorioEmMigracaoPage(titulo: titulo),
      ),
    );
  }

  @override
  void dispose() {
    _buscaController.dispose();
    _buscaFocus.dispose();
    super.dispose();
  }

  List<_RelatorioHubItem> _todasEntradas() {
    final v = widget.vendaRepository;
    final c = widget.clienteRepository;
    final vd = widget.vendedorRepository;
    final p = widget.produtoRepository;

    return [
      _RelatorioHubItem(
        categoriaId: 'executivo',
        categoriaTitulo: 'Visao executiva',
        categoriaIcone: Icons.dashboard_outlined,
        icon: Icons.insights_outlined,
        relatorioCor: AppRelatorioId.dashboard,
        titulo: 'Painel executivo',
        subtitulo:
            'KPIs do mes, comparativo e alertas (fiado, estoque, orcamentos, entregas).',
        palavrasChave: const [
          'dashboard',
          'executivo',
          'kpi',
          'alerta',
          'resumo',
        ],
        onTap: () => Navigator.push<void>(
          context,
          MaterialPageRoute<void>(
            builder: (_) => RelatorioDashboardExecutivoPage(
              vendaRepository: v,
              clienteRepository: c,
              produtoRepository: p,
            ),
          ),
        ),
      ),
      _RelatorioHubItem(
        categoriaId: 'executivo',
        categoriaTitulo: 'Visao executiva',
        categoriaIcone: Icons.dashboard_outlined,
        icon: Icons.pie_chart_outline,
        relatorioCor: AppRelatorioId.abc,
        titulo: 'Curva ABC',
        subtitulo:
            'Classificacao A/B/C de clientes e produtos por faturamento no periodo.',
        palavrasChave: const [
          'abc',
          'curva',
          'classificacao',
          'pareto',
          'clientes',
          'produtos',
        ],
        onTap: () => Navigator.push<void>(
          context,
          MaterialPageRoute<void>(
            builder: (_) => RelatorioCurvaAbcPage(
              vendaRepository: v,
              clienteRepository: c,
              produtoRepository: p,
            ),
          ),
        ),
      ),
      _RelatorioHubItem(
        categoriaId: 'financeiro',
        categoriaTitulo: 'Financeiro e credito',
        categoriaIcone: Icons.account_balance_wallet_outlined,
        icon: Icons.receipt_long_outlined,
        relatorioCor: AppRelatorioId.fiados,
        titulo: 'Fiados em aberto',
        subtitulo:
            'Titulos a receber por cliente, vencimento e saldo; filtro de vencidos.',
        palavrasChave: const [
          'fiado',
          'credito',
          'receber',
          'vencido',
          'titulo',
          'financeiro',
        ],
        onTap: () => Navigator.push<void>(
          context,
          MaterialPageRoute<void>(
            builder: (_) => RelatorioFiadosPage(
              vendaRepository: v,
              clienteRepository: c,
              vendedorRepository: vd,
            ),
          ),
        ),
      ),
      _RelatorioHubItem(
        categoriaId: 'financeiro',
        categoriaTitulo: 'Financeiro e credito',
        categoriaIcone: Icons.account_balance_wallet_outlined,
        icon: Icons.payments_outlined,
        relatorioCor: AppRelatorioId.contasPagar,
        titulo: 'Contas a pagar',
        subtitulo:
            'Parcelas a fornecedores (NF-e e manual); exportar PDF/CSV.',
        palavrasChave: const [
          'pagar',
          'fornecedor',
          'despesa',
          'vencimento',
          'nf-e',
          'financeiro',
        ],
        onTap: () {
          final ob = _objectBoxLocal;
          final repoApi = MainMenuDeps.maybeOf(context)?.contaPagarRepository;
          Navigator.push<void>(
            context,
            MaterialPageRoute<void>(
              builder: (_) => RelatorioContasPagarPage(
                objectBox: ob,
                contaPagarRepository:
                    repoApi ?? (ob != null ? ContaPagarRepository(ob) : null),
              ),
            ),
          );
        },
      ),
      _RelatorioHubItem(
        categoriaId: 'vendas',
        categoriaTitulo: 'Vendas e faturamento',
        categoriaIcone: Icons.point_of_sale_outlined,
        icon: Icons.date_range_outlined,
        relatorioCor: AppRelatorioId.vendasPeriodo,
        titulo: 'Vendas por periodo',
        subtitulo:
            'Lista vendas finalizadas no intervalo; inclui ajuste por devolucoes/trocas.',
        palavrasChave: const [
          'vendas',
          'periodo',
          'faturamento',
          'nota',
          'finalizada',
        ],
        onTap: () => Navigator.push<void>(
          context,
          MaterialPageRoute<void>(
            builder: (_) => RelatorioVendasPeriodoPage(
              vendaRepository: v,
              clienteRepository: c,
              vendedorRepository: vd,
            ),
          ),
        ),
      ),
      _RelatorioHubItem(
        categoriaId: 'vendas',
        categoriaTitulo: 'Vendas e faturamento',
        categoriaIcone: Icons.point_of_sale_outlined,
        icon: Icons.schedule_outlined,
        relatorioCor: AppRelatorioId.horariosPico,
        titulo: 'Horarios de pico',
        subtitulo:
            'Horario com maior numero de vendas no periodo — ideal para escala e operacao.',
        palavrasChave: const [
          'horario',
          'pico',
          'movimento',
          'fluxo',
          'hora',
          'vendas',
          'escala',
        ],
        onTap: () => Navigator.push<void>(
          context,
          MaterialPageRoute<void>(
            builder: (_) => RelatorioHorariosPicoPage(vendaRepository: v),
          ),
        ),
      ),
      _RelatorioHubItem(
        categoriaId: 'vendas',
        categoriaTitulo: 'Vendas e faturamento',
        categoriaIcone: Icons.point_of_sale_outlined,
        icon: Icons.flag_outlined,
        relatorioCor: AppRelatorioId.metasVendedor,
        titulo: 'Metas de vendedores — hoje',
        subtitulo:
            'Acompanhamento diario da meta mensal: realizado, percentual e falta.',
        palavrasChave: const [
          'meta',
          'vendedor',
          'diario',
          'objetivo',
          'acompanhamento',
        ],
        onTap: () {
          final ob = _objectBoxLocal;
          final client = MainMenuDeps.maybeOf(context)?.lanApiClient;
          if (ob == null && client == null) {
            _abrirEmMigracao('Metas de vendedores');
            return;
          }
          Navigator.push<void>(
            context,
            MaterialPageRoute<void>(
              builder: (_) => RelatorioMetasVendedoresPage(
                vendaRepository: v,
                vendedorRepository: vd,
                produtoRepository: p,
                objectBox: ob,
                lanApiClient: client,
                usuarioLogado: widget.usuarioLogado,
              ),
            ),
          );
        },
      ),
      _RelatorioHubItem(
        categoriaId: 'vendas',
        categoriaTitulo: 'Vendas e faturamento',
        categoriaIcone: Icons.point_of_sale_outlined,
        icon: Icons.person_search_outlined,
        relatorioCor: AppRelatorioId.vendasVendedor,
        titulo: 'Vendas por vendedor',
        subtitulo:
            'Total por representante no periodo, com ajuste de devolucoes/trocas.',
        palavrasChave: const [
          'vendedor',
          'representante',
          'vendas',
          'ranking',
        ],
        onTap: () => Navigator.push<void>(
          context,
          MaterialPageRoute<void>(
            builder: (_) => RelatorioVendasPorVendedorPage(
              vendaRepository: v,
              vendedorRepository: vd,
            ),
          ),
        ),
      ),
      _RelatorioHubItem(
        categoriaId: 'vendas',
        categoriaTitulo: 'Vendas e faturamento',
        categoriaIcone: Icons.point_of_sale_outlined,
        icon: Icons.payments_outlined,
        relatorioCor: AppRelatorioId.comissao,
        titulo: 'Comissao de vendedores',
        subtitulo:
            'Percentual do cadastro; base em venda ou lucro (ajustado por devolucoes).',
        palavrasChave: const [
          'comissao',
          'vendedor',
          'lucro',
          'percentual',
        ],
        onTap: () => Navigator.push<void>(
          context,
          MaterialPageRoute<void>(
            builder: (_) => RelatorioComissaoVendedoresPage(
              vendaRepository: v,
              vendedorRepository: vd,
            ),
          ),
        ),
      ),
      _RelatorioHubItem(
        categoriaId: 'clientes',
        categoriaTitulo: 'Clientes',
        categoriaIcone: Icons.groups_outlined,
        icon: Icons.leaderboard_outlined,
        relatorioCor: AppRelatorioId.topClientes,
        titulo: 'Clientes que mais compraram',
        subtitulo:
            'Ranking por valor no periodo (vendas menos devolucoes/trocas).',
        palavrasChave: const [
          'cliente',
          'ranking',
          'top',
          'compraram',
          'fidelidade',
        ],
        onTap: () => Navigator.push<void>(
          context,
          MaterialPageRoute<void>(
            builder: (_) => RelatorioTopClientesPage(
              vendaRepository: v,
              clienteRepository: c,
            ),
          ),
        ),
      ),
      _RelatorioHubItem(
        categoriaId: 'produtos',
        categoriaTitulo: 'Produtos e estoque',
        categoriaIcone: Icons.inventory_2_outlined,
        icon: Icons.trending_up_outlined,
        relatorioCor: AppRelatorioId.produtosRanking,
        titulo: 'Produtos mais vendidos',
        subtitulo:
            'Quantidade e valor no periodo, ajustado por devolucoes/trocas.',
        palavrasChave: const [
          'produto',
          'mais vendidos',
          'ranking',
          'quantidade',
          'estoque',
        ],
        onTap: () => Navigator.push<void>(
          context,
          MaterialPageRoute<void>(
            builder: (_) => RelatorioProdutosMaisVendidosPage(
              vendaRepository: v,
              produtoRepository: p,
            ),
          ),
        ),
      ),
      _RelatorioHubItem(
        categoriaId: 'produtos',
        categoriaTitulo: 'Produtos e estoque',
        categoriaIcone: Icons.inventory_2_outlined,
        icon: Icons.warning_amber_outlined,
        relatorioCor: AppRelatorioId.estoqueMin,
        titulo: 'Estoque abaixo do minimo',
        subtitulo:
            'Produtos com saldo menor que a quantidade minima cadastrada.',
        palavrasChave: const [
          'estoque',
          'minimo',
          'ruptura',
          'reposicao',
          'saldo',
        ],
        onTap: () => Navigator.push<void>(
          context,
          MaterialPageRoute<void>(
            builder: (_) => RelatorioEstoqueMinimoPage(
              produtoRepository: p,
            ),
          ),
        ),
      ),
      _RelatorioHubItem(
        categoriaId: 'produtos',
        categoriaTitulo: 'Produtos e estoque',
        categoriaIcone: Icons.inventory_2_outlined,
        icon: Icons.shopping_cart_outlined,
        relatorioCor: AppRelatorioId.sugestaoCompra,
        titulo: 'Sugestao de compras',
        subtitulo:
            'Ponto de pedido, giro recente e falta ate o minimo / cobertura.',
        palavrasChave: const [
          'compra',
          'reposicao',
          'ponto de pedido',
          'giro',
          'estoque',
          'minimo',
        ],
        onTap: () => Navigator.push<void>(
          context,
          MaterialPageRoute<void>(
            builder: (_) => SugestaoCompraPage(
              produtoRepository: p,
              lanApiClient: MainMenuDeps.maybeOf(context)?.lanApiClient,
            ),
          ),
        ),
      ),
      _RelatorioHubItem(
        categoriaId: 'produtos',
        categoriaTitulo: 'Produtos e estoque',
        categoriaIcone: Icons.inventory_2_outlined,
        icon: Icons.percent_outlined,
        relatorioCor: AppRelatorioId.margemMarkup,
        titulo: 'Margem bruta e markup',
        subtitulo:
            'Receita liquida, CMV, margem % e markup por produto e categoria.',
        palavrasChave: const [
          'margem',
          'markup',
          'lucro',
          'cmv',
          'categoria',
          'preco',
        ],
        onTap: () => Navigator.push<void>(
          context,
          MaterialPageRoute<void>(
            builder: (_) => RelatorioMargemMarkupPage(
              vendaRepository: v,
              produtoRepository: p,
            ),
          ),
        ),
      ),
      _RelatorioHubItem(
        categoriaId: 'produtos',
        categoriaTitulo: 'Produtos e estoque',
        categoriaIcone: Icons.inventory_2_outlined,
        icon: Icons.swap_vert_outlined,
        relatorioCor: AppRelatorioId.movimentacaoEstoque,
        titulo: 'Movimentacao de estoque',
        subtitulo:
            'Entradas, saidas e saldo por produto ou grupo (categoria/marca); detalhe do kardex.',
        palavrasChave: const [
          'movimentacao',
          'estoque',
          'kardex',
          'entrada',
          'saida',
          'ajuste',
          'inventario',
        ],
        onTap: () {
          final ob = _objectBoxLocal;
          final client = MainMenuDeps.maybeOf(context)?.lanApiClient;
          if (ob == null && client == null) {
            _abrirEmMigracao('Movimentacao de estoque');
            return;
          }
          Navigator.push<void>(
            context,
            MaterialPageRoute<void>(
              builder: (_) => RelatorioMovimentacaoEstoquePage(
                produtoRepository: p,
                objectBox: ob,
                lanApiClient: client,
              ),
            ),
          );
        },
      ),
      _RelatorioHubItem(
        categoriaId: 'produtos',
        categoriaTitulo: 'Produtos e estoque',
        categoriaIcone: Icons.inventory_2_outlined,
        icon: Icons.undo_outlined,
        relatorioCor: AppRelatorioId.devolucoesPeriodo,
        titulo: 'Devolucoes e trocas',
        subtitulo:
            'Registros no periodo por produto ou detalhe (cliente, nota, motivo).',
        palavrasChave: const [
          'devolucao',
          'troca',
          'retorno',
          'estorno',
          'cliente',
        ],
        onTap: () => Navigator.push<void>(
          context,
          MaterialPageRoute<void>(
            builder: (_) => RelatorioDevolucoesPage(
              vendaRepository: v,
              clienteRepository: c,
            ),
          ),
        ),
      ),
      _RelatorioHubItem(
        categoriaId: 'produtos',
        categoriaTitulo: 'Produtos e estoque',
        categoriaIcone: Icons.inventory_2_outlined,
        icon: Icons.unarchive_outlined,
        relatorioCor: AppRelatorioId.saidasProduto,
        titulo: 'Saidas por produto',
        subtitulo:
            'Vendas finalizadas do item no periodo: quantidade, lucro e cliente.',
        palavrasChave: const [
          'saida',
          'produto',
          'movimentacao',
          'lucro',
        ],
        onTap: () => Navigator.push<void>(
          context,
          MaterialPageRoute<void>(
            builder: (_) => RelatorioSaidasProdutoPage(
              vendaRepository: v,
              produtoRepository: p,
            ),
          ),
        ),
      ),
      _RelatorioHubItem(
        categoriaId: 'produtos',
        categoriaTitulo: 'Produtos e estoque',
        categoriaIcone: Icons.inventory_2_outlined,
        icon: Icons.local_offer_outlined,
        relatorioCor: AppRelatorioId.vendasPromocao,
        titulo: 'Vendas em promocao',
        subtitulo:
            'Itens vendidos com campanha promocional no periodo: campanha, lucro e cliente.',
        palavrasChave: const [
          'promocao',
          'campanha',
          'oferta',
          'desconto',
          'promo',
        ],
        onTap: () {
          final ob = _objectBoxLocal;
          final promoRepo =
              MainMenuDeps.maybeOf(context)?.promocaoRepository ??
              (ob != null ? PromocaoRepository(ob) : null);
          if (promoRepo == null) {
            _abrirEmMigracao('Vendas em promocao');
            return;
          }
          Navigator.push<void>(
            context,
            MaterialPageRoute<void>(
              builder: (_) => RelatorioVendasPromocaoPage(
                vendaRepository: v,
                promocaoRepository: promoRepo,
              ),
            ),
          );
        },
      ),
      _RelatorioHubItem(
        categoriaId: 'vendas',
        categoriaTitulo: 'Vendas e faturamento',
        categoriaIcone: Icons.point_of_sale_outlined,
        icon: Icons.lightbulb_outline,
        relatorioCor: AppRelatorioId.sugestoesVenda,
        titulo: 'Sugestoes de venda',
        subtitulo:
            'Ranking de ofertas aceitas e ignoradas no PDV (cadastro e historico).',
        palavrasChave: const [
          'sugestao',
          'agregado',
          'complementar',
          'ofereca',
          'pdv',
          'ranking',
          'aceite',
        ],
        onTap: () {
          final ob = _objectBoxLocal;
          final client = MainMenuDeps.maybeOf(context)?.lanApiClient;
          dynamic metricaRepo;
          if (ob != null) {
            metricaRepo = SugestaoVendaMetricaRepository(ob);
          } else if (client != null) {
            metricaRepo = SugestaoVendaMetricaApiRepository(client);
          } else {
            _abrirEmMigracao('Sugestoes de venda');
            return;
          }
          Navigator.push<void>(
            context,
            MaterialPageRoute<void>(
              builder: (_) => RelatorioSugestoesVendaPage(
                metricaRepository: metricaRepo,
                produtoRepository: p,
              ),
            ),
          );
        },
      ),
      _RelatorioHubItem(
        categoriaId: 'produtos',
        categoriaTitulo: 'Produtos e estoque',
        categoriaIcone: Icons.inventory_2_outlined,
        icon: Icons.table_chart_outlined,
        relatorioCor: AppRelatorioId.tabelaPrecos,
        titulo: 'Tabela de precos',
        subtitulo:
            'PDF alfabetico com estoque; precos de venda ou com custo; somente ativos.',
        palavrasChave: const [
          'tabela',
          'preco',
          'pdf',
          'catalogo',
          'lista',
        ],
        onTap: () => Navigator.push<void>(
          context,
          MaterialPageRoute<void>(
            builder: (_) => RelatorioTabelaPrecosPage(
              produtoRepository: p,
            ),
          ),
        ),
      ),
      _RelatorioHubItem(
        categoriaId: 'operacional',
        categoriaTitulo: 'Operacional',
        categoriaIcone: Icons.settings_suggest_outlined,
        icon: Icons.fact_check_outlined,
        relatorioCor: AppRelatorioId.logSistema,
        titulo: 'Log do sistema',
        subtitulo:
            'Auditoria central, mensagens WhatsApp e historico de entregas.',
        palavrasChave: const [
          'log',
          'auditoria',
          'historico',
          'sistema',
          'rastreio',
          'evento',
        ],
        onTap: () {
          final ob = _objectBoxLocal;
          final client = MainMenuDeps.maybeOf(context)?.lanApiClient;
          dynamic auditRepo;
          if (ob != null) {
            auditRepo = AuditoriaRepository(ob);
          } else if (client != null) {
            auditRepo = AuditoriaApiRepository(client);
          } else {
            _abrirEmMigracao('Log do sistema');
            return;
          }
          Navigator.push<void>(
            context,
            MaterialPageRoute<void>(
              builder: (_) => RelatorioLogSistemaPage(
                auditoriaRepository: auditRepo,
                appConfigRepository: widget.appConfigRepository,
                vendaRepository: widget.vendaRepository,
                usuarioAdmin: widget.usuarioAdmin,
                usuarioLogin: widget.usuarioLogin,
              ),
            ),
          );
        },
      ),
      _RelatorioHubItem(
        categoriaId: 'operacional',
        categoriaTitulo: 'Operacional',
        categoriaIcone: Icons.settings_suggest_outlined,
        icon: Icons.lock_clock_outlined,
        relatorioCor: AppRelatorioId.fechamentoHist,
        titulo: 'Historico de fechamento',
        subtitulo:
            'Fechamentos de caixa do PC servidor (API) ou auditoria local neste PC.',
        palavrasChave: const [
          'fechamento',
          'caixa',
          'turno',
          'historico',
          'auditoria',
        ],
        onTap: () {
          final deps = MainMenuDeps.maybeOf(context);
          Navigator.push<void>(
            context,
            MaterialPageRoute<void>(
              builder: (_) => RelatorioHistoricoFechamentoPage(
                lanApiClient: deps?.lanApiClient,
                objectBox: deps?.objectBox,
              ),
            ),
          );
        },
      ),
      _RelatorioHubItem(
        categoriaId: 'operacional',
        categoriaTitulo: 'Operacional',
        categoriaIcone: Icons.settings_suggest_outlined,
        icon: Icons.pending_actions_outlined,
        relatorioCor: AppRelatorioId.pendenciasEntrega,
        titulo: 'Pendencias de retirada e entrega',
        subtitulo:
            'Itens ainda nao retirados (futura) ou em carreto; cliente, produto e quantidade.',
        palavrasChave: const [
          'pendente',
          'retirada',
          'futura',
          'entrega',
          'carreto',
          'separacao',
        ],
        onTap: () => Navigator.push<void>(
          context,
          MaterialPageRoute<void>(
            builder: (_) => RelatorioPendenciasEntregaPage(
              vendaRepository: v,
              clienteRepository: c,
              vendedorRepository: vd,
            ),
          ),
        ),
      ),
      _RelatorioHubItem(
        categoriaId: 'operacional',
        categoriaTitulo: 'Operacional',
        categoriaIcone: Icons.settings_suggest_outlined,
        icon: Icons.history_outlined,
        relatorioCor: AppRelatorioId.historicoEntregas,
        titulo: 'Historico de entregas',
        subtitulo:
            'Transicoes de status, retiradas, devolucoes e POD no periodo.',
        palavrasChave: const [
          'historico',
          'entrega',
          'status',
          'motorista',
          'romaneio',
          'evento',
        ],
        onTap: () => Navigator.push<void>(
          context,
          MaterialPageRoute<void>(
            builder: (_) => RelatorioHistoricoEntregasPage(
              vendaRepository: v,
              clienteRepository: widget.clienteRepository,
            ),
          ),
        ),
      ),
      _RelatorioHubItem(
        categoriaId: 'operacional',
        categoriaTitulo: 'Operacional',
        categoriaIcone: Icons.settings_suggest_outlined,
        icon: Icons.local_shipping_outlined,
        relatorioCor: AppRelatorioId.entregasResumo,
        titulo: 'Entregas — resumo',
        subtitulo:
            'Status, atrasadas e agenda de hoje; atalho para romaneios no modulo Entregas.',
        palavrasChave: const [
          'entrega',
          'romaneio',
          'carreto',
          'motorista',
          'logistica',
          'atrasada',
        ],
        onTap: () => Navigator.push<void>(
          context,
          MaterialPageRoute<void>(
            builder: (_) => RelatorioEntregasResumoPage(
              vendaRepository: v,
              clienteRepository: widget.clienteRepository,
              onAbrirModuloEntregas: widget.onAbrirModuloEntregas,
            ),
          ),
        ),
      ),
      _RelatorioHubItem(
        categoriaId: 'operacional',
        categoriaTitulo: 'Operacional',
        categoriaIcone: Icons.settings_suggest_outlined,
        icon: Icons.local_shipping,
        relatorioCor: AppRelatorioId.performanceEntregas,
        titulo: 'Performance de entregas',
        subtitulo:
            'Taxa de sucesso, insucessos e carga que voltou, por motorista ou veiculo.',
        palavrasChave: const [
          'performance',
          'insucesso',
          'motorista',
          'veiculo',
          'ausente',
          'carreto',
        ],
        onTap: () => Navigator.push<void>(
          context,
          MaterialPageRoute<void>(
            builder: (_) => RelatorioPerformanceEntregasPage(
              vendaRepository: v,
            ),
          ),
        ),
      ),
      _RelatorioHubItem(
        categoriaId: 'operacional',
        categoriaTitulo: 'Operacional',
        categoriaIcone: Icons.settings_suggest_outlined,
        icon: Icons.account_balance_outlined,
        relatorioCor: AppRelatorioId.fiscalMensal,
        titulo: 'Relatorio fiscal do mes',
        subtitulo:
            'Totais de NF-e e NFC-e autorizadas e canceladas para a contabilidade.',
        palavrasChave: const [
          'fiscal',
          'nfe',
          'nfce',
          'contabilidade',
          'fechamento',
          'mes',
        ],
        onTap: () => Navigator.push<void>(
          context,
          MaterialPageRoute<void>(
            builder: (_) => RelatorioFiscalMensalPage(vendaRepository: v),
          ),
        ),
      ),
    ];
  }

  bool _entradaPermitida(_RelatorioHubItem item) {
    final u = widget.usuarioLogado;
    switch (item.titulo) {
      case 'Comissao de vendedores':
        return UsuarioPermissaoHelper.tem(
          u,
          PermissaoUsuario.relatoriosComissao,
        );
      case 'Fiados em aberto':
        return UsuarioPermissaoHelper.tem(u, PermissaoUsuario.relatoriosFiado);
      case 'Log do sistema':
        return UsuarioPermissaoHelper.tem(
          u,
          PermissaoUsuario.relatoriosLogSistema,
        );
      case 'Relatorio fiscal do mes':
        return UsuarioPermissaoHelper.tem(u, PermissaoUsuario.fiscal);
      default:
        return true;
    }
  }

  List<_RelatorioHubItem> _entradasFiltradas() {
    final termo = _buscaController.text.trim().toLowerCase();
    final todas = _todasEntradas().where(_entradaPermitida).toList();
    if (termo.isEmpty) return todas;
    return todas.where((item) {
      final blob = [
        item.titulo,
        item.subtitulo,
        item.categoriaTitulo,
        ...item.palavrasChave,
      ].join(' ').toLowerCase();
      return blob.contains(termo);
    }).toList();
  }

  Map<String, List<_RelatorioHubItem>> _agruparPorCategoria(
    List<_RelatorioHubItem> itens,
  ) {
    final map = <String, List<_RelatorioHubItem>>{};
    for (final id in _ordemCategorias) {
      map[id] = [];
    }
    for (final item in itens) {
      map.putIfAbsent(item.categoriaId, () => []).add(item);
    }
    return map;
  }

  Widget _buildCard(_RelatorioHubItem item) {
    return HubNavButton(
      icon: item.icon,
      corDestaque: AppRelatorioCores.cor(context, item.relatorioCor),
      titulo: item.titulo,
      subtitulo: item.subtitulo,
      onTap: item.onTap,
    );
  }

  List<Widget> _buildSecoesHub(
    Map<String, List<_RelatorioHubItem>> agrupados,
  ) {
    final widgets = <Widget>[];
    for (final catId in _ordemCategorias) {
      final itens = agrupados[catId] ?? const <_RelatorioHubItem>[];
      if (itens.isEmpty) continue;
      final primeiro = itens.first;
      widgets.addAll([
        RelatorioHubSecao(
          titulo: primeiro.categoriaTitulo,
          icone: primeiro.categoriaIcone,
          quantidadeItens: itens.length,
        ),
        _buildGridSecao(itens),
      ]);
    }
    return widgets;
  }

  Widget _buildGridSecao(List<_RelatorioHubItem> itens) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final duasColunas = constraints.maxWidth >= 640;
        if (!duasColunas) {
          return Column(
            children: [
              for (var i = 0; i < itens.length; i++) ...[
                if (i > 0) const SizedBox(height: 12),
                _buildCard(itens[i]),
              ],
            ],
          );
        }
        final rows = <Widget>[];
        for (var i = 0; i < itens.length; i += 2) {
          final esquerda = itens[i];
          final direita = i + 1 < itens.length ? itens[i + 1] : null;
          rows.add(
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(child: _buildCard(esquerda)),
                const SizedBox(width: 12),
                Expanded(
                  child: direita == null
                      ? const SizedBox.shrink()
                      : _buildCard(direita),
                ),
              ],
            ),
          );
          if (i + 2 < itens.length) {
            rows.add(const SizedBox(height: 12));
          }
        }
        return Column(children: rows);
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final filtrados = _entradasFiltradas();
    final agrupados = _agruparPorCategoria(filtrados);
    final termoBusca = _buscaController.text.trim();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Relatorios'),
        actions: [
          IconButton(
            tooltip: 'Focar busca',
            icon: const Icon(Icons.search),
            onPressed: () => _buscaFocus.requestFocus(),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
        children: [
          Text(
            'Escolha o relatorio por area da loja. Use a busca para filtrar por nome.',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
          ),
          if (_carregandoJanela || _erroJanela.isNotEmpty) ...[
            const SizedBox(height: 12),
            _JanelaTerminalAviso(
              carregando: _carregandoJanela,
              erro: _erroJanela,
              meses: _mesesJanelaTerminal,
              onTentarNovamente: () => unawaited(_carregarJanelaTerminal()),
            ),
          ],
          const SizedBox(height: 12),
          TextField(
            controller: _buscaController,
            focusNode: _buscaFocus,
            decoration: InputDecoration(
              labelText: 'Buscar relatorio',
              hintText: 'Ex.: fiado, estoque, comissao...',
              prefixIcon: const Icon(Icons.search),
              suffixIcon: termoBusca.isEmpty
                  ? null
                  : IconButton(
                      icon: const Icon(Icons.clear),
                      onPressed: () {
                        _buscaController.clear();
                        setState(() {});
                      },
                    ),
              isDense: true,
            ),
            onChanged: (_) => setState(() {}),
          ),
          if (filtrados.isEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 32),
              child: Center(
                child: Text(
                  'Nenhum relatorio encontrado para "$termoBusca".',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodyLarge,
                ),
              ),
            )
          else
            ..._buildSecoesHub(agrupados),
        ],
      ),
    );
  }
}

/// Fallback quando nao ha ObjectBox local nem LanApiClient configurado.
class _RelatorioEmMigracaoPage extends StatelessWidget {
  const _RelatorioEmMigracaoPage({required this.titulo});

  final String titulo;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(titulo)),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.cloud_off_outlined, size: 48),
              const SizedBox(height: 12),
              Text(
                'Sem conexao com o PC servidor',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 8),
              Text(
                '$titulo precisa da API do PC 1. Verifique a rede do terminal '
                'ou abra este relatorio no PC servidor.',
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Estado da janela de vendas baixada da API (somente terminal leve).
class _JanelaTerminalAviso extends StatelessWidget {
  const _JanelaTerminalAviso({
    required this.carregando,
    required this.erro,
    required this.meses,
    required this.onTentarNovamente,
  });

  final bool carregando;
  final String erro;
  final int meses;
  final VoidCallback onTentarNovamente;

  @override
  Widget build(BuildContext context) {
    final cores = Theme.of(context).colorScheme;
    final falhou = erro.isNotEmpty;
    return Card(
      margin: EdgeInsets.zero,
      color: falhou ? cores.errorContainer : cores.surfaceContainerHighest,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            if (carregando)
              const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            else
              Icon(
                falhou ? Icons.cloud_off : Icons.cloud_done_outlined,
                color: falhou ? cores.onErrorContainer : null,
              ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                carregando
                    ? 'Baixando vendas dos ultimos $meses meses do servidor...'
                    : 'Nao foi possivel baixar as vendas do servidor: $erro',
                style: TextStyle(
                  color: falhou ? cores.onErrorContainer : null,
                ),
              ),
            ),
            if (falhou)
              TextButton(
                onPressed: onTentarNovamente,
                child: const Text('Tentar novamente'),
              ),
          ],
        ),
      ),
    );
  }
}
