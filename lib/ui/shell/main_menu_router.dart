import 'package:flutter/material.dart';

import '../../domain/filtro_contas_pagar.dart';
import '../../domain/filtro_contas_receber.dart';
import '../../domain/main_menu_destino.dart';
import '../../domain/permissao_usuario.dart';
import '../../domain/usuario_permissao_helper.dart';
import '../cadastros_page.dart';
import '../caixa_page.dart';
import '../configuracoes_page.dart';
import '../entregas_page.dart';
import '../estoque_page.dart';
import '../financeiro/contas_pagar_page.dart';
import '../financeiro/contas_receber_page.dart';
import '../financeiro/financeiro_hub_page.dart';
import '../motorista/motorista_entregas_page.dart';
import '../notas_fiscais_page.dart';
import '../ponto_de_venda_page.dart';
import '../vendas_page.dart';
import 'app_shell_scope.dart';
import 'main_menu_deps.dart';

/// Constroi paginas do menu e abre via shell (desktop) ou push (mobile).
class MainMenuRouter {
  MainMenuRouter._();

  static void abrirContasPagar(
    BuildContext context, {
    FiltroContasPagar filtro = FiltroContasPagar.todos,
  }) {
    final deps = MainMenuDeps.maybeOf(context);
    if (deps == null) return;
    if (!MainMenuDestino.financeiro.podeAcessar(deps.usuarioLogado)) return;

    Navigator.push<void>(
      context,
      MaterialPageRoute<void>(
        builder: (_) => MainMenuDeps(
          objectBox: deps.objectBox,
          produtoRepository: deps.produtoRepository,
          clienteRepository: deps.clienteRepository,
          vendaRepository: deps.vendaRepository,
          vendedorRepository: deps.vendedorRepository,
          funcionarioRepository: deps.funcionarioRepository,
          motoristaRepository: deps.motoristaRepository,
          usuarioLogado: deps.usuarioLogado,
          onLogout: deps.onLogout,
          lanSyncScheduler: deps.lanSyncScheduler,
          appConfigRepository: deps.appConfigRepository,
          printService: deps.printService,
          child: ContasPagarPage(
            objectBox: deps.objectBox,
            filtroInicial: filtro,
          ),
        ),
      ),
    );
  }

  static void abrirContasReceber(
    BuildContext context, {
    FiltroContasReceber filtro = FiltroContasReceber.todos,
  }) {
    final deps = MainMenuDeps.maybeOf(context);
    if (deps == null) return;
    if (!MainMenuDestino.financeiro.podeAcessar(deps.usuarioLogado)) return;

    final podeCaixa = UsuarioPermissaoHelper.tem(
      deps.usuarioLogado,
      PermissaoUsuario.acessarCaixa,
    );

    Navigator.push<void>(
      context,
      MaterialPageRoute<void>(
        builder: (_) => MainMenuDeps(
          objectBox: deps.objectBox,
          produtoRepository: deps.produtoRepository,
          clienteRepository: deps.clienteRepository,
          vendaRepository: deps.vendaRepository,
          vendedorRepository: deps.vendedorRepository,
          funcionarioRepository: deps.funcionarioRepository,
          motoristaRepository: deps.motoristaRepository,
          usuarioLogado: deps.usuarioLogado,
          onLogout: deps.onLogout,
          lanSyncScheduler: deps.lanSyncScheduler,
          appConfigRepository: deps.appConfigRepository,
          printService: deps.printService,
          child: ContasReceberPage(
            vendaRepository: deps.vendaRepository,
            clienteRepository: deps.clienteRepository,
            usuarioLogado: deps.usuarioLogado,
            podeRegistrarRecebimento: podeCaixa,
            filtroInicial: filtro,
          ),
        ),
      ),
    );
  }

  static void abrir(BuildContext context, MainMenuDestino destino) {
    final deps = MainMenuDeps.maybeOf(context);
    if (deps == null || !destino.podeAcessar(deps.usuarioLogado)) return;

    final shell = AppShellScope.maybeOf(context);
    if (shell != null) {
      shell.irPara(destino);
      return;
    }

    Navigator.push<void>(
      context,
      MaterialPageRoute<void>(
        builder: (ctx) => MainMenuDeps(
          objectBox: deps.objectBox,
          produtoRepository: deps.produtoRepository,
          clienteRepository: deps.clienteRepository,
          vendaRepository: deps.vendaRepository,
          vendedorRepository: deps.vendedorRepository,
          funcionarioRepository: deps.funcionarioRepository,
          motoristaRepository: deps.motoristaRepository,
          usuarioLogado: deps.usuarioLogado,
          onLogout: deps.onLogout,
          lanSyncScheduler: deps.lanSyncScheduler,
          appConfigRepository: deps.appConfigRepository,
          printService: deps.printService,
          child: pagina(destino, deps),
        ),
      ),
    );
  }

