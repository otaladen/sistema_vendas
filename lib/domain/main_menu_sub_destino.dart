import 'package:flutter/material.dart';

import '../model/usuario_sistema.dart';
import 'main_menu_destino.dart';
import 'permissao_usuario.dart';
import 'usuario_permissao_helper.dart';

/// Sub-rotas dos modulos com menu expansivel no shell desktop.
enum MainMenuSubDestino {
  vendasOrcamentos,
  vendasListagem,
  vendasRelatorios,
  cadastrosProdutos,
  cadastrosKitsOrcamento,
  cadastrosPromocoes,
  cadastrosMotoristas,
  cadastrosFuncionarios,
  cadastrosClientes,
  cadastrosVendedores,
  cadastrosUsuarios,
  fiscalImportarNfe,
  fiscalNotasImportadas,
  fiscalDevolucaoFornecedor,
  fiscalPendencias,
  fiscalNfeSaida,
  fiscalRelatorioMensal,
  fiscalExportarFechamento,
  financeiroTesouraria,
  financeiroContasReceber,
  financeiroContasPagar,
  financeiroRelatorioContasPagar,
  financeiroRelatorioFiados,
}

extension MainMenuSubDestinoExt on MainMenuSubDestino {
  MainMenuDestino get pai {
    switch (this) {
      case MainMenuSubDestino.vendasOrcamentos:
      case MainMenuSubDestino.vendasListagem:
      case MainMenuSubDestino.vendasRelatorios:
        return MainMenuDestino.vendas;
      case MainMenuSubDestino.cadastrosProdutos:
      case MainMenuSubDestino.cadastrosKitsOrcamento:
      case MainMenuSubDestino.cadastrosPromocoes:
      case MainMenuSubDestino.cadastrosMotoristas:
      case MainMenuSubDestino.cadastrosFuncionarios:
      case MainMenuSubDestino.cadastrosClientes:
      case MainMenuSubDestino.cadastrosVendedores:
      case MainMenuSubDestino.cadastrosUsuarios:
        return MainMenuDestino.cadastros;
      case MainMenuSubDestino.fiscalImportarNfe:
      case MainMenuSubDestino.fiscalNotasImportadas:
      case MainMenuSubDestino.fiscalDevolucaoFornecedor:
      case MainMenuSubDestino.fiscalPendencias:
      case MainMenuSubDestino.fiscalNfeSaida:
      case MainMenuSubDestino.fiscalRelatorioMensal:
      case MainMenuSubDestino.fiscalExportarFechamento:
        return MainMenuDestino.notasFiscais;
      case MainMenuSubDestino.financeiroTesouraria:
      case MainMenuSubDestino.financeiroContasReceber:
      case MainMenuSubDestino.financeiroContasPagar:
      case MainMenuSubDestino.financeiroRelatorioContasPagar:
      case MainMenuSubDestino.financeiroRelatorioFiados:
        return MainMenuDestino.financeiro;
    }
  }

  String get titulo {
    switch (this) {
      case MainMenuSubDestino.vendasOrcamentos:
        return 'Orcamentos';
      case MainMenuSubDestino.vendasListagem:
        return 'Listagem de vendas';
      case MainMenuSubDestino.vendasRelatorios:
        return 'Relatorios';
      case MainMenuSubDestino.cadastrosProdutos:
        return 'Produtos';
      case MainMenuSubDestino.cadastrosKitsOrcamento:
        return 'Kits de orcamento';
      case MainMenuSubDestino.cadastrosPromocoes:
        return 'Promocoes';
      case MainMenuSubDestino.cadastrosMotoristas:
        return 'Motoristas';
      case MainMenuSubDestino.cadastrosFuncionarios:
        return 'Funcionarios';
      case MainMenuSubDestino.cadastrosClientes:
        return 'Clientes';
      case MainMenuSubDestino.cadastrosVendedores:
        return 'Vendedores';
      case MainMenuSubDestino.cadastrosUsuarios:
        return 'Usuarios';
      case MainMenuSubDestino.fiscalImportarNfe:
        return 'Importar NF-e (XML)';
      case MainMenuSubDestino.fiscalNotasImportadas:
        return 'Notas ja importadas';
      case MainMenuSubDestino.fiscalDevolucaoFornecedor:
        return 'Devolucao ao fornecedor';
      case MainMenuSubDestino.fiscalPendencias:
        return 'Pendencias fiscais';
      case MainMenuSubDestino.fiscalNfeSaida:
        return 'NF-e de saida (55)';
      case MainMenuSubDestino.fiscalRelatorioMensal:
        return 'Relatorio fiscal do mes';
      case MainMenuSubDestino.fiscalExportarFechamento:
        return 'Exportar fechamento';
      case MainMenuSubDestino.financeiroTesouraria:
        return 'Tesouraria semanal';
      case MainMenuSubDestino.financeiroContasReceber:
        return 'Contas a receber';
      case MainMenuSubDestino.financeiroContasPagar:
        return 'Contas a pagar';
      case MainMenuSubDestino.financeiroRelatorioContasPagar:
        return 'Relatorio contas a pagar';
      case MainMenuSubDestino.financeiroRelatorioFiados:
        return 'Relatorio de fiados';
    }
  }

