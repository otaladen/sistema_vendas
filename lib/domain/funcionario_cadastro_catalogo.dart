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
