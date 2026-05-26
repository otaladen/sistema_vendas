import '../model/usuario_sistema.dart';

/// Perfis operacionais da loja de material de construcao.
enum PerfilUsuarioPreset {
  customizado,
  vendedor,
  caixa,
  separador,
  motorista,
  comprador,
  gerente,
  dono,
}

extension PerfilUsuarioPresetExt on PerfilUsuarioPreset {
  String get id {
    switch (this) {
      case PerfilUsuarioPreset.customizado:
        return 'customizado';
      case PerfilUsuarioPreset.vendedor:
        return 'vendedor';
      case PerfilUsuarioPreset.caixa:
        return 'caixa';
      case PerfilUsuarioPreset.separador:
        return 'separador';
      case PerfilUsuarioPreset.motorista:
        return 'motorista';
      case PerfilUsuarioPreset.comprador:
        return 'comprador';
      case PerfilUsuarioPreset.gerente:
        return 'gerente';
      case PerfilUsuarioPreset.dono:
        return 'dono';
    }
  }

  String get rotulo {
    switch (this) {
      case PerfilUsuarioPreset.customizado:
        return 'Personalizado';
      case PerfilUsuarioPreset.vendedor:
        return 'Vendedor';
      case PerfilUsuarioPreset.caixa:
        return 'Caixa';
      case PerfilUsuarioPreset.separador:
        return 'Separador';
      case PerfilUsuarioPreset.motorista:
        return 'Motorista';
      case PerfilUsuarioPreset.comprador:
        return 'Comprador';
      case PerfilUsuarioPreset.gerente:
        return 'Gerente';
      case PerfilUsuarioPreset.dono:
        return 'Dono';
    }
  }
}

PerfilUsuarioPreset perfilUsuarioFromId(String? raw) {
  final id = (raw ?? '').trim().toLowerCase();
  for (final p in PerfilUsuarioPreset.values) {
    if (p.id == id) return p;
  }
  return PerfilUsuarioPreset.customizado;
}

/// Aplica pacote de permissoes ao usuario (preserva id, nome, login, senha, ativo).
class PerfilUsuarioPresetAplicador {
  PerfilUsuarioPresetAplicador._();

  static UsuarioSistema aplicar(UsuarioSistema base, PerfilUsuarioPreset perfil) {
    final flags = _flagsPara(perfil);
    return base.copyWith(
      perfil: perfil.id,
      admin: flags.admin,
      podeCadastros: flags.podeCadastros,
      podeEstoque: flags.podeEstoque,
      podeVendas: flags.podeVendas,
      podeCaixa: flags.podeCaixa,
      podeAcessarPdv: flags.podeAcessarPdv,
      podeAcessarCaixa: flags.podeAcessarCaixa,
      podeAcessarListagemVendas: flags.podeAcessarListagemVendas,
      podeAcessarRelatorios: flags.podeAcessarRelatorios,
      podeLeituraParcialCaixa: flags.podeLeituraParcialCaixa,
      podeVisualizarAuditoriaCaixa: flags.podeVisualizarAuditoriaCaixa,
      podeManutencaoAuditoriaCaixa: flags.podeManutencaoAuditoriaCaixa,
      podeEntregas: flags.podeEntregas,
      podeVisualizarEntregas: flags.podeVisualizarEntregas,
      podeGerenciarEntregas: flags.podeGerenciarEntregas,
      podeFinanceiro: flags.podeFinanceiro,
      podeConfiguracoes: flags.podeConfiguracoes,
      podeCancelarVendas: flags.podeCancelarVendas,
      podeAutorizarSegundaViaCupom: flags.podeAutorizarSegundaViaCupom,
      podeAutorizarMargemVenda: flags.podeAutorizarMargemVenda,
      podeReajustePrecoLote: flags.podeReajustePrecoLote,
      podeAutorizarReajustePreco: flags.podeAutorizarReajustePreco,
      podeAlterarPrecoPdv: flags.podeAlterarPrecoPdv,
      podeVenderFiado: flags.podeVenderFiado,
      podeVerCustoMargem: flags.podeVerCustoMargem,
      podeGerenciarUsuarios: flags.podeGerenciarUsuarios,
      podeEditarPrecoProduto: flags.podeEditarPrecoProduto,
      podeAlterarPrecoUnitarioPdv: flags.podeAlterarPrecoUnitarioPdv,
      podeRelatoriosComissao: flags.podeRelatoriosComissao,
      podeRelatoriosFiado: flags.podeRelatoriosFiado,
      podeRelatoriosLogSistema: flags.podeRelatoriosLogSistema,
      podeEmitirNfeSaida: flags.podeEmitirNfeSaida,
      podeCancelarNfeSaida: flags.podeCancelarNfeSaida,
      descontoMaximoPercentualPdv: flags.descontoMaximoPercentualPdv,
      limparDescontoMaximoPdv: flags.descontoMaximoPercentualPdv == null,
    );
  }

