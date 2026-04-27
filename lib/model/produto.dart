import 'package:objectbox/objectbox.dart';

@Entity()
class Produto {
  Produto({
    this.id = 0,
    required this.codigoInterno,
    required this.nome,
    this.descricao = '',
    this.unidade = 'UN',
    this.categoria = '',
    this.subcategoria = '',
    this.marca = '',
    this.fornecedor = '',
    this.fabricante = '',
    this.codigoBarras = '',
    this.fotoPath = '',
    this.localizacao = '',
    this.ncm = '',
    required this.estoque,
    required this.quantidadeMinima,
    required this.precoCusto,
    this.preco1 = 0,
    this.preco2 = 0,
    this.preco3 = 0,
    required this.precoVenda,
    DateTime? criadoEm,
  }) : criadoEm = criadoEm ?? DateTime.now();

  @Id()
  int id;

  String codigoInterno;
  String nome;
  String descricao;
  String unidade;
  String categoria;
  String subcategoria;
  String marca;
  String fornecedor;
  String fabricante;
  String codigoBarras;
  String fotoPath;
  String localizacao;
  String ncm;
  int estoque;
  int quantidadeMinima;
  double precoCusto;
  double preco1;
  double preco2;
  double preco3;
  double precoVenda;
  double get lucroValor => precoVenda - precoCusto;
  double get markupPercentual {
    if (precoCusto <= 0) {
      return 0;
    }
    return ((precoVenda - precoCusto) / precoCusto) * 100;
  }
  double get margemLucroPercentual {
    if (precoVenda <= 0) {
      return 0;
    }
    return ((precoVenda - precoCusto) / precoVenda) * 100;
  }

  @Property(type: PropertyType.dateUtc)
  DateTime criadoEm;
}
