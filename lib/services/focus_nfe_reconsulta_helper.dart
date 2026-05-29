import 'focus_nfe_service.dart';

/// Recuperacao pos-timeout/rede via reconsulta Focus (F1).
abstract final class FocusNfeReconsultaHelper {
  FocusNfeReconsultaHelper._();

  static Future<FocusNfeEmissaoResultado> recuperarSePossivel({
    required FocusNfeEmissaoResultado original,
    required Future<FocusNfeEmissaoResultado> Function() reconsultar,
  }) async {
    if (original.autorizada || original.processando) return original;
    if (!FocusNfeService.pareceFalhaComunicacao(original)) return original;
    try {
      final consulta = await reconsultar();
      if (consulta.autorizada || consulta.processando) return consulta;
    } catch (_) {}
    return original;
  }

  static FocusNfeEmissaoResultado comoProcessandoAposFalhaComunicacao({
    required String referencia,
    String mensagem =
        'Falha de comunicacao ao emitir. A nota pode ter sido enviada — '
        'aguardando confirmacao da SEFAZ.',
  }) {
    return FocusNfeEmissaoResultado(
      autorizada: false,
      rejeitada: false,
      processando: true,
      statusFocus: 'processando_autorizacao',
      referencia: referencia,
      mensagem: mensagem,
    );
  }
}
