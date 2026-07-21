/// Entrada da tabela de NCM sugeridos para loja de materiais de construcao.
class NcmCatalogoItem {
  const NcmCatalogoItem({
    required this.codigo,
    required this.descricao,
  });

  /// 8 digitos, sem pontuacao.
  final String codigo;
  final String descricao;

  String get codigoFormatado {
    if (codigo.length != 8) return codigo;
    return '${codigo.substring(0, 4)}.${codigo.substring(4, 6)}.${codigo.substring(6)}';
  }

  String get rotuloLista => '$codigoFormatado — $descricao';

  bool corresponde(String termo) {
    final t = termo.trim().toLowerCase();
    if (t.isEmpty) return true;
    final digits = t.replaceAll(RegExp(r'\D'), '');
    if (digits.isNotEmpty && codigo.contains(digits)) return true;
    return descricao.toLowerCase().contains(t) ||
        codigoFormatado.toLowerCase().contains(t);
  }
}

/// Tabela de NCM mais usados em material de construcao / hidraulica / eletrica.
///
/// Nao e a TIPI completa — e a lista pratica da loja (como no sistema antigo).
/// O usuario pode digitar qualquer outro NCM fora desta lista.
abstract final class NcmMateriaisCatalogo {
  NcmMateriaisCatalogo._();

