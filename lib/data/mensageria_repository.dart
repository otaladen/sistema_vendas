import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../model/cliente.dart';
import '../model/mensagem_fila.dart';
import '../model/mensagem_log.dart';
import '../model/mensagem_template.dart';
import '../model/venda.dart';
import 'app_config_repository.dart';
import 'sync/sync_write_trigger.dart';

class MensageriaRepository {
  static const _kTemplates = 'mensageria_templates_v1';
  static const _kFila = 'mensageria_fila_v1';
  static const _kLogs = 'mensageria_logs_v1';

  MensageriaRepository() : _appConfigRepository = AppConfigRepository();

  final AppConfigRepository _appConfigRepository;

  Future<List<MensagemTemplate>> listarTemplates() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_kTemplates);
    if (raw == null || raw.trim().isEmpty) return [];
    final decoded = jsonDecode(raw);
    if (decoded is! List) return [];
    final lista = decoded
        .whereType<Map>()
        .map((e) => MensagemTemplate.fromMap(e.cast<String, dynamic>()))
        .toList();
    lista.sort((a, b) => a.nome.toLowerCase().compareTo(b.nome.toLowerCase()));
    return lista;
  }

  Future<void> salvarTemplate(MensagemTemplate template) async {
    final lista = await listarTemplates();
    final idx = lista.indexWhere((t) => t.id == template.id);
    if (idx >= 0) {
      lista[idx] = template;
    } else {
      lista.add(template);
    }
    await _persistirTemplates(lista);
    notificarAlteracaoParaRede();
  }

  Future<void> removerTemplate(String templateId) async {
    final lista = await listarTemplates();
    lista.removeWhere((t) => t.id == templateId);
    await _persistirTemplates(lista);
    notificarAlteracaoParaRede();
  }

  Future<List<MensagemFila>> listarFila() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_kFila);
    if (raw == null || raw.trim().isEmpty) return [];
    final decoded = jsonDecode(raw);
    if (decoded is! List) return [];
    final lista = decoded
        .whereType<Map>()
        .map((e) => MensagemFila.fromMap(e.cast<String, dynamic>()))
        .toList();
    lista.sort((a, b) => b.criadaEm.compareTo(a.criadaEm));
    return lista;
  }

  Future<List<MensagemLog>> listarLogs() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_kLogs);
    if (raw == null || raw.trim().isEmpty) return [];
    final decoded = jsonDecode(raw);
    if (decoded is! List) return [];
    final lista = decoded
        .whereType<Map>()
        .map((e) => MensagemLog.fromMap(e.cast<String, dynamic>()))
        .toList();
    lista.sort((a, b) => b.criadoEm.compareTo(a.criadoEm));
    return lista;
  }

  Future<List<MensagemLog>> listarLogsPorCliente(int clienteId) async {
    final logs = await listarLogs();
    return logs.where((log) => log.clienteId == clienteId).toList();
  }

  Future<List<MensagemLog>> filtrarLogs({
    String statusEntrega = 'todos',
    String canal = 'todos',
    String texto = '',
  }) async {
    final logs = await listarLogs();
    final termo = texto.trim().toLowerCase();
    return logs.where((log) {
      if (statusEntrega != 'todos' && log.statusEntrega != statusEntrega) {
        return false;
      }
      if (canal != 'todos' && log.canal != canal) {
        return false;
      }
      if (termo.isEmpty) return true;
      return log.destino.toLowerCase().contains(termo) ||
          log.templateId.toLowerCase().contains(termo) ||
          log.responseJson.toLowerCase().contains(termo);
    }).toList();
  }

  Future<({int total, int enviados, int entregues, int lidos, int falhas})>
  resumoDashboard() async {
    final logs = await listarLogs();
    final total = logs.length;
    final enviados = logs.where((l) => l.resultado == 'enviado').length;
    final entregues = logs.where((l) => l.statusEntrega == 'entregue').length;
    final lidos = logs.where((l) => l.statusEntrega == 'lido').length;
    final falhas = logs.where((l) => l.resultado == 'falhou').length;
    return (
      total: total,
      enviados: enviados,
      entregues: entregues,
      lidos: lidos,
      falhas: falhas,
    );
  }

  Future<void> enfileirarMensagem({
    required int clienteId,
    required String templateId,
    required String destino,
    required Map<String, String> variaveis,
  }) async {
    final templates = await listarTemplates();
    final template = templates.where((t) => t.id == templateId).firstOrNull;
    if (template == null || !template.ativo) {
      return;
    }
    final fila = await listarFila();
    final payload = {
      'texto': _renderTexto(template.textoBase, variaveis),
      'variaveis': variaveis,
    };
    fila.add(
      MensagemFila(
        id: _id(),
        clienteId: clienteId,
        templateId: templateId,
        canal: template.canal,
        destino: destino,
        payloadJson: jsonEncode(payload),
        criadaEm: DateTime.now(),
        proximaTentativaEm: DateTime.now(),
      ),
    );
    await _persistirFila(fila);
  }

  Future<void> enfileirarAgradecimentoVenda({
    required Venda venda,
    required Cliente cliente,
  }) async {
    final templates = await listarTemplates();
    final template = templates
        .where((t) => t.ativo && t.evento == 'venda_finalizada')
        .firstOrNull;
    if (template == null) return;
    final telefone = _normalizarDestinoWhatsapp(cliente.whatsapp, cliente.telefone);
    if (telefone.isEmpty) return;
    await enfileirarMensagem(
      clienteId: cliente.id,
      templateId: template.id,
      destino: telefone,
      variaveis: {
        'cliente_nome': cliente.nomeRazao.trim(),
        'numero_orcamento': venda.numeroOrcamento.toString(),
        'valor_total': venda.total.toStringAsFixed(2).replaceAll('.', ','),
      },
    );
  }

  Future<int> processarFilaPendente({int limite = 20}) async {
    final fila = await listarFila();
    final templates = await listarTemplates();
    final logs = await listarLogs();
    final agora = DateTime.now();
    var processadas = 0;
    for (var i = 0; i < fila.length; i++) {
      final item = fila[i];
      if (processadas >= limite) break;
      if (item.status == 'enviado' || item.status == 'cancelado') continue;
      final proxima = item.proximaTentativaEm;
      if (proxima != null && proxima.isAfter(agora)) continue;
      final template = templates.where((t) => t.id == item.templateId).firstOrNull;
      if (template == null || !template.ativo) {
        fila[i] = item.copyWith(
          status: 'falhou',
          tentativas: item.tentativas + 1,
          erroUltimo: 'Template inexistente/inativo',
        );
        logs.add(
          MensagemLog(
            id: _id(),
            clienteId: item.clienteId,
            filaId: item.id,
            templateId: item.templateId,
            canal: item.canal,
            destino: item.destino,
            requestJson: item.payloadJson,
            responseJson: '{"erro":"Template inexistente/inativo"}',
            resultado: 'falhou',
            criadoEm: DateTime.now(),
          ),
        );
        processadas++;
        continue;
      }
      final tentativa = item.tentativas + 1;
      final envio = await _enviarMensagem(template: template, item: item);
      final providerMessageId = _extrairProviderMessageId(envio.resposta);
      if (envio.sucesso) {
        fila[i] = item.copyWith(
          status: 'enviado',
          tentativas: tentativa,
          enviadaEm: DateTime.now(),
          erroUltimo: '',
        );
      } else {
        final atrasoMinutos = tentativa == 1 ? 2 : 10;
        fila[i] = item.copyWith(
          status: tentativa >= 3 ? 'falhou' : 'pendente',
          tentativas: tentativa,
          erroUltimo: envio.resposta,
          proximaTentativaEm: tentativa >= 3
              ? null
              : DateTime.now().add(Duration(minutes: atrasoMinutos)),
        );
      }
      logs.add(
        MensagemLog(
          id: _id(),
          clienteId: item.clienteId,
          filaId: item.id,
          templateId: item.templateId,
          canal: item.canal,
          destino: item.destino,
          requestJson: item.payloadJson,
          responseJson: envio.resposta,
          statusHttp: envio.statusHttp,
          resultado: envio.sucesso ? 'enviado' : 'falhou',
          statusEntrega: envio.sucesso ? 'aceito_api' : 'falhou',
          providerMessageId: providerMessageId,
          criadoEm: DateTime.now(),
        ),
      );
      processadas++;
    }
    await _persistirFila(fila);
    await _persistirLogs(logs);
    return processadas;
  }

  Future<void> reenfileirarFalha(String filaId) async {
    final fila = await listarFila();
    final idx = fila.indexWhere((f) => f.id == filaId);
    if (idx < 0) return;
    final atual = fila[idx];
    fila[idx] = atual.copyWith(
      status: 'pendente',
      erroUltimo: '',
      proximaTentativaEm: DateTime.now(),
    );
    await _persistirFila(fila);
  }

  Future<({bool sucesso, String resposta, int statusHttp})> testarBackend({
    required String backendUrl,
    String canal = 'whatsapp',
    String destino = '5599999999999',
  }) async {
    final url = backendUrl.trim();
    if (url.isEmpty) {
      return (sucesso: false, resposta: '{"erro":"Backend URL nao informada"}', statusHttp: 0);
    }
    try {
      final uri = Uri.parse(url);
      final response = await http.post(
        uri,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'canal': canal,
          'destino': destino,
          'templateId': 'teste_backend',
          'templateName': '',
          'idioma': 'pt_BR',
          'payload': {
            'messaging_product': 'whatsapp',
            'to': destino,
            'type': 'text',
            'text': {'body': 'Teste de integracao do Sistema de Vendas.'},
          },
          'meta': {'origin': 'sistema_vendas_desktop', 'test': true},
        }),
      );
      return (
        sucesso: response.statusCode >= 200 && response.statusCode < 300,
        resposta: response.body,
        statusHttp: response.statusCode,
      );
    } catch (e) {
      return (
        sucesso: false,
        resposta: '{"erro":"$e"}',
        statusHttp: 0,
      );
    }
  }

  Future<_EnvioResultado> _enviarMensagem({
    required MensagemTemplate template,
    required MensagemFila item,
  }) async {
    if (template.canal == 'sms') {
      return const _EnvioResultado(
        sucesso: false,
        resposta: '{"erro":"Canal SMS ainda nao configurado"}',
        statusHttp: 0,
      );
    }
    final config = await _appConfigRepository.carregarEmpresaConfig();
    final backendUrl = config.mensageriaBackendUrl.trim();
    final payloadMap = jsonDecode(item.payloadJson) as Map<String, dynamic>;
    final texto = payloadMap['texto'] as String? ?? '';
    final body = template.metaTemplateName.trim().isNotEmpty
        ? {
            'messaging_product': 'whatsapp',
            'to': item.destino,
            'type': 'template',
            'template': {
              'name': template.metaTemplateName.trim(),
              'language': {'code': template.idioma.trim()},
            },
          }
        : {
            'messaging_product': 'whatsapp',
            'to': item.destino,
            'type': 'text',
            'text': {'body': texto},
          };
    if (backendUrl.isNotEmpty) {
      try {
        final uri = Uri.parse(backendUrl);
        final response = await http.post(
          uri,
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({
            'canal': template.canal,
            'destino': item.destino,
            'templateId': template.id,
            'templateName': template.metaTemplateName,
            'idioma': template.idioma,
            'payload': body,
          }),
        );
        return _EnvioResultado(
          sucesso: response.statusCode >= 200 && response.statusCode < 300,
          resposta: response.body,
          statusHttp: response.statusCode,
        );
      } catch (e) {
        return _EnvioResultado(
          sucesso: false,
          resposta: '{"erro":"$e"}',
          statusHttp: 0,
        );
      }
    }
    final apiVersion = config.whatsappApiVersion.trim();
    final phoneId = config.whatsappPhoneNumberId.trim();
    final token = config.whatsappAccessToken.trim();
    if (apiVersion.isEmpty || phoneId.isEmpty || token.isEmpty) {
      return const _EnvioResultado(
        sucesso: false,
        resposta: '{"erro":"WhatsApp Cloud API nao configurada"}',
        statusHttp: 0,
      );
    }
    final uri = Uri.parse('https://graph.facebook.com/$apiVersion/$phoneId/messages');
    try {
      final response = await http.post(
        uri,
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
        },
        body: jsonEncode(body),
      );
      return _EnvioResultado(
        sucesso: response.statusCode >= 200 && response.statusCode < 300,
        resposta: response.body,
        statusHttp: response.statusCode,
      );
    } catch (e) {
      return _EnvioResultado(
        sucesso: false,
        resposta: '{"erro":"$e"}',
        statusHttp: 0,
      );
    }
  }

  String _normalizarDestinoWhatsapp(String whatsapp, String telefone) {
    final origem = whatsapp.trim().isNotEmpty ? whatsapp.trim() : telefone.trim();
    var digits = origem.replaceAll(RegExp(r'\D'), '');
    // Normaliza para formato E.164 simplificado sem "+" (Brasil):
    // - 10/11 digitos -> assume DDD+número local e prefixa 55
    // - 12/13 digitos iniciando com 55 -> mantém
    // - remove prefixo 0 de longa distância quando presente
    if (digits.startsWith('0')) {
      digits = digits.replaceFirst(RegExp(r'^0+'), '');
    }
    if (digits.length == 10 || digits.length == 11) {
      digits = '55$digits';
    }
    return digits;
  }

  String _extrairProviderMessageId(String resposta) {
    try {
      final json = jsonDecode(resposta);
      if (json is Map<String, dynamic>) {
        final messages = json['messages'];
        if (messages is List && messages.isNotEmpty) {
          final first = messages.first;
          if (first is Map<String, dynamic>) {
            return first['id'] as String? ?? '';
          }
        }
      }
    } catch (_) {}
    return '';
  }

  Future<int> processarWebhookWhatsappPayload(String rawPayload) async {
    Map<String, dynamic> payload;
    try {
      final decoded = jsonDecode(rawPayload);
      if (decoded is! Map<String, dynamic>) return 0;
      payload = decoded;
    } catch (_) {
      return 0;
    }
    final logs = await listarLogs();
    var atualizados = 0;
    final entries = payload['entry'];
    if (entries is! List) return 0;
    for (final entry in entries) {
      if (entry is! Map<String, dynamic>) continue;
      final changes = entry['changes'];
      if (changes is! List) continue;
      for (final change in changes) {
        if (change is! Map<String, dynamic>) continue;
        final value = change['value'];
        if (value is! Map<String, dynamic>) continue;
        final statuses = value['statuses'];
        if (statuses is! List) continue;
        for (final statusObj in statuses) {
          if (statusObj is! Map<String, dynamic>) continue;
          final messageId = statusObj['id'] as String? ?? '';
          final status = statusObj['status'] as String? ?? '';
          if (messageId.isEmpty || status.isEmpty) continue;
          final idx = logs.indexWhere((log) => log.providerMessageId == messageId);
          if (idx < 0) continue;
          final antigo = logs[idx];
          final novoResultado = status == 'failed' ? 'falhou' : antigo.resultado;
          logs[idx] = antigo.copyWith(
            statusEntrega: _mapearStatusWebhook(status),
            resultado: novoResultado,
            responseJson: antigo.responseJson,
          );
          atualizados++;
        }
      }
    }
    if (atualizados > 0) {
      await _persistirLogs(logs);
    }
    return atualizados;
  }

  String _mapearStatusWebhook(String status) {
    switch (status) {
      case 'sent':
        return 'enviado';
      case 'delivered':
        return 'entregue';
      case 'read':
        return 'lido';
      case 'failed':
        return 'falhou';
      default:
        return status;
    }
  }

  String _renderTexto(String base, Map<String, String> variaveis) {
    var texto = base;
    variaveis.forEach((chave, valor) {
      texto = texto.replaceAll('{{$chave}}', valor);
    });
    return texto;
  }

  Future<void> _persistirTemplates(List<MensagemTemplate> templates) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _kTemplates,
      jsonEncode(templates.map((e) => e.toMap()).toList()),
    );
  }

  Future<void> _persistirFila(List<MensagemFila> fila) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kFila, jsonEncode(fila.map((e) => e.toMap()).toList()));
  }

  Future<void> _persistirLogs(List<MensagemLog> logs) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kLogs, jsonEncode(logs.map((e) => e.toMap()).toList()));
  }

  String _id() => '${DateTime.now().microsecondsSinceEpoch}_${_rand4()}';

  String _rand4() {
    final n = DateTime.now().millisecondsSinceEpoch % 10000;
    return n.toString().padLeft(4, '0');
  }
}

class _EnvioResultado {
  const _EnvioResultado({
    required this.sucesso,
    required this.resposta,
    required this.statusHttp,
  });

  final bool sucesso;
  final String resposta;
  final int statusHttp;
}
