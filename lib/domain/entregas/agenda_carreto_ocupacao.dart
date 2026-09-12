import 'package:flutter/material.dart';

import '../../model/item_venda.dart';
import '../../model/venda.dart';
import '../entrega_filtro_util.dart';
import '../entrega_venda_helper.dart';
import '../venda_documento_rotulo_helper.dart';
import '../venda_relacao_safe.dart';

/// Ocupacao da agenda de carretos (PDV checkout + API).
class AgendaCarretoOcupacaoMes {
  const AgendaCarretoOcupacaoMes({
    required this.ano,
    required this.mes,
    required this.quantidadePorDia,
    required this.itens,
  });

  final int ano;
  final int mes;

  /// Chave `yyyy-MM-dd` (dia local) -> quantidade.
  final Map<String, int> quantidadePorDia;

  final List<AgendaCarretoOcupacaoItem> itens;

  List<AgendaCarretoOcupacaoItem> itensDoDia(DateTime dia) {
    final k = chaveDia(dia);
    return itens.where((e) => e.dataChave == k).toList(growable: false);
  }

  int quantidadeDoDia(DateTime dia) => quantidadePorDia[chaveDia(dia)] ?? 0;

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

  Map<String, dynamic> paraMap() => {
        'mes': '$ano-${mes.toString().padLeft(2, '0')}',
        'dias': quantidadePorDia.entries
            .map((e) => {'data': e.key, 'quantidade': e.value})
            .toList(),
        'itens': itens.map((e) => e.paraMap()).toList(),
      };

  factory AgendaCarretoOcupacaoMes.deMap(Map<String, dynamic> m) {
    final mesRaw = (m['mes'] ?? '').toString();
    var ano = DateTime.now().year;
    var mes = DateTime.now().month;
    final partes = mesRaw.split('-');
    if (partes.length >= 2) {
      ano = int.tryParse(partes[0]) ?? ano;
      mes = int.tryParse(partes[1]) ?? mes;
    }
    final qtd = <String, int>{};
    final diasRaw = m['dias'];
    if (diasRaw is List) {
      for (final e in diasRaw) {
        if (e is! Map) continue;
        final data = (e['data'] ?? '').toString();
        final n = (e['quantidade'] as num?)?.toInt() ?? 0;
        if (data.isNotEmpty && n > 0) qtd[data] = n;
      }
    }
    final itens = <AgendaCarretoOcupacaoItem>[];
    final itensRaw = m['itens'];
    if (itensRaw is List) {
      for (final e in itensRaw) {
        if (e is! Map) continue;
        itens.add(
          AgendaCarretoOcupacaoItem.deMap(Map<String, dynamic>.from(e)),
        );
      }
    }
    return AgendaCarretoOcupacaoMes(
      ano: ano,
      mes: mes,
      quantidadePorDia: qtd,
      itens: itens,
    );
  }
}

class AgendaCarretoOcupacaoItem {
  const AgendaCarretoOcupacaoItem({
    required this.dataChave,
    required this.vendaId,
    required this.numero,
    required this.clienteNome,
    required this.bairro,
    required this.janela,
    required this.status,
    required this.ehOrcamento,
    this.produtos = const [],
  });

  final String dataChave;
  final int vendaId;
  final int numero;
  final String clienteNome;
  final String bairro;
  final String janela;
  final String status;
  final bool ehOrcamento;
  final List<AgendaCarretoProdutoLinha> produtos;

  String get janelaRotulo => AgendaCarretoOcupacaoHelper.rotuloJanela(janela);
  String get statusRotulo => AgendaCarretoOcupacaoHelper.rotuloStatus(status);

  Map<String, dynamic> paraMap() => {
        'data': dataChave,
        'vendaId': vendaId,
        'numero': numero,
        'clienteNome': clienteNome,
        'bairro': bairro,
        'janela': janela,
        'status': status,
        'ehOrcamento': ehOrcamento,
        'produtos': produtos.map((e) => e.paraMap()).toList(),
      };

