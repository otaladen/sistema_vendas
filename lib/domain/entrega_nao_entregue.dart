/// Motivos de insucesso no Modo motorista (vira [reagendada] na loja).
abstract final class EntregaNaoEntregueMotivo {
  static const ausente = 'ausente';
  static const enderecoErrado = 'endereco_errado';
  static const recusou = 'recusou';

  static const todos = [ausente, enderecoErrado, recusou];

  static String rotulo(String id) {
    switch (id) {
      case ausente:
        return 'Cliente ausente';
      case enderecoErrado:
        return 'Endereco errado';
      case recusou:
        return 'Cliente recusou';
      default:
        return id.trim();
    }
  }

  static bool valido(String id) => todos.contains(id.trim());

  static String textoOcorrencia(String codigo, String detalhe) {
    final base = rotulo(codigo.trim());
    final extra = detalhe.trim();
    return extra.isEmpty ? base : '$base. $extra';
  }

  static const sufixoCargaLoja = 'Carga retornou para a loja.';
  static const sufixoCargaCaminhao = 'Carga permanece no caminhao.';
}

/// Ultimo insucesso visivel no patio (observacao da venda).
class EntregaInsucessoResumo {
  const EntregaInsucessoResumo({
    required this.motivo,
    this.retornouParaLoja,
  });

  final String motivo;
  final bool? retornouParaLoja;

  String get linhaPatio {
    final carga = switch (retornouParaLoja) {
      true => ' · voltou a loja',
      false => ' · no caminhao',
      null => '',
    };
    return '$motivo$carga';
  }

  static final _linhaInsucesso = RegExp(
    r'^\[\d{2}/\d{2}/\d{4}[^\]]*\]\s+'
    r'(ENTREGA_EVENTO_NAO_ENTREGUE|REAGENDADA)\s+por\s+[^:]+:\s*(.+)$',
    caseSensitive: false,
  );

  static EntregaInsucessoResumo? deVenda({
    required String statusEntrega,
    required String observacaoEntrega,
  }) {
    if (statusEntrega.trim() != 'reagendada') return null;
    EntregaInsucessoResumo? ultimo;
    for (final raw in observacaoEntrega.split('\n')) {
      final linha = raw.trim();
      if (linha.isEmpty) continue;
      final m = _linhaInsucesso.firstMatch(linha);
      if (m == null) continue;
      ultimo = _dePayload(m.group(2) ?? '');
    }
    return ultimo ?? const EntregaInsucessoResumo(motivo: 'Insucesso');
  }

  static EntregaInsucessoResumo _dePayload(String payload) {
    var texto = payload.trim();
    bool? retornou;
    if (texto.contains(EntregaNaoEntregueMotivo.sufixoCargaLoja)) {
      retornou = true;
      texto = texto.replaceAll(EntregaNaoEntregueMotivo.sufixoCargaLoja, '');
    } else if (texto.contains(EntregaNaoEntregueMotivo.sufixoCargaCaminhao)) {
      retornou = false;
      texto = texto.replaceAll(EntregaNaoEntregueMotivo.sufixoCargaCaminhao, '');
    }
    texto = texto.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (texto.endsWith('.')) {
      texto = texto.substring(0, texto.length - 1).trim();
    }
    if (texto.isEmpty) texto = 'Insucesso';
    return EntregaInsucessoResumo(motivo: texto, retornouParaLoja: retornou);
  }
}

abstract final class EntregaMotoristaAcao {
  static const entregue = 'entregue';
  static const naoEntregue = 'nao_entregue';
}

/// Observacao do PDV, sem log de ocorrencia/motorista.
abstract final class EntregaObservacaoMotorista {
  static final _linhaOcorrencia = RegExp(r'^\[\d{2}/\d{2}/\d{4}');

  static String visivel(String raw) {
    final linhas = raw
        .split('\n')
        .map((l) => l.trim())
        .where((l) => l.isNotEmpty)
        .where((l) => !l.startsWith('Motorista:'))
        .where((l) => !_linhaOcorrencia.hasMatch(l))
        .toList();
    return linhas.join('\n');
  }
}

abstract final class EntregaContatoMotorista {
  static String somenteDigitos(String raw) =>
      raw.replaceAll(RegExp(r'\D'), '');

  static String? uriTelefone(String raw) {
    final d = somenteDigitos(raw);
    if (d.length < 8) return null;
    return 'tel:$d';
  }

  static String? uriWhatsApp(String raw) {
    var d = somenteDigitos(raw);
    if (d.length < 8) return null;
    if (d.length <= 11) d = '55$d';
    return 'https://wa.me/$d';
  }
}
