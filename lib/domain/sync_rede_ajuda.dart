import 'package:flutter/material.dart';

/// Dicas de resolucao e dialogos da aba Rede (sync LAN).
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
        'No PC servidor: Configuracoes > Rede > copie o token (icone de olho/copiar).',
        'No PC cliente: cole o mesmo token, sem espacos no fim.',
        'Salve nos dois PCs e use Testar conexao antes de sincronizar.',
      ];
    }
    if (m.contains('objectbox') ||
        m.contains('internal id sequence') ||
        m.contains('obx_error') ||
        m.contains('use id 0')) {
      return const [
        'Atualize o app nos dois PCs para a mesma versao (correcao de IDs na sync).',
        'No PC cliente: feche o app e apague apenas os dados locais deste PC '
        '(nao apague no servidor).',
        'Abra de novo, configure token e endereco, e sincronize do zero.',
        'Se persistir: Backup e Dados > restaurar backup vazio no cliente antes da primeira sync.',
      ];
    }
    if (m.contains('firewall') ||
        m.contains('nao alcanc') ||
        m.contains('servidor local nao encontrado') ||
        m.contains('socket') ||
        m.contains('connection refused') ||
        m.contains('timed out') ||
        m.contains('dhcp')) {
      return const [
        'Servidor local nao encontrado: confirme Wi-Fi/cabo na mesma rede.',
        'No PC servidor: anote o IP atual (ipconfig) — DHCP pode ter mudado.',
        'Atualize o endereco nos clientes (ex.: http://192.168.0.10:8787).',
        'No servidor: Liberar porta no firewall (secao Avancado) e Iniciar servidor.',
        'Desative VPN temporariamente para testar.',
      ];
    }
    if (m.contains('servico de sync') ||
        m.contains('nao respondeu') ||
        m.contains('nao esta ativo')) {
      return const [
        'Servidor local nao encontrado (servico parado).',
        'No PC servidor: marque Servidor neste PC e clique Iniciar servidor.',
        'Use Ativar como servidor e sincronizar ou Salvar com sync ativa.',
      ];
    }
    return const [
      'Use Testar conexao e corrija token/endereco antes de sincronizar.',
      'Veja Problemas na primeira sincronizacao? no final desta tela.',
    ];
  }

  static Future<void> mostrarDialogPrimeiraSync(BuildContext context) {
    return showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Primeira sincronizacao na rede'),
        content: const SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Siga esta ordem nos dois computadores:',
                style: TextStyle(fontWeight: FontWeight.w600),
              ),
              SizedBox(height: 12),
              Text('1. PC servidor'),
              Text('   • Servidor neste PC\n'
                  '   • Ative sincronizacao\n'
                  '   • Gere/copie o token\n'
                  '   • Ativar como servidor e sincronizar\n'
                  '   • Copie o endereco (IP:porta) para o outro PC'),
              SizedBox(height: 10),
              Text('2. PC cliente'),
              Text('   • Outro PC e o servidor\n'
                  '   • Cole IP:porta e o mesmo token\n'
                  '   • Testar conexao (deve ficar verde)\n'
                  '   • Conectar ao servidor e sincronizar'),
              SizedBox(height: 10),
              Text('3. Se der erro de banco (ObjectBox) no cliente'),
              Text(
                '   Atualize o app, feche o cliente e limpe apenas os dados '
                'locais deste PC. Nunca apague dados no servidor.',
                style: TextStyle(fontSize: 13),
              ),
              SizedBox(height: 10),
              Text('4. Fotos de entrega (POD)'),
              Text(
                '   No PC servidor, o servico de sync grava JPEG em '
                'pod_entrega/ (ou SYNC_POD_PATH). Libere a mesma porta no '
                'firewall. Outros PCs baixam a foto ao abrir os detalhes da entrega.',
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
