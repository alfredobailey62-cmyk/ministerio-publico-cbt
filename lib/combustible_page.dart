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
  String? _errorMensaje; // Para mostrar errores al usuario

  Future<String?> _subirBaucher(String placa) async {
    if (_imagenBytes == null) return null;
    final ref = FirebaseStorage.instance
        .ref()
        .child('bauchers/$placa-${DateTime.now().millisecondsSinceEpoch}.jpg');
    await ref.putData(_imagenBytes!);
    return await ref.getDownloadURL();
  }

  void _mostrarFormulario() {
    // Limpiar error al abrir
    _errorMensaje = null;
    _litrosController.clear();
    
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
                          _errorMensaje = null;
                        });
                      },
                    );
                  },
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _litrosController,
                  decoration: InputDecoration(
                    labelText: 'Litros cargados',
                    suffixText: 'L',
                    errorText: _errorMensaje,
                    hintText: 'Ejemplo: 60.427',
                  ),
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
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
                        _errorMensaje = null;
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
                _errorMensaje = null;
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
                // VALIDACIÓN: Vehículo seleccionado
                if (_vehiculoSeleccionado == null) {
                  setStateDialog(() {
                    _errorMensaje = 'Seleccione un vehículo';
                  });
                  return;
                }
                
                // 🔧 CORRECCIÓN PRINCIPAL: Leer números reales (con decimales)
                final litrosTexto = _litrosController.text.trim();
                if (litrosTexto.isEmpty) {
                  setStateDialog(() {
                    _errorMensaje = 'Ingrese la cantidad de litros';
                  });
                  return;
                }
                
                // Reemplazar coma por punto (por si usan 60,427 en lugar de 60.427)
                final litrosTextoNormalizado = litrosTexto.replaceAll(',', '.');
                final litros = double.tryParse(litrosTextoNormalizado);
                
                if (litros == null) {
                  setStateDialog(() {
                    _errorMensaje = 'Ingrese un número válido (ejemplo: 60.427)';
                  });
                  return;
                }
                
                if (litros <= 0) {
                  setStateDialog(() {
                    _errorMensaje = 'Los litros deben ser mayores a 0';
                  });
                  return;
                }
                
                // Validación de foto (opcional, pero recomendado)
                if (_imagenBytes == null) {
                  setStateDialog(() {
                    _errorMensaje = 'Seleccione la foto del baucher';
                  });
                  return;
                }
                
                // Cerrar el diálogo antes de procesar
                Navigator.pop(context);
                
                // Procesar el registro
                final baucherUrl = await _subirBaucher(_placaSeleccionada ?? '');
                await FirebaseFirestore.instance
                    .collection('combustible')
                    .add({
                  'vehiculo_id': _vehiculoSeleccionado,
                  'placa': _placaSeleccionada,
                  'litros': litros, // 🔧 Ahora es double, no int
                  'baucher_url': baucherUrl ?? '',
                  'fecha': DateTime.now(),
                  'mes': DateTime.now().month,
                  'anio': DateTime.now().year,
                });
                
                await FirebaseFirestore.instance
                    .collection('vehiculos')
                    .doc(_vehiculoSeleccionado)
                    .update({
                  'litros_usados': FieldValue.increment(litros), // 🔧 Incrementa double
                });
                
                // Limpiar campos
                _litrosController.clear();
                _imagenBytes = null;
                _vehiculoSeleccionado = null;
                _placaSeleccionada = null;
                _errorMensaje = null;
                
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('✅ Registrado: ${litros.toStringAsFixed(3)} litros'),
                      backgroundColor: Colors.green,
                    ),
                  );
                }
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
              // 🔧 Asegurar que litros_usados sea double
              final litrosUsados = (v['litros_usados'] ?? 0.0).toDouble();
              final limiteMensual = (v['limite_litros'] ?? 300.0).toDouble();
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
                          Text('Usados: ${litrosUsados.toStringAsFixed(3)} L'),
                          Text(
                            'Restantes: ${litrosRestantes.toStringAsFixed(3)} L',
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
                        '${(porcentaje * 100).toStringAsFixed(1)}% del límite mensual (${limiteMensual.toStringAsFixed(0)} L)',
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