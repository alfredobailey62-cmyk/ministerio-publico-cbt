import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:provider/provider.dart';
import 'firebase_options.dart';
import 'vehiculos_page.dart';
import 'combustible_page.dart';
import 'recorridos_page.dart';
import 'mantenimiento_page.dart';
import 'estadisticas_page.dart';
import 'usuario_provider.dart';
import 'danos_page.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  runApp(
    MultiProvider(
      providers: [ChangeNotifierProvider(create: (_) => UsuarioProvider())],
      child: const MyApp(),
    ),
  );
}

// ─── PALETA INSTITUCIONAL ─────────────────────────────────────────────────────
const kNavy = Color(0xFF002B6E);
const kNavyLight = Color(0xFF003D99);
const kGold = Color(0xFFE5A800);
const kGoldLight = Color(0xFFFFC825);
const kSurface = Color(0xFFF4F6FB);
const kCardBg = Colors.white;
const kTextDark = Color(0xFF0D1B3E);
const kTextMuted = Color(0xFF6B7A99);

// ─── APP ──────────────────────────────────────────────────────────────────────
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
      home: const LoginPage(),
    );
  }
}

// ─── LOGIN ────────────────────────────────────────────────────────────────────
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
      final userCredential = await FirebaseAuth.instance
          .signInWithEmailAndPassword(
            email: _emailController.text.trim(),
            password: _passwordController.text.trim(),
          );
      if (!mounted) return;

      final doc = await FirebaseFirestore.instance
          .collection('admins')
          .doc(userCredential.user?.uid)
          .get();

      if (!mounted) return;

      final usuarioProvider = Provider.of<UsuarioProvider>(
        context,
        listen: false,
      );

      usuarioProvider.setUsuario(_emailController.text.trim(), doc.exists);

      if (mounted) {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (_) => const PantallaPrincipal()),
        );
      }
    } catch (_) {
      setState(() {
        _error = 'Correo o contraseña incorrectos';
      });
    } finally {
      if (mounted) {
        setState(() {
          _cargando = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          Container(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [kNavy, Color(0xFF001A4D), Color(0xFF004080)],
              ),
            ),
          ),
          Opacity(
            opacity: 0.06,
            child: CustomPaint(
              painter: _DotPatternPainter(),
              size: Size.infinite,
            ),
          ),
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: Container(height: 4, color: kGold),
          ),
          SafeArea(
            child: Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(
                  horizontal: 28,
                  vertical: 40,
                ),
                child: Column(
                  children: [
                    Container(
                      width: 108,
                      height: 108,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(color: kGold, width: 2.5),
                        boxShadow: [
                          BoxShadow(
                            color: kGold.withOpacity(0.3),
                            blurRadius: 20,
                            spreadRadius: 4,
                          ),
                        ],
                      ),
                      child: ClipOval(
                        child: Image.asset(
                          'assets/logo.png',
                          fit: BoxFit.cover,
                        ),
                      ),
                    ),
                    const SizedBox(height: 20),
                    const Text(
                      'MINISTERIO PÚBLICO',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 22,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 2.5,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Container(width: 30, height: 1.5, color: kGold),
                        const SizedBox(width: 8),
                        const Text(
                          'Bocas del Toro',
                          style: TextStyle(
                            color: kGoldLight,
                            fontSize: 14,
                            letterSpacing: 1.2,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Container(width: 30, height: 1.5, color: kGold),
                      ],
                    ),
                    const SizedBox(height: 38),
                    Container(
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.07),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color: Colors.white.withOpacity(0.15),
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.2),
                            blurRadius: 24,
                            offset: const Offset(0, 8),
                          ),
                        ],
                      ),
                      padding: const EdgeInsets.all(24),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Container(
                                width: 3,
                                height: 18,
                                decoration: BoxDecoration(
                                  color: kGold,
                                  borderRadius: BorderRadius.circular(2),
                                ),
                              ),
                              const SizedBox(width: 8),
                              const Text(
                                'Acceso al sistema',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                  letterSpacing: 0.8,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 20),
                          _CampoTexto(
                            controller: _emailController,
                            label: 'Correo institucional',
                            icono: Icons.alternate_email_rounded,
                            teclado: TextInputType.emailAddress,
                          ),
                          const SizedBox(height: 14),
                          _CampoTexto(
                            controller: _passwordController,
                            label: 'Contraseña',
                            icono: Icons.lock_outline_rounded,
                            oculto: !_verClave,
                            sufijo: IconButton(
                              icon: Icon(
                                _verClave
                                    ? Icons.visibility_off_rounded
                                    : Icons.visibility_rounded,
                                color: Colors.white54,
                                size: 20,
                              ),
                              onPressed: () =>
                                  setState(() => _verClave = !_verClave),
                            ),
                          ),
                          if (_error.isNotEmpty) ...[
                            const SizedBox(height: 12),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 8,
                              ),
                              decoration: BoxDecoration(
                                color: Colors.red.withOpacity(0.15),
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(
                                  color: Colors.red.withOpacity(0.4),
                                ),
                              ),
                              child: Row(
                                children: [
                                  const Icon(
                                    Icons.warning_amber_rounded,
                                    color: Colors.redAccent,
                                    size: 16,
                                  ),
                                  const SizedBox(width: 8),
                                  Text(
                                    _error,
                                    style: const TextStyle(
                                      color: Colors.redAccent,
                                      fontSize: 13,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                          const SizedBox(height: 22),
                          SizedBox(
                            width: double.infinity,
                            height: 50,
                            child: ElevatedButton(
                              onPressed: _cargando ? null : _ingresar,
                              style: ElevatedButton.styleFrom(
                                backgroundColor: kGold,
                                foregroundColor: kNavy,
                                elevation: 0,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(10),
                                ),
                              ),
                              child: _cargando
                                  ? const SizedBox(
                                      width: 22,
                                      height: 22,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2.5,
                                        color: kNavy,
                                      ),
                                    )
                                  : const Row(
                                      mainAxisAlignment:
                                          MainAxisAlignment.center,
                                      children: [
                                        Icon(Icons.login_rounded, size: 18),
                                        SizedBox(width: 8),
                                        Text(
                                          'INGRESAR',
                                          style: TextStyle(
                                            fontWeight: FontWeight.w800,
                                            letterSpacing: 1.5,
                                            fontSize: 14,
                                          ),
                                        ),
                                      ],
                                    ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 32),
                    const Text(
                      'Procuraduría General de la Nación',
                      style: TextStyle(color: Colors.white38, fontSize: 11),
                    ),
                    const SizedBox(height: 4),
                    const Text(
                      'Sistema Interno de Gestión Vehicular',
                      style: TextStyle(color: Colors.white24, fontSize: 10),
                    ),
                  ],
                ),
              ),
            ),
          ),
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: Container(height: 3, color: kGold.withOpacity(0.6)),
          ),
        ],
      ),
    );
  }
}

