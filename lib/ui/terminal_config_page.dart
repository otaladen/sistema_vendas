import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../services/configuracoes_service.dart';
import '../../data/api/lan_api_url.dart';
import '../../data/api/lan_conexao_perfis.dart';

/// Tela minima: cliente Windows/Android sem URL do servidor (sem bootstrap ObjectBox).
class TerminalConfigPage extends StatefulWidget {
  const TerminalConfigPage({
    super.key,
    required this.configuracoesService,
    required this.onSalvo,
    required this.onLogout,
    this.erroConexao,
  });

  final ConfiguracoesService configuracoesService;
  final Future<void> Function() onSalvo;
  final VoidCallback onLogout;

  /// Erro da tentativa anterior de conectar (ex.: API offline / token).
  final String? erroConexao;

  @override
  State<TerminalConfigPage> createState() => _TerminalConfigPageState();
}

class _TerminalConfigPageState extends State<TerminalConfigPage> {
  final _urlCtrl = TextEditingController();
  final _tokenCtrl = TextEditingController();
  bool _salvando = false;
  bool _revertendo = false;
  String? _erro;
  LanConexaoPerfil _perfil = LanConexaoPerfil.wifiLoja;

  @override
  void initState() {
    super.initState();
    _erro = widget.erroConexao;
    unawaited(_carregar());
  }

