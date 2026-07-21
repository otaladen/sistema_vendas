import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';

import '../data/app_config_repository.dart';
import '../data/objectbox.dart';
import '../data/sync/sync_primeira_carga.dart';
import '../data/sync/sync_service.dart';

/// Tela obrigatoria de bootstrap: bloqueia menu/PDV ate o pull inicial concluir.
class PrimeiraCargaPage extends StatefulWidget {
  const PrimeiraCargaPage({
    super.key,
    required this.objectBox,
    required this.syncService,
    required this.appConfigRepository,
    required this.onConcluido,
    this.onLogout,
  });

  final ObjectBox objectBox;
  final SyncService syncService;
  final AppConfigRepository appConfigRepository;
  final VoidCallback onConcluido;
  final VoidCallback? onLogout;

  @override
  State<PrimeiraCargaPage> createState() => _PrimeiraCargaPageState();
}

class _PrimeiraCargaPageState extends State<PrimeiraCargaPage> {
  SyncPrimeiraCargaProgresso _progresso = const SyncPrimeiraCargaProgresso();
  bool _rodando = false;
  final _urlController = TextEditingController();
  final _tokenController = TextEditingController();
  String _nomeLoja = 'Sistema de Vendas';
  String? _logoPath;

  @override
  void initState() {
    super.initState();
    unawaited(_prepararEIniciar());
  }

  @override
  void dispose() {
    _urlController.dispose();
    _tokenController.dispose();
    super.dispose();
  }

  Future<void> _prepararEIniciar() async {
    final config = await widget.appConfigRepository.carregarEmpresaConfig();
    if (!mounted) return;
    setState(() {
      _nomeLoja =
          config.nomeLoja.trim().isEmpty ? 'Sistema de Vendas' : config.nomeLoja.trim();
      _logoPath = config.logoPath.trim().isEmpty ? null : config.logoPath.trim();
      _urlController.text = config.redeServidorUrl;
      _tokenController.text = config.redeSyncToken;
    });

    if (!config.redeSincronizacaoAtiva || config.redeServidorUrl.trim().isEmpty) {
      setState(() {
        _progresso = const SyncPrimeiraCargaProgresso(
          mensagem:
              'Configure o endereco do PC servidor da loja para baixar o banco.',
        );
      });
      return;
    }

    await _iniciarCarga();
  }

  Future<void> _salvarRedeEIniciar() async {
    final url = _urlController.text.trim();
    if (url.isEmpty) {
      setState(() {
        _progresso = const SyncPrimeiraCargaProgresso(
          mensagem: 'Informe a URL do servidor (ex.: http://192.168.0.10:8787).',
          erro: 'URL obrigatoria',
        );
      });
      return;
    }
    final atual = await widget.appConfigRepository.carregarEmpresaConfig();
    await widget.appConfigRepository.salvarEmpresaConfig(
      atual.copyWith(
        redeSincronizacaoAtiva: true,
        redeModoServidor: false,
        redeServidorUrl: url,
        redeSyncToken: _tokenController.text.trim(),
      ),
    );
    await _iniciarCarga();
  }