  factory AgendaCarretoOcupacaoItem.deMap(Map<String, dynamic> m) {
    final produtos = <AgendaCarretoProdutoLinha>[];
    final raw = m['produtos'];
    if (raw is List) {
      for (final e in raw) {
        if (e is! Map) continue;
        produtos.add(
          AgendaCarretoProdutoLinha.deMap(Map<String, dynamic>.from(e)),
        );
      }
    }
    return AgendaCarretoOcupacaoItem(
      dataChave: (m['data'] ?? '').toString(),
      vendaId: (m['vendaId'] as num?)?.toInt() ?? 0,
      numero: (m['numero'] as num?)?.toInt() ?? 0,
      clienteNome: (m['clienteNome'] ?? 'Sem cliente').toString(),
      bairro: (m['bairro'] ?? 'Sem bairro').toString(),
      janela: (m['janela'] ?? 'nao_definida').toString(),
      status: (m['status'] ?? '').toString(),
      ehOrcamento: m['ehOrcamento'] == true,
      produtos: produtos,
    );
  }

  AgendaCarretoOcupacaoItem copyWith({
    List<AgendaCarretoProdutoLinha>? produtos,
  }) {
    return AgendaCarretoOcupacaoItem(
      dataChave: dataChave,
      vendaId: vendaId,
      numero: numero,
      clienteNome: clienteNome,
      bairro: bairro,
      janela: janela,
      status: status,
      ehOrcamento: ehOrcamento,
      produtos: produtos ?? this.produtos,
    );
  }
}

/// Linha simplificada para o ExpansionTile do PDV.
class AgendaCarretoProdutoLinha {
  const AgendaCarretoProdutoLinha({
    required this.nomeProduto,
    required this.quantidade,
    required this.quantidadeTexto,
    this.unidade = '',
  });

  final String nomeProduto;
  final double quantidade;
  final String quantidadeTexto;
  final String unidade;

  /// Ex.: "50x Cimento Cautex 50kg"
  String get rotulo {
    final nome = nomeProduto.trim().isEmpty ? 'Produto' : nomeProduto.trim();
    final q = quantidadeTexto.trim().isEmpty ? '1' : quantidadeTexto.trim();
    return '${q}x $nome';
  }

  Map<String, dynamic> paraMap() => {
        'nomeProduto': nomeProduto,
        'quantidade': quantidade,
        'quantidadeTexto': quantidadeTexto,
        'unidade': unidade,
      };

  factory AgendaCarretoProdutoLinha.deMap(Map<String, dynamic> m) {
    final q = (m['quantidade'] as num?)?.toDouble() ?? 0;
    var texto = (m['quantidadeTexto'] ?? '').toString().trim();
    if (texto.isEmpty) {
      texto = q == q.roundToDouble() ? '${q.toInt()}' : q.toStringAsFixed(2);
    }
    return AgendaCarretoProdutoLinha(
      nomeProduto: (m['nomeProduto'] ?? '').toString(),
      quantidade: q,
      quantidadeTexto: texto,
      unidade: (m['unidade'] ?? '').toString(),
    );
  }
}

abstract final class AgendaCarretoOcupacaoHelper {
  AgendaCarretoOcupacaoHelper._();

  /// Ate 3 verde, 4–7 amarelo, 8+ vermelho.
  static Color corVolume(BuildContext context, int quantidade) {
    final cs = Theme.of(context).colorScheme;
    if (quantidade <= 0) return cs.outlineVariant;
    if (quantidade <= 3) return const Color(0xFF2E7D32);
    if (quantidade <= 7) return const Color(0xFFF9A825);
    return const Color(0xFFC62828);
  }

  static String rotuloJanela(String janela) {
    switch (janela.trim().toLowerCase()) {
      case 'manha':
        return 'Manha';
      case 'tarde':
        return 'Tarde';
      case 'nao_definida':
      default:
        return 'Nao definida';
    }
  }

  static String rotuloStatus(String status) {
    switch (status.trim().toLowerCase()) {
      case 'pendente':
        return 'Pendente';
      case 'roteirizada':
        return 'No patio';
      case 'em_rota':
        return 'Em rota';
      case 'entregue':
        return 'Entregue';
      case 'reagendada':
        return 'Reagendada';
      case 'cancelada':
        return 'Cancelada';
      case 'orcamento':
        return 'Orcamento';
      case 'nao_aplicavel':
        return '—';
      default:
        final s = status.trim();
        return s.isEmpty ? '—' : s;
    }
  }

