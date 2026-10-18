import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:geolocator/geolocator.dart';
import 'package:flutter/foundation.dart'
    show defaultTargetPlatform, TargetPlatform;
import 'package:shared_preferences/shared_preferences.dart';

class TripsPage extends StatefulWidget {
  const TripsPage({super.key});

  @override
  State<TripsPage> createState() => _TripsPageState();
}

class _TripsPageState extends State<TripsPage> {
  final _kmInicioController = TextEditingController();
  final _kmFinController = TextEditingController();
  final _conductorController = TextEditingController();
  final _destinoController = TextEditingController();

  String? _selectedVehicle;
  String? _selectedPlate;
  String? _brandModel;

  List<Map<String, dynamic>> _gpsPoints = [];
  static StreamSubscription<Position>? _positionStream;
  bool _tripActive = false;
  String? _activeTripId;

  Position? _lastPosition;
  DateTime? _stopStart;
  bool _isStopped = false;
  List<Map<String, dynamic>> _stopPoints = [];

  static const double STOP_DISTANCE = 5.0;
  static const int STOP_TIME_MINUTES = 5;

  SharedPreferences? _prefs;

  @override
  void initState() {
    super.initState();
    _loadActiveTrip();
  }

  Future<void> _loadActiveTrip() async {
    _prefs = await SharedPreferences.getInstance();
    final recorridoGuardado = _prefs?.getString('recorrido_activo_id');
    final puntosGuardados = _prefs?.getString('puntos_activos');

    if (recorridoGuardado != null) {
      if (!mounted) return;

      setState(() {
        _activeTripId = recorridoGuardado;
        _tripActive = true;
      });

      if (puntosGuardados != null) {
        final puntos = json.decode(puntosGuardados) as List;
        _gpsPoints = puntos.map((e) => Map<String, dynamic>.from(e)).toList();
      }

      _resumeGps();
    }
  }

  static Timer? _stopTimer;
  DateTime? _lastPointTime;
  int _nextBlock = 0;
  int _pointCounter = 0;
  bool _uploading = false;
  static const int BLOCK_SIZE = 300;

  Future<void> _saveTripInBackground() async {
    if (_activeTripId == null) return;
    await _prefs?.setString('recorrido_activo_id', _activeTripId!);
    await _prefs?.setString('puntos_activos', json.encode(_gpsPoints));
    await _prefs?.setInt('bloque_siguiente', _nextBlock);
  }

  LocationSettings _gpsSettings() {
    if (defaultTargetPlatform == TargetPlatform.android) {
      return AndroidSettings(
        accuracy: LocationAccuracy.bestForNavigation,
        distanceFilter: 30,
        intervalDuration: const Duration(seconds: 5),
        foregroundNotificationConfig: const ForegroundNotificationConfig(
          notificationTitle: 'Recorrido en curso',
          notificationText: 'Registrando la ruta GPS del vehículo',
          enableWakeLock: true,
        ),
      );
    }
    return const LocationSettings(
      accuracy: LocationAccuracy.bestForNavigation,
      distanceFilter: 30,
    );
  }

  Future<bool> _checkServiceAndPermissions() async {
    if (!await Geolocator.isLocationServiceEnabled()) {
      _showSnackbar('Active el GPS del dispositivo');
      return false;
    }
    var permiso = await Geolocator.checkPermission();
    if (permiso == LocationPermission.denied) {
      permiso = await Geolocator.requestPermission();
    }
    if (permiso == LocationPermission.denied) {
      _showSnackbar('Se necesita permiso de ubicación');
      return false;
    }
    if (permiso == LocationPermission.deniedForever) {
      _showSnackbar(
        'El permiso de ubicación está denegado. Actívelo en Ajustes.',
      );
      return false;
    }
    return true;
  }

  void _startStream() {
    _positionStream?.cancel();
    _positionStream = Geolocator.getPositionStream(
      locationSettings: _gpsSettings(),
    ).listen(_onPositionReceived, onError: (_) {});

    _stopTimer?.cancel();
    _stopTimer = Timer.periodic(const Duration(minutes: 1), (_) {
      _checkStop();
      _uploadBlocks();
    });
  }

  Future<void> _resumeGps() async {
    _nextBlock = _prefs?.getInt('bloque_siguiente') ?? 0;
    if (!await _checkServiceAndPermissions()) return;
    _startStream();
  }

  void _onPositionReceived(Position position) {
    if (position.accuracy > 100 && _lastPosition != null) return;

    final ahora = DateTime.now();
    if (_isStopped) _saveStop(ahora);

    _lastPosition = position;
    _lastPointTime = ahora;

    _gpsPoints.add(<String, dynamic>{
      'lat': double.parse(position.latitude.toStringAsFixed(6)),
      'lng': double.parse(position.longitude.toStringAsFixed(6)),
      'hora': ahora.toIso8601String(),
    });

    _pointCounter++;
    if (_pointCounter % 10 == 0) _saveTripInBackground();
    if (_gpsPoints.length >= BLOCK_SIZE) _uploadBlocks();
  }