  @override
  void didUpdateWidget(covariant TerminalConfigPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.erroConexao != oldWidget.erroConexao &&
        widget.erroConexao != null) {
      _erro = widget.erroConexao;
    }
  }

  Future<void> _carregar() async {
    final c = await widget.configuracoesService.carregarEfetiva();
    final raw = c.redeServidorUrl.trim();
    await LanConexaoPerfisStore.migrarSeVazio(raw);
    final perfil = await LanConexaoPerfisStore.perfilAtivo();
    var urlPerfil = await LanConexaoPerfisStore.urlDoPerfil(perfil);
    if (urlPerfil.isEmpty && raw.isNotEmpty) {
      urlPerfil = LanApiUrl.fromSyncUrl(raw);
    }
    if (!mounted) return;
    setState(() {
      _perfil = perfil;
      _urlCtrl.text = urlPerfil;
      _tokenCtrl.text = c.redeSyncToken;
    });
  }

  Future<void> _trocarPerfil(LanConexaoPerfil novo) async {
    if (novo == _perfil) return;
    // Guarda o que esta digitado no perfil atual antes de trocar.
    final digitado = _urlCtrl.text.trim();
    if (digitado.isNotEmpty) {
      await LanConexaoPerfisStore.salvarUrlPerfil(_perfil, digitado);
    }
    await LanConexaoPerfisStore.setPerfilAtivo(novo);
    final url = await LanConexaoPerfisStore.urlDoPerfil(novo);
    if (!mounted) return;
    setState(() {
      _perfil = novo;
      _urlCtrl.text = url;
      _erro = null;
    });
  }

  Future<void> _salvar() async {
    setState(() {
      _salvando = true;
      _erro = null;
    });
    try {
      var url = _urlCtrl.text.trim();
      if (url.isEmpty) {
        throw StateError('Informe o endereco do PC servidor.');
      }
      // Sempre normaliza para http://host:8788
      final apiUrl = LanApiUrl.fromSyncUrl(url);
      if (apiUrl.isEmpty) {
        throw StateError('URL invalida. Ex.: 192.168.0.10 ou 100.64.1.2');
      }
      await LanConexaoPerfisStore.salvarUrlPerfil(_perfil, apiUrl);
      await LanConexaoPerfisStore.setPerfilAtivo(_perfil);
      final c = await widget.configuracoesService.carregarEfetiva();
      await widget.configuracoesService.salvarEfetiva(
        c.copyWith(
          redeSincronizacaoAtiva: true,
          redeModoServidor: false,
          redeServidorUrl: apiUrl,
          redeSyncToken: _tokenCtrl.text.trim(),
        ),
        propagarRede: false,
      );
      if (!mounted) return;
      setState(() => _urlCtrl.text = apiUrl);
      await widget.onSalvo();
    } catch (e) {
      if (!mounted) return;
      setState(() => _erro = '$e');
    } finally {
      if (mounted) setState(() => _salvando = false);
    }
  }

  /// Sai do Terminal Leve e volta ao ERP com banco local (dev ou celular offline).
  Future<void> _voltarModoNormal() async {
    final ehMobile = !kIsWeb && (Platform.isAndroid || Platform.isIOS);
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(
          ehMobile ? 'Usar modo local no celular?' : 'Voltar ao modo normal?',
        ),
        content: Text(
          ehMobile
              ? 'O celular deixa de depender do PC servidor e volta a usar '
                  'banco local neste aparelho (sem ver o estoque da loja em tempo real).\n\n'
                  'Feche e abra o app de novo apos confirmar.'
              : 'Este PC deixa de ser Terminal Leve e volta a usar o banco local '
                  '(ObjectBox), como servidor/ERP completo.\n\n'
                  'O app sera fechado — rode flutter run -d windows de novo.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(ehMobile ? 'Usar modo local' : 'Voltar ao normal'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;

    setState(() {
      _revertendo = true;
      _erro = null;
    });
    try {
      final c = await widget.configuracoesService.carregarEfetiva();
      await widget.configuracoesService.salvarEfetiva(
        c.copyWith(
          // Celular: desliga rede → proximo boot abre ObjectBox local.
          // Windows: marca servidor para sair do Terminal Leve.
          redeSincronizacaoAtiva: ehMobile ? false : c.redeSincronizacaoAtiva,
          redeModoServidor: ehMobile ? false : true,
        ),
        propagarRede: false,
      );
      if (!kIsWeb &&
          (Platform.isWindows || Platform.isLinux || Platform.isMacOS)) {
        exit(0);
      }
      if (ehMobile) {
        await SystemNavigator.pop();
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _revertendo = false;
        _erro =
            'Nao foi possivel sair do Terminal Leve: $e\n'
            'Feche o app completamente e abra de novo.';
      });
    }
  }

  @override
  void dispose() {
    _urlCtrl.dispose();
    _tokenCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final ocupado = _salvando || _revertendo;
    final ehMobile = !kIsWeb && (Platform.isAndroid || Platform.isIOS);
    return Scaffold(
      appBar: AppBar(
        title: Text(
          ehMobile
              ? 'Conectar ao servidor'
              : 'Terminal leve — conectar ao servidor',
        ),
        actions: [
          TextButton(
            onPressed: ocupado ? null : widget.onLogout,
            child: const Text('Sair'),
          ),
        ],
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 480),
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  ehMobile
                      ? 'Este celular nao guarda o banco da loja: le e grava '
                          'direto no PC servidor (API porta ${LanApiUrl.portaPadrao}), '
                          'igual aos terminais Windows.\n\n'
                          'Se o servidor ou a rede cair, o app para. '
                          'Na rua use Tailscale (4G); na loja use Wi-Fi local.'
                      : 'Este PC nao guarda banco local. Conecte na API do PC servidor '
                          '(porta ${LanApiUrl.portaPadrao}).\n\n'
                          'Depois de conectar, o login usa somente usuarios cadastrados '
                          'no PC servidor.',
                ),
                const SizedBox(height: 16),
                Text(
                  'Perfil de conexao',
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                ),
                const SizedBox(height: 8),
                SegmentedButton<LanConexaoPerfil>(
                  segments: const [
                    ButtonSegment(
                      value: LanConexaoPerfil.wifiLoja,
                      icon: Icon(Icons.home_outlined, size: 18),
                      label: Text('Wi-Fi Loja'),
                      tooltip: 'Wi-Fi Loja (Local)',
                    ),
                    ButtonSegment(
                      value: LanConexaoPerfil.tailscale4g,
                      icon: Icon(Icons.local_shipping_outlined, size: 18),
                      label: Text('Tailscale 4G'),
                      tooltip: 'Rede Externa (Tailscale 4G)',
                    ),
                  ],
                  selected: {_perfil},
                  onSelectionChanged: ocupado
                      ? null
                      : (s) => unawaited(_trocarPerfil(s.first)),
                ),
                const SizedBox(height: 8),
                Text(
                  _perfil == LanConexaoPerfil.tailscale4g
                      ? 'Use o IP Tailscale do PC servidor (100.x.x.x). '
                          'Ative o app Tailscale no celular antes de conectar.'
                      : 'Use o IP Wi-Fi do PC servidor (192.168.x.x). '
                          'Nao use o IP do roteador (em geral .1).',
                  style: TextStyle(color: cs.onSurfaceVariant, fontSize: 13),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: _urlCtrl,
                  enabled: !ocupado,
                  keyboardType: TextInputType.url,
                  autocorrect: false,
                  decoration: InputDecoration(
                    labelText: 'URL / IP da API do servidor',
                    hintText: LanConexaoPerfisStore.hint(_perfil),
                    helperText:
                        'Porta ${LanApiUrl.portaPadrao} e adicionada se omitida.',
                    border: const OutlineInputBorder(),
                    prefixIcon: Icon(
                      _perfil == LanConexaoPerfil.tailscale4g
                          ? Icons.cloud_outlined
                          : Icons.wifi,
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _tokenCtrl,
                  enabled: !ocupado,
                  decoration: const InputDecoration(
                    labelText: 'Token da rede',
                    border: OutlineInputBorder(),
                  ),
                ),
                if (_erro != null) ...[
                  const SizedBox(height: 12),
                  Material(
                    color: cs.errorContainer,
                    borderRadius: BorderRadius.circular(8),
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Text(
                        _erro!,
                        style: TextStyle(color: cs.onErrorContainer),
                      ),
                    ),
                  ),
                ],
                const SizedBox(height: 20),
                FilledButton(
                  onPressed: ocupado ? null : _salvar,
                  child: Text(_salvando ? 'Conectando...' : 'Conectar'),
                ),
                const SizedBox(height: 12),
                OutlinedButton.icon(
                  onPressed: ocupado ? null : _voltarModoNormal,
                  icon: Icon(
                    ehMobile
                        ? Icons.phone_android_outlined
                        : Icons.computer_outlined,
                  ),
                  label: Text(
                    _revertendo
                        ? 'Revertendo...'
                        : ehMobile
                            ? 'Usar modo local neste celular'
                            : 'Este PC e o servidor — sair do Terminal Leve',
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  ehMobile
                      ? 'So use o botao acima se quiser voltar ao banco local '
                          'deste aparelho (sem ver a loja em tempo real).'
                      : 'Use o botao acima no PC de desenvolvimento/teste quando '
                          'mudou para Terminal Leve por engano e precisa voltar ao ERP local.',
                  style: TextStyle(color: cs.onSurfaceVariant, fontSize: 12),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
