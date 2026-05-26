import '../../model/cliente.dart';

/// Monta link WhatsApp com texto da NF-e (DANFE).
abstract final class NfeWhatsappHelper {
  NfeWhatsappHelper._();

  static String normalizarTelefone(String telefone) {
    var d = telefone.replaceAll(RegExp(r'\D'), '');
    if (d.length == 10 || d.length == 11) {
      d = '55$d';
    }
    return d;
  }

  static String? telefoneCliente(Cliente? cliente) {
    if (cliente == null) return null;
    final w = normalizarTelefone(cliente.whatsapp);
    if (w.length >= 12) return w;
    final t = normalizarTelefone(cliente.telefone);
    if (t.length >= 12) return t;
    return null;
  }

  static String montarMensagemDanfe({
    required String clienteNome,
    required String numeroNfe,
    required String urlDanfe,
    String? chave,
  }) {
    final buf = StringBuffer()
      ..writeln('Ola${clienteNome.trim().isNotEmpty ? ", $clienteNome" : ""}!')
      ..writeln('Segue a NF-e${numeroNfe.isNotEmpty ? " nº $numeroNfe" : ""} da sua compra.');
    if (urlDanfe.trim().isNotEmpty) {
      buf.writeln('DANFE: ${urlDanfe.trim()}');
    }
    if (chave != null && chave.replaceAll(RegExp(r'\D'), '').length == 44) {
      buf.writeln('Chave: $chave');
    }
    return buf.toString().trim();
  }

  static Uri? uriWhatsapp({
    required String telefone,
    required String mensagem,
  }) {
    final tel = normalizarTelefone(telefone);
    if (tel.length < 12) return null;
    return Uri.parse(
      'https://wa.me/$tel?text=${Uri.encodeComponent(mensagem)}',
    );
  }
}
