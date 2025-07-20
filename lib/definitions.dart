import 'package:flutter/material.dart';

const Color darkBlue = Color(0xFF0D47A1);
const Color lightBlue = Color(0xFF42A5F5);
const Color accentGreen = Color(0xFF43A047);
const Color accentRed = Color(0xFFE53935);

final lightColorScheme = ColorScheme.light(
  primary: darkBlue,
  primaryContainer: lightBlue,
  secondary: accentGreen,
  error: accentRed,
  onPrimary: Colors.white,
  onSecondary: Colors.white,
  onError: Colors.white,
  background: Colors.white,
  surface: Colors.white,
  onBackground: Colors.black87,
  onSurface: Colors.black87,
);

final darkColorScheme = ColorScheme.dark(
  primary: lightBlue,
  primaryContainer: darkBlue,
  secondary: Colors.green.shade200,
  error: Colors.red.shade200,
  onPrimary: Colors.black,
  onSecondary: Colors.black,
  onError: Colors.black,
  background: Colors.black,
  surface: Colors.grey.shade900,
  onBackground: Colors.white,
  onSurface: Colors.white,
);

final lightTheme = ThemeData.from(colorScheme: lightColorScheme).copyWith(
  appBarTheme: AppBarTheme(
    backgroundColor: lightColorScheme.primary,
    foregroundColor: lightColorScheme.onPrimary,
    elevation: 2,
    titleTextStyle: TextStyle(
      fontSize: 20,
      fontWeight: FontWeight.w600,
      color: lightColorScheme.onPrimary,
    ),
    iconTheme: IconThemeData(color: lightColorScheme.onPrimary),
  ),
  elevatedButtonTheme: ElevatedButtonThemeData(
    style: ElevatedButton.styleFrom(
      foregroundColor: lightColorScheme.onPrimary,
      backgroundColor: lightColorScheme.primary,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      padding: EdgeInsets.symmetric(vertical: 14, horizontal: 20),
      textStyle: TextStyle(fontSize: 16, fontWeight: FontWeight.w500),
    ),
  ),
  textTheme: TextTheme(
    bodyLarge: TextStyle(color: lightColorScheme.primary),
    titleLarge: TextStyle(fontSize: 18, fontWeight: FontWeight.w600, color: lightColorScheme.primary),
    bodyMedium: TextStyle(fontSize: 16, color: lightColorScheme.onBackground),
    labelLarge: TextStyle(fontSize: 16, fontWeight: FontWeight.w500),
  ),
  inputDecorationTheme: InputDecorationTheme(
    filled: true,
    fillColor: lightColorScheme.primaryContainer.withOpacity(0.1),
    labelStyle: TextStyle(color: lightColorScheme.primary, fontWeight: FontWeight.w500),
    focusedBorder: OutlineInputBorder(
      borderSide: BorderSide(color: lightColorScheme.primary, width: 2),
      borderRadius: BorderRadius.circular(8),
    ),
    enabledBorder: OutlineInputBorder(
      borderSide: BorderSide(color: lightColorScheme.primaryContainer, width: 1),
      borderRadius: BorderRadius.circular(8),
    ),
    errorBorder: OutlineInputBorder(
      borderSide: BorderSide(color: lightColorScheme.error, width: 1),
      borderRadius: BorderRadius.circular(8),
    ),
    focusedErrorBorder: OutlineInputBorder(
      borderSide: BorderSide(color: lightColorScheme.error, width: 2),
      borderRadius: BorderRadius.circular(8),
    ),
  ),
  dialogTheme: DialogThemeData(
    backgroundColor: lightColorScheme.surface,
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    titleTextStyle: TextStyle(
      fontSize: 20,
      fontWeight: FontWeight.w600,
      color: lightColorScheme.primary,
    ),
    contentTextStyle: TextStyle(fontSize: 16, color: lightColorScheme.onSurface),
  ),
  iconTheme: IconThemeData(color: lightColorScheme.primary),
);

final darkTheme = ThemeData.from(colorScheme: darkColorScheme).copyWith(
  appBarTheme: AppBarTheme(
    backgroundColor: darkColorScheme.primary,
    foregroundColor: darkColorScheme.onPrimary,
    elevation: 2,
    titleTextStyle: TextStyle(
      fontSize: 20,
      fontWeight: FontWeight.w600,
      color: darkColorScheme.onPrimary,
    ),
    iconTheme: IconThemeData(color: darkColorScheme.onPrimary),
  ),
  elevatedButtonTheme: ElevatedButtonThemeData(
    style: ElevatedButton.styleFrom(
      foregroundColor: darkColorScheme.onPrimary,
      backgroundColor: darkColorScheme.primary,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      padding: EdgeInsets.symmetric(vertical: 14, horizontal: 20),
      textStyle: TextStyle(fontSize: 16, fontWeight: FontWeight.w500),
    ),
  ),
  textTheme: TextTheme(
    bodyLarge: TextStyle(color: darkColorScheme.primary),
    titleLarge: TextStyle(fontSize: 18, fontWeight: FontWeight.w600, color: darkColorScheme.primary),
    bodyMedium: TextStyle(fontSize: 16, color: darkColorScheme.onBackground),
    labelLarge: TextStyle(fontSize: 16, fontWeight: FontWeight.w500),
  ),
  inputDecorationTheme: InputDecorationTheme(
    filled: true,
    fillColor: darkColorScheme.surface,
    labelStyle: TextStyle(color: darkColorScheme.primary, fontWeight: FontWeight.w500),
    focusedBorder: OutlineInputBorder(
      borderSide: BorderSide(color: darkColorScheme.primary, width: 2),
      borderRadius: BorderRadius.circular(8),
    ),
    enabledBorder: OutlineInputBorder(
      borderSide: BorderSide(color: darkColorScheme.primaryContainer, width: 1),
      borderRadius: BorderRadius.circular(8),
    ),
    errorBorder: OutlineInputBorder(
      borderSide: BorderSide(color: darkColorScheme.error, width: 1),
      borderRadius: BorderRadius.circular(8),
    ),
    focusedErrorBorder: OutlineInputBorder(
      borderSide: BorderSide(color: darkColorScheme.error, width: 2),
      borderRadius: BorderRadius.circular(8),
    ),
  ),
  dialogTheme: DialogThemeData(
    backgroundColor: darkColorScheme.surface,
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    titleTextStyle: TextStyle(
      fontSize: 20,
      fontWeight: FontWeight.w600,
      color: darkColorScheme.primary,
    ),
    contentTextStyle: TextStyle(fontSize: 16, color: darkColorScheme.onSurface),
  ),
  iconTheme: IconThemeData(color: darkColorScheme.primary),
);