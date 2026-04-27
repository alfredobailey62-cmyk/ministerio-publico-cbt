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

  // Coordenadas de referencia (Empalme) - ajustar según ubicación real
  static const double empalmeLat = 9.5000;
  static const double empalmeLng = -82.5000;

  Future<void> _iniciarRecorrido() async {
    bool servicioActivo = await Geolocator.isLocationServiceEnabled();
    if (!servicioActivo) return;

    LocationPermission permiso = await Geolocator.checkPermission();
    if (permiso == LocationPermission.denied) {
      permiso = await Geolocator.requestPermission();
      if (permiso == LocationPermission.denied) return;
    }

    _puntosGPS.clear();

    _posicionStream = Geolocator.getPositionStream(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.best,
        distanceFilter: 5,
      ),
    ).listen((Position position) {
      _puntosGPS.add({
        'lat': position.latitude,
        'lng': position.longitude,
        'hora': DateTime.now().toIso8601String(),
      });
    });

    setState(() => _recorridoActivo = true);
  }

  void _detenerRecorrido() {
    _posicionStream?.cancel();
    setState(() => _recorridoActivo = false);
  }

  bool pasoPorEmpalme(List<Map<String, dynamic>> puntos) {
    const double rango = 0.02;

    for (var p in puntos) {
      if ((p['lat'] - empalmeLat).abs() < rango &&
          (p['lng'] - empalmeLng).abs() < rango) {
        return true;
      }
    }
    return false;
  }

  void _verMapa(Map<String, dynamic> recorrido) {
    final puntos = (recorrido['puntos_gps'] as List<dynamic>? ?? []);
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

  void _mostrarFormulario() {
    showDialog(
      context: context,
      builder: (_) => StatefulBuilder(
        builder: (context, setStateDialog) => AlertDialog(
          title: const Text('Registrar Recorrido'),
          content: SingleChildScrollView(
            child: Column(
              children: [

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
                  decoration: const InputDecoration(labelText: 'Kilometraje inicial'),
                ),

                TextField(
                  controller: _kmFinController,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(labelText: 'Kilometraje final'),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () {
                _limpiarFormulario();
                Navigator.pop(context);
              },
              child: const Text('Cancelar'),
            ),

            ElevatedButton(
              onPressed: () async {

                final kmInicio = int.tryParse(_kmInicioController.text) ?? 0;
                final kmFin = int.tryParse(_kmFinController.text) ?? 0;

                final fueEmpalme = pasoPorEmpalme(_puntosGPS);

                await FirebaseFirestore.instance.collection('recorridos').add({
                  'vehiculo_id': _vehiculoSeleccionado,
                  'placa': _placaSeleccionada,
                  'vehiculo': _marcaModelo,
                  'conductor': _conductorController.text,
                  'fiscalia': _fiscaliaController.text,
                  'carpeta': _carpetaController.text,
                  'diligencia': _diligenciaController.text,
                  'km_inicio': kmInicio,
                  'km_fin': kmFin,
                  'km_recorrido': kmFin - kmInicio,
                  'fecha': DateTime.now(),
                  'mes': DateTime.now().month,
                  'anio': DateTime.now().year,
                  'puntos_gps': _puntosGPS,
                  'fue_empalme': fueEmpalme,
                });

                _detenerRecorrido();
                _limpiarFormulario();

                if (context.mounted) {
                  Navigator.pop(context);
                }
              },
              child: const Text('Guardar'),
            ),
          ],
        ),
      ),
    );
  }

  void _limpiarFormulario() {
    _kmInicioController.clear();
    _kmFinController.clear();
    _fiscaliaController.clear();
    _diligenciaController.clear();
    _conductorController.clear();
    _carpetaController.clear();
    _vehiculoSeleccionado = null;
    _placaSeleccionada = null;
    _marcaModelo = null;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Recorridos'),
        backgroundColor: const Color(0xFF003580),
      ),

      floatingActionButton: Column(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [

          FloatingActionButton(
            backgroundColor: _recorridoActivo ? Colors.red : Colors.green,
            onPressed: _recorridoActivo ? _detenerRecorrido : _iniciarRecorrido,
            child: Icon(_recorridoActivo ? Icons.stop : Icons.play_arrow),
          ),

          const SizedBox(height: 10),

          FloatingActionButton(
            backgroundColor: const Color(0xFF003580),
            onPressed: _mostrarFormulario,
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

          return ListView.builder(
            itemCount: recorridos.length,
            itemBuilder: (context, i) {

              final r = recorridos[i].data() as Map<String, dynamic>;

              return Card(
                child: ListTile(
                  title: Text(r['placa'] ?? ''),
                  subtitle: Text(
                    '${r['vehiculo']} - ${r['km_recorrido']} km\n'
                    'Verificación de destino: ${r['fue_empalme'] == true ? "Cumplido" : "No registrado"}',
                  ),
                  trailing: IconButton(
                    icon: const Icon(Icons.map),
                    onPressed: () => _verMapa(r),
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}

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