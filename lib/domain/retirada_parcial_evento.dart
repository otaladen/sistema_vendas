import 'dart:convert';

/// Documento formal de baixa de patio (retirada futura ou loja pre-saida).
///
/// Persistido em [HistoricoEntrega.statusAnterior] como JSON. Nao e editavel:
/// o repositorio so insere; sync recusa update/delete desses eventos.
class RetiradaParcialLinhaEvento {
  const RetiradaParcialLinhaEvento({
    required this.itemVendaId,
    required this.nomeProduto,
    required this.quantidade,
    required this.vendido,
    required this.jaRetiradaAntes,
    required this.quantidadeDevolvida,
  });

  final int itemVendaId;
  final String nomeProduto;
  final int quantidade;
  final int vendido;
  final int jaRetiradaAntes;
  final int quantidadeDevolvida;

  int get jaRetiradaDepois => jaRetiradaAntes + quantidade;

  Map<String, dynamic> toJson() => {
        'itemVendaId': itemVendaId,
        'nomeProduto': nomeProduto,
        'quantidade': quantidade,
        'vendido': vendido,
        'jaRetiradaAntes': jaRetiradaAntes,
        'quantidadeDevolvida': quantidadeDevolvida,
      };

  static RetiradaParcialLinhaEvento? tryParse(Object? raw) {
    if (raw is! Map) return null;
    final m = Map<String, dynamic>.from(raw);
    final q = (m['quantidade'] as num?)?.toInt() ?? 0;
    if (q <= 0) return null;
    return RetiradaParcialLinhaEvento(
      itemVendaId: (m['itemVendaId'] as num?)?.toInt() ?? 0,
      nomeProduto: (m['nomeProduto'] ?? '').toString(),
      quantidade: q,
      vendido: (m['vendido'] as num?)?.toInt() ?? 0,
      jaRetiradaAntes: (m['jaRetiradaAntes'] as num?)?.toInt() ?? 0,
      quantidadeDevolvida: (m['quantidadeDevolvida'] as num?)?.toInt() ?? 0,
    );
  }
}

class RetiradaParcialEvento {
  const RetiradaParcialEvento({
    required this.vendaId,
    required this.numeroOrcamento,
    required this.documento,
    required this.tipo,
    required this.usuario,
    required this.retiradoPor,
    required this.dataHora,
    required this.linhas,
  });

  static const int versao = 1;
  static const String tipoFutura = 'futura';
  static const String tipoLojaCarreto = 'loja_carreto';

  final int vendaId;
  final int numeroOrcamento;
  final String documento;
  final String tipo;
  final String usuario;
  final String retiradoPor;
  final DateTime dataHora;
  final List<RetiradaParcialLinhaEvento> linhas;

  String get textoHumano {
    final trecho = linhas
        .map((l) => '${l.nomeProduto} x${l.quantidade}')
        .join('; ');
    final base = trecho.isEmpty
        ? 'Retirada $tipo em $documento.'
        : 'Retirada ($documento): $trecho';
    final quem = retiradoPor.trim();
    if (quem.isEmpty) return base;
    return '$base Quem retirou: $quem.';
  }

  String encode() => jsonEncode({
        'v': versao,
        'vendaId': vendaId,
        'numeroOrcamento': numeroOrcamento,
        'documento': documento,
        'tipo': tipo,
        'usuario': usuario,
        'retiradoPor': retiradoPor,
        'dataHora': dataHora.toUtc().toIso8601String(),
        'linhas': linhas.map((l) => l.toJson()).toList(),
      });

  static RetiradaParcialEvento? tryParse(String raw) {
    final t = raw.trim();
    if (t.isEmpty || !t.startsWith('{')) return null;
    try {
      final decoded = jsonDecode(t);
      if (decoded is! Map) return null;
      final m = Map<String, dynamic>.from(decoded);
      final linhasRaw = m['linhas'];
      final linhas = <RetiradaParcialLinhaEvento>[];
      if (linhasRaw is List) {
        for (final e in linhasRaw) {
          final linha = RetiradaParcialLinhaEvento.tryParse(e);
          if (linha != null) linhas.add(linha);
        }
      }
      if (linhas.isEmpty) return null;
      return RetiradaParcialEvento(
        vendaId: (m['vendaId'] as num?)?.toInt() ?? 0,
        numeroOrcamento: (m['numeroOrcamento'] as num?)?.toInt() ?? 0,
        documento: (m['documento'] ?? '').toString(),
        tipo: (m['tipo'] ?? '').toString(),
        usuario: (m['usuario'] ?? '').toString(),
        retiradoPor: (m['retiradoPor'] ?? '').toString(),
        dataHora: DateTime.tryParse((m['dataHora'] ?? '').toString())
                ?.toUtc() ??
            DateTime.now().toUtc(),
        linhas: linhas,
      );
    } catch (_) {
      return null;
    }
  }
}
