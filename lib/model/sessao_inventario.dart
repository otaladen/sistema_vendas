import 'package:objectbox/objectbox.dart';

import '../domain/inventario_constantes.dart';

/// Sessao de balanco/inventario com snapshot e progresso persistido.
@Entity()
class SessaoInventario {
  SessaoInventario({
    this.id = 0,
    this.nome = '',
    this.status = InventarioSessaoStatus.aberta,
    this.filtroCategoria = '',
    this.filtroSubcategoria = '',
    this.contagemCega = false,
    this.criadoPor = '',
    DateTime? criadoEm,
    this.aplicadaEm,
    this.aplicadaPor = '',
    this.totalItens = 0,
    this.totalConferidos = 0,
    this.totalDivergentes = 0,
    this.valorSobras = 0,
    this.valorPerdas = 0,
    this.observacao = '',
  }) : criadoEm = criadoEm ?? DateTime.now().toUtc();

  @Id(assignable: true)
  int id;

  String nome;

  @Index()
  String status;

  String filtroCategoria;
  String filtroSubcategoria;

  /// Se true, a UI de contagem oculta o saldo do sistema.
  bool contagemCega;

  String criadoPor;

  @Property(type: PropertyType.dateUtc)
  DateTime criadoEm;

  @Property(type: PropertyType.dateUtc)
  DateTime? aplicadaEm;

  String aplicadaPor;

  int totalItens;
  int totalConferidos;
  int totalDivergentes;
  double valorSobras;
  double valorPerdas;
  String observacao;

  int get totalPendentes {
    final n = totalItens - totalConferidos;
    return n < 0 ? 0 : n;
  }

  bool get aberta => status == InventarioSessaoStatus.aberta;

  String get progressoTexto {
    if (totalItens <= 0) return 'Nenhum item';
    return '$totalConferidos de $totalItens itens contados';
  }

  double get progressoFracao {
    if (totalItens <= 0) return 0;
    return (totalConferidos / totalItens).clamp(0.0, 1.0);
  }

  String get escopoTexto {
    final cat = filtroCategoria.trim();
    final sub = filtroSubcategoria.trim();
    if (cat.isEmpty) return 'Loja inteira';
    if (sub.isEmpty) return cat;
    return '$cat / $sub';
  }
}
