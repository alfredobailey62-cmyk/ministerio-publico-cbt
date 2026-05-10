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
  final _fiscaliaController = TextEditingController();
  final _diligenciaController = TextEditingController();
  final _carpetaController = TextEditingController();
  final List<String> _carpetasList = [];

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
      setState(() {
        _recorridoIdActivo = recorridoGuardado;
        _recorridoActivo = true;
      });
      
      if (puntosGuardados != null) {
        final puntos = json.decode(puntosGuardados) as List;
        _puntosGPS = puntos.map((e) => Map<String, dynamic>.from(e)).toList();
      }
      
      _reanudarGPS();
    }
  }

  Future<void> _guardarRecorridoEnBackground() async {
    if (_recorridoIdActivo != null) {
      await _prefs?.setString('recorrido_activo_id', _recorridoIdActivo!);
      await _prefs?.setString('puntos_activos', json.encode(_puntosGPS));
    }
  }

  Future<void> _reanudarGPS() async {
    bool servicioActivo = await Geolocator.isLocationServiceEnabled();
    if (!servicioActivo) return;

    LocationPermission permiso = await Geolocator.checkPermission();
    if (permiso != LocationPermission.always && permiso != LocationPermission.whileInUse) {
      permiso = await Geolocator.requestPermission();
      return;
    }

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
              .add(punto);
        }
      } catch (e) {
        await _guardarPuntoOffline(punto);
      }
    });
  }

  Future<void> _guardarPuntoOffline(Map<String, dynamic> punto) async {
    final pendientes = _prefs?.getStringList('puntos_pendientes') ?? [];
    pendientes.add(json.encode(punto));
    await _prefs?.setStringList('puntos_pendientes', pendientes);
  }

  Future<void> _sincronizarPuntosOffline() async {
    final pendientes = _prefs?.getStringList('puntos_pendientes') ?? [];
    
    if (pendientes.isNotEmpty && _recorridoIdActivo != null) {
      for (var puntoJson in pendientes) {
        try {
          final punto = json.decode(puntoJson) as Map<String, dynamic>;
          await FirebaseFirestore.instance
              .collection('recorridos')
              .doc(_recorridoIdActivo)
              .collection('puntos_gps')
              .add(punto);
        } catch (e) {
          return;
        }
      }
      await _prefs?.remove('puntos_pendientes');
    }
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
        
        if (DateTime.now().difference(_inicioParada!).inMinutes >= TIEMPO_PARADA_MINUTOS) {
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
    if (_recorridoIdActivo == null || _puntosParada.isEmpty) return;
    if (_inicioParada == null) return;
    
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

  void _agregarCarpeta(StateSetter setStateDialog) {
    if (_carpetaController.text.isNotEmpty) {
      setStateDialog(() {
        _carpetasList.add(_carpetaController.text);
        _carpetaController.clear();
      });
    }
  }

  void _eliminarCarpeta(int index, StateSetter setStateDialog) {
    setStateDialog(() {
      _carpetasList.removeAt(index);
    });
  }

  Future<bool> _iniciarGPS() async {
    bool servicioActivo = await Geolocator.isLocationServiceEnabled();
    if (!servicioActivo) {
      _mostrarSnackbar('Active el GPS del dispositivo');
      return false;
    }

    LocationPermission permiso = await Geolocator.checkPermission();
    if (permiso == LocationPermission.denied) {
      permiso = await Geolocator.requestPermission();
      if (permiso == LocationPermission.denied) {
        _mostrarSnackbar('Se necesita permiso de ubicacion');
        return false;
      }
    }

    if (permiso == LocationPermission.deniedForever) {
      _mostrarSnackbar('Permiso de ubicacion denegado permanentemente');
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
              .add(punto);
        }
      } catch (e) {
        await _guardarPuntoOffline(punto);
      }
    });

    setState(() => _recorridoActivo = true);
    _mostrarSnackbar('GPS activado - Grabando recorrido');
    return true;
  }

  Future<void> _detenerGPS() async {
    if (_enParada && _inicioParada != null) {
      final duracionParada = DateTime.now().difference(_inicioParada!);
      if (duracionParada.inMinutes >= TIEMPO_PARADA_MINUTOS) {
        await _registrarParada();
      }
    }
    await _posicionStream?.cancel();
    await _sincronizarPuntosOffline();
    await _prefs?.remove('recorrido_activo_id');
    await _prefs?.remove('puntos_activos');
    setState(() => _recorridoActivo = false);
  }

  void _mostrarFormularioInicio() {
    _kmInicioController.clear();
    _conductorController.clear();
    _fiscaliaController.clear();
    _diligenciaController.clear();
    _carpetaController.clear();
    _carpetasList.clear();
    _vehiculoSeleccionado = null;

    showDialog(
      context: context,
      builder: (_) => StatefulBuilder(
        builder: (context, setStateDialog) => AlertDialog(
          title: const Text('Iniciar Recorrido'),
          content: SizedBox(
            width: 380,
            height: MediaQuery.of(context).size.height * 0.7,
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
                        hint: const Text('Seleccione vehiculo'),
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
                          labelText: 'Vehiculo',
                          border: OutlineInputBorder(),
                        ),
                      );
                    },
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _conductorController,
                    decoration: const InputDecoration(
                      labelText: 'Conductor',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _fiscaliaController,
                    decoration: InputDecoration(
                      labelText: 'Fiscalia',
                      border: const OutlineInputBorder(),
                      suffixIcon: _fiscaliaController.text.toUpperCase() == 'COORDINACION'
                          ? const Icon(Icons.verified, color: Colors.green)
                          : null,
                      helperText: _fiscaliaController.text.toUpperCase() == 'COORDINACION' 
                          ? 'Esta diligencia sera marcada como MISION OFICIAL'
                          : null,
                    ),
                    onChanged: (value) {
                      setStateDialog(() {});
                    },
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _diligenciaController,
                    decoration: const InputDecoration(
                      labelText: 'Tipo de Diligencia',
                      border: OutlineInputBorder(),
                      hintText: 'Ej: Inspeccion, Allanamiento, Traslado',
                    ),
                  ),
                  const SizedBox(height: 12),
                  const Text('Numeros de Carpeta', style: TextStyle(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _carpetaController,
                          decoration: const InputDecoration(
                            labelText: 'Numero de carpeta',
                            border: OutlineInputBorder(),
                            hintText: 'Ej: 123-2024',
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      IconButton(
                        icon: const Icon(Icons.add_circle, color: Colors.green, size: 32),
                        onPressed: () => _agregarCarpeta(setStateDialog),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  if (_carpetasList.isNotEmpty)
                    Container(
                      height: 120,
                      decoration: BoxDecoration(
                        border: Border.all(color: Colors.grey),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: ListView.builder(
                        itemCount: _carpetasList.length,
                        itemBuilder: (context, index) {
                          return ListTile(
                            dense: true,
                            leading: const Icon(Icons.folder, color: Colors.blue),
                            title: Text(_carpetasList[index]),
                            trailing: IconButton(
                              icon: const Icon(Icons.delete, color: Colors.red),
                              onPressed: () => _eliminarCarpeta(index, setStateDialog),
                            ),
                          );
                        },
                      ),
                    ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _kmInicioController,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: 'Kilometraje inicial',
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
                  _mostrarSnackbar('Complete los campos obligatorios');
                  return;
                }

                bool gpsIniciado = await _iniciarGPS();
                if (!gpsIniciado) return;

                final fechaHoraInicio = DateTime.now();
                final esMisionOficial = _fiscaliaController.text.toUpperCase() == 'COORDINACION';
                
                final docRef = await FirebaseFirestore.instance.collection('recorridos').add({
                  'vehiculo_id': _vehiculoSeleccionado,
                  'placa': _placaSeleccionada,
                  'vehiculo': _marcaModelo,
                  'conductor': _conductorController.text,
                  'fiscalia': _fiscaliaController.text,
                  'tipo_diligencia': _diligenciaController.text,
                  'carpetas': _carpetasList,
                  'es_mision_oficial': esMisionOficial,
                  'km_inicio': kmInicio,
                  'km_fin': null,
                  'km_recorrido': null,
                  'fecha_inicio': fechaHoraInicio,
                  'fecha_inicio_str': '${fechaHoraInicio.day}/${fechaHoraInicio.month}/${fechaHoraInicio.year} ${fechaHoraInicio.hour}:${fechaHoraInicio.minute}',
                  'fecha_fin': null,
                  'mes': fechaHoraInicio.month,
                  'anio': fechaHoraInicio.year,
                  'estado': 'en_curso',
                });

                setState(() => _recorridoIdActivo = docRef.id);
                await _guardarRecorridoEnBackground();
                _mostrarSnackbar('Recorrido iniciado');
                if (context.mounted) Navigator.pop(context);
              },
              child: const Text('Iniciar Recorrido'),
            ),
          ],
        ),
      ),
    );
  }

  void _mostrarFormularioFinalizacion(String recorridoId, Map<String, dynamic> recorridoActual) {
    _kmFinController.clear();

    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Finalizar Recorrido'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.blue[50],
                borderRadius: BorderRadius.circular(8),
              ),
              child: Column(
                children: [
                  Text('${recorridoActual['placa']} - ${recorridoActual['vehiculo']}'),
                  const SizedBox(height: 4),
                  Text('Conductor: ${recorridoActual['conductor']}'),
                  if (recorridoActual['fiscalia'] != null && recorridoActual['fiscalia'].isNotEmpty)
                    Text('Fiscalia: ${recorridoActual['fiscalia']}'),
                  if (recorridoActual['tipo_diligencia'] != null && recorridoActual['tipo_diligencia'].isNotEmpty)
                    Text('Diligencia: ${recorridoActual['tipo_diligencia']}'),
                  if (recorridoActual['carpetas'] != null && (recorridoActual['carpetas'] as List).isNotEmpty)
                    Text('Carpetas: ${(recorridoActual['carpetas'] as List).length}'),
                  if (recorridoActual['es_mision_oficial'] == true)
                    const Padding(
                      padding: EdgeInsets.only(top: 4),
                      child: Text('MISION OFICIAL', style: TextStyle(color: Colors.green, fontWeight: FontWeight.bold)),
                    ),
                  const Divider(),
                  Text('Km inicial: ${recorridoActual['km_inicio']} km'),
                ],
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _kmFinController,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: 'Kilometraje final',
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
                _mostrarSnackbar('Kilometraje final invalido');
                return;
              }

              await _detenerGPS();

              final kmRecorrido = kmFin - (recorridoActual['km_inicio'] as int);
              final fechaHoraFin = DateTime.now();

              await FirebaseFirestore.instance.collection('recorridos').doc(recorridoId).update({
                'km_fin': kmFin,
                'km_recorrido': kmRecorrido,
                'fecha_fin': fechaHoraFin,
                'fecha_fin_str': '${fechaHoraFin.day}/${fechaHoraFin.month}/${fechaHoraFin.year} ${fechaHoraFin.hour}:${fechaHoraFin.minute}',
                'estado': 'completado',
              });

              setState(() {
                _recorridoIdActivo = null;
                _puntosGPS = [];
              });

              _mostrarSnackbar('Recorrido finalizado. ${kmRecorrido} km');
              if (context.mounted) Navigator.pop(context);
            },
            child: const Text('Finalizar Recorrido'),
          ),
        ],
      ),
    );
  }

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

  void _mostrarSnackbar(String mensaje) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(mensaje), duration: const Duration(seconds: 2)),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Recorridos'),
        backgroundColor: const Color(0xFF003580),
        foregroundColor: Colors.white,
        actions: [
          if (_recorridoActivo)
            Container(
              margin: const EdgeInsets.only(right: 16),
              child: const Row(
                children: [
                  Icon(Icons.circle, color: Colors.green, size: 12),
                  SizedBox(width: 4),
                  Text('GRABANDO', style: TextStyle(fontSize: 12)),
                ],
              ),
            ),
        ],
      ),
      floatingActionButton: Column(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          if (_recorridoActivo)
            FloatingActionButton(
              heroTag: 'btnStop',
              backgroundColor: Colors.red,
              onPressed: () async {
                if (_recorridoIdActivo != null) {
                  final doc = await FirebaseFirestore.instance
                      .collection('recorridos')
                      .doc(_recorridoIdActivo)
                      .get();
                  if (doc.exists) {
                    _mostrarFormularioFinalizacion(_recorridoIdActivo!, doc.data()!);
                  }
                }
              },
              child: const Icon(Icons.stop),
            ),
          const SizedBox(height: 10),
          FloatingActionButton(
            heroTag: 'btnAdd',
            backgroundColor: const Color(0xFF003580),
            onPressed: _recorridoActivo ? null : _mostrarFormularioInicio,
            child: const Icon(Icons.add),
          ),
        ],
      ),
      body: StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance
            .collection('recorridos')
            .orderBy('fecha_inicio', descending: true)
            .snapshots(),
        builder: (context, snapshot) {
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }

          final recorridos = snapshot.data!.docs;
          if (recorridos.isEmpty) {
            return const Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.route, size: 64, color: Colors.grey),
                  SizedBox(height: 16),
                  Text('No hay recorridos registrados'),
                  SizedBox(height: 8),
                  Text('Presione el boton + para iniciar uno'),
                ],
              ),
            );
          }

          return ListView.builder(
            padding: const EdgeInsets.all(8),
            itemCount: recorridos.length,
            itemBuilder: (context, i) {
              final r = recorridos[i].data() as Map<String, dynamic>;
              final estado = r['estado'] ?? 'completado';
              final estaActivo = estado == 'en_curso';
              final esMisionOficial = r['es_mision_oficial'] ?? false;
              final carpetas = r['carpetas'] as List? ?? [];
              final tipoDiligencia = r['tipo_diligencia'] ?? '';
              
              return Card(
                elevation: estaActivo ? 4 : 1,
                color: estaActivo ? Colors.yellow[100] : Colors.white,
                child: ListTile(
                  leading: CircleAvatar(
                    backgroundColor: esMisionOficial 
                        ? Colors.green 
                        : (estaActivo ? Colors.green : Colors.blue),
                    child: Icon(
                      esMisionOficial 
                          ? Icons.verified 
                          : (estaActivo ? Icons.play_arrow : Icons.check_circle),
                      color: Colors.white,
                      size: 20,
                    ),
                  ),
                  title: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${r['placa']} - ${r['conductor']}',
                        style: TextStyle(
                          fontWeight: estaActivo ? FontWeight.bold : FontWeight.normal,
                        ),
                      ),
                      if (esMisionOficial)
                        const Chip(
                          label: Text('MISION OFICIAL', style: TextStyle(fontSize: 10)),
                          backgroundColor: Colors.green,
                          labelStyle: TextStyle(color: Colors.white),
                        ),
                    ],
                  ),
                  subtitle: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Inicio: ${r['fecha_inicio_str'] ?? ''}'),
                      if (tipoDiligencia.isNotEmpty) Text('Diligencia: $tipoDiligencia'),
                      if (carpetas.isNotEmpty) Text('Carpetas: ${carpetas.length}'),
                      Text('Km: ${r['km_inicio']} -> ${r['km_fin'] ?? '...'} (${r['km_recorrido'] ?? 'En curso'} km)'),
                      if (estaActivo) const Text('EN CURSO', style: TextStyle(color: Colors.green, fontWeight: FontWeight.bold)),
                    ],
                  ),
                  trailing: estaActivo
                      ? ElevatedButton.icon(
                          onPressed: () => _mostrarFormularioFinalizacion(recorridos[i].id, r),
                          icon: const Icon(Icons.stop, size: 18),
                          label: const Text('Finalizar'),
                          style: ElevatedButton.styleFrom(backgroundColor: Colors.green),
                        )
                      : IconButton(
                          icon: const Icon(Icons.map),
                          onPressed: () => _verMapa(recorridos[i].id, r['placa'] ?? '', r['vehiculo'] ?? ''),
                          tooltip: 'Ver recorrido en mapa',
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
    _conductorController.dispose();
    _fiscaliaController.dispose();
    _diligenciaController.dispose();
    _carpetaController.dispose();
    _posicionStream?.cancel();
    super.dispose();
  }
}

