import '../data/movimento_estoque_repository.dart';
import '../data/objectbox.dart';
import '../domain/entrega_venda_helper.dart';
import '../domain/estoque/estoque_diagnostico_models.dart';
import '../domain/venda_documento_rotulo_helper.dart';
import '../model/produto.dart';
import '../model/venda.dart';
import '../objectbox.g.dart';

/// Diagnostico read-only de integridade operacional do estoque.
class EstoqueDiagnosticoService {
  EstoqueDiagnosticoService(ObjectBox db)
      : _db = db,
        _movimentos = MovimentoEstoqueRepository(db);

  final ObjectBox _db;
  final MovimentoEstoqueRepository _movimentos;

  EstoqueDiagnosticoResultado executar() {
    final achados = <EstoqueDiagnosticoAchado>[];
    achados.addAll(_diagnosticarVendas());
    achados.addAll(_diagnosticarProdutos());
    achados.sort(_ordenarAchados);
    return EstoqueDiagnosticoResultado(
      achados: achados,
      geradoEm: DateTime.now().toUtc(),
    );
  }

  List<EstoqueDiagnosticoAchado> _diagnosticarVendas() {
    final achados = <EstoqueDiagnosticoAchado>[];
    final query = _db.vendaBox
        .query(Venda_.status.equals('finalizada'))
        .build();
    try {
      for (final venda in query.find()) {
        if (venda.cancelada) continue;
        achados.addAll(_achadosVenda(venda));
      }
    } finally {
      query.close();
    }
    return achados;
  }

  List<EstoqueDiagnosticoAchado> _achadosVenda(Venda venda) {
    final achados = <EstoqueDiagnosticoAchado>[];
    final controle = VendaDocumentoRotuloHelper.rotuloControleInterno(venda);
    final temLevaAgoraPendente =
        EntregaVendaHelper.vendaTemItensRetiradaImediataPendenteCupom(venda);

    if (venda.estoqueBaixadoCupom && temLevaAgoraPendente) {
      achados.add(
        EstoqueDiagnosticoAchado(
          codigo: EstoqueDiagnosticoCodigo.vendaFlagBaixaSemMovimento,
          severidade: EstoqueDiagnosticoSeveridade.critico,
          titulo: '$controle marcada com estoque OK, mas itens pendentes',
          detalhe:
              'A venda consta com baixa concluida, porem ainda ha itens '
              '"leva agora" sem quantidade retirada. Revise o kardex e '
              'reprocesse a baixa se necessario.',
          vendaId: venda.id,
          podeReprocessarBaixa: true,
        ),
      );
      return achados;
    }

    if (!temLevaAgoraPendente || venda.estoqueBaixadoCupom) {
      return achados;
    }

    achados.add(
      EstoqueDiagnosticoAchado(
        codigo: EstoqueDiagnosticoCodigo.vendaBaixaPendente,
        severidade: EstoqueDiagnosticoSeveridade.critico,
        titulo: '$controle com baixa de estoque pendente',
        detalhe:
            'Venda finalizada com itens "leva agora" ainda nao baixados. '
            'Use "Reprocessar baixa" ou verifique a finalizacao no caixa.',
        vendaId: venda.id,
        podeReprocessarBaixa: true,
      ),
    );
    return achados;
  }

  List<EstoqueDiagnosticoAchado> _diagnosticarProdutos() {
    final achados = <EstoqueDiagnosticoAchado>[];
    final produtos = _db.produtoBox.getAll();
    for (final produto in produtos) {
      achados.addAll(_achadosProduto(produto));
    }
    return achados;
  }

  List<EstoqueDiagnosticoAchado> _achadosProduto(Produto produto) {
    final achados = <EstoqueDiagnosticoAchado>[];
    final nome = produto.nome.trim().isEmpty
        ? 'Produto #${produto.id}'
        : produto.nome.trim();

    if (produto.estoqueReservado < 0) {
      achados.add(
        EstoqueDiagnosticoAchado(
          codigo: EstoqueDiagnosticoCodigo.reservaNegativa,
          severidade: EstoqueDiagnosticoSeveridade.critico,
          titulo: '$nome com reserva negativa',
          detalhe:
              'Reservado: ${produto.estoqueReservado}. '
              'Corrija com ajuste manual ou libere reservas orfas.',
          produtoId: produto.id,
        ),
      );
    }

    if (_movimentos.contarPorProduto(produto.id) <= 0) {
      return achados;
    }

    final ultimos = _movimentos.listarPorProduto(produto.id, limite: 1);
    if (ultimos.isEmpty) return achados;

    final ultimo = ultimos.first;
    final fisicoDiverge = ultimo.saldoFisicoDepois != produto.estoqueReal;
    final reservaDiverge =
        ultimo.saldoReservaDepois != produto.estoqueReservado;
    if (!fisicoDiverge && !reservaDiverge) return achados;

    final partes = <String>[];
    if (fisicoDiverge) {
      partes.add(
        'fisico cadastro ${produto.estoqueReal}, '
        'kardex ${ultimo.saldoFisicoDepois}',
      );
    }
    if (reservaDiverge) {
      partes.add(
        'reserva cadastro ${produto.estoqueReservado}, '
        'kardex ${ultimo.saldoReservaDepois}',
      );
    }

    achados.add(
      EstoqueDiagnosticoAchado(
        codigo: EstoqueDiagnosticoCodigo.saldoDivergenteKardex,
        severidade: EstoqueDiagnosticoSeveridade.alerta,
        titulo: '$nome com saldo divergente do kardex',
        detalhe: partes.join(' · '),
        produtoId: produto.id,
      ),
    );
    return achados;
  }

  int _ordenarAchados(
    EstoqueDiagnosticoAchado a,
    EstoqueDiagnosticoAchado b,
  ) {
    final pa = _pesoSeveridade(a.severidade);
    final pb = _pesoSeveridade(b.severidade);
    if (pa != pb) return pb.compareTo(pa);
    return a.titulo.compareTo(b.titulo);
  }

  int _pesoSeveridade(EstoqueDiagnosticoSeveridade s) {
    switch (s) {
      case EstoqueDiagnosticoSeveridade.critico:
        return 3;
      case EstoqueDiagnosticoSeveridade.alerta:
        return 2;
      case EstoqueDiagnosticoSeveridade.info:
        return 1;
    }
  }
}
