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

  int _mesFiltro = DateTime.now().month;
  int _anioFiltro = DateTime.now().year;

  List<Map<String, dynamic>> _puntosGPS = [];
  StreamSubscription<Position>? _posicionStream;
  bool _recorridoActivo = false;
  String? _recorridoIdActivo; // ID del recorrido activo para actualizar después

  // Coordenadas de referencia (Empalme)
  static const double empalmeLat = 9.5000;
  static const double empalmeLng = -82.5000;

  // ========== FUNCIONES DE GPS ==========
  
  Future<bool> _iniciarGPS() async {
    print('🟢 Iniciando GPS...');
    
    bool servicioActivo = await Geolocator.isLocationServiceEnabled();
    if (!servicioActivo) {
      print('❌ GPS no activado');
      _mostrarSnackbar('Active el GPS para continuar');
      return false;
    }

    LocationPermission permiso = await Geolocator.checkPermission();
    if (permiso == LocationPermission.denied) {
      permiso = await Geolocator.requestPermission();
      if (permiso == LocationPermission.denied) {
        print('❌ Permiso denegado');
        _mostrarSnackbar('Se necesita permiso de ubicación');
        return false;
      }
    }

    _puntosGPS.clear();
    print('✅ GPS iniciado, grabando puntos...');

    _posicionStream = Geolocator.getPositionStream(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.best,
        distanceFilter: 1, // Cada 5 metros
      ),
    ).listen((Position position) {
      final punto = {
        'lat': position.latitude,
        'lng': position.longitude,
        'hora': DateTime.now().toIso8601String(),
      };
      _puntosGPS.add(punto);
      print('📍 Punto grabado #${_puntosGPS.length}: ${position.latitude}, ${position.longitude}');
    });

    setState(() => _recorridoActivo = true);
    return true;
  }

  Future<void> _detenerGPS() async {
    print('🛑 Deteniendo GPS...');
    print('📊 Total puntos grabados: ${_puntosGPS.length}');
    await _posicionStream?.cancel();
    setState(() => _recorridoActivo = false);
  }

  bool pasoPorEmpalme(List<Map<String, dynamic>> puntos) {
    const double rango = 0.02;
    for (var p in puntos) {
      if ((p['lat'] - empalmeLat).abs() < rango &&
          (p['lng'] - empalmeLng).abs() < rango) {
        print('✅ PASÓ POR EMPALME');
        return true;
      }
    }
    print('❌ NO pasó por empalme');
    return false;
  }

  // ========== PASO 1: CREAR RECORRIDO (SOLO km_inicio) ==========
  
  void _mostrarFormularioInicio() {
    // Limpiar formulario
    _kmInicioController.clear();
    _fiscaliaController.clear();
    _diligenciaController.clear();
    _conductorController.clear();
    _carpetaController.clear();
    _vehiculoSeleccionado = null;
    _placaSeleccionada = null;
    _marcaModelo = null;

    showDialog(
      context: context,
      builder: (_) => StatefulBuilder(
        builder: (context, setStateDialog) => AlertDialog(
          title: const Text('Iniciar Recorrido'),
          content: SingleChildScrollView(
            child: Column(
              children: [
                // Selector de vehículo
                StreamBuilder<QuerySnapshot>(
                  stream: FirebaseFirestore.instance.collection('vehiculos').snapshots(),
                  builder: (context, snapshot) {
                    if (!snapshot.hasData) {
                      return const CircularProgressIndicator();
                    }
                    final vehiculos = snapshot.data!.docs;
                    return DropdownButton<String>(
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
                    );
                  },
                ),
                TextField(controller: _conductorController, decoration: const InputDecoration(labelText: 'Conductor')),
                TextField(controller: _fiscaliaController, decoration: const InputDecoration(labelText: 'Fiscalía')),
                TextField(controller: _carpetaController, decoration: const InputDecoration(labelText: 'Carpeta')),
                TextField(controller: _diligenciaController, decoration: const InputDecoration(labelText: 'Diligencia')),
                TextField(
                  controller: _kmInicioController,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(labelText: 'Kilometraje inicial *'),
                ),
              ],
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
                
                if (kmInicio == null) {
                  _mostrarSnackbar('Ingrese el kilometraje inicial');
                  return;
                }
                
                if (_vehiculoSeleccionado == null) {
                  _mostrarSnackbar('Seleccione un vehículo');
                  return;
                }

                print('📝 PASO 1: Guardando recorrido con km_inicio: $kmInicio');
                
                // INICIAR GPS AUTOMÁTICAMENTE
                bool gpsIniciado = await _iniciarGPS();
                if (!gpsIniciado) {
                  _mostrarSnackbar('No se pudo iniciar el GPS');
                  return;
                }

                // Guardar en Firestore con km_fin = null
                final docRef = await FirebaseFirestore.instance.collection('recorridos').add({
                  'vehiculo_id': _vehiculoSeleccionado,
                  'placa': _placaSeleccionada,
                  'vehiculo': _marcaModelo,
                  'conductor': _conductorController.text,
                  'fiscalia': _fiscaliaController.text,
                  'carpeta': _carpetaController.text,
                  'diligencia': _diligenciaController.text,
                  'km_inicio': kmInicio,
                  'km_fin': null, // PENDIENTE
                  'km_recorrido': null, // PENDIENTE
                  'fecha_inicio': DateTime.now(),
                  'fecha_fin': null, // PENDIENTE
                  'mes': DateTime.now().month,
                  'anio': DateTime.now().year,
                  'puntos_gps': [], // Se irán llenando con el stream
                  'fue_empalme': false, // Se actualizará al finalizar
                  'estado': 'en_curso', // NUEVO CAMPO
                });

                setState(() {
                  _recorridoIdActivo = docRef.id;
                });

                print('✅ Recorrido creado con ID: $_recorridoIdActivo');
                _mostrarSnackbar('Recorrido iniciado. GPS activo.');
                
                if (context.mounted) {
                  Navigator.pop(context);
                }
              },
              child: const Text('Iniciar Recorrido'),
            ),
          ],
        ),
      ),
    );
  }

  // ========== PASO 2: FINALIZAR RECORRIDO (SOLO km_fin) ==========
  
  void _mostrarFormularioFinalizacion(String recorridoId, Map<String, dynamic> recorridoActual) {
    _kmFinController.clear();
    
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Finalizar Recorrido'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('Vehículo: ${recorridoActual['placa']} - ${recorridoActual['vehiculo']}'),
            Text('Conductor: ${recorridoActual['conductor']}'),
            Text('Kilometraje inicial: ${recorridoActual['km_inicio']} km'),
            const SizedBox(height: 16),
            TextField(
              controller: _kmFinController,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: 'Kilometraje final *'),
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
              
              if (kmFin == null) {
                _mostrarSnackbar('Ingrese el kilometraje final');
                return;
              }
              
              final kmInicio = recorridoActual['km_inicio'] as int;
              if (kmFin <= kmInicio) {
                _mostrarSnackbar('El kilometraje final debe ser mayor al inicial');
                return;
              }

              print('📝 PASO 2: Finalizando recorrido con km_fin: $kmFin');
              
              // DETENER GPS
              await _detenerGPS();
              
              // Calcular datos finales
              final kmRecorrido = kmFin - kmInicio;
              final fueEmpalme = pasoPorEmpalme(_puntosGPS);
              
              print('📍 Puntos GPS totales: ${_puntosGPS.length}');
              print('📊 KM recorrido: $kmRecorrido');
              
              // ACTUALIZAR el registro existente
              await FirebaseFirestore.instance.collection('recorridos').doc(recorridoId).update({
                'km_fin': kmFin,
                'km_recorrido': kmRecorrido,
                'fecha_fin': DateTime.now(),
                'puntos_gps': _puntosGPS,
                'fue_empalme': fueEmpalme,
                'estado': 'completado',
              });
              
              // Limpiar estado
              setState(() {
                _recorridoIdActivo = null;
                _puntosGPS = [];
              });
              
              _mostrarSnackbar('Recorrido finalizado y guardado');
              
              if (context.mounted) {
                Navigator.pop(context);
              }
            },
            child: const Text('Finalizar Recorrido'),
          ),
        ],
      ),
    );
  }

  // ========== VER MAPA ==========
  
  void _verMapa(Map<String, dynamic> recorrido) {
    final puntos = (recorrido['puntos_gps'] as List<dynamic>? ?? []);
    if (puntos.isEmpty) {
      _mostrarSnackbar('Este recorrido no tiene puntos GPS registrados');
      return;
    }
    
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => _MapaRecorrido(
          placa: recorrido['placa'] ?? '',
          vehiculo: recorrido['vehiculo'] ?? '',
          puntos: puntos.map((p) => LatLng(p['lat'], p['lng'])).toList(),
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

  void _cancelarRecorridoActivo() async {
    if (_recorridoIdActivo != null) {
      showDialog(
        context: context,
        builder: (_) => AlertDialog(
          title: const Text('Cancelar Recorrido'),
          content: const Text('¿Está seguro que desea cancelar el recorrido activo? Se perderán todos los datos.'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('No'),
            ),
            TextButton(
              onPressed: () async {
                await _detenerGPS();
                await FirebaseFirestore.instance.collection('recorridos').doc(_recorridoIdActivo).delete();
                setState(() {
                  _recorridoIdActivo = null;
                  _puntosGPS = [];
                });
                _mostrarSnackbar('Recorrido cancelado');
                if (context.mounted) Navigator.pop(context);
              },
              child: const Text('Sí, cancelar'),
            ),
          ],
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Recorridos'),
        backgroundColor: const Color(0xFF003580),
        actions: [
          if (_recorridoActivo)
            IconButton(
              icon: const Icon(Icons.cancel, color: Colors.white),
              onPressed: _cancelarRecorridoActivo,
              tooltip: 'Cancelar recorrido activo',
            ),
        ],
      ),
      floatingActionButton: Column(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          if (_recorridoActivo)
            FloatingActionButton(
              backgroundColor: Colors.red,
              onPressed: () async {
                if (_recorridoIdActivo != null) {
                  final doc = await FirebaseFirestore.instance.collection('recorridos').doc(_recorridoIdActivo).get();
                  if (doc.exists) {
                    _mostrarFormularioFinalizacion(_recorridoIdActivo!, doc.data()!);
                  }
                }
              },
              child: const Icon(Icons.stop),
            ),
          const SizedBox(height: 10),
          FloatingActionButton(
            backgroundColor: const Color(0xFF003580),
            onPressed: _recorridoActivo ? null : _mostrarFormularioInicio,
            child: const Icon(Icons.add),
          ),
        ],
      ),
      body: StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance
            .collection('recorridos')
            .where('mes', isEqualTo: _mesFiltro)
            .where('anio', isEqualTo: _anioFiltro)
            .snapshots(),
        builder: (context, snapshot) {
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }

          final recorridos = snapshot.data!.docs;

          return Column(
            children: [
              // Filtros de mes/año
              Padding(
                padding: const EdgeInsets.all(8.0),
                child: Row(
                  children: [
                    Expanded(
                      child: DropdownButton<int>(
                        value: _mesFiltro,
                        items: List.generate(12, (i) => i + 1).map((m) {
                          return DropdownMenuItem(value: m, child: Text(_getMesNombre(m)));
                        }).toList(),
                        onChanged: (v) => setState(() => _mesFiltro = v!),
                      ),
                    ),
                    Expanded(
                      child: DropdownButton<int>(
                        value: _anioFiltro,
                        items: [2023, 2024, 2025, 2026].map((a) {
                          return DropdownMenuItem(value: a, child: Text(a.toString()));
                        }).toList(),
                        onChanged: (v) => setState(() => _anioFiltro = v!),
                      ),
                    ),
                  ],
                ),
              ),
              // Lista de recorridos
              Expanded(
                child: ListView.builder(
                  itemCount: recorridos.length,
                  itemBuilder: (context, i) {
                    final r = recorridos[i].data() as Map<String, dynamic>;
                    final estado = r['estado'] ?? 'completado';
                    final estaActivo = estado == 'en_curso';
                    
                    return Card(
                      color: estaActivo ? Colors.yellow[100] : null,
                      child: ListTile(
                        title: Text('${r['placa']} - ${r['conductor']}'),
                        subtitle: Text(
                          'Inicio: ${r['km_inicio']} km\n'
                          'Fin: ${r['km_fin'] ?? "Pendiente"} km\n'
                          'Recorrido: ${r['km_recorrido'] ?? "En curso"} km\n'
                          'Estado: ${estaActivo ? "🟡 EN CURSO" : "✅ COMPLETADO"}\n'
                          'Destino: ${r['fue_empalme'] == true ? "✅ Empalme" : "❌ No registrado"}',
                        ),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (estaActivo)
                              ElevatedButton(
                                onPressed: () => _mostrarFormularioFinalizacion(recorridos[i].id, r),
                                style: ElevatedButton.styleFrom(backgroundColor: Colors.green),
                                child: const Text('Finalizar'),
                              ),
                            if (!estaActivo && (r['puntos_gps'] as List?)?.isNotEmpty == true)
                              IconButton(
                                icon: const Icon(Icons.map),
                                onPressed: () => _verMapa(r),
                              ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
            ],
          );
        },
      ),
    );
  }
  
  String _getMesNombre(int mes) {
    const meses = ['Ene', 'Feb', 'Mar', 'Abr', 'May', 'Jun', 'Jul', 'Ago', 'Sep', 'Oct', 'Nov', 'Dic'];
    return meses[mes - 1];
  }
}

// ========== WIDGET DEL MAPA ==========

class _MapaRecorrido extends StatelessWidget {
  final String placa;
  final String vehiculo;
  final List<LatLng> puntos;

  const _MapaRecorrido({
    required this.placa,
    required this.vehiculo,
    required this.puntos,
  });

  @override
  Widget build(BuildContext context) {
    final centro = puntos.isNotEmpty
        ? puntos.first
        : const LatLng(9.4325, -82.4429);

    return Scaffold(
      appBar: AppBar(
        title: Text('Mapa - $placa'),
        backgroundColor: const Color(0xFF003580),
      ),
      body: FlutterMap(
        options: MapOptions(
          initialCenter: centro,
          initialZoom: 13,
        ),
        children: [
          TileLayer(
            urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
          ),
          if (puntos.isNotEmpty) ...[
            PolylineLayer(
              polylines: [
                Polyline(
                  points: puntos,
                  strokeWidth: 4,
                  color: Colors.blue,
                ),
              ],
            ),
            MarkerLayer(
              markers: [
                Marker(
                  point: puntos.first,
                  child: const Icon(Icons.location_on, color: Colors.green, size: 40),
                ),
                Marker(
                  point: puntos.last,
                  child: const Icon(Icons.location_on, color: Colors.red, size: 40),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}