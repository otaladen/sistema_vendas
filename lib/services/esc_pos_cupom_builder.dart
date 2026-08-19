import 'dart:typed_data';

import 'package:intl/intl.dart';

import '../config/fiscal_config.dart';
import '../data/app_config_repository.dart';
import '../domain/produto_nome_exibicao.dart';
import '../domain/quantidade_venda_util.dart';
import '../domain/venda_documento_rotulo_helper.dart';
import '../model/cliente.dart';
import '../model/item_venda.dart';
import '../model/venda.dart';
import '../model/vendedor.dart';
import 'cupom_nao_fiscal_venda_pdf.dart';
import 'cupom_pdf_layout.dart';
import 'esc_pos_commands.dart';

/// Dados tipados para montar o cupom termico.
class CupomBalcaoDados {
  const CupomBalcaoDados({
    required this.venda,
    required this.config,
    required this.itens,
    this.cliente,
    this.vendedor,
    this.totalRecebido = 0,
    this.troco = 0,
    this.segundaVia = false,
  });

  final Venda venda;
  final EmpresaConfig config;
  final List<ItemVenda> itens;
  final Cliente? cliente;
  final Vendedor? vendedor;
  final double totalRecebido;
  final double troco;
  final bool segundaVia;
}

/// Monta bytes ESC/POS do cupom de venda / NFC-e.
abstract final class EscPosCupomBuilder {
  EscPosCupomBuilder._();

  static final _moeda = NumberFormat('#,##0.00', 'pt_BR');
  static final _data = DateFormat('dd/MM/yyyy HH:mm:ss', 'pt_BR');

