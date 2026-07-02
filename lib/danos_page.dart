import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:image_picker/image_picker.dart';

class DanosPage extends StatefulWidget {
  const DanosPage({super.key});

  @override
  State<DanosPage> createState() => _DanosPageState();
}

class _DanosPageState extends State<DanosPage> {
  final TextEditingController _descripcionController = TextEditingController();

  String? _vehiculoSeleccionado;
  String? _placaSeleccionada;

  Uint8List? _imagenBytes;

  String _gravedad = 'Leve';

  final List<String> _gravedades = ['Leve', 'Moderado', 'Grave'];

  // 🔥 SUBIR IMAGEN (CORREGIDO Y DEBUG)
  Future<String?> _subirFoto(String placa) async {
    try {
      if (_imagenBytes == null) {
        debugPrint("❌ No hay imagen");
        return null;
      }

      if (placa.isEmpty) {
        debugPrint("❌ Placa vacía");
        return null;
      }

      final ref = FirebaseStorage.instance.ref().child(
        'danos/$placa/${DateTime.now().millisecondsSinceEpoch}.jpg',
      );

      debugPrint("⬆️ Subiendo imagen...");

      final uploadTask = await ref.putData(_imagenBytes!);

      if (uploadTask.state != TaskState.success) {
        debugPrint("❌ Falló la subida");
        return null;
      }

      final url = await ref.getDownloadURL();

      debugPrint("✅ Imagen subida: $url");

      return url;
    } catch (e) {
      debugPrint("🔥 ERROR SUBIENDO IMAGEN: $e");
      return null;
    }
  }

  // 🔥 SELECCIONAR IMAGEN
  Future<void> _seleccionarImagen() async {
    try {
      final picker = ImagePicker();

      final XFile? imagen = await picker.pickImage(
        source: ImageSource.gallery,
        imageQuality: 70,
      );

      if (imagen == null) return;

      final bytes = await imagen.readAsBytes();

      setState(() {
        _imagenBytes = bytes;
      });

      debugPrint("📸 Imagen seleccionada");
    } catch (e) {
      debugPrint("❌ Error imagen: $e");
    }
  }

