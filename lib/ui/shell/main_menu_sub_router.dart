import 'package:flutter/material.dart';

import '../../data/conta_pagar_repository.dart';
import '../../data/fornecedor_repository.dart';
import '../../data/kit_orcamento_repository.dart';
import '../../data/promocao_repository.dart';
import '../../domain/main_menu_sub_destino.dart';
import '../../domain/permissao_usuario.dart';
import '../../domain/usuario_permissao_helper.dart';
import '../caixa/caixa_page.dart';
import '../clientes_page.dart';
import '../entregas_page.dart';
import '../financeiro/contas_pagar_page.dart';
import '../financeiro/contas_receber_page.dart';
import '../financeiro/obrigacoes_mensais_page.dart';
import '../financeiro/relatorio_contas_pagar_page.dart';
import '../financeiro/tesouraria_semanal_page.dart';
import '../../data/api/obrigacao_mensal_api_repository.dart';
import '../../data/obrigacao_mensal_fixa_repository.dart';
import '../fiscal/exportar_fechamento_page.dart';
import '../fiscal/fiscal_importar_nfe_page.dart';
import '../fiscal/nfe_devolucao_fornecedor_page.dart';
import '../fiscal/nfe_gerenciamento_page.dart';
import '../fiscal/pendencias_fiscais_page.dart';
import '../fiscal/relatorio_fiscal_mensal_page.dart';
import '../fornecedores_page.dart';
import '../funcionarios_page.dart';
import '../kits_orcamento_page.dart';
import '../lista_preco_externa_page.dart';
import '../listagem_vendas_page.dart';
import '../motoristas_page.dart';
import '../nfe_importadas_page.dart';
import '../orcamentos_page.dart';
import '../produtos_page.dart';
import '../promocoes_page.dart';
import '../relatorio_fiados_page.dart';
import '../relatorios_page.dart';
import '../usuarios_page.dart';
import '../vendedores_page.dart';
import 'main_menu_deps.dart';

/// Paginas dos subitens do menu lateral (sem hub intermediario).
class MainMenuSubRouter {
  MainMenuSubRouter._();