// ─── CAMPO TEXTO REUTILIZABLE ─────────────────────────────────────────────────
class _CampoTexto extends StatelessWidget {
  final TextEditingController controller;
  final String label;
  final IconData icono;
  final bool oculto;
  final TextInputType teclado;
  final Widget? sufijo;

  const _CampoTexto({
    required this.controller,
    required this.label,
    required this.icono,
    this.oculto = false,
    this.teclado = TextInputType.text,
    this.sufijo,
  });

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      obscureText: oculto,
      keyboardType: teclado,
      style: const TextStyle(color: Colors.white, fontSize: 14),
      cursorColor: kGoldLight,
      decoration: InputDecoration(
        labelText: label,
        labelStyle: const TextStyle(color: Colors.white54, fontSize: 13),
        prefixIcon: Icon(icono, color: kGoldLight, size: 20),
        suffixIcon: sufijo,
        filled: true,
        fillColor: Colors.white.withOpacity(0.06),
        contentPadding: const EdgeInsets.symmetric(
          vertical: 14,
          horizontal: 12,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: Colors.white24),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: kGoldLight, width: 1.5),
        ),
      ),
    );
  }
}

// ─── PATRÓN DE PUNTOS ─────────────────────────────────────────────────────────
class _DotPatternPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = Colors.white;
    const gap = 22.0;
    for (double x = 0; x < size.width; x += gap) {
      for (double y = 0; y < size.height; y += gap) {
        canvas.drawCircle(Offset(x, y), 1.2, paint);
      }
    }
  }

  @override
  bool shouldRepaint(_) => false;
}

// ─── HOME ─────────────────────────────────────────────────────────────────────
class PantallaPrincipal extends StatelessWidget {
  const PantallaPrincipal({super.key});

  String get _saludo {
    final hora = DateTime.now().hour;
    if (hora < 12) return 'Buenos días';
    if (hora < 18) return 'Buenas tardes';
    return 'Buenas noches';
  }

  String get _usuarioNombre {
    final user = FirebaseAuth.instance.currentUser;
    return user?.displayName ?? user?.email?.split('@').first ?? 'Usuario';
  }