  IconData get icone {
    switch (this) {
      case MainMenuSubDestino.vendasOrcamentos:
        return Icons.request_quote_outlined;
      case MainMenuSubDestino.vendasListagem:
        return Icons.view_list_outlined;
      case MainMenuSubDestino.vendasRelatorios:
        return Icons.assessment_outlined;
      case MainMenuSubDestino.cadastrosProdutos:
        return Icons.inventory_2_outlined;
      case MainMenuSubDestino.cadastrosKitsOrcamento:
        return Icons.widgets_outlined;
      case MainMenuSubDestino.cadastrosPromocoes:
        return Icons.local_offer_outlined;
      case MainMenuSubDestino.cadastrosMotoristas:
        return Icons.local_shipping_outlined;
      case MainMenuSubDestino.cadastrosFuncionarios:
        return Icons.badge_outlined;
      case MainMenuSubDestino.cadastrosClientes:
        return Icons.people_outline;
      case MainMenuSubDestino.cadastrosVendedores:
        return Icons.storefront_outlined;
      case MainMenuSubDestino.cadastrosUsuarios:
        return Icons.manage_accounts_outlined;
      case MainMenuSubDestino.fiscalImportarNfe:
        return Icons.receipt_long_outlined;
      case MainMenuSubDestino.fiscalNotasImportadas:
        return Icons.fact_check_outlined;
      case MainMenuSubDestino.fiscalDevolucaoFornecedor:
        return Icons.assignment_return_outlined;
      case MainMenuSubDestino.fiscalPendencias:
        return Icons.pending_actions_outlined;
      case MainMenuSubDestino.fiscalNfeSaida:
        return Icons.description_outlined;
      case MainMenuSubDestino.fiscalRelatorioMensal:
        return Icons.analytics_outlined;
      case MainMenuSubDestino.fiscalExportarFechamento:
        return Icons.folder_zip_outlined;
      case MainMenuSubDestino.financeiroTesouraria:
        return Icons.calendar_view_week_outlined;
      case MainMenuSubDestino.financeiroContasReceber:
        return Icons.call_received_outlined;
      case MainMenuSubDestino.financeiroContasPagar:
        return Icons.call_made_outlined;
      case MainMenuSubDestino.financeiroRelatorioContasPagar:
        return Icons.receipt_long_outlined;
      case MainMenuSubDestino.financeiroRelatorioFiados:
        return Icons.assessment_outlined;
    }
  }

