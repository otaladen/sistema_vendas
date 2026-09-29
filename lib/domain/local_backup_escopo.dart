/// Escopo do backup local (pasta `backup_sistema_vendas_*`).
enum LocalBackupEscopo {
  /// Banco ObjectBox, fotos de produto, POD de entrega e preferencias locais.
  /// Caches (`product_images_cache`, `pod_entrega_cache`) ficam de fora.
  completo,

  /// Apenas a pasta `objectbox/` (data.mdb). Diario recomendado.
  somenteBanco,

  /// Banco, demais arquivos e preferencias, sem pastas de foto/POD.
  semImagens,

  /// Cadastro de produtos (JSON + fotos), sem vendas/clientes/estoque operacional.
  cadastroProdutos,
}

/// Grupo usado na retencao: leves e completos nao disputam o mesmo limite.
enum BackupClasseRetencao { leve, completo, outro }

extension LocalBackupEscopoJson on LocalBackupEscopo {
  String get manifestValue => switch (this) {
        LocalBackupEscopo.completo => 'completo',
        LocalBackupEscopo.somenteBanco => 'somente_banco',
        LocalBackupEscopo.semImagens => 'sem_imagens',
        LocalBackupEscopo.cadastroProdutos => 'cadastro_produtos',
      };

  String get rotulo => switch (this) {
        LocalBackupEscopo.completo => 'Completo (semanal)',
        LocalBackupEscopo.somenteBanco => 'So o banco (diario)',
        LocalBackupEscopo.semImagens => 'Sem fotos',
        LocalBackupEscopo.cadastroProdutos => 'So cadastro de produtos',
      };

  String get descricaoCurta => switch (this) {
        LocalBackupEscopo.completo =>
          'Banco, fotos de produto, entregas e configuracoes. '
              'Demora mais; use uma vez por semana',
        LocalBackupEscopo.somenteBanco =>
          'Diario leve: vendas, estoque, clientes e precos. Sem fotos',
        LocalBackupEscopo.semImagens =>
          'Banco e configuracoes deste PC, sem fotos de produto, '
              'funcionario e entrega',
        LocalBackupEscopo.cadastroProdutos =>
          'Produtos, precos, fiscal e fotos (sem vendas)',
      };

  bool get incluiPreferencias =>
      this == LocalBackupEscopo.completo ||
      this == LocalBackupEscopo.semImagens;

  BackupClasseRetencao get classeRetencao => switch (this) {
        LocalBackupEscopo.completo => BackupClasseRetencao.completo,
        LocalBackupEscopo.somenteBanco ||
        LocalBackupEscopo.semImagens =>
          BackupClasseRetencao.leve,
        LocalBackupEscopo.cadastroProdutos => BackupClasseRetencao.outro,
      };

  /// Diario pode ser banco, sem fotos ou completo (o completo e o pesado).
  bool get disponivelNoAutomatico =>
      this == LocalBackupEscopo.somenteBanco ||
      this == LocalBackupEscopo.semImagens ||
      this == LocalBackupEscopo.completo;
}

LocalBackupEscopo localBackupEscopoFromManifest(dynamic raw) {
  final v = raw?.toString().trim().toLowerCase() ?? '';
  if (v == LocalBackupEscopo.somenteBanco.manifestValue ||
      v == 'somente_banco' ||
      v == 'banco') {
    return LocalBackupEscopo.somenteBanco;
  }
  if (v == LocalBackupEscopo.semImagens.manifestValue ||
      v == 'sem_imagens' ||
      v == 'sem_fotos' ||
      v == 'completo_sem_fotos') {
    return LocalBackupEscopo.semImagens;
  }
  if (v == LocalBackupEscopo.cadastroProdutos.manifestValue ||
      v == 'cadastro_produtos' ||
      v == 'produtos') {
    return LocalBackupEscopo.cadastroProdutos;
  }
  return LocalBackupEscopo.completo;
}

/// Ordem do seletor: diario leve primeiro, completo por ultimo.
List<LocalBackupEscopo> localBackupEscoposAutomaticos() => const [
      LocalBackupEscopo.somenteBanco,
      LocalBackupEscopo.semImagens,
      LocalBackupEscopo.completo,
    ];
