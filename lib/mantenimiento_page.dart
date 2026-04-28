import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:image_picker/image_picker.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:firebase_auth/firebase_auth.dart';

class MantenimientoPage extends StatefulWidget {
  const MantenimientoPage({super.key});

  @override
  State<MantenimientoPage> createState() => _MantenimientoPageState();
}

class _MantenimientoPageState extends State<MantenimientoPage> {

  final _descripcionController = TextEditingController();
  final _costoController = TextEditingController();
  final _kmController = TextEditingController();
  final _responsableController = TextEditingController();

  String? _vehiculoSeleccionado;
  String? _placaSeleccionada;
  String? _marcaModelo;

  String _tipoTrabajo = 'Cambio de aceite';
  String _tipoEjecucion = 'Taller externo';

  final picker = ImagePicker();

  XFile? _fotoKm;
  List<XFile> _fotosTrabajo = [];
  List<XFile> _fotosPiezas = [];

  final List<String> tiposTrabajo = [
    'Cambio de aceite',
    'Revisión general',
    'Otro'
  ];

  final List<String> tipoEjecucion = [
    'Taller externo',
    'Mecánicos institucionales'
  ];

  // ================== IMÁGENES ==================

  Future<XFile?> _seleccionarImagen() async {
    return await picker.pickImage(source: ImageSource.camera);
  }

  Future<List<String>> _subirImagenes(List<XFile> imagenes) async {
    List<String> urls = [];

    for (var img in imagenes) {
      final bytes = await img.readAsBytes();

      final ref = FirebaseStorage.instance
          .ref('mantenimientos/${DateTime.now().millisecondsSinceEpoch}.jpg');

      await ref.putData(bytes);
      final url = await ref.getDownloadURL();
      urls.add(url);
    }

    return urls;
  }

  // ================== FORMULARIO ==================

