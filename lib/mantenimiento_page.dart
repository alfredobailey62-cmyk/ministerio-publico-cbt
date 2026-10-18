import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';

class MaintenancePage extends StatefulWidget {
  const MaintenancePage({super.key});

  @override
  State<MaintenancePage> createState() => _MaintenancePageState();
}

class _MaintenancePageState extends State<MaintenancePage> {
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  static const int maintenanceInterval = 5000;
  static const Color blue = Color(0xFF003580);
  static const Color gold = Color(0xFFD4AF37);

  int? _parseInt(dynamic valor) {
    if (valor is num) return valor.toInt();
    return int.tryParse(valor?.toString() ?? '');
  }

  double _parseDouble(dynamic valor) {
    if (valor is num) return valor.toDouble();
    return double.tryParse(valor?.toString() ?? '') ?? 0;
  }

  String _formatDate(dynamic valor) {
    DateTime? fecha;

    if (valor is Timestamp) fecha = valor.toDate();
    if (valor is DateTime) fecha = valor;

    if (fecha == null) return 'Fecha no disponible';

    final d = fecha.day.toString().padLeft(2, '0');
    final m = fecha.month.toString().padLeft(2, '0');

    return '$d/$m/${fecha.year} '
        '${fecha.hour.toString().padLeft(2, '0')}:'
        '${fecha.minute.toString().padLeft(2, '0')}';
  }

  String _currentUser() {
    return FirebaseAuth.instance.currentUser?.email ?? 'Usuario del sistema';
  }

  int? _currentMileage(Map<String, dynamic> vehiculo) {
    return _parseInt(
      vehiculo['kilometraje'] ?? vehiculo['km_actual'] ?? vehiculo['km'],
    );
  }

