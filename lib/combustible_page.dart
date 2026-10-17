import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

class CombustiblePage extends StatefulWidget {
  const CombustiblePage({super.key});

  @override
  State<CombustiblePage> createState() => _CombustiblePageState();
}

class _CombustiblePageState extends State<CombustiblePage> {
  static const Color azul = Color(0xFF003580);

  final _placaController = TextEditingController();
  final _kmController = TextEditingController();
  final _cantidadController = TextEditingController();

  Map<String, dynamic>? _vehiculo;
  String? _vehiculoId;
  String _unidad = 'Litros';
  String _nivelTanque = 'Medio tanque';
  Uint8List? _imagenBytes;
  bool _buscando = false;
  bool _guardando = false;
  String? _error;

  final List<String> _nivelesTanque = const [
    'Vacío',
    '1/4 de tanque',
    'Medio tanque',
    '3/4 de tanque',
    'Tanque lleno',
  ];

  @override
  void dispose() {
    _placaController.dispose();
    _kmController.dispose();
    _cantidadController.dispose();
    super.dispose();
  }

  String _normalizarPlaca(String placa) =>
      placa.trim().toUpperCase().replaceAll(RegExp(r'[\s-]'), '');

  double _aLitros(double cantidad) =>
      _unidad == 'Galones' ? cantidad * 3.785411784 : cantidad;