// ========== PAGINA DEL MAPA ==========

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
  List<Map<String, dynamic>> _paradas = [];
  bool _cargando = true;
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
      for (var doc in puntosSnapshot.docs) {
        puntosTemp.add(LatLng(doc['lat'], doc['lng']));
      }

      final paradasSnapshot = await FirebaseFirestore.instance
          .collection('recorridos')
          .doc(widget.recorridoId)
          .collection('paradas')
          .get();

      setState(() {
        _puntos = puntosTemp;
        _paradas = paradasSnapshot.docs.map((d) => d.data()).toList();
        _cargando = false;
      });
    } catch (e) {
      setState(() => _cargando = false);
    }
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
            urlTemplate: 'https://{s}.basemaps.cartocdn.com/light_all/{z}/{x}/{y}.png',
            subdomains: ['a', 'b', 'c'],
            userAgentPackageName: 'com.ministerio.publico.cbt',
          ),
          if (_puntos.isNotEmpty)
            PolylineLayer(
              polylines: [
                Polyline(points: _puntos, strokeWidth: 4, color: Colors.blue),
              ],
            ),
          MarkerLayer(
            markers: [
              if (_puntos.isNotEmpty)
                Marker(
                  point: _puntos.first,
                  width: 50,
                  height: 50,
                  child: const Icon(Icons.location_on, color: Colors.green, size: 40),
                ),
              if (_puntos.length > 1)
                Marker(
                  point: _puntos.last,
                  width: 50,
                  height: 50,
                  child: const Icon(Icons.location_on, color: Colors.red, size: 40),
                ),
              for (var parada in _paradas)
                if (parada['ubicacion'] != null)
                  Marker(
                    point: LatLng(
                      (parada['ubicacion'] as GeoPoint).latitude,
                      (parada['ubicacion'] as GeoPoint).longitude,
                    ),
                    width: 45,
                    height: 45,
                    child: const Icon(Icons.pause_circle, color: Colors.orange, size: 35),
                  ),
            ],
          ),
        ],
      ),
    );
  }
}