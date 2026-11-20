import 'package:flutter/material.dart';

import 'screens/editor_screen.dart';

void main() {
  runApp(const PdfStudioApp());
}

class PdfStudioApp extends StatelessWidget {
  const PdfStudioApp({super.key});

  // A quiet ink-blue accent on neutral paper tones suits a document tool.
  static const _seed = Color(0xFF2B4C7E);

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'PDF Studio',
      debugShowCheckedModeBanner: false,
      themeMode: ThemeMode.system,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(seedColor: _seed),
        scaffoldBackgroundColor: const Color(0xFFF6F5F2),
        appBarTheme: const AppBarTheme(
          centerTitle: false,
          elevation: 0,
          surfaceTintColor: Colors.transparent,
        ),
        snackBarTheme: const SnackBarThemeData(
          behavior: SnackBarBehavior.floating,
        ),
      ),
      darkTheme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: _seed,
          brightness: Brightness.dark,
        ),
        appBarTheme: const AppBarTheme(
          centerTitle: false,
          elevation: 0,
          surfaceTintColor: Colors.transparent,
        ),
        snackBarTheme: const SnackBarThemeData(
          behavior: SnackBarBehavior.floating,
        ),
      ),
      home: const EditorScreen(),
    );
  }
}
