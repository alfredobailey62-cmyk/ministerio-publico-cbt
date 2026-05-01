import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:image_picker/image_picker.dart';
import 'package:ministerio_publico_cbt/usuario_provider.dart';
import 'dart:io';
import 'dart:typed_data';
import 'package:provider/provider.dart';
import 'usuario_provider.dart';

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
  File? _imagenFile;
  bool _subiendoImagen = false;
  String? _errorMensaje;

  // ✅ Función mejorada para subir imagen
  Future<String?> _subirImagen(String placa) async {
    if (_imagenBytes == null && _imagenFile == null) return null;

    setState(() => _subiendoImagen = true);

    try {
      // Crear nombre único para evitar caché
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final ref = FirebaseStorage.instance.ref().child(
        'vehiculos/$placa/$timestamp.jpg',
      );

      // Subir según el tipo de imagen
      if (_imagenBytes != null) {
        await ref.putData(_imagenBytes!);
      } else if (_imagenFile != null) {
        await ref.putFile(_imagenFile!);
      }

      final url = await ref.getDownloadURL();
      print(' Imagen subida: $url');
      return url;
    } catch (e) {
      print(' Error al subir imagen: $e');
      _mostrarSnackbar('Error al subir imagen: $e');
      return null;
    } finally {
      setState(() => _subiendoImagen = false);
    }
  }

  // ✅ Función para seleccionar imagen (múltiples fuentes)
  Future<void> _seleccionarImagen(StateSetter setStateDialog) async {
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
                    _imagenBytes = bytes;
                    _imagenFile = File(imagen.path);
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
                    _imagenBytes = bytes;
                    _imagenFile = File(imagen.path);
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
                  _imagenBytes = null;
                  _imagenFile = null;
                });
              },
            ),
          ],
        ),
      ),
    );
  }

  // ✅ Validar formulario
  bool _validarFormulario() {
    if (_placaController.text.trim().isEmpty) {
      _mostrarSnackbar('Ingrese la placa del vehículo');
      return false;
    }
    if (_marcaController.text.trim().isEmpty) {
      _mostrarSnackbar('Ingrese la marca del vehículo');
      return false;
    }
    if (_modeloController.text.trim().isEmpty) {
      _mostrarSnackbar('Ingrese el modelo del vehículo');
      return false;
    }
    if (_kmController.text.trim().isEmpty) {
      _mostrarSnackbar('Ingrese el kilometraje actual');
      return false;
    }
    return true;
  }

  // ✅ Mostrar snackbar
  void _mostrarSnackbar(String mensaje) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(mensaje)));
  }

  // ✅ Formulario mejorado
  void _mostrarFormulario({Map<String, dynamic>? vehiculo, String? docId}) {
    // Si es edición, cargar datos
    if (vehiculo != null) {
      _placaController.text = vehiculo['placa'] ?? '';
      _marcaController.text = vehiculo['marca'] ?? '';
      _modeloController.text = vehiculo['modelo'] ?? '';
      _colorController.text = vehiculo['color'] ?? '';
      _kmController.text = (vehiculo['kilometraje'] ?? 0).toString();
      _kmMantenimientoController.text = (vehiculo['km_mantenimiento'] ?? 0)
          .toString();
    } else {
      _limpiarFormulario();
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
                  child: _imagenBytes != null
                      ? ClipRRect(
                          borderRadius: BorderRadius.circular(8),
                          child: Image.memory(
                            _imagenBytes!,
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
                  onPressed: () => _seleccionarImagen(setStateDialog),
                  icon: const Icon(Icons.photo),
                  label: const Text('Seleccionar foto'),
                ),

                const Divider(height: 24),

                // Campos del formulario
                TextField(
                  controller: _placaController,
                  decoration: const InputDecoration(
                    labelText: 'Placa *',
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.badge),
                  ),
                  textCapitalization: TextCapitalization.characters,
                ),
                const SizedBox(height: 12),

                TextField(
                  controller: _marcaController,
                  decoration: const InputDecoration(
                    labelText: 'Marca *',
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.directions_car_filled),
                  ),
                ),
                const SizedBox(height: 12),

                TextField(
                  controller: _modeloController,
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
                  controller: _kmController,
                  decoration: const InputDecoration(
                    labelText: 'Kilometraje actual *',
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.speed),
                  ),
                  keyboardType: TextInputType.number,
                ),
                const SizedBox(height: 12),

                TextField(
                  controller: _kmMantenimientoController,
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
                _limpiarFormulario();
                Navigator.pop(context);
              },
              child: const Text('Cancelar'),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF003580),
                foregroundColor: Colors.white,
              ),
              onPressed: _subiendoImagen
                  ? null
                  : () async {
                      if (!_validarFormulario()) return;

                      setStateDialog(() => _subiendoImagen = true);

                      try {
                        final placa = _placaController.text
                            .trim()
                            .toUpperCase();

                        String? fotoUrl;
                        if (_imagenBytes != null || _imagenFile != null) {
                          fotoUrl = await _subirImagen(placa);
                        } else if (vehiculo != null &&
                            vehiculo['foto_url'] != null) {
                          fotoUrl =
                              vehiculo['foto_url']; // Mantener foto existente
                        }

                        final data = {
                          'placa': placa,
                          'marca': _marcaController.text.trim(),
                          'modelo': _modeloController.text.trim(),
                          'color': _colorController.text.trim(),
                          'kilometraje': int.tryParse(_kmController.text) ?? 0,
                          'km_mantenimiento':
                              int.tryParse(_kmMantenimientoController.text) ??
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
                          _mostrarSnackbar('Vehículo actualizado');
                        } else {
                          // Nuevo vehículo
                          data['fecha_registro'] = DateTime.now();
                          data['litros_usados'] = 0;
                          await FirebaseFirestore.instance
                              .collection('vehiculos')
                              .add(data);
                          _mostrarSnackbar('Vehículo agregado');
                        }

                        _limpiarFormulario();
                        if (context.mounted) Navigator.pop(context);
                      } catch (e) {
                        _mostrarSnackbar('Error: $e');
                      } finally {
                        setStateDialog(() => _subiendoImagen = false);
                      }
                    },
              child: _subiendoImagen
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
        _mostrarSnackbar('Vehículo eliminado');
      } catch (e) {
        _mostrarSnackbar('Error al eliminar: $e');
      }
    }
  }

  void _limpiarFormulario() {
    _placaController.clear();
    _marcaController.clear();
    _modeloController.clear();
    _colorController.clear();
    _kmController.clear();
    _kmMantenimientoController.clear();
    _imagenBytes = null;
    _imagenFile = null;
    _errorMensaje = null;
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



    final usuarioProvider = Provider.of<UsuarioProvider>(context);


    return Scaffold(
      appBar: AppBar(
        backgroundColor: const Color(0xFF003580),
        title: Text(
          'Vehículos /${usuarioProvider.email} es admin? ${usuarioProvider.isAdmin}',
          style: TextStyle(color: Colors.white),
        ),
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      floatingActionButton: FloatingActionButton(
        backgroundColor: const Color(0xFF003580),
        onPressed: () => _mostrarFormulario(),
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
                    _mostrarFormulario(vehiculo: v, docId: doc.id);
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
    _placaController.dispose();
    _marcaController.dispose();
    _modeloController.dispose();
    _colorController.dispose();
    _kmController.dispose();
    _kmMantenimientoController.dispose();
    super.dispose();
  }
}
