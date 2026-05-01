import 'dart:io';

import 'package:flutter/material.dart';

import 'data/cliente_repository.dart';
import 'data/objectbox.dart';
import 'data/produto_repository.dart';
import 'data/usuario_repository.dart';
import 'data/venda_repository.dart';
import 'data/vendedor_repository.dart';
import 'model/usuario_sistema.dart';
import 'ui/login_page.dart';
import 'ui/main_menu_page.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await _tentarSincronizarHorarioSistemaNoInicio();
  final objectBox = await ObjectBox.create();
  runApp(MyApp(objectBox: objectBox));
}

Future<void> _tentarSincronizarHorarioSistemaNoInicio() async {
  if (!Platform.isWindows) {
    return;
  }
  try {
    await Process.run(
      'w32tm',
      ['/resync'],
      runInShell: true,
    ).timeout(const Duration(seconds: 4));
  } catch (_) {
    // Falha silenciosa: sem permissao/rede/servico, app segue normalmente.
  }
}

class MyApp extends StatefulWidget {
  const MyApp({super.key, required this.objectBox});

  final ObjectBox objectBox;

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  UsuarioSistema? _usuarioLogado;
  final UsuarioRepository _usuarioRepository = UsuarioRepository();

  void _entrar(UsuarioSistema usuario) {
    setState(() {
      _usuarioLogado = usuario;
    });
  }

  void _sair() {
    setState(() {
      _usuarioLogado = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final baseTheme = ThemeData(
      useMaterial3: true,
      colorScheme: ColorScheme.fromSeed(seedColor: Colors.teal),
      visualDensity: VisualDensity.standard,
    );
    const globalRadius = 12.0;
    final globalShape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(globalRadius),
    );

    return MaterialApp(
      title: 'Sistema de Vendas',
      theme: baseTheme.copyWith(
        scaffoldBackgroundColor: baseTheme.colorScheme.surface,
        textTheme: baseTheme.textTheme.copyWith(
          bodyLarge: baseTheme.textTheme.bodyLarge?.copyWith(
            fontSize: (baseTheme.textTheme.bodyLarge?.fontSize ?? 16) * 1.05,
            height: 1.35,
            color: const Color(0xFF1F2937),
          ),
          bodyMedium: baseTheme.textTheme.bodyMedium?.copyWith(
            fontSize: (baseTheme.textTheme.bodyMedium?.fontSize ?? 14) * 1.05,
            height: 1.35,
            color: const Color(0xFF1F2937),
          ),
          bodySmall: baseTheme.textTheme.bodySmall?.copyWith(
            fontSize: (baseTheme.textTheme.bodySmall?.fontSize ?? 12) * 1.05,
            height: 1.35,
            color: const Color(0xFF1F2937),
          ),
          titleMedium: baseTheme.textTheme.titleMedium?.copyWith(
            color: const Color(0xFF1F2937),
          ),
          titleLarge: baseTheme.textTheme.titleLarge?.copyWith(
            color: const Color(0xFF1F2937),
          ),
        ),
        inputDecorationTheme: baseTheme.inputDecorationTheme.copyWith(
          floatingLabelBehavior: FloatingLabelBehavior.auto,
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 12,
            vertical: 14,
          ),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(globalRadius),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(globalRadius),
            borderSide: BorderSide(color: baseTheme.colorScheme.outlineVariant),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(globalRadius),
            borderSide: BorderSide(
              color: baseTheme.colorScheme.primary,
              width: 1.4,
            ),
          ),
          errorBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(globalRadius),
            borderSide: BorderSide(color: baseTheme.colorScheme.error),
          ),
          focusedErrorBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(globalRadius),
            borderSide: BorderSide(
              color: baseTheme.colorScheme.error,
              width: 1.4,
            ),
          ),
        ),
        cardTheme: CardThemeData(
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(globalRadius),
            side: BorderSide(color: baseTheme.colorScheme.outlineVariant),
          ),
          clipBehavior: Clip.antiAlias,
        ),
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            shape: globalShape,
            minimumSize: const Size(88, 44),
            textStyle: const TextStyle(fontWeight: FontWeight.w600),
          ),
        ),
        outlinedButtonTheme: OutlinedButtonThemeData(
          style: OutlinedButton.styleFrom(
            shape: globalShape,
            minimumSize: const Size(88, 44),
            side: BorderSide(color: baseTheme.colorScheme.outline),
          ),
        ),
        dialogTheme: DialogThemeData(shape: globalShape),
        snackBarTheme: SnackBarThemeData(
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(globalRadius),
          ),
        ),
        extensions: const [
          AppSemanticColors(
            successBg: Color(0xFFEAF8EF),
            successBorder: Color(0xFF8FD1A8),
            successFg: Color(0xFF166534),
            warningBg: Color(0xFFFFF8E6),
            warningBorder: Color(0xFFF2CC7A),
            warningFg: Color(0xFF8A5B00),
            errorBg: Color(0xFFFDECEC),
            errorBorder: Color(0xFFF1A3A3),
            errorFg: Color(0xFF9B1C1C),
            infoBg: Color(0xFFEAF2FF),
            infoBorder: Color(0xFF9EC0FF),
            infoFg: Color(0xFF1E3A8A),
          ),
        ],
      ),
      home: _usuarioLogado == null
          ? LoginPage(
              usuarioRepository: _usuarioRepository,
              onLoginSuccess: _entrar,
            )
          : MainMenuPage(
              produtoRepository: ProdutoRepository(widget.objectBox),
              clienteRepository: ClienteRepository(widget.objectBox),
              vendaRepository: VendaRepository(widget.objectBox),
              vendedorRepository: VendedorRepository(widget.objectBox),
              usuarioLogado: _usuarioLogado!,
              onLogout: _sair,
            ),
    );
  }
}

