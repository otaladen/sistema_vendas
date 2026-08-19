import 'package:flutter/material.dart';

/// Chaves de permissao do ERP (cadastro de usuarios + checagens no app).
enum PermissaoUsuario {
  cadastros,
  estoque,
  /// Modulo Notas Fiscais (NFC-e / NF-e) — isolado do estoque. Alias: PERM_FISCAL.
  fiscal,
  vendasHub,
  acessarPdv,
  acessarCaixa,
  acessarListagemVendas,
  acessarRelatorios,
  leituraParcialCaixa,
  visualizarAuditoriaCaixa,
  manutencaoAuditoriaCaixa,
  visualizarEntregas,
  gerenciarEntregas,
  financeiro,
  configuracoes,
  cancelarVendas,
  autorizarSegundaViaCupom,
  autorizarMargemVenda,
  reajustePrecoLote,
  autorizarReajustePreco,
  alterarPrecoPdv,
  venderFiado,
  verCustoMargem,
  gerenciarUsuarios,
  editarPrecoProduto,
  alterarPrecoUnitarioPdv,
  relatoriosComissao,
  relatoriosFiado,
  relatoriosLogSistema,
  emitirNfeSaida,
  cancelarNfeSaida,
}

/// Metadados para exibir no cadastro de usuarios.
class PermissaoUsuarioInfo {
  const PermissaoUsuarioInfo({
    required this.chave,
    required this.titulo,
    required this.descricao,
    required this.grupo,
    this.dependeDe,
  });

  final PermissaoUsuario chave;
  final String titulo;
  final String descricao;
  final PermissaoGrupo grupo;

  /// Outra permissao que costuma ser necessaria (apenas dica na UI).
  final PermissaoUsuario? dependeDe;
}

enum PermissaoGrupo {
  modulosMenu,
  vendasCaixa,
  logistica,
  financeiroConfig,
  autorizacoesGerente,
  administracao,
}

extension PermissaoGrupoExt on PermissaoGrupo {
  String get titulo {
    switch (this) {
      case PermissaoGrupo.modulosMenu:
        return 'Modulos do menu principal';
      case PermissaoGrupo.vendasCaixa:
        return 'Vendas e caixa';
      case PermissaoGrupo.logistica:
        return 'Logistica e entregas';
      case PermissaoGrupo.financeiroConfig:
        return 'Financeiro e configuracoes';
      case PermissaoGrupo.autorizacoesGerente:
        return 'Autorizacoes de gerente';
      case PermissaoGrupo.administracao:
        return 'Administracao';
    }
  }

  IconData get icone {
    switch (this) {
      case PermissaoGrupo.modulosMenu:
        return Icons.dashboard_outlined;
      case PermissaoGrupo.vendasCaixa:
        return Icons.point_of_sale_outlined;
      case PermissaoGrupo.logistica:
        return Icons.local_shipping_outlined;
      case PermissaoGrupo.financeiroConfig:
        return Icons.account_balance_wallet_outlined;
      case PermissaoGrupo.autorizacoesGerente:
        return Icons.verified_user_outlined;
      case PermissaoGrupo.administracao:
        return Icons.admin_panel_settings_outlined;
    }
  }
}

/// Catalogo ordenado de permissoes para a tela de usuarios.
class PermissaoUsuarioCatalogo {
  PermissaoUsuarioCatalogo._();

  static const ordemGrupos = PermissaoGrupo.values;

