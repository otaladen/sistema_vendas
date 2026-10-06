import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sistema_vendas/ui/configuracoes/backup_controller.dart';
import 'package:sistema_vendas/ui/configuracoes/backup_dialog_feedback.dart';
import 'package:sistema_vendas/ui/theme/app_semantic_colors.dart';

const _caminhoTeste = r'C:\Backups\backup_sistema_vendas_20261006_172100';

Future<void> _pumpDialogoSucesso(WidgetTester tester) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: ThemeData(
        extensions: const [AppSemanticColors.claro],
      ),
      home: Scaffold(
        body: Builder(
          builder: (context) => Center(
            child: FilledButton(
              onPressed: () {
                mostrarDialogoSucessoBackupManual(
                  context,
                  info: const BackupManualConclusaoInfo(
                    caminho: _caminhoTeste,
                    tamanhoTotalFormatado: '12.4 MB',
                    horarioConclusaoFormatado: '06/10/2026 17:21',
                  ),
                );
              },
              child: const Text('Abrir sucesso'),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('Abrir sucesso'));
  await tester.pumpAndSettle();
}

Future<void> _pumpDialogoErro(
  WidgetTester tester, {
  required String mensagem,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: ThemeData(
        extensions: const [AppSemanticColors.claro],
      ),
      home: Scaffold(
        body: Builder(
          builder: (context) => Center(
            child: FilledButton(
              onPressed: () {
                mostrarDialogoErroBackupManual(
                  context,
                  mensagem: mensagem,
                );
              },
              child: const Text('Abrir erro'),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('Abrir erro'));
  await tester.pumpAndSettle();
}

void main() {
  group('Backup manual — feedback visual', () {
    testWidgets('modal de sucesso exibe caminho e tamanho', (tester) async {
      await _pumpDialogoSucesso(tester);

      expect(find.text('Backup concluído'), findsOneWidget);
      expect(find.byKey(const Key('backup_sucesso_caminho')), findsOneWidget);
      expect(find.textContaining(_caminhoTeste), findsOneWidget);
      expect(find.byKey(const Key('backup_sucesso_tamanho')), findsOneWidget);
      expect(find.text('12.4 MB'), findsOneWidget);
      expect(find.byKey(const Key('backup_sucesso_horario')), findsOneWidget);
      expect(find.text('06/10/2026 17:21'), findsOneWidget);
    });

    testWidgets('diálogo de erro exibe mensagem amigável', (tester) async {
      const mensagem =
          'Não foi possível gravar na pasta selecionada. Verifique permissões.';

      await _pumpDialogoErro(tester, mensagem: mensagem);

      expect(
        find.text('Não foi possível concluir o backup'),
        findsOneWidget,
      );
      expect(find.byKey(const Key('backup_erro_mensagem')), findsOneWidget);
      expect(find.text(mensagem), findsOneWidget);
      expect(find.text('Entendi'), findsOneWidget);
    });

    test('BackupController formata exceções conhecidas', () {
      expect(
        BackupController.mensagemErroAmigavel(
          LocalBackupInvalidoException('Backup inválido.'),
        ),
        'Backup inválido.',
      );
      expect(
        BackupController.mensagemErroAmigavel(
          Exception('Falha de disco'),
        ),
        'Falha de disco',
      );
    });
  });
}
