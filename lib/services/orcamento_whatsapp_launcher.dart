import 'package:url_launcher/url_launcher.dart';

import '../domain/fiscal/nfe_whatsapp_helper.dart';

/// Abre conversa WhatsApp com resumo de orcamento (link wa.me).
abstract final class OrcamentoWhatsappLauncher {
  OrcamentoWhatsappLauncher._();

  /// Apenas digitos; adiciona `55` se o operador informou 10 ou 11 digitos.
  static String higienizarTelefone(String telefone) {
    return NfeWhatsappHelper.normalizarTelefone(telefone);
  }

  /// `https://wa.me/NUMERO?text=MENSAGEM` com encoding seguro.
  static Uri? montarUriWaMe({
    required String telefone,
    required String mensagem,
  }) {
    final phoneClean = higienizarTelefone(telefone);
    if (phoneClean.length < 12) return null;
    final messageEncoded = Uri.encodeComponent(mensagem);
    return Uri.parse('https://wa.me/$phoneClean?text=$messageEncoded');
  }

  static Future<bool> abrirConversa({
    required String telefone,
    required String mensagem,
  }) async {
    final uri = montarUriWaMe(telefone: telefone, mensagem: mensagem);
    if (uri == null) return false;
    if (!await canLaunchUrl(uri)) return false;
    return launchUrl(uri, mode: LaunchMode.externalApplication);
  }
}
