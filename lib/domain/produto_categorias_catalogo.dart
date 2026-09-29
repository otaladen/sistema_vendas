/// Setor da loja usado para agrupar categorias na selecao.
class ProdutoCategoriaSetor {
  const ProdutoCategoriaSetor({
    required this.nome,
    required this.categorias,
  });

  final String nome;
  final List<String> categorias;
}

/// Catalogo de categorias e subcategorias do cadastro de produtos.
abstract final class ProdutoCategoriasCatalogo {
  ProdutoCategoriasCatalogo._();

  static const String outros = 'Outros';

  static const Map<String, List<String>> materiaisConstrucao = {
    'Cimento e Argamassas': [
      'Cimento',
      'Argamassa',
      'Rejunte',
      'Cal',
      'Argamassa Colante',
      'Gesso em Po',
      'Graute',
      'Chapisco',
      'Concreto',
      'Contrapiso',
    ],
    'Telhas e Cobertura': [
      'Telha Ceramica',
      'Telha Fibrocimento',
      'Telha Metalica',
      'Telha PVC',
      'Cumeeira',
      'Rufos e Calhas',
      'Manta Termica',
      'Parafuso para Telha',
      'Telha de Concreto',
      'Telha Translucida',
      'Espigao',
    ],
    'Estrutural e Alvenaria': [
      'Tijolo',
      'Bloco de Concreto',
      'Canaleta',
      'Areia',
      'Brita',
      'Pedra',
      'Aco para Construcao',
      'Vergalhao',
      'Bloco Ceramico',
      'Laje e Trelica',
      'Arame Recozido',
      'Po de Pedra',
      'Tela para Concreto',
    ],
    'Tintas e Acessorios': [
      'Tinta Acrilica',
      'Tinta Esmalte',
      'Selador',
      'Verniz',
      'Rolo e Pincel',
      'Massa Corrida',
      'Massa Acrilica',
      'Textura',
      'Fundo Preparador',
      'Tinta para Piso',
      'Tinta Epoxi',
      'Spray',
      'Solvente e Thinner',
    ],
    'Hidraulica': [
      'Tubos e Conexoes',
      'Registros',
      'Torneiras',
      'Caixa d\'agua',
      'Sifoes e Valvulas',
      'Bombas',
      'Irrigacao',
      'Acessorios para Banheiro',
      'Tubo de Esgoto',
      'Agua Quente (CPVC e PPR)',
      'Caixa de Gordura',
      'Ralos e Grelhas',
      'Valvula de Descarga',
      'Flexiveis e Engates',
      'Filtros e Purificadores',
    ],
    'Eletrica': [
      'Fios e Cabos',
      'Disjuntores',
      'Tomadas e Interruptores',
      'Quadro de Distribuicao',
      'Iluminacao',
      'Eletroduto',
      'Canaleta',
      'Luminaria LED',
      'Fita Isolante',
      'Conectores e Emendas',
      'DR e DPS',
      'Caixa de Passagem',
      'Eletrocalha',
      'Extensao e Plugue',
      'Sensores e Campainhas',
    ],
    'Ferragens': [
      'Parafusos e Buchas',
      'Pregos',
      'Dobradiças',
      'Fechaduras',
      'Correntes e Cabos de Aco',
      'Abraçadeiras',
      'Chapas e Cantoneiras',
      'Fixadores',
      'Puxadores e Macanetas',
      'Cadeados',
      'Porcas e Arruelas',
      'Rebites',
      'Arames e Grampos',
      'Suportes e Ganchos',
    ],
    'Madeiras e Chapas': [
      'Compensado',
      'MDF',
      'OSB',
      'Vigas e Ripas',
      'Portas e Batentes',
      'Sarrafo e Caibro',
      'Tabua',
      'Deck',
      'MDP',
      'Chapa Naval',
    ],
    'Pisos e Revestimentos': [
      'Piso Ceramico',
      'Porcelanato',
      'Revestimento de Parede',
      'Rodape',
      'Pastilha',
      'Piso Vinilico',
      'Piso Laminado',
      'Piso Intertravado',
      'Pedra Natural',
      'Soleira e Peitoril',
      'Espacador de Piso',
    ],
    'Loucas e Metais': [
      'Vaso Sanitario',
      'Lavatório',
      'Cuba',
      'Torneira',
      'Chuveiro',
      'Misturador',
      'Assento Sanitario',
      'Pia de Cozinha',
      'Tanque',
      'Banheira',
      'Ducha Higienica',
      'Caixa Acoplada',
      'Acessorios de Banheiro',
      'Ralo Linear',
    ],
    'Impermeabilizacao e Quimicos': [
      'Impermeabilizante',
      'Vedante',
      'Silicone',
      'Espuma Expansiva',
      'Aditivo para Concreto',
      'Desmoldante',
      'Manta Asfaltica',
      'Manta Liquida',
      'Primer Asfaltico',
      'Tela de Poliester',
      'Hidrofugante',
    ],
    'Ferramentas': [
      'Manuais',
      'Eletricas',
      'Medicao',
      'EPIs',
      'Acessorios de Corte',
      'Pneumaticas',
      'Escadas',
      'Carrinho de Mao',
      'Betoneira',
      'Ferramentas de Pedreiro',
    ],
    'Jardinagem e Externo': [
      'Mangueira',
      'Grama Sintetica',
      'Ferramentas de Jardim',
      'Vaso e Cachepot',
      'Pedrisco Decorativo',
      'Terra e Substrato',
      'Adubo',
      'Regador e Aspersor',
      'Irrigacao de Jardim',
    ],
    'Forros e Divisorias': [
      'Forro PVC',
      'Forro Gesso',
      'Perfil para Drywall',
      'Chapa Drywall',
      'Acessorios Drywall',
      'Forro Mineral',
      'Forro de Isopor',
      'Lambri',
      'Perfil de Aluminio',
    ],
    'Portas, Janelas e Vidros': [
      'Porta de Madeira',
      'Porta de Aluminio',
      'Porta Sanfonada',
      'Janela',
      'Basculante',
      'Vidro',
      'Espelho',
      'Box para Banheiro',
      'Grade e Portao',
    ],
    'Iluminacao': [
      'Lampada',
      'Luminaria',
      'Refletor',
      'Painel de LED',
      'Spot e Embutido',
      'Fita de LED',
      'Plafon e Arandela',
      'Soquete e Reator',
    ],
    'Climatizacao': [
      'Ventilador',
      'Exaustor',
      'Ar Condicionado',
      'Aquecedor',
    ],
    'Abrasivos e Corte': [
      'Lixa',
      'Disco de Corte',
      'Disco de Desbaste',
      'Broca',
      'Serra Copo',
      'Eletrodo de Solda',
    ],
    'Colas, Fitas e Vedacao': [
      'Cola Branca e de Madeira',
      'Adesivo Instantaneo',
      'Fita Crepe',
      'Fita Veda Rosca',
      'Fita Dupla Face',
      'Massa de Vedacao',
    ],
    'EPIs e Seguranca': [
      'Capacete',
      'Luva',
      'Oculos de Protecao',
      'Bota de Seguranca',
      'Mascara e Respirador',
      'Protetor Auricular',
      'Cinto de Seguranca',
      'Sinalizacao de Obra',
    ],
    'Telas, Cercas e Alambrados': [
      'Tela Soldada',
      'Alambrado',
      'Tela Mosquiteiro',
      'Arame Farpado',
      'Mourao',
      'Concertina',
    ],
    outros: [],
  };

