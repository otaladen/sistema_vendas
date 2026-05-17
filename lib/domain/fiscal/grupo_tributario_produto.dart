/// Grupo tributario do produto (cadastro e regra de CFOP na venda).
enum GrupoTributarioProduto {
  tributado,
  isento,
  substituicaoTributaria,
}

extension GrupoTributarioProdutoExt on GrupoTributarioProduto {
  String get codigo {
    switch (this) {
      case GrupoTributarioProduto.tributado:
        return 'tributado';
      case GrupoTributarioProduto.isento:
        return 'isento';
      case GrupoTributarioProduto.substituicaoTributaria:
        return 'substituicao_tributaria';
    }
  }

  String get rotulo {
    switch (this) {
      case GrupoTributarioProduto.tributado:
        return 'Tributado';
      case GrupoTributarioProduto.isento:
        return 'Isento';
      case GrupoTributarioProduto.substituicaoTributaria:
        return 'Substituicao Tributaria';
    }
  }

  /// CFOP padrao para venda ao consumidor final dentro do estado (BA).
  /// Ajuste com o contador/API fiscal quando os dados oficiais chegarem.
  String get cfopVendaConsumidorFinalBahia {
    switch (this) {
      case GrupoTributarioProduto.substituicaoTributaria:
        return '5405';
      case GrupoTributarioProduto.isento:
      case GrupoTributarioProduto.tributado:
        return '5102';
    }
  }
}

GrupoTributarioProduto grupoTributarioProdutoDeString(String? valor) {
  switch ((valor ?? '').trim().toLowerCase()) {
    case 'isento':
      return GrupoTributarioProduto.isento;
    case 'substituicao_tributaria':
    case 'st':
    case 'substituicao tributaria':
      return GrupoTributarioProduto.substituicaoTributaria;
    default:
      return GrupoTributarioProduto.tributado;
  }
}

List<GrupoTributarioProduto> get todosGruposTributariosProduto =>
    GrupoTributarioProduto.values;
