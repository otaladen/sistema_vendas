import '../model/usuario_sistema.dart';
import 'perfil_usuario_preset.dart';
import 'permissao_usuario.dart';

/// Politica minima de senha (Fase C).
class PoliticaSenhaUsuario {
  PoliticaSenhaUsuario._();

  static const int tamanhoMinimo = 4;

  static const int loginMinimo = 3;

  static String? validarLogin(String login) {
    final l = login.trim();
    if (l.length < loginMinimo) {
      return 'Login deve ter pelo menos $loginMinimo caracteres.';
    }
    if (!RegExp(r'^[a-zA-Z0-9._-]+$').hasMatch(l)) {
      return 'Login: use apenas letras, numeros, ponto, traco e sublinhado.';
    }
    return null;
  }

  static String? validar(String senha) {
    final s = senha.trim();
    if (s.length < tamanhoMinimo) {
      return 'Senha deve ter pelo menos $tamanhoMinimo caracteres.';
    }
    return null;
  }

  static String? validarParaSalvar({
    required bool criacao,
    required String senhaDigitada,
  }) {
    if (criacao && senhaDigitada.trim().isEmpty) {
      return 'Informe a senha do usuario.';
    }
    if (senhaDigitada.isNotEmpty) {
      return validar(senhaDigitada);
    }
    return null;
  }
}

extension UsuarioDescontoPdvExt on UsuarioSistema {
  /// Teto efetivo de desconto no PDV (%): perfil do usuario ou padrao da empresa.
  double tetoDescontoPercentualPdv(double padraoEmpresa) {
    if (admin || podeAlterarPrecoPdv) {
      return padraoEmpresa;
    }
    final t = descontoMaximoPercentualPdv;
    if (t != null && t >= 0) return t;
    return padraoEmpresa;
  }
}

/// Checagens centralizadas de permissao.
class UsuarioPermissaoHelper {
  UsuarioPermissaoHelper._();

  static bool tem(UsuarioSistema u, PermissaoUsuario p) {
    if (!u.ativo) return false;
    if (u.admin) return true;
    switch (p) {
      case PermissaoUsuario.cadastros:
        return u.podeCadastros;
      case PermissaoUsuario.estoque:
        return u.podeEstoque;
      case PermissaoUsuario.vendasHub:
        return u.podeVendas ||
            u.podeAcessarPdv ||
            u.podeAcessarCaixa ||
            u.podeAcessarListagemVendas ||
            u.podeAcessarRelatorios;
      case PermissaoUsuario.acessarPdv:
        return u.podeAcessarPdv;
      case PermissaoUsuario.acessarCaixa:
        return u.podeAcessarCaixa || u.podeCaixa;
      case PermissaoUsuario.acessarListagemVendas:
        return u.podeAcessarListagemVendas;
      case PermissaoUsuario.acessarRelatorios:
        return u.podeAcessarRelatorios;
      case PermissaoUsuario.leituraParcialCaixa:
        return u.podeLeituraParcialCaixa;
      case PermissaoUsuario.visualizarAuditoriaCaixa:
        return u.podeVisualizarAuditoriaCaixa;
      case PermissaoUsuario.manutencaoAuditoriaCaixa:
        return u.podeManutencaoAuditoriaCaixa;
      case PermissaoUsuario.visualizarEntregas:
        return podeVisualizarEntregas(u);
      case PermissaoUsuario.gerenciarEntregas:
        return podeGerenciarEntregas(u);
      case PermissaoUsuario.financeiro:
        return u.podeFinanceiro;
      case PermissaoUsuario.configuracoes:
        return u.podeConfiguracoes;
      case PermissaoUsuario.cancelarVendas:
        return u.podeCancelarVendas;
      case PermissaoUsuario.autorizarSegundaViaCupom:
        return u.podeAutorizarSegundaViaCupom;
      case PermissaoUsuario.autorizarMargemVenda:
        return u.podeAutorizarMargemVenda;
      case PermissaoUsuario.reajustePrecoLote:
        return u.podeReajustePrecoLote;
      case PermissaoUsuario.autorizarReajustePreco:
        return u.podeAutorizarReajustePreco || u.podeAutorizarMargemVenda;
      case PermissaoUsuario.alterarPrecoPdv:
        return u.podeAlterarPrecoPdv;
      case PermissaoUsuario.venderFiado:
        return u.podeVenderFiado;
      case PermissaoUsuario.verCustoMargem:
        return u.podeVerCustoMargem;
      case PermissaoUsuario.gerenciarUsuarios:
        return u.podeGerenciarUsuarios;
      case PermissaoUsuario.editarPrecoProduto:
        return u.podeEditarPrecoProduto;
      case PermissaoUsuario.alterarPrecoUnitarioPdv:
        return u.podeAlterarPrecoUnitarioPdv;
      case PermissaoUsuario.relatoriosComissao:
        return u.podeRelatoriosComissao;
      case PermissaoUsuario.relatoriosFiado:
        return u.podeRelatoriosFiado;
      case PermissaoUsuario.relatoriosLogSistema:
        return u.podeRelatoriosLogSistema;
    }
  }

