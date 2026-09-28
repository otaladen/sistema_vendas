import 'dart:convert';

/// Quantidade de um produto que segue numa carga (unidade de venda).
class LinhaCargaEntrega {
  const LinhaCargaEntrega({
    required this.produtoId,
    required this.nomeProduto,
    required this.quantidade,
  });

  final int produtoId;
  final String nomeProduto;
  final double quantidade;

  Map<String, dynamic> toJson() => {
        'produtoId': produtoId,
        'nomeProduto': nomeProduto,
        'quantidade': quantidade,
      };

  static LinhaCargaEntrega? tryParse(Object? raw) {
    if (raw is! Map) return null;
    final m = Map<String, dynamic>.from(raw);
    final produtoId = (m['produtoId'] as num?)?.toInt() ?? 0;
    final q = (m['quantidade'] as num?)?.toDouble() ?? 0;
    if (produtoId <= 0 || q <= 0) return null;
    return LinhaCargaEntrega(
      produtoId: produtoId,
      nomeProduto: (m['nomeProduto'] ?? '').toString(),
      quantidade: q,
    );
  }
}

/// Uma viagem (carreto) do plano de entrega da venda.
class CargaEntrega {
  const CargaEntrega({
    required this.numero,
    required this.data,
    this.janela = 'nao_definida',
    this.status = statusPendente,
    this.entregueEm,
    this.linhas = const [],
    this.recebidoPor = '',
    this.podFotoPath = '',
    this.podFotoPathServidor = '',
    this.podRegistradoPor = '',
    this.motorista = '',
    this.veiculo = '',
  });

  static const String statusPendente = 'pendente';
  static const String statusEntregue = 'entregue';

  final int numero;

  /// Dia local da viagem (hora ignorada).
  final DateTime? data;
  final String janela;
  final String status;
  final DateTime? entregueEm;
  final List<LinhaCargaEntrega> linhas;

  /// Comprovante desta viagem (a venda so guarda o da carga atual).
  final String recebidoPor;
  final String podFotoPath;
  final String podFotoPathServidor;
  final String podRegistradoPor;

  /// Quem levou esta viagem (o motorista da venda pode mudar entre cargas).
  final String motorista;
  final String veiculo;

  bool get entregue => status == statusEntregue;
  bool get pendente => !entregue;

  double quantidadeDoProduto(int produtoId) {
    var s = 0.0;
    for (final l in linhas) {
      if (l.produtoId == produtoId) s += l.quantidade;
    }
    return s;
  }

  CargaEntrega copyWith({
    int? numero,
    DateTime? data,
    bool limparData = false,
    String? janela,
    String? status,
    DateTime? entregueEm,
    List<LinhaCargaEntrega>? linhas,
    String? recebidoPor,
    String? podFotoPath,
    String? podFotoPathServidor,
    String? podRegistradoPor,
    String? motorista,
    String? veiculo,
  }) {
    return CargaEntrega(
      numero: numero ?? this.numero,
      data: limparData ? null : (data ?? this.data),
      janela: janela ?? this.janela,
      status: status ?? this.status,
      entregueEm: entregueEm ?? this.entregueEm,
      linhas: linhas ?? this.linhas,
      recebidoPor: recebidoPor ?? this.recebidoPor,
      podFotoPath: podFotoPath ?? this.podFotoPath,
      podFotoPathServidor: podFotoPathServidor ?? this.podFotoPathServidor,
      podRegistradoPor: podRegistradoPor ?? this.podRegistradoPor,
      motorista: motorista ?? this.motorista,
      veiculo: veiculo ?? this.veiculo,
    );
  }

  Map<String, dynamic> toJson() {
    final d = data;
    return {
      'numero': numero,
      'data': d == null
          ? null
          : CargasEntregaHelper.chaveDia(d),
      'janela': janela,
      'status': status,
      'entregueEm': entregueEm?.toUtc().toIso8601String(),
      'linhas': linhas.map((l) => l.toJson()).toList(),
      if (recebidoPor.isNotEmpty) 'recebidoPor': recebidoPor,
      if (podFotoPath.isNotEmpty) 'podFotoPath': podFotoPath,
      if (podFotoPathServidor.isNotEmpty)
        'podFotoPathServidor': podFotoPathServidor,
      if (podRegistradoPor.isNotEmpty) 'podRegistradoPor': podRegistradoPor,
      if (motorista.isNotEmpty) 'motorista': motorista,
      if (veiculo.isNotEmpty) 'veiculo': veiculo,
    };
  }

