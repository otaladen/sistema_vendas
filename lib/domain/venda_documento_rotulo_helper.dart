import 'package:flutter/material.dart';

import '../model/venda.dart';

/// Dados minimos da NF-e 55 para rotulos (evita acoplar UI ao store).
class VendaDocumentoNfe55Resumo {
  const VendaDocumentoNfe55Resumo({
    this.numero = '',
    this.autorizada = false,
  });

  final String numero;
  final bool autorizada;
}

/// Rotulos unificados: orçamento, controle interno, nota fiscal e estoque.
abstract final class VendaDocumentoRotuloHelper {
  VendaDocumentoRotuloHelper._();

  static bool ehOrcamentoAberto(Venda venda) =>
      venda.status == 'orcamento' && !venda.cancelada;

  static int numeroOrcamentoExibido(Venda venda) =>
      venda.numeroOrcamento > 0 ? venda.numeroOrcamento : venda.id;

  static String rotuloOrcamentoPorNumero(int numero) => 'Orc. $numero';

  static String rotuloOrcamento(Venda venda) =>
      rotuloOrcamentoPorNumero(numeroOrcamentoExibido(venda));

  /// Controle Interno só existe depois da finalização no caixa.
  /// Orçamento aberto não tem número de controle.
  static int numeroControleInterno(Venda venda) {
    if (venda.numeroControle > 0) return venda.numeroControle;
    if (venda.status == 'finalizada') {
      return venda.numeroOrcamento > 0 ? venda.numeroOrcamento : venda.id;
    }
    return 0;
  }

  /// Próximo Controle a partir dos números já exibidos (nunca reinicia do 1).
  static int proximoNumeroControleApos(Iterable<int> numerosExistentes) {
    var maior = 0;
    for (final n in numerosExistentes) {
      if (n > maior) maior = n;
    }
    return maior + 1;
  }

  static String rotuloControlePorNumero(int numero) => 'Controle $numero';

  static String rotuloControleInterno(Venda venda) {
    if (venda.status == 'orcamento') {
      return rotuloOrcamento(venda);
    }
    final n = numeroControleInterno(venda);
    if (n <= 0) return rotuloOrcamento(venda);
    return rotuloControlePorNumero(n);
  }

  static String? rotuloNfce(Venda venda) {
    if (!venda.nfceEmitida) return null;
    final numero = venda.nfceNumero.trim();
    return numero.isNotEmpty ? 'NFC-e $numero' : 'NFC-e autorizada';
  }

  static String? rotuloNfe55DeVenda(Venda venda) {
    if (!venda.nfe55Autorizada) return null;
    final numero = venda.nfeNumero.trim();
    return numero.isNotEmpty ? 'NF-e $numero' : 'NF-e 55';
  }

  static String? rotuloNfe55(VendaDocumentoNfe55Resumo? nfe55) {
    if (nfe55 == null || !nfe55.autorizada) return null;
    final numero = nfe55.numero.trim();
    return numero.isNotEmpty ? 'NF-e $numero' : 'NF-e 55';
  }

  /// Cabecalho da listagem: nota(s) fiscal(is) + controle interno.
  static String rotuloIdentificacaoLista(
    Venda venda, {
    VendaDocumentoNfe55Resumo? nfe55,
  }) {
    if (venda.status == 'orcamento') {
      return rotuloOrcamento(venda);
    }
    final partes = <String>[];
    final nfce = rotuloNfce(venda);
    if (nfce != null) partes.add(nfce);
    final nfe = rotuloNfe55(nfe55);
    if (nfe != null) partes.add(nfe);
    partes.add(rotuloControleInterno(venda));
    return partes.join(' · ');
  }

  /// Status operacional na listagem de vendas.
  static String statusOperacionalLista(
    Venda venda, {
    VendaDocumentoNfe55Resumo? nfe55,
  }) {
    if (venda.status == 'orcamento') {
      return venda.cancelada
          ? '${rotuloOrcamento(venda)} · cancelado'
          : '${rotuloOrcamento(venda)} · em aberto';
    }
    final controle = rotuloControleInterno(venda);
    if (venda.nfceProcessandoPendenteFocus) {
      final estoque = venda.estoqueBaixadoCupom
          ? ''
          : ' · Estoque pendente';
      return 'NFC-e aguardando SEFAZ · $controle$estoque';
    }
    if (venda.nfceEmissaoEmAndamento) {
      return 'Emitindo NFC-e... · $controle';
    }

    final temNfce = venda.nfceEmitida;
    final temNfe55 = nfe55?.autorizada == true;
    if (!temNfce && !temNfe55) {
      if (venda.estoqueBaixadoCupom) {
        return '$controle · fiscal pendente';
      }
      return '$controle · aguardando documento';
    }

    final partes = <String>[];
    final nfce = rotuloNfce(venda);
    if (nfce != null) partes.add(nfce);
    final nfe = rotuloNfe55(nfe55);
    if (nfe != null) partes.add(nfe);
    partes.add(controle);
    if (!venda.estoqueBaixadoCupom) partes.add('Estoque pendente');
    return partes.join(' · ');
  }

