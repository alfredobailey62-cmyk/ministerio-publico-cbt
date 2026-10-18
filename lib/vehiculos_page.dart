import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:image_picker/image_picker.dart';
import 'package:control_flota_vehicular/usuario_provider.dart';
import 'dart:io';
import 'dart:typed_data';
import 'package:provider/provider.dart';

class VehiclesPage extends StatefulWidget {
  const VehiclesPage({super.key});

  @override
  State<VehiclesPage> createState() => _VehiclesPageState();
}

class _VehiclesPageState extends State<VehiclesPage> {
  final _plateController = TextEditingController();
  final _brandController = TextEditingController();
  final _modelController = TextEditingController();
  final _colorController = TextEditingController();
  final _mileageController = TextEditingController();
  final _maintenanceMileageController = TextEditingController();

  Uint8List? _imageBytes;
  File? _imageFile;
  bool _uploadingImage = false;
  String? _errorMessage;

  // ✅ Función mejorada para subir imagen
  Future<String?> _uploadImage(String placa) async {
    if (_imageBytes == null && _imageFile == null) return null;

    setState(() => _uploadingImage = true);

    try {
      // Crear nombre único para evitar caché
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final ref = FirebaseStorage.instance.ref().child(
        'vehiculos/$placa/$timestamp.jpg',
      );

      // Subir según el tipo de imagen
      if (_imageBytes != null) {
        await ref.putData(_imageBytes!);
      } else if (_imageFile != null) {
        await ref.putFile(_imageFile!);
      }

      final url = await ref.getDownloadURL();
      print(' Imagen subida: $url');
      return url;
    } catch (e) {
      print(' Error al subir imagen: $e');
      _showSnackbar('Error al subir imagen: $e');
      return null;
    } finally {
      setState(() => _uploadingImage = false);
    }
  }

