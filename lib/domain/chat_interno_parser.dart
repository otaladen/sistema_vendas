/// Extrai @setor e #pedido do mural interno.
class ChatInternoParse {
  const ChatInternoParse({
    this.mencoes = const {},
    this.pedidoNumero,
  });

  /// IDs de perfil ([caixa], [motorista], [separador], …) ou `todos`.
  final Set<String> mencoes;
  final int? pedidoNumero;

  bool get temMencaoDirecionada =>
      mencoes.isNotEmpty && !mencoes.contains('todos');
}

abstract final class ChatInternoParser {
  ChatInternoParser._();

  static final _pedidoRe = RegExp(r'#(\d{1,9})');
  static final _mencaoRe = RegExp(r'(?:^|[^\w@])@([A-Za-zÀ-ÿ]{2,20})');

  static const aliases = <String, String>{
    'caixa': 'caixa',
    'motorista': 'motorista',
    'vendedor': 'vendedor',
    'gerente': 'gerente',
    'dono': 'dono',
    'comprador': 'comprador',
    'separador': 'separador',
    'patio': 'separador',
    'expedicao': 'separador',
    'carga': 'separador',
    'todos': 'todos',
    'equipe': 'todos',
    'loja': 'todos',
  };

  static const atalhosUi = <({String token, String rotulo})>[
    (token: '@caixa', rotulo: 'Caixa'),
    (token: '@patio', rotulo: 'Patio'),
    (token: '@motorista', rotulo: 'Motorista'),
    (token: '@vendedor', rotulo: 'Vendedor'),
    (token: '@gerente', rotulo: 'Gerente'),
  ];

  static String rotuloMencao(String id) {
    switch (id) {
      case 'caixa':
        return 'Caixa';
      case 'motorista':
        return 'Motorista';
      case 'vendedor':
        return 'Vendedor';
      case 'gerente':
        return 'Gerente';
      case 'dono':
        return 'Dono';
      case 'comprador':
        return 'Comprador';
      case 'separador':
        return 'Patio';
      case 'todos':
        return 'Todos';
      default:
        return id;
    }
  }

  static String normalizarToken(String raw) {
    final s = raw.trim().toLowerCase();
    const mapa = {
      'á': 'a',
      'à': 'a',
      'ã': 'a',
      'â': 'a',
      'é': 'e',
      'ê': 'e',
      'í': 'i',
      'ó': 'o',
      'ô': 'o',
      'õ': 'o',
      'ú': 'u',
      'ç': 'c',
    };
    final b = StringBuffer();
    for (final r in s.runes) {
      final ch = String.fromCharCode(r);
      b.write(mapa[ch] ?? ch);
    }
    return b.toString();
  }

  static ChatInternoParse parse(String texto) {
    final mencoes = <String>{};
    for (final m in _mencaoRe.allMatches(texto)) {
      final token = normalizarToken(m.group(1) ?? '');
      final id = aliases[token];
      if (id != null) mencoes.add(id);
    }
    int? pedido;
    final pm = _pedidoRe.firstMatch(texto);
    if (pm != null) {
      pedido = int.tryParse(pm.group(1) ?? '');
      if (pedido != null && pedido <= 0) pedido = null;
    }
    return ChatInternoParse(mencoes: mencoes, pedidoNumero: pedido);
  }

  /// Mensagem dirigida a este perfil (mural geral nao conta).
  static bool mencionadaPara(String perfilId, Iterable<String> mencoes) {
    final set = mencoes.map((e) => e.trim()).where((e) => e.isNotEmpty).toSet();
    if (set.isEmpty || set.contains('todos')) return false;
    final p = perfilId.trim();
    if (p.isEmpty) return false;
    if (set.contains(p)) return true;
    if (p == 'separador' && set.contains('separador')) return true;
    return false;
  }
}