  /// Rotulo curto para coluna Status (sem repetir documento/controle).
  static String statusOperacionalResumidoLista(
    Venda venda, {
    VendaDocumentoNfe55Resumo? nfe55,
  }) {
    if (venda.status == 'orcamento') {
      return venda.cancelada ? 'Orçamento cancelado' : 'Orçamento';
    }
    if (venda.nfceProcessandoPendenteFocus) {
      return venda.estoqueBaixadoCupom
          ? 'SEFAZ pendente'
          : 'SEFAZ pendente · Estoque pendente';
    }
    if (venda.nfceEmissaoEmAndamento) {
      return 'Emitindo NFC-e';
    }

    final temNfce = venda.nfceEmitida;
    final temNfe55 = nfe55?.autorizada == true;
    if (!temNfce && !temNfe55) {
      if (!venda.estoqueBaixadoCupom) {
        return 'Fiscal e estoque pendentes';
      }
      return 'Fiscal pendente';
    }

    if (!venda.estoqueBaixadoCupom) return 'Estoque pendente';
    return 'Concluída';
  }

  static Color corStatusLista(Venda venda, ColorScheme scheme) {
    if (venda.status == 'orcamento') {
      return scheme.outline;
    }
    if (venda.nfceProcessandoPendenteFocus || venda.nfceEmissaoEmAndamento) {
      return scheme.tertiary;
    }
    if (venda.estoqueBaixadoCupom) return scheme.primary;
    return scheme.error;
  }

  /// Texto curto para chip/snackbar no caixa apos autorizacao fiscal.
  static String resumoPosAutorizacaoFiscal(
    Venda venda, {
    VendaDocumentoNfe55Resumo? nfe55,
  }) {
    final partes = <String>[];
    final nfce = rotuloNfce(venda);
    if (nfce != null) partes.add(nfce);
    final nfe = rotuloNfe55(nfe55);
    if (nfe != null) partes.add(nfe);
    partes.add(rotuloControleInterno(venda));
    if (venda.estoqueBaixadoCupom) partes.add('Estoque OK');
    return partes.join(' · ');
  }

  /// Observacao transmitida na NFC-e / NF-e (campo infCpl / adicionais).
  static String observacaoFiscalNota(Venda venda) {
    final partes = <String>[rotuloControleInterno(venda)];
    if (venda.enderecoEntrega.trim().isNotEmpty) {
      partes.add('Entrega: ${venda.enderecoEntrega.trim()}');
    }
    return partes.join(' | ');
  }

  /// Linhas de referencia fiscal no cupom interno (abaixo do titulo CONTROLE).
  static List<String> linhasReferenciasFiscaisNoCupom(Venda venda) {
    final linhas = <String>[];
    final nfce = rotuloNfce(venda);
    if (nfce != null) linhas.add(nfce);
    final nfe = rotuloNfe55DeVenda(venda);
    if (nfe != null) linhas.add(nfe);
    return linhas;
  }

  /// Titulo curto em listas (caixa, modais).
  static String rotuloTituloLista(Venda venda) => rotuloControleInterno(venda);

  static String badgeNumeroCurto(Venda venda) {
    if (venda.status == 'orcamento') {
      return '${numeroOrcamentoExibido(venda)}';
    }
    final n = numeroControleInterno(venda);
    return n > 0 ? '$n' : '${numeroOrcamentoExibido(venda)}';
  }

  /// Identificador visivel ao cliente na aba Entregas (ex.: `#712`).
  static String hashIdentificadorEntrega(Venda venda) =>
      '#${badgeNumeroCurto(venda)}';

  static String rotuloPedidoEntrega(Venda venda) =>
      'Pedido ${hashIdentificadorEntrega(venda)}';

  static String tituloItensPedidoEntrega(
    Venda venda, {
    bool paraEntrega = false,
  }) {
    final id = hashIdentificadorEntrega(venda);
    return paraEntrega ? 'Itens para entrega $id' : 'Itens do pedido $id';
  }

  /// Busca por numero na aba Entregas (controle, orcamento legado, id interno).
  static bool vendaAtendeBuscaNumeroEntrega(Venda venda, int numero) {
    if (numero <= 0) return false;
    if (venda.numeroControle > 0 && venda.numeroControle == numero) {
      return true;
    }
    final controle = numeroControleInterno(venda);
    if (controle > 0 && controle == numero) return true;
    if (venda.numeroOrcamento > 0 && venda.numeroOrcamento == numero) {
      return true;
    }
    return venda.id == numero;
  }

  /// Subtitulo com nota fiscal quando existir (ultimas vendas do caixa).
  static String subtituloListaComDocumentos(Venda venda) {
    final partes = <String>[];
    final nfce = rotuloNfce(venda);
    if (nfce != null) partes.add(nfce);
    final nfe = rotuloNfe55DeVenda(venda);
    if (nfe != null) partes.add(nfe);
    if (partes.isEmpty) return '';
    return partes.join(' · ');
  }
}
