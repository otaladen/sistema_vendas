class UsuarioSistema {
  const UsuarioSistema({
    required this.id,
    required this.nome,
    required this.login,
    required this.senha,
    this.ativo = true,
    this.admin = false,
    this.podeCadastros = false,
    this.podeEstoque = false,
    this.podeVendas = false,
    this.podeCaixa = false,
    this.podeLeituraParcialCaixa = false,
    this.podeManutencaoAuditoriaCaixa = false,
    this.podeEntregas = false,
    this.podeFinanceiro = false,
    this.podeConfiguracoes = false,
    this.podeAutorizarSegundaViaCupom = false,
    this.podeAutorizarMargemVenda = false,
  });

  final String id;
  final String nome;
  final String login;
  final String senha;
  final bool ativo;
  final bool admin;
  final bool podeCadastros;
  final bool podeEstoque;
  final bool podeVendas;
  final bool podeCaixa;
  final bool podeLeituraParcialCaixa;
  final bool podeManutencaoAuditoriaCaixa;
  final bool podeEntregas;
  final bool podeFinanceiro;
  final bool podeConfiguracoes;
  /// Autoriza informar login/senha para emitir segunda via do cupom (caixa / listagem).
  final bool podeAutorizarSegundaViaCupom;

  /// Autoriza venda abaixo da margem minima de campanha promocional.
  final bool podeAutorizarMargemVenda;

  UsuarioSistema copyWith({
    String? id,
    String? nome,
    String? login,
    String? senha,
    bool? ativo,
    bool? admin,
    bool? podeCadastros,
    bool? podeEstoque,
    bool? podeVendas,
    bool? podeCaixa,
    bool? podeLeituraParcialCaixa,
    bool? podeManutencaoAuditoriaCaixa,
    bool? podeEntregas,
    bool? podeFinanceiro,
    bool? podeConfiguracoes,
    bool? podeAutorizarSegundaViaCupom,
    bool? podeAutorizarMargemVenda,
  }) {
    return UsuarioSistema(
      id: id ?? this.id,
      nome: nome ?? this.nome,
      login: login ?? this.login,
      senha: senha ?? this.senha,
      ativo: ativo ?? this.ativo,
      admin: admin ?? this.admin,
      podeCadastros: podeCadastros ?? this.podeCadastros,
      podeEstoque: podeEstoque ?? this.podeEstoque,
      podeVendas: podeVendas ?? this.podeVendas,
      podeCaixa: podeCaixa ?? this.podeCaixa,
      podeLeituraParcialCaixa:
          podeLeituraParcialCaixa ?? this.podeLeituraParcialCaixa,
      podeManutencaoAuditoriaCaixa:
          podeManutencaoAuditoriaCaixa ?? this.podeManutencaoAuditoriaCaixa,
      podeEntregas: podeEntregas ?? this.podeEntregas,
      podeFinanceiro: podeFinanceiro ?? this.podeFinanceiro,
      podeConfiguracoes: podeConfiguracoes ?? this.podeConfiguracoes,
      podeAutorizarSegundaViaCupom:
          podeAutorizarSegundaViaCupom ?? this.podeAutorizarSegundaViaCupom,
      podeAutorizarMargemVenda:
          podeAutorizarMargemVenda ?? this.podeAutorizarMargemVenda,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'nome': nome,
      'login': login,
      'senha': senha,
      'ativo': ativo,
      'admin': admin,
      'podeCadastros': podeCadastros,
      'podeEstoque': podeEstoque,
      'podeVendas': podeVendas,
      'podeCaixa': podeCaixa,
      'podeLeituraParcialCaixa': podeLeituraParcialCaixa,
      'podeManutencaoAuditoriaCaixa': podeManutencaoAuditoriaCaixa,
      'podeEntregas': podeEntregas,
      'podeFinanceiro': podeFinanceiro,
      'podeConfiguracoes': podeConfiguracoes,
      'podeAutorizarSegundaViaCupom': podeAutorizarSegundaViaCupom,
      'podeAutorizarMargemVenda': podeAutorizarMargemVenda,
    };
  }

  static UsuarioSistema fromMap(Map<String, dynamic> map) {
    return UsuarioSistema(
      id: (map['id'] ?? '').toString(),
      nome: (map['nome'] ?? '').toString(),
      login: (map['login'] ?? '').toString(),
      senha: (map['senha'] ?? '').toString(),
      ativo: map['ativo'] == true,
      admin: map['admin'] == true,
      podeCadastros: map['podeCadastros'] == true,
      podeEstoque: map['podeEstoque'] == true,
      podeVendas: map['podeVendas'] == true,
      podeCaixa: map['podeCaixa'] == true,
      podeLeituraParcialCaixa: map['podeLeituraParcialCaixa'] == true,
      podeManutencaoAuditoriaCaixa:
          map['podeManutencaoAuditoriaCaixa'] == true,
      podeEntregas: map['podeEntregas'] == true,
      podeFinanceiro: map['podeFinanceiro'] == true,
      podeConfiguracoes: map['podeConfiguracoes'] == true,
      podeAutorizarSegundaViaCupom: () {
        if (map['podeAutorizarSegundaViaCupom'] == true) return true;
        if (!map.containsKey('podeAutorizarSegundaViaCupom') &&
            map['admin'] == true) {
          return true;
        }
        return false;
      }(),
      podeAutorizarMargemVenda: map['podeAutorizarMargemVenda'] == true,
    );
  }
}
