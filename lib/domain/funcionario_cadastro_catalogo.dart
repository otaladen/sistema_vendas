/// Setores e funcoes padrao para cadastro de funcionarios (material de construcao).
class FuncionarioCadastroCatalogo {
  FuncionarioCadastroCatalogo._();

  static const String funcaoOutro = 'outro';

  static const Map<String, String> setores = {
    'balcao': 'Balcao / vendas',
    'caixa': 'Caixa',
    'expedicao': 'Expedicao / separacao',
    'patio': 'Patio / carga e descarga',
    'motorista': 'Motorista / entregas',
    'compras': 'Compras / recebimento NF',
    'administrativo': 'Administrativo / financeiro',
    'manutencao': 'Manutencao / servicos',
    'outro': 'Outro',
  };

  static const Map<String, String> funcoes = {
    'vendedor': 'Vendedor(a)',
    'caixa': 'Operador(a) de caixa',
    'conferente': 'Conferente',
    'estoquista': 'Estoquista',
    'motorista': 'Motorista',
    'ajudante': 'Ajudante de entrega',
    'comprador': 'Comprador(a)',
    'gerente': 'Gerente / supervisor',
    'aux_admin': 'Auxiliar administrativo',
    'outro': 'Outro (informar)',
  };

  static const Map<String, String> motivosDemissao = {
    'pedido': 'Pedido de demissao',
    'sem_justa': 'Sem justa causa',
    'justa_causa': 'Justa causa',
    'fim_contrato': 'Fim de contrato / experiencia',
    'aposentadoria': 'Aposentadoria',
    'outro': 'Outro',
  };

  static const Map<String, String> tiposVinculo = {
    'clt': 'CLT',
    'pj': 'PJ / prestador',
    'temporario': 'Temporario',
    'aprendiz': 'Aprendiz / estagiario',
  };

  static const Map<String, String> categoriasCnh = {
    '': 'Nao informada',
    'A': 'A — moto',
    'B': 'B — carro',
    'AB': 'AB — moto + carro',
    'C': 'C — caminhao',
    'D': 'D — onibus / van',
    'E': 'E — carreta',
  };

  static const Map<String, String> tamanhosUniforme = {
    '': 'Nao informado',
    'PP': 'PP',
    'P': 'P',
    'M': 'M',
    'G': 'G',
    'GG': 'GG',
    'XG': 'XG',
    'XXG': 'XXG',
    'calca_38': 'Calca 38',
    'calca_40': 'Calca 40',
    'calca_42': 'Calca 42',
    'calca_44': 'Calca 44',
    'calca_46': 'Calca 46',
    'calca_48': 'Calca 48',
    'bota_38': 'Bota 38',
    'bota_40': 'Bota 40',
    'bota_42': 'Bota 42',
    'bota_44': 'Bota 44',
  };

  static List<String> get idsTiposVinculo => tiposVinculo.keys.toList();

  static List<String> get idsCategoriasCnh => categoriasCnh.keys.toList();

  static List<String> get idsTamanhosUniforme => tamanhosUniforme.keys.toList();

  static String rotuloTipoVinculo(String id) =>
      tiposVinculo[id.trim().isEmpty ? 'clt' : id] ?? id;

  static String rotuloCategoriaCnh(String id) =>
      categoriasCnh[id] ?? (id.isEmpty ? 'Nao informada' : id);

  static String rotuloTamanhoUniforme(String id) =>
      tamanhosUniforme[id] ?? (id.isEmpty ? 'Nao informado' : id);

  static List<String> get idsSetores => setores.keys.toList();

  static List<String> get idsFuncoes => funcoes.keys.toList();

  static List<String> get idsMotivosDemissao => motivosDemissao.keys.toList();

  static String rotuloSetor(String id) =>
      setores[id.trim().isEmpty ? 'outro' : id] ?? id;

  static String rotuloFuncao(String id, {String outroTexto = ''}) {
    if (id == funcaoOutro || id == 'outro') {
      final t = outroTexto.trim();
      return t.isEmpty ? 'Outro' : t;
    }
    return funcoes[id] ?? (outroTexto.trim().isEmpty ? id : outroTexto.trim());
  }

  static String rotuloMotivoDemissao(String id, {String outroTexto = ''}) {
    if (id == 'outro') {
      final t = outroTexto.trim();
      return t.isEmpty ? 'Outro' : t;
    }
    return motivosDemissao[id] ?? id;
  }

  /// Legado: registros antigos so tinham [cargo] texto livre.
  static ({String setor, String funcao, String funcaoOutro}) migrarCargoLegado(
    String cargo,
    String setorAtual,
    String funcaoAtual,
  ) {
    if (setorAtual.isNotEmpty || funcaoAtual.isNotEmpty) {
      return (setor: setorAtual, funcao: funcaoAtual, funcaoOutro: '');
    }
    final c = cargo.trim();
    if (c.isEmpty) {
      return (setor: 'balcao', funcao: 'vendedor', funcaoOutro: '');
    }
    return (setor: 'outro', funcao: funcaoOutro, funcaoOutro: c);
  }

  static String resumoSetorFuncao({
    required String setor,
    required String funcao,
    String funcaoOutro = '',
    String cargoLegado = '',
  }) {
    final s = rotuloSetor(setor);
    final f = rotuloFuncao(funcao, outroTexto: funcaoOutro);
    if (setor.isEmpty && funcao.isEmpty && cargoLegado.isNotEmpty) {
      return cargoLegado;
    }
    if (funcao.isEmpty) return s;
    return '$s · $f';
  }
}
