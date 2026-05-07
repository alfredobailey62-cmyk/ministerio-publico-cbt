import 'dart:async';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:geolocator/geolocator.dart';

class RecorridosPage extends StatefulWidget {
  const RecorridosPage({super.key});

  @override
  State<RecorridosPage> createState() => _RecorridosPageState();
}

class _RecorridosPageState extends State<RecorridosPage> {
  final _kmInicioController = TextEditingController();
  final _kmFinController = TextEditingController();
  final _fiscaliaController = TextEditingController();
  final _diligenciaController = TextEditingController();
  final _conductorController = TextEditingController();
  final _carpetaController = TextEditingController();

  String? _vehiculoSeleccionado;
  String? _placaSeleccionada;
  String? _marcaModelo;

  List<Map<String, dynamic>> _puntosGPS = [];
  StreamSubscription<Position>? _posicionStream;
  bool _recorridoActivo = false;
  String? _recorridoIdActivo;

  // Configuración para detección de paradas
  Position? _ultimaPosicion;
  DateTime? _inicioParada;
  bool _enParada = false;
  List<Map<String, dynamic>> _puntosParada = [];

  static const double DISTANCIA_PARADA = 5.0;
  static const int TIEMPO_PARADA_MINUTOS = 5;

  // ========== FUNCIONES DE GPS ==========

  Future<bool> _iniciarGPS() async {
    print('🟢 Iniciando GPS...');

    bool servicioActivo = await Geolocator.isLocationServiceEnabled();
    if (!servicioActivo) {
      _mostrarSnackbar('Active el GPS del dispositivo');
      return false;
    }

    LocationPermission permiso = await Geolocator.checkPermission();

    if (permiso == LocationPermission.denied) {
      permiso = await Geolocator.requestPermission();
      if (permiso == LocationPermission.denied) {
        _mostrarSnackbar('Se necesita permiso de ubicación');
        return false;
      }
    }

    if (permiso == LocationPermission.deniedForever) {
      _mostrarSnackbar('Permiso de ubicación denegado permanentemente');
      return false;
    }

    _puntosGPS.clear();
    _ultimaPosicion = null;
    _inicioParada = null;
    _enParada = false;
    _puntosParada.clear();

    _posicionStream = Geolocator.getPositionStream(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.bestForNavigation,
        distanceFilter: 5,
      ),
    ).listen((Position position) {
      final punto = {
        'lat': position.latitude,
        'lng': position.longitude,
        'hora': DateTime.now().toIso8601String(),
      };
      _puntosGPS.add(punto);
      _detectarParada(position);
    });