  Future<void> _iniciarCarga() async {
    if (_rodando) return;
    setState(() {
      _rodando = true;
      _progresso = const SyncPrimeiraCargaProgresso(
        mensagem: 'Sincronizando banco de dados inicial da loja... Mantenha o app aberto.',
      );
    });

    final erro = await widget.syncService.executarBootstrapInicial(
      onProgresso: (p) {
        if (!mounted) return;
        setState(() => _progresso = p);
      },
    );

    if (!mounted) return;

    if (erro != null) {
      setState(() {
        _rodando = false;
        _progresso = _progresso.copyWith(
          mensagem: erro,
          erro: erro,
          concluido: false,
        );
      });
      return;
    }

    setState(() {
      _rodando = false;
      _progresso = _progresso.copyWith(concluido: true);
    });

    await Future<void>.delayed(const Duration(milliseconds: 450));
    if (!mounted) return;
    widget.onConcluido();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final pct = _progresso.percentual.clamp(0, 100);
    final fracao = (pct / 100).clamp(0.0, 1.0);
    final precisaUrl = !_rodando &&
        (_progresso.erro != null ||
            _progresso.mensagem.contains('Configure') ||
            _progresso.mensagem.contains('Informe'));

    return PopScope(
      canPop: false,
      child: Scaffold(
        body: SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 440),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 24),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    _buildLogo(scheme),
                    const SizedBox(height: 20),
                    Text(
                      _nomeLoja,
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      'Sincronizando banco de dados inicial da loja...\nMantenha o app aberto.',
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            color: scheme.onSurfaceVariant,
                            height: 1.35,
                          ),
                    ),
                    const SizedBox(height: 28),
                    Text(
                      '${pct.toStringAsFixed(0)}%',
                      style: Theme.of(context).textTheme.displaySmall?.copyWith(
                            fontWeight: FontWeight.w800,
                            color: scheme.primary,
                          ),
                    ),
                    const SizedBox(height: 12),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: LinearProgressIndicator(
                        value: _rodando || _progresso.concluido ? fracao : null,
                        minHeight: 10,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      _progresso.produtosLocais > 0
                          ? '${_progresso.produtosLocais} produtos no aparelho'
                          : (_rodando
                              ? 'Baixando registros da loja...'
                              : _progresso.mensagem),
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      _progresso.mensagem,
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: _progresso.erro != null
                                ? scheme.error
                                : scheme.onSurfaceVariant,
                          ),
                    ),
                    if (_progresso.pagina > 0) ...[
                      const SizedBox(height: 6),
                      Text(
                        'Pagina ${_progresso.pagina}'
                        '${_progresso.registrosAcumulados > 0 ? ' · ${_progresso.registrosAcumulados} registros' : ''}'
                        '${_progresso.revisionLocal > 0 ? ' · rev ${_progresso.revisionLocal}' : ''}'
                        '${_progresso.revisionRemota != null && _progresso.revisionRemota! > 0 ? '/${_progresso.revisionRemota}' : ''}',
                        style: Theme.of(context).textTheme.labelSmall?.copyWith(
                              color: scheme.outline,
                            ),
                      ),
                    ],
                    if (precisaUrl) ...[
                      const SizedBox(height: 24),
                      TextField(
                        controller: _urlController,
                        enabled: !_rodando,
                        decoration: const InputDecoration(
                          labelText: 'URL do PC servidor',
                          hintText: 'http://192.168.0.10:8787',
                          border: OutlineInputBorder(),
                        ),
                        keyboardType: TextInputType.url,
                        textInputAction: TextInputAction.next,
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: _tokenController,
                        enabled: !_rodando,
                        decoration: const InputDecoration(
                          labelText: 'Token de sync (se houver)',
                          border: OutlineInputBorder(),
                        ),
                      ),
                      const SizedBox(height: 16),
                      FilledButton.icon(
                        onPressed: _rodando ? null : _salvarRedeEIniciar,
                        icon: const Icon(Icons.cloud_download_outlined),
                        label: const Text('Conectar e baixar banco'),
                      ),
                    ] else if (_progresso.erro != null && !_rodando) ...[
                      const SizedBox(height: 20),
                      FilledButton.icon(
                        onPressed: _iniciarCarga,
                        icon: const Icon(Icons.refresh),
                        label: const Text('Tentar novamente'),
                      ),
                    ],
                    if (widget.onLogout != null) ...[
                      const SizedBox(height: 16),
                      TextButton(
                        onPressed: _rodando ? null : widget.onLogout,
                        child: const Text('Sair'),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildLogo(ColorScheme scheme) {
    final path = _logoPath;
    Widget image;
    if (path != null && File(path).existsSync()) {
      image = Image.file(File(path), fit: BoxFit.contain);
    } else {
      image = Image.asset(
        'assets/images/logo.jpg',
        fit: BoxFit.contain,
        errorBuilder: (_, _, _) => Icon(
          Icons.storefront_outlined,
          size: 64,
          color: scheme.primary,
        ),
      );
    }
    return SizedBox(
      height: 96,
      width: 96,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: image,
      ),
    );
  }
}
