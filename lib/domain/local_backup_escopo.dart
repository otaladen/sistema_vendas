/// Escopo do backup local (pasta `backup_sistema_vendas_*`).
enum LocalBackupEscopo {
  /// Banco ObjectBox, fotos de produto, POD de entrega e preferencias locais.
  completo,

  /// Apenas a pasta `objectbox/` (data.mdb).
  somenteBanco,

  /// Cadastro de produtos (JSON + fotos), sem vendas/clientes/estoque operacional.
  cadastroProdutos,
}

extension LocalBackupEscopoJson on LocalBackupEscopo {
  String get manifestValue => switch (this) {
        LocalBackupEscopo.completo => 'completo',
        LocalBackupEscopo.somenteBanco => 'somente_banco',
        LocalBackupEscopo.cadastroProdutos => 'cadastro_produtos',
      };

  String get rotulo => switch (this) {
        LocalBackupEscopo.completo => 'Completo',
        LocalBackupEscopo.somenteBanco => 'Somente banco',
        LocalBackupEscopo.cadastroProdutos => 'Cadastro de produtos',
      };

  String get descricaoCurta => switch (this) {
        LocalBackupEscopo.completo =>
          'Banco, fotos, POD e configuracoes deste PC',
        LocalBackupEscopo.somenteBanco =>
          'Apenas o banco ObjectBox (data.mdb)',
        LocalBackupEscopo.cadastroProdutos =>
          'Produtos, precos, fiscal e fotos (sem vendas)',
      };

  /// Backups automaticos costumam ser completos ou somente banco.
  bool get disponivelNoAutomatico =>
      this == LocalBackupEscopo.completo ||
      this == LocalBackupEscopo.somenteBanco;
}

LocalBackupEscopo localBackupEscopoFromManifest(dynamic raw) {
  final v = raw?.toString().trim().toLowerCase() ?? '';
  if (v == LocalBackupEscopo.somenteBanco.manifestValue ||
      v == 'somente_banco' ||
      v == 'banco') {
    return LocalBackupEscopo.somenteBanco;
  }
  if (v == LocalBackupEscopo.cadastroProdutos.manifestValue ||
      v == 'cadastro_produtos' ||
      v == 'produtos') {
    return LocalBackupEscopo.cadastroProdutos;
  }
  return LocalBackupEscopo.completo;
}

List<LocalBackupEscopo> localBackupEscoposAutomaticos() =>
    LocalBackupEscopo.values.where((e) => e.disponivelNoAutomatico).toList();
