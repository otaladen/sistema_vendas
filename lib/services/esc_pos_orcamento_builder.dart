import 'dart:typed_data';

import 'package:intl/intl.dart';

import '../config/fiscal_config.dart';
import '../data/app_config_repository.dart';
import '../domain/entrega_venda_helper.dart';
import '../domain/orcamento_condicoes_pagamento.dart';
import '../domain/plano_fiado.dart';
import '../domain/produto_embalagem.dart';
import '../domain/produto_nome_exibicao.dart';
import '../model/cliente.dart';
import '../model/item_venda.dart';
import '../model/produto.dart';
import '../model/venda.dart';
import '../model/vendedor.dart';
import 'esc_pos_commands.dart';
import 'fiscal_config_store.dart';
import 'orcamento_pdf_service.dart';

/// Dados tipados para montar o orcamento termico ESC/POS.
class OrcamentoEscPosDados {
  const OrcamentoEscPosDados({
    required this.venda,
    required this.config,
    required this.itens,
    required this.validadeDias,
    this.cliente,
    this.vendedor,
    this.produtosPorItem = const {},
  });

  final Venda venda;
  final EmpresaConfig config;
  final List<ItemVenda> itens;
  final int validadeDias;
  final Cliente? cliente;
  final Vendedor? vendedor;
  final Map<int, Produto?> produtosPorItem;
}

/// Monta bytes ESC/POS do orcamento (fonte nativa da Epson TM-T20 etc.).
///
/// Evita PDF/raster do Windows, que deixa letras "picotadas" na termica.
abstract final class EscPosOrcamentoBuilder {
  EscPosOrcamentoBuilder._();

  static final _moeda = NumberFormat('#,##0.00', 'pt_BR');
  static final _data = DateFormat('dd/MM/yyyy HH:mm');
  static final _dataCurta = DateFormat('dd/MM/yyyy');

