import '../data/models/conta_pagar.dart';
import '../data/objectbox.dart';
import '../data/titulo_receber_repository.dart';
import '../data/venda_repository.dart';
import '../model/caixa_sessao.dart';
import 'dashboard_alertas.dart';

/// Snapshot consolidado AR + AP + caixa para o hub financeiro.
class FinanceiroResumoSnapshot {
  const FinanceiroResumoSnapshot({
    required this.totalAReceber,
    required this.aReceberVencido,
    required this.aReceberVenceHoje,
    required this.aReceberProximos7,
    required this.totalAPagarPendente,
    required this.aPagarAtrasado,
    required this.aPagarProximos7,
    required this.qtdTitulosReceberAbertos,
    required this.qtdContasPagarAbertas,
    required this.qtdContasPagarAtrasadas,
    this.saldoCaixaEstimado,
    this.caixaAberto = false,
    this.operadorCaixa = '',
  });

  final double totalAReceber;
  final double aReceberVencido;
  final double aReceberVenceHoje;
  final double aReceberProximos7;
  final double totalAPagarPendente;
  final double aPagarAtrasado;
  final double aPagarProximos7;
  final int qtdTitulosReceberAbertos;
  final int qtdContasPagarAbertas;
  final int qtdContasPagarAtrasadas;
  final double? saldoCaixaEstimado;
  final bool caixaAberto;
  final String operadorCaixa;

  double get saldoLiquidoProjetado {
    final caixa = saldoCaixaEstimado ?? 0;
    return caixa + totalAReceber - totalAPagarPendente;
  }

  bool get temAlertaCritico =>
      aReceberVencido > 0.01 || aPagarAtrasado > 0.01;

  bool get semMovimentacaoFinanceira =>
      totalAReceber < 0.01 &&
      totalAPagarPendente < 0.01 &&
      !caixaAberto;

  factory FinanceiroResumoSnapshot.fromMap(Map<String, dynamic> m) {
    return FinanceiroResumoSnapshot(
      totalAReceber: (m['totalAReceber'] as num?)?.toDouble() ?? 0,
      aReceberVencido: (m['aReceberVencido'] as num?)?.toDouble() ?? 0,
      aReceberVenceHoje: (m['aReceberVenceHoje'] as num?)?.toDouble() ?? 0,
      aReceberProximos7: (m['aReceberProximos7'] as num?)?.toDouble() ?? 0,
      totalAPagarPendente: (m['totalAPagarPendente'] as num?)?.toDouble() ?? 0,
      aPagarAtrasado: (m['aPagarAtrasado'] as num?)?.toDouble() ?? 0,
      aPagarProximos7: (m['aPagarProximos7'] as num?)?.toDouble() ?? 0,
      qtdTitulosReceberAbertos:
          (m['qtdTitulosReceberAbertos'] as num?)?.toInt() ?? 0,
      qtdContasPagarAbertas: (m['qtdContasPagarAbertas'] as num?)?.toInt() ?? 0,
      qtdContasPagarAtrasadas:
          (m['qtdContasPagarAtrasadas'] as num?)?.toInt() ?? 0,
      saldoCaixaEstimado: (m['saldoCaixaEstimado'] as num?)?.toDouble(),
      caixaAberto: m['caixaAberto'] == true,
      operadorCaixa: (m['operadorCaixa'] ?? '').toString(),
    );
  }
}

/// Agrega indicadores financeiros a partir dos dados existentes no ERP.
class FinanceiroResumoService {
  FinanceiroResumoService._();

  static FinanceiroResumoSnapshot montar({
    required VendaRepository vendaRepository,
    required ObjectBox objectBox,
    CaixaSessao? sessaoCaixaLocal,
  }) {
    vendaRepository.titulos.migrarTitulosLegadoSeNecessario();
    final titulos = vendaRepository.titulos.listarTodosAbertos();

    double soma(Iterable<TituloReceberResumoLinha> lista) =>
        lista.fold<double>(0, (s, l) => s + l.titulo.saldo);

    final vencidos = titulos.where(ContasReceberHelper.ehVencido);
    final venceHoje = titulos.where(ContasReceberHelper.ehVenceHoje);
    final prox7 = titulos.where(ContasReceberHelper.ehProximos7);

    final hoje = DateTime.now();
    final base = DateTime(hoje.year, hoje.month, hoje.day);

    var apPendente = 0.0;
    var apAtrasado = 0.0;
    var apProx7 = 0.0;
    var qtdAbertas = 0;
    var qtdAtrasadas = 0;

    for (final c in objectBox.contaPagarBox.getAll()) {
      if (c.status == ContaPagarStatus.pago) continue;
      final venc = DateTime(
        c.dataVencimento.year,
        c.dataVencimento.month,
        c.dataVencimento.day,
      );
      final valor = c.valorParcela;
      if (!valor.isFinite || valor <= 0) continue;
      qtdAbertas++;
      if (venc.isBefore(base) ||
          c.status == ContaPagarStatus.atrasado) {
        apAtrasado += valor;
        qtdAtrasadas++;
      } else {
        apPendente += valor;
        final diff = venc.difference(base).inDays;
        if (diff >= 0 && diff <= 7) {
          apProx7 += valor;
        }
      }
    }

    double? saldoCaixa;
    var caixaAberto = false;
    var operador = '';
    final sessao = sessaoCaixaLocal;
    if (sessao != null && sessao.aberto) {
      caixaAberto = true;
      operador = sessao.operador.trim();
      saldoCaixa = (sessao.fundoTroco + sessao.suprimentos - sessao.sangrias)
          .clamp(0, double.infinity);
    }

    return FinanceiroResumoSnapshot(
      totalAReceber: soma(titulos),
      aReceberVencido: soma(vencidos),
      aReceberVenceHoje: soma(venceHoje),
      aReceberProximos7: soma(prox7),
      totalAPagarPendente: apPendente + apAtrasado,
      aPagarAtrasado: apAtrasado,
      aPagarProximos7: apProx7,
      qtdTitulosReceberAbertos: titulos.length,
      qtdContasPagarAbertas: qtdAbertas,
      qtdContasPagarAtrasadas: qtdAtrasadas,
      saldoCaixaEstimado: saldoCaixa,
      caixaAberto: caixaAberto,
      operadorCaixa: operador,
    );
  }
}
