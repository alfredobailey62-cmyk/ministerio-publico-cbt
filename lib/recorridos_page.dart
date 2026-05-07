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
  String? _recorridoIdActivo;

  // Configuración para detección de paradas
  Position? _ultimaPosicion;
  DateTime? _inicioParada;
  bool _enParada = false;
  List<Map<String, dynamic>> _puntosParada = [];

  // Umbrales para detección de paradas
  static const double DISTANCIA_PARADA = 5.0; // 5 metros sin movimiento
  static const int TIEMPO_PARADA_MINUTOS = 5; // 5 minutos para considerar parada

  // ========== FUNCIONES DE GPS ==========

  Future<bool> _iniciarGPS() async {
    print('🟢 Iniciando GPS...');

    bool servicioActivo = await Geolocator.isLocationServiceEnabled();
    if (!servicioActivo) {
      print('❌ GPS no activado');
      _mostrarSnackbar('Active el GPS del dispositivo');
      return false;
    }

    LocationPermission permiso = await Geolocator.checkPermission();

    if (permiso == LocationPermission.denied) {
      print('📱 Solicitando permiso de ubicación...');
      permiso = await Geolocator.requestPermission();

      if (permiso == LocationPermission.denied) {
        print('❌ Permiso denegado por el usuario');
        _mostrarSnackbar('Se necesita permiso de ubicación');
        return false;
      }
    }

    if (permiso == LocationPermission.deniedForever) {
      print('❌ Permiso denegado permanentemente');
      _mostrarSnackbar('Permiso de ubicación denegado permanentemente');
      return false;
    }

    print('✅ Permisos concedidos, iniciando GPS...');
    _puntosGPS.clear();
    _ultimaPosicion = null;
    _inicioParada = null;
    _enParada = false;
    _puntosParada.clear();

    _posicionStream = Geolocator.getPositionStream(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.bestForNavigation,
        distanceFilter: 5, // Actualizar cada 5 metros
        timeLimit: Duration(seconds: 5), // O cada 5 segundos
      ),
    ).listen((Position position) {
      final punto = {
        'lat': position.latitude,
        'lng': position.longitude,
        'hora': DateTime.now().toIso8601String(),
      };
      _puntosGPS.add(punto);
      
      // Detectar paradas
      _detectarParada(position);
      
      print('📍 Punto #${_puntosGPS.length}: ${position.latitude}, ${position.longitude}');
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
        // Vehículo detenido o casi detenido
        if (!_enParada) {
          // Inicio de una posible parada
          _enParada = true;
          _inicioParada = DateTime.now();
          _puntosParada.clear();
          _puntosParada.add({
            'lat': posicionActual.latitude,
            'lng': posicionActual.longitude,
            'hora': DateTime.now().toIso8601String(),
          });
          print('🛑 Posible inicio de parada detectado');
        } else {
          // Continuamos en parada
          _puntosParada.add({
            'lat': posicionActual.latitude,
            'lng': posicionActual.longitude,
            'hora': DateTime.now().toIso8601String(),
          });
          
          // Verificar si ya pasaron 5 minutos
          final duracionParada = DateTime.now().difference(_inicioParada!);
          if (duracionParada.inMinutes >= TIEMPO_PARADA_MINUTOS) {
            _registrarParada();
          }
        }
      } else {
        // Vehículo en movimiento
        if (_enParada) {
          // Terminó la parada, registrar si duró al menos 5 minutos
          final duracionParada = DateTime.now().difference(_inicioParada!);
          if (duracionParada.inMinutes >= TIEMPO_PARADA_MINUTOS) {
            _registrarParada();
          }
          _enParada = false;
          _inicioParada = null;
          _puntosParada.clear();
          print('▶️ Vehículo en movimiento nuevamente');
        }
      }
    }
    
    _ultimaPosicion = posicionActual;
  }

  Future<void> _registrarParada() async {
    if (_recorridoIdActivo == null || _puntosParada.isEmpty) return;
    
    // Calcular centro de la parada
    double avgLat = _puntosParada.map((p) => p['lat'] as double).reduce((a, b) => a + b) / _puntosParada.length;
    double avgLng = _puntosParada.map((p) => p['lng'] as double).reduce((a, b) => a + b) / _puntosParada.length;
    
    final duracion = DateTime.now().difference(_inicioParada!).inMinutes;
    
    // Guardar la parada en una subcolección
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
    
    print('✅ Parada registrada: $duracion minutos');
    _mostrarSnackbar('Parada de $duracion minutos registrada');
  }

  Future<void> _detenerGPS() async {
    print('🛑 Deteniendo GPS...');
    print('📊 Total puntos grabados: ${_puntosGPS.length}');
    
    // Registrar parada final si estábamos en una
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
    _placaSeleccionada = null;
    _marcaModelo = null;

    showDialog(
      context: context,
      builder: (_) => StatefulBuilder(
        builder: (context, setStateDialog) => AlertDialog(
          title: const Text('Iniciar Recorrido'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                StreamBuilder<QuerySnapshot>(
                  stream: FirebaseFirestore.instance
                      .collection('vehiculos')
                      .snapshots(),
                  builder: (context, snapshot) {
                    if (!snapshot.hasData) {
                      return const CircularProgressIndicator();
                    }
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
                  controller: _fiscaliaController,
                  decoration: const InputDecoration(
                    labelText: 'Fiscalía',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _carpetaController,
                  decoration: const InputDecoration(
                    labelText: 'Carpeta',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _diligenciaController,
                  decoration: const InputDecoration(
                    labelText: 'Diligencia',
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

                if (_conductorController.text.isEmpty) {
                  _mostrarSnackbar('Ingrese el nombre del conductor');
                  return;
                }

                print('📝 Guardando recorrido con km_inicio: $kmInicio');

                bool gpsIniciado = await _iniciarGPS();
                if (!gpsIniciado) {
                  _mostrarSnackbar('No se pudo iniciar el GPS');
                  return;
                }

                final docRef = await FirebaseFirestore.instance
                    .collection('recorridos')
                    .add({
                      'vehiculo_id': _vehiculoSeleccionado,
                      'placa': _placaSeleccionada,
                      'vehiculo': _marcaModelo,
                      'conductor': _conductorController.text,
                      'fiscalia': _fiscaliaController.text,
                      'carpeta': _carpetaController.text,
                      'diligencia': _diligenciaController.text,
                      'km_inicio': kmInicio,
                      'km_fin': null,
                      'km_recorrido': null,
                      'fecha_inicio': DateTime.now(),
                      'fecha_fin': null,
                      'mes': DateTime.now().month,
                      'anio': DateTime.now().year,
                      'estado': 'en_curso',
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
            Text('Vehículo: ${recorridoActual['placa']} - ${recorridoActual['vehiculo']}'),
            const SizedBox(height: 8),
            Text('Conductor: ${recorridoActual['conductor']}'),
            const SizedBox(height: 8),
            Text('Kilometraje inicial: ${recorridoActual['km_inicio']} km'),
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

              if (kmFin == null) {
                _mostrarSnackbar('Ingrese el kilometraje final');
                return;
              }

              final kmInicio = recorridoActual['km_inicio'] as int;
              if (kmFin <= kmInicio) {
                _mostrarSnackbar('El kilometraje final debe ser mayor al inicial');
                return;
              }

              print('📝 Finalizando recorrido con km_fin: $kmFin');

              await _detenerGPS();

              final kmRecorrido = kmFin - kmInicio;

              print('📍 Puntos GPS totales: ${_puntosGPS.length}');
              print('📊 KM recorrido: $kmRecorrido');

              await FirebaseFirestore.instance
                  .collection('recorridos')
                  .doc(recorridoId)
                  .update({
                    'km_fin': kmFin,
                    'km_recorrido': kmRecorrido,
                    'fecha_fin': DateTime.now(),
                    'estado': 'completado',
                  });

              // Guardar puntos GPS en subcolección
              if (_puntosGPS.isNotEmpty) {
                final batch = FirebaseFirestore.instance.batch();
                for (var punto in _puntosGPS) {
                  final docRef = FirebaseFirestore.instance
                      .collection('recorridos')
                      .doc(recorridoId)
                      .collection('puntos_gps')
                      .doc();
                  batch.set(docRef, punto);
                }
                await batch.commit();
              }

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

  // ========== VER MAPA (CORREGIDO - SIN ERROR 403) ==========

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

  void _cancelarRecorridoActivo() async {
    if (_recorridoIdActivo != null) {
      showDialog(
        context: context,
        builder: (_) => AlertDialog(
          title: const Text('Cancelar Recorrido'),
          content: const Text(
            '¿Está seguro que desea cancelar el recorrido activo? Se perderán todos los datos.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('No'),
            ),
            TextButton(
              onPressed: () async {
                await _detenerGPS();
                await FirebaseFirestore.instance
                    .collection('recorridos')
                    .doc(_recorridoIdActivo)
                    .delete();
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
        foregroundColor: Colors.white,
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
                  Text('Presione el botón + para iniciar uno'),
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
              final fechaInicio = (r['fecha_inicio'] as Timestamp?)?.toDate();
              final fechaFin = (r['fecha_fin'] as Timestamp?)?.toDate();

              return Card(
                elevation: estaActivo ? 4 : 1,
                color: estaActivo ? Colors.yellow[50] : Colors.white,
                child: ListTile(
                  leading: CircleAvatar(
                    backgroundColor: estaActivo ? Colors.green : Colors.blue,
                    child: Icon(
                      estaActivo ? Icons.play_arrow : Icons.check_circle,
                      color: Colors.white,
                    ),
                  ),
                  title: Text(
                    '${r['placa']} - ${r['conductor']}',
                    style: TextStyle(
                      fontWeight: estaActivo ? FontWeight.bold : FontWeight.normal,
                    ),
                  ),
                  subtitle: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Inicio: ${fechaInicio != null ? _formatearFecha(fechaInicio) : "N/A"}'),
                      if (fechaFin != null) Text('Fin: ${_formatearFecha(fechaFin)}'),
                      Text('Km: ${r['km_inicio']} → ${r['km_fin'] ?? "..."} (${r['km_recorrido'] ?? "En curso"} km)'),
                      if (estaActivo)
                        const Text('🟢 EN CURSO', style: TextStyle(color: Colors.green, fontWeight: FontWeight.bold)),
                    ],
                  ),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (estaActivo)
                        ElevatedButton.icon(
                          onPressed: () => _mostrarFormularioFinalizacion(recorridos[i].id, r),
                          icon: const Icon(Icons.stop, size: 18),
                          label: const Text('Finalizar'),
                          style: ElevatedButton.styleFrom(backgroundColor: Colors.green),
                        ),
                      if (!estaActivo)
                        IconButton(
                          icon: const Icon(Icons.map),
                          onPressed: () => _verMapa(recorridos[i].id, r['placa'] ?? '', r['vehiculo'] ?? ''),
                          tooltip: 'Ver recorrido en mapa',
                        ),
                    ],
                  ),
                  isThreeLine: true,
                ),
              );
            },
          );
        },
      ),
    );
  }

  String _formatearFecha(DateTime fecha) {
    return '${fecha.day.toString().padLeft(2, '0')}/${fecha.month.toString().padLeft(2, '0')}/${fecha.year} ${fecha.hour.toString().padLeft(2, '0')}:${fecha.minute.toString().padLeft(2, '0')}';
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

// ========== PÁGINA DEL MAPA CORREGIDA (SIN ERROR 403) ==========

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
  final MapController _mapController = MapController();

  @override
  void initState() {
    super.initState();
    _cargarDatos();
  }

  Future<void> _cargarDatos() async {
    try {
      // Cargar puntos GPS desde subcolección
      final puntosSnapshot = await FirebaseFirestore.instance
          .collection('recorridos')
          .doc(widget.recorridoId)
          .collection('puntos_gps')
          .orderBy('hora')
          .get();

      final puntosTemp = <LatLng>[];
      LatLng? ultimoPunto;

      for (var doc in puntosSnapshot.docs) {
        final punto = LatLng(doc['lat'], doc['lng']);
        
        // Simplificar polilínea: solo agregar si está a más de 10 metros del anterior
        if (ultimoPunto == null) {
          puntosTemp.add(punto);
        } else {
          final distancia = Geolocator.distanceBetween(
            ultimoPunto.latitude, ultimoPunto.longitude,
            punto.latitude, punto.longitude,
          );
          if (distancia > 10) {
            puntosTemp.add(punto);
          }
        }
        ultimoPunto = punto;
      }

      // Cargar paradas
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
      print('Error cargando datos: $e');
      setState(() => _cargando = false);
      _mostrarError();
    }
  }

  void _mostrarError() {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Error al cargar los datos del recorrido')),
    );
  }

  void _mostrarDetalleParada(Map<String, dynamic> parada) {
    final inicio = (parada['inicio'] as Timestamp?)?.toDate();
    final fin = (parada['fin'] as Timestamp?)?.toDate();
    final ubicacion = parada['ubicacion'] as GeoPoint?;

    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => Container(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Row(
              children: [
                Icon(Icons.pause_circle, color: Colors.red, size: 28),
                SizedBox(width: 10),
                Text('Detalle de Parada', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              ],
            ),
            const SizedBox(height: 16),
            if (inicio != null) _buildInfoRow('⏰ Inicio:', _formatearFecha(inicio)),
            if (fin != null) _buildInfoRow('🏁 Fin:', _formatearFecha(fin)),
            _buildInfoRow('⌛ Duración:', '${parada['duracion_minutos'] ?? 0} minutos'),
            const SizedBox(height: 12),
            if (ubicacion != null) ...[
              const Divider(),
              _buildInfoRow('📍 Latitud:', ubicacion.latitude.toStringAsFixed(6)),
              _buildInfoRow('📍 Longitud:', ubicacion.longitude.toStringAsFixed(6)),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildInfoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(width: 80, child: Text(label, style: const TextStyle(fontWeight: FontWeight.w500))),
          Expanded(child: Text(value)),
        ],
      ),
    );
  }

  String _formatearFecha(DateTime fecha) {
    return '${fecha.day.toString().padLeft(2, '0')}/${fecha.month.toString().padLeft(2, '0')}/${fecha.year} ${fecha.hour.toString().padLeft(2, '0')}:${fecha.minute.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    if (_cargando) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    if (_puntos.isEmpty) {
      return Scaffold(
        appBar: AppBar(
          title: Text('Mapa - ${widget.placa}'),
          backgroundColor: const Color(0xFF003580),
          foregroundColor: Colors.white,
        ),
        body: const Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.map, size: 64, color: Colors.grey),
              SizedBox(height: 16),
              Text('No hay puntos GPS registrados'),
              SizedBox(height: 8),
              Text('El recorrido no tiene datos de ubicación'),
            ],
          ),
        ),
      );
    }

    final centro = _puntos.first;
    final inicio = _puntos.first;
    final fin = _puntos.last;

    return Scaffold(
      appBar: AppBar(
        title: Text('${widget.placa} - ${widget.vehiculo}'),
        backgroundColor: const Color(0xFF003580),
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.center_focus_strong),
            onPressed: () {
              _mapController.move(centro, 13);
            },
            tooltip: 'Centrar mapa',
          ),
        ],
      ),
      body: Column(
        children: [
          // Resumen del recorrido
          Container(
            padding: const EdgeInsets.all(12),
            color: Colors.blue[50],
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                Column(
                  children: [
                    const Icon(Icons.play_circle, color: Colors.green),
                    const Text('Inicio'),
                    Text(_formatearFecha(_puntos.isNotEmpty ? DateTime.parse('2024-01-01') : DateTime.now())),
                  ],
                ),
                Column(
                  children: [
                    const Icon(Icons.location_on, color: Colors.red),
                    const Text('Paradas'),
                    Text('${_paradas.length}'),
                  ],
                ),
                Column(
                  children: [
                    const Icon(Icons.flag, color: Colors.orange),
                    const Text('Distancia'),
                    Text('${_calcularDistanciaTotal()} km'),
                  ],
                ),
              ],
            ),
          ),
          // Mapa CORREGIDO - Sin error 403
          Expanded(
            child: FlutterMap(
              mapController: _mapController,
              options: MapOptions(
                initialCenter: centro,
                initialZoom: 14,
              ),
              children: [
                // TILE LAYER CORREGIDO - Usando servidor que NO da error 403
                TileLayer(
                  urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                  userAgentPackageName: 'com.ministerio.publico.cbt',
                  attributionBuilder: (_) {
                    return const Text(
                      '© OpenStreetMap contributors',
                      style: TextStyle(fontSize: 10, color: Colors.black54),
                    );
                  },
                ),
                // Polilínea del recorrido
                PolylineLayer(
                  polylines: [
                    Polyline(
                      points: _puntos,
                      strokeWidth: 4,
                      color: Colors.blue,
                      borderStrokeWidth: 1,
                      borderColor: Colors.white,
                    ),
                  ],
                ),
                // Marcadores de paradas
                MarkerLayer(
                  markers: _paradas.map((parada) {
                    final ubicacion = parada['ubicacion'] as GeoPoint?;
                    if (ubicacion == null) return null;
                    return Marker(
                      point: LatLng(ubicacion.latitude, ubicacion.longitude),
                      width: 60,
                      height: 60,
                      child: GestureDetector(
                        onTap: () => _mostrarDetalleParada(parada),
                        child: Container(
                          decoration: BoxDecoration(
                            color: Colors.red.withOpacity(0.9),
                            shape: BoxShape.circle,
                            border: Border.all(color: Colors.white, width: 2),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black26,
                                blurRadius: 4,
                                offset: const Offset(0, 2),
                              ),
                            ],
                          ),
                          child: const Icon(Icons.pause, color: Colors.white, size: 28),
                        ),
                      ),
                    );
                  }).whereType<Marker>().toList(),
                ),
                // Marcador de inicio
                MarkerLayer(
                  markers: [
                    Marker(
                      point: inicio,
                      width: 60,
                      height: 60,
                      child: Container(
                        decoration: BoxDecoration(
                          color: Colors.green.withOpacity(0.9),
                          shape: BoxShape.circle,
                          border: Border.all(color: Colors.white, width: 2),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black26,
                              blurRadius: 4,
                              offset: const Offset(0, 2),
                            ),
                          ],
                        ),
                        child: const Icon(Icons.play_arrow, color: Colors.white, size: 28),
                      ),
                    ),
                  ],
                ),
                // Marcador de fin
                if (_puntos.length > 1)
                  MarkerLayer(
                    markers: [
                      Marker(
                        point: fin,
                        width: 60,
                        height: 60,
                        child: Container(
                          decoration: BoxDecoration(
                            color: Colors.orange.withOpacity(0.9),
                            shape: BoxShape.circle,
                            border: Border.all(color: Colors.white, width: 2),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black26,
                                blurRadius: 4,
                                offset: const Offset(0, 2),
                              ),
                            ],
                          ),
                          child: const Icon(Icons.stop, color: Colors.white, size: 28),
                        ),
                      ),
                    ],
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  double _calcularDistanciaTotal() {
    double distancia = 0;
    for (int i = 0; i < _puntos.length - 1; i++) {
      distancia += Geolocator.distanceBetween(
        _puntos[i].latitude, _puntos[i].longitude,
        _puntos[i + 1].latitude, _puntos[i + 1].longitude,
      );
    }
    return (distancia / 1000).toStringAsFixed(2); // Convertir a km
  }
}