  static const List<ProdutoCategoriaSetor> setores = [
    ProdutoCategoriaSetor(
      nome: 'Obra bruta',
      categorias: [
        'Cimento e Argamassas',
        'Estrutural e Alvenaria',
        'Telhas e Cobertura',
        'Impermeabilizacao e Quimicos',
        'Forros e Divisorias',
      ],
    ),
    ProdutoCategoriaSetor(
      nome: 'Acabamento',
      categorias: [
        'Tintas e Acessorios',
        'Pisos e Revestimentos',
        'Loucas e Metais',
        'Madeiras e Chapas',
        'Portas, Janelas e Vidros',
      ],
    ),
    ProdutoCategoriaSetor(
      nome: 'Instalacoes',
      categorias: [
        'Hidraulica',
        'Eletrica',
        'Iluminacao',
        'Climatizacao',
      ],
    ),
    ProdutoCategoriaSetor(
      nome: 'Ferragens e ferramentas',
      categorias: [
        'Ferragens',
        'Ferramentas',
        'Abrasivos e Corte',
        'Colas, Fitas e Vedacao',
        'EPIs e Seguranca',
        'Telas, Cercas e Alambrados',
      ],
    ),
    ProdutoCategoriaSetor(
      nome: 'Area externa',
      categorias: [
        'Jardinagem e Externo',
      ],
    ),
    ProdutoCategoriaSetor(
      nome: 'Geral',
      categorias: [outros],
    ),
  ];

