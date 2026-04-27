import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:image_picker/image_picker.dart';
import 'dart:typed_data';

class CombustiblePage extends StatefulWidget {
  const CombustiblePage({super.key});

  @override
  State<CombustiblePage> createState() => _CombustiblePageState();
}

class _CombustiblePageState extends State<CombustiblePage> {
  final _litrosController = TextEditingController();
  String? _vehiculoSeleccionado;
  String? _placaSeleccionada;
  Uint8List? _imagenBytes;

  Future<String?> _subirBaucher(String placa) async {
    if (_imagenBytes == null) return null;
    final ref = FirebaseStorage.instance
        .ref()
        .child('bauchers/$placa-${DateTime.now().millisecondsSinceEpoch}.jpg');
    await ref.putData(_imagenBytes!);
    return await ref.getDownloadURL();
  }

  void _mostrarFormulario() {
    showDialog(
      context: context,
      builder: (_) => StatefulBuilder(
        builder: (context, setStateDialog) => AlertDialog(
          title: const Text('Registrar Combustible'),
          content: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Seleccionar vehículo:',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                StreamBuilder<QuerySnapshot>(
                  stream: FirebaseFirestore.instance
                      .collection('vehiculos')
                      .snapshots(),
                  builder: (context, snapshot) {
                    if (!snapshot.hasData) {
                      return const CircularProgressIndicator();
                    }
                    final vehiculos = snapshot.data!.docs;
                    return DropdownButton<String>(
                      isExpanded: true,
                      hint: const Text('Seleccione un vehículo'),
                      value: _vehiculoSeleccionado,
                      items: vehiculos.map((v) {
                        final data = v.data() as Map<String, dynamic>;
                        return DropdownMenuItem<String>(
                          value: v.id,
                          child: Text(
                            '${data['placa']} - ${data['marca']} ${data['modelo']}',
                          ),
                        );
                      }).toList(),
                      onChanged: (val) {
                        final v = vehiculos.firstWhere((e) => e.id == val);
                        final data = v.data() as Map<String, dynamic>;
                        setStateDialog(() {
                          _vehiculoSeleccionado = val;
                          _placaSeleccionada = data['placa'];
                        });
                      },
                    );
                  },
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _litrosController,
                  decoration: const InputDecoration(
                    labelText: 'Litros cargados',
                    suffixText: 'L',
                  ),
                  keyboardType: TextInputType.number,
                ),
                const SizedBox(height: 12),
                const Text(
                  'Foto del baucher:',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                _imagenBytes != null
                    ? Image.memory(
                        _imagenBytes!,
                        height: 100,
                        fit: BoxFit.cover,
                      )
                    : const Text('No hay foto seleccionada'),
                const SizedBox(height: 8),
                ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF003580),
                    foregroundColor: Colors.white,
                  ),
                  onPressed: () async {
                    final picker = ImagePicker();
                    final imagen = await picker.pickImage(
                      source: ImageSource.gallery,
                    );
                    if (imagen != null) {
                      final bytes = await imagen.readAsBytes();
                      setStateDialog(() {
                        _imagenBytes = bytes;
                      });
                    }
                  },
                  icon: const Icon(Icons.photo),
                  label: const Text('Seleccionar baucher'),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () {
                _imagenBytes = null;
                _vehiculoSeleccionado = null;
                _placaSeleccionada = null;
                _litrosController.clear();
                Navigator.pop(context);
              },
              child: const Text('Cancelar'),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF003580),
                foregroundColor: Colors.white,
              ),
              onPressed: () async {
                if (_vehiculoSeleccionado == null) return;
                final litros = int.tryParse(_litrosController.text) ?? 0;
                final baucherUrl = await _subirBaucher(_placaSeleccionada ?? '');
                await FirebaseFirestore.instance
                    .collection('combustible')
                    .add({
                  'vehiculo_id': _vehiculoSeleccionado,
                  'placa': _placaSeleccionada,
                  'litros': litros,
                  'baucher_url': baucherUrl ?? '',
                  'fecha': DateTime.now(),
                  'mes': DateTime.now().month,
                  'anio': DateTime.now().year,
                });
                await FirebaseFirestore.instance
                    .collection('vehiculos')
                    .doc(_vehiculoSeleccionado)
                    .update({
                  'litros_usados': FieldValue.increment(litros),
                });
                _litrosController.clear();
                _imagenBytes = null;
                _vehiculoSeleccionado = null;
                _placaSeleccionada = null;
                if (context.mounted) Navigator.pop(context);
              },
              child: const Text('Guardar'),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: const Color(0xFF003580),
        title: const Text(
          'Control de Combustible',
          style: TextStyle(color: Colors.white),
        ),
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      floatingActionButton: FloatingActionButton(
        backgroundColor: const Color(0xFF003580),
        onPressed: _mostrarFormulario,
        child: const Icon(Icons.add, color: Colors.white),
      ),
      body: StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance.collection('vehiculos').snapshots(),
        builder: (context, snapshot) {
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final vehiculos = snapshot.data!.docs;
          if (vehiculos.isEmpty) {
            return const Center(
              child: Text('No hay vehículos registrados'),
            );
          }
          return ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: vehiculos.length,
            itemBuilder: (context, index) {
              final v = vehiculos[index].data() as Map<String, dynamic>;
              final litrosUsados = (v['litros_usados'] ?? 0).toDouble();
              final limiteMensual = (v['limite_litros'] ?? 300).toDouble();
              final litrosRestantes = limiteMensual - litrosUsados;
              final porcentaje = (litrosUsados / limiteMensual).clamp(0.0, 1.0);
              return Card(
                margin: const EdgeInsets.only(bottom: 12),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Icon(Icons.directions_car,
                              color: Color(0xFF003580)),
                          const SizedBox(width: 8),
                          Text(
                            '${v['placa']} - ${v['marca']} ${v['modelo']}',
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 16,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text('Usados: ${litrosUsados.toStringAsFixed(0)} L'),
                          Text(
                            'Restantes: ${litrosRestantes.toStringAsFixed(0)} L',
                            style: TextStyle(
                              color: litrosRestantes < 50
                                  ? Colors.red
                                  : Colors.green,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      LinearProgressIndicator(
                        value: porcentaje,
                        backgroundColor: Colors.grey[300],
                        color: porcentaje > 0.8
                            ? Colors.red
                            : const Color(0xFF003580),
                        minHeight: 10,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '${(porcentaje * 100).toStringAsFixed(0)}% del límite mensual (${limiteMensual.toStringAsFixed(0)} L)',
                        style: const TextStyle(
                          fontSize: 12,
                          color: Colors.grey,
                        ),
                      ),
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
}