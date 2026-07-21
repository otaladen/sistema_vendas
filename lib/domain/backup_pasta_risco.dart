/// Detecta pastas de destino pouco seguras para backup (nuvem / Desktop / Downloads).
class BackupPastaRisco {
  BackupPastaRisco._();

  static final _padroes = <RegExp>[
    RegExp(r'onedrive', caseSensitive: false),
    RegExp(r'dropbox', caseSensitive: false),
    RegExp(r'google\s*drive', caseSensitive: false),
    RegExp(r'[\\/]Desktop([\\/]|$)', caseSensitive: false),
    RegExp(r'Área de Trabalho', caseSensitive: false),
    RegExp(r'Area de Trabalho', caseSensitive: false),
    RegExp(r'[\\/]Downloads([\\/]|$)', caseSensitive: false),
    RegExp(r'[\\/]Download([\\/]|$)', caseSensitive: false),
  ];

  static bool pareceRisco(String caminho) {
    final t = caminho.trim();
    if (t.isEmpty) return false;
    for (final r in _padroes) {
      if (r.hasMatch(t)) return true;
    }
    return false;
  }

  static String mensagemAviso(String caminho) {
    return 'A pasta escolhida parece estar na Area de Trabalho, Downloads '
        'ou em sincronizacao com a nuvem (OneDrive, Dropbox, etc.).\n\n'
        'Isso pode corromper ou “sumir” com o backup.\n\n'
        'Recomendado: pasta local dedicada, por exemplo D:\\Backups\\SistemaVendas.\n\n'
        'Pasta:\n$caminho';
  }
}
