import 'dart:io';
import 'dart:typed_data';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../domain/fiscal/nfe_whatsapp_helper.dart';

/// Resultado do envio (PDF + conversa WhatsApp).
class OrcamentoWhatsappEnvioResult {
  const OrcamentoWhatsappEnvioResult._({
    required this.sucesso,
    this.chatAberto = false,
    this.pdfPath,
    this.mensagemErro,
  });

  final bool sucesso;
  final bool chatAberto;
  final String? pdfPath;
  final String? mensagemErro;

  factory OrcamentoWhatsappEnvioResult.ok({
    required bool chatAberto,
    String? pdfPath,
  }) {
    return OrcamentoWhatsappEnvioResult._(
      sucesso: true,
      chatAberto: chatAberto,
      pdfPath: pdfPath,
    );
  }

  factory OrcamentoWhatsappEnvioResult.falha(
    String mensagem, {
    String? pdfPath,
  }) {
    return OrcamentoWhatsappEnvioResult._(
      sucesso: false,
      pdfPath: pdfPath,
      mensagemErro: mensagem,
    );
  }
}

/// Abre conversa WhatsApp no numero informado e prepara PDF para anexo.
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

  static Uri? _montarUriWebWhatsapp({
    required String telefone,
    required String mensagem,
  }) {
    final phoneClean = higienizarTelefone(telefone);
    if (phoneClean.length < 12) return null;
    return Uri.parse(
      'https://web.whatsapp.com/send?phone=$phoneClean&text=${Uri.encodeComponent(mensagem)}',
    );
  }

  static Future<bool> _abrirUrlExterna(String url) async {
    if (Platform.isWindows) {
      try {
        final r = await Process.run(
          'rundll32',
          ['url.dll,FileProtocolHandler', url],
        );
        if (r.exitCode == 0) return true;
      } catch (_) {}
    }
    final uri = Uri.parse(url);
    try {
      if (await canLaunchUrl(uri)) {
        return launchUrl(uri, mode: LaunchMode.externalApplication);
      }
    } catch (_) {}
    try {
      return launchUrl(uri, mode: LaunchMode.platformDefault);
    } catch (_) {
      return false;
    }
  }

  /// Abre o chat do cliente (wa.me / WhatsApp Desktop / Web).
  static Future<bool> abrirConversa({
    required String telefone,
    required String mensagem,
  }) async {
    final waMe = montarUriWaMe(telefone: telefone, mensagem: mensagem);
    if (waMe == null) return false;

    if (await _abrirUrlExterna(waMe.toString())) return true;

    final phoneClean = higienizarTelefone(telefone);
    final zapApp = Uri.parse(
      'whatsapp://send?phone=$phoneClean&text=${Uri.encodeComponent(mensagem)}',
    );
    if (await _abrirUrlExterna(zapApp.toString())) return true;

    final web = _montarUriWebWhatsapp(telefone: telefone, mensagem: mensagem);
    if (web == null) return false;
    return _abrirUrlExterna(web.toString());
  }

  static String _nomeArquivoSeguro(String nomeArquivo) {
    var nome = nomeArquivo.trim();
    if (nome.isEmpty) nome = 'orcamento.pdf';
    if (!nome.toLowerCase().endsWith('.pdf')) nome = '$nome.pdf';
    return nome.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');
  }

  static Future<String> _salvarPdfParaEnvio({
    required Uint8List pdfBytes,
    required String nomeArquivo,
  }) async {
    Directory destino;
    try {
      destino = await getDownloadsDirectory() ?? await getTemporaryDirectory();
    } catch (_) {
      destino = await getTemporaryDirectory();
    }
    final nomeSeguro = _nomeArquivoSeguro(nomeArquivo);
    final path = p.join(destino.path, nomeSeguro);
    await File(path).writeAsBytes(pdfBytes, flush: true);
    return path;
  }

  static Future<void> _destacarArquivoNoExplorer(String path) async {
    if (!Platform.isWindows) return;
    try {
      await Process.run('explorer', ['/select,', path]);
    } catch (_) {}
  }

  /// Gera PDF, abre chat no numero e destaca arquivo para anexar e enviar.
  static Future<OrcamentoWhatsappEnvioResult> enviarOrcamentoComPdf({
    required Uint8List pdfBytes,
    required String nomeArquivo,
    required String telefone,
    required String mensagem,
  }) async {
    if (higienizarTelefone(telefone).length < 12) {
      return OrcamentoWhatsappEnvioResult.falha(
        'Informe um WhatsApp válido (DDD + número).',
      );
    }
    if (pdfBytes.isEmpty) {
      return OrcamentoWhatsappEnvioResult.falha(
        'Não foi possível gerar o PDF do orçamento.',
      );
    }

    final path = await _salvarPdfParaEnvio(
      pdfBytes: pdfBytes,
      nomeArquivo: nomeArquivo,
    );

    final chatAberto = await abrirConversa(
      telefone: telefone,
      mensagem: mensagem,
    );
    if (!chatAberto) {
      return OrcamentoWhatsappEnvioResult.falha(
        'Não foi possível abrir o WhatsApp no número informado.',
        pdfPath: path,
      );
    }

    await _destacarArquivoNoExplorer(path);

    return OrcamentoWhatsappEnvioResult.ok(
      chatAberto: true,
      pdfPath: path,
    );
  }
}
