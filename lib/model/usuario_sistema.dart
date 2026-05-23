class UsuarioSistema {
  const UsuarioSistema({
    required this.id,
    required this.nome,
    required this.login,
    required this.senha,
    this.ativo = true,
    this.admin = false,
    this.perfil = 'customizado',
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
    this.descontoMaximoPercentualPdv,
  });

  final String id;
  final String nome;
  final String login;
  final String senha;
  final bool ativo;
  final bool admin;

  /// Perfil operacional: vendedor, caixa, separador, motorista, comprador, gerente, dono, customizado.
  final String perfil;

  final bool podeCadastros;
  final bool podeEstoque;
  final bool podeVendas;

  /// Legado — espelha [podeAcessarCaixa] ao salvar.
  final bool podeCaixa;
  final bool podeAcessarPdv;
  final bool podeAcessarCaixa;
  final bool podeAcessarListagemVendas;
  final bool podeAcessarRelatorios;
  final bool podeLeituraParcialCaixa;
  final bool podeVisualizarAuditoriaCaixa;
  final bool podeManutencaoAuditoriaCaixa;

  /// Legado — migrado para visualizar/gerenciar.
  final bool podeEntregas;
  final bool podeVisualizarEntregas;
  final bool podeGerenciarEntregas;

  final bool podeFinanceiro;
  final bool podeConfiguracoes;
  final bool podeCancelarVendas;

  /// Autoriza informar login/senha para emitir segunda via do cupom (caixa / listagem).
  final bool podeAutorizarSegundaViaCupom;

  /// Autoriza venda abaixo da margem minima de campanha promocional.
  final bool podeAutorizarMargemVenda;

  /// Executa reajuste de precos em lote (Estoque) — tipicamente Gerente/Dono.
  final bool podeReajustePrecoLote;

  /// Autoriza aplicar reajuste com alertas (margem, variacao, abaixo do custo).
  final bool podeAutorizarReajustePreco;

  /// Desconto manual no checkout do PDV.
  final bool podeAlterarPrecoPdv;

  /// Forma de pagamento fiado no PDV.
  final bool podeVenderFiado;

  /// Ver custo e exportar tabelas com custo.
  final bool podeVerCustoMargem;

  /// Cadastro de usuarios (alem de admin).
  final bool podeGerenciarUsuarios;

  /// Alterar precos de venda no cadastro de produtos.
  final bool podeEditarPrecoProduto;

  /// Alterar preco unitario de item no PDV (alem das tabelas F1-F3).
  final bool podeAlterarPrecoUnitarioPdv;

  final bool podeRelatoriosComissao;
  final bool podeRelatoriosFiado;
  final bool podeRelatoriosLogSistema;

  /// Teto de desconto no PDV (%). Null = usar configuracao da empresa.
  final double? descontoMaximoPercentualPdv;

  UsuarioSistema copyWith({
    String? id,
    String? nome,
    String? login,
    String? senha,
    bool? ativo,
    bool? admin,
    String? perfil,
    bool? podeCadastros,
    bool? podeEstoque,
    bool? podeVendas,
    bool? podeCaixa,
    bool? podeAcessarPdv,
    bool? podeAcessarCaixa,
    bool? podeAcessarListagemVendas,
    bool? podeAcessarRelatorios,
    bool? podeLeituraParcialCaixa,
    bool? podeVisualizarAuditoriaCaixa,
    bool? podeManutencaoAuditoriaCaixa,
    bool? podeEntregas,
    bool? podeVisualizarEntregas,
    bool? podeGerenciarEntregas,
    bool? podeFinanceiro,
    bool? podeConfiguracoes,
    bool? podeCancelarVendas,
    bool? podeAutorizarSegundaViaCupom,
    bool? podeAutorizarMargemVenda,
    bool? podeReajustePrecoLote,
    bool? podeAutorizarReajustePreco,
    bool? podeAlterarPrecoPdv,
    bool? podeVenderFiado,
    bool? podeVerCustoMargem,
    bool? podeGerenciarUsuarios,
    bool? podeEditarPrecoProduto,
    bool? podeAlterarPrecoUnitarioPdv,
    bool? podeRelatoriosComissao,
    bool? podeRelatoriosFiado,
    bool? podeRelatoriosLogSistema,
    double? descontoMaximoPercentualPdv,
    bool limparDescontoMaximoPdv = false,
  }) {
    final caixa = podeAcessarCaixa ?? podeCaixa ?? this.podeAcessarCaixa;
    final visualizar =
        podeVisualizarEntregas ?? this.podeVisualizarEntregas;
    final gerenciar = podeGerenciarEntregas ?? this.podeGerenciarEntregas;
    return UsuarioSistema(
      id: id ?? this.id,
      nome: nome ?? this.nome,
      login: login ?? this.login,
      senha: senha ?? this.senha,
      ativo: ativo ?? this.ativo,
      admin: admin ?? this.admin,
      perfil: perfil ?? this.perfil,
      podeCadastros: podeCadastros ?? this.podeCadastros,
      podeEstoque: podeEstoque ?? this.podeEstoque,
      podeVendas: podeVendas ?? this.podeVendas,
      podeCaixa: caixa,
      podeAcessarPdv: podeAcessarPdv ?? this.podeAcessarPdv,
      podeAcessarCaixa: caixa,
      podeAcessarListagemVendas:
          podeAcessarListagemVendas ?? this.podeAcessarListagemVendas,
      podeAcessarRelatorios: podeAcessarRelatorios ?? this.podeAcessarRelatorios,
      podeLeituraParcialCaixa:
          podeLeituraParcialCaixa ?? this.podeLeituraParcialCaixa,
      podeVisualizarAuditoriaCaixa:
          podeVisualizarAuditoriaCaixa ?? this.podeVisualizarAuditoriaCaixa,
      podeManutencaoAuditoriaCaixa:
          podeManutencaoAuditoriaCaixa ?? this.podeManutencaoAuditoriaCaixa,
      podeEntregas: podeEntregas ?? (visualizar || gerenciar),
      podeVisualizarEntregas: visualizar,
      podeGerenciarEntregas: gerenciar,
      podeFinanceiro: podeFinanceiro ?? this.podeFinanceiro,
      podeConfiguracoes: podeConfiguracoes ?? this.podeConfiguracoes,
      podeCancelarVendas: podeCancelarVendas ?? this.podeCancelarVendas,
      podeAutorizarSegundaViaCupom:
          podeAutorizarSegundaViaCupom ?? this.podeAutorizarSegundaViaCupom,
      podeAutorizarMargemVenda:
          podeAutorizarMargemVenda ?? this.podeAutorizarMargemVenda,
      podeReajustePrecoLote:
          podeReajustePrecoLote ?? this.podeReajustePrecoLote,
      podeAutorizarReajustePreco:
          podeAutorizarReajustePreco ?? this.podeAutorizarReajustePreco,
      podeAlterarPrecoPdv: podeAlterarPrecoPdv ?? this.podeAlterarPrecoPdv,
      podeVenderFiado: podeVenderFiado ?? this.podeVenderFiado,
      podeVerCustoMargem: podeVerCustoMargem ?? this.podeVerCustoMargem,
      podeGerenciarUsuarios:
          podeGerenciarUsuarios ?? this.podeGerenciarUsuarios,
      podeEditarPrecoProduto:
          podeEditarPrecoProduto ?? this.podeEditarPrecoProduto,
      podeAlterarPrecoUnitarioPdv: podeAlterarPrecoUnitarioPdv ??
          this.podeAlterarPrecoUnitarioPdv,
      podeRelatoriosComissao:
          podeRelatoriosComissao ?? this.podeRelatoriosComissao,
      podeRelatoriosFiado: podeRelatoriosFiado ?? this.podeRelatoriosFiado,
      podeRelatoriosLogSistema:
          podeRelatoriosLogSistema ?? this.podeRelatoriosLogSistema,
      descontoMaximoPercentualPdv: limparDescontoMaximoPdv
          ? null
          : (descontoMaximoPercentualPdv ?? this.descontoMaximoPercentualPdv),
    );
  }

  Map<String, dynamic> toMap() {
    final caixa = podeAcessarCaixa || podeCaixa;
    final entregas =
        podeEntregas || podeVisualizarEntregas || podeGerenciarEntregas;
    return {
      'id': id,
      'nome': nome,
      'login': login,
      'senha': senha,
      'ativo': ativo,
      'admin': admin,
      'perfil': perfil,
      'podeCadastros': podeCadastros,
      'podeEstoque': podeEstoque,
      'podeVendas': podeVendas,
      'podeCaixa': caixa,
      'podeAcessarPdv': podeAcessarPdv,
      'podeAcessarCaixa': caixa,
      'podeAcessarListagemVendas': podeAcessarListagemVendas,
      'podeAcessarRelatorios': podeAcessarRelatorios,
      'podeLeituraParcialCaixa': podeLeituraParcialCaixa,
      'podeVisualizarAuditoriaCaixa': podeVisualizarAuditoriaCaixa,
      'podeManutencaoAuditoriaCaixa': podeManutencaoAuditoriaCaixa,
      'podeEntregas': entregas,
      'podeVisualizarEntregas': podeVisualizarEntregas || podeGerenciarEntregas || podeEntregas,
      'podeGerenciarEntregas': podeGerenciarEntregas || (podeEntregas && !podeVisualizarEntregas),
      'podeFinanceiro': podeFinanceiro,
      'podeConfiguracoes': podeConfiguracoes,
      'podeCancelarVendas': podeCancelarVendas,
      'podeAutorizarSegundaViaCupom': podeAutorizarSegundaViaCupom,
      'podeAutorizarMargemVenda': podeAutorizarMargemVenda,
      'podeReajustePrecoLote': podeReajustePrecoLote,
      'podeAutorizarReajustePreco': podeAutorizarReajustePreco,
      'podeAlterarPrecoPdv': podeAlterarPrecoPdv,
      'podeVenderFiado': podeVenderFiado,
      'podeVerCustoMargem': podeVerCustoMargem,
      'podeGerenciarUsuarios': podeGerenciarUsuarios,
      'podeEditarPrecoProduto': podeEditarPrecoProduto,
      'podeAlterarPrecoUnitarioPdv': podeAlterarPrecoUnitarioPdv,
      'podeRelatoriosComissao': podeRelatoriosComissao,
      'podeRelatoriosFiado': podeRelatoriosFiado,
      'podeRelatoriosLogSistema': podeRelatoriosLogSistema,
      if (descontoMaximoPercentualPdv != null)
        'descontoMaximoPercentualPdv': descontoMaximoPercentualPdv,
    };
  }

  static UsuarioSistema fromMap(Map<String, dynamic> map) {
    final legadoEntregas = map['podeEntregas'] == true;
    final temChaveVisualizar = map.containsKey('podeVisualizarEntregas');
    final temChaveGerenciar = map.containsKey('podeGerenciarEntregas');
    final gerenciar = map['podeGerenciarEntregas'] == true ||
        (legadoEntregas && !temChaveVisualizar && !temChaveGerenciar);
    final visualizar = map['podeVisualizarEntregas'] == true ||
        gerenciar ||
        (legadoEntregas && !gerenciar);

    final caixaLegado = map['podeCaixa'] == true;
    final caixa = map['podeAcessarCaixa'] == true || caixaLegado;

    final pdvLegado = map['podeAcessarPdv'] == true ||
        (map['podeVendas'] == true && map.containsKey('podeAcessarPdv') == false);
    final relatorios = map['podeAcessarRelatorios'] == true;
    final listagemExplicita = map.containsKey('podeAcessarListagemVendas');
    final listagem = listagemExplicita
        ? map['podeAcessarListagemVendas'] == true
        : pdvLegado || relatorios;

    final visualizarAuditoriaExplicita =
        map.containsKey('podeVisualizarAuditoriaCaixa');
    final visualizarAuditoria = visualizarAuditoriaExplicita
        ? map['podeVisualizarAuditoriaCaixa'] == true
        : map['podeManutencaoAuditoriaCaixa'] == true || caixa;

    final admin = map['admin'] == true;
    final legadoCancelarSemFlag = map['podeFinanceiro'] == true &&
        !map.containsKey('podeCancelarVendas');
    final legadoCancelarAuditoria =
        map['podeManutencaoAuditoriaCaixa'] == true &&
            !map.containsKey('podeCancelarVendas');

    return UsuarioSistema(
      id: (map['id'] ?? '').toString(),
      nome: (map['nome'] ?? '').toString(),
      login: (map['login'] ?? '').toString(),
      senha: (map['senha'] ?? '').toString(),
      ativo: map['ativo'] != false,
      admin: admin,
      perfil: (map['perfil'] ?? (admin ? 'dono' : 'customizado')).toString(),
      podeCadastros: map['podeCadastros'] == true,
      podeEstoque: map['podeEstoque'] == true,
      podeVendas: map['podeVendas'] == true,
      podeCaixa: caixa,
      podeAcessarPdv: pdvLegado,
      podeAcessarCaixa: caixa,
      podeAcessarListagemVendas: listagem,
      podeAcessarRelatorios: relatorios,
      podeLeituraParcialCaixa: map['podeLeituraParcialCaixa'] == true,
      podeVisualizarAuditoriaCaixa: visualizarAuditoria,
      podeManutencaoAuditoriaCaixa:
          map['podeManutencaoAuditoriaCaixa'] == true,
      podeEntregas: legadoEntregas,
      podeVisualizarEntregas: visualizar || gerenciar,
      podeGerenciarEntregas: gerenciar,
      podeFinanceiro: map['podeFinanceiro'] == true,
      podeConfiguracoes: map['podeConfiguracoes'] == true,
      podeCancelarVendas: map['podeCancelarVendas'] == true ||
          legadoCancelarSemFlag ||
          legadoCancelarAuditoria,
      podeAutorizarSegundaViaCupom: () {
        if (map['podeAutorizarSegundaViaCupom'] == true) return true;
        if (!map.containsKey('podeAutorizarSegundaViaCupom') && admin) {
          return true;
        }
        return false;
      }(),
      podeAutorizarMargemVenda: map['podeAutorizarMargemVenda'] == true,
      podeReajustePrecoLote: map['podeReajustePrecoLote'] == true,
      podeAutorizarReajustePreco: map['podeAutorizarReajustePreco'] == true,
      podeAlterarPrecoPdv: map['podeAlterarPrecoPdv'] == true,
      podeVenderFiado: map['podeVenderFiado'] == true,
      podeVerCustoMargem: map['podeVerCustoMargem'] == true,
      podeGerenciarUsuarios:
          map['podeGerenciarUsuarios'] == true || admin,
      podeEditarPrecoProduto: map['podeEditarPrecoProduto'] == true,
      podeAlterarPrecoUnitarioPdv:
          map['podeAlterarPrecoUnitarioPdv'] == true ||
              map['podeAlterarPrecoPdv'] == true,
      podeRelatoriosComissao: map['podeRelatoriosComissao'] == true ||
          (map['podeAcessarRelatorios'] == true &&
              !map.containsKey('podeRelatoriosComissao')),
      podeRelatoriosFiado: map['podeRelatoriosFiado'] == true ||
          map['podeFinanceiro'] == true,
      podeRelatoriosLogSistema: map['podeRelatoriosLogSistema'] == true ||
          admin,
      descontoMaximoPercentualPdv:
          (map['descontoMaximoPercentualPdv'] as num?)?.toDouble(),
    );
  }
}