  /// Legado: [podeEntregas] antigo = visualizar e gerenciar.
  static bool podeGerenciarEntregas(UsuarioSistema u) {
    if (!u.ativo) return false;
    if (u.admin) return true;
    if (u.podeGerenciarEntregas) return true;
    if (u.podeEntregas &&
        !u.podeVisualizarEntregas &&
        !u.podeGerenciarEntregas) {
      return true;
    }
    return false;
  }

  static bool podeVisualizarEntregas(UsuarioSistema u) {
    if (!u.ativo) return false;
    if (u.admin) return true;
    if (u.podeVisualizarEntregas) return true;
    if (podeGerenciarEntregas(u)) return true;
    if (u.podeEntregas) return true;
    return false;
  }

  static bool podeCancelarVendas(UsuarioSistema u) {
    if (!u.ativo) return false;
    if (u.admin) return true;
    return u.podeCancelarVendas;
  }

  static bool podeReajustePrecoLote(UsuarioSistema u) {
    if (!u.ativo) return false;
    if (u.admin) return true;
    return u.podeReajustePrecoLote;
  }

  static bool podeAutorizarReajustePreco(UsuarioSistema u) {
    if (!u.ativo) return false;
    if (u.admin) return true;
    return u.podeAutorizarReajustePreco || u.podeAutorizarMargemVenda;
  }

  static bool podeAutorizarMargemPromocao(UsuarioSistema u) {
    if (!u.ativo) return false;
    if (u.admin) return true;
    return u.podeAutorizarMargemVenda;
  }

  static bool podeAutorizarSegundaViaCupom(UsuarioSistema u) {
    if (!u.ativo) return false;
    if (u.admin) return true;
    return u.podeAutorizarSegundaViaCupom;
  }