  Future<void> _buscarVehiculo() async {
    final placa = _normalizarPlaca(_placaController.text);

    if (placa.isEmpty) {
      setState(() => _error = 'Escriba la placa del vehículo.');
      return;
    }

    setState(() {
      _buscando = true;
      _error = null;
      _vehiculo = null;
      _vehiculoId = null;
    });

    try {
      final snapshot =
          await FirebaseFirestore.instance.collection('vehiculos').get();

      QueryDocumentSnapshot<Map<String, dynamic>>? encontrado;

      for (final doc in snapshot.docs) {
        final datos = doc.data();

        if (_normalizarPlaca((datos['placa'] ?? '').toString()) == placa) {
          encontrado = doc;
          break;
        }
      }

      if (!mounted) return;

      if (encontrado == null) {
        setState(() {
          _error =
              'No se encontró esa placa. Verifique que el vehículo esté registrado.';
        });
      } else {
        setState(() {
          _vehiculoId = encontrado!.id;
          _vehiculo = encontrado.data();
          _error = null;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _error = 'No se pudo consultar el vehículo: $e');
      }
    } finally {
      if (mounted) {
        setState(() => _buscando = false);
      }
    }
  }

  Future<String?> _subirComprobante(String placa) async {
    if (_imagenBytes == null) return null;

    final nombre =
        '${_normalizarPlaca(placa)}-${DateTime.now().millisecondsSinceEpoch}.jpg';

    final ref = FirebaseStorage.instance
        .ref()
        .child('comprobantes_combustible/$nombre');

    await ref.putData(_imagenBytes!);

    return ref.getDownloadURL();
  }

  Future<void> _guardarRegistro() async {
    if (_vehiculoId == null || _vehiculo == null) {
      setState(() {
        _error = 'Primero busque y confirme la placa del vehículo.';
      });
      return;
    }

    final kmTexto = _kmController.text.trim().replaceAll(',', '.');
    final cantidadTexto =
        _cantidadController.text.trim().replaceAll(',', '.');

    final km = double.tryParse(kmTexto);
    final cantidad = double.tryParse(cantidadTexto);

    if (km == null || km < 0) {
      setState(() => _error = 'Ingrese un kilometraje válido.');
      return;
    }

    if (cantidad == null || cantidad <= 0) {
      setState(() {
        _error = 'Ingrese una cantidad de combustible mayor que cero.';
      });
      return;
    }

    setState(() {
      _guardando = true;
      _error = null;
    });

    try {
      final ahora = DateTime.now();
      final usuario = FirebaseAuth.instance.currentUser;

      final placa =
          (_vehiculo!['placa'] ?? _placaController.text).toString();

      final litros = _aLitros(cantidad);
      final comprobante = await _subirComprobante(placa);

      await FirebaseFirestore.instance.collection('combustible').add({
        'vehiculo_id': _vehiculoId,
        'placa': placa,
        'marca': (_vehiculo!['marca'] ?? '').toString(),
        'modelo': (_vehiculo!['modelo'] ?? '').toString(),
        'kilometraje': km,
        'cantidad_ingresada': cantidad,
        'unidad_ingresada': _unidad,
        'litros_equivalentes': litros,
        'nivel_tanque': _nivelTanque,
        'comprobante_url': comprobante ?? '',
        'fecha': Timestamp.fromDate(ahora),
        'mes': ahora.month,
        'anio': ahora.year,
        'mes_anio':
            '${ahora.year}-${ahora.month.toString().padLeft(2, '0')}',
        'usuario_uid': usuario?.uid ?? '',
        'usuario_nombre': usuario?.displayName ??
            usuario?.email ??
            'Usuario no identificado',
        'usuario_email': usuario?.email ?? '',
        'creado_en': FieldValue.serverTimestamp(),
      });

      if (!mounted) return;

      setState(() {
        _kmController.clear();
        _cantidadController.clear();
        _placaController.clear();
        _vehiculo = null;
        _vehiculoId = null;
        _imagenBytes = null;
        _unidad = 'Litros';
        _nivelTanque = 'Medio tanque';
      });

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Registro de combustible guardado.'),
        ),
      );
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = 'No se pudo guardar el registro: $e';
        });
      }
    } finally {
      if (mounted) {
        setState(() => _guardando = false);
      }
    }
  }

  String _fechaHora(dynamic valor) {
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

  String _mesActual() {
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

  Widget _crearFormulario() {
    return Card(
      margin: const EdgeInsets.all(12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Registrar carga de combustible',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
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
                    controller: _placaController,
                    textCapitalization: TextCapitalization.characters,
                    decoration: const InputDecoration(
                      labelText: 'Placa del vehículo',
                      hintText: 'Ej. ABC123',
                      border: OutlineInputBorder(),
                      prefixIcon: Icon(Icons.directions_car),
                    ),
                    onSubmitted: (_) => _buscarVehiculo(),
                  ),
                ),
                const SizedBox(width: 8),
                SizedBox(
                  height: 56,
                  child: ElevatedButton(
                    onPressed: _buscando ? null : _buscarVehiculo,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: azul,
                      foregroundColor: Colors.white,
                    ),
                    child: _buscando
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                            ),
                          )
                        : const Text('Buscar'),
                  ),
                ),
              ],
            ),
            if (_vehiculo != null) ...[
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
                  '${_vehiculo!['placa'] ?? ''} · '
                  '${_vehiculo!['marca'] ?? ''} '
                  '${_vehiculo!['modelo'] ?? ''}',
                  style: const TextStyle(
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _kmController,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
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
                value: _unidad,
                decoration: const InputDecoration(
                  labelText: 'Unidad de combustible',
                  border: OutlineInputBorder(),
                ),
                items: const [
                  DropdownMenuItem(
                    value: 'Litros',
                    child: Text('Litros'),
                  ),
                  DropdownMenuItem(
                    value: 'Galones',
                    child: Text('Galones'),
                  ),
                ],
                onChanged: (v) {
                  setState(() => _unidad = v ?? 'Litros');
                },
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _cantidadController,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                decoration: InputDecoration(
                  labelText: 'Cantidad cargada',
                  hintText: _unidad == 'Litros' ? 'Ej. 35.5' : 'Ej. 9.4',
                  suffixText: _unidad == 'Litros' ? 'L' : 'gal',
                  border: const OutlineInputBorder(),
                  prefixIcon: const Icon(Icons.local_gas_station),
                ),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                value: _nivelTanque,
                decoration: const InputDecoration(
                  labelText: 'Nivel aproximado del tanque después de cargar',
                  border: OutlineInputBorder(),
                ),
                items: _nivelesTanque
                    .map(
                      (nivel) => DropdownMenuItem(
                        value: nivel,
                        child: Text(nivel),
                      ),
                    )
                    .toList(),
                onChanged: (v) {
                  setState(() {
                    _nivelTanque = v ?? 'Medio tanque';
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
              if (_error != null) ...[
                const SizedBox(height: 8),
                Text(
                  _error!,
                  style: const TextStyle(color: Colors.red),
                ),
              ],
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: _guardando ? null : _guardarRegistro,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: azul,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                  icon: _guardando
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                          ),
                        )
                      : const Icon(Icons.save),
                  label: Text(
                    _guardando ? 'Guardando...' : 'Guardar registro',
                  ),
                ),
              ),
            ],
            if (_error != null && _vehiculo == null) ...[
              const SizedBox(height: 8),
              Text(
                _error!,
                style: const TextStyle(color: Colors.red),
              ),
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
        .where(
          'fecha',
          isGreaterThanOrEqualTo: Timestamp.fromDate(inicio),
        )
        .where(
          'fecha',
          isLessThan: Timestamp.fromDate(fin),
        );

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
            child: Center(
              child: CircularProgressIndicator(),
            ),
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
          litrosPorVehiculo[id] =
              (litrosPorVehiculo[id] ?? 0) + litros;
        }

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
              child: Text(
                'Resumen de ${_mesActual()}',
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            Card(
              margin: const EdgeInsets.symmetric(
                horizontal: 12,
                vertical: 8,
              ),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    const CircleAvatar(
                      backgroundColor: azul,
                      child: Icon(
                        Icons.local_gas_station,
                        color: Colors.white,
                      ),
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
                child: Text(
                  'Todavía no hay cargas registradas este mes.',
                ),
              )
            else
              ...litrosPorVehiculo.entries.map((entrada) {
                final docsVehiculo = registros
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
                    '${ultimo['marca'] ?? ''} ${ultimo['modelo'] ?? ''}'
                        .trim();

                // Estimación orientativa según kilometrajes y cargas.
                // No es una inteligencia artificial entrenada.
                double? rendimiento;

                if (docsVehiculo.length >= 2) {
                  final recientes = docsVehiculo
                      .where(
                        (d) => d.data()['kilometraje'] is num,
                      )
                      .toList();

                  if (recientes.length >= 2) {
                    final kmNuevo =
                        (recientes[0].data()['kilometraje'] as num)
                            .toDouble();

                    final kmAnterior =
                        (recientes[1].data()['kilometraje'] as num)
                            .toDouble();

                    final litrosAnterior =
                        ((recientes[1].data()['litros_equivalentes']
                                    as num?)
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
                    leading: const Icon(
                      Icons.directions_car,
                      color: azul,
                    ),
                    title: Text(
                      placa,
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                      ),
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
                          title: Text(
                            'Rendimiento aún no disponible',
                          ),
                          subtitle: Text(
                            'Se necesitan cargas consecutivas con '
                            'kilometrajes crecientes para estimarlo.',
                          ),
                        ),
                      const Divider(height: 1),
                      ...docsVehiculo.map((doc) {
                        final d = doc.data();

                        final fecha = _fechaHora(d['fecha']);

                        final km =
                            (d['kilometraje'] as num?)
                                    ?.toStringAsFixed(0) ??
                                'No indicado';

                        final litros =
                            ((d['litros_equivalentes'] as num?)
                                    ?.toDouble() ??
                                (d['litros'] as num?)?.toDouble() ??
                                0);

                        final usuario =
                            (d['usuario_nombre'] ??
                                    'Usuario no identificado')
                                .toString();

                        final cantidad =
                            (d['cantidad_ingresada'] as num?)?.toDouble();

                        final unidad =
                            (d['unidad_ingresada'] ?? 'Litros').toString();

                        final nivel =
                            (d['nivel_tanque'] ?? 'No indicado').toString();

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
      body: ListView(
        children: [
          _crearFormulario(),
          _resumenMensual(),
        ],
      ),
    );
  }
}