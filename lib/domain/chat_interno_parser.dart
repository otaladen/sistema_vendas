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

  static final pedidoNumeroPattern = RegExp(r'#(\d{1,9})');
  static final _pedidoRe = pedidoNumeroPattern;
  static final _mencaoRe =
      RegExp(r'(?:^|[^\w@])@([A-Za-zÀ-ÿ0-9._-]{2,30})');
  static final mencaoNoTextoPattern = RegExp(
    r'@([A-Za-zÀ-ÿ0-9._-]{2,30})',
  );

  /// Frases prontas para o mural (menu rapido ao lado do campo).
  static const frasesRapidas = <String>[
    'Cliente aguardando no balcão',
    'Conferir item no estoque',
    'Autorização solicitada no caixa',
    'Carga liberada para o motorista',
  ];

  static const sugestoesPapelMencao = <({String token, String rotulo})>[
    (token: 'caixa', rotulo: 'Caixa'),
    (token: 'gerente', rotulo: 'Gerente'),
    (token: 'vendedor', rotulo: 'Vendedor'),
    (token: 'motorista', rotulo: 'Motorista'),
    (token: 'estoque', rotulo: 'Estoque'),
  ];

  /// Todos os `#1234` citados no texto (ordem de aparicao, sem repetir).
  static List<int> numerosPedidoNoTexto(String texto) {
    final vistos = <int>{};
    final out = <int>[];
    for (final m in _pedidoRe.allMatches(texto)) {
      final n = int.tryParse(m.group(1) ?? '');
      if (n == null || n <= 0 || vistos.contains(n)) continue;
      vistos.add(n);
      out.add(n);
    }
    return out;
  }

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
    'estoque': 'estoque',
  };

  static const atalhosUi = <({String token, String rotulo})>[
    (token: '@caixa', rotulo: 'Caixa'),
    (token: '@patio', rotulo: 'Patio'),
    (token: '@motorista', rotulo: 'Motorista'),
    (token: '@vendedor', rotulo: 'Vendedor'),
    (token: '@gerente', rotulo: 'Gerente'),
    (token: '@estoque', rotulo: 'Estoque'),
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
      case 'estoque':
        return 'Estoque';
      case 'todos':
        return 'Todos';
      default:
        if (id.startsWith('login:')) return id.substring(6);
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
      final bruto = (m.group(1) ?? '').trim();
      final token = normalizarToken(bruto);
      final id = aliases[token];
      if (id != null) {
        mencoes.add(id);
      } else if (bruto.isNotEmpty) {
        mencoes.add('login:${bruto.toLowerCase()}');
      }
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
    return mencionadaParaOperador(
      perfilId: perfilId,
      loginUsuario: '',
      podeEstoque: false,
      mencoes: mencoes,
    );
  }

  static bool mencionadaParaOperador({
    required String perfilId,
    required String loginUsuario,
    required bool podeEstoque,
    required Iterable<String> mencoes,
  }) {
    final set = mencoes.map((e) => e.trim()).where((e) => e.isNotEmpty).toSet();
    if (set.isEmpty || set.contains('todos')) return false;
    final p = perfilId.trim();
    if (p.isNotEmpty && set.contains(p)) return true;
    if (p == 'separador' && set.contains('separador')) return true;
    if (set.contains('estoque') && (podeEstoque || p == 'comprador')) {
      return true;
    }
    final login = loginUsuario.trim().toLowerCase();
    if (login.isNotEmpty) {
      if (set.contains(login)) return true;
      if (set.contains('login:$login')) return true;
    }
    return false;
  }

  static String tokenInserirMencaoPapel(String token) => '@$token';

  static String tokenInserirMencaoUsuario(String login) => '@${login.trim()}';
}