  static Uint8List montar(
    OrcamentoEscPosDados dados, {
    EscPosLarguraBobina largura = EscPosLarguraBobina.mm80,
    bool cortar = true,
  }) {
    final cols = largura.colunas;
    final out = BytesBuilder(copy: false);
    final venda = dados.venda;
    final config = dados.config;
    final itens = dados.itens;

    out.add(EscPosCommands.init);
    out.add(EscPosCommands.codePage850);

    // --- Cabecalho ---
    // Sem double-height: na TM-T20 corta o nome no meio da palavra.
    out.add(EscPosCommands.alignCenter);
    out.add(EscPosCommands.boldOn);
    for (final l in _wrap(config.nomeLoja.trim(), cols)) {
      out.add(EscPosCommands.line(l));
    }
    out.add(EscPosCommands.boldOff);

    final tel = config.telefone.trim();
    if (tel.isNotEmpty) {
      out.add(EscPosCommands.line('Tel/WhatsApp: $tel'));
    }
    final cnpj = FiscalConfigStore.efetivo.cnpjEmitente.trim().isNotEmpty
        ? FiscalConfigStore.efetivo.cnpjEmitente
        : FiscalConfig.cnpjEmitente;
    if (cnpj.trim().isNotEmpty) {
      out.add(EscPosCommands.line('CNPJ ${_formatCnpj(cnpj)}'));
    }
    for (final l in _wrap(config.endereco.trim(), cols)) {
      out.add(EscPosCommands.line(l));
    }

    out.add(EscPosCommands.separator(cols));
    out.add(EscPosCommands.boldOn);
    out.add(EscPosCommands.line('ORCAMENTO'));
    out.add(EscPosCommands.boldOff);
    out.add(EscPosCommands.alignLeft);

    final numOrc = venda.numeroOrcamento > 0 ? venda.numeroOrcamento : venda.id;
    final agora = DateTime.now();
    final validade = agora.add(Duration(days: dados.validadeDias));
    out.add(EscPosCommands.boldOn);
    out.add(EscPosCommands.line('ORCAMENTO N. $numOrc'));
    out.add(EscPosCommands.line('Emissao: ${_data.format(agora)}'));
    out.add(EscPosCommands.line(
      'Validade: ${_dataCurta.format(validade)} (${dados.validadeDias} dias)',
    ));
    out.add(EscPosCommands.boldOff);
    out.add(EscPosCommands.separator(cols));

    final cliente = dados.cliente;
    if (cliente != null && cliente.nomeRazao.trim().isNotEmpty) {
      out.add(EscPosCommands.boldOn);
      out.add(EscPosCommands.line('CLIENTE'));
      out.add(EscPosCommands.boldOff);
      out.add(EscPosCommands.line(
        'Nome: ${_trunc(cliente.nomeRazao.trim(), cols - 6)}',
      ));
      final telCli = cliente.telefone.trim();
      if (telCli.isNotEmpty) {
        out.add(EscPosCommands.line('Telefone: $telCli'));
      }
    }

    final vend = dados.vendedor;
    if (vend != null) {
      final nome = vend.apelido.trim().isNotEmpty
          ? vend.apelido.trim()
          : vend.nomeCompleto.trim();
      final codigo = vend.codigoInterno.trim();
      final rotulo = codigo.isNotEmpty ? '$codigo - $nome' : nome;
      out.add(EscPosCommands.line(
        'Vendedor: ${_trunc(rotulo, cols - 10)}',
      ));
    }

    _adicionarBlocoEntregaCarreto(
      out,
      cols: cols,
      venda: venda,
      cliente: cliente,
      itens: itens,
    );

    out.add(EscPosCommands.separator(cols));
    out.add(EscPosCommands.boldOn);
    out.add(EscPosCommands.line('ITENS'));
    out.add(EscPosCommands.boldOff);

    if (itens.isEmpty) {
      out.add(EscPosCommands.line('(Sem itens)'));
    } else {
      for (var i = 0; i < itens.length; i++) {
        final item = itens[i];
        final produto = dados.produtosPorItem[i];
        final qtdEfetiva = ProdutoEmbalagem.quantidadeVendaEfetivaItem(
          produto: produto,
          quantidadeArmazenada: item.quantidade,
        );
        final snap = item.nomeProduto.trim();
        final nome = produto != null
            ? ProdutoNomeExibicao.paraImpressao(produto)
            : (snap.isEmpty ? 'Produto' : snap);
        final sku = (produto?.codigoInterno ?? '').trim();
        final titulo = sku.isEmpty ? nome : '$sku - $nome';
        for (final l in _wrap(titulo, cols)) {
          out.add(EscPosCommands.line(l));
        }
        final qtdTxt = OrcamentoPdfService.quantidadeComUnidade(
          item: item,
          produto: produto,
        );
        final unit = _moeda.format(item.precoUnitario);
        final sub = _moeda.format(qtdEfetiva * item.precoUnitario);
        out.add(EscPosCommands.line(
          _trunc('  $qtdTxt x R\$ $unit = R\$ $sub', cols),
        ));
      }
    }

    out.add(EscPosCommands.separator(cols));
    out.add(EscPosCommands.boldOn);
    out.add(EscPosCommands.line('RESUMO'));
    out.add(EscPosCommands.boldOff);

    final subtotalItens = itens.fold<double>(0, (s, i) => s + i.subtotal);
    final desconto = venda.descontoImplicitoTotal;
    final temFrete = venda.valorFrete > 0;
    final bruto = subtotalItens + (temFrete ? venda.valorFrete : 0);
    final total = itens.isEmpty
        ? venda.total
        : (bruto - desconto).clamp(0.0, double.infinity);

    out.add(EscPosCommands.line(
      _padCols('Subtotal produtos:', 'R\$ ${_moeda.format(subtotalItens)}', cols),
    ));
    if (temFrete) {
      out.add(EscPosCommands.line(
        _padCols('Frete/Entrega:', 'R\$ ${_moeda.format(venda.valorFrete)}', cols),
      ));
    }
    if (desconto > 0) {
      out.add(EscPosCommands.line(
        _padCols('Desconto:', '- R\$ ${_moeda.format(desconto)}', cols),
      ));
    }
    out.add(EscPosCommands.boldOn);
    out.add(EscPosCommands.line(
      _padCols('VALOR TOTAL:', 'R\$ ${_moeda.format(total)}', cols),
    ));
    out.add(EscPosCommands.boldOff);

    out.add(EscPosCommands.separator(cols));
    out.add(EscPosCommands.boldOn);
    out.add(EscPosCommands.line(OrcamentoCondicoesPagamento.tituloSecao));
    for (final linha in OrcamentoCondicoesPagamento.linhasDaVenda(
      venda,
      total: total,
      formatarMoeda: (v) => 'R\$ ${_moeda.format(v)}',
    )) {
      for (final l in _wrap(linha, cols)) {
        out.add(EscPosCommands.line(l));
      }
    }
    out.add(EscPosCommands.boldOff);

    if (PlanoFiadoCodec.vendaTemPlanoQuitacao(venda)) {
      out.add(EscPosCommands.line('Condicao de quitacao (fiado):'));
      for (final linha in PlanoFiadoCodec.linhasTextoPdf(venda)) {
        for (final l in _wrap(linha, cols)) {
          out.add(EscPosCommands.line(l));
        }
      }
    }

    out.add(EscPosCommands.separator(cols));
    out.add(EscPosCommands.alignCenter);
    out.add(EscPosCommands.boldOn);
    for (final l in _wrap(
      'ESTE DOCUMENTO E UMA COTACAO E NAO POSSUI VALOR FISCAL.',
      cols,
    )) {
      out.add(EscPosCommands.line(l));
    }
    out.add(EscPosCommands.boldOff);

    final rodape = config.rodapeOrcamento.trim();
    if (rodape.isNotEmpty) {
      out.add(EscPosCommands.line(''));
      for (final l in _wrap(rodape, cols)) {
        out.add(EscPosCommands.line(l));
      }
    }

    out.add(EscPosCommands.feed(3));
    if (cortar) {
      out.add(EscPosCommands.cutPartial);
    }
    return out.toBytes();
  }

