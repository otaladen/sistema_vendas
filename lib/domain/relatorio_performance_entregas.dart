import 'entrega_nao_entregue.dart';
import 'entregas/cargas_entrega.dart';
import '../model/venda.dart';

/// Agregado de entregas / insucessos por motorista (ou veiculo).
class RelatorioPerformanceEntregaLinha {
  RelatorioPerformanceEntregaLinha({
    required this.chave,
    required this.nome,
    this.veiculo = '',
  });

  final String chave;
  final String nome;
  String veiculo;
  int entregues = 0;
  int insucessos = 0;
  int cargaVoltou = 0;
  int ausente = 0;
  int enderecoErrado = 0;
  int recusou = 0;
  int outros = 0;

  int get tentativas => entregues + insucessos;

  double get taxaSucesso =>
      tentativas == 0 ? 0 : entregues / tentativas;

  double get taxaSucessoPct => taxaSucesso * 100;
}

/// Performance operacional de carreto no periodo (data marcada ou data da venda).
abstract final class RelatorioPerformanceEntregas {
  RelatorioPerformanceEntregas._();

  static bool noPeriodo(Venda v, DateTime inicio, DateTime fim) =>
      _diaNoPeriodo(v.dataEntregaMarcada ?? v.data, inicio, fim);

  static bool _diaNoPeriodo(DateTime quando, DateTime inicio, DateTime fim) {
    final raw = quando.toLocal();
    final dia = DateTime(raw.year, raw.month, raw.day);
    final ini = DateTime(inicio.year, inicio.month, inicio.day);
    final fimDia = DateTime(fim.year, fim.month, fim.day);
    return !dia.isBefore(ini) && !dia.isAfter(fimDia);
  }

  static String nomeMotorista(Venda v) {
    final n = v.motoristaEntrega.trim();
    return n.isEmpty ? 'Sem motorista' : n;
  }

  static String nomeVeiculo(Venda v) {
    final n = v.caminhaoEntrega.trim();
    return n.isEmpty ? 'Sem veiculo' : n;
  }

  static List<RelatorioPerformanceEntregaLinha> agregar({
    required List<Venda> entregas,
    required DateTime inicio,
    required DateTime fim,
    required String dimensao,
  }) {
    final map = <String, RelatorioPerformanceEntregaLinha>{};
    RelatorioPerformanceEntregaLinha linha(String motorista, String veiculo) {
      final chave = dimensao == 'veiculo' ? veiculo : motorista;
      final cur = map.putIfAbsent(
        chave,
        () => RelatorioPerformanceEntregaLinha(
          chave: chave,
          nome: chave,
          veiculo: veiculo,
        ),
      );
      if (cur.veiculo == 'Sem veiculo' && veiculo != 'Sem veiculo') {
        cur.veiculo = veiculo;
      }
      return cur;
    }

    for (final v in entregas) {
      final cargas = CargasEntregaCodec.decode(v.cargasEntregaJson);
      if (cargas.isNotEmpty) {
        // Cada carga entregue e uma viagem, do motorista que a levou.
        for (final c in cargas.where((c) => c.entregue)) {
          final dia = c.entregueEm ?? c.data ?? v.dataEntregaMarcada ?? v.data;
          if (!_diaNoPeriodo(dia, inicio, fim)) continue;
          linha(
            c.motorista.isEmpty ? nomeMotorista(v) : c.motorista,
            c.veiculo.isEmpty ? nomeVeiculo(v) : c.veiculo,
          ).entregues++;
        }
        final s = v.statusEntrega.trim();
        if (s == 'entregue' || !noPeriodo(v, inicio, fim)) continue;
        if (s == 'entregue_complemento_pendente' || s == 'reagendada') {
          _aplicarStatus(linha(nomeMotorista(v), nomeVeiculo(v)), v);
        }
        continue;
      }
      if (!noPeriodo(v, inicio, fim)) continue;
      _aplicarStatus(linha(nomeMotorista(v), nomeVeiculo(v)), v);
    }
    final lista = map.values.toList()
      ..sort((a, b) {
        final c = b.tentativas.compareTo(a.tentativas);
        if (c != 0) return c;
        return a.nome.toLowerCase().compareTo(b.nome.toLowerCase());
      });
    return lista;
  }

  static void _aplicarStatus(RelatorioPerformanceEntregaLinha cur, Venda v) {
    final s = v.statusEntrega.trim();
    if (s == 'entregue' || s == 'entregue_complemento_pendente') {
      cur.entregues++;
      return;
    }
    if (s != 'reagendada') return;
    final resumo = EntregaInsucessoResumo.deVenda(
      statusEntrega: v.statusEntrega,
      observacaoEntrega: v.observacaoEntrega,
    );
    cur.insucessos++;
    if (resumo?.retornouParaLoja == true) cur.cargaVoltou++;
    final motivo = (resumo?.motivo ?? '').toLowerCase();
    if (motivo.contains('ausente')) {
      cur.ausente++;
    } else if (motivo.contains('endereco')) {
      cur.enderecoErrado++;
    } else if (motivo.contains('recusou') || motivo.contains('recusa')) {
      cur.recusou++;
    } else {
      cur.outros++;
    }
  }
}
