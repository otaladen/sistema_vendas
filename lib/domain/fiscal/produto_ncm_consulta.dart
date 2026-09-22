/// Estado e regras da consulta oficial de NCM no cadastro de produto.
class ProdutoNcmConsultaState {
  String infoExibicao = '';
  bool consultando = false;

  int _geracao = 0;
  String? _ncmUltimaConsultaAplicada;

  static String normalizarDigitos(String ncm) =>
      ncm.replaceAll(RegExp(r'\D'), '');

  static String textoInfoValido({
    required String descricaoOficial,
    required String codigoFormatado,
  }) {
    final desc = descricaoOficial.trim();
    if (desc.isEmpty) return 'NCM valido: $codigoFormatado';
    return 'NCM valido: $desc';
  }

  static String textoTabelaLocal(String descricao) =>
      'Tabela local: ${descricao.trim()}';

  /// Limpa descricao e invalida consultas HTTP ainda em voo.
  void limpar() {
    _geracao++;
    consultando = false;
    infoExibicao = '';
    _ncmUltimaConsultaAplicada = null;
  }

  /// Usuario editou o campo NCM — remove texto obsoleto de outro codigo.
  void aoEditarCampo(String ncmCampo) {
    final digitos = normalizarDigitos(ncmCampo);
    if (_ncmUltimaConsultaAplicada != null &&
        digitos != _ncmUltimaConsultaAplicada) {
      infoExibicao = '';
      _ncmUltimaConsultaAplicada = null;
    } else if (digitos.length < 8 &&
        infoExibicao.startsWith('NCM valido:')) {
      infoExibicao = '';
      _ncmUltimaConsultaAplicada = null;
    }
  }

  int iniciarConsulta() {
    _geracao++;
    consultando = true;
    infoExibicao = '';
    return _geracao;
  }

  bool _campoCompativelComConsulta(int token, String ncmCampoAtual) {
    if (token != _geracao) return false;
    return normalizarDigitos(ncmCampoAtual).length == 8;
  }

  void finalizarConsulta(int token) {
    if (token == _geracao) consultando = false;
  }

  void aplicarResultadoOficial(
    int token,
    String ncmCampoAtual, {
    required String digitosConsultados,
    required String descricaoOficial,
    required String codigoFormatado,
  }) {
    if (!_campoCompativelComConsulta(token, ncmCampoAtual)) return;
    if (normalizarDigitos(ncmCampoAtual) != digitosConsultados) return;
    infoExibicao = textoInfoValido(
      descricaoOficial: descricaoOficial,
      codigoFormatado: codigoFormatado,
    );
    _ncmUltimaConsultaAplicada = digitosConsultados;
  }

  void aplicarNaoEncontrado(
    int token,
    String ncmCampoAtual,
    String digitosConsultados,
  ) {
    if (!_campoCompativelComConsulta(token, ncmCampoAtual)) return;
    if (normalizarDigitos(ncmCampoAtual) != digitosConsultados) return;
    infoExibicao = '';
    _ncmUltimaConsultaAplicada = null;
  }

  void aplicarTabelaLocal(String digitos, String descricao) {
    _geracao++;
    consultando = false;
    infoExibicao = textoTabelaLocal(descricao);
    _ncmUltimaConsultaAplicada = normalizarDigitos(digitos);
  }

  bool deveConsultarAutomaticamente(String ncmCampo) {
    final digitos = normalizarDigitos(ncmCampo);
    if (digitos.length != 8 || consultando) return false;
    return digitos != _ncmUltimaConsultaAplicada;
  }
}
