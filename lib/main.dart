import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:provider/provider.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:intl/intl.dart';

import 'firebase_options.dart';
import 'vehiculos_page.dart';
import 'combustible_page.dart';
import 'recorridos_page.dart';
import 'mantenimiento_page.dart';
import 'estadisticas_page.dart';
import 'usuario_provider.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initializeDateFormatting();
  Intl.defaultLocale = 'es';

  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);

  runApp(
    MultiProvider(
      providers: [ChangeNotifierProvider(create: (_) => UserProvider())],
      child: const MyApp(),
    ),
  );
}

// ───────────── PALETA VISUAL ─────────────

const kNavy = Color(0xFF0B1730);
const kNavyLight = Color(0xFF142A4D);
const kGold = Color(0xFFD4AF37);
const kGoldLight = Color(0xFFFFD76A);
const kSurface = Color(0xFFF3F6FC);
const kCardBg = Colors.white;
const kTextDark = Color(0xFF17243B);
const kTextMuted = Color(0xFF718096);

const kSlogan = 'Tecnología al servicio de una flota eficiente y responsable.';
const kSystemFooter = 'Sistema interno de gestión vehicular';
const kPieSistema = kSystemFooter;

// ───────────── APLICACIÓN ─────────────

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Control de Flota Vehicular',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        fontFamily: 'Roboto',
        scaffoldBackgroundColor: kSurface,
        colorScheme: ColorScheme.fromSeed(
          seedColor: kNavy,
          primary: kNavy,
          secondary: kGold,
        ),
        appBarTheme: const AppBarTheme(
          backgroundColor: kNavy,
          foregroundColor: Colors.white,
          centerTitle: false,
        ),
        inputDecorationTheme: InputDecorationTheme(
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
        ),
      ),
      home: const LoginPage(),
    );
  }
}

