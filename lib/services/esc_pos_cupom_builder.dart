import 'dart:typed_data';

import 'package:intl/intl.dart';

import '../config/fiscal_config.dart';
import '../data/app_config_repository.dart';
import '../domain/entrega_venda_helper.dart';
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
import 'fiscal_config_store.dart';

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
///
/// Dinheiro/fiado (sem NFC-e real): layout estilo DANFE NFC-e com chave
/// decorativa + QR — o mesmo visual do PDF `estiloCupomNfce`.
abstract final class EscPosCupomBuilder {
  EscPosCupomBuilder._();

  static final _moeda = NumberFormat('#,##0.00', 'pt_BR');
  static final _data = DateFormat('dd/MM/yyyy HH:mm:ss');

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

    final chaveReal =
        CupomPdfLayout.chaveAcessoSomenteDigitos(venda.nfceChaveAcesso);
    final chaveValida = chaveReal.length == 44;
    final temNfceReal =
        chaveValida || venda.nfceNumero.trim().isNotEmpty;
    final homolog = FiscalConfigStore.efetivo.homologacao;
    final emissao = (venda.nfceEmitidaEm ?? venda.data).toLocal();

    // Cupom dinheiro/fiado: numera como NFC-e auxiliar (controle interno).
    final numeroDoc = temNfceReal
        ? (venda.nfceNumero.trim().isEmpty ? '-' : venda.nfceNumero.trim())
        : '${VendaDocumentoRotuloHelper.numeroControleInterno(venda)}';
    final serieDoc = temNfceReal
        ? (venda.nfceSerie.trim().isEmpty
            ? '001'
            : venda.nfceSerie.trim().padLeft(3, '0'))
        : '001';

    final chaveImpressao = chaveValida
        ? chaveReal
        : CupomPdfLayout.chaveAcessoSomenteDigitos(
            CupomPdfLayout.gerarChaveAcessoDecorativaNfce(
              cnpj: FiscalConfig.cnpjEmitente,
              uf: FiscalConfig.ufEmitente,
              numeroNota: numeroDoc,
              serie: serieDoc,
              emissao: emissao,
            ),
          );

