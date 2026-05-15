/// Item extraido do XML da NF-e (nao persistido no ObjectBox).
class ItemNotaTemporario {
  const ItemNotaTemporario({
    required this.numeroItem,
    required this.codigo,
    required this.descricao,
    required this.unidadeComercial,
    required this.quantidadeComercial,
    required this.valorUnitarioComercial,
    this.codigoBarras = '',
    this.ncm = '',
  });

  final int numeroItem;
  final String codigo;
  final String descricao;
  final String unidadeComercial;
  final double quantidadeComercial;
  final double valorUnitarioComercial;

  /// cEAN / cEANTrib quando informado (sem "SEM GTIN").
  final String codigoBarras;
  final String ncm;
}

/// Dados do emitente extraidos do XML.
class EmitenteNfeTemporario {
  const EmitenteNfeTemporario({
    required this.cnpj,
    required this.razaoSocial,
    this.nomeFantasia = '',
  });

  final String cnpj;
  final String razaoSocial;
  final String nomeFantasia;
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
