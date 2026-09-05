/// Item extraido do XML da NF-e (nao persistido no ObjectBox).
class ItemNotaTemporario {
  const ItemNotaTemporario({
    required this.numeroItem,
    required this.codigo,
    required this.descricao,
    required this.unidadeComercial,
    required this.quantidadeComercial,
    required this.valorUnitarioComercial,
    this.unidadeTributavel = '',
    this.quantidadeTributavel = 0,
    this.valorUnitarioTributavel = 0,
    this.codigoBarras = '',
    this.ncm = '',
    this.cfop = '',
    this.icmsOrigem = '',
    this.icmsSituacaoTributaria = '',
    this.icmsBaseCalculo = 0,
    this.icmsAliquota = 0,
    this.icmsValor = 0,
    this.icmsBaseCalculoSt = 0,
    this.icmsAliquotaSt = 0,
    this.icmsValorSt = 0,
    this.ipiValor = 0,
    this.numeroLote = '',
    this.dataValidade,
  });

  final int numeroItem;
  final String codigo;
  final String descricao;
  final String unidadeComercial;
  final double quantidadeComercial;
  final double valorUnitarioComercial;

  /// Tags uTrib / qTrib / vUnTrib quando informadas no XML.
  final String unidadeTributavel;
  final double quantidadeTributavel;
  final double valorUnitarioTributavel;

  /// Fator qTrib/qCom quando uCom difere de uTrib (ex.: 1 CX = 12 UN).
  double get fatorComercialParaTributavel {
    if (quantidadeComercial <= 0 ||
        quantidadeTributavel <= 0 ||
        !quantidadeComercial.isFinite ||
        !quantidadeTributavel.isFinite) {
      return 0;
    }
    final uCom = unidadeComercial.trim();
    final uTrib = unidadeTributavel.trim();
    if (uCom.isEmpty || uTrib.isEmpty) return 0;
    if (uCom.toUpperCase() == uTrib.toUpperCase()) return 0;
    return quantidadeTributavel / quantidadeComercial;
  }

  /// cEAN / cEANTrib quando informado (sem "SEM GTIN").
  final String codigoBarras;
  final String ncm;

  /// Tributacao da compra (para espelhar na devolucao).
  final String cfop;
  final String icmsOrigem;
  final String icmsSituacaoTributaria;
  final double icmsBaseCalculo;
  final double icmsAliquota;
  final double icmsValor;
  final double icmsBaseCalculoSt;
  final double icmsAliquotaSt;
  final double icmsValorSt;
  final double ipiValor;

  /// Rastro NF-e (`prod/rastro/nLote`) quando informado.
  final String numeroLote;

  /// Rastro NF-e (`prod/rastro/dVal`) quando informado.
  final DateTime? dataValidade;

  ItemNotaTemporario copyWith({
    String? numeroLote,
    DateTime? dataValidade,
    bool limparDataValidade = false,
  }) {
    return ItemNotaTemporario(
      numeroItem: numeroItem,
      codigo: codigo,
      descricao: descricao,
      unidadeComercial: unidadeComercial,
      quantidadeComercial: quantidadeComercial,
      valorUnitarioComercial: valorUnitarioComercial,
      unidadeTributavel: unidadeTributavel,
      quantidadeTributavel: quantidadeTributavel,
      valorUnitarioTributavel: valorUnitarioTributavel,
      codigoBarras: codigoBarras,
      ncm: ncm,
      cfop: cfop,
      icmsOrigem: icmsOrigem,
      icmsSituacaoTributaria: icmsSituacaoTributaria,
      icmsBaseCalculo: icmsBaseCalculo,
      icmsAliquota: icmsAliquota,
      icmsValor: icmsValor,
      icmsBaseCalculoSt: icmsBaseCalculoSt,
      icmsAliquotaSt: icmsAliquotaSt,
      icmsValorSt: icmsValorSt,
      ipiValor: ipiValor,
      numeroLote: numeroLote ?? this.numeroLote,
      dataValidade:
          limparDataValidade ? null : (dataValidade ?? this.dataValidade),
    );
  }
}

/// Dados do emitente extraidos do XML.
class EmitenteNfeTemporario {
  const EmitenteNfeTemporario({
    required this.cnpj,
    required this.razaoSocial,
    this.nomeFantasia = '',
    this.inscricaoEstadual = '',
    this.logradouro = '',
    this.numero = '',
    this.complemento = '',
    this.bairro = '',
    this.municipio = '',
    this.codigoMunicipioIbge = '',
    this.uf = '',
    this.cep = '',
    this.telefone = '',
    this.email = '',
  });

  final String cnpj;
  final String razaoSocial;
  final String nomeFantasia;
  final String inscricaoEstadual;
  final String logradouro;
  final String numero;
  final String complemento;
  final String bairro;
  final String municipio;
  final String codigoMunicipioIbge;
  final String uf;
  final String cep;
  final String telefone;
  final String email;
}

/// Duplicata extraída de `<cobr><dup>` no XML da NF-e.
class NfeDuplicataXml {
  const NfeDuplicataXml({
    required this.numeroParcela,
    required this.dataVencimento,
    required this.valorParcela,
  });

  /// Conteúdo de `nDup` (ex.: `001/003` ou `001`).
  final String numeroParcela;

  /// Conteúdo de `dVenc` (apenas calendário, armazenado em UTC meia-noite).
  final DateTime dataVencimento;

  /// Conteúdo de `vDup`.
  final double valorParcela;
}

/// Resultado do parse da NF-e (antes da conferencia / persistencia).
class NfeXmlParseResult {
  const NfeXmlParseResult({
    required this.chaveAcesso,
    required this.numeroNota,
    required this.dataEmissao,
    required this.emitente,
    required this.itens,
    required this.duplicatas,
    required this.valorTotalNota,
  });

  final String chaveAcesso;
  final int numeroNota;
  final DateTime dataEmissao;
  final EmitenteNfeTemporario emitente;
  final List<ItemNotaTemporario> itens;

  /// Parcelas de `<cobr><dup>`. Vazia se não houver `cobr` ou nenhuma `dup` válida.
  final List<NfeDuplicataXml> duplicatas;

  /// Valor total da nota (`total/ICMSTot/vNF` ou soma dos itens como fallback).
  final double valorTotalNota;
}