  @override
  Widget build(BuildContext context) {
    final usuarioProvider = Provider.of<UsuarioProvider>(context);

    return Scaffold(
      backgroundColor: kSurface,
      appBar: PreferredSize(
        preferredSize: const Size.fromHeight(64),
        child: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              colors: [kNavy, kNavyLight],
              begin: Alignment.centerLeft,
              end: Alignment.centerRight,
            ),
            boxShadow: [
              BoxShadow(
                color: Color(0x40000000),
                blurRadius: 12,
                offset: Offset(0, 3),
              ),
            ],
          ),
          child: SafeArea(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                children: [
                  Image.asset('assets/logo.png', height: 38),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Ministerio Público',
                          style: TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w800,
                            fontSize: 15,
                            letterSpacing: 0.3,
                          ),
                        ),
                        Text(
                          'Bocas del Toro',
                          style: TextStyle(color: kGoldLight, fontSize: 11),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(
                      Icons.logout_rounded,
                      color: Colors.white70,
                      size: 22,
                    ),
                    tooltip: 'Cerrar sesión',
                    onPressed: () async {
                      await FirebaseAuth.instance.signOut();
                      if (context.mounted) {
                        Navigator.pushReplacement(
                          context,
                          MaterialPageRoute(builder: (_) => const LoginPage()),
                        );
                      }
                    },
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
      body: Column(
        children: [
          Container(
            width: double.infinity,
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                colors: [kNavy, Color(0xFF004DA0)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
            ),
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 36,
                  height: 3,
                  decoration: BoxDecoration(
                    color: kGold,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  '$_saludo,',
                  style: const TextStyle(color: Colors.white70, fontSize: 13),
                ),
                Text(
                  _usuarioNombre,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 6),
                const Text(
                  'Gestión Vehicular Institucional',
                  style: TextStyle(
                    color: kGoldLight,
                    fontSize: 11,
                    letterSpacing: 1.2,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
          Container(height: 3, color: kGold),
          Expanded(
            child: GridView(
              padding: const EdgeInsets.all(16),
              gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                maxCrossAxisExtent: 200,
                childAspectRatio: 0.95,
                crossAxisSpacing: 14,
                mainAxisSpacing: 14,
              ),
              children: [
                if (usuarioProvider.isAdmin)
                  _ModuloCard(
                    icono: Icons.directions_car_rounded,
                    titulo: 'Vehículos',
                    descripcion: 'Registro y control',
                    color: const Color(0xFF0050C8),
                    pagina: VehiculosPage(),
                  ),
                _ModuloCard(
                  icono: Icons.local_gas_station_rounded,
                  titulo: 'Combustible',
                  descripcion: 'Consumo y reportes',
                  color: const Color(0xFF007A3D),
                  pagina: CombustiblePage(),
                ),
                _ModuloCard(
                  icono: Icons.map_rounded,
                  titulo: 'Recorridos',
                  descripcion: 'Rutas y bitácoras',
                  color: const Color(0xFF8B4500),
                  pagina: RecorridosPage(),
                ),
                _ModuloCard(
                  icono: Icons.build_circle_rounded,
                  titulo: 'Mantenimiento',
                  descripcion: 'Servicios y talleres',
                  color: const Color(0xFF6A1B9A),
                  pagina: MantenimientoPage(),
                ),
                _ModuloCard(
                  icono: Icons.bar_chart_rounded,
                  titulo: 'Estadísticas',
                  descripcion: 'Dashboard y reportes',
                  color: const Color(0xFFE5A800),
                  pagina: EstadisticasPage(), // ✅ CORREGIDO: sin "const"
                ),
                const _ModuloCard(
                  icono: Icons.car_crash_rounded,
                  titulo: 'Daños',
                  descripcion: 'Incidentes y daños',
                  color: const Color(0xFFC62828),
                  pagina: DanosPage(),
                ),
              ],
            ),
          ),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 10),
            color: kNavy,
            child: const Column(
              children: [
                Text(
                  'Procuraduría General de la Nación',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.white38, fontSize: 10),
                ),
                Text(
                  'Sistema Interno v2.0 · Uso oficial',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.white24, fontSize: 9),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ─── CARD DE MÓDULO ───────────────────────────────────────────────────────────
class _ModuloCard extends StatelessWidget {
  final IconData icono;
  final String titulo;
  final String descripcion;
  final Color color;
  final Widget? pagina;

  const _ModuloCard({
    required this.icono,
    required this.titulo,
    required this.descripcion,
    required this.color,
    this.pagina,
  });

  @override
  Widget build(BuildContext context) {
    final bool activo = pagina != null;

    return Material(
      color: kCardBg,
      borderRadius: BorderRadius.circular(14),
      elevation: activo ? 3 : 1,
      shadowColor: color.withOpacity(0.3),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: activo
            ? () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => pagina!),
              )
            : null,
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border(top: BorderSide(color: color, width: 3.5)),
          ),
          padding: const EdgeInsets.fromLTRB(16, 18, 16, 14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: color.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icono, color: color, size: 26),
              ),
              const Spacer(),
              Text(
                titulo,
                style: TextStyle(
                  color: activo ? kTextDark : kTextMuted,
                  fontWeight: FontWeight.w700,
                  fontSize: 15,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                descripcion,
                style: const TextStyle(color: kTextMuted, fontSize: 11),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Container(
                    width: 6,
                    height: 6,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: activo
                          ? const Color(0xFF2ECC71)
                          : Colors.grey.shade300,
                    ),
                  ),
                  const SizedBox(width: 5),
                  Text(
                    activo ? 'Disponible' : 'Próximamente',
                    style: TextStyle(
                      color: activo ? const Color(0xFF27AE60) : kTextMuted,
                      fontSize: 10,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const Spacer(),
                  if (activo)
                    Icon(
                      Icons.arrow_forward_ios_rounded,
                      size: 12,
                      color: color.withOpacity(0.6),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