  static _FlagsPerfil _flagsPara(PerfilUsuarioPreset perfil) {
    switch (perfil) {
      case PerfilUsuarioPreset.dono:
        return const _FlagsPerfil(
          admin: true,
          podeCadastros: true,
          podeEstoque: true,
          podeVendas: true,
          podeCaixa: true,
          podeAcessarPdv: true,
          podeAcessarCaixa: true,
          podeAcessarListagemVendas: true,
          podeAcessarRelatorios: true,
          podeLeituraParcialCaixa: true,
          podeVisualizarAuditoriaCaixa: true,
          podeManutencaoAuditoriaCaixa: true,
          podeEntregas: true,
          podeVisualizarEntregas: true,
          podeGerenciarEntregas: true,
          podeFinanceiro: true,
          podeConfiguracoes: true,
          podeCancelarVendas: true,
          podeAutorizarSegundaViaCupom: true,
          podeAutorizarMargemVenda: true,
          podeReajustePrecoLote: true,
          podeAutorizarReajustePreco: true,
          podeAlterarPrecoPdv: true,
          podeVenderFiado: true,
          podeVerCustoMargem: true,
          podeGerenciarUsuarios: true,
          podeEditarPrecoProduto: true,
          podeAlterarPrecoUnitarioPdv: true,
          podeRelatoriosComissao: true,
          podeRelatoriosFiado: true,
          podeRelatoriosLogSistema: true,
          podeEmitirNfeSaida: true,
          podeCancelarNfeSaida: true,
        );
      case PerfilUsuarioPreset.gerente:
        return const _FlagsPerfil(
          podeCadastros: true,
          podeEstoque: true,
          podeVendas: true,
          podeCaixa: true,
          podeAcessarPdv: true,
          podeAcessarCaixa: true,
          podeAcessarListagemVendas: true,
          podeAcessarRelatorios: true,
          podeLeituraParcialCaixa: true,
          podeVisualizarAuditoriaCaixa: true,
          podeManutencaoAuditoriaCaixa: true,
          podeEntregas: true,
          podeVisualizarEntregas: true,
          podeGerenciarEntregas: true,
          podeFinanceiro: true,
          podeConfiguracoes: true,
          podeCancelarVendas: true,
          podeAutorizarSegundaViaCupom: true,
          podeAutorizarMargemVenda: true,
          podeReajustePrecoLote: true,
          podeAutorizarReajustePreco: true,
          podeAlterarPrecoPdv: true,
          podeVenderFiado: true,
          podeVerCustoMargem: true,
          podeEditarPrecoProduto: true,
          podeAlterarPrecoUnitarioPdv: true,
          podeRelatoriosComissao: true,
          podeRelatoriosFiado: true,
          podeRelatoriosLogSistema: true,
          podeEmitirNfeSaida: true,
          podeCancelarNfeSaida: true,
        );
      case PerfilUsuarioPreset.vendedor:
        return const _FlagsPerfil(
          podeVendas: true,
          podeAcessarPdv: true,
          podeAcessarListagemVendas: true,
          descontoMaximoPercentualPdv: 8,
        );
      case PerfilUsuarioPreset.caixa:
        return const _FlagsPerfil(
          podeVendas: true,
          podeCaixa: true,
          podeAcessarCaixa: true,
        );
      case PerfilUsuarioPreset.separador:
        return const _FlagsPerfil(
          podeVisualizarEntregas: true,
          podeGerenciarEntregas: true,
          podeEntregas: true,
        );
      case PerfilUsuarioPreset.motorista:
        return const _FlagsPerfil(
          podeVisualizarEntregas: true,
          podeEntregas: true,
        );
      case PerfilUsuarioPreset.comprador:
        return const _FlagsPerfil(
          podeCadastros: true,
          podeEstoque: true,
          podeVerCustoMargem: true,
        );
      case PerfilUsuarioPreset.customizado:
        return const _FlagsPerfil();
    }
  }
}

