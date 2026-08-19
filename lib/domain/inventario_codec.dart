import '../domain/inventario_constantes.dart';
import '../model/item_inventario.dart';
import '../model/sessao_inventario.dart';

/// JSON da API LAN de inventario (PC1 ↔ terminais).
abstract final class InventarioCodec {
  InventarioCodec._();

  static Map<String, dynamic> sessaoParaMap(SessaoInventario s) => {
        'id': s.id,
        'nome': s.nome,
        'status': s.status,
        'statusRotulo': InventarioSessaoStatus.rotulo(s.status),
        'filtroCategoria': s.filtroCategoria,
        'filtroSubcategoria': s.filtroSubcategoria,
        'escopoTexto': s.escopoTexto,
        'contagemCega': s.contagemCega,
        'criadoPor': s.criadoPor,
        'criadoEm': s.criadoEm.toUtc().toIso8601String(),
        if (s.aplicadaEm != null)
          'aplicadaEm': s.aplicadaEm!.toUtc().toIso8601String(),
        'aplicadaPor': s.aplicadaPor,
        'totalItens': s.totalItens,
        'totalConferidos': s.totalConferidos,
        'totalDivergentes': s.totalDivergentes,
        'totalPendentes': s.totalPendentes,
        'valorSobras': s.valorSobras,
        'valorPerdas': s.valorPerdas,
        'observacao': s.observacao,
        'progressoTexto': s.progressoTexto,
        'aberta': s.aberta,
      };

  static SessaoInventario sessaoDeMap(Map<String, dynamic> m) {
    final s = SessaoInventario(
      id: (m['id'] as num?)?.toInt() ?? 0,
      nome: (m['nome'] ?? '').toString(),
      status: (m['status'] ?? InventarioSessaoStatus.aberta).toString(),
      filtroCategoria: (m['filtroCategoria'] ?? '').toString(),
      filtroSubcategoria: (m['filtroSubcategoria'] ?? '').toString(),
      contagemCega: m['contagemCega'] == true,
      criadoPor: (m['criadoPor'] ?? '').toString(),
      criadoEm: DateTime.tryParse((m['criadoEm'] ?? '').toString()) ??
          DateTime.now().toUtc(),
      aplicadaEm: DateTime.tryParse((m['aplicadaEm'] ?? '').toString()),
      aplicadaPor: (m['aplicadaPor'] ?? '').toString(),
      totalItens: (m['totalItens'] as num?)?.toInt() ?? 0,
      totalConferidos: (m['totalConferidos'] as num?)?.toInt() ?? 0,
      totalDivergentes: (m['totalDivergentes'] as num?)?.toInt() ?? 0,
      valorSobras: (m['valorSobras'] as num?)?.toDouble() ?? 0,
      valorPerdas: (m['valorPerdas'] as num?)?.toDouble() ?? 0,
      observacao: (m['observacao'] ?? '').toString(),
    );
    return s;
  }

  static Map<String, dynamic> itemParaMap(ItemInventario i) => {
        'id': i.id,
        'sessaoId': i.sessaoId,
        'produtoId': i.produtoId,
        'nome': i.nomeSnapshot,
        'nomeSnapshot': i.nomeSnapshot,
        'codigoInterno': i.codigoInterno,
        'codigoBarras': i.codigoBarras,
        'unidade': i.unidade,
        'categoria': i.categoria,
        'subcategoria': i.subcategoria,
        'permiteQuantidadeFracionada': i.permiteQuantidadeFracionada,
        'quantidadePorEmbalagem': i.quantidadePorEmbalagem,
        'embalagemMultiplica': i.embalagemMultiplica,
        'unidadeCompra': i.unidadeCompra,
        'controlaLoteValidade': i.controlaLoteValidade,
        'snapshotFisico': i.snapshotFisico,
        'snapshotLivre': i.snapshotLivre,
        'snapshotReservado': i.snapshotReservado,
        'quantidadeContada': i.quantidadeContada,
        'conferido': i.conferido,
        'estado': i.estado,
        'estadoRotulo': InventarioItemEstado.rotulo(i.estado),
        'conferidoPor': i.conferidoPor,
        if (i.conferidoEm != null)
          'conferidoEm': i.conferidoEm!.toUtc().toIso8601String(),
        'custoUnitario': i.custoUnitario,
        'aplicado': i.aplicado,
        'deltaArmazenado': i.deltaArmazenado,
      };

