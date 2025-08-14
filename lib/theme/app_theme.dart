import 'package:flutter/material.dart';

class AppTheme {
  static const seed =
      Color(0xFF22C55E); // verde (ajusto depois conforme seu HEX)

  static ThemeData light = ThemeData(
    useMaterial3: true,
    colorSchemeSeed: seed,
    brightness: Brightness.light,
    scaffoldBackgroundColor: const Color(0xFFF7F9FC),
    visualDensity: VisualDensity.standard,
    inputDecorationTheme: InputDecorationTheme(
      border: OutlineInputBorder(
        borderRadius: BorderRadius.all(Radius.circular(14)),
      ),
      filled: true,
      fillColor: Colors.white,
    ),
    cardTheme: const CardThemeData(
      elevation: 0,
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
    ),
  );

  static ThemeData dark = ThemeData(
    useMaterial3: true,
    colorSchemeSeed: seed,
    brightness: Brightness.dark,
  );
}
