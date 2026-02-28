import 'package:flutter/material.dart';
import 'theme/app_theme.dart';
import 'screens/welcome_screen.dart';

void main() {
  runApp(const GravitySyncApp());
}

class GravitySyncApp extends StatelessWidget {
  const GravitySyncApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'GravitySync',
      theme: AppTheme.darkTheme,
      home: const WelcomeScreen(), // Carga la pantalla inicial
      debugShowCheckedModeBanner: false,
    );
  }
}
