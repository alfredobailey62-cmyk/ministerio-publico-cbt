import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:geolocator/geolocator.dart';
import 'package:shared_preferences/shared_preferences.dart';

class RecorridosPage extends StatefulWidget {
  const RecorridosPage({super.key});

  @override
  State<RecorridosPage> createState() => _RecorridosPageState();
}

class _RecorridosPageState extends State<RecorridosPage> {
  final _kmInicioController = TextEditingController();
  final _kmFinController = TextEditingController();
  final _conductorController = TextEditingController();
  final _destinoController = TextEditingController();

  String? _vehiculoSeleccionado;
  String? _placaSeleccionada;
  String? _marcaModelo;

  List<Map<String, dynamic>> _puntosGPS = [];
  StreamSubscription<Position>? _posicionStream;
  bool _recorridoActivo = false;
  String? _recorridoIdActivo;

  Position? _ultimaPosicion;
  DateTime? _inicioParada;
  bool _enParada = false;
  List<Map<String, dynamic>> _puntosParada = [];

  static const double DISTANCIA_PARADA = 5.0;
  static const int TIEMPO_PARADA_MINUTOS = 5;

  SharedPreferences? _prefs;

  @override
  void initState() {
    super.initState();
    _cargarRecorridoActivo();
  }

  Future<void> _cargarRecorridoActivo() async {
    _prefs = await SharedPreferences.getInstance();
    final recorridoGuardado = _prefs?.getString('recorrido_activo_id');
    final puntosGuardados = _prefs?.getString('puntos_activos');

    if (recorridoGuardado != null) {
      if (!mounted) return;

      setState(() {
        _recorridoIdActivo = recorridoGuardado;
        _recorridoActivo = true;
      });

      if (puntosGuardados != null) {
        final puntos = json.decode(puntosGuardados) as List;
        _puntosGPS = puntos
            .map((e) => Map<String, dynamic>.from(e))
            .toList();
      }

      _reanudarGPS();
    }
  }

  Future<void> _guardarRecorridoEnBackground() async {
    if (_recorridoIdActivo != null) {
      await _prefs?.setString(
        'recorrido_activo_id',
        _recorridoIdActivo!,
      );
      await _prefs?.setString(
        'puntos_activos',
        json.encode(_puntosGPS),
      );
    }
  }