    setState(() => _recorridoActivo = true);
    _mostrarSnackbar('GPS activado - Grabando recorrido');
    return true;
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
          _puntosParada.add({
            'lat': posicionActual.latitude,
            'lng': posicionActual.longitude,
            'hora': DateTime.now().toIso8601String(),
          });
        } else {
          _puntosParada.add({
            'lat': posicionActual.latitude,
            'lng': posicionActual.longitude,
            'hora': DateTime.now().toIso8601String(),
          });
          
          final duracionParada = DateTime.now().difference(_inicioParada!);
          if (duracionParada.inMinutes >= TIEMPO_PARADA_MINUTOS) {
            _registrarParada();
          }
        }
      } else {
        if (_enParada) {
          final duracionParada = DateTime.now().difference(_inicioParada!);
          if (duracionParada.inMinutes >= TIEMPO_PARADA_MINUTOS) {
            _registrarParada();
          }
          _enParada = false;
          _inicioParada = null;
          _puntosParada.clear();
        }
      }
    }
    _ultimaPosicion = posicionActual;
  }

  Future<void> _registrarParada() async {
    if (_recorridoIdActivo == null || _puntosParada.isEmpty) return;
    
    double avgLat = _puntosParada.map((p) => p['lat'] as double).reduce((a, b) => a + b) / _puntosParada.length;
    double avgLng = _puntosParada.map((p) => p['lng'] as double).reduce((a, b) => a + b) / _puntosParada.length;
    
    final duracion = DateTime.now().difference(_inicioParada!).inMinutes;
    
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
  }

  Future<void> _detenerGPS() async {
    if (_enParada && _inicioParada != null) {
      final duracionParada = DateTime.now().difference(_inicioParada!);
      if (duracionParada.inMinutes >= TIEMPO_PARADA_MINUTOS) {
        await _registrarParada();
      }
    }
    await _posicionStream?.cancel();
    setState(() => _recorridoActivo = false);
  }

  // ========== PASO 1: CREAR RECORRIDO ==========

  void _mostrarFormularioInicio() {
    _kmInicioController.clear();
    _fiscaliaController.clear();
    _diligenciaController.clear();
    _conductorController.clear();
    _carpetaController.clear();
    _vehiculoSeleccionado = null;

    showDialog(
      context: context,
      builder: (_) => StatefulBuilder(
        builder: (context, setStateDialog) => AlertDialog(
          title: const Text('Iniciar Recorrido'),
          content: SizedBox(
            width: 300,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  StreamBuilder<QuerySnapshot>(
                    stream: FirebaseFirestore.instance.collection('vehiculos').snapshots(),
                    builder: (context, snapshot) {
                      if (!snapshot.hasData) return const CircularProgressIndicator();
                      final vehiculos = snapshot.data!.docs;
                      return DropdownButtonFormField<String>(
                        isExpanded: true,
                        hint: const Text('Seleccione vehículo'),
                        value: _vehiculoSeleccionado,
                        items: vehiculos.map((v) {
                          final data = v.data() as Map<String, dynamic>;
                          return DropdownMenuItem(
                            value: v.id,
                            child: Text('${data['placa']} - ${data['marca']} ${data['modelo']}'),
                          );
                        }).toList(),
                        onChanged: (val) {
                          final v = vehiculos.firstWhere((e) => e.id == val);
                          final data = v.data() as Map<String, dynamic>;
                          setStateDialog(() {
                            _vehiculoSeleccionado = val;
                            _placaSeleccionada = data['placa'];
                            _marcaModelo = '${data['marca']} ${data['modelo']}';
                          });
                        },
                        decoration: const InputDecoration(
                          labelText: 'Vehículo *',
                          border: OutlineInputBorder(),
                        ),
                      );
                    },
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _conductorController,
                    decoration: const InputDecoration(
                      labelText: 'Conductor *',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _kmInicioController,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: 'Kilometraje inicial *',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancelar'),
            ),
            ElevatedButton(
              onPressed: () async {
                final kmInicio = int.tryParse(_kmInicioController.text);
                if (kmInicio == null || _vehiculoSeleccionado == null || _conductorController.text.isEmpty) {
                  _mostrarSnackbar('Complete todos los campos');
                  return;
                }

                bool gpsIniciado = await _iniciarGPS();
                if (!gpsIniciado) return;

                final docRef = await FirebaseFirestore.instance.collection('recorridos').add({
                  'vehiculo_id': _vehiculoSeleccionado,
                  'placa': _placaSeleccionada,
                  'vehiculo': _marcaModelo,
                  'conductor': _conductorController.text,
                  'km_inicio': kmInicio,
                  'km_fin': null,
                  'km_recorrido': null,
                  'fecha_inicio': DateTime.now(),
                  'fecha_fin': null,
                  'mes': DateTime.now().month,
                  'anio': DateTime.now().year,
                  'estado': 'en_curso',
                });

                setState(() => _recorridoIdActivo = docRef.id);
                _mostrarSnackbar('Recorrido iniciado');
                if (context.mounted) Navigator.pop(context);
              },
              child: const Text('Iniciar'),
            ),
          ],
        ),
      ),
    );
  }

  // ========== PASO 2: FINALIZAR RECORRIDO ==========

  void _mostrarFormularioFinalizacion(String recorridoId, Map<String, dynamic> recorridoActual) {
    _kmFinController.clear();

    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Finalizar Recorrido'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('Vehículo: ${recorridoActual['placa']}'),
            Text('Km inicial: ${recorridoActual['km_inicio']}'),
            const SizedBox(height: 16),
            TextField(
              controller: _kmFinController,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: 'Kilometraje final *',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            onPressed: () async {
              final kmFin = int.tryParse(_kmFinController.text);
              if (kmFin == null || kmFin <= (recorridoActual['km_inicio'] as int)) {
                _mostrarSnackbar('Kilometraje inválido');
                return;
              }

              await _detenerGPS();
              final kmRecorrido = kmFin - (recorridoActual['km_inicio'] as int);

              await FirebaseFirestore.instance.collection('recorridos').doc(recorridoId).update({
                'km_fin': kmFin,
                'km_recorrido': kmRecorrido,
                'fecha_fin': DateTime.now(),
                'estado': 'completado',
              });

              if (_puntosGPS.isNotEmpty) {
                for (var punto in _puntosGPS) {
                  await FirebaseFirestore.instance
                      .collection('recorridos')
                      .doc(recorridoId)
                      .collection('puntos_gps')
                      .add(punto);
                }
              }

              setState(() {
                _recorridoIdActivo = null;
                _puntosGPS = [];
              });

              _mostrarSnackbar('Recorrido finalizado');
              if (context.mounted) Navigator.pop(context);
            },
            child: const Text('Finalizar'),
          ),
        ],
      ),
    );
  }

  // ========== VER MAPA ==========

  void _verMapa(String recorridoId, String placa, String vehiculo) {
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

  // ========== UTILIDADES ==========

  void _mostrarSnackbar(String mensaje) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(mensaje)),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Recorridos'),
        backgroundColor: const Color(0xFF003580),
        foregroundColor: Colors.white,
      ),
      floatingActionButton: FloatingActionButton(
        backgroundColor: const Color(0xFF003580),
        onPressed: _recorridoActivo ? null : _mostrarFormularioInicio,
        child: const Icon(Icons.add),
      ),
      body: StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance.collection('recorridos').orderBy('fecha_inicio', descending: true).snapshots(),
        builder: (context, snapshot) {
          if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
          
          final recorridos = snapshot.data!.docs;
          if (recorridos.isEmpty) {
            return const Center(child: Text('No hay recorridos'));
          }

          return ListView.builder(
            padding: const EdgeInsets.all(8),
            itemCount: recorridos.length,
            itemBuilder: (context, i) {
              final r = recorridos[i].data() as Map<String, dynamic>;
              final estado = r['estado'] ?? 'completado';
              final estaActivo = estado == 'en_curso';
              
              return Card(
                color: estaActivo ? Colors.yellow[50] : null,
                child: ListTile(
                  title: Text('${r['placa']} - ${r['conductor']}'),
                  subtitle: Text('Km: ${r['km_inicio']} → ${r['km_fin'] ?? "..."}'),
                  trailing: estaActivo
                      ? ElevatedButton(
                          onPressed: () => _mostrarFormularioFinalizacion(recorridos[i].id, r),
                          child: const Text('Finalizar'),
                        )
                      : IconButton(
                          icon: const Icon(Icons.map),
                          onPressed: () => _verMapa(recorridos[i].id, r['placa'] ?? '', r['vehiculo'] ?? ''),
                        ),
                ),
              );
            },
          );
        },
      ),
    );
  }

  @override
  void dispose() {
    _kmInicioController.dispose();
    _kmFinController.dispose();
    _fiscaliaController.dispose();
    _diligenciaController.dispose();
    _conductorController.dispose();
    _carpetaController.dispose();
    _posicionStream?.cancel();
    super.dispose();
  }
}