  static bool lerFlag(UsuarioSistema u, PermissaoUsuario p) {
    if (u.admin) return true;
    switch (p) {
      case PermissaoUsuario.cadastros:
        return u.podeCadastros;
      case PermissaoUsuario.estoque:
        return u.podeEstoque;
      case PermissaoUsuario.vendasHub:
        return u.podeVendas;
      case PermissaoUsuario.acessarPdv:
        return u.podeAcessarPdv;
      case PermissaoUsuario.acessarCaixa:
        return u.podeAcessarCaixa || u.podeCaixa;
      case PermissaoUsuario.acessarListagemVendas:
        return u.podeAcessarListagemVendas;
      case PermissaoUsuario.acessarRelatorios:
        return u.podeAcessarRelatorios;
      case PermissaoUsuario.leituraParcialCaixa:
        return u.podeLeituraParcialCaixa;
      case PermissaoUsuario.visualizarAuditoriaCaixa:
        return u.podeVisualizarAuditoriaCaixa;
      case PermissaoUsuario.manutencaoAuditoriaCaixa:
        return u.podeManutencaoAuditoriaCaixa;
      case PermissaoUsuario.visualizarEntregas:
        return u.podeVisualizarEntregas || u.podeEntregas;
      case PermissaoUsuario.gerenciarEntregas:
        return u.podeGerenciarEntregas ||
            (u.podeEntregas && !u.podeVisualizarEntregas);
      case PermissaoUsuario.financeiro:
        return u.podeFinanceiro;
      case PermissaoUsuario.configuracoes:
        return u.podeConfiguracoes;
      case PermissaoUsuario.cancelarVendas:
        return u.podeCancelarVendas;
      case PermissaoUsuario.autorizarSegundaViaCupom:
        return u.podeAutorizarSegundaViaCupom;
      case PermissaoUsuario.autorizarMargemVenda:
        return u.podeAutorizarMargemVenda;
      case PermissaoUsuario.reajustePrecoLote:
        return u.podeReajustePrecoLote;
      case PermissaoUsuario.autorizarReajustePreco:
        return u.podeAutorizarReajustePreco;
      case PermissaoUsuario.alterarPrecoPdv:
        return u.podeAlterarPrecoPdv;
      case PermissaoUsuario.venderFiado:
        return u.podeVenderFiado;
      case PermissaoUsuario.verCustoMargem:
        return u.podeVerCustoMargem;
      case PermissaoUsuario.gerenciarUsuarios:
        return u.podeGerenciarUsuarios;
      case PermissaoUsuario.editarPrecoProduto:
        return u.podeEditarPrecoProduto;
      case PermissaoUsuario.alterarPrecoUnitarioPdv:
        return u.podeAlterarPrecoUnitarioPdv;
      case PermissaoUsuario.relatoriosComissao:
        return u.podeRelatoriosComissao;
      case PermissaoUsuario.relatoriosFiado:
        return u.podeRelatoriosFiado;
      case PermissaoUsuario.relatoriosLogSistema:
        return u.podeRelatoriosLogSistema;
    }
  }