// ───────────── INICIO DE SESIÓN ─────────────

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();

  bool _loading = false;
  bool _passwordVisible = false;
  String _error = '';

  Future<void> _signIn() async {
    final emailInput = _emailController.text.trim();
    final password = _passwordController.text;

    if (emailInput.isEmpty || password.isEmpty) {
      setState(() => _error = 'Introduzca su usuario y contraseña.');
      return;
    }

    setState(() {
      _loading = true;
      _error = '';
    });

    try {
      final credentials = await FirebaseAuth.instance
          .signInWithEmailAndPassword(
            email: 'alfredobailey62@gmail.com',
            password: '123456',
          );

      final uid = credentials.user?.uid;
      if (uid == null) {
        throw Exception('No se pudo iniciar sesión.');
      }

      final result = await FirebaseFirestore.instance
          .collection('usuarios')
          .where('nombre', isEqualTo: emailInput)
          .where('contraseña', isEqualTo: password)
          .get();

      if (result.docs.isEmpty) {
        await FirebaseAuth.instance.signOut();

        if (!mounted) return;

        setState(() {
          _error = 'Usuario no registrado en el sistema.';
          _loading = false;
        });
        return;
      }

      final userData = result.docs.first.data();
      final isAdmin = userData['admin'] ?? false;

      Provider.of<UserProvider>(
        context,
        listen: false,
      ).setUser(emailInput, isAdmin);

      if (!mounted) return;

      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => const MainDashboard()),
      );
    } on FirebaseAuthException catch (error) {
      if (error.code == 'network-request-failed') {
        setState(() => _error = 'Compruebe su conexión a internet.');
      } else if (error.code == 'user-not-found' ||
          error.code == 'wrong-password' ||
          error.code == 'invalid-credential') {
        setState(() => _error = 'Usuario o contraseña incorrectos.');
      } else {
        setState(() => _error = 'Error: ${error.message ?? error.code}');
      }
    } catch (err) {
      if (mounted) {
        debugPrint(err.toString());
        setState(() => _error = 'No se pudo iniciar sesión, error externo.');
      }
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          const Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [kNavy, Color(0xFF10294D), Color(0xFF061124)],
                ),
              ),
            ),
          ),
          Positioned.fill(
            child: IgnorePointer(
              child: CustomPaint(painter: _DotPatternPainter()),
            ),
          ),
          const Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: ColoredBox(color: kGold, child: SizedBox(height: 4)),
          ),
          SafeArea(
            child: Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(
                  horizontal: 24,
                  vertical: 32,
                ),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 430),
                  child: Column(
                    children: [
                      Container(
                        width: 100,
                        height: 100,
                        decoration: BoxDecoration(
                          color: Colors.white,
                          shape: BoxShape.circle,
                          border: Border.all(color: kGold, width: 3),
                          boxShadow: [
                            BoxShadow(
                              color: kGold.withOpacity(0.2),
                              blurRadius: 24,
                              spreadRadius: 3,
                            ),
                          ],
                        ),
                        padding: const EdgeInsets.all(5),
                        child: ClipOval(
                          child: Image.asset(
                            'assets/logo.png',
                            fit: BoxFit.cover,
                            errorBuilder: (_, __, ___) => const Icon(
                              Icons.directions_car_rounded,
                              color: kNavy,
                              size: 48,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 22),
                      const Text(
                        'CONTROL DE FLOTA VEHICULAR',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 22,
                          height: 1.3,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 1.3,
                        ),
                      ),
                      const SizedBox(height: 12),
                      Container(
                        width: 60,
                        height: 3,
                        decoration: BoxDecoration(
                          color: kGold,
                          borderRadius: BorderRadius.circular(5),
                        ),
                      ),
                      const SizedBox(height: 12),
                      const Text(
                        kSlogan,
                        textAlign: TextAlign.center,
                        style: TextStyle(                          color: kGoldLight,
                          fontSize: 13,
                          height: 1.5,
                        ),
                      ),
                      const SizedBox(height: 32),
                      Container(
                        padding: const EdgeInsets.all(22),
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.97),
                          borderRadius: BorderRadius.circular(22),
                          border: Border.all(
                            color: Colors.white.withOpacity(0.5),
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withOpacity(0.2),
                              blurRadius: 28,
                              offset: const Offset(0, 12),
                            ),
                          ],
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Row(
                              children: [
                                Icon(
                                  Icons.lock_outline_rounded,
                                  color: kNavy,
                                  size: 22,
                                ),
                                SizedBox(width: 10),
                                Text(
                                  'Acceso al sistema',
                                  style: TextStyle(
                                    color: kTextDark,
                                    fontSize: 18,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 22),
                            _CampoTexto(
                              controller: _emailController,
                              label: 'Usuario o correo',
                              icono: Icons.person_outline_rounded,
                              teclado: TextInputType.emailAddress,
                            ),
                            const SizedBox(height: 16),
                            _CampoTexto(
                              controller: _passwordController,
                              label: 'Contraseña',
                              icono: Icons.lock_outline_rounded,
                              oculto: !_passwordVisible,
                              sufijo: IconButton(
                                tooltip: _passwordVisible
                                    ? 'Ocultar contraseña'
                                    : 'Mostrar contraseña',
                                icon: Icon(
                                  _passwordVisible
                                      ? Icons.visibility_off_rounded
                                      : Icons.visibility_rounded,
                                ),
                                onPressed: () {
                                  setState(() {
                                    _passwordVisible = !_passwordVisible;
                                  });
                                },
                              ),
                              alEnviar: _signIn,
                            ),
                            if (_error.isNotEmpty) ...[
                              const SizedBox(height: 14),
                              Container(
                                width: double.infinity,
                                padding: const EdgeInsets.all(12),
                                decoration: BoxDecoration(
                                  color: const Color(0xFFFFEEEE),
                                  borderRadius: BorderRadius.circular(10),
                                  border: Border.all(
                                    color: Colors.red.shade200,
                                  ),
                                ),
                                child: Text(
                                  _error,
                                  style: TextStyle(
                                    color: Colors.red.shade800,
                                    fontSize: 13,
                                  ),
                                ),
                              ),
                            ],
                            const SizedBox(height: 22),
                            SizedBox(
                              width: double.infinity,
                              height: 52,
                              child: FilledButton(
                                onPressed: _loading ? null : _signIn,
                                style: FilledButton.styleFrom(
                                  backgroundColor: kGold,
                                  foregroundColor: kNavy,
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                ),
                                child: _loading
                                    ? const SizedBox(
                                        width: 23,
                                        height: 23,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2.5,
                                          color: kNavy,
                                        ),
                                      )
                                    : const Row(
                                        mainAxisAlignment:
                                            MainAxisAlignment.center,
                                        children: [
                                          Icon(Icons.login_rounded),
                                          SizedBox(width: 10),
                                          Text(
                                            'INGRESAR',
                                            style: TextStyle(
                                              fontWeight: FontWeight.w900,
                                              letterSpacing: 1.2,
                                            ),
                                          ),
                                        ],
                                      ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 28),
                      const Text(
                        kPieSistema,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: Colors.white70,
                          fontSize: 11,
                          letterSpacing: 0.5,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          const Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: ColoredBox(color: kGold, child: SizedBox(height: 3)),
          ),
        ],
      ),
    );
  }
}

// ───────────── CAMPO REUTILIZABLE ─────────────

class _CampoTexto extends StatelessWidget {
  final TextEditingController controller;
  final String label;
  final IconData icono;
  final bool oculto;
  final TextInputType teclado;
  final Widget? sufijo;
  final VoidCallback? alEnviar;

  const _CampoTexto({
    required this.controller,
    required this.label,
    required this.icono,
    this.oculto = false,
    this.teclado = TextInputType.text,
    this.sufijo,
    this.alEnviar,
  });

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      obscureText: oculto,
      keyboardType: teclado,
      textInputAction: oculto ? TextInputAction.done : TextInputAction.next,
      onSubmitted: oculto ? (_) => alEnviar?.call() : null,
      style: const TextStyle(color: kTextDark, fontSize: 14),
      decoration: InputDecoration(
        labelText: label,
        prefixIcon: Icon(icono, color: kNavy),
        suffixIcon: sufijo,
        filled: true,
        fillColor: const Color(0xFFF5F7FB),
        contentPadding: const EdgeInsets.symmetric(
          vertical: 16,
          horizontal: 12,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Color(0xFFDDE3EE)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: kNavy, width: 1.5),
        ),
      ),
    );
  }
}