class _FlagsPerfil {
  const _FlagsPerfil({
    this.admin = false,
    this.podeCadastros = false,
    this.podeEstoque = false,
    this.podeVendas = false,
    this.podeCaixa = false,
    this.podeAcessarPdv = false,
    this.podeAcessarCaixa = false,
    this.podeAcessarListagemVendas = false,
    this.podeAcessarRelatorios = false,
    this.podeLeituraParcialCaixa = false,
    this.podeVisualizarAuditoriaCaixa = false,
    this.podeManutencaoAuditoriaCaixa = false,
    this.podeEntregas = false,
    this.podeVisualizarEntregas = false,
    this.podeGerenciarEntregas = false,
    this.podeFinanceiro = false,
    this.podeConfiguracoes = false,
    this.podeCancelarVendas = false,
    this.podeAutorizarSegundaViaCupom = false,
    this.podeAutorizarMargemVenda = false,
    this.podeReajustePrecoLote = false,
    this.podeAutorizarReajustePreco = false,
    this.podeAlterarPrecoPdv = false,
    this.podeVenderFiado = false,
    this.podeVerCustoMargem = false,
    this.podeGerenciarUsuarios = false,
    this.podeEditarPrecoProduto = false,
    this.podeAlterarPrecoUnitarioPdv = false,
    this.podeRelatoriosComissao = false,
    this.podeRelatoriosFiado = false,
    this.podeRelatoriosLogSistema = false,
    this.podeEmitirNfeSaida = false,
    this.podeCancelarNfeSaida = false,
    this.descontoMaximoPercentualPdv,
  });

  final bool admin;
  final bool podeCadastros;
  final bool podeEstoque;
  final bool podeVendas;
  final bool podeCaixa;
  final bool podeAcessarPdv;
  final bool podeAcessarCaixa;
  final bool podeAcessarListagemVendas;
  final bool podeAcessarRelatorios;
  final bool podeLeituraParcialCaixa;
  final bool podeVisualizarAuditoriaCaixa;
  final bool podeManutencaoAuditoriaCaixa;
  final bool podeEntregas;
  final bool podeVisualizarEntregas;
  final bool podeGerenciarEntregas;
  final bool podeFinanceiro;
  final bool podeConfiguracoes;
  final bool podeCancelarVendas;
  final bool podeAutorizarSegundaViaCupom;
  final bool podeAutorizarMargemVenda;
  final bool podeReajustePrecoLote;
  final bool podeAutorizarReajustePreco;
  final bool podeAlterarPrecoPdv;
  final bool podeVenderFiado;
  final bool podeVerCustoMargem;
  final bool podeGerenciarUsuarios;
  final bool podeEditarPrecoProduto;
  final bool podeAlterarPrecoUnitarioPdv;
  final bool podeRelatoriosComissao;
  final bool podeRelatoriosFiado;
  final bool podeRelatoriosLogSistema;
  final bool podeEmitirNfeSaida;
  final bool podeCancelarNfeSaida;
  final double? descontoMaximoPercentualPdv;
}