  static String extrairBairro(String enderecoEntrega) {
    final endereco = enderecoEntrega.trim();
    if (endereco.isEmpty) return 'Sem bairro';
    final partesPipe = endereco
        .split('|')
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toList();
    if (partesPipe.length >= 2) return partesPipe[1];
    final partesVirgula = endereco
        .split(',')
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toList();
    if (partesVirgula.length >= 2) return partesVirgula[1];
    return partesPipe.isNotEmpty ? partesPipe.first : 'Sem bairro';
  }

  static AgendaCarretoOcupacaoItem itemDeVenda(
    Venda venda, {
    dynamic clienteRepository,
    List<AgendaCarretoProdutoLinha> produtos = const [],
  }) {
    final marcada = venda.dataEntregaMarcada!;
    final ehOrc = venda.status.trim().toLowerCase() == 'orcamento';
    final status = ehOrc
        ? 'orcamento'
        : (venda.statusEntrega.trim().isEmpty
            ? 'pendente'
            : venda.statusEntrega);
    return AgendaCarretoOcupacaoItem(
      dataChave: AgendaCarretoOcupacaoMes.chaveDia(marcada),
      vendaId: venda.id,
      numero: int.tryParse(
            VendaDocumentoRotuloHelper.badgeNumeroCurto(venda),
          ) ??
          venda.id,
      clienteNome: VendaRelacaoSafe.nomeCliente(
        venda,
        clienteRepository: clienteRepository,
      ),
      bairro: extrairBairro(venda.enderecoEntrega),
      janela: venda.janelaEntrega,
      status: status,
      ehOrcamento: ehOrc,
      produtos: produtos,
    );
  }

  /// Produtos do carreto (em misto, so linhas entrega_loja).
  static List<AgendaCarretoProdutoLinha> mapearProdutos(
    Venda venda,
    List<ItemVenda> linhas,
  ) {
    if (linhas.isEmpty) return const [];
    final misto = venda.tipoEntrega == EntregaVendaHelper.tipoMisto;
    final out = <AgendaCarretoProdutoLinha>[];
    for (final it in linhas) {
      if (misto &&
          EntregaVendaHelper.normalizarTipoItem(it.tipoEntregaItem) !=
              EntregaVendaHelper.tipoEntregaLoja) {
        continue;
      }
      final p = it.produtoOuNull;
      final unidade = (p?.unidade ?? '').trim();
      final qEfetiva = it.quantidadeVendaEfetiva;
      final texto = it.quantidadeExibicaoVenda.trim().isNotEmpty
          ? it.quantidadeExibicaoVenda.trim()
          : (qEfetiva == qEfetiva.roundToDouble()
              ? '${qEfetiva.toInt()}'
              : qEfetiva.toStringAsFixed(2));
      final nome = it.nomeProduto.trim().isNotEmpty
          ? it.nomeProduto.trim()
          : (p?.nome.trim().isNotEmpty == true ? p!.nome.trim() : 'Produto');
      out.add(
        AgendaCarretoProdutoLinha(
          nomeProduto: nome,
          quantidade: qEfetiva,
          quantidadeTexto: texto,
          unidade: unidade,
        ),
      );
    }
    return out;
  }

  static bool contaNaAgenda(Venda venda) {
    if (venda.cancelada) return false;
    if (venda.dataEntregaMarcada == null) return false;
    final st = venda.status.trim().toLowerCase();
    if (st != 'finalizada' && st != 'orcamento') return false;
    if (EntregaFiltroUtil.ehConcluidaNaAgenda(venda.statusEntrega)) return false;
    return EntregaVendaHelper.vendaTemItensCarreto(venda) ||
        venda.tipoEntrega == EntregaVendaHelper.tipoEntregaLoja ||
        venda.tipoEntrega == EntregaVendaHelper.tipoMisto;
  }
}
