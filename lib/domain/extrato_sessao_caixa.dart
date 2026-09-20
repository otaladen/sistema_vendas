import '../data/caixa_auditoria_repository.dart';
import '../domain/pagamento_orcamento.dart';
import '../domain/venda_documento_rotulo_helper.dart';
import '../domain/venda_finalizacao_caixa_helper.dart';
import '../model/recebimento_fiado.dart';
import '../model/venda.dart';
import '../services/cupom_nao_fiscal_venda_pdf.dart';
import 'caixa_meio_pagamento_fechamento.dart';
import 'sessao_caixa_referencia.dart';

class ExtratoSessaoCaixaResumoPagamento {
  const ExtratoSessaoCaixaResumoPagamento({
    this.dinheiro = 0,
    this.pix = 0,
    this.cartaoDebito = 0,
    this.cartaoCredito = 0,
    this.fiado = 0,
    this.outros = 0,
  });

  final double dinheiro;
  final double pix;
  final double cartaoDebito;
  final double cartaoCredito;
  final double fiado;
  final double outros;

  double get cartao => cartaoDebito + cartaoCredito;

  double get totalVendas =>
      dinheiro + pix + cartaoDebito + cartaoCredito + fiado + outros;
}

class ExtratoSessaoCaixaLinhaVenda {
  const ExtratoSessaoCaixaLinhaVenda({
    required this.numeroDocumento,
    required this.nfceRotulo,
    required this.hora,
    required this.cliente,
    required this.valor,
    required this.formaPagamento,
  });

  final String numeroDocumento;
  final String nfceRotulo;
  final String hora;
  final String cliente;
  final double valor;
  final String formaPagamento;
}

class ExtratoSessaoCaixaMovimento {
  const ExtratoSessaoCaixaMovimento({
    required this.tipo,
    required this.dataHora,
    required this.valor,
    this.observacao = '',
  });

  final String tipo;
  final DateTime dataHora;
  final double valor;
  final String observacao;
}

class ExtratoSessaoCaixaLinhaRecebimento {
  const ExtratoSessaoCaixaLinhaRecebimento({
    required this.recebimentoId,
    required this.hora,
    required this.cliente,
    required this.valor,
    required this.formaPagamento,
  });

  final int recebimentoId;
  final String hora;
  final String cliente;
  final double valor;
  final String formaPagamento;
}

class ExtratoSessaoCaixaDados {
  const ExtratoSessaoCaixaDados({
    required this.sessao,
    required this.resumo,
    required this.vendas,
    required this.recebimentos,
    required this.movimentos,
    required this.quantidadeVendas,
    required this.totalVendas,
    required this.quantidadeRecebimentosFiado,
    required this.totalRecebimentosFiado,
  });

  final SessaoCaixaReferencia sessao;
  final ExtratoSessaoCaixaResumoPagamento resumo;
  final List<ExtratoSessaoCaixaLinhaVenda> vendas;
  final List<ExtratoSessaoCaixaLinhaRecebimento> recebimentos;
  final List<ExtratoSessaoCaixaMovimento> movimentos;
  final int quantidadeVendas;
  final double totalVendas;
  final int quantidadeRecebimentosFiado;
  final double totalRecebimentosFiado;
}

/// Monta o extrato detalhado de uma sessao de caixa.
abstract final class ExtratoSessaoCaixaMontador {
  ExtratoSessaoCaixaMontador._();

