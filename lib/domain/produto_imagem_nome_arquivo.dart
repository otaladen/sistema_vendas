/// Validacao e nomes de arquivo de foto de produto (cliente + servidor sync).
abstract final class ProdutoImagemNomeArquivo {
  ProdutoImagemNomeArquivo._();

  /// Formato legado: `shared_<sha1>.jpg`.
  static final RegExp padraoShared =
      RegExp(r'^shared_[a-fA-F0-9]{40}\.jpg$');

  /// Formato atual: `nome_do_produto_a1b2c3d4.jpg`.
  static final RegExp padraoLegivel =
      RegExp(r'^[a-z0-9][a-z0-9_\-]{0,120}_[a-f0-9]{8}\.jpg$');

  static final RegExp _extensaoImagem =
      RegExp(r'\.(jpe?g|png|webp)$', caseSensitive: false);

  static bool valido(String raw) {
    final name = raw.trim();
    if (name.isEmpty ||
        name.contains('..') ||
        name.contains('\\') ||
        name.contains('/')) {
      return false;
    }
    return padraoShared.hasMatch(name) || padraoLegivel.hasMatch(name);
  }

  /// Aceita `shared_*.jpg`, `nome_hash.jpg` ou outro basename de imagem seguro.
  static bool validoParaLan(String raw) {
    if (valido(raw)) return true;
    final nome = nomeArquivoSeguro(raw);
    if (nome == null) return false;
    if (nome.length > 180) return false;
    return _extensaoImagem.hasMatch(nome);
  }

  static String? extrairNomeArquivo(String caminhoOuRelativo) {
    final s = caminhoOuRelativo.trim().replaceAll(r'\', '/');
    if (s.isEmpty) return null;
    final partes = s.split('/');
    final nome = partes.isNotEmpty ? partes.last : s;
    return valido(nome) ? nome : null;
  }

  /// Nome para sync/download LAN (shared_*, legivel ou imagem segura).
  static String? extrairNomeParaLan(String caminhoOuRelativo) {
    final canonico = extrairNomeArquivo(caminhoOuRelativo);
    if (canonico != null) return canonico;
    final seguro = nomeArquivoSeguro(caminhoOuRelativo);
    if (seguro == null) return null;
    return validoParaLan(seguro) ? seguro : null;
  }

  /// Basename seguro para qualquer imagem (backup/restore).
  static String? nomeArquivoSeguro(String caminhoOuRelativo) {
    final s = caminhoOuRelativo.trim().replaceAll(r'\', '/');
    if (s.isEmpty) return null;
    final nome = s.split('/').last.trim();
    if (nome.isEmpty ||
        nome.contains('..') ||
        nome.contains('/') ||
        nome.contains(r'\')) {
      return null;
    }
    return nome;
  }

  /// Prefixo legivel a partir do nome ou SKU do produto.
  static String prefixoDeIdentificador(String identificador) {
    if (identificador.trim().isEmpty) return '';
    var s = identificador.trim().toLowerCase();
    const mapa = {
      'á': 'a', 'à': 'a', 'ã': 'a', 'â': 'a', 'ä': 'a',
      'é': 'e', 'è': 'e', 'ê': 'e', 'ë': 'e',
      'í': 'i', 'ì': 'i', 'î': 'i', 'ï': 'i',
      'ó': 'o', 'ò': 'o', 'õ': 'o', 'ô': 'o', 'ö': 'o',
      'ú': 'u', 'ù': 'u', 'û': 'u', 'ü': 'u',
      'ç': 'c', 'ñ': 'n',
    };
    final buf = StringBuffer();
    for (final rune in s.runes) {
      final c = String.fromCharCode(rune);
      buf.write(mapa[c] ?? c);
    }
    s = buf.toString();
    s = s.replaceAll(RegExp(r'[^a-z0-9]+'), '_');
    s = s.replaceAll(RegExp(r'_+'), '_');
    s = s.replaceAll(RegExp(r'^_|_$'), '');
    if (s.length > 60) {
      s = s.substring(0, 60).replaceAll(RegExp(r'_$'), '');
    }
    return s;
  }

  /// `solei_marmore_br_145x15_a1b2c3d4.jpg` ou `shared_<sha1>.jpg` sem prefixo.
  static String gerarNomeArquivo({
    required String productIdentifier,
    required String hashCompleto,
  }) {
    final hashCurto = hashCompleto.length >= 8
        ? hashCompleto.substring(0, 8)
        : hashCompleto;
    final prefixo = prefixoDeIdentificador(productIdentifier);
    if (prefixo.isEmpty) {
      return 'shared_$hashCompleto.jpg';
    }
    return '${prefixo}_$hashCurto.jpg';
  }
}