  static Widget pagina(
    MainMenuSubDestino sub,
    MainMenuDeps deps, {
    BuildContext? navigatorContext,
  }) {
    final u = deps.usuarioLogado;
    switch (sub) {
      case MainMenuSubDestino.vendasOrcamentos:
        return OrcamentosPage(
          vendaRepository: deps.vendaRepository,
          clienteRepository: deps.clienteRepository,
          produtoRepository: deps.produtoRepository,
          vendedorRepository: deps.vendedorRepository,
          appConfigRepository: deps.appConfigRepository,
          printService: deps.printService,
          usuarioLogado: u,
        );
      case MainMenuSubDestino.vendasListagem:
        return ListagemVendasPage(
          vendaRepository: deps.vendaRepository,
          clienteRepository: deps.clienteRepository,
          vendedorRepository: deps.vendedorRepository,
          produtoRepository: deps.produtoRepository,
          appConfigRepository: deps.appConfigRepository,
          printService: deps.printService,
          usuarioAtual: u.login,
          podeCancelarVendas: UsuarioPermissaoHelper.podeCancelarVendas(u),
          usuarioLogado: u,
          periodoPresetInicial: ListagemVendasAbertura.consumirPeriodo(),
        );
      case MainMenuSubDestino.vendasRelatorios:
        assert(navigatorContext != null);
        return _relatorios(deps, navigatorContext!);
      case MainMenuSubDestino.cadastrosProdutos:
        return ProdutosPage(
          produtoRepository: deps.produtoRepository,
          printService: deps.printService,
          usuarioLogado: u,
        );
      case MainMenuSubDestino.cadastrosListaPrecoExterna:
        return const ListaPrecoExternaPage();
      case MainMenuSubDestino.cadastrosKitsOrcamento:
        final kitRepo =
            deps.kitOrcamentoRepository ??
            (deps.objectBox != null
                ? KitOrcamentoRepository(deps.objectBox!)
                : null);
        if (kitRepo == null) {
          return const Scaffold(
            body: Center(child: Text('Kits indisponiveis neste terminal.')),
          );
        }
        return KitsOrcamentoPage(
          kitOrcamentoRepository: kitRepo,
          produtoRepository: deps.produtoRepository,
        );
      case MainMenuSubDestino.cadastrosPromocoes:
        final promoRepo =
            deps.promocaoRepository ??
            (deps.objectBox != null
                ? PromocaoRepository(deps.objectBox!)
                : null);
        if (promoRepo == null) {
          return const Scaffold(
            body: Center(
              child: Text('Promocoes indisponiveis neste terminal.'),
            ),
          );
        }
        return PromocoesPage(
          promocaoRepository: promoRepo,
          produtoRepository: deps.produtoRepository,
        );
      case MainMenuSubDestino.cadastrosMotoristas:
        return MotoristasPage(
          motoristaRepository: deps.motoristaRepository,
          funcionarioRepository: deps.funcionarioRepository,
        );
      case MainMenuSubDestino.cadastrosFuncionarios:
        return FuncionariosPage(
          funcionarioRepository: deps.funcionarioRepository,
          vendedorRepository: deps.vendedorRepository,
          vendaRepository: deps.vendaRepository,
          motoristaRepository: deps.motoristaRepository,
          usuarioRepository: deps.usuarioRepositoryEfetivo(),
          usuarioLogado: u,
          onLogout: deps.onLogout,
        );
      case MainMenuSubDestino.cadastrosClientes:
        return ClientesPage(
          clienteRepository: deps.clienteRepository,
          vendaRepository: deps.vendaRepository,
          vendedorRepository: deps.vendedorRepository,
        );
      case MainMenuSubDestino.cadastrosVendedores:
        return VendedoresPage(
          vendedorRepository: deps.vendedorRepository,
          usuarioRepository: deps.usuarioRepositoryEfetivo(),
          vendaRepository: deps.vendaRepository,
        );
      case MainMenuSubDestino.cadastrosFornecedores:
        final repo = deps.fornecedorRepository;
        if (repo != null) {
          return FornecedoresPage(fornecedorRepository: repo);
        }
        final ob = deps.objectBox;
        if (ob == null) {
          return const _TerminalIndisponivelPage(
            titulo: 'Fornecedores',
            detalhe:
                'Conecte ao PC servidor para cadastrar fornecedores. '
                'Fornecedores tambem nascem automaticamente ao importar NF-e.',
          );
        }
        return FornecedoresPage(
          fornecedorRepository: FornecedorRepository(ob),
        );
      case MainMenuSubDestino.cadastrosUsuarios:
        return UsuariosPage(
          usuarioRepository: deps.usuarioRepositoryEfetivo(),
          motoristaRepository: deps.motoristaRepository,
          vendedorRepository: deps.vendedorRepository,
          funcionarioRepository: deps.funcionarioRepository,
          usuarioLogado: u,
        );
      case MainMenuSubDestino.fiscalImportarNfe:
        if (_fiscalMutacaoLocalIndisponivel(deps) && deps.lanApiClient == null) {
          return const _TerminalIndisponivelPage(
            titulo: 'Importar NF-e',
            detalhe:
                'A importacao de XML altera estoque e arquivos locais do servidor. '
                'Use o PC servidor para importar; neste terminal voce pode consultar '
                'as notas ja importadas em "Notas importadas".',
          );
        }
        return FiscalImportarNfePage(
          produtoRepository: deps.produtoRepository,
          appConfigRepository: deps.appConfigRepository,
          lanApiClient: deps.lanApiClient,
        );
      case MainMenuSubDestino.fiscalNotasImportadas:
        return NfeImportadasPage(
          produtoRepository: deps.produtoRepository,
          nfeImportadaRepository: deps.nfeImportadaRepository,
        );
      case MainMenuSubDestino.fiscalDevolucaoFornecedor:
        if (_fiscalMutacaoLocalIndisponivel(deps) &&
            deps.lanApiClient == null &&
            deps.nfeImportadaRepository == null) {
          return const _TerminalIndisponivelPage(
            titulo: 'Devolucao ao fornecedor',
            detalhe:
                'Conecte-se a API do PC servidor (:8788) para listar NF-e '
                'e emitir a devolucao fiscal remotamente.',
          );
        }
        return NfeDevolucaoFornecedorPage(
          produtoRepository: deps.produtoRepository,
          nfeImportadaRepository: deps.nfeImportadaRepository,
        );
      case MainMenuSubDestino.fiscalPendencias:
        return PendenciasFiscaisPage(
          vendaRepository: deps.vendaRepository,
          clienteRepository: deps.clienteRepository,
          appConfigRepository: deps.appConfigRepository,
          usuarioLogado: u,
        );
      case MainMenuSubDestino.fiscalNfeSaida:
        return NfeGerenciamentoPage(
          vendaRepository: deps.vendaRepository,
          clienteRepository: deps.clienteRepository,
          appConfigRepository: deps.appConfigRepository,
          usuarioLogado: u,
        );
      case MainMenuSubDestino.fiscalRelatorioMensal:
        return RelatorioFiscalMensalPage(vendaRepository: deps.vendaRepository);
      case MainMenuSubDestino.fiscalExportarFechamento:
        return ExportarFechamentoPage(vendaRepository: deps.vendaRepository);
      case MainMenuSubDestino.financeiroTesouraria:
        return TesourariaSemanalPage(
          objectBox: deps.objectBox,
          vendaRepository: deps.vendaRepository,
          lanApiClient: deps.lanApiClient,
        );
      case MainMenuSubDestino.financeiroContasReceber:
        return ContasReceberPage(
          vendaRepository: deps.vendaRepository,
          clienteRepository: deps.clienteRepository,
          usuarioLogado: u,
          podeRegistrarRecebimento: UsuarioPermissaoHelper.tem(
            u,
            PermissaoUsuario.acessarCaixa,
          ),
        );
      case MainMenuSubDestino.financeiroContasPagar:
        return ContasPagarPage(
          objectBox: deps.objectBox,
          contaPagarRepository:
              deps.contaPagarRepository ??
              (deps.objectBox != null
                  ? ContaPagarRepository(deps.objectBox!)
                  : null),
        );
      case MainMenuSubDestino.financeiroObrigacoesMensais:
        return ObrigacoesMensaisPage(
          objectBox: deps.objectBox,
          obrigacaoRepository: deps.lanApiClient != null
              ? ObrigacaoMensalApiRepository(deps.lanApiClient!)
              : (deps.objectBox != null
                  ? ObrigacaoMensalFixaRepository(deps.objectBox!)
                  : null),
        );
      case MainMenuSubDestino.financeiroRelatorioContasPagar:
        return RelatorioContasPagarPage(
          objectBox: deps.objectBox,
          contaPagarRepository:
              deps.contaPagarRepository ??
              (deps.objectBox != null
                  ? ContaPagarRepository(deps.objectBox!)
                  : null),
        );
      case MainMenuSubDestino.financeiroRelatorioFiados:
        return RelatorioFiadosPage(
          vendaRepository: deps.vendaRepository,
          clienteRepository: deps.clienteRepository,
        );
    }
  }

