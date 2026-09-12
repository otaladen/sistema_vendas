import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import '../../data/api/lan_api_client.dart';
import '../../data/api/lan_api_event_hub.dart';
import 'operacao_feedback.dart';

/// Tratamento uniforme de falhas da LAN API no Terminal Leve.
///
/// Use em toda escrita/consulta remota para evitar tela quebrada e
/// exibir SnackBar amigavel (offline ou mensagem da API).
abstract final class LanApiFeedback {
  LanApiFeedback._();

  static DateTime? _ultimoSnackRedeEm;
  static String? _ultimoSnackRedeChave;

  static bool _deveSuprimirSnackRede(String chave) {
    final agora = DateTime.now();
    final ultimo = _ultimoSnackRedeEm;
    if (ultimo != null &&
        agora.difference(ultimo) < const Duration(seconds: 20) &&
        _ultimoSnackRedeChave == chave) {
      return true;
    }
    _ultimoSnackRedeEm = agora;
    _ultimoSnackRedeChave = chave;
    return false;
  }

  /// Mensagem legivel para o usuario.
  static String mensagem(Object erro, {String? fallback}) {
    if (erro is LanApiException) {
      final m = erro.message.trim();
      if (m.isNotEmpty) return m;
    }
    final t = '$erro'.trim();
    if (t.isNotEmpty &&
        t != 'Exception' &&
        t != 'null' &&
        !t.startsWith('Instance of')) {
      return t;
    }
    return fallback ?? LanApiEventHub.msgServidorOffline;
  }

  /// SnackBar de erro (vermelho via [OperacaoFeedback] quando possivel).
  static void snackErro(
    BuildContext context,
    Object erro, {
    String? prefixo,
    String? fallback,
  }) {
    if (!context.mounted) return;
    final body = mensagem(erro, fallback: fallback);
    final texto = (prefixo != null && prefixo.trim().isNotEmpty)
        ? '${prefixo.trim()}: $body'
        : body;
    if (ehFalhaRede(erro) && _deveSuprimirSnackRede(texto)) return;
    try {
      OperacaoFeedback.erro(context, texto);
    } catch (_) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(texto),
          duration: const Duration(seconds: 5),
        ),
      );
    }
  }

  /// Aviso (laranja) — ex.: servidor offline sem bloquear a tela.
  static void snackAviso(
    BuildContext context,
    Object erro, {
    String? prefixo,
    String? fallback,
  }) {
    if (!context.mounted) return;
    final body = mensagem(erro, fallback: fallback);
    final texto = (prefixo != null && prefixo.trim().isNotEmpty)
        ? '${prefixo.trim()}: $body'
        : body;
    if (ehFalhaRede(erro) && _deveSuprimirSnackRede(texto)) return;
    try {
      OperacaoFeedback.aviso(context, texto);
    } catch (_) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(texto)),
      );
    }
  }

  /// Falha de rede tipica no Modo Motorista (4G / Tailscale).
  static void snackRedeMotorista(BuildContext context, [Object? erro]) {
    if (!context.mounted) return;
    final detalhe = erro == null ? '' : mensagem(erro);
    final texto = detalhe.isEmpty ||
            detalhe == LanApiClient.msgRedeInstavelMotorista
        ? LanApiClient.msgRedeInstavelMotorista
        : '${LanApiClient.msgRedeInstavelMotorista}\n($detalhe)';
    try {
      OperacaoFeedback.aviso(context, texto);
    } catch (_) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(texto),
          duration: const Duration(seconds: 6),
        ),
      );
    }
  }

  /// True se o erro parece falha de rede / timeout (nao regra de negocio).
  static bool ehFalhaRede(Object erro) {
    if (erro is TimeoutException) return true;
    if (erro is SocketException) return true;
    if (erro is http.ClientException) return true;
    if (erro is LanApiException) {
      final c = erro.cause;
      if (c is TimeoutException ||
          c is SocketException ||
          c is http.ClientException) {
        return true;
      }
      final m = erro.message.toLowerCase();
      return m.contains('sem conexao') ||
          m.contains('tempo esgotado') ||
          m.contains('falha de rede') ||
          m.contains('tailscale') ||
          m.contains('socket');
    }
    final t = '$erro'.toLowerCase();
    return t.contains('socket') ||
        t.contains('timeout') ||
        t.contains('connection');
  }

  /// Executa [acao]; em falha mostra SnackBar e retorna null (nao propaga).
  static Future<T?> guardar<T>(
    BuildContext context,
    Future<T> Function() acao, {
    String? prefixo,
    VoidCallback? onError,
  }) async {
    try {
      return await acao();
    } on LanApiException catch (e) {
      snackErro(context, e, prefixo: prefixo);
      onError?.call();
      return null;
    } catch (e) {
      snackErro(context, e, prefixo: prefixo);
      onError?.call();
      return null;
    }
  }
}