  bool podeAcessar(UsuarioSistema u) {
    switch (this) {
      case MainMenuSubDestino.vendasOrcamentos:
        return UsuarioPermissaoHelper.tem(u, PermissaoUsuario.acessarPdv) ||
            UsuarioPermissaoHelper.tem(u, PermissaoUsuario.acessarCaixa) ||
            UsuarioPermissaoHelper.tem(u, PermissaoUsuario.acessarListagemVendas);
      case MainMenuSubDestino.vendasListagem:
        return UsuarioPermissaoHelper.tem(
          u,
          PermissaoUsuario.acessarListagemVendas,
        );
      case MainMenuSubDestino.vendasRelatorios:
        return UsuarioPermissaoHelper.tem(u, PermissaoUsuario.acessarRelatorios);
      case MainMenuSubDestino.cadastrosUsuarios:
        return UsuarioPermissaoHelper.tem(
          u,
          PermissaoUsuario.gerenciarUsuarios,
        );
      case MainMenuSubDestino.cadastrosProdutos:
      case MainMenuSubDestino.cadastrosKitsOrcamento:
      case MainMenuSubDestino.cadastrosPromocoes:
      case MainMenuSubDestino.cadastrosMotoristas:
      case MainMenuSubDestino.cadastrosFuncionarios:
      case MainMenuSubDestino.cadastrosClientes:
      case MainMenuSubDestino.cadastrosVendedores:
        return UsuarioPermissaoHelper.tem(u, PermissaoUsuario.cadastros);
      case MainMenuSubDestino.fiscalImportarNfe:
      case MainMenuSubDestino.fiscalNotasImportadas:
      case MainMenuSubDestino.fiscalDevolucaoFornecedor:
      case MainMenuSubDestino.fiscalPendencias:
      case MainMenuSubDestino.fiscalNfeSaida:
      case MainMenuSubDestino.fiscalRelatorioMensal:
      case MainMenuSubDestino.fiscalExportarFechamento:
        return UsuarioPermissaoHelper.tem(u, PermissaoUsuario.estoque);
      case MainMenuSubDestino.financeiroTesouraria:
      case MainMenuSubDestino.financeiroContasReceber:
      case MainMenuSubDestino.financeiroContasPagar:
      case MainMenuSubDestino.financeiroRelatorioContasPagar:
        return UsuarioPermissaoHelper.tem(u, PermissaoUsuario.financeiro);
      case MainMenuSubDestino.financeiroRelatorioFiados:
        return UsuarioPermissaoHelper.tem(u, PermissaoUsuario.relatoriosFiado);
    }
  }
}

abstract final class MainMenuSubDestinoHelper {
  MainMenuSubDestinoHelper._();

  static const modulosComSubmenu = {
    MainMenuDestino.vendas,
    MainMenuDestino.cadastros,
    MainMenuDestino.notasFiscais,
    MainMenuDestino.financeiro,
  };

  static bool moduloTemSubmenu(MainMenuDestino destino) =>
      modulosComSubmenu.contains(destino);

  static const _vendas = [
    MainMenuSubDestino.vendasOrcamentos,
    MainMenuSubDestino.vendasListagem,
    MainMenuSubDestino.vendasRelatorios,
  ];

  static const _cadastros = [
    MainMenuSubDestino.cadastrosProdutos,
    MainMenuSubDestino.cadastrosKitsOrcamento,
    MainMenuSubDestino.cadastrosPromocoes,
    MainMenuSubDestino.cadastrosMotoristas,
    MainMenuSubDestino.cadastrosFuncionarios,
    MainMenuSubDestino.cadastrosClientes,
    MainMenuSubDestino.cadastrosVendedores,
    MainMenuSubDestino.cadastrosUsuarios,
  ];

  static const _fiscal = [
    MainMenuSubDestino.fiscalImportarNfe,
    MainMenuSubDestino.fiscalNotasImportadas,
    MainMenuSubDestino.fiscalDevolucaoFornecedor,
    MainMenuSubDestino.fiscalPendencias,
    MainMenuSubDestino.fiscalNfeSaida,
    MainMenuSubDestino.fiscalRelatorioMensal,
    MainMenuSubDestino.fiscalExportarFechamento,
  ];

  static const _financeiro = [
    MainMenuSubDestino.financeiroTesouraria,
    MainMenuSubDestino.financeiroContasReceber,
    MainMenuSubDestino.financeiroContasPagar,
    MainMenuSubDestino.financeiroRelatorioContasPagar,
    MainMenuSubDestino.financeiroRelatorioFiados,
  ];

  static List<MainMenuSubDestino> subitensDe(
    MainMenuDestino pai,
    UsuarioSistema usuario,
  ) {
    final lista = switch (pai) {
      MainMenuDestino.vendas => _vendas,
      MainMenuDestino.cadastros => _cadastros,
      MainMenuDestino.notasFiscais => _fiscal,
      MainMenuDestino.financeiro => _financeiro,
      _ => const <MainMenuSubDestino>[],
    };
    return [
      for (final s in lista)
        if (s.podeAcessar(usuario)) s,
    ];
  }

  static MainMenuSubDestino? primeiroPermitido(
    MainMenuDestino pai,
    UsuarioSistema usuario,
  ) {
    final subs = subitensDe(pai, usuario);
    return subs.isEmpty ? null : subs.first;
  }
}