// ========== PÁGINA DEL MAPA CORREGIDA ==========

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
  List<LatLng> _puntos = [];
  bool _cargando = true;
  final MapController _mapController = MapController();

  @override
  void initState() {
    super.initState();
    _cargarDatos();
  }

  Future<void> _cargarDatos() async {
    final puntosSnapshot = await FirebaseFirestore.instance
        .collection('recorridos')
        .doc(widget.recorridoId)
        .collection('puntos_gps')
        .orderBy('hora')
        .get();

    final puntosTemp = <LatLng>[];
    for (var doc in puntosSnapshot.docs) {
      puntosTemp.add(LatLng(doc['lat'], doc['lng']));
    }

    setState(() {
      _puntos = puntosTemp;
      _cargando = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_cargando) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    final centro = _puntos.isNotEmpty ? _puntos.first : const LatLng(9.4325, -82.4429);

    return Scaffold(
      appBar: AppBar(
        title: Text('${widget.placa} - ${widget.vehiculo}'),
        backgroundColor: const Color(0xFF003580),
        foregroundColor: Colors.white,
      ),
      body: FlutterMap(
        mapController: _mapController,
        options: MapOptions(initialCenter: centro, initialZoom: 14),
        children: [
          TileLayer(
            urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
            userAgentPackageName: 'com.ministerio.publico.cbt',
          ),
          if (_puntos.isNotEmpty)
            PolylineLayer(
              polylines: [
                Polyline(points: _puntos, strokeWidth: 4, color: Colors.blue),
              ],
            ),
          if (_puntos.isNotEmpty)
            MarkerLayer(
              markers: [
                Marker(
                  point: _puntos.first,
                  width: 40,
                  height: 40,
                  child: const Icon(Icons.location_on, color: Colors.green, size: 40),
                ),
                if (_puntos.length > 1)
                  Marker(
                    point: _puntos.last,
                    width: 40,
                    height: 40,
                    child: const Icon(Icons.location_on, color: Colors.red, size: 40),
                  ),
              ],
            ),
        ],
      ),
    );
  }
}