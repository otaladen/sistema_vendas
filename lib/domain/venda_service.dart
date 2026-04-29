import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../data/venda_repository.dart';
import '../model/venda.dart';

class ResumoFinanceiroPeriodo {
  ResumoFinanceiroPeriodo({
    required this.quantidadeVendas,
    required this.faturamento,
    required this.custo,
    required this.lucro,
  });

  final int quantidadeVendas;
  final double faturamento;
  final double custo;
  final double lucro;
}

class HistoricoVendaDetalhado {
  HistoricoVendaDetalhado({required this.venda, required this.descricaoItens});

  final Venda venda;
  final String descricaoItens;
}

class VendaService {
  VendaService(this._vendaRepository);

  final VendaRepository _vendaRepository;

  String gerarSenhaDoDia({DateTime? dataBase}) {
    final data = (dataBase ?? DateTime.now()).toLocal();
    const fatorFixo = 37;
    final senhaNumero = ((data.day * 100) + (data.month * fatorFixo)) % 10000;
    return senhaNumero.toString().padLeft(4, '0');
  }

  void solicitarRetiradaFutura({
    required int vendaId,
    required String senhaDoDiaInformada,
  }) {
    final senhaEsperada = gerarSenhaDoDia();
    if (senhaDoDiaInformada != senhaEsperada) {
      throw StateError('Senha do dia invalida.');
    }
    _vendaRepository.marcarEntregaComoPendente(vendaId);
  }

  int registrarVenda(List<ItemVendaInput> itens) {
    return _vendaRepository.registrarVenda(itens);
  }

  int registrarOrcamento(
    List<ItemVendaInput> itens, {
    required DadosPagamentoOrcamento pagamento,
    DadosEntregaOrcamento? entrega,
    int? clienteId,
    int? vendedorId,
  }) {
    return _vendaRepository.registrarOrcamento(
      itens,
      pagamento: pagamento,
      entrega:
          entrega ??
          DadosEntregaOrcamento(tipoEntrega: 'retirada', valorFrete: 0),
      clienteId: clienteId,
      vendedorId: vendedorId,
    );
  }

  void converterOrcamentoParaVenda(int vendaId) {
    _vendaRepository.converterOrcamentoParaVenda(vendaId);
  }

  List<Venda> listarOrcamentosPendentes() {
    return _vendaRepository.listarOrcamentosPendentes();
  }

  void cancelarVenda(int vendaId) {
    _vendaRepository.cancelarVenda(vendaId);
  }

  List<HistoricoVendaDetalhado> listarHistoricoDetalhado(
    PeriodoFiltro periodo,
  ) {
    final vendas = _vendaRepository.listarPorPeriodo(periodo);
    return vendas.map((venda) {
      final descricaoItens = venda.itens
          .map(
            (item) =>
                '${item.nomeProduto} x${item.quantidade} = ${item.subtotal.toStringAsFixed(2)}',
          )
          .join(' | ');
      return HistoricoVendaDetalhado(
        venda: venda,
        descricaoItens: descricaoItens.isEmpty ? 'Sem itens' : descricaoItens,
      );
    }).toList();
  }

  ResumoFinanceiroPeriodo gerarResumo(PeriodoFiltro periodo) {
    final vendas = _vendaRepository
        .listarPorPeriodo(periodo)
        .where((venda) => !venda.cancelada);
    double faturamento = 0;
    double custo = 0;
    for (final venda in vendas) {
      faturamento += venda.total;
      custo += venda.custoTotal;
    }
    return ResumoFinanceiroPeriodo(
      quantidadeVendas: vendas.length,
      faturamento: faturamento,
      custo: custo,
      lucro: faturamento - custo,
    );
  }

  PeriodoFiltro periodoHoje() {
    final agora = DateTime.now();
    final inicio = DateTime(agora.year, agora.month, agora.day);
    final fim = inicio
        .add(const Duration(days: 1))
        .subtract(const Duration(milliseconds: 1));
    return PeriodoFiltro(inicio: inicio, fim: fim);
  }

  PeriodoFiltro ultimosDias(int dias) {
    final agora = DateTime.now();
    final inicio = DateTime(
      agora.year,
      agora.month,
      agora.day,
    ).subtract(Duration(days: dias - 1));
    return PeriodoFiltro(inicio: inicio, fim: agora);
  }

  Future<String> exportarCsv(PeriodoFiltro periodo) async {
    final vendas = _vendaRepository.listarPorPeriodo(periodo);
    final linhas = <String>[
      'id,data,total,custo_total,lucro_total,cancelada,itens',
    ];

    for (final venda in vendas) {
      final itensTexto = venda.itens
          .map((item) => '${item.nomeProduto} x${item.quantidade}')
          .join(' | ');
      final linha = [
        venda.id.toString(),
        venda.data.toIso8601String(),
        venda.total.toStringAsFixed(2),
        venda.custoTotal.toStringAsFixed(2),
        venda.lucroTotal.toStringAsFixed(2),
        venda.cancelada ? 'sim' : 'nao',
        '"${itensTexto.replaceAll('"', '""')}"',
      ].join(',');
      linhas.add(linha);
    }

    final baseDir = Platform.isWindows
        ? await getApplicationSupportDirectory()
        : await getApplicationDocumentsDirectory();
    final exportDir = Directory(p.join(baseDir.path, 'exportacoes'));
    if (!exportDir.existsSync()) {
      exportDir.createSync(recursive: true);
    }

    final timestamp = DateTime.now().toIso8601String().replaceAll(':', '-');
    final arquivo = File(p.join(exportDir.path, 'vendas_$timestamp.csv'));
    await arquivo.writeAsString(linhas.join('\n'));
    return arquivo.path;
  }
}
