import 'package:flutter/material.dart';

import 'chat_service.dart';
import 'screens/home.dart';

void main() => runApp(const App());

class App extends StatelessWidget {
  const App({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'WhatsApp seguro',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(colorSchemeSeed: const Color(0xFF075E54)),
      home: const LoginScreen(),
    );
  }
}

// Pantalla inicial: nombre de usuario y dirección del servidor
class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final nombre = TextEditingController();
  final servidor = TextEditingController(text: 'ws://localhost:8080');
  String? error;

  Future<void> entrar() async {
    if (nombre.text.trim().isEmpty) return;
    final chat = ChatService();
    try {
      await chat.conectar(nombre.text.trim(), servidor.text.trim());
      if (!mounted) return;
      Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => HomeScreen(chat: chat)));
    } catch (e) {
      setState(() => error = 'No se ha podido conectar: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('WhatsApp seguro')),
      body: Center(
        child: SizedBox(
          width: 350,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(controller: nombre, decoration: const InputDecoration(labelText: 'Tu nombre')),
              TextField(controller: servidor, decoration: const InputDecoration(labelText: 'Servidor')),
              const SizedBox(height: 20),
              FilledButton(onPressed: entrar, child: const Text('Entrar')),
              if (error != null) Text(error!, style: const TextStyle(color: Colors.red)),
            ],
          ),
        ),
      ),
    );
  }
}