@immutable
class AppSemanticColors extends ThemeExtension<AppSemanticColors> {
  const AppSemanticColors({
    required this.successBg,
    required this.successBorder,
    required this.successFg,
    required this.warningBg,
    required this.warningBorder,
    required this.warningFg,
    required this.errorBg,
    required this.errorBorder,
    required this.errorFg,
    required this.infoBg,
    required this.infoBorder,
    required this.infoFg,
  });

  final Color successBg;
  final Color successBorder;
  final Color successFg;
  final Color warningBg;
  final Color warningBorder;
  final Color warningFg;
  final Color errorBg;
  final Color errorBorder;
  final Color errorFg;
  final Color infoBg;
  final Color infoBorder;
  final Color infoFg;

  @override
  ThemeExtension<AppSemanticColors> copyWith({
    Color? successBg,
    Color? successBorder,
    Color? successFg,
    Color? warningBg,
    Color? warningBorder,
    Color? warningFg,
    Color? errorBg,
    Color? errorBorder,
    Color? errorFg,
    Color? infoBg,
    Color? infoBorder,
    Color? infoFg,
  }) {
    return AppSemanticColors(
      successBg: successBg ?? this.successBg,
      successBorder: successBorder ?? this.successBorder,
      successFg: successFg ?? this.successFg,
      warningBg: warningBg ?? this.warningBg,
      warningBorder: warningBorder ?? this.warningBorder,
      warningFg: warningFg ?? this.warningFg,
      errorBg: errorBg ?? this.errorBg,
      errorBorder: errorBorder ?? this.errorBorder,
      errorFg: errorFg ?? this.errorFg,
      infoBg: infoBg ?? this.infoBg,
      infoBorder: infoBorder ?? this.infoBorder,
      infoFg: infoFg ?? this.infoFg,
    );
  }

  @override
  ThemeExtension<AppSemanticColors> lerp(
    covariant ThemeExtension<AppSemanticColors>? other,
    double t,
  ) {
    if (other is! AppSemanticColors) return this;
    return AppSemanticColors(
      successBg: Color.lerp(successBg, other.successBg, t) ?? successBg,
      successBorder:
          Color.lerp(successBorder, other.successBorder, t) ?? successBorder,
      successFg: Color.lerp(successFg, other.successFg, t) ?? successFg,
      warningBg: Color.lerp(warningBg, other.warningBg, t) ?? warningBg,
      warningBorder:
          Color.lerp(warningBorder, other.warningBorder, t) ?? warningBorder,
      warningFg: Color.lerp(warningFg, other.warningFg, t) ?? warningFg,
      errorBg: Color.lerp(errorBg, other.errorBg, t) ?? errorBg,
      errorBorder: Color.lerp(errorBorder, other.errorBorder, t) ?? errorBorder,
      errorFg: Color.lerp(errorFg, other.errorFg, t) ?? errorFg,
      infoBg: Color.lerp(infoBg, other.infoBg, t) ?? infoBg,
      infoBorder: Color.lerp(infoBorder, other.infoBorder, t) ?? infoBorder,
      infoFg: Color.lerp(infoFg, other.infoFg, t) ?? infoFg,
    );
  }
}