  static ExtratoSessaoCaixaDados montar({
    required SessaoCaixaReferencia sessao,
    required dynamic vendaRepository,
    required List<CaixaAuditoriaRegistro> auditoria,
    required String Function(int clienteId) nomeCliente,
  }) {
    final intervalo = sessao.intervaloFiltroVendasUtc();
    final vendas = _listarVendasSessao(
      vendaRepository,
      inicio: intervalo.$1,
      fim: intervalo.$2,
    );

    final resumoVendas = _resumoPagamentos(vendas);
    final recebimentosBruto = _listarRecebimentosSessao(
      vendaRepository,
      inicio: intervalo.$1,
      fim: intervalo.$2,
    );
    final resumoRecebimentos = _resumoRecebimentos(recebimentosBruto);
    final resumo = ExtratoSessaoCaixaResumoPagamento(
      dinheiro: resumoVendas.dinheiro + resumoRecebimentos.dinheiro,
      pix: resumoVendas.pix + resumoRecebimentos.pix,
      cartaoDebito: resumoVendas.cartaoDebito + resumoRecebimentos.cartaoDebito,
      cartaoCredito:
          resumoVendas.cartaoCredito + resumoRecebimentos.cartaoCredito,
      fiado: resumoVendas.fiado,
      outros: resumoVendas.outros + resumoRecebimentos.outros,
    );
    final linhasRecebimentos = recebimentosBruto.map((rec) {
      final momento = rec.data;
      return ExtratoSessaoCaixaLinhaRecebimento(
        recebimentoId: rec.id,
        hora: _fmtHora.format(momento.toLocal()),
        cliente: nomeCliente(rec.cliente.targetId).trim().isEmpty
            ? 'Sem cliente'
            : nomeCliente(rec.cliente.targetId),
        valor: rec.valorTotal,
        formaPagamento:
            CupomNaoFiscalVendaPdf.rotuloFormaPagamento(rec.formaPagamento),
      );
    }).toList()
      ..sort((a, b) => a.hora.compareTo(b.hora));
    final linhas = vendas.map((v) {
      final momento = VendaFinalizacaoCaixaHelper.momentoFinalizacao(v);
      return ExtratoSessaoCaixaLinhaVenda(
        numeroDocumento: VendaDocumentoRotuloHelper.badgeNumeroCurto(v),
        nfceRotulo: _rotuloNfce(v),
        hora: _fmtHora.format(momento.toLocal()),
        cliente: nomeCliente(v.cliente.targetId).trim().isEmpty
            ? 'Sem cliente'
            : nomeCliente(v.cliente.targetId),
        valor: v.total,
        formaPagamento: CupomNaoFiscalVendaPdf.rotuloPagamentoCabecalho(v),
      );
    }).toList();

    final movimentos = _movimentosSessao(
      auditoria,
      inicio: intervalo.$1,
      fim: intervalo.$2,
      operador: sessao.operador,
    );

    final totalVendas = vendas.fold<double>(0, (s, v) => s + v.total);
    final totalRecebimentos = recebimentosBruto.fold<double>(
      0,
      (s, r) => s + r.valorTotal,
    );

    return ExtratoSessaoCaixaDados(
      sessao: sessao,
      resumo: resumo,
      vendas: linhas,
      recebimentos: linhasRecebimentos,
      movimentos: movimentos,
      quantidadeVendas: vendas.length,
      totalVendas: totalVendas,
      quantidadeRecebimentosFiado: recebimentosBruto.length,
      totalRecebimentosFiado: totalRecebimentos,
    );
  }

  static final _fmtHora = _HoraLocal();

  static List<RecebimentoFiado> _listarRecebimentosSessao(
    dynamic repo, {
    required DateTime inicio,
    required DateTime fim,
  }) {
    try {
      return (repo.recebimentos.listarNoPeriodo(
            inicio: inicio,
            fim: fim,
          ) as List)
          .whereType<RecebimentoFiado>()
          .toList();
    } catch (_) {
      return const [];
    }
  }

  static List<Venda> _listarVendasSessao(
    dynamic repo, {
    required DateTime inicio,
    required DateTime fim,
  }) {
    try {
      return (repo.listarVendasFinalizadasSessaoCaixa(
            inicioSessao: inicio,
            fimSessao: fim,
          ) as List)
          .whereType<Venda>()
          .toList();
    } catch (_) {
      return const [];
    }
  }