  // 🔥 MOSTRAR FORMULARIO
  void _mostrarFormulario() {
    _descripcionController.clear();
    _vehiculoSeleccionado = null;
    _placaSeleccionada = null;
    _imagenBytes = null;
    _gravedad = 'Leve';

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) {
        return StatefulBuilder(
          builder: (context, setStateDialog) {
            return AlertDialog(
              title: const Text('Registrar Daño'),

              content: SizedBox(
                width: 450,
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Vehículo',
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

                          return DropdownButtonFormField<String>(
                            value: _vehiculoSeleccionado,
                            decoration: const InputDecoration(
                              border: OutlineInputBorder(),
                            ),
                            items: vehiculos.map((v) {
                              final data = v.data() as Map<String, dynamic>;

                              return DropdownMenuItem(
                                value: v.id,
                                child: Text(
                                  '${data['placa']} - ${data['marca']} ${data['modelo']}',
                                ),
                              );
                            }).toList(),
                            onChanged: (val) {
                              final vehiculo = vehiculos.firstWhere(
                                (e) => e.id == val,
                              );

                              final data =
                                  vehiculo.data() as Map<String, dynamic>;

                              setStateDialog(() {
                                _vehiculoSeleccionado = val;
                                _placaSeleccionada = data['placa'];
                              });
                            },
                          );
                        },
                      ),

                      const SizedBox(height: 16),

                      const Text(
                        'Gravedad',
                        style: TextStyle(fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 8),

                      DropdownButtonFormField<String>(
                        value: _gravedad,
                        items: _gravedades
                            .map(
                              (g) => DropdownMenuItem(value: g, child: Text(g)),
                            )
                            .toList(),
                        onChanged: (val) {
                          setStateDialog(() {
                            _gravedad = val!;
                          });
                        },
                      ),

                      const SizedBox(height: 16),

                      TextField(
                        controller: _descripcionController,
                        maxLines: 3,
                        decoration: const InputDecoration(
                          labelText: 'Descripción del daño',
                          border: OutlineInputBorder(),
                        ),
                      ),

                      const SizedBox(height: 16),

                      const Text(
                        'Foto del daño',
                        style: TextStyle(fontWeight: FontWeight.bold),
                      ),

                      const SizedBox(height: 10),

                      _imagenBytes != null
                          ? Image.memory(
                              _imagenBytes!,
                              height: 180,
                              width: double.infinity,
                              fit: BoxFit.cover,
                            )
                          : Container(
                              height: 180,
                              color: Colors.grey[200],
                              child: const Center(
                                child: Icon(Icons.photo, size: 60),
                              ),
                            ),

                      const SizedBox(height: 12),

                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton.icon(
                          onPressed: _seleccionarImagen,
                          icon: const Icon(Icons.photo_library),
                          label: const Text('Seleccionar imagen'),
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
                    try {
                      if (_vehiculoSeleccionado == null ||
                          _descripcionController.text.isEmpty) {
                        debugPrint("❌ Campos incompletos");
                        return;
                      }

                      debugPrint("🚀 Guardando...");

                      String? fotoUrl;

                      if (_imagenBytes != null) {
                        fotoUrl = await _subirFoto(_placaSeleccionada ?? '');
                      }

                      // 🔥 GUARDAR DAÑO
                      final danoRef = await FirebaseFirestore.instance
                          .collection('danos')
                          .add({
                            'vehiculo_id': _vehiculoSeleccionado,
                            'placa': _placaSeleccionada ?? '',
                            'descripcion': _descripcionController.text.trim(),
                            'gravedad': _gravedad,
                            'foto_url': fotoUrl ?? '',
                            'fecha': Timestamp.now(),
                          });

                      // 🔥 CREAR NOTIFICACIÓN PARA EL ADMIN
                      await FirebaseFirestore.instance
                          .collection('notificaciones')
                          .add({
                            'titulo': 'Nuevo daño reportado',
                            'mensaje':
                                'Vehículo ${_placaSeleccionada ?? ''} reportó un daño $_gravedad',
                            'descripcion': _descripcionController.text.trim(),
                            'placa': _placaSeleccionada ?? '',
                            'gravedad': _gravedad,
                            'foto_url': fotoUrl ?? '',
                            'dano_id': danoRef.id,
                            'leida': false,
                            'fecha': Timestamp.now(),
                            'tipo': 'dano',
                          });

                      debugPrint("✅ Guardado exitoso");

                      if (mounted) {
                        Navigator.pop(context);

                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('Daño registrado'),
                            backgroundColor: Colors.green,
                          ),
                        );
                      }
                    } catch (e) {
                      debugPrint("🔥 ERROR: $e");
                    }
                  },
                  child: const Text('Guardar'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  // 🔥 COLOR
  Color _colorGravedad(String g) {
    switch (g) {
      case 'Grave':
        return Colors.red;
      case 'Moderado':
        return Colors.orange;
      default:
        return Colors.green;
    }
  }

  // 🔥 UI PRINCIPAL
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Registro de Daños'),
        backgroundColor: const Color(0xFF002B6E),
      ),

      floatingActionButton: FloatingActionButton(
        onPressed: _mostrarFormulario,
        child: const Icon(Icons.add),
      ),

      body: StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance
            .collection('danos')
            .orderBy('fecha', descending: true)
            .snapshots(),
        builder: (context, snapshot) {
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }

          final docs = snapshot.data!.docs;

          if (docs.isEmpty) {
            return const Center(child: Text("No hay registros"));
          }

          return ListView.builder(
            itemCount: docs.length,
            itemBuilder: (context, i) {
              final data = docs[i].data() as Map<String, dynamic>;

              return Card(
                child: ListTile(
                  leading: (data['foto_url'] ?? '').isNotEmpty
                      ? Image.network(
                          data['foto_url'],
                          width: 60,
                          height: 60,
                          fit: BoxFit.cover,
                        )
                      : const Icon(Icons.photo),

                  title: Text(data['placa'] ?? ''),
                  subtitle: Text(data['descripcion'] ?? ''),

                  trailing: Chip(
                    label: Text(data['gravedad'] ?? ''),
                    backgroundColor: _colorGravedad(data['gravedad'] ?? 'Leve'),
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