  static Uint8List montar(
    CupomBalcaoDados dados, {
    EscPosLarguraBobina largura = EscPosLarguraBobina.mm80,
    bool cortar = true,
    bool abrirGaveta = false,
    int gavetaPino = 0,
  }) {
    final cols = largura.colunas;
    final out = BytesBuilder(copy: false);
    final venda = dados.venda;
    final config = dados.config;

    out.add(EscPosCommands.init);
    out.add(EscPosCommands.codePage850);

    // --- Cabecalho ---
    out.add(EscPosCommands.alignCenter);
    out.add(EscPosCommands.boldOn);
    out.add(EscPosCommands.doubleHeightOn);
    out.add(EscPosCommands.line(_trunc(config.nomeLoja, cols)));
    out.add(EscPosCommands.normalSize);
    out.add(EscPosCommands.boldOff);
    final razao = FiscalConfig.razaoSocialEmitente.trim();
    if (razao.isNotEmpty &&
        razao.toLowerCase() != config.nomeLoja.trim().toLowerCase()) {
      out.add(EscPosCommands.line(_wrap(razao, cols).first));
    }
    out.add(EscPosCommands.line(
      'CNPJ ${_formatCnpj(FiscalConfig.cnpjEmitente)}',
    ));
    if (FiscalConfig.inscricaoEstadualEmitente.trim().isNotEmpty) {
      out.add(EscPosCommands.line(
        'IE ${FiscalConfig.inscricaoEstadualEmitente.trim()}',
      ));
    }
    for (final l in _wrap(config.endereco.trim(), cols)) {
      out.add(EscPosCommands.line(l));
    }
    if (config.telefone.trim().isNotEmpty) {
      out.add(EscPosCommands.line('Tel: ${config.telefone.trim()}'));
    }
    out.add(EscPosCommands.separator(cols));

    final chaveValida =
        CupomPdfLayout.chaveAcessoSomenteDigitos(venda.nfceChaveAcesso).length ==
            44;
    final temNfce =
        chaveValida || venda.nfceNumero.trim().isNotEmpty;

    out.add(EscPosCommands.boldOn);
    if (temNfce) {
      out.add(EscPosCommands.line('CUPOM FISCAL ELETRONICO - NFC-e'));
    } else {
      out.add(EscPosCommands.line('CUPOM NAO FISCAL'));
    }
    out.add(EscPosCommands.boldOff);
    if (dados.segundaVia) {
      out.add(EscPosCommands.line('*** SEGUNDA VIA ***'));
    }
    out.add(EscPosCommands.alignLeft);

    final doc = temNfce
        ? 'NFC-e ${venda.nfceNumero.trim().isEmpty ? '-' : venda.nfceNumero.trim()}'
            '${venda.nfceSerie.trim().isEmpty ? '' : ' Serie ${venda.nfceSerie.trim()}'}'
        : 'Doc ${VendaDocumentoRotuloHelper.numeroControleInterno(venda)}';
    out.add(EscPosCommands.line(doc));
    out.add(EscPosCommands.line(
      'Emissao: ${_data.format((venda.nfceEmitidaEm ?? venda.data).toLocal())}',
    ));

    final vendNome = CupomNaoFiscalVendaPdf.rotuloVendedorUmLinha(dados.vendedor);
    out.add(EscPosCommands.line('Vendedor: ${_trunc(vendNome, cols - 10)}'));

    final cli = dados.cliente;
    if (cli != null) {
      final nome = cli.nomeFantasia.trim().isNotEmpty
          ? cli.nomeFantasia.trim()
          : cli.nomeRazao.trim();
      if (nome.isNotEmpty) {
        out.add(EscPosCommands.line('Cliente: ${_trunc(nome, cols - 9)}'));
      }
      final docCli = cli.documento.trim();
      if (docCli.isNotEmpty) {
        out.add(EscPosCommands.line('CPF/CNPJ: $docCli'));
      }
    } else {
      out.add(EscPosCommands.line('Cliente: Consumidor'));
    }

    out.add(EscPosCommands.separator(cols));
    out.add(EscPosCommands.boldOn);
    out.add(EscPosCommands.line(
      cols >= 42
          ? _padCols('COD/DESC', 'QTD  VL.UN  TOTAL', cols)
          : 'ITENS',
    ));
    out.add(EscPosCommands.boldOff);
    out.add(EscPosCommands.separator(cols));

    for (final item in dados.itens) {
      final cod = () {
        final p = item.produtoOuNull;
        if (p == null) return '${item.produto.targetId}';
        final c = p.codigoInterno.trim();
        if (c.isNotEmpty) return c;
        final b = p.codigoBarras.trim();
        if (b.isNotEmpty) return b;
        return '${p.id}';
      }();
      final nome = ProdutoNomeExibicao.paraImpressaoItem(item);
      final un = (item.produtoOuNull?.unidade ?? 'UN').trim().toUpperCase();
      final fracionada =
          item.produtoOuNull?.permiteQuantidadeFracionada ?? false;
      final qtd = QuantidadeVendaUtil.formatarExibicao(
        item.quantidadeVendaEfetiva,
        fracionada: fracionada,
      );
      final unit = _moeda.format(item.precoUnitario);
      final tot = _moeda.format(item.subtotal);
      out.add(EscPosCommands.line(_trunc('$cod $nome', cols)));
      out.add(EscPosCommands.line(
        _padCols('  $qtd $un x $unit', tot, cols),
      ));
    }

    out.add(EscPosCommands.separator(cols));
    final sub = dados.itens.fold<double>(0, (s, i) => s + i.subtotal);
    final desc = venda.descontoImplicitoTotal;
    final frete = venda.valorFrete;
    out.add(EscPosCommands.line(
      _padCols('Subtotal', _moeda.format(sub), cols),
    ));
    if (desc > 0.0001) {
      out.add(EscPosCommands.line(
        _padCols('Desconto', '-${_moeda.format(desc)}', cols),
      ));
    }
    if (frete > 0.0001) {
      out.add(EscPosCommands.line(
        _padCols('Acrescimo/Frete', _moeda.format(frete), cols),
      ));
    }
    out.add(EscPosCommands.boldOn);
    out.add(EscPosCommands.line(
      _padCols('TOTAL', 'R\$ ${_moeda.format(venda.total)}', cols),
    ));
    out.add(EscPosCommands.boldOff);

    out.add(EscPosCommands.line(
      'Pagamento: ${CupomNaoFiscalVendaPdf.rotuloPagamentoCabecalho(venda)}',
    ));
    if (dados.totalRecebido > 0.0001) {
      out.add(EscPosCommands.line(
        _padCols('Recebido', _moeda.format(dados.totalRecebido), cols),
      ));
    }
    if (dados.troco > 0.0001) {
      out.add(EscPosCommands.line(
        _padCols('Troco', _moeda.format(dados.troco), cols),
      ));
    }

    out.add(EscPosCommands.separator(cols));
    out.add(EscPosCommands.alignCenter);

    if (chaveValida) {
      final chave = CupomPdfLayout.formatarChaveAcessoGrupos(venda.nfceChaveAcesso);
      out.add(EscPosCommands.line('CHAVE DE ACESSO'));
      for (final l in _wrap(chave, cols)) {
        out.add(EscPosCommands.line(l));
      }
      final qr = _payloadQr(venda);
      if (qr.isNotEmpty) {
        out.add(EscPosCommands.feed(1));
        out.add(EscPosCommands.qrCode(qr, moduleSize: cols >= 42 ? 5 : 4));
        out.add(EscPosCommands.feed(1));
      }
    }

    final rodape = config.rodapeNota.trim().isEmpty
        ? 'Obrigado pela preferencia!'
        : config.rodapeNota.trim();
    for (final l in _wrap(rodape, cols)) {
      out.add(EscPosCommands.line(l));
    }
    out.add(EscPosCommands.line(''));

    out.add(EscPosCommands.feed(3));
    if (cortar) {
      out.add(EscPosCommands.cutPartial);
    }
    if (abrirGaveta) {
      out.add(EscPosCommands.drawerPulse(pino: gavetaPino));
    }

    return out.toBytes();
  }

  static String _payloadQr(Venda venda) {
    final url = venda.nfceUrlDanfe.trim();
    if (url.isNotEmpty) return url;
    final chave =
        CupomPdfLayout.chaveAcessoSomenteDigitos(venda.nfceChaveAcesso);
    if (chave.length == 44) {
      return 'https://www.nfce.fazenda.gov.br/portal/consulta.aspx?p=$chave';
    }
    return '';
  }

  static String _formatCnpj(String raw) {
    final d = raw.replaceAll(RegExp(r'\D'), '');
    if (d.length != 14) return raw;
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