  static ExtratoSessaoCaixaResumoPagamento _resumoPagamentos(List<Venda> vendas) {
    var dinheiro = 0.0;
    var pix = 0.0;
    var debito = 0.0;
    var credito = 0.0;
    var fiado = 0.0;
    var outros = 0.0;

    void aplicar(String? meio, double valor) {
      if (valor <= 0) return;
      switch (CaixaMeioPagamentoFechamento.bucket(meio)) {
        case CaixaMeioPagamentoFechamento.bucketDinheiro:
          dinheiro += valor;
          break;
        case CaixaMeioPagamentoFechamento.bucketPix:
          pix += valor;
          break;
        case CaixaMeioPagamentoFechamento.bucketDebito:
          debito += valor;
          break;
        case CaixaMeioPagamentoFechamento.bucketCredito:
          credito += valor;
          break;
        default:
          if ((meio ?? '').trim().toLowerCase() == PagamentoMeio.fiado) {
            fiado += valor;
          } else {
            outros += valor;
          }
          break;
      }
    }

    for (final v in vendas) {
      if (v.formaPagamento == PagamentoMeio.misto &&
          v.pagamentosJson.trim().isNotEmpty) {
        for (final l in PagamentoOrcamentoCodec.decode(v.pagamentosJson)) {
          aplicar(l.meio, l.valor);
        }
      } else {
        aplicar(v.formaPagamento, v.total);
      }
    }

    return ExtratoSessaoCaixaResumoPagamento(
      dinheiro: dinheiro,
      pix: pix,
      cartaoDebito: debito,
      cartaoCredito: credito,
      fiado: fiado,
      outros: outros,
    );
  }

  /// Quitacoes de fiado (entrada real no caixa), mesma regra da leitura parcial.
  static ExtratoSessaoCaixaResumoPagamento _resumoRecebimentos(
    List<RecebimentoFiado> recebimentos,
  ) {
    var dinheiro = 0.0;
    var pix = 0.0;
    var debito = 0.0;
    var credito = 0.0;
    var outros = 0.0;

    for (final rec in recebimentos) {
      final valor = rec.valorTotal;
      if (valor <= 0) continue;
      switch (rec.formaPagamento.trim().toLowerCase()) {
        case 'dinheiro':
          dinheiro += valor;
          break;
        case 'pix':
          pix += valor;
          break;
        case 'cartao_debito':
          debito += valor;
          break;
        case 'cartao_credito':
          credito += valor;
          break;
        default:
          outros += valor;
          break;
      }
    }

    return ExtratoSessaoCaixaResumoPagamento(
      dinheiro: dinheiro,
      pix: pix,
      cartaoDebito: debito,
      cartaoCredito: credito,
      outros: outros,
    );
  }

  static List<ExtratoSessaoCaixaMovimento> _movimentosSessao(
    List<CaixaAuditoriaRegistro> auditoria, {
    required DateTime inicio,
    required DateTime fim,
    required String operador,
  }) {
    final ini = inicio.toUtc();
    final f = fim.toUtc();
    final out = <ExtratoSessaoCaixaMovimento>[];
    for (final r in auditoria) {
      if (r.evento != 'suprimento' && r.evento != 'sangria') continue;
      final em = r.em.toUtc();
      if (em.isBefore(ini) || em.isAfter(f)) continue;
      final op =
          (r.detalhes['operador']?.toString() ?? r.operadorCaixa).trim();
      if (operador.trim().isNotEmpty &&
          op.isNotEmpty &&
          op.toLowerCase() != operador.trim().toLowerCase()) {
        continue;
      }
      out.add(
        ExtratoSessaoCaixaMovimento(
          tipo: r.evento == 'suprimento' ? 'Suprimento' : 'Sangria',
          dataHora: r.em,
          valor: r.valor,
          observacao: (r.detalhes['observacao'] ?? '').toString(),
        ),
      );
    }
    out.sort((a, b) => a.dataHora.compareTo(b.dataHora));
    return out;
  }

  static String _rotuloNfce(Venda v) {
    if (v.nfceNumero.trim().isNotEmpty) {
      return 'NFC-e ${v.nfceNumero.trim()}';
    }
    if (v.nfceChaveAcesso.trim().length >= 20) {
      return 'NFC-e ${v.nfceChaveAcesso.substring(v.nfceChaveAcesso.length - 8)}';
    }
    return '-';
  }
}

class _HoraLocal {
  String format(DateTime local) {
    final h = local.hour.toString().padLeft(2, '0');
    final m = local.minute.toString().padLeft(2, '0');
    return '$h:$m';
  }
}