  void _mostrarFormulario() {
    showDialog(
      context: context,
      builder: (_) => StatefulBuilder(
        builder: (context, setStateDialog) => AlertDialog(
          title: const Text('Registrar Mantenimiento'),
          content: SingleChildScrollView(
            child: Column(
              children: [

                StreamBuilder<QuerySnapshot>(
                  stream: FirebaseFirestore.instance.collection('vehiculos').snapshots(),
                  builder: (context, snapshot) {
                    if (!snapshot.hasData) {
                      return const CircularProgressIndicator();
                    }

                    final vehiculos = snapshot.data!.docs;

                    return DropdownButton<String>(
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
                    );
                  },
                ),

                const SizedBox(height: 10),

                DropdownButton<String>(
                  value: _tipoTrabajo,
                  isExpanded: true,
                  items: tiposTrabajo.map((t) =>
                      DropdownMenuItem(value: t, child: Text(t))).toList(),
                  onChanged: (val) =>
                      setStateDialog(() => _tipoTrabajo = val!),
                ),

                if (_tipoTrabajo == 'Otro')
                  TextField(
                    controller: _descripcionController,
                    decoration: const InputDecoration(labelText: 'Detalle del trabajo'),
                  ),

                const SizedBox(height: 10),

                DropdownButton<String>(
                  value: _tipoEjecucion,
                  isExpanded: true,
                  items: tipoEjecucion.map((t) =>
                      DropdownMenuItem(value: t, child: Text(t))).toList(),
                  onChanged: (val) =>
                      setStateDialog(() => _tipoEjecucion = val!),
                ),

                TextField(
                  controller: _responsableController,
                  decoration: const InputDecoration(labelText: 'Responsable'),
                ),

                TextField(
                  controller: _kmController,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(labelText: 'Kilometraje'),
                ),

                TextField(
                  controller: _costoController,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(labelText: 'Costo'),
                ),

                const SizedBox(height: 10),

                ElevatedButton(
                  onPressed: () async {
                    final img = await _seleccionarImagen();
                    if (img != null) {
                      setStateDialog(() => _fotoKm = img);
                    }
                  },
                  child: const Text('Foto del kilometraje'),
                ),

                ElevatedButton(
                  onPressed: () async {
                    final img = await _seleccionarImagen();
                    if (img != null) {
                      setStateDialog(() => _fotosTrabajo.add(img));
                    }
                  },
                  child: const Text('Foto del trabajo'),
                ),

                ElevatedButton(
                  onPressed: () async {
                    final img = await _seleccionarImagen();
                    if (img != null) {
                      setStateDialog(() => _fotosPiezas.add(img));
                    }
                  },
                  child: const Text('Foto de piezas'),
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

                if (_vehiculoSeleccionado == null) {
                  _mostrarError('Seleccione vehículo');
                  return;
                }

                if (_fotoKm == null) {
                  _mostrarError('Debe tomar foto del km');
                  return;
                }

                final km = int.tryParse(_kmController.text) ?? 0;
                final costo = double.tryParse(_costoController.text) ?? 0;

                String urlKm = (await _subirImagenes([_fotoKm!])).first;
                final urlsTrabajo = await _subirImagenes(_fotosTrabajo);
                final urlsPiezas = await _subirImagenes(_fotosPiezas);

                await FirebaseFirestore.instance.collection('mantenimientos').add({
                  'vehiculo_id': _vehiculoSeleccionado,
                  'placa': _placaSeleccionada,
                  'vehiculo': _marcaModelo,
                  'tipo_trabajo': _tipoTrabajo,
                  'descripcion': _descripcionController.text,
                  'tipo_ejecucion': _tipoEjecucion,
                  'responsable': _responsableController.text,
                  'km': km,
                  'costo': costo,
                  'foto_km': urlKm,
                  'fotos_trabajo': urlsTrabajo,
                  'fotos_piezas': urlsPiezas,
                  'usuario': FirebaseAuth.instance.currentUser?.email,
                  'fecha': DateTime.now(),
                });

                Navigator.pop(context);
              },
              child: const Text('Guardar'),
            ),
          ],
        ),
      ),
    );
  }

  void _mostrarError(String msg) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(msg)));
  }

  void _verDetalle(Map<String, dynamic> data) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => _DetalleMantenimiento(data: data),
      ),
    );
  }

  // ================== UI ==================

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Mantenimiento'),
        backgroundColor: const Color(0xFF003580),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _mostrarFormulario,
        backgroundColor: const Color(0xFF003580),
        child: const Icon(Icons.add),
      ),
      body: StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance
            .collection('mantenimientos')
            .orderBy('fecha', descending: true)
            .snapshots(),
        builder: (context, snapshot) {

          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }

          final docs = snapshot.data!.docs;

          return ListView.builder(
            itemCount: docs.length,
            itemBuilder: (context, i) {
              final data = docs[i].data() as Map<String, dynamic>;

              return Card(
                child: ListTile(
                  title: Text(data['placa'] ?? ''),
                  subtitle: Text('${data['tipo_trabajo']} - ${data['km']} km'),
                  onTap: () => _verDetalle(data),
                ),
              );
            },
          );
        },
      ),
    );
  }
}

// ================== DETALLE ==================

class _DetalleMantenimiento extends StatelessWidget {

  final Map<String, dynamic> data;

  const _DetalleMantenimiento({required this.data});

  @override
  Widget build(BuildContext context) {

    final fotosTrabajo = List<String>.from(data['fotos_trabajo'] ?? []);
    final fotosPiezas = List<String>.from(data['fotos_piezas'] ?? []);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Detalle'),
        backgroundColor: const Color(0xFF003580),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [

            Text('Vehículo: ${data['vehiculo']}'),
            Text('Tipo: ${data['tipo_trabajo']}'),
            Text('Km: ${data['km']}'),
            Text('Responsable: ${data['responsable']}'),

            const SizedBox(height: 10),

            if (data['foto_km'] != null)
              Image.network(data['foto_km']),

            const SizedBox(height: 10),

            const Text('Trabajo realizado'),
            ...fotosTrabajo.map((url) => Image.network(url)),

            const SizedBox(height: 10),

            const Text('Piezas'),
            ...fotosPiezas.map((url) => Image.network(url)),
          ],
        ),
      ),
    );
  }
}