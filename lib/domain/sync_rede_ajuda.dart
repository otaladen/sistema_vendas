import 'package:flutter/material.dart';

/// Dicas de resolucao e dialogos da aba Rede (API-first).
abstract final class SyncRedeAjuda {
  SyncRedeAjuda._();

  static List<String> dicasParaErro(String mensagem) {
    final m = mensagem.toLowerCase();
    if (m.contains('token') &&
        (m.contains('invalid') ||
            m.contains('recusad') ||
            m.contains('ausente') ||
            m.contains('403') ||
            m.contains('401'))) {
      return const [
        'No PC servidor: Configuracoes > Rede > copie o token.',
        'No Terminal: cole o mesmo token, sem espacos no fim.',
        'Salve nos dois PCs e use Testar conexao.',
      ];
    }
    if (m.contains('firewall') ||
        m.contains('nao alcanc') ||
        m.contains('servidor local nao encontrado') ||
        m.contains('socket') ||
        m.contains('connection refused') ||
        m.contains('timed out') ||
        m.contains('dhcp') ||
        m.contains('inacessivel') ||
        m.contains('8788')) {
      return const [
        'Confirme Wi-Fi/cabo na mesma rede.',
        'No PC servidor: anote o IP (ipconfig) — DHCP pode ter mudado.',
        'No servidor: Ativar como servidor e Liberar portas no firewall.',
        'Deixe o app aberto no PC servidor (ou "Servidor ao ligar o PC").',
        'Terminais (PC ou celular) usam a API na porta 8788.',
      ];
    }
    if (m.contains('servico de sync') ||
        m.contains('nao respondeu') ||
        m.contains('nao esta ativo')) {
      return const [
        'No PC servidor: marque Servidor neste PC e Ativar como servidor.',
        'Confirme que a API :8788 esta ativa (status verde na tela Rede).',
      ];
    }
    if (m.contains('objectbox') ||
        m.contains('object put failed') ||
        m.contains('id sequence') ||
        m.contains('internal id sequence')) {
      return const [
        'Banco ObjectBox inconsistente no PC servidor (cliente/sync).',
        'Feche o app nos terminais, reinicie o PC1 e teste a conexao.',
        'Se persistir: restaure o ultimo backup e reabra a API :8788.',
      ];
    }
    return const [
      'Use Testar conexao e corrija token/endereco.',
      'Veja "Como configurar a rede?" no final desta tela.',
    ];
  }

  static Future<void> mostrarDialogPrimeiraSync(BuildContext context) {
    return showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Como configurar a rede'),
        content: const SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Arquitetura (API-first):',
                style: TextStyle(fontWeight: FontWeight.w600),
              ),
              SizedBox(height: 8),
              Text(
                '• PC servidor: guarda o banco e sobe a API dos terminais '
                'na porta 8788.\n'
                '• Terminal (PC Windows ou celular): le e grava direto '
                'na API :8788 (sem banco local). Se o servidor cair, o terminal para.',
                style: TextStyle(fontSize: 13, height: 1.35),
              ),
              SizedBox(height: 14),
              Text('1. PC servidor', style: TextStyle(fontWeight: FontWeight.w600)),
              Text(
                '   • Servidor neste PC\n'
                '   • Ative a rede local\n'
                '   • Gere/copie o token\n'
                '   • Ativar como servidor\n'
                '   • Copie o endereco API (IP:8788) para o terminal',
              ),
              SizedBox(height: 10),
              Text('2. Terminal (PC ou celular)',
                  style: TextStyle(fontWeight: FontWeight.w600)),
              Text(
                '   • Ative “Usar rede local” / informe IP:8788\n'
                '   • Cole o mesmo token\n'
                '   • Testar conexao e salvar\n'
                '   • Reinicie o app no celular se ainda estiver no modo antigo',
              ),
              SizedBox(height: 10),
              Text(
                'Nunca apague o banco do PC servidor para "testar" o terminal.',
                style: TextStyle(fontSize: 13),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Entendi'),
          ),
        ],
      ),
    );
  }
}