// ───────────── PATRÓN DE FONDO ─────────────

class _DotPatternPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = Colors.white.withOpacity(0.06);

    const gap = 24.0;

    for (double x = 0; x < size.width; x += gap) {
      for (double y = 0; y < size.height; y += gap) {
        canvas.drawCircle(Offset(x, y), 1.1, paint);
      }
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

// ───────────── MENÚ PRINCIPAL ─────────────

class MainDashboard extends StatelessWidget {
  const MainDashboard({super.key});

  String get _greeting {
    final hora = DateTime.now().hour;

    if (hora < 12) return 'Buenos días';
    if (hora < 18) return 'Buenas tardes';
    return 'Buenas noches';
  }

  Future<void> _signOut(BuildContext context) async {
    await FirebaseAuth.instance.signOut();

    if (!context.mounted) return;

    Navigator.pushAndRemoveUntil(
      context,
      MaterialPageRoute(builder: (_) => const LoginPage()),
      (_) => false,
    );
  }

  @override
  Widget build(BuildContext context) {
    final user = context.watch<UserProvider>();
    final isAdmin = user.isAdmin;
    final userName = user.email;

    final modules = <_ModuleInfo>[
      if (isAdmin)
        _ModuleInfo(
          title: 'Vehículos',
          description: 'Registro y control de la flota',
          icon: Icons.directions_car_rounded,
          color: const Color(0xFF2864C5),
          page: VehiclesPage(),
        ),
      _ModuleInfo(
        title: 'Combustible',
        description: 'Cargas, consumo y costos',
        icon: Icons.local_gas_station_rounded,
        color: const Color(0xFF16805A),
        page: FuelPage(),
      ),
      _ModuleInfo(
        title: 'Recorridos',
        description: 'Salidas, destinos y kilometraje',
        icon: Icons.route_rounded,
        color: const Color(0xFFB56A18),
        page: TripsPage(),
      ),
      _ModuleInfo(
        title: 'Mantenimiento',
        description: 'Servicios, averías y alertas',
        icon: Icons.build_circle_rounded,
        color: const Color(0xFF7851B8),
        page: MaintenancePage(),
      ),
      if (isAdmin)
        _ModuleInfo(
          title: 'Estadísticas',
          description: 'Indicadores y reportes de la flota',
          icon: Icons.query_stats_rounded,
          color: const Color(0xFF147D9B),
          page: StatisticsPage(),
        ),
    ];

    return Scaffold(
      backgroundColor: kSurface,
      appBar: AppBar(
        toolbarHeight: 72,
        elevation: 0,
        flexibleSpace: const DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [kNavy, kNavyLight],
              begin: Alignment.centerLeft,
              end: Alignment.centerRight,
            ),
          ),
        ),
        titleSpacing: 16,
        title: Row(
          children: [
            Container(
              width: 43,
              height: 43,
              padding: const EdgeInsets.all(3),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(11),
                border: Border.all(color: kGold, width: 1.5),
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(7),
                child: Image.asset(
                  'assets/logo.png',
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) =>
                      const Icon(Icons.directions_car_rounded, color: kNavy),
                ),
              ),
            ),
            const SizedBox(width: 11),
            const Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'CONTROL DE FLOTA',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 15,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 0.5,
                    ),
                  ),
                  Text(
                    'VEHICULAR',
                    style: TextStyle(
                      color: kGoldLight,
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 1.7,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            tooltip: 'Cerrar sesión',
            onPressed: () => _signOut(context),
            icon: const Icon(Icons.logout_rounded),
          ),
          const SizedBox(width: 5),
        ],
      ),
      body: Column(
        children: [
          // Encabezado de bienvenida
          Container(
            width: double.infinity,
            padding: const EdgeInsets.fromLTRB(22, 23, 22, 25),
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [kNavy, Color(0xFF173A69), Color(0xFF214A7D)],
              ),
              borderRadius: BorderRadius.only(
                bottomLeft: Radius.circular(25),
                bottomRight: Radius.circular(25),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      width: 4,
                      height: 43,
                      decoration: BoxDecoration(
                        color: kGold,
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                    const SizedBox(width: 13),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '$_greeting,',
                            style: const TextStyle(
                              color: Colors.white70,
                              fontSize: 13,
                            ),
                          ),
                          const SizedBox(height: 3),
                          Text(
                            userName,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 21,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 11,
                        vertical: 7,
                      ),
                      decoration: BoxDecoration(
                        color: isAdmin
                            ? kGold.withOpacity(0.18)
                            : Colors.white.withOpacity(0.10),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                          color: isAdmin
                              ? kGold.withOpacity(0.7)
                              : Colors.white24,
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            isAdmin
                                ? Icons.admin_panel_settings_rounded
                                : Icons.person_outline_rounded,
                            color: isAdmin ? kGoldLight : Colors.white,
                            size: 16,
                          ),
                          const SizedBox(width: 5),
                          Text(
                            isAdmin ? 'Administrador' : 'Conductor',
                            style: TextStyle(
                              color: isAdmin ? kGoldLight : Colors.white,
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 19),
                const Text(
                  kSlogan,
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 13,
                    height: 1.5,
                  ),
                ),
              ],
            ),
          ),

          // Título del menú
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 23, 20, 13),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Módulos del sistema',
                        style: TextStyle(
                          color: kTextDark,
                          fontSize: 19,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        isAdmin
                            ? 'Administra y supervisa la flota'
                            : 'Selecciona la operación que necesitas',
                        style: const TextStyle(color: kTextMuted, fontSize: 12),
                      ),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 11,
                    vertical: 7,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: const Color(0xFFE0E6F0)),
                  ),
                  child: Text(
                    '${modules.length} módulos',
                    style: const TextStyle(
                      color: kNavy,
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
          ),

          // Tarjetas adaptables al tamaño de pantalla
          Expanded(
            child: LayoutBuilder(
              builder: (context, constraints) {
                final ancho = constraints.maxWidth;

                final columnas = ancho >= 1050
                    ? 4
                    : ancho >= 700
                    ? 3
                    : ancho >= 430
                    ? 2
                    : 1;

                final proporcion = columnas == 1 ? 2.15 : 1.05;

                return GridView.builder(
                  padding: const EdgeInsets.fromLTRB(18, 4, 18, 22),
                  itemCount: modules.length,
                  gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: columnas,
                    childAspectRatio: proporcion,
                    crossAxisSpacing: 14,
                    mainAxisSpacing: 14,
                  ),
                  itemBuilder: (context, index) {
                    final module = modules[index];

                    return _ModuleCard(
                      modulo: module,
                      onTap: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(builder: (_) => module.page),
                        );
                      },
                    );
                  },
                );
              },
            ),
          ),

          // Pie de pantalla
          Container(
            width: double.infinity,
            padding: const EdgeInsets.fromLTRB(12, 13, 12, 15),
            decoration: const BoxDecoration(
              color: kNavy,
              border: Border(top: BorderSide(color: kGold, width: 2)),
            ),
            child: const SafeArea(
              top: false,
              child: Column(
                children: [
                  Text(
                    kPieSistema,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 0.6,
                    ),
                  ),
                  SizedBox(height: 4),
                  Text(
                    'CONTROL Y SEGUIMIENTO DE LA FLOTA',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: kGoldLight,
                      fontSize: 9,
                      letterSpacing: 1.3,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ───────────── DATOS DE CADA MÓDULO ─────────────

class _ModuleInfo {
  final String title;
  final String description;
  final IconData icon;
  final Color color;
  final Widget page;

  const _ModuleInfo({
    required this.title,
    required this.description,
    required this.icon,
    required this.color,
    required this.page,
  });
}

// ───────────── TARJETA DEL MENÚ ─────────────

class _ModuleCard extends StatelessWidget {
  final _ModuleInfo modulo;
  final VoidCallback onTap;

  const _ModuleCard({super.key, required this.modulo, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: kCardBg,
      borderRadius: BorderRadius.circular(19),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(19),
        child: Container(
          padding: const EdgeInsets.all(17),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(19),
            border: Border.all(color: const Color(0xFFE2E8F2)),
            boxShadow: [
              BoxShadow(
                color: kNavy.withOpacity(0.045),
                blurRadius: 15,
                offset: const Offset(0, 5),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 51,
                    height: 51,
                    decoration: BoxDecoration(
                      color: modulo.color.withOpacity(0.10),
                      borderRadius: BorderRadius.circular(15),
                    ),
                    child: Icon(modulo.icon, color: modulo.color, size: 28),
                  ),
                  const Spacer(),
                  Icon(
                    Icons.arrow_outward_rounded,
                    color: modulo.color.withOpacity(0.8),
                    size: 20,
                  ),
                ],
              ),
              const Spacer(),
              Text(
                modulo.title,
                style: const TextStyle(
                  color: kTextDark,
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                modulo.description,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: kTextMuted,
                  fontSize: 11,
                  height: 1.4,
                ),
              ),
              const SizedBox(height: 12),
              Container(
                height: 3,
                width: 43,
                decoration: BoxDecoration(
                  color: modulo.color,
                  borderRadius: BorderRadius.circular(5),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