  static void _adicionarBlocoEntregaCarreto(
    BytesBuilder out, {
    required int cols,
    required Venda venda,
    Cliente? cliente,
    required List<ItemVenda> itens,
  }) {
    final linhas = EntregaVendaHelper.linhasBlocoEntregaImpressao(
      venda: venda,
      cliente: cliente,
      itens: itens,
    );
    if (linhas.isEmpty) return;

    out.add(EscPosCommands.separator(cols));
    out.add(EscPosCommands.alignLeft);
    out.add(EscPosCommands.boldOn);
    for (final l in _wrap(EntregaVendaHelper.tituloBlocoEntregaImpressao, cols)) {
      out.add(EscPosCommands.line(l));
    }
    out.add(EscPosCommands.boldOff);
    for (final linha in linhas) {
      for (final l in _wrap(linha, cols)) {
        out.add(EscPosCommands.line(l));
      }
    }
  }

  static String _formatCnpj(String raw) {
    final d = raw.replaceAll(RegExp(r'\D'), '');
    if (d.length != 14) return raw.trim();
    return '${d.substring(0, 2)}.${d.substring(2, 5)}.${d.substring(5, 8)}/'
        '${d.substring(8, 12)}-${d.substring(12)}';
  }

  static String _trunc(String s, int max) {
    final t = s.trim();
    if (t.length <= max) return t;
    if (max <= 1) return t.substring(0, max);
    return '${t.substring(0, max - 1)}.';
  }

  static List<String> _wrap(String s, int cols) {
    final t = s.trim();
    if (t.isEmpty) return const [];
    if (t.length <= cols) return [t];
    final out = <String>[];
    var rest = t;
    while (rest.length > cols) {
      var cut = rest.lastIndexOf(' ', cols);
      if (cut < cols ~/ 2) cut = cols;
      out.add(rest.substring(0, cut).trimRight());
      rest = rest.substring(cut).trimLeft();
    }
    if (rest.isNotEmpty) out.add(rest);
    return out;
  }

  static String _padCols(String left, String right, int cols) {
    final l = _trunc(left, cols - 1);
    final r = _trunc(right, cols - 1);
    final space = cols - l.length - r.length;
    if (space <= 0) return _trunc('$l $r', cols);
    return '$l${' ' * space}$r';
  }
}