  static const itens = <PermissaoUsuarioInfo>[
    PermissaoUsuarioInfo(
      chave: PermissaoUsuario.cadastros,
      titulo: 'Cadastros',
      descricao: 'Produtos, clientes, vendedores, motoristas e demais cadastros.',
      grupo: PermissaoGrupo.modulosMenu,
    ),
    PermissaoUsuarioInfo(
      chave: PermissaoUsuario.estoque,
      titulo: 'Estoque',
      descricao: 'Entrada de mercadoria, produtos e movimentacoes.',
      grupo: PermissaoGrupo.modulosMenu,
    ),
    PermissaoUsuarioInfo(
      chave: PermissaoUsuario.fiscal,
      titulo: 'Fiscal (NFC-e / NF-e)',
      descricao:
          'Modulo fiscal: importacao, pendencias, emissao e fechamento. '
          '(PERM_FISCAL)',
      grupo: PermissaoGrupo.modulosMenu,
    ),
    PermissaoUsuarioInfo(
      chave: PermissaoUsuario.vendasHub,
      titulo: 'Hub Vendas (menu)',
      descricao: 'Abre o modulo Vendas no menu principal.',
      grupo: PermissaoGrupo.modulosMenu,
    ),
    PermissaoUsuarioInfo(
      chave: PermissaoUsuario.acessarPdv,
      titulo: 'Ponto de venda (PDV)',
      descricao: 'Orcamentos e vendas no balcao.',
      grupo: PermissaoGrupo.vendasCaixa,
      dependeDe: PermissaoUsuario.vendasHub,
    ),
    PermissaoUsuarioInfo(
      chave: PermissaoUsuario.acessarCaixa,
      titulo: 'Caixa',
      descricao: 'Abertura, fechamento e movimentos do caixa.',
      grupo: PermissaoGrupo.vendasCaixa,
      dependeDe: PermissaoUsuario.vendasHub,
    ),
    PermissaoUsuarioInfo(
      chave: PermissaoUsuario.acessarListagemVendas,
      titulo: 'Listagem de vendas',
      descricao:
          'Consulta historico de pedidos, filtros e reimpressao (independente do caixa).',
      grupo: PermissaoGrupo.vendasCaixa,
      dependeDe: PermissaoUsuario.vendasHub,
    ),
    PermissaoUsuarioInfo(
      chave: PermissaoUsuario.acessarRelatorios,
      titulo: 'Relatorios de vendas',
      descricao: 'Relatorios gerenciais dentro do modulo Vendas.',
      grupo: PermissaoGrupo.vendasCaixa,
      dependeDe: PermissaoUsuario.vendasHub,
    ),
    PermissaoUsuarioInfo(
      chave: PermissaoUsuario.leituraParcialCaixa,
      titulo: 'Leitura parcial do caixa',
      descricao:
          'Botao "Leitura parcial" na tela de caixa (totais por forma de pagamento).',
      grupo: PermissaoGrupo.vendasCaixa,
      dependeDe: PermissaoUsuario.acessarCaixa,
    ),
    PermissaoUsuarioInfo(
      chave: PermissaoUsuario.visualizarAuditoriaCaixa,
      titulo: 'Auditoria do caixa (consultar)',
      descricao:
          'Botao "Auditoria" na tela de caixa: ver historico, filtrar e exportar.',
      grupo: PermissaoGrupo.vendasCaixa,
      dependeDe: PermissaoUsuario.acessarCaixa,
    ),
    PermissaoUsuarioInfo(
      chave: PermissaoUsuario.manutencaoAuditoriaCaixa,
      titulo: 'Auditoria do caixa (manutencao)',
      descricao:
          'Dentro da auditoria: limpar registros antigos e executar manutencao.',
      grupo: PermissaoGrupo.vendasCaixa,
      dependeDe: PermissaoUsuario.visualizarAuditoriaCaixa,
    ),
    PermissaoUsuarioInfo(
      chave: PermissaoUsuario.visualizarEntregas,
      titulo: 'Visualizar entregas',
      descricao: 'Ver fila, romaneio e mapa (somente leitura).',
      grupo: PermissaoGrupo.logistica,
    ),
    PermissaoUsuarioInfo(
      chave: PermissaoUsuario.gerenciarEntregas,
      titulo: 'Gerenciar entregas',
      descricao: 'Alterar status, montagem de carga, motorista e impressao.',
      grupo: PermissaoGrupo.logistica,
      dependeDe: PermissaoUsuario.visualizarEntregas,
    ),
    PermissaoUsuarioInfo(
      chave: PermissaoUsuario.financeiro,
      titulo: 'Financeiro',
      descricao: 'Contas a pagar e rotinas financeiras.',
      grupo: PermissaoGrupo.financeiroConfig,
    ),
    PermissaoUsuarioInfo(
      chave: PermissaoUsuario.configuracoes,
      titulo: 'Configuracoes',
      descricao: 'Empresa, impressao, rede e parametros do sistema.',
      grupo: PermissaoGrupo.financeiroConfig,
    ),
    PermissaoUsuarioInfo(
      chave: PermissaoUsuario.cancelarVendas,
      titulo: 'Cancelar vendas e devolucoes',
      descricao: 'Cancelar pedidos e registrar devolucao/troca sem senha de gerente.',
      grupo: PermissaoGrupo.autorizacoesGerente,
    ),
    PermissaoUsuarioInfo(
      chave: PermissaoUsuario.autorizarSegundaViaCupom,
      titulo: 'Autorizar segunda via do cupom',
      descricao: 'Login/senha para reimpressao de cupom.',
      grupo: PermissaoGrupo.autorizacoesGerente,
    ),
    PermissaoUsuarioInfo(
      chave: PermissaoUsuario.autorizarMargemVenda,
      titulo: 'Autorizar margem promocional',
      descricao: 'Libera venda abaixo da margem minima da campanha no PDV.',
      grupo: PermissaoGrupo.autorizacoesGerente,
    ),
    PermissaoUsuarioInfo(
      chave: PermissaoUsuario.reajustePrecoLote,
      titulo: 'Reajuste de precos em lote',
      descricao: 'Executa assistente de reajuste no Estoque (perfil Gerente/Dono).',
      grupo: PermissaoGrupo.autorizacoesGerente,
      dependeDe: PermissaoUsuario.estoque,
    ),
    PermissaoUsuarioInfo(
      chave: PermissaoUsuario.autorizarReajustePreco,
      titulo: 'Autorizar reajuste com alertas',
      descricao: 'Aprova reajuste com margem/variacao/custo fora do padrao.',
      grupo: PermissaoGrupo.autorizacoesGerente,
    ),
    PermissaoUsuarioInfo(
      chave: PermissaoUsuario.alterarPrecoPdv,
      titulo: 'Desconto manual no PDV',
      descricao: 'Aplica desconto manual no checkout alem do teto automatico.',
      grupo: PermissaoGrupo.autorizacoesGerente,
      dependeDe: PermissaoUsuario.acessarPdv,
    ),
    PermissaoUsuarioInfo(
      chave: PermissaoUsuario.venderFiado,
      titulo: 'Vender a prazo (fiado)',
      descricao: 'Permite forma de pagamento fiado no PDV.',
      grupo: PermissaoGrupo.autorizacoesGerente,
      dependeDe: PermissaoUsuario.acessarPdv,
    ),
    PermissaoUsuarioInfo(
      chave: PermissaoUsuario.verCustoMargem,
      titulo: 'Ver custo e margem',
      descricao: 'Exibe custo em estoque, relatorios e exportacoes com custo.',
      grupo: PermissaoGrupo.autorizacoesGerente,
      dependeDe: PermissaoUsuario.estoque,
    ),
    PermissaoUsuarioInfo(
      chave: PermissaoUsuario.gerenciarUsuarios,
      titulo: 'Gerenciar usuarios',
      descricao: 'Cadastrar, editar e remover usuarios do sistema.',
      grupo: PermissaoGrupo.administracao,
    ),
    PermissaoUsuarioInfo(
      chave: PermissaoUsuario.editarPrecoProduto,
      titulo: 'Editar preco no cadastro de produtos',
      descricao: 'Altera precos de venda/custo no cadastro de produtos.',
      grupo: PermissaoGrupo.modulosMenu,
      dependeDe: PermissaoUsuario.cadastros,
    ),
    PermissaoUsuarioInfo(
      chave: PermissaoUsuario.alterarPrecoUnitarioPdv,
      titulo: 'Alterar preco unitario no PDV',
      descricao: 'Permite ajustar manualmente o preco de um item no carrinho.',
      grupo: PermissaoGrupo.autorizacoesGerente,
      dependeDe: PermissaoUsuario.acessarPdv,
    ),
    PermissaoUsuarioInfo(
      chave: PermissaoUsuario.relatoriosComissao,
      titulo: 'Relatorio de comissao',
      descricao: 'Acessa relatorio de comissao de vendedores.',
      grupo: PermissaoGrupo.vendasCaixa,
      dependeDe: PermissaoUsuario.acessarRelatorios,
    ),
    PermissaoUsuarioInfo(
      chave: PermissaoUsuario.relatoriosFiado,
      titulo: 'Relatorio de fiados',
      descricao: 'Acessa relatorio de titulos/fiados em aberto.',
      grupo: PermissaoGrupo.vendasCaixa,
      dependeDe: PermissaoUsuario.acessarRelatorios,
    ),
    PermissaoUsuarioInfo(
      chave: PermissaoUsuario.relatoriosLogSistema,
      titulo: 'Log do sistema',
      descricao: 'Acessa auditoria e log central do ERP.',
      grupo: PermissaoGrupo.administracao,
      dependeDe: PermissaoUsuario.acessarRelatorios,
    ),
    PermissaoUsuarioInfo(
      chave: PermissaoUsuario.emitirNfeSaida,
      titulo: 'Emitir NF-e de saida (55)',
      descricao: 'Painel NF-e / Focus — faturamento construtoras.',
      grupo: PermissaoGrupo.autorizacoesGerente,
      dependeDe: PermissaoUsuario.fiscal,
    ),
    PermissaoUsuarioInfo(
      chave: PermissaoUsuario.cancelarNfeSaida,
      titulo: 'Cancelar NF-e de saida',
      descricao: 'Cancelamento e carta de correcao na SEFAZ.',
      grupo: PermissaoGrupo.autorizacoesGerente,
      dependeDe: PermissaoUsuario.emitirNfeSaida,
    ),
  ];

  static List<PermissaoUsuarioInfo> porGrupo(PermissaoGrupo grupo) =>
      itens.where((i) => i.grupo == grupo).toList();
}
