import 'dart:io';

import 'sync_api_client.dart';

/// Resultado do teste de rede + token contra o servidor LAN.
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

/// Testa alcance do host, servico de sync e token (via `/sync/meta`).
Future<SyncTesteResultado> testarConexaoSyncLan({
  required String baseUrl,
  required String syncToken,
}) async {
  final client = SyncApiClient(baseUrl: baseUrl, syncToken: syncToken);
  if (!client.configurado) {
    return const SyncTesteResultado(
      servidorAlcancavel: false,
      servicoSyncAtivo: false,
      tokenValido: false,
      mensagem:
          'Servidor local nao encontrado. Informe o endereco '
          '(ex.: 192.168.0.10:8787).',
    );
  }

  final hostPorta = client.hostPorta;
  if (hostPorta == null) {
    return const SyncTesteResultado(
      servidorAlcancavel: false,
      servicoSyncAtivo: false,
      tokenValido: false,
      mensagem: 'Servidor local nao encontrado. Endereco invalido.',
    );
  }

  final host = hostPorta.$1;
  final porta = hostPorta.$2;

  if (await client.health()) {
    return _validarTokenMeta(client, syncToken);
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
        'Servidor local nao encontrado: a porta $host:$porta responde, '
        'mas o servico de sync nao esta ativo. '
        'No PC principal, inicie o servidor em Configuracoes > Rede.',
  );
}

Future<SyncTesteResultado> _validarTokenMeta(
  SyncApiClient client,
  String syncToken,
) async {
  final token = syncToken.trim();
  final comToken = await client.metaStatus(incluirToken: true);
  if (comToken == 200) {
    return SyncTesteResultado(
      servidorAlcancavel: true,
      servicoSyncAtivo: true,
      tokenValido: token.isEmpty ? null : true,
      mensagem: token.isEmpty
          ? 'Servidor OK (sem token no servidor).'
          : 'Servidor OK. Token aceito.',
    );
  }

  if (comToken == 401 || comToken == 403) {
    if (token.isEmpty) {
      return const SyncTesteResultado(
        servidorAlcancavel: true,
        servicoSyncAtivo: true,
        tokenValido: false,
        mensagem:
            'O servidor exige token. Preencha o mesmo token do PC servidor.',
      );
    }
    final semToken = await client.metaStatus(incluirToken: false);
    if (semToken == 200) {
      return const SyncTesteResultado(
        servidorAlcancavel: true,
        servicoSyncAtivo: true,
        tokenValido: false,
        mensagem:
            'Token recusado pelo servidor. Use o mesmo valor do PC servidor.',
      );
    }
    return const SyncTesteResultado(
      servidorAlcancavel: true,
      servicoSyncAtivo: true,
      tokenValido: false,
      mensagem:
          'Token invalido ou ausente. Confira Configuracoes > Rede nos dois PCs.',
    );
  }

  return SyncTesteResultado(
    servidorAlcancavel: true,
    servicoSyncAtivo: true,
    tokenValido: null,
    mensagem: 'Servidor OK. Nao foi possivel validar o token (HTTP $comToken).',
  );
}
