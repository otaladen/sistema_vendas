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
    int? estoque,
    int? estoqueReal,
    this.estoqueReservado = 0,
    required this.quantidadeMinima,
    required this.precoCusto,
    this.preco1 = 0,
    this.preco2 = 0,
    this.preco3 = 0,
    required this.precoVenda,
    DateTime? criadoEm,
  })  : estoqueReal = estoqueReal ?? estoque ?? 0,
        criadoEm = criadoEm ?? DateTime.now();

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
  int estoqueReal;
  int estoqueReservado;
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

  // Mantem compatibilidade com o codigo legado enquanto a migracao
  // para estoqueReal/estoqueReservado e finalizada.
  int get estoque => estoqueReal;
  set estoque(int value) => estoqueReal = value;
}