  static CargaEntrega? tryParse(Object? raw) {
    if (raw is! Map) return null;
    final m = Map<String, dynamic>.from(raw);
    final linhas = <LinhaCargaEntrega>[];
    final linhasRaw = m['linhas'];
    if (linhasRaw is List) {
      for (final e in linhasRaw) {
        final l = LinhaCargaEntrega.tryParse(e);
        if (l != null) linhas.add(l);
      }
    }
    final status = (m['status'] ?? '').toString() == statusEntregue
        ? statusEntregue
        : statusPendente;
    return CargaEntrega(
      numero: (m['numero'] as num?)?.toInt() ?? 0,
      data: CargasEntregaHelper.parseDia((m['data'] ?? '').toString()),
      janela: (m['janela'] ?? 'nao_definida').toString(),
      status: status,
      entregueEm: DateTime.tryParse((m['entregueEm'] ?? '').toString()),
      linhas: linhas,
      recebidoPor: (m['recebidoPor'] ?? '').toString(),
      podFotoPath: (m['podFotoPath'] ?? '').toString(),
      podFotoPathServidor: (m['podFotoPathServidor'] ?? '').toString(),
      podRegistradoPor: (m['podRegistradoPor'] ?? '').toString(),
      motorista: (m['motorista'] ?? '').toString(),
      veiculo: (m['veiculo'] ?? '').toString(),
    );
  }
}

/// JSON em `Venda.cargasEntregaJson`.
abstract final class CargasEntregaCodec {
  CargasEntregaCodec._();

  static String encode(List<CargaEntrega> cargas) {
    if (cargas.length < 2) return '';
    return jsonEncode(cargas.map((c) => c.toJson()).toList());
  }

  /// Menos de 2 cargas validas = plano vazio (venda de uma viagem so).
  static List<CargaEntrega> decode(String raw) {
    final t = raw.trim();
    if (t.isEmpty || !t.startsWith('[')) return const [];
    try {
      final decoded = jsonDecode(t);
      if (decoded is! List) return const [];
      final out = <CargaEntrega>[];
      for (final e in decoded) {
        final c = CargaEntrega.tryParse(e);
        if (c != null) out.add(c);
      }
      if (out.length < 2) return const [];
      out.sort((a, b) => a.numero.compareTo(b.numero));
      return out;
    } catch (_) {
      return const [];
    }
  }
}

/// Produto de carreto a distribuir entre as cargas (total da venda).
class ProdutoCarretoTotal {
  const ProdutoCarretoTotal({
    required this.produtoId,
    required this.nomeProduto,
    required this.quantidade,
    this.unidade = '',
    this.fracionado = false,
  });

  final int produtoId;
  final String nomeProduto;
  final double quantidade;
  final String unidade;

  /// Aceita casas decimais (m3, kg...). Falso = somente inteiros.
  final bool fracionado;
}

abstract final class CargasEntregaHelper {
  CargasEntregaHelper._();

  static const double tolerancia = 0.0005;
  static const int maximoCargas = 6;

  static DateTime soDia(DateTime d) {
    final l = d.toLocal();
    return DateTime(l.year, l.month, l.day);
  }

  static String chaveDia(DateTime d) {
    final l = soDia(d);
    final m = l.month.toString().padLeft(2, '0');
    final day = l.day.toString().padLeft(2, '0');
    return '${l.year}-$m-$day';
  }

  static DateTime? parseDia(String raw) {
    final partes = raw.trim().split('-');
    if (partes.length != 3) return null;
    final y = int.tryParse(partes[0]);
    final m = int.tryParse(partes[1]);
    final d = int.tryParse(partes[2]);
    if (y == null || m == null || d == null) return null;
    return DateTime(y, m, d);
  }

  static bool temPlano(String cargasEntregaJson) =>
      CargasEntregaCodec.decode(cargasEntregaJson).isNotEmpty;

  /// Primeira carga ainda nao entregue (ordem do plano).
  static CargaEntrega? cargaAtual(List<CargaEntrega> cargas) {
    for (final c in cargas) {
      if (c.pendente) return c;
    }
    return null;
  }

  /// "Carga 2/3". Null quando a venda nao tem plano de cargas.
  static String? rotuloCargaAtual(List<CargaEntrega> cargas) {
    if (cargas.length < 2) return null;
    final atual = cargaAtual(cargas);
    if (atual == null) return 'Cargas ${cargas.length}/${cargas.length}';
    return 'Carga ${atual.numero}/${cargas.length}';
  }

  /// "Entrega parcial (1/2)" enquanto houver carga pendente apos a primeira.
  static String? rotuloProgresso(List<CargaEntrega> cargas) {
    if (cargas.length < 2) return null;
    final entregues = cargas.where((c) => c.entregue).length;
    if (entregues == 0) return null;
    if (entregues >= cargas.length) return 'Entregue';
    return 'Entrega parcial ($entregues/${cargas.length})';
  }

  static double arredondar(double v) =>
      double.parse(v.toStringAsFixed(3));

  /// Quantidade que sobra para a carga 1 depois das demais.
  static double saldoPrimeiraCarga(
    ProdutoCarretoTotal produto,
    List<CargaEntrega> cargas,
  ) {
    var outras = 0.0;
    for (final c in cargas.skip(1)) {
      outras += c.quantidadeDoProduto(produto.produtoId);
    }
    return arredondar(produto.quantidade - outras);
  }