  Future<void> _reanudarGPS() async {
    final servicioActivo = await Geolocator.isLocationServiceEnabled();
    if (!servicioActivo) return;

    LocationPermission permiso = await Geolocator.checkPermission();

    if (permiso != LocationPermission.always &&
        permiso != LocationPermission.whileInUse) {
      permiso = await Geolocator.requestPermission();

      if (permiso != LocationPermission.always &&
          permiso != LocationPermission.whileInUse) {
        return;
      }
    }

    _posicionStream?.cancel();

    _posicionStream = Geolocator.getPositionStream(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.bestForNavigation,
        distanceFilter: 5,
      ),
    ).listen((Position position) async {
      final punto = {
        'lat': position.latitude,
        'lng': position.longitude,
        'hora': DateTime.now().toIso8601String(),
      };

      _puntosGPS.add(punto);
      await _guardarRecorridoEnBackground();
      _detectarParada(position);

      try {
        if (_recorridoIdActivo != null) {
          await FirebaseFirestore.instance
              .collection('recorridos')
              .doc(_recorridoIdActivo)
              .collection('puntos_gps')
              .doc('${DateTime.now().microsecondsSinceEpoch}')
              .set(punto);
        }
      } catch (e) {
        await _guardarPuntoOffline(punto);
      }
    });
  }

  Future<void> _guardarPuntoOffline(
    Map<String, dynamic> punto,
  ) async {
    // Cada punto queda ligado al recorrido que lo generó.
    // Así no se mezcla con otro recorrido al recuperar conexión.
    final pendientes =
        _prefs?.getStringList('puntos_pendientes') ?? [];
    final puntoSeguro = <String, dynamic>{
      ...punto,
      'recorrido_id': _recorridoIdActivo,
      'punto_id': punto['punto_id'] ??
          '${DateTime.now().microsecondsSinceEpoch}',
    };

    pendientes.add(json.encode(puntoSeguro));
    await _prefs?.setStringList('puntos_pendientes', pendientes);
  }

  Future<void> _sincronizarPuntosOffline() async {
    final pendientes =
        _prefs?.getStringList('puntos_pendientes') ?? [];
    if (pendientes.isEmpty) return;

    final noSincronizados = <String>[];
    for (final puntoJson in pendientes) {
      try {
        final punto =
            Map<String, dynamic>.from(json.decode(puntoJson) as Map);
        final recorridoId = punto['recorrido_id']?.toString();
        final puntoId = punto['punto_id']?.toString();
        if (recorridoId == null || recorridoId.isEmpty ||
            puntoId == null || puntoId.isEmpty) {
          // Los puntos antiguos no tenían recorrido_id. Se conservan
          // pendientes en lugar de asignarlos al recorrido equivocado.
          noSincronizados.add(puntoJson);
          continue;
        }

        punto.remove('recorrido_id');
        punto.remove('punto_id');
        await FirebaseFirestore.instance
            .collection('recorridos')
            .doc(recorridoId)
            .collection('puntos_gps')
            .doc(puntoId)
            .set(punto, SetOptions(merge: true));
      } catch (_) {
        noSincronizados.add(puntoJson);
      }
    }

    await _prefs?.setStringList('puntos_pendientes', noSincronizados);
  }

  void _detectarParada(Position posicionActual) {
    if (_ultimaPosicion != null) {
      final distancia = Geolocator.distanceBetween(
        _ultimaPosicion!.latitude,
        _ultimaPosicion!.longitude,
        posicionActual.latitude,
        posicionActual.longitude,
      );

      if (distancia < DISTANCIA_PARADA) {
        if (!_enParada) {
          _enParada = true;
          _inicioParada = DateTime.now();
          _puntosParada.clear();
        }

        _puntosParada.add({
          'lat': posicionActual.latitude,
          'lng': posicionActual.longitude,
          'hora': DateTime.now().toIso8601String(),
        });

        if (DateTime.now()
                .difference(_inicioParada!)
                .inMinutes >=
            TIEMPO_PARADA_MINUTOS) {
          _registrarParada();
        }
      } else {
        if (_enParada) {
          _registrarParada();
          _enParada = false;
          _inicioParada = null;
          _puntosParada.clear();
        }
      }
    }

    _ultimaPosicion = posicionActual;
  }

  Future<void> _registrarParada() async {
    if (_recorridoIdActivo == null || _puntosParada.isEmpty) {
      return;
    }

    if (_inicioParada == null) return;

    final avgLat = _puntosParada
            .map((p) => p['lat'] as double)
            .reduce((a, b) => a + b) /
        _puntosParada.length;

    final avgLng = _puntosParada
            .map((p) => p['lng'] as double)
            .reduce((a, b) => a + b) /
        _puntosParada.length;

    final duracion =
        DateTime.now().difference(_inicioParada!).inMinutes;

    await FirebaseFirestore.instance
        .collection('recorridos')
        .doc(_recorridoIdActivo)
        .collection('paradas')
        .add({
      'ubicacion': GeoPoint(avgLat, avgLng),
      'inicio': _inicioParada,
      'fin': DateTime.now(),
      'duracion_minutos': duracion,
      'puntos': _puntosParada,
    });
  }  Future<bool> _iniciarGPS() async {
    final servicioActivo =
        await Geolocator.isLocationServiceEnabled();

    if (!servicioActivo) {
      _mostrarSnackbar('Active el GPS del dispositivo');
      return false;
    }

    LocationPermission permiso =
        await Geolocator.checkPermission();

    if (permiso == LocationPermission.denied) {
      permiso = await Geolocator.requestPermission();

      if (permiso == LocationPermission.denied) {
        _mostrarSnackbar('Se necesita permiso de ubicación');
        return false;
      }
    }

    if (permiso == LocationPermission.deniedForever) {
      _mostrarSnackbar(
        'El permiso de ubicación está denegado permanentemente',
      );
      return false;
    }

    _puntosGPS.clear();
    _ultimaPosicion = null;
    _inicioParada = null;
    _enParada = false;
    _puntosParada.clear();

    _posicionStream?.cancel();

    _posicionStream = Geolocator.getPositionStream(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.bestForNavigation,
        distanceFilter: 5,
      ),
    ).listen((Position position) async {
      final punto = {
        'lat': position.latitude,
        'lng': position.longitude,
        'hora': DateTime.now().toIso8601String(),
      };

      _puntosGPS.add(punto);

      await _guardarRecorridoEnBackground();
      _detectarParada(position);

      try {
        if (_recorridoIdActivo != null) {
          await FirebaseFirestore.instance
              .collection('recorridos')
              .doc(_recorridoIdActivo)
              .collection('puntos_gps')
              .doc('${DateTime.now().microsecondsSinceEpoch}')
              .set(punto);
        }
      } catch (e) {
        await _guardarPuntoOffline(punto);
      }
    });

    if (mounted) {
      setState(() => _recorridoActivo = true);
    }

    _mostrarSnackbar('GPS activado. Grabando recorrido');
    return true;
  }

  Future<void> _detenerGPS() async {
    if (_enParada && _inicioParada != null) {
      final duracionParada =
          DateTime.now().difference(_inicioParada!);

      if (duracionParada.inMinutes >= TIEMPO_PARADA_MINUTOS) {
        await _registrarParada();
      }
    }

    await _posicionStream?.cancel();
    _posicionStream = null;

    await _sincronizarPuntosOffline();

    await _prefs?.remove('recorrido_activo_id');
    await _prefs?.remove('puntos_activos');

    if (mounted) {
      setState(() => _recorridoActivo = false);
    }
  }

  String _formatearFechaHora(DateTime fecha) {
    final dia = fecha.day.toString().padLeft(2, '0');
    final mes = fecha.month.toString().padLeft(2, '0');
    final anio = fecha.year;
    final hora = fecha.hour.toString().padLeft(2, '0');
    final minuto = fecha.minute.toString().padLeft(2, '0');

    return '$dia/$mes/$anio $hora:$minuto';
  }

  String _formatearDuracion(Duration duracion) {
    final horas = duracion.inHours;
    final minutos = duracion.inMinutes.remainder(60);

    if (horas > 0) {
      return '$horas h $minutos min';
    }

    return '$minutos min';
  }

  void _mostrarFormularioInicio() {
    _kmInicioController.clear();
    _conductorController.clear();
    _destinoController.clear();

    _vehiculoSeleccionado = null;
    _placaSeleccionada = null;
    _marcaModelo = null;

    showDialog(
      context: context,
      builder: (_) => StatefulBuilder(
        builder: (context, setStateDialog) => AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          title: const Row(
            children: [
              Icon(
                Icons.add_road,
                color: Color(0xFF17365D),
              ),
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
                        return const Center(
                          child: CircularProgressIndicator(),
                        );
                      }

                      final vehiculos = snapshot.data!.docs;

                      if (vehiculos.isEmpty) {
                        return const Text(
                          'No hay vehículos registrados.',
                        );
                      }

                      return DropdownButtonFormField<String>(
                        isExpanded: true,
                        value: _vehiculoSeleccionado,
                        hint: const Text('Seleccione un vehículo'),
                        items: vehiculos.map((v) {
                          final data =
                              v.data() as Map<String, dynamic>;

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

                          final data = vehiculo.data()
                              as Map<String, dynamic>;

                          setStateDialog(() {
                            _vehiculoSeleccionado = valor;
                            _placaSeleccionada =
                                data['placa']?.toString() ?? '';
                            _marcaModelo =
                                '${data['marca'] ?? ''} '
                                '${data['modelo'] ?? ''}'.trim();
                          });
                        },
                        decoration: InputDecoration(
                          labelText: 'Vehículo',
                          prefixIcon: const Icon(
                            Icons.directions_car_outlined,
                          ),
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
                        Icon(
                          Icons.schedule,
                          color: Color(0xFF17365D),
                        ),
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
                final kmInicio =
                    int.tryParse(_kmInicioController.text.trim());

                if (kmInicio == null ||
                    kmInicio < 0 ||
                    _vehiculoSeleccionado == null ||
                    _conductorController.text.trim().isEmpty ||
                    _destinoController.text.trim().isEmpty) {
                  _mostrarSnackbar(
                    'Complete todos los campos con datos válidos.',
                  );
                  return;
                }

                final fechaHoraInicio = DateTime.now();

                try {
                  final docRef = await FirebaseFirestore.instance
                      .collection('recorridos')
                      .add({
                    'vehiculo_id': _vehiculoSeleccionado,
                    'placa': _placaSeleccionada,
                    'vehiculo': _marcaModelo,
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
                    'fecha_inicio_str':
                        _formatearFechaHora(fechaHoraInicio),
                    'fecha_fin': null,
                    'fecha_llegada': null,
                    'tiempo_recorrido': null,
                    'tiempo_recorrido_minutos': null,
                    'mes': fechaHoraInicio.month,
                    'anio': fechaHoraInicio.year,
                    'estado': 'en_curso',
                  });

                  _recorridoIdActivo = docRef.id;
                  await _guardarRecorridoEnBackground();

                  final gpsIniciado = await _iniciarGPS();

                  if (!gpsIniciado) {
                    await FirebaseFirestore.instance
                        .collection('recorridos')
                        .doc(docRef.id)
                        .update({
                      'estado': 'en_curso_sin_gps',
                    });

                    if (mounted) {
                      setState(() {
                        _recorridoActivo = false;
                        _recorridoIdActivo = null;
                      });
                    }

                    _mostrarSnackbar(
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
                      _recorridoActivo = true;
                    });
                  }

                  _mostrarSnackbar('Recorrido iniciado correctamente.');

                  if (context.mounted) {
                    Navigator.pop(context);
                  }
                } catch (e) {
                  _mostrarSnackbar(
                    'No se pudo iniciar el recorrido: $e',
                  );
                }
              },
            ),
          ],
        ),
      ),
    );
  }

  void _mostrarFormularioFinalizacion(
    String recorridoId,
    Map<String, dynamic> recorridoActual,
  ) {
    _kmFinController.clear();

    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
        ),
        title: const Row(
          children: [
            Icon(
              Icons.flag_outlined,
              color: Color(0xFF17365D),
            ),
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
                    Text(
                      'Conductor: ${recorridoActual['conductor'] ?? '—'}',
                    ),
                    Text(
                      'Destino: ${recorridoActual['destino'] ?? '—'}',
                    ),
                    Text(
                      'Salida: ${recorridoActual['fecha_inicio_str'] ?? '—'}',
                    ),
                    const Divider(),
                    Text(
                      'Kilometraje inicial: '
                      '${recorridoActual['km_inicio']} km',
                      style: const TextStyle(
                        fontWeight: FontWeight.w700,
                      ),
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
              final kmFin =
                  int.tryParse(_kmFinController.text.trim());

              final kmInicio = (recorridoActual['km_inicio'] as num?)
                  ?.toInt();

              if (kmFin == null ||
                  kmInicio == null ||
                  kmFin < kmInicio) {
                _mostrarSnackbar(
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

              final duracion =
                  fechaHoraFin.difference(fechaHoraInicio);

              final kmRecorrido = kmFin - kmInicio;
              final tiempoRecorrido = _formatearDuracion(duracion);

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
                  'fecha_fin_str':
                      _formatearFechaHora(fechaHoraFin),
                  'tiempo_recorrido_minutos': duracion.inMinutes,
                  'tiempo_recorrido': tiempoRecorrido,
                  'estado': 'completado',
                });

                await _detenerGPS();

                if (mounted) {
                  setState(() {
                    _recorridoIdActivo = null;
                    _puntosGPS = [];
                  });
                }

                _mostrarSnackbar(
                  'Recorrido finalizado: $kmRecorrido km '
                  'en $tiempoRecorrido.',
                );

                if (context.mounted) {
                  Navigator.pop(context);
                }
              } catch (e) {
                _mostrarSnackbar(
                  'No se pudo finalizar el recorrido: $e',
                );
              }
            },
          ),
        ],
      ),
    );
  }

  void _verMapa(
    String recorridoId,
    String placa,
    String vehiculo,
  ) {
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

  void _mostrarSnackbar(String mensaje) {
    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(mensaje),
        duration: const Duration(seconds: 3),
      ),
    );
  }  @override
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
          if (_recorridoActivo)
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
                      Icon(
                        Icons.circle,
                        color: Color(0xFF55D187),
                        size: 10,
                      ),
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
      floatingActionButton: _recorridoActivo
          ? FloatingActionButton.extended(
              heroTag: 'btnStop',
              backgroundColor: const Color(0xFFB42318),
              foregroundColor: Colors.white,
              icon: const Icon(Icons.flag),
              label: const Text('Finalizar recorrido'),
              onPressed: () async {
                if (_recorridoIdActivo == null) return;

                final doc = await FirebaseFirestore.instance
                    .collection('recorridos')
                    .doc(_recorridoIdActivo)
                    .get();

                if (doc.exists && mounted) {
                  _mostrarFormularioFinalizacion(
                    _recorridoIdActivo!,
                    doc.data()!,
                  );
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
              onPressed: _mostrarFormularioInicio,
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
            return const Center(
              child: CircularProgressIndicator(),
            );
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
                  constraints: const BoxConstraints(
                    maxWidth: 1400,
                  ),
                  child: ListView(
                    padding: EdgeInsets.fromLTRB(
                      padding,
                      20,
                      padding,
                      100,
                    ),
                    children: [
                      Text(
                        'Resumen de flota',
                        style: Theme.of(context)
                            .textTheme
                            .headlineSmall
                            ?.copyWith(
                              color: azul,
                              fontWeight: FontWeight.w800,
                            ),
                      ),
                      const SizedBox(height: 5),
                      Text(
                        'Consulta los recorridos, kilometrajes y '
                        'tiempos registrados.',
                        style: TextStyle(
                          color: Colors.blueGrey.shade700,
                        ),
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
                          const Icon(
                            Icons.history,
                            color: azul,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'Historial de recorridos',
                              style: Theme.of(context)
                                  .textTheme
                                  .titleLarge
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
                            border: Border.all(
                              color: const Color(0xFFE1E7EF),
                            ),
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
                                style: TextStyle(
                                  color: Colors.blueGrey,
                                ),
                              ),
                            ],
                          ),
                        )
                      else
                        ...recorridos.map((doc) {
                          final r =
                              doc.data() as Map<String, dynamic>;

                          final estaActivo =
                              r['estado'] == 'en_curso' ||
                              r['estado'] == 'en_curso_sin_gps';

                          final kmInicio =
                              r['km_inicio']?.toString() ?? '—';

                          final kmFin =
                              r['km_fin']?.toString() ?? 'Pendiente';

                          final kmRecorrido =
                              r['km_recorrido']?.toString() ?? '—';

                          final destino =
                              (r['destino'] ??
                                      'Destino no especificado')
                                  .toString();

                          final placa =
                              (r['placa'] ?? 'Sin placa').toString();

                          final conductor =
                              (r['conductor'] ?? 'Sin conductor')
                                  .toString();

                          return Container(
                            margin: const EdgeInsets.only(
                              bottom: 12,
                            ),
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
                              padding: EdgeInsets.all(
                                anchoAmplio ? 20 : 14,
                              ),
                              child: Column(
                                crossAxisAlignment:
                                    CrossAxisAlignment.start,
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
                                          borderRadius:
                                              BorderRadius.circular(13),
                                        ),
                                        child: Icon(
                                          Icons
                                              .directions_car_filled_outlined,
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
                                                fontWeight:
                                                    FontWeight.w800,
                                                color: azul,
                                              ),
                                            ),
                                            const SizedBox(height: 3),
                                            Text(
                                              conductor,
                                              style: TextStyle(
                                                color: Colors
                                                    .blueGrey.shade700,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                      Container(
                                        padding:
                                            const EdgeInsets.symmetric(
                                          horizontal: 10,
                                          vertical: 6,
                                        ),
                                        decoration: BoxDecoration(
                                          color: estaActivo
                                              ? const Color(0xFFE7F7EF)
                                              : const Color(0xFFEAF0F8),
                                          borderRadius:
                                              BorderRadius.circular(20),
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
                                      borderRadius:
                                          BorderRadius.circular(12),
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
                                                  fontWeight:
                                                      FontWeight.w800,
                                                  color: Colors.blueGrey,
                                                ),
                                              ),
                                              const SizedBox(height: 3),
                                              Text(
                                                destino,
                                                style: const TextStyle(
                                                  fontWeight:
                                                      FontWeight.w600,
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
                                            ? (estaActivo
                                                ? 'En curso'
                                                : '—')
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
                                                _mostrarFormularioFinalizacion(
                                              doc.id,
                                              r,
                                            ),
                                            icon: const Icon(
                                              Icons.flag_outlined,
                                            ),
                                            label: const Text(
                                              'Finalizar recorrido',
                                            ),
                                            style: FilledButton.styleFrom(
                                              backgroundColor:
                                                  const Color(0xFF16835D),
                                              foregroundColor: Colors.white,
                                            ),
                                          )
                                        : OutlinedButton.icon(
                                            onPressed: () => _verMapa(
                                              doc.id,
                                              placa,
                                              (r['vehiculo'] ?? '')
                                                  .toString(),
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
        border: Border.all(
          color: const Color(0xFFE1E7EF),
        ),
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
                  style: const TextStyle(
                    fontSize: 11,
                    color: Colors.blueGrey,
                  ),
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

  Widget _datoRecorrido(
    String etiqueta,
    String valor,
    IconData icono,
  ) {
    return ConstrainedBox(
      constraints: const BoxConstraints(
        minWidth: 125,
        maxWidth: 260,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            icono,
            size: 17,
            color: const Color(0xFF68788D),
          ),
          const SizedBox(width: 6),
          Flexible(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  etiqueta,
                  style: const TextStyle(
                    fontSize: 11,
                    color: Colors.blueGrey,
                  ),
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
    _posicionStream?.cancel();
    super.dispose();
  }
}// ========== PAGINA DEL MAPA ==========

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
  State<MapaRecorridoPage> createState() =>
      _MapaRecorridoPageState();
}

class _MapaRecorridoPageState extends State<MapaRecorridoPage> {
  List<LatLng> _puntos = [];
  List<Map<String, dynamic>> _paradas = [];
  bool _cargando = true;
  String? _errorCarga;
  late MapController _mapController;

  @override
  void initState() {
    super.initState();
    _mapController = MapController();
    _cargarDatos();
  }

  Future<void> _cargarDatos() async {
    try {
      final puntosSnapshot = await FirebaseFirestore.instance
          .collection('recorridos')
          .doc(widget.recorridoId)
          .collection('puntos_gps')
          .orderBy('hora')
          .get();

      final puntosTemp = <LatLng>[];

      for (final doc in puntosSnapshot.docs) {
        final lat = doc['lat'];
        final lng = doc['lng'];

        puntosTemp.add(
          LatLng(
            (lat as num).toDouble(),
            (lng as num).toDouble(),
          ),
        );
      }

      final paradasSnapshot = await FirebaseFirestore.instance
          .collection('recorridos')
          .doc(widget.recorridoId)
          .collection('paradas')
          .get();

      if (!mounted) return;

      setState(() {
        _puntos = puntosTemp;
        _paradas = paradasSnapshot.docs
            .map((d) => d.data())
            .toList();
        _errorCarga = null;
        _cargando = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _errorCarga = 'No se pudieron cargar los datos del mapa. '
            'Compruebe la conexión y los permisos de Firebase.\n$e';
        _cargando = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    const azul = Color(0xFF17365D);

    if (_cargando) {
      return const Scaffold(
        body: Center(
          child: CircularProgressIndicator(),
        ),
      );
    }

    final centro = _puntos.isNotEmpty
        ? _puntos.first
        : const LatLng(9.4325, -82.4429);

    return Scaffold(
      appBar: AppBar(
        title: Text(
          '${widget.placa} - ${widget.vehiculo}',
        ),
        backgroundColor: azul,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            tooltip: 'Actualizar mapa',
            icon: const Icon(Icons.refresh),
            onPressed: () {
              setState(() => _cargando = true);
              _cargarDatos();
            },
          ),
        ],
      ),
      body: _errorCarga != null
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.cloud_off, size: 48, color: Colors.blueGrey),
                    const SizedBox(height: 12),
                    Text(_errorCarga!, textAlign: TextAlign.center),
                    const SizedBox(height: 12),
                    ElevatedButton.icon(
                      onPressed: () {
                        setState(() => _cargando = true);
                        _cargarDatos();
                      },
                      icon: const Icon(Icons.refresh),
                      label: const Text('Reintentar'),
                    ),
                  ],
                ),
              ),
            )
          : _puntos.isEmpty
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
              ),
              children: [
                TileLayer(
                  urlTemplate:
                      'https://{s}.basemaps.cartocdn.com/light_all/'
                      '{z}/{x}/{y}.png',
                  subdomains: const ['a', 'b', 'c'],
                  userAgentPackageName:
                      'com.ministerio.publico.cbt',
                ),
                if (_puntos.isNotEmpty)
                  PolylineLayer(
                    polylines: [
                      Polyline(
                        points: _puntos,
                        strokeWidth: 4,
                        color: const Color(0xFF2F65B0),
                      ),
                    ],
                  ),
                MarkerLayer(
                  markers: [
                    if (_puntos.isNotEmpty)
                      Marker(
                        point: _puntos.first,
                        width: 50,
                        height: 50,
                        child: const Icon(
                          Icons.location_on,
                          color: Colors.green,
                          size: 40,
                        ),
                      ),
                    if (_puntos.length > 1)
                      Marker(
                        point: _puntos.last,
                        width: 50,
                        height: 50,
                        child: const Icon(
                          Icons.location_on,
                          color: Colors.red,
                          size: 40,
                        ),
                      ),
                    for (final parada in _paradas)
                      if (parada['ubicacion'] is GeoPoint)
                        Marker(
                          point: LatLng(
                            (parada['ubicacion'] as GeoPoint)
                                .latitude,
                            (parada['ubicacion'] as GeoPoint)
                                .longitude,
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