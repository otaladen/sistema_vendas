import 'dart:io';

import '../api/lan_api_url.dart';
import 'sync_auth.dart';
import '../../services/lan_rede_helper.dart';

/// Resultado do teste de rede + token contra a API do servidor (:8788).
class SyncTesteResultado {
  const SyncTesteResultado({
    required this.servidorAlcancavel,
    required this.servicoSyncAtivo,
    this.tokenValido,
    this.mensagem,
  });

  final bool servidorAlcancavel;
  final bool servicoSyncAtivo;
  /// `null` = servidor sem exigencia de token; `true`/`false` = validacao feita.
  final bool? tokenValido;
  final String? mensagem;

  bool get sucesso =>
      servidorAlcancavel &&
      servicoSyncAtivo &&
      (tokenValido ?? true);
}

/// Testa alcance do host e da API de terminais (`/api/health`).
Future<SyncTesteResultado> testarConexaoSyncLan({
  required String baseUrl,
  required String syncToken,
}) async {
  final apiUrl = LanApiUrl.fromSyncUrl(baseUrl);
  if (apiUrl.isEmpty) {
    return const SyncTesteResultado(
      servidorAlcancavel: false,
      servicoSyncAtivo: false,
      tokenValido: false,
      mensagem:
          'Servidor local nao encontrado. Informe o endereco '
          '(ex.: 192.168.0.10:${LanApiUrl.portaPadrao}).',
    );
  }

  final u = Uri.tryParse(apiUrl);
  final host = u?.host.trim() ?? '';
  final porta = u?.port ?? LanApiUrl.portaPadrao;
  if (host.isEmpty) {
    return const SyncTesteResultado(
      servidorAlcancavel: false,
      servicoSyncAtivo: false,
      tokenValido: false,
      mensagem: 'Servidor local nao encontrado. Endereco invalido.',
    );
  }

  final healthOk = await LanRedeHelper.apiRespondendo(
    baseUrl: apiUrl,
    porta: porta,
    syncToken: syncToken,
  );
  if (healthOk) {
    return SyncTesteResultado(
      servidorAlcancavel: true,
      servicoSyncAtivo: true,
      tokenValido: syncToken.trim().isEmpty ? null : true,
      mensagem: 'API do servidor OK em $host:$porta.',
    );
  }

  try {
    await Socket.connect(host, porta, timeout: const Duration(seconds: 6));
  } on SocketException catch (e) {
    return SyncTesteResultado(
      servidorAlcancavel: false,
      servicoSyncAtivo: false,
      tokenValido: false,
      mensagem:
          'Servidor local nao encontrado em $host:$porta. '
          'Verifique se o PC servidor esta ligado, na mesma rede, '
          'e se o IP nao mudou (DHCP). (${e.message})',
    );
  }

  return SyncTesteResultado(
    servidorAlcancavel: true,
    servicoSyncAtivo: false,
    tokenValido: false,
    mensagem:
        'A porta $host:$porta responde, mas a API de terminais nao esta ativa. '
        'No PC servidor, ative a rede local em Configuracoes > Rede e '
        'deixe o programa aberto (ou "Servidor ao ligar o PC"). '
        'Cabecalho ${SyncAuth.headerName} precisa ser o mesmo token.',
  );
}
