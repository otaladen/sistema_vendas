/// Modulos e acoes do log central do sistema (Fase 1).
class AuditoriaModulo {
  AuditoriaModulo._();

  static const autenticacao = 'autenticacao';
  static const orcamento = 'orcamento';
  static const venda = 'venda';
  static const backup = 'backup';
  static const caixa = 'caixa';
  static const fiscal = 'fiscal';
  static const estoque = 'estoque';
  static const sistema = 'sistema';

  static const todos = [
    autenticacao,
    orcamento,
    venda,
    backup,
    caixa,
    fiscal,
    estoque,
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
  static const usuarioCriado = 'usuario_criado';
  static const usuarioAlterado = 'usuario_alterado';
  static const usuarioRemovido = 'usuario_removido';
  static const nfeEmitir = 'nfe_emitir';
  static const nfeCancelar = 'nfe_cancelar';
  static const nfeCartaCorrecao = 'nfe_carta_correcao';
  static const nfeReconsultar = 'nfe_reconsultar';
  static const nfeReconsultarLote = 'nfe_reconsultar_lote';
  static const nfeEmail = 'nfe_email';
  static const nfeWhatsapp = 'nfe_whatsapp';
  static const nfeInutilizar = 'nfe_inutilizar';
  static const descontoOrcamento = 'desconto_orcamento';
  static const autorizacaoDescontoAcimaTeto = 'autorizacao_desconto_acima_teto';
  static const alterarPrecoUnitarioPdv = 'alterar_preco_unitario_pdv';
  static const autorizacaoMargemPromocao = 'autorizacao_margem_promocao';
  static const autorizacaoReajustePreco = 'autorizacao_reajuste_preco';
  static const reajustePrecoLote = 'reajuste_preco_lote';
  static const reajustePrecoEstorno = 'reajuste_preco_estorno';
  static const devolucao = 'devolucao';
  static const troca = 'troca';
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
    case AuditoriaModulo.fiscal:
      return 'Fiscal';
    case AuditoriaModulo.estoque:
      return 'Estoque';
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
    case AuditoriaAcao.usuarioCriado:
      return 'Usuario criado';
    case AuditoriaAcao.usuarioAlterado:
      return 'Usuario alterado';
    case AuditoriaAcao.usuarioRemovido:
      return 'Usuario removido';
    case AuditoriaAcao.nfeEmitir:
      return 'NF-e emitida';
    case AuditoriaAcao.nfeCancelar:
      return 'NF-e cancelada';
    case AuditoriaAcao.nfeCartaCorrecao:
      return 'Carta de correcao NF-e';
    case AuditoriaAcao.nfeReconsultar:
      return 'Reconsulta NF-e';
    case AuditoriaAcao.nfeReconsultarLote:
      return 'Reconsulta NF-e em lote';
    case AuditoriaAcao.nfeEmail:
      return 'NF-e enviada por e-mail';
    case AuditoriaAcao.nfeWhatsapp:
      return 'DANFE enviado por WhatsApp';
    case AuditoriaAcao.nfeInutilizar:
      return 'Inutilizacao numeracao NF-e';
    case AuditoriaAcao.descontoOrcamento:
      return 'Desconto no orcamento';
    case AuditoriaAcao.autorizacaoDescontoAcimaTeto:
      return 'Autorizacao desconto acima do teto';
    case AuditoriaAcao.alterarPrecoUnitarioPdv:
      return 'Preco unitario alterado no PDV';
    case AuditoriaAcao.autorizacaoMargemPromocao:
      return 'Autorizacao margem promocional';
    case AuditoriaAcao.autorizacaoReajustePreco:
      return 'Autorizacao reajuste de precos';
    case AuditoriaAcao.reajustePrecoLote:
      return 'Reajuste de precos em lote';
    case AuditoriaAcao.reajustePrecoEstorno:
      return 'Estorno de reajuste';
    case AuditoriaAcao.devolucao:
      return 'Devolucao';
    case AuditoriaAcao.troca:
      return 'Troca';
    default:
      return acao;
  }
}