  void _showMessage(String texto, {bool error = false}) {
    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(texto),
        backgroundColor: error ? Colors.red.shade800 : blue,
      ),
    );
  }

  Future<void> _registerMaintenance() async {
    final responsable = TextEditingController();
    final kmController = TextEditingController();
    final costoController = TextEditingController();
    final detalleController = TextEditingController();

    String? vehiculoId;
    String tipo = 'Cambio de aceite';
    String ejecucion = 'Taller externo';

    final tipos = [
      'Cambio de aceite',
      'Revisión general',
      'Frenos',
      'Llantas',
      'Motor',
      'Sistema eléctrico',
      'Otro',
    ];

    final formas = ['Taller externo', 'Mecánicos institucionales'];

    final resultado = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: const Text('Registrar mantenimiento'),
              content: SizedBox(
                width: 450,
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                        stream: _db.collection('vehiculos').snapshots(),
                        builder: (context, snapshot) {
                          if (!snapshot.hasData) {
                            return const LinearProgressIndicator();
                          }

                          final vehiculos = snapshot.data!.docs;

                          return DropdownButtonFormField<String>(
                            value: vehiculoId,
                            isExpanded: true,
                            decoration: const InputDecoration(
                              labelText: 'Vehículo',
                              prefixIcon: Icon(Icons.directions_car),
                            ),
                            items: vehiculos.map((doc) {
                              final v = doc.data();
                              final placa = v['placa'] ?? 'Sin placa';
                              final marca = v['marca'] ?? '';
                              final modelo = v['modelo'] ?? '';

                              return DropdownMenuItem(
                                value: doc.id,
                                child: Text('$placa - $marca $modelo'),
                              );
                            }).toList(),
                            onChanged: (value) {
                              setDialogState(() => vehiculoId = value);
                            },
                          );
                        },
                      ),
                      const SizedBox(height: 12),
                      DropdownButtonFormField<String>(
                        value: tipo,
                        isExpanded: true,
                        decoration: const InputDecoration(
                          labelText: 'Trabajo realizado',
                        ),
                        items: tipos.map((item) {
                          return DropdownMenuItem(
                            value: item,
                            child: Text(item),
                          );
                        }).toList(),
                        onChanged: (value) {
                          if (value != null) {
                            setDialogState(() => tipo = value);
                          }
                        },
                      ),
                      if (tipo == 'Otro')
                        TextField(
                          controller: detalleController,
                          decoration: const InputDecoration(
                            labelText: 'Descripción del trabajo',
                          ),
                        ),
                      const SizedBox(height: 8),
                      DropdownButtonFormField<String>(
                        value: ejecucion,
                        isExpanded: true,
                        decoration: const InputDecoration(
                          labelText: 'Tipo de ejecución',
                        ),
                        items: formas.map((item) {
                          return DropdownMenuItem(
                            value: item,
                            child: Text(item),
                          );
                        }).toList(),
                        onChanged: (value) {
                          if (value != null) {
                            setDialogState(() => ejecucion = value);
                          }
                        },
                      ),
                      TextField(
                        controller: responsable,
                        decoration: const InputDecoration(
                          labelText: 'Responsable del mantenimiento',
                        ),
                      ),
                      TextField(
                        controller: kmController,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(
                          labelText: 'Kilometraje del vehículo',
                          suffixText: 'km',
                        ),
                      ),
                      TextField(
                        controller: costoController,
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                        decoration: const InputDecoration(
                          labelText: 'Costo (B/.)',
                          prefixText: 'B/. ',
                        ),
                      ),
                      const SizedBox(height: 10),
                      const Text(
                        'El próximo mantenimiento se calculará '
                        'automáticamente sumando 5,000 km.',
                        style: TextStyle(fontSize: 12),
                      ),
                    ],
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(dialogContext, false),
                  child: const Text('Cancelar'),
                ),
                FilledButton(
                  onPressed: () async {
                    if (vehiculoId == null) {
                      _showMessage('Seleccione un vehículo.', error: true);
                      return;
                    }

                    final km = int.tryParse(kmController.text.trim());
                    final costo = double.tryParse(
                      costoController.text.trim().replaceAll(',', '.'),
                    );

                    if (km == null || km < 0) {
                      _showMessage(
                        'Introduzca un kilometraje válido.',
                        error: true,
                      );
                      return;
                    }

                    if (costo == null || costo < 0) {
                      _showMessage('Introduzca un costo válido.', error: true);
                      return;
                    }

                    if (responsable.text.trim().isEmpty) {
                      _showMessage('Escriba el responsable.', error: true);
                      return;
                    }

                    try {
                      final ref = _db.collection('vehiculos').doc(vehiculoId);
                      final vehiculo = await ref.get();

                      if (!vehiculo.exists) {
                        _showMessage('El vehículo ya no existe.', error: true);
                        return;
                      }

                      final datos = vehiculo.data()!;
                      final proximoKm = km + maintenanceInterval;

                      final registro = _db.collection('mantenimientos').doc();

                      final batch = _db.batch();

                      batch.set(registro, {
                        'vehiculo_id': vehiculoId,
                        'placa': datos['placa'] ?? '',
                        'vehiculo':
                            '${datos['marca'] ?? ''} ${datos['modelo'] ?? ''}'
                                .trim(),
                        'tipo_trabajo': tipo,
                        'descripcion': tipo == 'Otro'
                            ? detalleController.text.trim()
                            : tipo,
                        'tipo_ejecucion': ejecucion,
                        'responsable': responsable.text.trim(),
                        'km': km,
                        'costo': costo,
                        'proximo_mantenimiento_km': proximoKm,
                        'usuario': _currentUser(),
                        'fecha': FieldValue.serverTimestamp(),
                      });

                      // Actualiza el mantenimiento vigente del vehículo.
                      // El registro anterior permanece en la colección.
                      batch.update(ref, {
                        'ultimo_mantenimiento_km': km,
                        'proximo_mantenimiento_km': proximoKm,
                        'fecha_ultimo_mantenimiento':
                            FieldValue.serverTimestamp(),
                      });

                      await batch.commit();

                      if (dialogContext.mounted) {
                        Navigator.pop(dialogContext, true);
                      }
                    } catch (e) {
                      _showMessage(
                        'No se pudo guardar el mantenimiento: $e',
                        error: true,
                      );
                    }
                  },
                  child: const Text('Guardar mantenimiento'),
                ),
              ],
            );
          },
        );
      },
    );

    responsable.dispose();
    kmController.dispose();
    costoController.dispose();
    detalleController.dispose();

    if (resultado == true) {
      _showMessage('Mantenimiento guardado. Próximo: +5,000 km.');
    }
  }

  Future<Position?> _getLocation() async {
    try {
      final habilitado = await Geolocator.isLocationServiceEnabled();

      if (!habilitado) {
        _showMessage('Active el GPS para registrar la ubicación.', error: true);
        return null;
      }

      LocationPermission permiso = await Geolocator.checkPermission();

      if (permiso == LocationPermission.denied) {
        permiso = await Geolocator.requestPermission();
      }

      if (permiso == LocationPermission.denied ||
          permiso == LocationPermission.deniedForever) {
        _showMessage(
          'No hay permiso para obtener la ubicación GPS.',
          error: true,
        );
        return null;
      }

      return await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 20),
        ),
      );
    } catch (e) {
      _showMessage('No se pudo obtener el GPS: $e', error: true);
      return null;
    }
  }

  Future<void> _reportDamage() async {
    final descripcion = TextEditingController();
    final kmController = TextEditingController();

    String? vehiculoId;
    String gravedad = 'Leve';

    final resultado = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: const Text('Reportar avería'),
              content: SizedBox(
                width: 450,
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Text(
                        'Si el vehículo se averió en carretera, '
                        'registre el daño para que el administrador '
                        'pueda coordinar la atención.',
                      ),
                      const SizedBox(height: 12),
                      StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                        stream: _db.collection('vehiculos').snapshots(),
                        builder: (context, snapshot) {
                          if (!snapshot.hasData) {
                            return const LinearProgressIndicator();
                          }

                          return DropdownButtonFormField<String>(
                            value: vehiculoId,
                            isExpanded: true,
                            decoration: const InputDecoration(
                              labelText: 'Vehículo afectado',
                            ),
                            items: snapshot.data!.docs.map((doc) {
                              final v = doc.data();

                              return DropdownMenuItem(
                                value: doc.id,
                                child: Text(
                                  '${v['placa'] ?? 'Sin placa'} - '
                                  '${v['marca'] ?? ''} ${v['modelo'] ?? ''}',
                                ),
                              );
                            }).toList(),
                            onChanged: (value) {
                              setDialogState(() => vehiculoId = value);
                            },
                          );
                        },
                      ),
                      const SizedBox(height: 8),
                      DropdownButtonFormField<String>(
                        value: gravedad,
                        decoration: const InputDecoration(
                          labelText: 'Gravedad del daño',
                        ),
                        items: const [
                          DropdownMenuItem(value: 'Leve', child: Text('Leve')),
                          DropdownMenuItem(
                            value: 'Moderado',
                            child: Text('Moderado'),
                          ),
                          DropdownMenuItem(
                            value: 'Grave',
                            child: Text('Grave'),
                          ),
                        ],
                        onChanged: (value) {
                          if (value != null) {
                            setDialogState(() => gravedad = value);
                          }
                        },
                      ),
                      TextField(
                        controller: descripcion,
                        minLines: 3,
                        maxLines: 5,
                        decoration: const InputDecoration(
                          labelText: 'Describa el daño',
                          hintText:
                              'Ej.: neumático pinchado, motor recalentado...',
                        ),
                      ),
                      TextField(
                        controller: kmController,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(
                          labelText: 'Kilometraje actual (si lo conoce)',
                          suffixText: 'km',
                        ),
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        'Se intentará guardar la ubicación GPS del reporte. '
                        'La ubicación depende del permiso y de la señal GPS.',
                        style: TextStyle(fontSize: 12),
                      ),
                    ],
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(dialogContext, false),
                  child: const Text('Cancelar'),
                ),
                FilledButton.icon(
                  icon: const Icon(Icons.location_on),
                  label: const Text('Enviar al administrador'),
                  onPressed: () async {
                    if (vehiculoId == null) {
                      _showMessage('Seleccione el vehículo.', error: true);
                      return;
                    }

                    if (descripcion.text.trim().isEmpty) {
                      _showMessage('Describa el daño.', error: true);
                      return;
                    }

                    final kmTexto = kmController.text.trim();
                    final km = kmTexto.isEmpty ? null : int.tryParse(kmTexto);

                    if (kmTexto.isNotEmpty && (km == null || km < 0)) {
                      _showMessage('El kilometraje no es válido.', error: true);
                      return;
                    }

                    try {
                      // Intentar GPS. Si falla, el reporte se conserva
                      // sin coordenadas para no perder la emergencia.
                      final posicion = await _getLocation();

                      final vehiculo = await _db
                          .collection('vehiculos')
                          .doc(vehiculoId)
                          .get();

                      if (!vehiculo.exists) {
                        _showMessage('El vehículo ya no existe.', error: true);
                        return;
                      }

                      final v = vehiculo.data()!;
                      final reporteRef = _db.collection('reportes_danos').doc();

                      final mensaje =
                          'Avería ${gravedad.toLowerCase()} en '
                          '${v['placa'] ?? 'vehículo sin placa'}.';

                      final batch = _db.batch();

                      batch.set(reporteRef, {
                        'vehiculo_id': vehiculoId,
                        'placa': v['placa'] ?? '',
                        'vehiculo': '${v['marca'] ?? ''} ${v['modelo'] ?? ''}'
                            .trim(),
                        'gravedad': gravedad,
                        'descripcion': descripcion.text.trim(),
                        'kilometraje': km,
                        'latitud': posicion?.latitude,
                        'longitud': posicion?.longitude,
                        'ubicacion': posicion == null
                            ? null
                            : GeoPoint(posicion.latitude, posicion.longitude),
                        'ubicacion_disponible': posicion != null,
                        'fecha': FieldValue.serverTimestamp(),
                        'reportado_por': _currentUser(),
                        'usuario_uid': FirebaseAuth.instance.currentUser?.uid,
                        'estado': 'Pendiente',
                        'destinatario': 'admin',
                      });

                      // Aviso dirigido al área administradora de la flota.
                      batch.set(_db.collection('avisos_admin').doc(), {
                        'tipo': 'averia_vehiculo',
                        'titulo': 'Reporte de avería: ${v['placa'] ?? ''}',
                        'mensaje': mensaje,
                        'reporte_id': reporteRef.id,
                        'placa': v['placa'] ?? '',
                        'gravedad': gravedad,
                        'destinatario': 'admin',
                        'leido': false,
                        'fecha': FieldValue.serverTimestamp(),
                      });

                      await batch.commit();

                      if (dialogContext.mounted) {
                        Navigator.pop(dialogContext, true);
                      }
                    } catch (e) {
                      _showMessage(
                        'No se pudo enviar el reporte: $e',
                        error: true,
                      );
                    }
                  },
                ),
              ],
            );
          },
        );
      },
    );

    descripcion.dispose();
    kmController.dispose();

    if (resultado == true) {
      _showMessage('Reporte registrado y aviso creado para el administrador.');
    }
  }

  Color _statusColor(int? restante) {
    if (restante == null) return Colors.blueGrey;
    if (restante <= 0) return Colors.red;
    if (restante <= 500) return Colors.orange;
    return Colors.green;
  }

  String _maintenanceStatus(int? restante) {
    if (restante == null) return 'Sin kilometraje actual registrado';
    if (restante < 0) {
      return 'MANTENIMIENTO VENCIDO por ${restante.abs()} km';
    }
    if (restante == 0) return 'MANTENIMIENTO VENCE AHORA';
    if (restante <= 500) return 'Próximo mantenimiento: faltan $restante km';
    return 'Faltan $restante km para el próximo mantenimiento';
  }

  Widget _tarjetaVehiculo(QueryDocumentSnapshot<Map<String, dynamic>> doc) {
    final v = doc.data();
    final placa = v['placa']?.toString() ?? 'Sin placa';
    final actual = _currentMileage(v);
    final proximo = _parseInt(v['proximo_mantenimiento_km']);
    final ultimo = _parseInt(v['ultimo_mantenimiento_km']);

    final restante = actual != null && proximo != null
        ? proximo - actual
        : null;

    final color = _statusColor(restante);

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.directions_car, color: blue, size: 30),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    '$placa - ${v['marca'] ?? ''} ${v['modelo'] ?? ''}',
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text('Kilometraje actual: ${actual ?? 'No registrado'} km'),
            Text('Último mantenimiento: ${ultimo ?? 'No registrado'} km'),
            Text('Próximo mantenimiento: ${proximo ?? 'No programado'} km'),
            const SizedBox(height: 8),
            if (proximo != null && actual != null)
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: LinearProgressIndicator(
                  minHeight: 9,
                  value: ((actual / proximo).clamp(0, 1)).toDouble(),
                  color: color,
                  backgroundColor: Colors.grey.shade300,
                ),
              ),
            const SizedBox(height: 7),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.notification_important, color: color),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    _maintenanceStatus(restante),
                    style: TextStyle(color: color, fontWeight: FontWeight.bold),
                  ),
                ),
              ],
            ),
            if (actual == null)
              const Padding(
                padding: EdgeInsets.only(top: 6),
                child: Text(
                  'Actualice el kilometraje del vehículo desde el registro '
                  'de recorridos para calcular la alerta.',
                  style: TextStyle(fontSize: 12),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _sectionTitle(String texto, IconData icono) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      child: Row(
        children: [
          Icon(icono, color: blue),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              texto,
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: blue,
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Mantenimiento y averías'),
        backgroundColor: blue,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            tooltip: 'Registrar mantenimiento',
            onPressed: _registerMaintenance,
            icon: const Icon(Icons.build),
          ),
          IconButton(
            tooltip: 'Reportar avería',
            onPressed: _reportDamage,
            icon: const Icon(Icons.warning_amber),
          ),
        ],
      ),
      floatingActionButton: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          FloatingActionButton.extended(
            heroTag: 'averia',
            onPressed: _reportDamage,
            backgroundColor: Colors.red.shade700,
            foregroundColor: Colors.white,
            icon: const Icon(Icons.warning_amber),
            label: const Text('Reportar avería'),
          ),
          const SizedBox(height: 10),
          FloatingActionButton.extended(
            heroTag: 'mantenimiento',
            onPressed: _registerMaintenance,
            backgroundColor: gold,
            foregroundColor: Colors.black,
            icon: const Icon(Icons.add_task),
            label: const Text('Mantenimiento'),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 100),
        children: [
          _sectionTitle('Estado preventivo de la flota', Icons.speed),
          StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
            stream: _db.collection('vehiculos').snapshots(),
            builder: (context, snapshot) {
              if (snapshot.hasError) {
                return const Padding(
                  padding: EdgeInsets.all(16),
                  child: Text('No se pudo cargar la flota.'),
                );
              }

              if (!snapshot.hasData) {
                return const Center(child: CircularProgressIndicator());
              }

              final vehiculos = snapshot.data!.docs;

              if (vehiculos.isEmpty) {
                return const Padding(
                  padding: EdgeInsets.all(16),
                  child: Text('Todavía no hay vehículos registrados.'),
                );
              }

              return Column(children: vehiculos.map(_tarjetaVehiculo).toList());
            },
          ),
          _sectionTitle(
            'Reportes de averías pendientes',
            Icons.notification_important,
          ),
          StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
            stream: _db
                .collection('reportes_danos')
                .where('estado', isEqualTo: 'Pendiente')
                .snapshots(),
            builder: (context, snapshot) {
              if (snapshot.hasError) {
                return const Padding(
                  padding: EdgeInsets.all(16),
                  child: Text('No se pudieron cargar los reportes.'),
                );
              }

              if (!snapshot.hasData) {
                return const Center(child: CircularProgressIndicator());
              }

              final reportes = snapshot.data!.docs;

              if (reportes.isEmpty) {
                return const Padding(
                  padding: EdgeInsets.all(16),
                  child: Text('No hay averías pendientes registradas.'),
                );
              }

              return Column(
                children: reportes.map((doc) {
                  final d = doc.data();
                  final grave = d['gravedad'] == 'Grave';
                  final moderado = d['gravedad'] == 'Moderado';

                  final color = grave
                      ? Colors.red
                      : moderado
                      ? Colors.orange
                      : Colors.blueGrey;

                  return Card(
                    margin: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 4,
                    ),
                    child: ListTile(
                      leading: Icon(Icons.warning_amber, color: color),
                      title: Text(
                        '${d['placa'] ?? 'Sin placa'} · '
                        '${d['gravedad'] ?? 'Sin gravedad'}',
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                      subtitle: Text(
                        '${d['descripcion'] ?? ''}\n'
                        'Reportado: ${d['reportado_por'] ?? 'No identificado'}\n'
                        '${_formatDate(d['fecha'])}',
                      ),
                      isThreeLine: true,
                      trailing: d['ubicacion_disponible'] == true
                          ? const Icon(Icons.location_on, color: Colors.green)
                          : const Icon(Icons.location_off, color: Colors.grey),
                      onTap: () => _showDamageDetails(doc.id, d),
                    ),
                  );
                }).toList(),
              );
            },
          ),
          _sectionTitle('Historial de mantenimientos', Icons.history),
          StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
            stream: _db
                .collection('mantenimientos')
                .orderBy('fecha', descending: true)
                .snapshots(),
            builder: (context, snapshot) {
              if (snapshot.hasError) {
                return const Padding(
                  padding: EdgeInsets.all(16),
                  child: Text('No se pudo cargar el historial.'),
                );
              }

              if (!snapshot.hasData) {
                return const Center(child: CircularProgressIndicator());
              }

              final docs = snapshot.data!.docs;

              if (docs.isEmpty) {
                return const Padding(
                  padding: EdgeInsets.all(16),
                  child: Text('Todavía no hay mantenimientos registrados.'),
                );
              }

              return Column(
                children: docs.map((doc) {
                  final d = doc.data();

                  return Card(
                    margin: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 4,
                    ),
                    child: ListTile(
                      leading: const CircleAvatar(
                        backgroundColor: blue,
                        foregroundColor: Colors.white,
                        child: Icon(Icons.build),
                      ),
                      title: Text(
                        '${d['placa'] ?? ''} · ${d['tipo_trabajo'] ?? ''}',
                      ),
                      subtitle: Text(
                        'Kilometraje: ${d['km'] ?? '—'} km\n'
                        'Próximo: ${d['proximo_mantenimiento_km'] ?? '—'} km\n'
                        'Fecha: ${_formatDate(d['fecha'])}',
                      ),
                      isThreeLine: true,
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () => _showMaintenanceDetails(d),
                    ),
                  );
                }).toList(),
              );
            },
          ),
        ],
      ),
    );
  }

  void _showMaintenanceDetails(Map<String, dynamic> d) {
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Mantenimiento ${d['placa'] ?? ''}'),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('Vehículo: ${d['vehiculo'] ?? ''}'),
              Text('Trabajo: ${d['tipo_trabajo'] ?? ''}'),
              Text('Detalle: ${d['descripcion'] ?? ''}'),
              Text('Responsable: ${d['responsable'] ?? ''}'),
              Text('Kilometraje: ${d['km'] ?? ''} km'),
              Text(
                'Próximo mantenimiento: '
                '${d['proximo_mantenimiento_km'] ?? '—'} km',
              ),
              Text('Costo: B/. ${_parseDouble(d['costo']).toStringAsFixed(2)}'),
              Text('Fecha y hora: ${_formatDate(d['fecha'])}'),
              Text('Registrado por: ${d['usuario'] ?? ''}'),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cerrar'),
          ),
        ],
      ),
    );
  }

  void _showDamageDetails(String id, Map<String, dynamic> d) {
    final lat = d['latitud'];
    final lon = d['longitud'];

    showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('Avería: ${d['placa'] ?? ''}'),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('Gravedad: ${d['gravedad'] ?? ''}'),
              Text('Descripción: ${d['descripcion'] ?? ''}'),
              Text('Kilometraje: ${d['kilometraje'] ?? 'No informado'}'),
              Text('Reportado por: ${d['reportado_por'] ?? ''}'),
              Text('Fecha: ${_formatDate(d['fecha'])}'),
              const SizedBox(height: 10),
              if (lat != null && lon != null)
                SelectableText('Coordenadas GPS: $lat, $lon')
              else
                const Text('El reporte no tiene coordenadas GPS.'),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cerrar'),
          ),
          if (lat != null && lon != null)
            TextButton(
              onPressed: () {
                // Copia las coordenadas para abrirlas en un mapa.
                // No requiere paquete adicional.
                Navigator.pop(dialogContext);
                _showMessage('Coordenadas GPS: $lat, $lon');
              },
              child: const Text('Ver coordenadas'),
            ),
          FilledButton(
            onPressed: () async {
              try {
                await _db.collection('reportes_danos').doc(id).update({
                  'estado': 'Atendido',
                  'atendido_por': _currentUser(),
                  'fecha_atencion': FieldValue.serverTimestamp(),
                });

                if (dialogContext.mounted) {
                  Navigator.pop(dialogContext);
                }

                _showMessage('Reporte marcado como atendido.');
              } catch (e) {
                _showMessage(
                  'No se pudo actualizar el reporte: $e',
                  error: true,
                );
              }
            },
            child: const Text('Marcar atendido'),
          ),
        ],
      ),
    );
  }
}