  static ItemInventario itemDeMap(Map<String, dynamic> m) {
    return ItemInventario(
      id: (m['id'] as num?)?.toInt() ?? 0,
      sessaoId: (m['sessaoId'] as num?)?.toInt() ?? 0,
      produtoId: (m['produtoId'] as num?)?.toInt() ?? 0,
      nomeSnapshot: (m['nomeSnapshot'] ?? m['nome'] ?? '').toString(),
      codigoInterno: (m['codigoInterno'] ?? '').toString(),
      codigoBarras: (m['codigoBarras'] ?? '').toString(),
      unidade: (m['unidade'] ?? 'UN').toString(),
      categoria: (m['categoria'] ?? '').toString(),
      subcategoria: (m['subcategoria'] ?? '').toString(),
      permiteQuantidadeFracionada: m['permiteQuantidadeFracionada'] == true,
      quantidadePorEmbalagem:
          (m['quantidadePorEmbalagem'] as num?)?.toDouble() ?? 1,
      embalagemMultiplica: m['embalagemMultiplica'] != false,
      unidadeCompra: (m['unidadeCompra'] ?? '').toString(),
      controlaLoteValidade: m['controlaLoteValidade'] == true,
      snapshotFisico: (m['snapshotFisico'] as num?)?.toInt() ?? 0,
      snapshotLivre: (m['snapshotLivre'] as num?)?.toInt() ?? 0,
      snapshotReservado: (m['snapshotReservado'] as num?)?.toInt() ?? 0,
      quantidadeContada: (m['quantidadeContada'] as num?)?.toInt() ?? 0,
      conferido: m['conferido'] == true,
      estado: (m['estado'] ?? InventarioItemEstado.pendente).toString(),
      conferidoPor: (m['conferidoPor'] ?? '').toString(),
      conferidoEm: DateTime.tryParse((m['conferidoEm'] ?? '').toString()),
      custoUnitario: (m['custoUnitario'] as num?)?.toDouble() ?? 0,
      aplicado: m['aplicado'] == true,
    );
  }
}

/// Resultado de [InventarioGateway.aplicarAjustes].
class InventarioAplicacaoResultado {
  const InventarioAplicacaoResultado({
    required this.sessao,
    required this.aplicados,
    required this.falhas,
  });

  final SessaoInventario sessao;
  final int aplicados;
  final List<InventarioAplicacaoFalha> falhas;

  bool get ok => falhas.isEmpty;

  Map<String, dynamic> toMap() => {
        'ok': ok,
        'aplicados': aplicados,
        'falhas': falhas.map((f) => f.toMap()).toList(),
        'sessao': InventarioCodec.sessaoParaMap(sessao),
      };

  factory InventarioAplicacaoResultado.fromMap(Map<String, dynamic> m) {
    final sessaoMap = m['sessao'];
    return InventarioAplicacaoResultado(
      sessao: sessaoMap is Map
          ? InventarioCodec.sessaoDeMap(Map<String, dynamic>.from(sessaoMap))
          : SessaoInventario(),
      aplicados: (m['aplicados'] as num?)?.toInt() ?? 0,
      falhas: (m['falhas'] is List)
          ? (m['falhas'] as List)
              .whereType<Map>()
              .map(
                (e) => InventarioAplicacaoFalha.fromMap(
                  Map<String, dynamic>.from(e),
                ),
              )
              .toList()
          : const [],
    );
  }
}

class InventarioAplicacaoFalha {
  const InventarioAplicacaoFalha({
    required this.itemId,
    required this.produtoId,
    required this.nome,
    required this.erro,
  });

  final int itemId;
  final int produtoId;
  final String nome;
  final String erro;

  Map<String, dynamic> toMap() => {
        'itemId': itemId,
        'produtoId': produtoId,
        'nome': nome,
        'erro': erro,
      };

  factory InventarioAplicacaoFalha.fromMap(Map<String, dynamic> m) =>
      InventarioAplicacaoFalha(
        itemId: (m['itemId'] as num?)?.toInt() ?? 0,
        produtoId: (m['produtoId'] as num?)?.toInt() ?? 0,
        nome: (m['nome'] ?? '').toString(),
        erro: (m['erro'] ?? '').toString(),
      );
}

class InventarioCategoriasInfo {
  const InventarioCategoriasInfo({
    required this.categorias,
    required this.subcategoriasPorCategoria,
    required this.totalAtivos,
  });

  final List<String> categorias;
  final Map<String, List<String>> subcategoriasPorCategoria;
  final int totalAtivos;

  Map<String, dynamic> toMap() => {
        'categorias': categorias,
        'subcategorias': subcategoriasPorCategoria,
        'totalAtivos': totalAtivos,
      };

  factory InventarioCategoriasInfo.fromMap(Map<String, dynamic> m) {
    final subRaw = m['subcategorias'];
    final sub = <String, List<String>>{};
    if (subRaw is Map) {
      for (final e in subRaw.entries) {
        final list = e.value;
        sub[e.key.toString()] = list is List
            ? list.map((x) => x.toString()).toList()
            : const [];
      }
    }
    final cats = m['categorias'];
    return InventarioCategoriasInfo(
      categorias: cats is List
          ? cats.map((e) => e.toString()).toList()
          : const [],
      subcategoriasPorCategoria: sub,
      totalAtivos: (m['totalAtivos'] as num?)?.toInt() ?? 0,
    );
  }
}