  static UsuarioSistema comPermissao(
    UsuarioSistema u,
    PermissaoUsuario p,
    bool valor,
  ) {
    var r = u.copyWith(perfil: PerfilUsuarioPreset.customizado.id);
    switch (p) {
      case PermissaoUsuario.cadastros:
        return r.copyWith(podeCadastros: valor);
      case PermissaoUsuario.estoque:
        return r.copyWith(podeEstoque: valor);
      case PermissaoUsuario.vendasHub:
        return r.copyWith(podeVendas: valor);
      case PermissaoUsuario.acessarPdv:
        return r.copyWith(podeAcessarPdv: valor);
      case PermissaoUsuario.acessarCaixa:
        return r.copyWith(podeAcessarCaixa: valor, podeCaixa: valor);
      case PermissaoUsuario.acessarListagemVendas:
        return r.copyWith(podeAcessarListagemVendas: valor);
      case PermissaoUsuario.acessarRelatorios:
        return r.copyWith(podeAcessarRelatorios: valor);
      case PermissaoUsuario.leituraParcialCaixa:
        return r.copyWith(podeLeituraParcialCaixa: valor);
      case PermissaoUsuario.visualizarAuditoriaCaixa:
        return r.copyWith(
          podeVisualizarAuditoriaCaixa: valor,
          podeManutencaoAuditoriaCaixa:
              valor ? r.podeManutencaoAuditoriaCaixa : false,
        );
      case PermissaoUsuario.manutencaoAuditoriaCaixa:
        return r.copyWith(
          podeManutencaoAuditoriaCaixa: valor,
          podeVisualizarAuditoriaCaixa:
              valor ? true : r.podeVisualizarAuditoriaCaixa,
        );
      case PermissaoUsuario.visualizarEntregas:
        return r.copyWith(
          podeVisualizarEntregas: valor,
          podeEntregas: valor || r.podeGerenciarEntregas,
        );
      case PermissaoUsuario.gerenciarEntregas:
        return r.copyWith(
          podeGerenciarEntregas: valor,
          podeVisualizarEntregas: valor ? true : r.podeVisualizarEntregas,
          podeEntregas: valor || r.podeVisualizarEntregas,
        );
      case PermissaoUsuario.financeiro:
        return r.copyWith(podeFinanceiro: valor);
      case PermissaoUsuario.configuracoes:
        return r.copyWith(podeConfiguracoes: valor);
      case PermissaoUsuario.cancelarVendas:
        return r.copyWith(podeCancelarVendas: valor);
      case PermissaoUsuario.autorizarSegundaViaCupom:
        return r.copyWith(podeAutorizarSegundaViaCupom: valor);
      case PermissaoUsuario.autorizarMargemVenda:
        return r.copyWith(podeAutorizarMargemVenda: valor);
      case PermissaoUsuario.reajustePrecoLote:
        return r.copyWith(podeReajustePrecoLote: valor);
      case PermissaoUsuario.autorizarReajustePreco:
        return r.copyWith(podeAutorizarReajustePreco: valor);
      case PermissaoUsuario.alterarPrecoPdv:
        return r.copyWith(podeAlterarPrecoPdv: valor);
      case PermissaoUsuario.venderFiado:
        return r.copyWith(podeVenderFiado: valor);
      case PermissaoUsuario.verCustoMargem:
        return r.copyWith(podeVerCustoMargem: valor);
      case PermissaoUsuario.gerenciarUsuarios:
        return r.copyWith(podeGerenciarUsuarios: valor);
      case PermissaoUsuario.editarPrecoProduto:
        return r.copyWith(podeEditarPrecoProduto: valor);
      case PermissaoUsuario.alterarPrecoUnitarioPdv:
        return r.copyWith(podeAlterarPrecoUnitarioPdv: valor);
      case PermissaoUsuario.relatoriosComissao:
        return r.copyWith(podeRelatoriosComissao: valor);
      case PermissaoUsuario.relatoriosFiado:
        return r.copyWith(podeRelatoriosFiado: valor);
      case PermissaoUsuario.relatoriosLogSistema:
        return r.copyWith(podeRelatoriosLogSistema: valor);
    }
  }

  static UsuarioSistema aplicarAdmin(UsuarioSistema u, bool admin) {
    if (!admin) {
      return u.copyWith(admin: false);
    }
    return PerfilUsuarioPresetAplicador.aplicar(
      u,
      PerfilUsuarioPreset.dono,
    ).copyWith(
      admin: true,
      perfil: PerfilUsuarioPreset.dono.id,
      nome: u.nome,
      login: u.login,
      senha: u.senha,
    );
  }

  static List<String> resumoChips(UsuarioSistema u) {
    if (u.admin) return const ['Dono/Admin'];
    final chips = <String>[];
    final perfil = perfilUsuarioFromId(u.perfil);
    if (perfil != PerfilUsuarioPreset.customizado) {
      chips.add(perfil.rotulo);
    }
    if (tem(u, PermissaoUsuario.acessarPdv)) chips.add('PDV');
    if (tem(u, PermissaoUsuario.acessarCaixa)) chips.add('Caixa');
    if (tem(u, PermissaoUsuario.leituraParcialCaixa)) {
      chips.add('Leitura parcial');
    }
    if (tem(u, PermissaoUsuario.visualizarAuditoriaCaixa)) {
      chips.add('Auditoria caixa');
    }
    if (tem(u, PermissaoUsuario.acessarListagemVendas)) {
      chips.add('Listagem');
    }
    if (podeVisualizarEntregas(u)) chips.add('Entregas');
    if (tem(u, PermissaoUsuario.estoque)) chips.add('Estoque');
    if (tem(u, PermissaoUsuario.reajustePrecoLote)) chips.add('Reajuste');
    if (tem(u, PermissaoUsuario.cancelarVendas)) chips.add('Cancelar');
    return chips.isEmpty ? const ['Basico'] : chips;
  }
}