  // ✅ Función para seleccionar imagen (múltiples fuentes)
  Future<void> _pickImage(StateSetter setStateDialog) async {
    showModalBottomSheet(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.photo_library),
              title: Text('Galería'),
              onTap: () async {
                Navigator.pop(context);
                final picker = ImagePicker();
                final imagen = await picker.pickImage(
                  source: ImageSource.gallery,
                  imageQuality: 80, // Comprimir imagen
                );
                if (imagen != null) {
                  final bytes = await imagen.readAsBytes();
                  setStateDialog(() {
                    _imageBytes = bytes;
                    _imageFile = File(imagen.path);
                  });
                }
              },
            ),
            ListTile(
              leading: const Icon(Icons.camera_alt),
              title: const Text('Cámara'),
              onTap: () async {
                Navigator.pop(context);
                final picker = ImagePicker();
                final imagen = await picker.pickImage(
                  source: ImageSource.camera,
                  imageQuality: 80,
                );
                if (imagen != null) {
                  final bytes = await imagen.readAsBytes();
                  setStateDialog(() {
                    _imageBytes = bytes;
                    _imageFile = File(imagen.path);
                  });
                }
              },
            ),
            ListTile(
              leading: const Icon(Icons.delete),
              title: const Text('Eliminar foto'),
              onTap: () {
                Navigator.pop(context);
                setStateDialog(() {
                  _imageBytes = null;
                  _imageFile = null;
                });
              },
            ),
          ],
        ),
      ),
    );
  }

  // ✅ Validar formulario
  bool _validateForm() {
    if (_plateController.text.trim().isEmpty) {
      _showSnackbar('Ingrese la placa del vehículo');
      return false;
    }
    if (_brandController.text.trim().isEmpty) {
      _showSnackbar('Ingrese la marca del vehículo');
      return false;
    }
    if (_modelController.text.trim().isEmpty) {
      _showSnackbar('Ingrese el modelo del vehículo');
      return false;
    }
    if (_mileageController.text.trim().isEmpty) {
      _showSnackbar('Ingrese el kilometraje actual');
      return false;
    }
    return true;
  }

  // ✅ Mostrar snackbar
  void _showSnackbar(String mensaje) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(mensaje)));
  }

  // ✅ Formulario mejorado
  void _showForm({Map<String, dynamic>? vehiculo, String? docId}) {
    // Si es edición, cargar datos
    if (vehiculo != null) {
      _plateController.text = vehiculo['placa'] ?? '';
      _brandController.text = vehiculo['marca'] ?? '';
      _modelController.text = vehiculo['modelo'] ?? '';
      _colorController.text = vehiculo['color'] ?? '';
      _mileageController.text = (vehiculo['kilometraje'] ?? 0).toString();
      _maintenanceMileageController.text = (vehiculo['km_mantenimiento'] ?? 0)
          .toString();
    } else {
      _clearForm();
    }

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => StatefulBuilder(
        builder: (context, setStateDialog) => AlertDialog(
          title: Text(
            vehiculo != null ? 'Editar Vehículo' : 'Agregar Vehículo',
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Vista previa de la imagen
                Container(
                  height: 120,
                  width: double.infinity,
                  decoration: BoxDecoration(
                    color: Colors.grey[200],
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: _imageBytes != null
                      ? ClipRRect(
                          borderRadius: BorderRadius.circular(8),
                          child: Image.memory(
                            _imageBytes!,
                            width: 120,
                            height: 120,
                            fit: BoxFit.cover,
                          ),
                        )
                      : vehiculo != null &&
                            vehiculo['foto_url'] != null &&
                            vehiculo['foto_url'] != ''
                      ? ClipRRect(
                          borderRadius: BorderRadius.circular(8),
                          child: Image.network(
                            vehiculo['foto_url'],
                            width: 120,
                            height: 120,
                            fit: BoxFit.cover,
                            errorBuilder: (_, __, ___) => const Icon(
                              Icons.directions_car,
                              size: 60,
                              color: Color(0xFF003580),
                            ),
                          ),
                        )
                      : Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: const [
                            Icon(
                              Icons.photo_camera,
                              size: 40,
                              color: Colors.grey,
                            ),
                            Text(
                              'Sin foto',
                              style: TextStyle(color: Colors.grey),
                            ),
                          ],
                        ),
                ),
                const SizedBox(height: 8),

                // Botones para imagen
                ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF003580),
                    foregroundColor: Colors.white,
                  ),
                  onPressed: () => _pickImage(setStateDialog),
                  icon: const Icon(Icons.photo),
                  label: const Text('Seleccionar foto'),
                ),

                const Divider(height: 24),

                // Campos del formulario
                TextField(
                  controller: _plateController,
                  decoration: const InputDecoration(
                    labelText: 'Placa *',
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.badge),
                  ),
                  textCapitalization: TextCapitalization.characters,
                ),
                const SizedBox(height: 12),

                TextField(
                  controller: _brandController,
                  decoration: const InputDecoration(
                    labelText: 'Marca *',
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.directions_car_filled),
                  ),
                ),
                const SizedBox(height: 12),

                TextField(
                  controller: _modelController,
                  decoration: const InputDecoration(
                    labelText: 'Modelo *',
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.model_training),
                  ),
                ),
                const SizedBox(height: 12),

                TextField(
                  controller: _colorController,
                  decoration: const InputDecoration(
                    labelText: 'Color',
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.color_lens),
                  ),
                ),
                const SizedBox(height: 12),

                TextField(
                  controller: _mileageController,
                  decoration: const InputDecoration(
                    labelText: 'Kilometraje actual *',
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.speed),
                  ),
                  keyboardType: TextInputType.number,
                ),
                const SizedBox(height: 12),

                TextField(
                  controller: _maintenanceMileageController,
                  decoration: const InputDecoration(
                    labelText: 'Km próximo mantenimiento',
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.build),
                  ),
                  keyboardType: TextInputType.number,
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () {
                _clearForm();
                Navigator.pop(context);
              },
              child: const Text('Cancelar'),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF003580),
                foregroundColor: Colors.white,
              ),
              onPressed: _uploadingImage
                  ? null
                  : () async {
                      if (!_validateForm()) return;

                      setStateDialog(() => _uploadingImage = true);

                      try {
                        final placa = _plateController.text
                            .trim()
                            .toUpperCase();

                        String? fotoUrl;
                        if (_imageBytes != null || _imageFile != null) {
                          fotoUrl = await _uploadImage(placa);
                        } else if (vehiculo != null &&
                            vehiculo['foto_url'] != null) {
                          fotoUrl =
                              vehiculo['foto_url']; // Mantener foto existente
                        }

                        final data = {
                          'placa': placa,
                          'marca': _brandController.text.trim(),
                          'modelo': _modelController.text.trim(),
                          'color': _colorController.text.trim(),
                          'kilometraje':
                              int.tryParse(_mileageController.text) ?? 0,
                          'km_mantenimiento':
                              int.tryParse(
                                _maintenanceMileageController.text,
                              ) ??
                              0,
                          'foto_url': fotoUrl ?? '',
                          'fecha_actualizacion': DateTime.now(),
                        };

                        if (vehiculo != null && docId != null) {
                          // Editar vehículo existente
                          await FirebaseFirestore.instance
                              .collection('vehiculos')
                              .doc(docId)
                              .update(data);
                          _showSnackbar('Vehículo actualizado');
                        } else {
                          // Nuevo vehículo
                          data['fecha_registro'] = DateTime.now();
                          data['litros_usados'] = 0;
                          await FirebaseFirestore.instance
                              .collection('vehiculos')
                              .add(data);
                          _showSnackbar('Vehículo agregado');
                        }

                        _clearForm();
                        if (context.mounted) Navigator.pop(context);
                      } catch (e) {
                        _showSnackbar('Error: $e');
                      } finally {
                        setStateDialog(() => _uploadingImage = false);
                      }
                    },
              child: _uploadingImage
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Text(vehiculo != null ? 'Actualizar' : 'Guardar'),
            ),
          ],
        ),
      ),
    );
  }

  // ✅ Función para eliminar vehículo
  Future<void> _eliminarVehiculo(
    String docId,
    String placa,
    String? fotoUrl,
  ) async {
    final confirmar = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Eliminar vehículo'),
        content: Text('¿Eliminar el vehículo $placa?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Eliminar'),
          ),
        ],
      ),
    );

    if (confirmar == true) {
      try {
        // Eliminar foto de Storage si existe
        if (fotoUrl != null && fotoUrl.isNotEmpty) {
          try {
            final ref = FirebaseStorage.instance.refFromURL(fotoUrl);
            await ref.delete();
            print(' Foto eliminada');
          } catch (e) {
            print('Error al eliminar foto: $e');
          }
        }

        // Eliminar documento de Firestore
        await FirebaseFirestore.instance
            .collection('vehiculos')
            .doc(docId)
            .delete();
        _showSnackbar('Vehículo eliminado');
      } catch (e) {
        _showSnackbar('Error al eliminar: $e');
      }
    }
  }

  void _clearForm() {
    _plateController.clear();
    _brandController.clear();
    _modelController.clear();
    _colorController.clear();
    _mileageController.clear();
    _maintenanceMileageController.clear();
    _imageBytes = null;
    _imageFile = null;
    _errorMessage = null;
  }

  // ✅ Widget para mostrar estado del mantenimiento
  Widget _buildMantenimientoStatus(int kmActual, int kmMant) {
    final kmRestante = kmMant - kmActual;
    Color color;
    String estado;

    if (kmRestante <= 0) {
      color = Colors.red;
      estado = ' MANTENIMIENTO VENCIDO';
    } else if (kmRestante <= 500) {
      color = Colors.orange;
      estado = ' Próximo mantenimiento: $kmRestante km';
    } else {
      color = Colors.green;
      estado = ' Próximo mantenimiento: $kmRestante km';
    }

    return Text(
      estado,
      style: TextStyle(color: color, fontWeight: FontWeight.bold, fontSize: 12),
    );
  }

  @override
  Widget build(BuildContext context) {
    final userProvider = Provider.of<UserProvider>(context);

    return Scaffold(
      appBar: AppBar(
        backgroundColor: const Color(0xFF003580),
        title: Text(
          'Vehículos /${userProvider.email} es admin? ${userProvider.isAdmin}',
          style: TextStyle(color: Colors.white),
        ),
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      floatingActionButton: FloatingActionButton(
        backgroundColor: const Color(0xFF003580),
        onPressed: () => _showForm(),
        child: const Icon(Icons.add, color: Colors.white),
      ),
      body: StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance
            .collection('vehiculos')
            .orderBy('placa')
            .snapshots(),
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return Center(child: Text('Error: ${snapshot.error}'));
          }

          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }

          final vehiculos = snapshot.data!.docs;

          if (vehiculos.isEmpty) {
            return const Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.directions_car, size: 80, color: Colors.grey),
                  SizedBox(height: 16),
                  Text(
                    'No hay vehículos registrados',
                    style: TextStyle(fontSize: 16, color: Colors.grey),
                  ),
                  SizedBox(height: 8),
                  Text(
                    'Presiona el botón + para agregar',
                    style: TextStyle(fontSize: 14, color: Colors.grey),
                  ),
                ],
              ),
            );
          }

          return ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: vehiculos.length,
            itemBuilder: (context, index) {
              final doc = vehiculos[index];
              final v = doc.data() as Map<String, dynamic>;
              final kmActual = v['kilometraje'] ?? 0;
              final kmMant = v['km_mantenimiento'] ?? 0;

              return Card(
                margin: const EdgeInsets.only(bottom: 12),
                elevation: 2,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                child: InkWell(
                  onTap: () {
                    // Ver detalles (puedes mostrar más info)
                    _showForm(vehiculo: v, docId: doc.id);
                  },
                  borderRadius: BorderRadius.circular(12),
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Row(
                      children: [
                        // Foto del vehículo
                        ClipRRect(
                          borderRadius: BorderRadius.circular(8),
                          child: Container(
                            width: 70,
                            height: 70,
                            color: Colors.grey[200],
                            child: v['foto_url'] != null && v['foto_url'] != ''
                                ? Image.network(
                                    v['foto_url'],
                                    width: 70,
                                    height: 70,
                                    fit: BoxFit.cover,
                                    errorBuilder: (_, __, ___) => const Icon(
                                      Icons.directions_car,
                                      size: 40,
                                      color: Color(0xFF003580),
                                    ),
                                  )
                                : const Icon(
                                    Icons.directions_car,
                                    size: 40,
                                    color: Color(0xFF003580),
                                  ),
                          ),
                        ),
                        const SizedBox(width: 12),

                        // Información
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                '${v['placa']} - ${v['marca']} ${v['modelo']}',
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 16,
                                ),
                              ),
                              const SizedBox(height: 4),
                              if (v['color'] != null && v['color'].isNotEmpty)
                                Text(
                                  ' ${v['color']}',
                                  style: const TextStyle(fontSize: 12),
                                ),
                              Text(
                                '$kmActual km',
                                style: const TextStyle(fontSize: 12),
                              ),
                              const SizedBox(height: 4),
                              _buildMantenimientoStatus(kmActual, kmMant),
                            ],
                          ),
                        ),

                        // Botón de eliminar
                        IconButton(
                          icon: const Icon(
                            Icons.delete_outline,
                            color: Colors.red,
                          ),
                          onPressed: () => _eliminarVehiculo(
                            doc.id,
                            v['placa'],
                            v['foto_url'],
                          ),
                        ),
                      ],
                    ),
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
    _plateController.dispose();
    _brandController.dispose();
    _modelController.dispose();
    _colorController.dispose();
    _mileageController.dispose();
    _maintenanceMileageController.dispose();
    super.dispose();
  }
}