  static const itens = <NcmCatalogoItem>[
    // Agregados / minerais
    NcmCatalogoItem(
      codigo: '25051000',
      descricao: 'AREIAS NATURAIS DE QUALQUER ESPECIE',
    ),
    NcmCatalogoItem(
      codigo: '25171000',
      descricao: 'SEIXOS, CASCALHO, PEDRAS BRITADAS',
    ),
    NcmCatalogoItem(
      codigo: '25174100',
      descricao: 'GRANULOS, LASCAS E POS DE MARMORE',
    ),
    NcmCatalogoItem(
      codigo: '25202010',
      descricao: 'GESSO',
    ),
    NcmCatalogoItem(
      codigo: '25221000',
      descricao: 'CAL VIVA',
    ),
    NcmCatalogoItem(
      codigo: '25222000',
      descricao: 'CAL APAGADA',
    ),
    NcmCatalogoItem(
      codigo: '25231000',
      descricao: 'CIMIENTOS NAO PULVERIZADOS (CLINKER)',
    ),
    NcmCatalogoItem(
      codigo: '25232100',
      descricao: 'CIMENTO PORTLAND BRANCO',
    ),
    NcmCatalogoItem(
      codigo: '25232910',
      descricao: 'CIMENTO PORTLAND COMUM',
    ),
    NcmCatalogoItem(
      codigo: '25232990',
      descricao: 'OUTROS CIMENTOS PORTLAND',
    ),
    NcmCatalogoItem(
      codigo: '25239000',
      descricao: 'OUTROS CIMENTOS HIDRAULICOS',
    ),

    // Madeira / compensados
    NcmCatalogoItem(
      codigo: '44071100',
      descricao: 'MADEIRA SERRADA DE CONIFERAS',
    ),
    NcmCatalogoItem(
      codigo: '44101100',
      descricao: 'PAINEIS DE PARTICULAS (AGLOMERADO)',
    ),
    NcmCatalogoItem(
      codigo: '44123100',
      descricao: 'MADEIRA COMPENSADA',
    ),

    // Plasticos / hidraulica PVC
    NcmCatalogoItem(
      codigo: '39172100',
      descricao: 'TUBOS DE POLIMEROS DE ETILENO',
    ),
    NcmCatalogoItem(
      codigo: '39172200',
      descricao: 'TUBOS DE POLIMEROS DE PROPILENO',
    ),
    NcmCatalogoItem(
      codigo: '39172300',
      descricao: 'TUBOS DE POLIMEROS DE CLORETO DE VINILO (PVC)',
    ),
    NcmCatalogoItem(
      codigo: '39172900',
      descricao: 'TUBOS DE OUTROS PLASTICOS',
    ),
    NcmCatalogoItem(
      codigo: '39174010',
      descricao: 'ACESSORIOS PARA TUBOS DE PVC',
    ),
    NcmCatalogoItem(
      codigo: '39174090',
      descricao: 'OUTROS ACESSORIOS PARA TUBOS PLASTICOS',
    ),
    NcmCatalogoItem(
      codigo: '39221000',
      descricao: 'BANHEIRAS, BOXES E SIMILARES DE PLASTICO',
    ),
    NcmCatalogoItem(
      codigo: '39222000',
      descricao: 'ASSENTOS E TAMPAS DE SANITARIOS DE PLASTICO',
    ),
    NcmCatalogoItem(
      codigo: '39229000',
      descricao: 'OUTROS ARTIGOS HIGIENICOS DE PLASTICO',
    ),
    NcmCatalogoItem(
      codigo: '39251000',
      descricao: 'RESERVATORIOS, CAIXAS D\'AGUA E SIMILARES DE PLASTICO',
    ),
    NcmCatalogoItem(
      codigo: '39252000',
      descricao: 'PORTAS, JANELAS E SEUS ALIZARES DE PLASTICO',
    ),
    NcmCatalogoItem(
      codigo: '39259010',
      descricao: 'OUTROS ARTIGOS PARA CONSTRUCAO DE PLASTICO',
    ),

    // Borracha / impermeabilizacao
    NcmCatalogoItem(
      codigo: '40082100',
      descricao: 'CHAPAS E TIRAS DE BORRACHA VULCANIZADA',
    ),

    // Papelao / isolamento
    NcmCatalogoItem(
      codigo: '48191000',
      descricao: 'CAIXAS DE PAPEL OU PAPELAO',
    ),

    // Fibras / telhas
    NcmCatalogoItem(
      codigo: '68114000',
      descricao: 'ARTIGOS DE FIBROCIMENTO COM AMIANTO',
    ),
    NcmCatalogoItem(
      codigo: '68118100',
      descricao: 'TELHAS ONDULADAS DE FIBROCIMENTO SEM AMIANTO',
    ),
    NcmCatalogoItem(
      codigo: '68118200',
      descricao: 'OUTRAS FOLHAS E PAINEIS DE FIBROCIMENTO SEM AMIANTO',
    ),
    NcmCatalogoItem(
      codigo: '68118900',
      descricao: 'OUTROS ARTIGOS DE FIBROCIMENTO SEM AMIANTO',
    ),

    // Ceramicos / pisos / loucas
    NcmCatalogoItem(
      codigo: '69010000',
      descricao: 'TIJOLOS, PLACAS E SIMILARES REFRATARIOS',
    ),
    NcmCatalogoItem(
      codigo: '69041000',
      descricao: 'TIJOLOS PARA CONSTRUCAO',
    ),
    NcmCatalogoItem(
      codigo: '69051000',
      descricao: 'TELHAS CERAMICAS',
    ),
    NcmCatalogoItem(
      codigo: '69059000',
      descricao: 'OUTROS ELEMENTOS CERAMICOS PARA CONSTRUCAO',
    ),
    NcmCatalogoItem(
      codigo: '69072100',
      descricao: 'LAMINADOS CERAMICOS ABSORCAO <= 0,5%',
    ),
    NcmCatalogoItem(
      codigo: '69072200',
      descricao: 'LAMINADOS CERAMICOS ABSORCAO > 0,5% E <= 10%',
    ),
    NcmCatalogoItem(
      codigo: '69072300',
      descricao: 'LAMINADOS CERAMICOS ABSORCAO > 10%',
    ),
    NcmCatalogoItem(
      codigo: '69073000',
      descricao: 'MOSAICOS CERAMICOS',
    ),
    NcmCatalogoItem(
      codigo: '69074000',
      descricao: 'PEDACOS E ACABAMENTOS CERAMICOS',
    ),
    NcmCatalogoItem(
      codigo: '69101000',
      descricao: 'LOUCAS SANITARIAS DE PORCELANA',
    ),
    NcmCatalogoItem(
      codigo: '69109000',
      descricao: 'OUTRAS LOUCAS SANITARIAS CERAMICAS',
    ),

    // Vidro
    NcmCatalogoItem(
      codigo: '70052900',
      descricao: 'VIDRO FLOTADO E VIDRO DESBASTADO',
    ),
    NcmCatalogoItem(
      codigo: '70071900',
      descricao: 'VIDRO TEMPERADO DE SEGURANCA',
    ),
    NcmCatalogoItem(
      codigo: '70080000',
      descricao: 'VIDROS ISOLANTES DE PAREDES MULTIPLAS',
    ),

    // Ferro / aco / ferragens
    NcmCatalogoItem(
      codigo: '72131000',
      descricao: 'FIOS DE FERRO OU ACO LAMINADOS A QUENTE',
    ),
    NcmCatalogoItem(
      codigo: '72142000',
      descricao: 'BARRAS DE FERRO OU ACO COM ENTALHES (VERGALHAO)',
    ),
    NcmCatalogoItem(
      codigo: '72149910',
      descricao: 'OUTRAS BARRAS DE FERRO OU ACO NAO LIGADO',
    ),
    NcmCatalogoItem(
      codigo: '72161000',
      descricao: 'PERFIS DE FERRO OU ACO EM U, I OU H',
    ),
    NcmCatalogoItem(
      codigo: '73063000',
      descricao: 'TUBOS SOLDADOS DE FERRO OU ACO',
    ),
    NcmCatalogoItem(
      codigo: '73066100',
      descricao: 'TUBOS SOLDADOS DE SECAO QUADRADA OU RETANGULAR',
    ),
    NcmCatalogoItem(
      codigo: '73071100',
      descricao: 'ACESSORIOS PARA TUBOS DE FERRO FUNDIDO',
    ),
    NcmCatalogoItem(
      codigo: '73071910',
      descricao: 'ACESSORIOS PARA TUBOS DE ACO',
    ),
    NcmCatalogoItem(
      codigo: '73083000',
      descricao: 'PORTAS, JANELAS E SEUS ALIZARES DE FERRO OU ACO',
    ),
    NcmCatalogoItem(
      codigo: '73089010',
      descricao: 'OUTRAS ESTRUTURAS E PARTES DE FERRO OU ACO',
    ),
    NcmCatalogoItem(
      codigo: '73170010',
      descricao: 'PREGOS DE FERRO OU ACO',
    ),
    NcmCatalogoItem(
      codigo: '73181500',
      descricao: 'PARAFUSOS E PINOS DE FERRO OU ACO',
    ),
    NcmCatalogoItem(
      codigo: '73181600',
      descricao: 'PORCAS DE FERRO OU ACO',
    ),
    NcmCatalogoItem(
      codigo: '73181900',
      descricao: 'OUTROS ARTIGOS ROSQUEADOS DE FERRO OU ACO',
    ),
    NcmCatalogoItem(
      codigo: '73170090',
      descricao: 'TAXBOS, GRAMPOS E SIMILARES DE FERRO OU ACO',
    ),
    NcmCatalogoItem(
      codigo: '73269090',
      descricao: 'OUTRAS OBRAS DE FERRO OU ACO',
    ),

    // Metais nao ferrosos
    NcmCatalogoItem(
      codigo: '74111010',
      descricao: 'TUBOS DE COBRE REFINADO',
    ),
    NcmCatalogoItem(
      codigo: '74121000',
      descricao: 'ACESSORIOS PARA TUBOS DE COBRE',
    ),
    NcmCatalogoItem(
      codigo: '76061110',
      descricao: 'CHAPAS E TIRAS DE ALUMINIO',
    ),
    NcmCatalogoItem(
      codigo: '76101000',
      descricao: 'PORTAS, JANELAS E SEUS ALIZARES DE ALUMINIO',
    ),
    NcmCatalogoItem(
      codigo: '76109000',
      descricao: 'OUTRAS ESTRUTURAS E PARTES DE ALUMINIO',
    ),

    // Ferramentas
    NcmCatalogoItem(
      codigo: '82011000',
      descricao: 'PAS E PAZINHAS',
    ),
    NcmCatalogoItem(
      codigo: '82013000',
      descricao: 'ALVIOES, PICARETAS E ENXADAS',
    ),
    NcmCatalogoItem(
      codigo: '82021000',
      descricao: 'SERRAS MANUAIS',
    ),
    NcmCatalogoItem(
      codigo: '82041100',
      descricao: 'CHAVES DE PORCAS DE ABERTURA FIXA',
    ),
    NcmCatalogoItem(
      codigo: '82041200',
      descricao: 'CHAVES DE PORCAS DE ABERTURA VARIAVEL',
    ),
    NcmCatalogoItem(
      codigo: '82054000',
      descricao: 'CHAVE DE FENDA',
    ),
    NcmCatalogoItem(
      codigo: '82052000',
      descricao: 'MARTELOS E MARRETAS',
    ),
    NcmCatalogoItem(
      codigo: '82055900',
      descricao: 'OUTRAS FERRAMENTAS MANUAIS',
    ),
    NcmCatalogoItem(
      codigo: '82075000',
      descricao: 'FERRAMENTAS DE FURAR',
    ),

    // Metais / torneiras
    NcmCatalogoItem(
      codigo: '84818011',
      descricao: 'TORNEIRAS E REGISTROS DE METAIS COMUNS',
    ),
    NcmCatalogoItem(
      codigo: '84818019',
      descricao: 'OUTRAS TORNEIRAS E VALVULAS',
    ),
    NcmCatalogoItem(
      codigo: '84818092',
      descricao: 'MISTURADORES E DUCHAS',
    ),
    NcmCatalogoItem(
      codigo: '84819010',
      descricao: 'PARTES DE TORNEIRAS E VALVULAS',
    ),

    // Tintas / vernizes / argamassas
    NcmCatalogoItem(
      codigo: '32081010',
      descricao: 'TINTAS A BASE DE POLIESTERES',
    ),
    NcmCatalogoItem(
      codigo: '32082010',
      descricao: 'TINTAS A BASE DE POLIMEROS ACRILICOS',
    ),
    NcmCatalogoItem(
      codigo: '32089010',
      descricao: 'OUTRAS TINTAS DISSOLVIDAS EM MEIO NAO AQUOSO',
    ),
    NcmCatalogoItem(
      codigo: '32091010',
      descricao: 'TINTAS A BASE DE POLIMEROS ACRILICOS (MEIO AQUOSO)',
    ),
    NcmCatalogoItem(
      codigo: '32099011',
      descricao: 'OUTRAS TINTAS EM MEIO AQUOSO',
    ),
    NcmCatalogoItem(
      codigo: '32100010',
      descricao: 'OUTRAS TINTAS E VERNIZES',
    ),
    NcmCatalogoItem(
      codigo: '32141010',
      descricao: 'MASTIQUE DE VIDRACEIRO',
    ),
    NcmCatalogoItem(
      codigo: '32149000',
      descricao: 'ARGAMASSAS E OUTROS MASTIQUES',
    ),

    // Eletrica
    NcmCatalogoItem(
      codigo: '85362000',
      descricao: 'DISJUNTORES',
    ),
    NcmCatalogoItem(
      codigo: '85365090',
      descricao: 'OUTROS INTERRUPTORES E COMUTADORES',
    ),
    NcmCatalogoItem(
      codigo: '85366910',
      descricao: 'TOMADAS DE CORRENTE',
    ),
    NcmCatalogoItem(
      codigo: '85369010',
      descricao: 'OUTROS APARELHOS PARA INTERRUPCAO/PROTECAO',
    ),
    NcmCatalogoItem(
      codigo: '85371010',
      descricao: 'QUADROS E PAINEIS DE COMANDO',
    ),
    NcmCatalogoItem(
      codigo: '85392200',
      descricao: 'LAMPADAS INCANDESCENTES',
    ),
    NcmCatalogoItem(
      codigo: '85395000',
      descricao: 'LAMPADAS E TUBOS DE LED',
    ),
    NcmCatalogoItem(
      codigo: '85442000',
      descricao: 'CABOS COAXIAIS',
    ),
    NcmCatalogoItem(
      codigo: '85444200',
      descricao: 'FIOS E CABOS COM CONECTORES',
    ),
    NcmCatalogoItem(
      codigo: '85444900',
      descricao: 'OUTROS FIOS E CABOS ELETRICOS',
    ),
    NcmCatalogoItem(
      codigo: '85446000',
      descricao: 'OUTROS CONDUTORES ELETRICOS PARA TENSAO > 1000V',
    ),

    // Colas / adesivos / silicone
    NcmCatalogoItem(
      codigo: '35061010',
      descricao: 'PRODUTOS ADEQUADOS PARA USO COMO COLAS',
    ),
    NcmCatalogoItem(
      codigo: '35069110',
      descricao: 'ADESIVOS A BASE DE POLIMEROS',
    ),
    NcmCatalogoItem(
      codigo: '39100011',
      descricao: 'SILICONES EM FORMAS PRIMARIAS (VEDACOES)',
    ),
  ];

  static NcmCatalogoItem? porCodigo(String? ncm) {
    final d = (ncm ?? '').replaceAll(RegExp(r'\D'), '');
    if (d.length != 8) return null;
    for (final item in itens) {
      if (item.codigo == d) return item;
    }
    return null;
  }

  static List<NcmCatalogoItem> buscar(String termo, {int limite = 80}) {
    final filtrados = itens.where((e) => e.corresponde(termo)).toList();
    if (filtrados.length <= limite) return filtrados;
    return filtrados.take(limite).toList();
  }
}
