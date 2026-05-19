/// Sinônimos e termos relacionados para [ProdutoRepository.pesquisar].
/// Chaves e valores em texto já normalizado (sem acento, minúsculo).
const Map<String, List<String>> kProdutoBuscaSinonimos = {
  // Embalagem / unidade
  'cx': ['caixa', 'embalagem'],
  'caixa': ['cx', 'embalagem', 'agua', 'dagua'],
  'sc': ['saco', 'embalagem'],
  'saco': ['sc', 'embalagem'],
  'und': ['un', 'unidade', 'peca'],
  'un': ['und', 'unidade', 'peca'],
  'pc': ['peca', 'unidade'],
  'peca': ['pc', 'unidade'],
  'kg': ['quilo', 'quilograma'],
  'mt': ['metro', 'metragem'],

  // Cimento e derivados
  'cimento': ['cp2', 'cpii', 'cp', 'portland', 'argamassa'],
  'cp2': ['cimento', 'cpii', 'portland'],
  'cpii': ['cimento', 'cp2', 'portland'],
  'cp': ['cimento', 'cp2', 'cpii'],
  'portland': ['cimento', 'cp2', 'cpii'],

  // Areia / pedra / brita
  'areia': ['areiao', 'fina', 'grossa', 'media', 'lavada'],
  'areiao': ['areia', 'lavada'],
  'brita': ['pedra', 'britao', 'rachao'],
  'pedra': ['brita', 'rachao', 'seixo'],
  'rachao': ['brita', 'pedra'],
  'seixo': ['pedra', 'brita'],

  // Cal e gesso
  'cal': ['calhidrica', 'hidraulica', 'argamassa'],
  'calhidrica': ['cal', 'hidraulica'],
  'hidraulica': ['cal', 'calhidrica'],
  'gesso': ['drywall', 'placa', 'massa'],
  'drywall': ['gesso', 'placa', 'steel'],
  'placa': ['gesso', 'drywall', 'steel', 'osb', 'mdf'],

  // Ferro / aço
  'vergalhao': ['ferro', 'barra', 'aco', 'armadura'],
  'ferro': ['vergalhao', 'barra', 'aco', 'metal'],
  'barra': ['vergalhao', 'ferro', 'aco'],
  'aco': ['ferro', 'vergalhao', 'barra', 'metal'],
  'armadura': ['vergalhao', 'ferro', 'malha', 'tela'],
  'malha': ['tela', 'solda', 'armadura', 'eletrod'],
  'tela': ['malha', 'solda', 'eletrod'],

  // Madeira
  'madeira': ['caibro', 'ripa', 'viga', 'compensado', 'tabua'],
  'caibro': ['madeira', 'ripa', 'viga'],
  'ripa': ['madeira', 'caibro'],
  'viga': ['madeira', 'caibro'],
  'compensado': ['madeira', 'compens', 'osb', 'mdf'],
  'osb': ['compensado', 'madeira', 'mdf'],
  'mdf': ['compensado', 'madeira', 'osb'],
  'tabua': ['madeira', 'ripa', 'caibro'],

  // Alvenaria
  'tijolo': ['bloco', 'ceramica', 'tijolinha', 'refugir'],
  'bloco': ['tijolo', 'ceramica', 'concreto'],
  'ceramica': ['tijolo', 'bloco', 'piso', 'revestimento', 'porcelanato'],
  'tijolinha': ['tijolo', 'bloco'],

  // Cobertura
  'telha': ['telhas', 'fibrocimento', 'eternit', 'cobertura'],
  'fibrocimento': ['telha', 'eternit', 'cobertura'],
  'eternit': ['fibrocimento', 'telha'],
  'cobertura': ['telha', 'fibrocimento', 'rufo', 'calha'],

  // Hidráulica (tokens normalizados)
  'pvc': ['tubo', 'cano', 'esgoto', 'agua', 'hidraulico', 'conexao'],
  'tubo': ['pvc', 'cano', 'esgoto', 'agua', 'conexao'],
  'cano': ['tubo', 'pvc', 'esgoto'],
  'esgoto': ['tubo', 'pvc', 'cano', 'conexao'],
  'conexao': ['joelho', 'curva', 'adaptador', 'luva', 'pvc'],
  'joelho': ['conexao', 'curva'],
  'registro': ['valvula', 'torneira'],
  'valvula': ['registro', 'torneira'],
  'torneira': ['registro', 'valvula', 'misturador'],
  'dagua': ['caixa', 'agua', 'hidraulico'],
  'agua': ['dagua', 'hidraulico', 'esgoto'],

  // Elétrica
  'fio': ['cabo', 'eletrico', 'eletrica', 'condutor'],
  'cabo': ['fio', 'eletrico', 'eletrica'],
  'eletrico': ['fio', 'cabo', 'tomada', 'disjuntor', 'interruptor'],
  'eletrica': ['fio', 'cabo', 'tomada', 'disjuntor'],
  'tomada': ['eletrico', 'interruptor', 'plug'],
  'disjuntor': ['eletrico', 'dr', 'quadro'],
  'interruptor': ['eletrico', 'tomada'],

  // Tintas e acabamento
  'tinta': ['latex', 'acrilica', 'esmalte', 'selador', 'pintura'],
  'latex': ['tinta', 'acrilica', 'pva'],
  'acrilica': ['tinta', 'latex'],
  'esmalte': ['tinta', 'verniz'],
  'selador': ['tinta', 'primer', 'fundo'],
  'massa': ['gesso', 'corrida', 'acabamento'],
  'corrida': ['massa', 'gesso', 'acabamento'],

  // Pisos e revestimentos
  'piso': ['ceramica', 'porcelanato', 'revestimento', 'azulejo'],
  'porcelanato': ['piso', 'ceramica', 'revestimento'],
  'revestimento': ['piso', 'ceramica', 'porcelanato', 'azulejo'],
  'azulejo': ['revestimento', 'ceramica', 'piso'],
  'rejunte': ['argamassa', 'cola', 'acrilico'],

  // Colas e adesivos
  'cola': ['adesivo', 'argamassa', 'rejunte', 'monta'],
  'adesivo': ['cola', 'selante', 'silicone'],
  'argamassa': ['cola', 'rejunte', 'cimento', 'cal'],
  'silicone': ['adesivo', 'selante', 'vedacao'],
  'selante': ['silicone', 'adesivo', 'vedacao'],

  // Fixação
  'parafuso': ['bucha', 'fixacao', 'rosca'],
  'bucha': ['parafuso', 'fixacao', 'nylon'],
  'prego': ['pregos', 'fixacao'],
  'pregos': ['prego', 'fixacao'],

  // Impermeabilização
  'impermeabilizante': ['manta', 'feltro', 'vedacao', 'lona'],
  'manta': ['impermeabilizante', 'feltro', 'asfaltica'],
  'feltro': ['manta', 'impermeabilizante'],
  'lona': ['plastica', 'polietileno', 'impermeabilizante'],
  'plastica': ['lona', 'polietileno', 'nylon'],

  // Ferramentas / consumíveis
  'disco': ['desbaste', 'corte', 'lixa'],
  'lixa': ['disco', 'desbaste', 'corte'],
  'broca': ['furacao', 'perfuracao'],
  'rolo': ['rolete', 'pintura', 'trincha'],
  'rolete': ['rolo', 'pintura'],
  'pincel': ['trincha', 'rolo'],
  'trincha': ['pincel', 'rolo'],

  // EPI
  'luva': ['conexao', 'pvc', 'epi', 'seguranca', 'borracha'],
  'bota': ['epi', 'seguranca', 'botina'],
  'capacete': ['epi', 'seguranca'],
  'epi': ['luva', 'bota', 'capacete', 'seguranca'],

  // Aberturas
  'porta': ['batente', 'marco', 'fechadura'],
  'janela': ['vidro', 'aluminio', 'esquadria'],
  'vidro': ['janela', 'temperado'],
  'fechadura': ['porta', 'cilindro', 'macaneta'],
  'macaneta': ['fechadura', 'porta'],

  // Concreto / formas
  'concreto': ['cimento', 'brita', 'areia', 'forma'],
  'forma': ['concreto', 'tabua', 'compensado'],

  // Energia solar / aquecedor (comum em lojas grandes)
  'aquecedor': ['solar', 'boiler', 'reservatorio'],
  'solar': ['aquecedor', 'placa', 'coletor'],
};

/// Expande tokens da consulta com sinônimos do mapa.
Iterable<String> expandirTokensBuscaComSinonimos(List<String> tokens) sync* {
  for (final token in tokens) {
    if (token.isEmpty) continue;
    yield token;
    final encontrados = kProdutoBuscaSinonimos[token];
    if (encontrados != null) {
      for (final sin in encontrados) {
        if (sin.isNotEmpty) yield sin;
      }
    }
  }
}
