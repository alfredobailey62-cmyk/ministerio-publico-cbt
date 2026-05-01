import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import 'firebase_options.dart';
import 'vehiculos_page.dart';
import 'combustible_page.dart';
import 'recorridos_page.dart';
import 'mantenimiento_page.dart';
import 'usuarios_page.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );
  runApp(const MyApp());
}

// ─── COLORES ─────────────────────────────────────────
const kNavy = Color(0xFF002B6E);
const kNavyLight = Color(0xFF003D99);
const kGold = Color(0xFFE5A800);
const kGoldLight = Color(0xFFFFC825);
const kSurface = Color(0xFFF4F6FB);
const kCardBg = Colors.white;
const kTextDark = Color(0xFF0D1B3E);
const kTextMuted = Color(0xFF6B7A99);

// ─── APP ─────────────────────────────────────────────
class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Ministerio Público CBT',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: kNavy),
        useMaterial3: true,
        fontFamily: 'Roboto',
      ),
      home: const AuthWrapper(), // 🔥 IMPORTANTE
    );
  }
}

// ─── CONTROL DE SESIÓN + ROL ─────────────────────────
class AuthWrapper extends StatelessWidget {
  const AuthWrapper({super.key});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder(
      stream: FirebaseAuth.instance.authStateChanges(),
      builder: (context, snapshot) {
        // Cargando
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }

        // No logueado
        if (!snapshot.hasData) {
          return const LoginPage();
        }

        final user = snapshot.data!;

        // Buscar rol
        return FutureBuilder<DocumentSnapshot>(
          future: FirebaseFirestore.instance
              .collection('usuarios')
              .doc(user.uid)
              .get(),
          builder: (context, snap) {
            if (!snap.hasData) {
              return const Scaffold(
                body: Center(child: CircularProgressIndicator()),
              );
            }

            final data = snap.data!.data() as Map<String, dynamic>?;
            final rol = data?['rol'] ?? 'conductor';

            return PantallaPrincipal(rol: rol);
          },
        );
      },
    );
  }
}

// ─── LOGIN ───────────────────────────────────────────
class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _cargando = false;
  bool _verClave = false;
  String _error = '';

  Future<void> _ingresar() async {
    setState(() {
      _cargando = true;
      _error = '';
    });

    try {
      await FirebaseAuth.instance.signInWithEmailAndPassword(
        email: _emailController.text.trim(),
        password: _passwordController.text.trim(),
      );
    } catch (_) {
      setState(() {
        _error = 'Correo o contraseña incorrectos';
      });
    } finally {
      setState(() {
        _cargando = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: kNavy,
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'INICIAR SESIÓN',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 20),

              TextField(
                controller: _emailController,
                decoration: const InputDecoration(
                  labelText: 'Correo',
                  filled: true,
                ),
              ),
              const SizedBox(height: 10),

              TextField(
                controller: _passwordController,
                obscureText: !_verClave,
                decoration: InputDecoration(
                  labelText: 'Contraseña',
                  filled: true,
                  suffixIcon: IconButton(
                    icon: Icon(_verClave
                        ? Icons.visibility_off
                        : Icons.visibility),
                    onPressed: () {
                      setState(() => _verClave = !_verClave);
                    },
                  ),
                ),
              ),

              if (_error.isNotEmpty)
                Text(_error, style: const TextStyle(color: Colors.red)),

              const SizedBox(height: 20),

              ElevatedButton(
                onPressed: _cargando ? null : _ingresar,
                child: _cargando
                    ? const CircularProgressIndicator()
                    : const Text('Ingresar'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─── HOME ────────────────────────────────────────────
class PantallaPrincipal extends StatelessWidget {
  final String rol;

  const PantallaPrincipal({super.key, required this.rol});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Panel Principal'),
        actions: [
          IconButton(
            icon: const Icon(Icons.logout),
            onPressed: () async {
              await FirebaseAuth.instance.signOut();
            },
          ),
        ],
      ),
      body: GridView.count(
        crossAxisCount: 2,
        padding: const EdgeInsets.all(16),
        children: [
          _card(context, 'Vehículos', Icons.car_rental, VehiculosPage()),
          _card(context, 'Combustible', Icons.local_gas_station,
              CombustiblePage()),
          _card(context, 'Recorridos', Icons.map, RecorridosPage()),
          _card(context, 'Mantenimiento', Icons.build,
              MantenimientoPage()),

          // 🔐 SOLO ADMIN
          if (rol == 'administrador')
            _card(context, 'Usuarios', Icons.people, UsuariosPage()),
        ],
      ),
    );
  }

  Widget _card(
      BuildContext context, String title, IconData icon, Widget page) {
    return Card(
      child: InkWell(
        onTap: () =>
            Navigator.push(context, MaterialPageRoute(builder: (_) => page)),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 40),
            const SizedBox(height: 10),
            Text(title),
          ],
        ),
      ),
    );
  }
}
