/// Modulos e acoes do log central do sistema (Fase 1).
class AuditoriaModulo {
  AuditoriaModulo._();

  static const autenticacao = 'autenticacao';
  static const orcamento = 'orcamento';
  static const venda = 'venda';
  static const backup = 'backup';
  static const caixa = 'caixa';
  static const sistema = 'sistema';

  static const todos = [
    autenticacao,
    orcamento,
    venda,
    backup,
    caixa,
    sistema,
  ];
}

class AuditoriaAcao {
  AuditoriaAcao._();

  static const login = 'login';
  static const logout = 'logout';
  static const loginFalha = 'login_falha';
  static const adminCriado = 'admin_criado';
  static const cancelar = 'cancelar';
  static const cancelarLote = 'cancelar_lote';
  static const backupCriar = 'backup_criar';
  static const backupRestaurar = 'backup_restaurar';
  static const backupAutomatico = 'backup_automatico';
  static const fechamentoCaixa = 'fechamento_caixa';
  static const fechamentoNegado = 'fechamento_negado';
  static const limparManual = 'limpar_manual';
  static const retencaoAutomatica = 'retencao_automatica';
}

String auditoriaRotuloModulo(String modulo) {
  switch (modulo) {
    case AuditoriaModulo.autenticacao:
      return 'Autenticacao';
    case AuditoriaModulo.orcamento:
      return 'Orcamentos';
    case AuditoriaModulo.venda:
      return 'Vendas';
    case AuditoriaModulo.backup:
      return 'Backup';
    case AuditoriaModulo.caixa:
      return 'Caixa';
    case AuditoriaModulo.sistema:
      return 'Sistema';
    default:
      return modulo;
  }
}

String auditoriaRotuloAcao(String acao) {
  switch (acao) {
    case AuditoriaAcao.login:
      return 'Login';
    case AuditoriaAcao.logout:
      return 'Logout';
    case AuditoriaAcao.loginFalha:
      return 'Login falhou';
    case AuditoriaAcao.adminCriado:
      return 'Admin criado';
    case AuditoriaAcao.cancelar:
      return 'Cancelamento';
    case AuditoriaAcao.cancelarLote:
      return 'Cancelamento em lote';
    case AuditoriaAcao.backupCriar:
      return 'Backup criado';
    case AuditoriaAcao.backupRestaurar:
      return 'Backup restaurado';
    case AuditoriaAcao.backupAutomatico:
      return 'Backup automatico';
    case AuditoriaAcao.fechamentoCaixa:
      return 'Fechamento de caixa';
    case AuditoriaAcao.fechamentoNegado:
      return 'Fechamento negado';
    case AuditoriaAcao.limparManual:
      return 'Limpeza de log';
    case AuditoriaAcao.retencaoAutomatica:
      return 'Retencao automatica';
    default:
      return acao;
  }
}