  /// Ajusta a carga 1 para receber o saldo de cada produto (total - demais).
  static List<CargaEntrega> recalcularPrimeiraCarga(
    List<ProdutoCarretoTotal> produtos,
    List<CargaEntrega> cargas,
  ) {
    if (cargas.isEmpty) return cargas;
    final linhas = <LinhaCargaEntrega>[];
    for (final p in produtos) {
      final saldo = saldoPrimeiraCarga(p, cargas);
      if (saldo > tolerancia) {
        linhas.add(
          LinhaCargaEntrega(
            produtoId: p.produtoId,
            nomeProduto: p.nomeProduto,
            quantidade: saldo,
          ),
        );
      }
    }
    return [cargas.first.copyWith(linhas: linhas), ...cargas.skip(1)];
  }

  static List<CargaEntrega> renumerar(List<CargaEntrega> cargas) {
    return [
      for (var i = 0; i < cargas.length; i++) cargas[i].copyWith(numero: i + 1),
    ];
  }

  /// Totais de carreto agregados por produto.
  static Map<int, double> totaisPorProduto(
    Iterable<ProdutoCarretoTotal> produtos,
  ) {
    final out = <int, double>{};
    for (final p in produtos) {
      out[p.produtoId] = (out[p.produtoId] ?? 0) + p.quantidade;
    }
    return out;
  }

  /// Null = plano valido. Senao, mensagem para o vendedor.
  static String? validarPlano(
    List<CargaEntrega> cargas,
    List<ProdutoCarretoTotal> produtos,
  ) {
    if (cargas.length < 2) {
      return 'Informe pelo menos duas cargas.';
    }
    if (cargas.length > maximoCargas) {
      return 'Maximo de $maximoCargas cargas por venda.';
    }
    DateTime? anterior;
    for (final c in cargas) {
      final d = c.data;
      if (d == null) return 'Defina a data da carga ${c.numero}.';
      final dia = soDia(d);
      if (anterior != null && dia.isBefore(anterior)) {
        return 'A carga ${c.numero} nao pode ser antes da carga '
            '${c.numero - 1}.';
      }
      anterior = dia;
      final temQuantidade = c.linhas.any((l) => l.quantidade > tolerancia);
      if (!temQuantidade) {
        return 'A carga ${c.numero} esta vazia. Coloque algum produto '
            'ou remova a carga.';
      }
      for (final l in c.linhas) {
        if (l.quantidade < -tolerancia) {
          return 'Quantidade negativa em "${l.nomeProduto}" '
              '(carga ${c.numero}).';
        }
      }
    }
    final totais = totaisPorProduto(produtos);
    final nomes = {for (final p in produtos) p.produtoId: p.nomeProduto};
    final distribuido = <int, double>{};
    for (final c in cargas) {
      for (final l in c.linhas) {
        if (!totais.containsKey(l.produtoId)) {
          return '"${l.nomeProduto}" nao esta mais no carreto desta venda. '
              'Refaca a divisao das cargas.';
        }
        distribuido[l.produtoId] =
            (distribuido[l.produtoId] ?? 0) + l.quantidade;
      }
    }
    for (final e in totais.entries) {
      final d = distribuido[e.key] ?? 0;
      if ((d - e.value).abs() > tolerancia) {
        final nome = nomes[e.key] ?? 'Produto';
        return d > e.value
            ? '"$nome": as cargas somam mais que o vendido. '
                'Refaca a divisao das cargas.'
            : '"$nome": falta distribuir ${arredondar(e.value - d)} '
                'entre as cargas.';
      }
    }
    return null;
  }

  /// Reparte cada carga pelas linhas de carreto da venda. Mesmo produto em
  /// varias linhas: as cargas enchem as linhas na ordem, sem sobrepor.
  ///
  /// Retorno na ordem de [cargas]: itemVendaId -> quantidade (unidade de venda).
  static List<Map<int, double>> alocarPorLinha({
    required List<CargaEntrega> cargas,
    required List<LinhaVendaCarreto> linhas,
  }) {
    final livre = {for (final l in linhas) l.itemVendaId: l.quantidade};
    final out = <Map<int, double>>[];
    for (final c in cargas) {
      final m = <int, double>{};
      for (final lc in c.linhas) {
        var resta = lc.quantidade;
        for (final lv in linhas) {
          if (resta <= tolerancia) break;
          if (lv.produtoId != lc.produtoId) continue;
          final disp = livre[lv.itemVendaId] ?? 0;
          if (disp <= tolerancia) continue;
          final q = resta < disp ? resta : disp;
          livre[lv.itemVendaId] = disp - q;
          resta -= q;
          m[lv.itemVendaId] = (m[lv.itemVendaId] ?? 0) + q;
        }
      }
      out.add(m);
    }
    return out;
  }
}

/// Linha de carreto gravada na venda (ordem das linhas importa).
class LinhaVendaCarreto {
  const LinhaVendaCarreto({
    required this.itemVendaId,
    required this.produtoId,
    required this.quantidade,
  });

  final int itemVendaId;
  final int produtoId;

  /// Quantidade vendida na unidade de venda.
  final double quantidade;
}
