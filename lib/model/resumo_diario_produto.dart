import 'package:objectbox/objectbox.dart';

/// Um dia civil de um produto: vendas, devoluções e entradas já somadas.
///
/// A chave [chaveDia] (`produtoId|yyyy-MM-dd`) impede duas linhas para o mesmo
/// produto no mesmo dia. [data] é meia-noite UTC do dia civil local, para a
/// consulta por intervalo usar o índice.
@Entity()
class ResumoDiarioProduto {
  ResumoDiarioProduto({
    this.id = 0,
    required this.produtoId,
    required this.data,
    required this.chaveDia,
    this.quantidadeVendida = 0,
    this.valorTotalVendido = 0,
    this.quantidadeDevolvida = 0,
    this.quantidadeEntrada = 0,
  });

  @Id()
  int id;

  int produtoId;

  @Property(type: PropertyType.dateUtc)
  @Index()
  DateTime data;

  @Unique()
  @Index()
  String chaveDia;

  /// Quantidade armazenada vendida no dia (bruta, sem descontar devolução).
  int quantidadeVendida;

  double valorTotalVendido;

  /// Quantidade armazenada devolvida pelo cliente.
  int quantidadeDevolvida;

  /// Entrada de compra, estorno dessa entrada e ajuste manual positivo.
  int quantidadeEntrada;
}
