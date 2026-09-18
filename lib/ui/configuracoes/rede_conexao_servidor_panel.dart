import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../data/api/lan_api_url.dart';
import '../../data/api/lan_conexao_qr.dart';
import '../../services/lan_rede_helper.dart';
import '../widgets/lan_qr_code_view.dart';

/// Lista as placas ativas e acoes de copia / QR para o celular.
class RedeConexaoServidorPanel extends StatelessWidget {
  const RedeConexaoServidorPanel({
    super.key,
    required this.enderecos,
    required this.token,
    required this.onAtualizar,
    this.ocupado = false,
    this.precisaAtivar = false,
    this.onAtivarRede,
  });

  final List<LanEnderecoLocal> enderecos;
  final String token;
  final VoidCallback onAtualizar;
  final bool ocupado;
  final bool precisaAtivar;
  final VoidCallback? onAtivarRede;

  LanEnderecoLocal? get _recomendadoPcs =>
      LanRedeHelper.enderecoRecomendadoPcs(enderecos);

  @override
  Widget build(BuildContext context) {
    final tema = Theme.of(context);
    final onVar = tema.colorScheme.onSurfaceVariant;
    final recomendado = _recomendadoPcs;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                'Endereços da API (:${LanApiUrl.portaPadrao})',
                style: tema.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            IconButton(
              tooltip: 'Atualizar placas de rede',
              onPressed: ocupado ? null : onAtualizar,
              icon: const Icon(Icons.refresh_rounded),
            ),
          ],
        ),
        Text(
          'A API escuta em 0.0.0.0:${LanApiUrl.portaPadrao} e atende '
          'Ethernet, Wi-Fi e Tailscale ao mesmo tempo. '
          'Terminais de caixa na rede cabeada continuam iguais.',
          style: tema.textTheme.bodySmall?.copyWith(color: onVar, height: 1.35),
        ),
        const SizedBox(height: 12),
        if (enderecos.isEmpty)
          Text(
            'Nenhum IP detectado. Verifique o cabo de rede ou o Wi-Fi deste PC.',
            style: tema.textTheme.bodyMedium,
          )
        else
          for (final e in enderecos) ...[
            _InterfaceTile(endereco: e),
            const SizedBox(height: 8),
          ],
        const SizedBox(height: 8),
        FilledButton.icon(
          onPressed: recomendado == null
              ? null
              : () => _copiar(context, recomendado.url),
          icon: const Icon(Icons.copy_rounded),
          label: const Text('Copiar endereço para os terminais (PCs)'),
        ),
        const SizedBox(height: 10),
        FilledButton.tonalIcon(
          onPressed: enderecos.isEmpty
              ? null
              : () => _abrirQrCelular(context),
          icon: const Icon(Icons.qr_code_2_rounded),
          label: const Text('Conectar Celular (QR Code)'),
        ),
        if (precisaAtivar) ...[
          const SizedBox(height: 10),
          FilledButton.tonalIcon(
            onPressed: ocupado ? null : onAtivarRede,
            icon: ocupado
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.power_settings_new_rounded),
            label: Text(ocupado ? 'Ativando...' : 'Ativar Rede da Loja'),
          ),
        ],
      ],
    );
  }

  Future<void> _copiar(BuildContext context, String texto) async {
    await Clipboard.setData(ClipboardData(text: texto));
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Copiado: $texto')),
    );
  }

  Future<void> _abrirQrCelular(BuildContext context) async {
    final candidatos = LanRedeHelper.enderecosParaCelular(enderecos);
    if (candidatos.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Nenhum IP de Wi-Fi ou Tailscale encontrado. '
            'Conecte o PC ao Wi-Fi da loja ou ative o Tailscale.',
          ),
        ),
      );
      return;
    }
    await showDialog<void>(
      context: context,
      builder: (ctx) => _QrCelularDialog(
        candidatos: candidatos,
        token: token,
      ),
    );
  }
}

class _InterfaceTile extends StatelessWidget {
  const _InterfaceTile({required this.endereco});

  final LanEnderecoLocal endereco;

  @override
  Widget build(BuildContext context) {
    final tema = Theme.of(context);
    final cs = tema.colorScheme;
    final destaque = endereco.recomendadoPcs;
    return Material(
      color: destaque
          ? cs.primaryContainer.withValues(alpha: 0.55)
          : cs.surfaceContainerHighest.withValues(alpha: 0.45),
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '${endereco.emoji} ${endereco.rotuloTipo}',
              style: tema.textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 4),
            SelectableText(
              endereco.url,
              style: tema.textTheme.titleMedium?.copyWith(
                fontFamily: 'monospace',
                fontWeight: FontWeight.w800,
                letterSpacing: 0.2,
              ),
            ),
            Text(
              endereco.nomeInterface,
              style: tema.textTheme.bodySmall?.copyWith(
                color: cs.onSurfaceVariant,
              ),
            ),
            if (destaque) ...[
              const SizedBox(height: 6),
              Text(
                'Conexão Recomendada para PCs',
                style: tema.textTheme.labelLarge?.copyWith(
                  color: cs.primary,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _QrCelularDialog extends StatefulWidget {
  const _QrCelularDialog({
    required this.candidatos,
    required this.token,
  });

  final List<LanEnderecoLocal> candidatos;
  final String token;

  @override
  State<_QrCelularDialog> createState() => _QrCelularDialogState();
}

class _QrCelularDialogState extends State<_QrCelularDialog> {
  late LanEnderecoLocal _escolhido;

  @override
  void initState() {
    super.initState();
    _escolhido = widget.candidatos.first;
  }

  @override
  Widget build(BuildContext context) {
    final token = widget.token.trim();
    final payload = LanConexaoQr.montar(url: _escolhido.url, token: token);
    return AlertDialog(
      title: const Text('Conectar celular'),
      content: SizedBox(
        width: 360,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (widget.candidatos.length > 1) ...[
                SegmentedButton<String>(
                  segments: [
                    for (final e in widget.candidatos)
                      ButtonSegment(
                        value: e.url,
                        label: Text(e.rotuloCurto),
                        icon: Icon(
                          e.tipo == LanInterfaceTipo.tailscale
                              ? Icons.cloud_outlined
                              : Icons.wifi,
                          size: 16,
                        ),
                      ),
                  ],
                  selected: {_escolhido.url},
                  onSelectionChanged: (s) {
                    setState(() {
                      _escolhido = widget.candidatos.firstWhere(
                        (e) => e.url == s.first,
                      );
                    });
                  },
                ),
                const SizedBox(height: 12),
              ],
              Text(
                _escolhido.tipo == LanInterfaceTipo.tailscale
                    ? 'Use este QR com o Tailscale ativo no celular (acesso remoto).'
                    : 'Use este QR com o celular na Wi-Fi da loja.',
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 12),
              LanQrCodeView(data: payload, size: 220),
              const SizedBox(height: 12),
              SelectableText(
                _escolhido.url,
                style: const TextStyle(
                  fontFamily: 'monospace',
                  fontWeight: FontWeight.w700,
                ),
                textAlign: TextAlign.center,
              ),
              if (token.isEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(
                    'Gere o token da rede nas opções avançadas antes de '
                    'conectar o celular.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Theme.of(context).colorScheme.error),
                  ),
                ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Fechar'),
        ),
      ],
    );
  }
}