  Future<void> _uploadBlocks({bool todo = false}) async {
    if (_uploading || _activeTripId == null) return;
    _uploading = true;
    try {
      while (_gpsPoints.length >= BLOCK_SIZE ||
          (todo && _gpsPoints.isNotEmpty)) {
        final n = _gpsPoints.length < BLOCK_SIZE
            ? _gpsPoints.length
            : BLOCK_SIZE;
        final bloque = _gpsPoints
            .sublist(0, n)
            .map((p) => Map<String, dynamic>.from(p))
            .toList();

        await FirebaseFirestore.instance
            .collection('recorridos')
            .doc(_activeTripId)
            .collection('ruta_bloques')
            .doc(_nextBlock.toString().padLeft(5, '0'))
            .set({'orden': _nextBlock, 'total': n, 'puntos': bloque})
            .timeout(const Duration(seconds: 10));

        _gpsPoints.removeRange(0, n);
        _nextBlock++;
        await _saveTripInBackground();
      }
    } catch (_) {
    } finally {
      _uploading = false;
    }
  }

  void _checkStop() {
    if (_isStopped || _lastPosition == null || _lastPointTime == null) return;
    final quieto = DateTime.now().difference(_lastPointTime!);
    if (quieto.inMinutes >= STOP_TIME_MINUTES) {
      _isStopped = true;
      _stopStart = _lastPointTime;
    }
  }

  Future<void> _saveStop(DateTime fin) async {
    final inicio = _stopStart;
    final pos = _lastPosition;
    final id = _activeTripId;
    _isStopped = false;
    _stopStart = null;
    if (inicio == null || pos == null || id == null) return;
    try {
      await FirebaseFirestore.instance
          .collection('recorridos')
          .doc(id)
          .collection('paradas')
          .add({
            'ubicacion': GeoPoint(pos.latitude, pos.longitude),
            'inicio': inicio,
            'fin': fin,
            'duracion_minutos': fin.difference(inicio).inMinutes,
          })
          .timeout(const Duration(seconds: 10));
    } catch (_) {}
  }

