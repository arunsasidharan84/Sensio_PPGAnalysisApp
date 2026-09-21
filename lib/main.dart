import 'package:flutter/material.dart';
import 'ui/theme.dart';
import 'ui/screens/home_screen.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const SensioApp());
}

class SensioApp extends StatelessWidget {
  const SensioApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Sensio PPG Studio',
      debugShowCheckedModeBanner: false,
      theme: SensioTheme.darkTheme,
      home: const HomeScreen(),
    );
  }
}
