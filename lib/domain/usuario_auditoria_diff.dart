import '../model/usuario_sistema.dart';

/// Diff legivel de permissoes para o log de auditoria.
class UsuarioAuditoriaDiff {
  UsuarioAuditoriaDiff._();

  static const _rotulos = <String, String>{
    'perfil': 'Perfil',
    'ativo': 'Ativo',
    'admin': 'Administrador',
    'podeCadastros': 'Cadastros',
    'podeEstoque': 'Estoque',
    'podeVendas': 'Hub vendas',
    'podeAcessarPdv': 'PDV',
    'podeAcessarCaixa': 'Caixa',
    'podeAcessarRelatorios': 'Relatorios',
    'podeVisualizarEntregas': 'Ver entregas',
    'podeGerenciarEntregas': 'Gerenciar entregas',
    'podeFinanceiro': 'Financeiro',
    'podeConfiguracoes': 'Configuracoes',
    'podeCancelarVendas': 'Cancelar vendas',
    'podeReajustePrecoLote': 'Reajuste em lote',
    'podeEditarPrecoProduto': 'Editar preco produto',
    'podeVenderFiado': 'Vender fiado',
    'podeAlterarPrecoPdv': 'Desconto manual PDV',
    'podeAlterarPrecoUnitarioPdv': 'Preco unitario PDV',
    'podeRelatoriosComissao': 'Relatorio comissao',
    'podeRelatoriosFiado': 'Relatorio fiados',
    'podeRelatoriosLogSistema': 'Log do sistema',
    'descontoMaximoPercentualPdv': 'Teto desconto PDV %',
  };

  static Map<String, dynamic> diffPermissoes(
    UsuarioSistema? antes,
    UsuarioSistema depois,
  ) {
    final a = antes?.toMap() ?? {};
    final d = depois.toMap();
  final alteracoes = <String, Map<String, dynamic>>{};
    for (final key in _rotulos.keys) {
      final va = a[key];
      final vd = d[key];
      if (va != vd) {
        alteracoes[_rotulos[key]!] = {
          'de': va,
          'para': vd,
        };
      }
    }
    if (antes != null && antes.nome != depois.nome) {
      alteracoes['Nome'] = {'de': antes.nome, 'para': depois.nome};
    }
    if (antes != null && antes.login != depois.login) {
      alteracoes['Login'] = {'de': antes.login, 'para': depois.login};
    }
    return {
      'alteracoes': alteracoes,
      'senhaAlterada': antes != null && antes.senha != depois.senha,
    };
  }
}
