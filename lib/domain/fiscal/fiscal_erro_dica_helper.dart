/// Dicas operacionais a partir de mensagens de rejeicao SEFAZ / Focus NFe.
abstract final class FiscalErroDicaHelper {
  FiscalErroDicaHelper._();

  static String? dicaSolucao(String mensagem) {
    final m = mensagem.trim().toLowerCase();
    if (m.isEmpty) return null;

    if (m.contains('ncm')) {
      return 'Revise o NCM do produto no cadastro (Fiscal / tributacao). '
          'Use um codigo valido na tabela TIPI.';
    }
    if (m.contains('csosn') || m.contains(' cst ') || m.startsWith('cst')) {
      return 'Confira CSOSN/CST e aliquotas do produto conforme o regime '
          'tributario da empresa.';
    }
    if (m.contains('cfop')) {
      return 'Verifique o CFOP da operacao (venda, entrega, devolucao) '
          'no cadastro fiscal do produto ou da venda.';
    }
    if (m.contains('frete') || m.contains('vfrete') || m.contains('537')) {
      return 'O total de frete ou desconto pode divergir do somatorio dos '
          'itens. Confira frete, desconto e totais no PDV/caixa.';
    }
    if (m.contains('desconto') || m.contains('vdesc')) {
      return 'Desconto informado no total difere da soma dos itens. '
          'Ajuste desconto no PDV ou rateie nos produtos.';
    }
    if (m.contains('produto') &&
        (m.contains('nao encontr') ||
            m.contains('inexistente') ||
            m.contains('sem cadastro') ||
            m.contains('vincul'))) {
      return 'Um item da venda pode estar sem produto vinculado ou com cadastro '
          'incompleto. Revincule o item ou complete o cadastro.';
    }
    if (m.contains('cpf') ||
        m.contains('cnpj') ||
        m.contains('destinat') ||
        m.contains('consumidor')) {
      return 'Confira CPF/CNPJ e dados do cliente/destinatario na venda.';
    }
    if (m.contains('gtin') ||
        m.contains('ean') ||
        m.contains('codigo de barras') ||
        m.contains('cbarra')) {
      return 'Verifique codigo de barras/GTIN do produto ou informe '
          '"SEM GTIN" quando aplicavel.';
    }
    if (m.contains('certificado') || m.contains('ssl') || m.contains('token')) {
      return 'Problema de certificado ou credenciais Focus NFe. '
          'Verifique configuracao fiscal no servidor.';
    }
    if (m.contains('duplic') || m.contains('ja autoriz') || m.contains('539')) {
      return 'A nota pode ja ter sido autorizada. Use Reconsultar antes de '
          'tentar emitir novamente.';
    }
    if (m.contains('timeout') ||
        m.contains('comunic') ||
        m.contains('conex') ||
        m.contains('sefaz indispon')) {
      return 'Falha de comunicacao com a SEFAZ. Aguarde alguns minutos e '
          'tente Reconsultar ou emitir novamente.';
    }
    return null;
  }

  /// Texto curto para badge na lista de pendencias.
  static String rotuloResumoLista(String mensagem) {
    final msg = mensagem.trim();
    if (msg.isEmpty) return '';
    final codigo = extrairCodigoRejeicao(msg);
    final resumo = msg.length > 90 ? '${msg.substring(0, 87)}...' : msg;
    if (codigo != null) {
      return 'Rejeicao SEFAZ $codigo: $resumo';
    }
    if (msg.toLowerCase().contains('rejeic') ||
        msg.toLowerCase().contains('sefaz')) {
      return 'Rejeicao SEFAZ: $resumo';
    }
    return 'Erro fiscal: $resumo';
  }

  static String? extrairCodigoRejeicao(String mensagem) {
    final patterns = [
      RegExp(r'rejei[cç][aã]o\s*[:#]?\s*(\d{2,4})', caseSensitive: false),
      RegExp(r'\bc[oó]d(?:igo)?\s*(\d{2,4})\b', caseSensitive: false),
      RegExp(r'\b(\d{3})\s*[-:]\s*rejei', caseSensitive: false),
    ];
    for (final p in patterns) {
      final m = p.firstMatch(mensagem);
      if (m != null) return m.group(1);
    }
    return null;
  }
}