  /// Nomes curtos ou de sistemas legados que apontam para uma categoria.
  static const Map<String, String> aliases = {
    'hidraulico': 'Hidraulica',
    'eletrico': 'Eletrica',
    'tintas': 'Tintas e Acessorios',
    'cimento': 'Cimento e Argamassas',
    'argamassa': 'Cimento e Argamassas',
    'telhas': 'Telhas e Cobertura',
    'cobertura': 'Telhas e Cobertura',
    'alvenaria': 'Estrutural e Alvenaria',
    'estrutural': 'Estrutural e Alvenaria',
    'madeiras': 'Madeiras e Chapas',
    'pisos': 'Pisos e Revestimentos',
    'revestimentos': 'Pisos e Revestimentos',
    'loucas': 'Loucas e Metais',
    'metais': 'Loucas e Metais',
    'impermeabilizacao': 'Impermeabilizacao e Quimicos',
    'quimicos': 'Impermeabilizacao e Quimicos',
    'jardinagem': 'Jardinagem e Externo',
    'forros': 'Forros e Divisorias',
    'drywall': 'Forros e Divisorias',
    'portas': 'Portas, Janelas e Vidros',
    'janelas': 'Portas, Janelas e Vidros',
    'vidros': 'Portas, Janelas e Vidros',
    'iluminacao': 'Iluminacao',
    'lampadas': 'Iluminacao',
    'climatizacao': 'Climatizacao',
    'abrasivos': 'Abrasivos e Corte',
    'colas': 'Colas, Fitas e Vedacao',
    'fitas': 'Colas, Fitas e Vedacao',
    'epis': 'EPIs e Seguranca',
    'seguranca': 'EPIs e Seguranca',
    'cercas': 'Telas, Cercas e Alambrados',
    'alambrados': 'Telas, Cercas e Alambrados',
    'telas': 'Telas, Cercas e Alambrados',
  };

  static List<String> subcategoriasDe(String? categoria) =>
      materiaisConstrucao[categoria] ?? const [];

  static String? setorDe(String? categoria) {
    if (categoria == null || categoria.trim().isEmpty) return null;
    for (final setor in setores) {
      if (setor.categorias.contains(categoria)) return setor.nome;
    }
    return null;
  }

  static String? resolverCategoria(String bruto) {
    final texto = bruto.trim();
    if (texto.isEmpty) return null;
    if (materiaisConstrucao.containsKey(texto)) return texto;
    final n = normalizar(texto);
    if (n.isEmpty) return null;
    final alias = aliases[n];
    if (alias != null && materiaisConstrucao.containsKey(alias)) return alias;
    for (final key in materiaisConstrucao.keys) {
      if (normalizar(key) == n) return key;
    }
    return null;
  }

  static String normalizar(String s) => s
      .toLowerCase()
      .replaceAll(RegExp(r'[áàâãä]'), 'a')
      .replaceAll(RegExp(r'[éèêë]'), 'e')
      .replaceAll(RegExp(r'[íìîï]'), 'i')
      .replaceAll(RegExp(r'[óòôõö]'), 'o')
      .replaceAll(RegExp(r'[úùûü]'), 'u')
      .replaceAll(RegExp(r'[ç]'), 'c')
      .replaceAll(RegExp(r'[^a-z0-9]'), '');

  static String textoParaPrompt() {
    final buf = StringBuffer(
      'Catalogo da loja — use categoria_sugerida e subcategoria_sugerida '
      'com o texto EXATO de uma opcao abaixo:\n',
    );
    for (final setor in setores) {
      buf.writeln('Setor ${setor.nome}:');
      for (final cat in setor.categorias) {
        if (cat == outros) continue;
        final subs = materiaisConstrucao[cat] ?? const <String>[];
        if (subs.isEmpty) continue;
        buf.writeln('- $cat: ${subs.join(' | ')}');
      }
    }
    return buf.toString();
  }
}