  Future<bool> _startGps() async {
    if (!await _checkServiceAndPermissions()) return false;

    _gpsPoints = [];
    _nextBlock = 0;
    _pointCounter = 0;
    _lastPosition = null;
    _lastPointTime = null;
    _stopStart = null;
    _isStopped = false;

    _startStream();

    try {
      final p = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 20),
        ),
      );
      _onPositionReceived(p);
    } catch (_) {}

    await _saveTripInBackground();
    if (mounted) setState(() => _tripActive = true);
    _showSnackbar('GPS activado. Grabando recorrido');
    return true;
  }

  Future<void> _stopGps() async {
    _stopTimer?.cancel();
    _stopTimer = null;

    try {
      final p = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 10),
        ),
      );
      _onPositionReceived(p);
    } catch (_) {}

    if (_isStopped) await _saveStop(DateTime.now());

    await _positionStream?.cancel();
    _positionStream = null;

    var espera = 0;
    while (_uploading && espera < 50) {
      await Future.delayed(const Duration(milliseconds: 300));
      espera++;
    }
    await _uploadBlocks(todo: true);

    _gpsPoints = [];
    await _prefs?.remove('recorrido_activo_id');
    await _prefs?.remove('puntos_activos');
    await _prefs?.remove('bloque_siguiente');

    if (mounted) setState(() => _tripActive = false);
  }

  String _formatDateTime(DateTime fecha) {
    final dia = fecha.day.toString().padLeft(2, '0');
    final mes = fecha.month.toString().padLeft(2, '0');
    final anio = fecha.year;
    final hora = fecha.hour.toString().padLeft(2, '0');
    final minuto = fecha.minute.toString().padLeft(2, '0');

    return '$dia/$mes/$anio $hora:$minuto';
  }

  String _formatDuration(Duration duracion) {
    final horas = duracion.inHours;
    final minutos = duracion.inMinutes.remainder(60);

    if (horas > 0) {
      return '$horas h $minutos min';
    }

    return '$minutos min';
  }

  void _showStartForm() {
    _kmInicioController.clear();
    _conductorController.clear();
    _destinoController.clear();

    _selectedVehicle = null;
    _selectedPlate = null;
    _brandModel = null;

    showDialog(
      context: context,
      builder: (_) => StatefulBuilder(
        builder: (context, setStateDialog) => AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          title: const Row(
            children: [
              Icon(Icons.add_road, color: Color(0xFF17365D)),
              SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Iniciar recorrido',
                  style: TextStyle(fontWeight: FontWeight.w800),
                ),
              ),
            ],
          ),
          content: SizedBox(
            width: 420,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  StreamBuilder<QuerySnapshot>(
                    stream: FirebaseFirestore.instance
                        .collection('vehiculos')
                        .snapshots(),
                    builder: (context, snapshot) {
                      if (snapshot.hasError) {
                        return const Text(
                          'No se pudieron cargar los vehículos.',
                        );
                      }

                      if (!snapshot.hasData) {
                        return const Center(child: CircularProgressIndicator());
                      }

                      final vehiculos = snapshot.data!.docs;

                      if (vehiculos.isEmpty) {
                        return const Text('No hay vehículos registrados.');
                      }

                      return DropdownButtonFormField<String>(
                        isExpanded: true,
                        value: _selectedVehicle,
                        hint: const Text('Seleccione un vehículo'),
                        items: vehiculos.map((v) {
                          final data = v.data() as Map<String, dynamic>;

                          return DropdownMenuItem<String>(
                            value: v.id,
                            child: Text(
                              '${data['placa'] ?? 'Sin placa'} - '
                              '${data['marca'] ?? ''} '
                              '${data['modelo'] ?? ''}',
                              overflow: TextOverflow.ellipsis,
                            ),
                          );
                        }).toList(),
                        onChanged: (valor) {
                          if (valor == null) return;

                          final vehiculo = vehiculos.firstWhere(
                            (v) => v.id == valor,
                          );

                          final data = vehiculo.data() as Map<String, dynamic>;

                          setStateDialog(() {
                            _selectedVehicle = valor;
                            _selectedPlate = data['placa']?.toString() ?? '';
                            _brandModel =
                                '${data['marca'] ?? ''} '
                                        '${data['modelo'] ?? ''}'
                                    .trim();
                          });
                        },
                        decoration: InputDecoration(
                          labelText: 'Vehículo',
                          prefixIcon: const Icon(Icons.directions_car_outlined),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                      );
                    },
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: _conductorController,
                    textCapitalization: TextCapitalization.words,
                    decoration: InputDecoration(
                      labelText: 'Nombre del conductor',
                      prefixIcon: const Icon(Icons.person_outline),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: _kmInicioController,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: false,
                    ),
                    decoration: InputDecoration(
                      labelText: 'Kilometraje inicial',
                      hintText: 'Ej. 45820',
                      suffixText: 'km',
                      prefixIcon: const Icon(Icons.speed),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: const Color(0xFFEAF0F8),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(Icons.schedule, color: Color(0xFF17365D)),
                        SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'La fecha y hora se registrarán '
                            'automáticamente al iniciar el recorrido.',
                            style: TextStyle(fontSize: 12),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: _destinoController,
                    textCapitalization: TextCapitalization.sentences,
                    decoration: InputDecoration(
                      labelText: 'Destino',
                      hintText: 'Introduzca el lugar de destino',
                      prefixIcon: const Icon(Icons.place_outlined),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          actionsPadding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancelar'),
            ),
            ElevatedButton.icon(
              icon: const Icon(Icons.play_arrow),
              label: const Text('Iniciar recorrido'),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF17365D),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(
                  horizontal: 18,
                  vertical: 14,
                ),
              ),
              onPressed: () async {
                final kmInicio = int.tryParse(_kmInicioController.text.trim());

                if (kmInicio == null ||
                    kmInicio < 0 ||
                    _selectedVehicle == null ||
                    _conductorController.text.trim().isEmpty ||
                    _destinoController.text.trim().isEmpty) {
                  _showSnackbar('Complete todos los campos con datos válidos.');
                  return;
                }

                final fechaHoraInicio = DateTime.now();

                try {
                  final docRef = await FirebaseFirestore.instance
                      .collection('recorridos')
                      .add({
                        'vehiculo_id': _selectedVehicle,
                        'placa': _selectedPlate,
                        'vehiculo': _brandModel,
                        'conductor': _conductorController.text.trim(),
                        'destino': _destinoController.text.trim(),
                        'km_inicio': kmInicio,
                        'km_fin': null,
                        'km_recorrido': null,
                        'fecha_inicio': fechaHoraInicio,
                        'fecha_salida': fechaHoraInicio,
                        'hora_salida_str':
                            '${fechaHoraInicio.hour.toString().padLeft(2, '0')}:'
                            '${fechaHoraInicio.minute.toString().padLeft(2, '0')}',
                        'fecha_inicio_str': _formatDateTime(fechaHoraInicio),
                        'fecha_fin': null,
                        'fecha_llegada': null,
                        'tiempo_recorrido': null,
                        'tiempo_recorrido_minutos': null,
                        'mes': fechaHoraInicio.month,
                        'anio': fechaHoraInicio.year,
                        'estado': 'en_curso',
                      });

                  _activeTripId = docRef.id;
                  await _saveTripInBackground();

                  final gpsIniciado = await _startGps();

                  if (!gpsIniciado) {
                    await FirebaseFirestore.instance
                        .collection('recorridos')
                        .doc(docRef.id)
                        .update({'estado': 'en_curso_sin_gps'});

                    if (mounted) {
                      setState(() {
                        _tripActive = false;
                        _activeTripId = null;
                      });
                    }

                    _showSnackbar(
                      'Recorrido guardado, pero no se activó el GPS. '
                      'Revise los permisos y el estado del GPS.',
                    );

                    if (context.mounted) {
                      Navigator.pop(context);
                    }
                    return;
                  }

                  if (mounted) {
                    setState(() {
                      _tripActive = true;
                    });
                  }

                  _showSnackbar('Recorrido iniciado correctamente.');

                  if (context.mounted) {
                    Navigator.pop(context);
                  }
                } catch (e) {
                  _showSnackbar('No se pudo iniciar el recorrido: $e');
                }
              },
            ),
          ],
        ),
      ),
    );
  }

  void _showCompletionForm(
    String recorridoId,
    Map<String, dynamic> recorridoActual,
  ) {
    _kmFinController.clear();

    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Row(
          children: [
            Icon(Icons.flag_outlined, color: Color(0xFF17365D)),
            SizedBox(width: 10),
            Expanded(
              child: Text(
                'Finalizar recorrido',
                style: TextStyle(fontWeight: FontWeight.w800),
              ),
            ),
          ],
        ),
        content: SizedBox(
          width: 420,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: const Color(0xFFF4F6FA),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${recorridoActual['placa'] ?? 'Sin placa'} - '
                      '${recorridoActual['vehiculo'] ?? 'Vehículo'}',
                      style: const TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 16,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text('Conductor: ${recorridoActual['conductor'] ?? '—'}'),
                    Text('Destino: ${recorridoActual['destino'] ?? '—'}'),
                    Text(
                      'Salida: ${recorridoActual['fecha_inicio_str'] ?? '—'}',
                    ),
                    const Divider(),
                    Text(
                      'Kilometraje inicial: '
                      '${recorridoActual['km_inicio']} km',
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _kmFinController,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: false,
                ),
                decoration: InputDecoration(
                  labelText: 'Kilometraje final',
                  hintText: 'Introduzca el kilometraje del vehículo',
                  suffixText: 'km',
                  prefixIcon: const Icon(Icons.speed),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancelar'),
          ),
          ElevatedButton.icon(
            icon: const Icon(Icons.check_circle_outline),
            label: const Text('Confirmar llegada'),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF16835D),
              foregroundColor: Colors.white,
            ),
            onPressed: () async {
              final kmFin = int.tryParse(_kmFinController.text.trim());

              final kmInicio = (recorridoActual['km_inicio'] as num?)?.toInt();

              if (kmFin == null || kmInicio == null || kmFin < kmInicio) {
                _showSnackbar(
                  'El kilometraje final debe ser igual o mayor '
                  'que el kilometraje inicial.',
                );
                return;
              }

              final fechaHoraFin = DateTime.now();
              final inicioRaw = recorridoActual['fecha_inicio'];

              final fechaHoraInicio = inicioRaw is Timestamp
                  ? inicioRaw.toDate()
                  : inicioRaw is DateTime
                  ? inicioRaw
                  : fechaHoraFin;

              final duracion = fechaHoraFin.difference(fechaHoraInicio);

              final kmRecorrido = kmFin - kmInicio;
              final tiempoRecorrido = _formatDuration(duracion);

              try {
                await FirebaseFirestore.instance
                    .collection('recorridos')
                    .doc(recorridoId)
                    .update({
                      'km_fin': kmFin,
                      'km_recorrido': kmRecorrido,
                      'fecha_fin': fechaHoraFin,
                      'fecha_llegada': fechaHoraFin,
                      'hora_llegada_str':
                          '${fechaHoraFin.hour.toString().padLeft(2, '0')}:'
                          '${fechaHoraFin.minute.toString().padLeft(2, '0')}',
                      'fecha_fin_str': _formatDateTime(fechaHoraFin),
                      'tiempo_recorrido_minutos': duracion.inMinutes,
                      'tiempo_recorrido': tiempoRecorrido,
                      'estado': 'completado',
                    });

                await _stopGps();

                if (mounted) {
                  setState(() {
                    _activeTripId = null;
                    _gpsPoints = [];
                  });
                }

                _showSnackbar(
                  'Recorrido finalizado: $kmRecorrido km '
                  'en $tiempoRecorrido.',
                );

                if (context.mounted) {
                  Navigator.pop(context);
                }
              } catch (e) {
                _showSnackbar('No se pudo finalizar el recorrido: $e');
              }
            },
          ),
        ],
      ),
    );
  }

  void _viewMap(String recorridoId, String placa, String vehiculo) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => MapaRecorridoPage(
          recorridoId: recorridoId,
          placa: placa,
          vehiculo: vehiculo,
        ),
      ),
    );
  }

  void _showSnackbar(String mensaje) {
    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(mensaje), duration: const Duration(seconds: 3)),
    );
  }

  @override
  Widget build(BuildContext context) {
    const azul = Color(0xFF17365D);
    const dorado = Color(0xFFC6A34A);
    const fondo = Color(0xFFF4F6FA);

    return Scaffold(
      backgroundColor: fondo,
      appBar: AppBar(
        title: const Text(
          'Control de flota',
          style: TextStyle(fontWeight: FontWeight.w700),
        ),
        backgroundColor: azul,
        foregroundColor: Colors.white,
        elevation: 0,
        actions: [
          if (_tripActive)
            Padding(
              padding: const EdgeInsets.only(right: 16),
              child: Center(
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.14),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: Colors.white24),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.circle, color: Color(0xFF55D187), size: 10),
                      SizedBox(width: 6),
                      Text(
                        'RECORRIDO ACTIVO',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
      floatingActionButton: _tripActive
          ? FloatingActionButton.extended(
              heroTag: 'btnStop',
              backgroundColor: const Color(0xFFB42318),
              foregroundColor: Colors.white,
              icon: const Icon(Icons.flag),
              label: const Text('Finalizar recorrido'),
              onPressed: () async {
                if (_activeTripId == null) return;

                final doc = await FirebaseFirestore.instance
                    .collection('recorridos')
                    .doc(_activeTripId)
                    .get();

                if (doc.exists && mounted) {
                  _showCompletionForm(_activeTripId!, doc.data()!);
                }
              },
            )
          : FloatingActionButton.extended(
              heroTag: 'btnAdd',
              backgroundColor: dorado,
              foregroundColor: azul,
              icon: const Icon(Icons.add_road),
              label: const Text(
                'Iniciar recorrido',
                style: TextStyle(fontWeight: FontWeight.w700),
              ),
              onPressed: _showStartForm,
            ),
      body: StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance
            .collection('recorridos')
            .orderBy('fecha_inicio', descending: true)
            .snapshots(),
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Text(
                  'No se pudieron cargar los recorridos. '
                  'Verifique la conexión y los permisos de Firebase.',
                  textAlign: TextAlign.center,
                ),
              ),
            );
          }

          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }

          final recorridos = snapshot.data!.docs;

          final activos = recorridos.where((doc) {
            final data = doc.data() as Map<String, dynamic>;
            return data['estado'] == 'en_curso' ||
                data['estado'] == 'en_curso_sin_gps';
          }).length;

          final completados = recorridos.where((doc) {
            final data = doc.data() as Map<String, dynamic>;
            return data['estado'] == 'completado';
          }).length;

          return LayoutBuilder(
            builder: (context, constraints) {
              final anchoAmplio = constraints.maxWidth >= 850;
              final padding = anchoAmplio ? 24.0 : 14.0;

              return Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 1400),
                  child: ListView(
                    padding: EdgeInsets.fromLTRB(padding, 20, padding, 100),
                    children: [
                      Text(
                        'Resumen de flota',
                        style: Theme.of(context).textTheme.headlineSmall
                            ?.copyWith(
                              color: azul,
                              fontWeight: FontWeight.w800,
                            ),
                      ),
                      const SizedBox(height: 5),
                      Text(
                        'Consulta los recorridos, kilometrajes y '
                        'tiempos registrados.',
                        style: TextStyle(color: Colors.blueGrey.shade700),
                      ),
                      const SizedBox(height: 18),
                      Wrap(
                        spacing: 12,
                        runSpacing: 12,
                        children: [
                          _resumenCard(
                            'Recorridos registrados',
                            '${recorridos.length}',
                            Icons.route_outlined,
                            azul,
                            anchoAmplio ? 250 : 160,
                          ),
                          _resumenCard(
                            'En curso',
                            '$activos',
                            Icons.near_me_outlined,
                            const Color(0xFF16835D),
                            anchoAmplio ? 210 : 145,
                          ),
                          _resumenCard(
                            'Finalizados',
                            '$completados',
                            Icons.task_alt,
                            dorado,
                            anchoAmplio ? 210 : 145,
                          ),
                        ],
                      ),
                      const SizedBox(height: 24),
                      Row(
                        children: [
                          const Icon(Icons.history, color: azul),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'Historial de recorridos',
                              style: Theme.of(context).textTheme.titleLarge
                                  ?.copyWith(
                                    color: azul,
                                    fontWeight: FontWeight.w800,
                                  ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      if (recorridos.isEmpty)
                        Container(
                          padding: const EdgeInsets.symmetric(
                            vertical: 42,
                            horizontal: 20,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(18),
                            border: Border.all(color: const Color(0xFFE1E7EF)),
                          ),
                          child: const Column(
                            children: [
                              Icon(
                                Icons.directions_car_outlined,
                                size: 52,
                                color: Color(0xFF8A98A9),
                              ),
                              SizedBox(height: 12),
                              Text(
                                'Todavía no hay recorridos',
                                style: TextStyle(
                                  fontSize: 17,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              SizedBox(height: 5),
                              Text(
                                'Pulsa “Iniciar recorrido” para '
                                'registrar el primero.',
                                textAlign: TextAlign.center,
                                style: TextStyle(color: Colors.blueGrey),
                              ),
                            ],
                          ),
                        )
                      else
                        ...recorridos.map((doc) {
                          final r = doc.data() as Map<String, dynamic>;

                          final estaActivo =
                              r['estado'] == 'en_curso' ||
                              r['estado'] == 'en_curso_sin_gps';

                          final kmInicio = r['km_inicio']?.toString() ?? '—';

                          final kmFin = r['km_fin']?.toString() ?? 'Pendiente';

                          final kmRecorrido =
                              r['km_recorrido']?.toString() ?? '—';

                          final destino =
                              (r['destino'] ?? 'Destino no especificado')
                                  .toString();

                          final placa = (r['placa'] ?? 'Sin placa').toString();

                          final conductor = (r['conductor'] ?? 'Sin conductor')
                              .toString();

                          return Container(
                            margin: const EdgeInsets.only(bottom: 12),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(
                                color: estaActivo
                                    ? const Color(0xFF9AD7BA)
                                    : const Color(0xFFE1E7EF),
                              ),
                              boxShadow: const [
                                BoxShadow(
                                  color: Color(0x08000000),
                                  blurRadius: 12,
                                  offset: Offset(0, 3),
                                ),
                              ],
                            ),
                            child: Padding(
                              padding: EdgeInsets.all(anchoAmplio ? 20 : 14),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Container(
                                        width: 46,
                                        height: 46,
                                        decoration: BoxDecoration(
                                          color: estaActivo
                                              ? const Color(0xFFE7F7EF)
                                              : const Color(0xFFEAF0F8),
                                          borderRadius: BorderRadius.circular(
                                            13,
                                          ),
                                        ),
                                        child: Icon(
                                          Icons.directions_car_filled_outlined,
                                          color: estaActivo
                                              ? const Color(0xFF16835D)
                                              : azul,
                                          size: 25,
                                        ),
                                      ),
                                      const SizedBox(width: 12),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              '$placa · '
                                              '${r['vehiculo'] ?? 'Vehículo'}',
                                              style: const TextStyle(
                                                fontSize: 16,
                                                fontWeight: FontWeight.w800,
                                                color: azul,
                                              ),
                                            ),
                                            const SizedBox(height: 3),
                                            Text(
                                              conductor,
                                              style: TextStyle(
                                                color: Colors.blueGrey.shade700,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                      Container(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 10,
                                          vertical: 6,
                                        ),
                                        decoration: BoxDecoration(
                                          color: estaActivo
                                              ? const Color(0xFFE7F7EF)
                                              : const Color(0xFFEAF0F8),
                                          borderRadius: BorderRadius.circular(
                                            20,
                                          ),
                                        ),
                                        child: Text(
                                          estaActivo
                                              ? 'EN CURSO'
                                              : 'FINALIZADO',
                                          style: TextStyle(
                                            fontSize: 10,
                                            letterSpacing: .3,
                                            fontWeight: FontWeight.w800,
                                            color: estaActivo
                                                ? const Color(0xFF13734F)
                                                : azul,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 16),
                                  Container(
                                    width: double.infinity,
                                    padding: const EdgeInsets.all(12),
                                    decoration: BoxDecoration(
                                      color: const Color(0xFFF7F9FC),
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                    child: Row(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        const Icon(
                                          Icons.place_outlined,
                                          color: dorado,
                                        ),
                                        const SizedBox(width: 8),
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: [
                                              const Text(
                                                'DESTINO',
                                                style: TextStyle(
                                                  fontSize: 10,
                                                  letterSpacing: .8,
                                                  fontWeight: FontWeight.w800,
                                                  color: Colors.blueGrey,
                                                ),
                                              ),
                                              const SizedBox(height: 3),
                                              Text(
                                                destino,
                                                style: const TextStyle(
                                                  fontWeight: FontWeight.w600,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  const SizedBox(height: 14),
                                  Wrap(
                                    spacing: 18,
                                    runSpacing: 12,
                                    children: [
                                      _datoRecorrido(
                                        'KM inicial',
                                        '$kmInicio km',
                                        Icons.flag_outlined,
                                      ),
                                      _datoRecorrido(
                                        'KM final',
                                        kmFin == 'Pendiente'
                                            ? kmFin
                                            : '$kmFin km',
                                        Icons.outlined_flag,
                                      ),
                                      _datoRecorrido(
                                        'Distancia',
                                        kmRecorrido == '—'
                                            ? (estaActivo ? 'En curso' : '—')
                                            : '$kmRecorrido km',
                                        Icons.speed,
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 12),
                                  Wrap(
                                    spacing: 18,
                                    runSpacing: 8,
                                    children: [
                                      _datoRecorrido(
                                        'Salida',
                                        (r['fecha_inicio_str'] ?? '—')
                                            .toString(),
                                        Icons.schedule,
                                      ),
                                      if (!estaActivo)
                                        _datoRecorrido(
                                          'Llegada',
                                          (r['fecha_fin_str'] ?? '—')
                                              .toString(),
                                          Icons.event_available,
                                        ),
                                      if (!estaActivo)
                                        _datoRecorrido(
                                          'Duración',
                                          (r['tiempo_recorrido'] ?? '—')
                                              .toString(),
                                          Icons.timelapse,
                                        ),
                                    ],
                                  ),
                                  const SizedBox(height: 14),
                                  Align(
                                    alignment: Alignment.centerRight,
                                    child: estaActivo
                                        ? FilledButton.icon(
                                            onPressed: () =>
                                                _showCompletionForm(doc.id, r),
                                            icon: const Icon(
                                              Icons.flag_outlined,
                                            ),
                                            label: const Text(
                                              'Finalizar recorrido',
                                            ),
                                            style: FilledButton.styleFrom(
                                              backgroundColor: const Color(
                                                0xFF16835D,
                                              ),
                                              foregroundColor: Colors.white,
                                            ),
                                          )
                                        : OutlinedButton.icon(
                                            onPressed: () => _viewMap(
                                              doc.id,
                                              placa,
                                              (r['vehiculo'] ?? '').toString(),
                                            ),
                                            icon: const Icon(
                                              Icons.map_outlined,
                                            ),
                                            label: const Text('Ver mapa'),
                                            style: OutlinedButton.styleFrom(
                                              foregroundColor: azul,
                                              side: const BorderSide(
                                                color: azul,
                                              ),
                                            ),
                                          ),
                                  ),
                                ],
                              ),
                            ),
                          );
                        }),
                    ],
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }

  Widget _resumenCard(
    String titulo,
    String valor,
    IconData icono,
    Color color,
    double ancho,
  ) {
    return Container(
      width: ancho,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(15),
        border: Border.all(color: const Color(0xFFE1E7EF)),
        boxShadow: const [
          BoxShadow(
            color: Color(0x06000000),
            blurRadius: 10,
            offset: Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: color.withOpacity(.12),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icono, color: color),
          ),
          const SizedBox(width: 11),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  valor,
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                    color: color,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  titulo,
                  style: const TextStyle(fontSize: 11, color: Colors.blueGrey),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _datoRecorrido(String etiqueta, String valor, IconData icono) {
    return ConstrainedBox(
      constraints: const BoxConstraints(minWidth: 125, maxWidth: 260),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icono, size: 17, color: const Color(0xFF68788D)),
          const SizedBox(width: 6),
          Flexible(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  etiqueta,
                  style: const TextStyle(fontSize: 11, color: Colors.blueGrey),
                ),
                Text(
                  valor,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                  ),
                  overflow: TextOverflow.ellipsis,
                  maxLines: 2,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _kmInicioController.dispose();
    _kmFinController.dispose();
    _conductorController.dispose();
    _destinoController.dispose();
    _saveTripInBackground();
    super.dispose();
  }
} // ========== PAGINA DEL MAPA ==========

class MapaRecorridoPage extends StatefulWidget {
  final String recorridoId;
  final String placa;
  final String vehiculo;

  const MapaRecorridoPage({
    super.key,
    required this.recorridoId,
    required this.placa,
    required this.vehiculo,
  });

  @override
  State<MapaRecorridoPage> createState() => _MapaRecorridoPageState();
}

class _MapaRecorridoPageState extends State<MapaRecorridoPage> {
  List<LatLng> _points = [];
  List<Map<String, dynamic>> _stops = [];
  bool _loading = true;
  String? _loadError;
  late MapController _mapController;

  @override
  void initState() {
    super.initState();
    _mapController = MapController();
    _loadData();
  }

  Future<void> _loadData() async {
    try {
      final ref = FirebaseFirestore.instance
          .collection('recorridos')
          .doc(widget.recorridoId);
      final puntosTemp = <LatLng>[];

      final bloques = await ref
          .collection('ruta_bloques')
          .orderBy('orden')
          .get();
      for (final b in bloques.docs) {
        final lista = b.data()['puntos'];
        if (lista is List) {
          for (final p in lista) {
            if (p is Map) {
              puntosTemp.add(
                LatLng(
                  (p['lat'] as num).toDouble(),
                  (p['lng'] as num).toDouble(),
                ),
              );
            }
          }
        }
      }

      if (puntosTemp.isEmpty) {
        final viejo = await ref.collection('puntos_gps').orderBy('hora').get();
        for (final d in viejo.docs) {
          final m = d.data();
          puntosTemp.add(
            LatLng((m['lat'] as num).toDouble(), (m['lng'] as num).toDouble()),
          );
        }
      }

      final paradasSnapshot = await ref.collection('paradas').get();

      if (!mounted) return;
      setState(() {
        _points = puntosTemp;
        _stops = paradasSnapshot.docs.map((d) => d.data()).toList();
        _loadError = null;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loadError = 'No se pudieron cargar los datos del mapa.\n$e';
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    const azul = Color(0xFF17365D);

    if (_loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    final centro = _points.isNotEmpty
        ? _points.first
        : const LatLng(9.4325, -82.4429);

    return Scaffold(
      appBar: AppBar(
        title: Text('${widget.placa} - ${widget.vehiculo}'),
        backgroundColor: azul,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            tooltip: 'Actualizar mapa',
            icon: const Icon(Icons.refresh),
            onPressed: () {
              setState(() => _loading = true);
              _loadData();
            },
          ),
        ],
      ),
      body: _loadError != null
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(
                      Icons.cloud_off,
                      size: 48,
                      color: Colors.blueGrey,
                    ),
                    const SizedBox(height: 12),
                    Text(_loadError!, textAlign: TextAlign.center),
                    const SizedBox(height: 12),
                    ElevatedButton.icon(
                      onPressed: () {
                        setState(() => _loading = true);
                        _loadData();
                      },
                      icon: const Icon(Icons.refresh),
                      label: const Text('Reintentar'),
                    ),
                  ],
                ),
              ),
            )
          : _points.isEmpty
          ? const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.location_off_outlined,
                      size: 56,
                      color: Colors.blueGrey,
                    ),
                    SizedBox(height: 12),
                    Text(
                      'No hay puntos GPS registrados para este recorrido.',
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),
            )
          : FlutterMap(
              mapController: _mapController,
              options: MapOptions(
                initialCenter: centro,
                initialZoom: 14,
                initialCameraFit: _points.length > 1
                    ? CameraFit.bounds(
                        bounds: LatLngBounds.fromPoints(_points),
                        padding: const EdgeInsets.all(40),
                      )
                    : null,
              ),
              children: [
                TileLayer(
                  urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                  userAgentPackageName: 'com.ministerio.publico.cbt',
                ),
                if (_points.isNotEmpty)
                  PolylineLayer(
                    polylines: [
                      Polyline(
                        points: _points,
                        strokeWidth: 4,
                        color: const Color(0xFF2F65B0),
                      ),
                    ],
                  ),
                MarkerLayer(
                  markers: [
                    if (_points.isNotEmpty)
                      Marker(
                        point: _points.first,
                        width: 50,
                        height: 50,
                        child: const Icon(
                          Icons.location_on,
                          color: Colors.green,
                          size: 40,
                        ),
                      ),
                    if (_points.length > 1)
                      Marker(
                        point: _points.last,
                        width: 50,
                        height: 50,
                        child: const Icon(
                          Icons.location_on,
                          color: Colors.red,
                          size: 40,
                        ),
                      ),
                    for (final stop in _stops)
                      if (stop['ubicacion'] is GeoPoint)
                        Marker(
                          point: LatLng(
                            (stop['ubicacion'] as GeoPoint).latitude,
                            (stop['ubicacion'] as GeoPoint).longitude,
                          ),
                          width: 45,
                          height: 45,
                          child: const Icon(
                            Icons.pause_circle,
                            color: Colors.orange,
                            size: 35,
                          ),
                        ),
                  ],
                ),
              ],
            ),
    );
  }
}
