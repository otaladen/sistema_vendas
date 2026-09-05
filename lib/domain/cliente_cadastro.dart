/// Constantes e rotulos do cadastro de clientes (varejo / material de construcao).
class ClienteCadastro {
  ClienteCadastro._();

  static const segmentos = [
    ('consumidor', 'Consumidor final'),
    ('construtor', 'Construtor / obra'),
    ('revenda', 'Revenda / lojista'),
    ('governo', 'Governo / orgao'),
  ];

  static const categoriasComerciais = ['A', 'B', 'C'];

  static const tabelasPreco = [
    ('preco1', 'Preco 1'),
    ('preco2', 'Preco 2'),
    ('preco3', 'Preco 3'),
  ];

  static const indicadoresIe = [
    ('contribuinte', 'Contribuinte ICMS'),
    ('isento', 'Isento'),
    ('nao_contribuinte', 'Nao contribuinte'),
  ];

  static const origensCadastro = [
    ('balcao', 'Balcao / loja'),
    ('indicacao', 'Indicacao'),
    ('telefone', 'Telefone / WhatsApp'),
    ('obra', 'Visita em obra'),
    ('outro', 'Outro'),
  ];

  static const tiposEndereco = [
    ('principal', 'Principal / sede'),
    ('obra', 'Obra'),
    ('entrega', 'Entrega (carreto)'),
    ('cobranca', 'Cobranca'),
  ];

  static String rotuloSegmento(String? codigo) {
    for (final item in segmentos) {
      if (item.$1 == codigo) return item.$2;
    }
    return codigo?.trim().isNotEmpty == true ? codigo!.trim() : 'Nao informado';
  }

  static String rotuloTabelaPreco(String? codigo) {
    for (final item in tabelasPreco) {
      if (item.$1 == codigo) return item.$2;
    }
    return 'Preco 1';
  }

  static String rotuloTipoEndereco(String? codigo) {
    for (final item in tiposEndereco) {
      if (item.$1 == codigo) return item.$2;
    }
    return codigo?.trim().isNotEmpty == true ? codigo!.trim() : 'Principal';
  }

  static String normalizarTabelaPreco(String? valor) {
    final v = (valor ?? '').trim().toLowerCase();
    if (v == 'preco2' || v == 'preco3') return v;
    return 'preco1';
  }

  static String normalizarTipoEndereco(String? valor) {
    final v = (valor ?? '').trim().toLowerCase();
    for (final item in tiposEndereco) {
      if (item.$1 == v) return v;
    }
    return 'principal';
  }
}
