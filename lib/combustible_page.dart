import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

class FuelPage extends StatefulWidget {
  const FuelPage({super.key});

  @override
  State<FuelPage> createState() => _FuelPageState();
}

class _FuelPageState extends State<FuelPage> {
  static const Color azul = Color(0xFF003580);

  final _plateController = TextEditingController();
  final _mileageController = TextEditingController();
  final _quantityController = TextEditingController();

  Map<String, dynamic>? _vehicle;
  String? _vehicleId;
  String _unit = 'Litros';
  String _tankLevel = 'Medio tanque';
  Uint8List? _imagenBytes;
  bool _searching = false;
  bool _saving = false;
  String? _errorMessage;

  final List<String> _tankLevels = const [
    'Vacío',
    '1/4 de tanque',
    'Medio tanque',
    '3/4 de tanque',
    'Tanque lleno',
  ];

  @override
  void dispose() {
    _plateController.dispose();
    _mileageController.dispose();
    _quantityController.dispose();
    super.dispose();
  }

  String _normalizePlate(String placa) =>
      placa.trim().toUpperCase().replaceAll(RegExp(r'[\s-]'), '');

  double _toLiters(double cantidad) =>
      _unit == 'Galones' ? cantidad * 3.785411784 : cantidad;

  Future<void> _findVehicle() async {
    final placa = _normalizePlate(_plateController.text);

    if (placa.isEmpty) {
      setState(() => _errorMessage = 'Escriba la placa del vehículo.');
      return;
    }

    setState(() {
      _searching = true;
      _errorMessage = null;
      _vehicle = null;
      _vehicleId = null;
    });

    try {
      final snapshot = await FirebaseFirestore.instance
          .collection('vehiculos')
          .get();

      QueryDocumentSnapshot<Map<String, dynamic>>? encontrado;

      for (final doc in snapshot.docs) {
        final datos = doc.data();

        if (_normalizePlate((datos['placa'] ?? '').toString()) == placa) {
          encontrado = doc;
          break;
        }
      }

      if (!mounted) return;

      if (encontrado == null) {
        setState(() {
          _errorMessage =
              'No se encontró esa placa. Verifique que el vehículo esté registrado.';
        });
      } else {
        setState(() {
          _vehicleId = encontrado!.id;
          _vehicle = encontrado.data();
          _errorMessage = null;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _errorMessage = 'No se pudo consultar el vehículo: $e');
      }
    } finally {
      if (mounted) {
        setState(() => _searching = false);
      }
    }
  }

  Future<String?> _uploadReceipt(String placa) async {
    if (_imagenBytes == null) return null;

    final nombre =
        '${_normalizePlate(placa)}-${DateTime.now().millisecondsSinceEpoch}.jpg';

    final ref = FirebaseStorage.instance.ref().child(
      'comprobantes_combustible/$nombre',
    );

    await ref.putData(_imagenBytes!);

    return ref.getDownloadURL();
  }

  Future<void> _saveRecord() async {
    if (_vehicleId == null || _vehicle == null) {
      setState(() {
        _errorMessage = 'Primero busque y confirme la placa del vehículo.';
      });
      return;
    }

    final kmTexto = _mileageController.text.trim().replaceAll(',', '.');
    final cantidadTexto = _quantityController.text.trim().replaceAll(',', '.');

    final km = double.tryParse(kmTexto);
    final cantidad = double.tryParse(cantidadTexto);

    if (km == null || km < 0) {
      setState(() => _errorMessage = 'Ingrese un kilometraje válido.');
      return;
    }

    if (cantidad == null || cantidad <= 0) {
      setState(() {
        _errorMessage = 'Ingrese una cantidad de combustible mayor que cero.';
      });
      return;
    }

    setState(() {
      _saving = true;
      _errorMessage = null;
    });

    try {
      final ahora = DateTime.now();
      final usuario = FirebaseAuth.instance.currentUser;

      final placa = (_vehicle!['placa'] ?? _plateController.text).toString();

      final litros = _toLiters(cantidad);
      final comprobante = await _uploadReceipt(placa);

      await FirebaseFirestore.instance.collection('combustible').add({
        'vehiculo_id': _vehicleId,
        'placa': placa,
        'marca': (_vehicle!['marca'] ?? '').toString(),
        'modelo': (_vehicle!['modelo'] ?? '').toString(),
        'kilometraje': km,
        'cantidad_ingresada': cantidad,
        'unidad_ingresada': _unit,
        'litros_equivalentes': litros,
        'nivel_tanque': _tankLevel,
        'comprobante_url': comprobante ?? '',
        'fecha': Timestamp.fromDate(ahora),
        'mes': ahora.month,
        'anio': ahora.year,
        'mes_anio': '${ahora.year}-${ahora.month.toString().padLeft(2, '0')}',
        'usuario_uid': usuario?.uid ?? '',
        'usuario_nombre':
            usuario?.displayName ?? usuario?.email ?? 'Usuario no identificado',
        'usuario_email': usuario?.email ?? '',
        'creado_en': FieldValue.serverTimestamp(),
      });

      if (!mounted) return;

      setState(() {
        _mileageController.clear();
        _quantityController.clear();
        _plateController.clear();
        _vehicle = null;
        _vehicleId = null;
        _imagenBytes = null;
        _unit = 'Litros';
        _tankLevel = 'Medio tanque';
      });

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Registro de combustible guardado.')),
      );
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = 'No se pudo guardar el registro: $e';
        });
      }
    } finally {
      if (mounted) {
        setState(() => _saving = false);
      }
    }
  }

  String _formatDateTime(dynamic valor) {
    DateTime? fecha;

    if (valor is Timestamp) fecha = valor.toDate();
    if (valor is DateTime) fecha = valor;

    if (fecha == null) return 'Fecha no disponible';

    final d = fecha.day.toString().padLeft(2, '0');
    final m = fecha.month.toString().padLeft(2, '0');
    final h = fecha.hour.toString().padLeft(2, '0');
    final min = fecha.minute.toString().padLeft(2, '0');

    return '$d/$m/${fecha.year} $h:$min';
  }

  String _currentMonthName() {
    const meses = [
      'enero',
      'febrero',
      'marzo',
      'abril',
      'mayo',
      'junio',
      'julio',
      'agosto',
      'septiembre',
      'octubre',
      'noviembre',
      'diciembre',
    ];

    final ahora = DateTime.now();

    return '${meses[ahora.month - 1]} ${ahora.year}';
  }

  Widget _buildForm() {
    return Card(
      margin: const EdgeInsets.all(12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Registrar carga de combustible',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 6),
            const Text(
              'Ingrese la placa; el sistema buscará el vehículo registrado.',
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _plateController,
                    textCapitalization: TextCapitalization.characters,
                    decoration: const InputDecoration(
                      labelText: 'Placa del vehículo',
                      hintText: 'Ej. ABC123',
                      border: OutlineInputBorder(),
                      prefixIcon: Icon(Icons.directions_car),
                    ),
                    onSubmitted: (_) => _findVehicle(),
                  ),
                ),
                const SizedBox(width: 8),
                SizedBox(
                  height: 56,
                  child: ElevatedButton(
                    onPressed: _searching ? null : _findVehicle,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: azul,
                      foregroundColor: Colors.white,
                    ),
                    child: _searching
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Text('Buscar'),
                  ),
                ),
              ],
            ),
            if (_vehicle != null) ...[
              const SizedBox(height: 12),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.green.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.green),
                ),
                child: Text(
                  'Vehículo identificado\n'
                  '${_vehicle!['placa'] ?? ''} · '
                  '${_vehicle!['marca'] ?? ''} '
                  '${_vehicle!['modelo'] ?? ''}',
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _mileageController,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                decoration: const InputDecoration(
                  labelText: 'Kilometraje actual del vehículo',
                  hintText: 'Ej. 85420',
                  suffixText: 'km',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.speed),
                ),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                value: _unit,
                decoration: const InputDecoration(
                  labelText: 'Unidad de combustible',
                  border: OutlineInputBorder(),
                ),
                items: const [
                  DropdownMenuItem(value: 'Litros', child: Text('Litros')),
                  DropdownMenuItem(value: 'Galones', child: Text('Galones')),
                ],
                onChanged: (v) {
                  setState(() => _unit = v ?? 'Litros');
                },
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _quantityController,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                decoration: InputDecoration(
                  labelText: 'Cantidad cargada',
                  hintText: _unit == 'Litros' ? 'Ej. 35.5' : 'Ej. 9.4',
                  suffixText: _unit == 'Litros' ? 'L' : 'gal',
                  border: const OutlineInputBorder(),
                  prefixIcon: const Icon(Icons.local_gas_station),
                ),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                value: _tankLevel,
                decoration: const InputDecoration(
                  labelText: 'Nivel aproximado del tanque después de cargar',
                  border: OutlineInputBorder(),
                ),
                items: _tankLevels
                    .map(
                      (nivel) =>
                          DropdownMenuItem(value: nivel, child: Text(nivel)),
                    )
                    .toList(),
                onChanged: (v) {
                  setState(() {
                    _tankLevel = v ?? 'Medio tanque';
                  });
                },
              ),
              const SizedBox(height: 12),
              const Text(
                'Comprobante (opcional)',
                style: TextStyle(fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 8),
              if (_imagenBytes != null)
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: Image.memory(
                    _imagenBytes!,
                    height: 110,
                    fit: BoxFit.cover,
                  ),
                ),
              OutlinedButton.icon(
                onPressed: () async {
                  final imagen = await ImagePicker().pickImage(
                    source: ImageSource.gallery,
                  );

                  if (imagen != null) {
                    final bytes = await imagen.readAsBytes();

                    if (mounted) {
                      setState(() => _imagenBytes = bytes);
                    }
                  }
                },
                icon: const Icon(Icons.receipt_long),
                label: Text(
                  _imagenBytes == null
                      ? 'Adjuntar comprobante'
                      : 'Cambiar comprobante',
                ),
              ),
              if (_errorMessage != null) ...[
                const SizedBox(height: 8),
                Text(_errorMessage!, style: const TextStyle(color: Colors.red)),
              ],
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: _saving ? null : _saveRecord,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: azul,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                  icon: _saving
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.save),
                  label: Text(_saving ? 'Guardando...' : 'Guardar registro'),
                ),
              ),
            ],
            if (_errorMessage != null && _vehicle == null) ...[
              const SizedBox(height: 8),
              Text(_errorMessage!, style: const TextStyle(color: Colors.red)),
            ],
          ],
        ),
      ),
    );
  }

  Widget _resumenMensual() {
    final ahora = DateTime.now();
    final inicio = DateTime(ahora.year, ahora.month, 1);
    final fin = DateTime(ahora.year, ahora.month + 1, 1);

    final consulta = FirebaseFirestore.instance
        .collection('combustible')
        .where('fecha', isGreaterThanOrEqualTo: Timestamp.fromDate(inicio))
        .where('fecha', isLessThan: Timestamp.fromDate(fin));

    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: consulta.snapshots(),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return const Card(
            child: Padding(
              padding: EdgeInsets.all(16),
              child: Text('No se pudo cargar el resumen mensual.'),
            ),
          );
        }

        if (!snapshot.hasData) {
          return const Padding(
            padding: EdgeInsets.all(20),
            child: Center(child: CircularProgressIndicator()),
          );
        }

        final registros = snapshot.data!.docs;
        final Map<String, double> litrosPorVehiculo = {};
        double totalLitros = 0;

        for (final doc in registros) {
          final d = doc.data();
          final id = (d['vehiculo_id'] ?? '').toString();

          final litros =
              (d['litros_equivalentes'] as num?)?.toDouble() ??
              (d['litros'] as num?)?.toDouble() ??
              0.0;

          totalLitros += litros;
          litrosPorVehiculo[id] = (litrosPorVehiculo[id] ?? 0) + litros;
        }

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
              child: Text(
                'Resumen de ${_currentMonthName()}',
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            Card(
              margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    const CircleAvatar(
                      backgroundColor: azul,
                      child: Icon(Icons.local_gas_station, color: Colors.white),
                    ),
                    const SizedBox(width: 12),
                    const Expanded(
                      child: Text('Combustible registrado este mes'),
                    ),
                    Text(
                      '${totalLitros.toStringAsFixed(2)} L',
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            if (registros.isEmpty)
              const Padding(
                padding: EdgeInsets.all(16),
                child: Text('Todavía no hay cargas registradas este mes.'),
              )
            else
              ...litrosPorVehiculo.entries.map((entrada) {
                final docsVehiculo =
                    registros
                        .where(
                          (doc) =>
                              (doc.data()['vehiculo_id'] ?? '').toString() ==
                              entrada.key,
                        )
                        .toList()
                      ..sort((a, b) {
                        final da = a.data()['fecha'];
                        final db = b.data()['fecha'];

                        final ta = da is Timestamp
                            ? da.millisecondsSinceEpoch
                            : 0;

                        final tb = db is Timestamp
                            ? db.millisecondsSinceEpoch
                            : 0;

                        return tb.compareTo(ta);
                      });

                final ultimo = docsVehiculo.first.data();

                final placa = (ultimo['placa'] ?? 'Vehículo').toString();

                final marcaModelo =
                    '${ultimo['marca'] ?? ''} ${ultimo['modelo'] ?? ''}'.trim();

                // Estimación orientativa según kilometrajes y cargas.
                // No es una inteligencia artificial entrenada.
                double? rendimiento;

                if (docsVehiculo.length >= 2) {
                  final recientes = docsVehiculo
                      .where((d) => d.data()['kilometraje'] is num)
                      .toList();

                  if (recientes.length >= 2) {
                    final kmNuevo = (recientes[0].data()['kilometraje'] as num)
                        .toDouble();

                    final kmAnterior =
                        (recientes[1].data()['kilometraje'] as num).toDouble();

                    final litrosAnterior =
                        ((recientes[1].data()['litros_equivalentes'] as num?)
                            ?.toDouble() ??
                        0);

                    final diferencia = kmNuevo - kmAnterior;

                    if (diferencia > 0 && litrosAnterior > 0) {
                      rendimiento = diferencia / litrosAnterior;
                    }
                  }
                }

                return Card(
                  margin: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 6,
                  ),
                  child: ExpansionTile(
                    leading: const Icon(Icons.directions_car, color: azul),
                    title: Text(
                      placa,
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                    subtitle: Text(
                      '$marcaModelo · '
                      '${entrada.value.toStringAsFixed(2)} L este mes',
                    ),
                    children: [
                      if (rendimiento != null &&
                          rendimiento.isFinite &&
                          rendimiento > 0)
                        ListTile(
                          leading: const Icon(Icons.insights),
                          title: Text(
                            'Rendimiento estimado: '
                            '${rendimiento.toStringAsFixed(1)} km/L',
                          ),
                          subtitle: const Text(
                            'Estimación orientativa con los dos registros '
                            'más recientes del mes; no es una predicción '
                            'de IA entrenada.',
                          ),
                        )
                      else
                        const ListTile(
                          leading: Icon(Icons.insights),
                          title: Text('Rendimiento aún no disponible'),
                          subtitle: Text(
                            'Se necesitan cargas consecutivas con '
                            'kilometrajes crecientes para estimarlo.',
                          ),
                        ),
                      const Divider(height: 1),
                      ...docsVehiculo.map((doc) {
                        final d = doc.data();

                        final fecha = _formatDateTime(d['fecha']);

                        final km =
                            (d['kilometraje'] as num?)?.toStringAsFixed(0) ??
                            'No indicado';

                        final litros =
                            ((d['litros_equivalentes'] as num?)?.toDouble() ??
                            (d['litros'] as num?)?.toDouble() ??
                            0);

                        final usuario =
                            (d['usuario_nombre'] ?? 'Usuario no identificado')
                                .toString();

                        final cantidad = (d['cantidad_ingresada'] as num?)
                            ?.toDouble();

                        final unidad = (d['unidad_ingresada'] ?? 'Litros')
                            .toString();

                        final nivel = (d['nivel_tanque'] ?? 'No indicado')
                            .toString();

                        return ListTile(
                          leading: const Icon(Icons.receipt_long),
                          title: Text(
                            '${cantidad?.toStringAsFixed(2) ?? litros.toStringAsFixed(2)} '
                            '$unidad · $fecha',
                          ),
                          subtitle: Text(
                            'Kilometraje: $km km · Tanque: $nivel\n'
                            'Equivalente: ${litros.toStringAsFixed(2)} L · '
                            'Registró: $usuario',
                          ),
                          isThreeLine: true,
                        );
                      }),
                    ],
                  ),
                );
              }),
            const SizedBox(height: 12),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: azul,
        foregroundColor: Colors.white,
        title: const Text('Control de combustible'),
      ),
      body: ListView(children: [_buildForm(), _resumenMensual()]),
    );
  }
}