  static Widget pagina(MainMenuDestino destino, MainMenuDeps deps) {
    final u = deps.usuarioLogado;
    switch (destino) {
      case MainMenuDestino.inicio:
        throw ArgumentError('Use MainMenuDashboard para inicio');
      case MainMenuDestino.vendas:
        return VendasPage(
          produtoRepository: deps.produtoRepository,
          clienteRepository: deps.clienteRepository,
          vendaRepository: deps.vendaRepository,
          vendedorRepository: deps.vendedorRepository,
          appConfigRepository: deps.appConfigRepository,
          printService: deps.printService,
          usuarioLogado: u,
          onLogout: deps.onLogout,
          motoristaRepository: deps.motoristaRepository,
        );
      case MainMenuDestino.pdv:
        return PontoDeVendaPage(
          produtoRepository: deps.produtoRepository,
          clienteRepository: deps.clienteRepository,
          vendaRepository: deps.vendaRepository,
          vendedorRepository: deps.vendedorRepository,
          appConfigRepository: deps.appConfigRepository,
          printService: deps.printService,
          usuarioLogado: u,
        );
      case MainMenuDestino.caixa:
        return CaixaPage(
          clienteRepository: deps.clienteRepository,
          produtoRepository: deps.produtoRepository,
          vendaRepository: deps.vendaRepository,
          vendedorRepository: deps.vendedorRepository,
          appConfigRepository: deps.appConfigRepository,
          printService: deps.printService,
          usuarioLogado: u,
          usuarioAtual: u.login,
          podeCancelarVendas: UsuarioPermissaoHelper.podeCancelarVendas(u),
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
        );
      case MainMenuDestino.estoque:
        return EstoquePage(
          produtoRepository: deps.produtoRepository,
          usuarioLogado: u,
        );
      case MainMenuDestino.notasFiscais:
        return NotasFiscaisPage(
          produtoRepository: deps.produtoRepository,
          vendaRepository: deps.vendaRepository,
          clienteRepository: deps.clienteRepository,
          appConfigRepository: deps.appConfigRepository,
          usuarioLogado: u,
        );
      case MainMenuDestino.entregas:
        return EntregasPage(
          vendaRepository: deps.vendaRepository,
          produtoRepository: deps.produtoRepository,
          motoristaRepository: deps.motoristaRepository,
          appConfigRepository: deps.appConfigRepository,
          usuarioAtual: u.login,
          podeGerenciarStatusEntrega:
              UsuarioPermissaoHelper.podeGerenciarEntregas(u),
          podeRegistrarPodEntrega:
              UsuarioPermissaoHelper.podeRegistrarPodEntrega(u),
          podeRegistrarDevolucaoTrocaSemSenha:
              UsuarioPermissaoHelper.podeCancelarVendas(u),
        );
      case MainMenuDestino.financeiro:
        return FinanceiroHubPage(
          objectBox: deps.objectBox,
          vendaRepository: deps.vendaRepository,
          clienteRepository: deps.clienteRepository,
          usuarioLogado: u,
          onLogout: deps.onLogout,
        );
      case MainMenuDestino.cadastros:
        return CadastrosPage(
          produtoRepository: deps.produtoRepository,
          clienteRepository: deps.clienteRepository,
          vendaRepository: deps.vendaRepository,
          vendedorRepository: deps.vendedorRepository,
          funcionarioRepository: deps.funcionarioRepository,
          motoristaRepository: deps.motoristaRepository,
          usuarioLogado: u,
          printService: deps.printService,
          onLogout: deps.onLogout,
        );
      case MainMenuDestino.configuracoes:
        return ConfiguracoesPage(
          vendaRepository: deps.vendaRepository,
          objectBox: deps.produtoRepository.objectBox,
          lanSyncScheduler: deps.lanSyncScheduler,
          appConfigRepository: deps.appConfigRepository,
          printService: deps.printService,
        );
      case MainMenuDestino.motorista:
        return MotoristaEntregasPage(
          vendaRepository: deps.vendaRepository,
          motoristaRepository: deps.motoristaRepository,
          usuarioLogado: u,
          appConfigRepository: deps.appConfigRepository,
        );
    }
  }
}
