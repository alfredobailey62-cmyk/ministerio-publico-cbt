import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:image_picker/image_picker.dart';
import 'dart:typed_data';

class VehiculosPage extends StatefulWidget {
  const VehiculosPage({super.key});

  @override
  State<VehiculosPage> createState() => _VehiculosPageState();
}

class _VehiculosPageState extends State<VehiculosPage> {
  final _placaController = TextEditingController();
  final _marcaController = TextEditingController();
  final _modeloController = TextEditingController();
  final _colorController = TextEditingController();
  final _kmController = TextEditingController();
  final _kmMantenimientoController = TextEditingController();
  Uint8List? _imagenBytes;

  Future<String?> _subirImagen(String placa) async {
    if (_imagenBytes == null) return null;
    final ref = FirebaseStorage.instance.ref().child('vehiculos/$placa.jpg');
    await ref.putData(_imagenBytes!);
    return await ref.getDownloadURL();
  }

  void _mostrarFormulario() {
    showDialog(
      context: context,
      builder: (_) => StatefulBuilder(
        builder: (context, setStateDialog) => AlertDialog(
          title: const Text('Agregar Vehículo'),
          content: SingleChildScrollView(
            child: Column(
              children: [
                TextField(
                  controller: _placaController,
                  decoration: const InputDecoration(labelText: 'Placa'),
                ),
                TextField(
                  controller: _marcaController,
                  decoration: const InputDecoration(labelText: 'Marca'),
                ),
                TextField(
                  controller: _modeloController,
                  decoration: const InputDecoration(labelText: 'Modelo'),
                ),
                TextField(
                  controller: _colorController,
                  decoration: const InputDecoration(labelText: 'Color'),
                ),
                TextField(
                  controller: _kmController,
                  decoration: const InputDecoration(labelText: 'Kilometraje actual'),
                  keyboardType: TextInputType.number,
                ),
                TextField(
                  controller: _kmMantenimientoController,
                  decoration: const InputDecoration(
                      labelText: 'Km próximo mantenimiento'),
                  keyboardType: TextInputType.number,
                ),
                const SizedBox(height: 12),
                _imagenBytes != null
                    ? Image.memory(_imagenBytes!, height: 100, fit: BoxFit.cover)
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
                        source: ImageSource.gallery);
                    if (imagen != null) {
                      final bytes = await imagen.readAsBytes();
                      setStateDialog(() {
                        _imagenBytes = bytes;
                      });
                    }
                  },
                  icon: const Icon(Icons.photo),
                  label: const Text('Seleccionar foto'),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () {
                _imagenBytes = null;
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
                final placa = _placaController.text.trim().toUpperCase();
                final fotoUrl = await _subirImagen(placa);
                await FirebaseFirestore.instance.collection('vehiculos').add({
                  'placa': placa,
                  'marca': _marcaController.text.trim(),
                  'modelo': _modeloController.text.trim(),
                  'color': _colorController.text.trim(),
                  'kilometraje': int.tryParse(_kmController.text) ?? 0,
                  'km_mantenimiento':
                      int.tryParse(_kmMantenimientoController.text) ?? 0,
                  'litros_usados': 0,
                  'foto_url': fotoUrl ?? '',
                  'fecha_registro': DateTime.now(),
                });
                _placaController.clear();
                _marcaController.clear();
                _modeloController.clear();
                _colorController.clear();
                _kmController.clear();
                _kmMantenimientoController.clear();
                _imagenBytes = null;
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
          'Vehículos',
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
              final kmActual = v['kilometraje'] ?? 0;
              final kmMant = v['km_mantenimiento'] ?? 0;
              final kmRestante = kmMant - kmActual;
              return Card(
                margin: const EdgeInsets.only(bottom: 12),
                child: ListTile(
                  leading: v['foto_url'] != null && v['foto_url'] != ''
                      ? ClipRRect(
                          borderRadius: BorderRadius.circular(8),
                          child: Image.network(
                            v['foto_url'],
                            width: 60,
                            height: 60,
                            fit: BoxFit.cover,
                          ),
                        )
                      : const Icon(
                          Icons.directions_car,
                          color: Color(0xFF003580),
                          size: 40,
                        ),
                  title: Text(
                    '${v['placa']} - ${v['marca']} ${v['modelo']}',
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  subtitle: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Color: ${v['color']}'),
                      Text('Kilometraje: ${v['kilometraje']} km'),
                      Text(
                        'Próximo mantenimiento en: $kmRestante km',
                        style: TextStyle(
                          color: kmRestante < 500 ? Colors.red : Colors.green,
                          fontWeight: FontWeight.bold,
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