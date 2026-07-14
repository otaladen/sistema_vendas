import 'package:flutter/material.dart';

import '../../data/kit_orcamento_repository.dart';
import '../../data/promocao_repository.dart';
import '../../data/usuario_repository.dart';
import '../../domain/main_menu_sub_destino.dart';
import '../../domain/permissao_usuario.dart';
import '../../domain/usuario_permissao_helper.dart';
import '../caixa/caixa_page.dart';
import '../clientes_page.dart';
import '../entregas_page.dart';
import '../financeiro/contas_pagar_page.dart';
import '../financeiro/contas_receber_page.dart';
import '../financeiro/relatorio_contas_pagar_page.dart';
import '../financeiro/tesouraria_semanal_page.dart';
import '../fiscal/exportar_fechamento_page.dart';
import '../fiscal/fiscal_importar_nfe_page.dart';
import '../fiscal/nfe_gerenciamento_page.dart';
import '../fiscal/pendencias_fiscais_page.dart';
import '../fiscal/relatorio_fiscal_mensal_page.dart';
import '../funcionarios_page.dart';
import '../kits_orcamento_page.dart';
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
      case MainMenuSubDestino.cadastrosKitsOrcamento:
        return KitsOrcamentoPage(
          kitOrcamentoRepository:
              KitOrcamentoRepository(deps.produtoRepository.objectBox),
          produtoRepository: deps.produtoRepository,
        );
      case MainMenuSubDestino.cadastrosPromocoes:
        return PromocoesPage(
          promocaoRepository:
              PromocaoRepository(deps.produtoRepository.objectBox),
          produtoRepository: deps.produtoRepository,
        );
      case MainMenuSubDestino.cadastrosMotoristas:
        return MotoristasPage(
          motoristaRepository: deps.motoristaRepository,
        );
      case MainMenuSubDestino.cadastrosFuncionarios:
        return FuncionariosPage(
          funcionarioRepository: deps.funcionarioRepository,
          vendedorRepository: deps.vendedorRepository,
          vendaRepository: deps.vendaRepository,
          motoristaRepository: deps.motoristaRepository,
          usuarioRepository: UsuarioRepository(),
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
        );
      case MainMenuSubDestino.cadastrosUsuarios:
        return UsuariosPage(
          usuarioRepository: UsuarioRepository(),
          motoristaRepository: deps.motoristaRepository,
          vendedorRepository: deps.vendedorRepository,
          usuarioLogado: u,
        );
      case MainMenuSubDestino.fiscalImportarNfe:
        return FiscalImportarNfePage(
          produtoRepository: deps.produtoRepository,
          appConfigRepository: deps.appConfigRepository,
        );
      case MainMenuSubDestino.fiscalNotasImportadas:
        return NfeImportadasPage(
          produtoRepository: deps.produtoRepository,
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
        return RelatorioFiscalMensalPage(
          vendaRepository: deps.vendaRepository,
        );
      case MainMenuSubDestino.fiscalExportarFechamento:
        return ExportarFechamentoPage(
          vendaRepository: deps.vendaRepository,
        );
      case MainMenuSubDestino.financeiroTesouraria:
        return TesourariaSemanalPage(
          objectBox: deps.objectBox,
          vendaRepository: deps.vendaRepository,
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
        );
      case MainMenuSubDestino.financeiroRelatorioContasPagar:
        return RelatorioContasPagarPage(objectBox: deps.objectBox);
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
    final podeCaixa =
        UsuarioPermissaoHelper.tem(u, PermissaoUsuario.acessarCaixa);
    final podeGerenciarEntregas =
        UsuarioPermissaoHelper.podeGerenciarEntregas(u);

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
}