    // --- Cabecalho ---
    out.add(EscPosCommands.alignCenter);
    out.add(EscPosCommands.boldOn);
    for (final l in _wrap(config.nomeLoja.trim(), cols)) {
      out.add(EscPosCommands.line(l));
    }
    out.add(EscPosCommands.boldOff);
    final razao = FiscalConfig.razaoSocialEmitente.trim();
    if (razao.isNotEmpty &&
        razao.toLowerCase() != config.nomeLoja.trim().toLowerCase()) {
      for (final l in _wrap(razao, cols)) {
        out.add(EscPosCommands.line(l));
      }
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

    // Titulo estilo DANFE (cupom dinheiro e NFC-e real).
    out.add(EscPosCommands.boldOn);
    out.add(EscPosCommands.line('DANFE NFC-e - DOCUMENTO AUXILIAR'));
    out.add(EscPosCommands.line('DA NOTA FISCAL ELETRONICA'));
    out.add(EscPosCommands.line('PARA CONSUMIDOR FINAL'));
    out.add(EscPosCommands.boldOff);
    if (dados.segundaVia) {
      out.add(EscPosCommands.line('*** SEGUNDA VIA ***'));
    }
    if (temNfceReal && homolog) {
      out.add(EscPosCommands.boldOn);
      out.add(EscPosCommands.line('AMBIENTE DE HOMOLOGACAO'));
      out.add(EscPosCommands.line('SEM VALOR FISCAL'));
      out.add(EscPosCommands.boldOff);
    }
    out.add(EscPosCommands.alignLeft);

    out.add(EscPosCommands.line('NFC-e $numeroDoc Serie $serieDoc'));
    out.add(EscPosCommands.line('Emissao: ${_data.format(emissao)}'));
    if (temNfceReal) {
      final prot = venda.nfceProtocolo.trim();
      if (prot.isNotEmpty && !prot.startsWith('emissao:')) {
        out.add(EscPosCommands.line('Protocolo: ${_trunc(prot, cols - 11)}'));
      }
    }
    out.add(EscPosCommands.boldOn);
    out.add(EscPosCommands.line(
      dados.segundaVia ? 'SEGUNDA VIA' : 'VIA CONSUMIDOR',
    ));
    out.add(EscPosCommands.boldOff);
    out.add(EscPosCommands.line(
      VendaDocumentoRotuloHelper.rotuloControleInterno(venda),
    ));

    final vendNome = CupomNaoFiscalVendaPdf.rotuloVendedorUmLinha(dados.vendedor);
    if (vendNome.trim().isNotEmpty &&
        vendNome.trim().toLowerCase() != 'sem vendedor') {
      out.add(EscPosCommands.line('Vendedor: ${_trunc(vendNome, cols - 10)}'));
    }

    _adicionarBlocoEntregaCarreto(
      out,
      cols: cols,
      venda: venda,
      cliente: dados.cliente,
      itens: dados.itens,
    );

    final cli = dados.cliente;
    if (temNfceReal && homolog) {
      out.add(EscPosCommands.line(
        _trunc('Cliente: NF-E EMITIDA EM AMBIENTE DE HOMOLOGACAO', cols),
      ));
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

    // Cupom dinheiro (sem NFC-e SEFAZ): aviso de contingencia visual LDV.
    if (!temNfceReal) {
      out.add(EscPosCommands.separator(cols));
      out.add(EscPosCommands.alignCenter);
      out.add(EscPosCommands.boldOn);
      for (final l in _wrap(
        'NOTA EMITIDA EM CONTIGENCIA-AUTORIZACAO PENDENTE',
        cols,
      )) {
        out.add(EscPosCommands.line(l));
      }
      out.add(EscPosCommands.boldOff);
    }

    out.add(EscPosCommands.separator(cols));
    out.add(EscPosCommands.alignCenter);

    final urlConsulta = CupomPdfLayout.urlConsultaNfcePorUf();
    out.add(EscPosCommands.line('Consulte pela Chave de Acesso em'));
    for (final l in _wrap(urlConsulta, cols)) {
      out.add(EscPosCommands.line(l));
    }
    out.add(EscPosCommands.line(''));
    out.add(EscPosCommands.boldOn);
    out.add(EscPosCommands.line('CHAVE DE ACESSO'));
    out.add(EscPosCommands.boldOff);
    if (chaveImpressao.length == 44) {
      for (final l in _linhasChaveAcesso(chaveImpressao, cols)) {
        out.add(EscPosCommands.line(l));
      }
    }

    final qr = _payloadQr(venda, chaveImpressao);
    if (qr.isNotEmpty) {
      out.add(EscPosCommands.feed(1));
      out.add(EscPosCommands.line('Consulta via leitor de QR Code'));
      out.add(EscPosCommands.qrCode(qr, moduleSize: cols >= 42 ? 5 : 4));
      out.add(EscPosCommands.feed(1));
    }

    if (!(temNfceReal && homolog)) {
      out.add(EscPosCommands.separator(cols));
      out.add(EscPosCommands.boldOn);
      for (final linha in CupomPdfLayout.linhasIdentificacaoConsumidor(cli)) {
        for (final l in _wrap(linha, cols)) {
          out.add(EscPosCommands.line(l));
        }
      }
      out.add(EscPosCommands.boldOff);
    }

    // Rodape fiscal: so em NFC-e real de homologacao.
    if (temNfceReal && homolog) {
      out.add(EscPosCommands.boldOn);
      out.add(EscPosCommands.line('SEM VALOR FISCAL'));
      out.add(EscPosCommands.boldOff);
    } else if (temNfceReal) {
      final rodape = config.rodapeNota.trim();
      if (rodape.isNotEmpty && !_pareceRodapeNaoFiscal(rodape)) {
        for (final l in _wrap(rodape, cols)) {
          out.add(EscPosCommands.line(l));
        }
      } else {
        out.add(EscPosCommands.line('Obrigado pela preferencia!'));
      }
    }
    // Cupom dinheiro: sem "Documento nao fiscal" (layout DANFE auxiliar).
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

  static bool _pareceRodapeNaoFiscal(String s) {
    final t = s
        .toLowerCase()
        .replaceAll('ã', 'a')
        .replaceAll('á', 'a')
        .replaceAll('à', 'a');
    return t.contains('nao fiscal');
  }

  static List<String> _linhasChaveAcesso(String digitos44, int cols) {
    final grupos = <String>[];
    for (var i = 0; i < digitos44.length; i += 4) {
      grupos.add(digitos44.substring(i, i + 4));
    }
    final maxGrupos = ((cols + 1) ~/ 5).clamp(4, 11);
    final linhas = <String>[];
    for (var i = 0; i < grupos.length; i += maxGrupos) {
      final end = (i + maxGrupos).clamp(0, grupos.length);
      linhas.add(grupos.sublist(i, end).join(' '));
    }
    return linhas;
  }

  static String _payloadQr(Venda venda, String chaveDigitos) {
    final url = venda.nfceUrlDanfe.trim();
    if (url.isNotEmpty) return url;
    if (chaveDigitos.length == 44) {
      final base = CupomPdfLayout.urlConsultaNfcePorUf();
      return '$base?p=$chaveDigitos';
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