  static Widget _relatorios(MainMenuDeps deps, BuildContext navigatorContext) {
    final u = deps.usuarioLogado;
    final podeCancelar = UsuarioPermissaoHelper.podeCancelarVendas(u);
    final podeCaixa = UsuarioPermissaoHelper.tem(
      u,
      PermissaoUsuario.acessarCaixa,
    );
    final podeGerenciarEntregas = UsuarioPermissaoHelper.podeGerenciarEntregas(
      u,
    );

    return RelatoriosPage(
      vendaRepository: deps.vendaRepository,
      clienteRepository: deps.clienteRepository,
      vendedorRepository: deps.vendedorRepository,
      produtoRepository: deps.produtoRepository,
      appConfigRepository: deps.appConfigRepository,
      usuarioLogado: u,
      usuarioAdmin: u.admin,
      usuarioLogin: u.login,
      onAbrirModuloEntregas: podeGerenciarEntregas
          ? () {
              Navigator.push<void>(
                navigatorContext,
                MaterialPageRoute<void>(
                  builder: (_) => EntregasPage(
                    vendaRepository: deps.vendaRepository,
                    produtoRepository: deps.produtoRepository,
                    motoristaRepository: deps.motoristaRepository,
                    vendedorRepository: deps.vendedorRepository,
                    appConfigRepository: deps.appConfigRepository,
                    usuarioAtual: u.login,
                    podeGerenciarStatusEntrega: podeGerenciarEntregas,
                    podeRegistrarPodEntrega:
                        UsuarioPermissaoHelper.podeRegistrarPodEntrega(u),
                    podeRegistrarDevolucaoTrocaSemSenha: podeCancelar,
                  ),
                ),
              );
            }
          : null,
      onAbrirModuloCaixa: () {
        if (!podeCaixa) return;
        Navigator.push<void>(
          navigatorContext,
          MaterialPageRoute<void>(
            builder: (_) => CaixaPage(
              clienteRepository: deps.clienteRepository,
              produtoRepository: deps.produtoRepository,
              vendaRepository: deps.vendaRepository,
              vendedorRepository: deps.vendedorRepository,
              appConfigRepository: deps.appConfigRepository,
              printService: deps.printService,
              usuarioLogado: u,
              usuarioAtual: u.login,
              podeCancelarVendas: podeCancelar,
              podeLeituraParcialCaixa: UsuarioPermissaoHelper.tem(
                u,
                PermissaoUsuario.leituraParcialCaixa,
              ),
              podeVisualizarAuditoriaCaixa: UsuarioPermissaoHelper.tem(
                u,
                PermissaoUsuario.visualizarAuditoriaCaixa,
              ),
              podeManutencaoAuditoriaCaixa: UsuarioPermissaoHelper.tem(
                u,
                PermissaoUsuario.manutencaoAuditoriaCaixa,
              ),
              onLogout: deps.onLogout,
            ),
          ),
        );
      },
    );
  }

  /// Operacoes que exigem XML/certificado/ObjectBox no disco do servidor.
  static bool _fiscalMutacaoLocalIndisponivel(MainMenuDeps deps) =>
      deps.terminalLeve || deps.objectBox == null;
}

class _TerminalIndisponivelPage extends StatelessWidget {
  const _TerminalIndisponivelPage({
    required this.titulo,
    this.detalhe,
  });

  final String titulo;
  final String? detalhe;

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
              const Icon(Icons.receipt_long_outlined, size: 48),
              const SizedBox(height: 12),
              Text(
                titulo,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 8),
              Text(
                detalhe ??
                    'Esta operacao depende de arquivos e certificado do PC servidor.',
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
