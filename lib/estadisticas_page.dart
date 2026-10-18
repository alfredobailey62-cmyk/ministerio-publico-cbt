import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:open_file/open_file.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

const Color _azul = Color(0xFF003580);
const Color _fondo = Color(0xFFF0F4FF);

class _Trip {
  final String conductor;
  final String placa;
  final double km;
  final double? horas;
  final DateTime fecha;

  const _Trip({
    required this.conductor,
    required this.placa,
    required this.km,
    required this.horas,
    required this.fecha,
  });
}

class _Summary {
  final List<_Trip> recorridos;
  final Map<String, int> viajesConductor;
  final Map<String, int> viajesVehiculo;
  final Map<String, double> kmConductor;
  final Map<String, double> kmVehiculo;
  final Map<String, double> horasConductor;
  final Map<String, double> combustibleVehiculo;
  final int recorridosSinKm;
  final int recorridosSinTiempo;

  const _Summary({
    required this.recorridos,
    required this.viajesConductor,
    required this.viajesVehiculo,
    required this.kmConductor,
    required this.kmVehiculo,
    required this.horasConductor,
    required this.combustibleVehiculo,
    required this.recorridosSinKm,
    required this.recorridosSinTiempo,
  });

  double get kmTotal => kmVehiculo.values.fold(0.0, (a, b) => a + b);

  double get horasTotal => horasConductor.values.fold(0.0, (a, b) => a + b);

  double get litrosTotal =>
      combustibleVehiculo.values.fold(0.0, (a, b) => a + b);

  int get totalRecorridos => recorridos.length;

  String? get topDriver => _highestValue(viajesConductor);

  String? get driverWithMostDistance => _highestValue(kmConductor);

  String? get driverWithMostHours => _highestValue(horasConductor);

  String? get mostActiveVehicle => _highestValue(viajesVehiculo);

  String? get vehicleWithMostDistance => _highestValue(kmVehiculo);

  String? get vehicleWithMostFuel => _highestValue(combustibleVehiculo);

  static String? _highestValue<T extends num>(Map<String, T> datos) {
    if (datos.isEmpty) return null;

    final ordenados = datos.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    return ordenados.first.key;
  }
}

class StatisticsPage extends StatefulWidget {
  const StatisticsPage({super.key});

  @override
  State<StatisticsPage> createState() => _StatisticsPageState();
}

class _StatisticsPageState extends State<StatisticsPage> {
  DateTime _selectedMonth = DateTime(DateTime.now().year, DateTime.now().month);

  bool _generatingPdf = false;

  DateTime _startOfMonth(DateTime fecha) => DateTime(fecha.year, fecha.month);

  DateTime _endOfMonth(DateTime fecha) => DateTime(fecha.year, fecha.month + 1);

  String get _monthName => DateFormat('MMMM yyyy', 'es').format(_selectedMonth);

  DateTime? _parseDate(dynamic valor) {
    if (valor is Timestamp) return valor.toDate();
    if (valor is DateTime) return valor;

    if (valor is String) {
      return DateTime.tryParse(valor);
    }

    return null;
  }

  double _parseNumber(dynamic valor) {
    if (valor is num) return valor.toDouble();
    if (valor is String) {
      return double.tryParse(valor.replaceAll(',', '.')) ?? 0;
    }
    return 0;
  }

  String _textValue(Map<String, dynamic> datos, List<String> claves) {
    for (final clave in claves) {
      final valor = datos[clave];
      if (valor != null && valor.toString().trim().isNotEmpty) {
        return valor.toString().trim();
      }
    }
    return '';
  }

  DateTime? _findDate(Map<String, dynamic> datos, List<String> claves) {
    for (final clave in claves) {
      final fecha = _parseDate(datos[clave]);
      if (fecha != null) return fecha;
    }
    return null;
  }

  double? _durationHours(Map<String, dynamic> datos) {
    final inicio = _findDate(datos, [
      'hora_salida',
      'fecha_inicio',
      'hora_inicio',
      'inicio',
      'fecha_salida',
      'salida',
    ]);

    final fin = _findDate(datos, [
      'hora_llegada',
      'fecha_fin',
      'hora_fin',
      'fin',
      'fecha_llegada',
      'llegada',
    ]);

    if (inicio != null && fin != null && fin.isAfter(inicio)) {
      return fin.difference(inicio).inSeconds / 3600;
    }

    final duracion = datos['duracion_minutos'];
    if (duracion is num && duracion >= 0) {
      return duracion.toDouble() / 60;
    }

    final horas = datos['duracion_horas'];
    if (horas is num && horas >= 0) {
      return horas.toDouble();
    }

    return null;
  }

  Future<_Summary> _calculateSummary(
    List<QueryDocumentSnapshot<Map<String, dynamic>>> recorridosDocs,
    List<QueryDocumentSnapshot<Map<String, dynamic>>> combustibleDocs,
  ) async {
    final inicio = _startOfMonth(_selectedMonth);
    final fin = _endOfMonth(_selectedMonth);

    final viajes = <_Trip>[];
    final viajesConductor = <String, int>{};
    final viajesVehiculo = <String, int>{};
    final kmConductor = <String, double>{};
    final kmVehiculo = <String, double>{};
    final horasConductor = <String, double>{};
    final combustibleVehiculo = <String, double>{};

    int sinKm = 0;
    int sinTiempo = 0;

    for (final doc in recorridosDocs) {
      final datos = doc.data();

      final fecha = _findDate(datos, [
        'fecha',
        'fecha_inicio',
        'hora_salida',
        'fecha_salida',
        'createdAt',
        'creado_en',
      ]);

      if (fecha == null || fecha.isBefore(inicio) || !fecha.isBefore(fin)) {
        continue;
      }

      final conductor = _textValue(datos, [
        'conductor',
        'nombre_conductor',
        'conductor_nombre',
        'usuario_nombre',
      ]);

      final placa = _textValue(datos, ['placa', 'vehiculo_placa', 'matricula']);

      final km = _parseNumber(
        datos['km_recorrido'] ??
            datos['kilometraje_recorrido'] ??
            datos['kilometros_recorridos'],
      );

      final horas = _durationHours(datos);

      final recorrido = _Trip(
        conductor: conductor.isEmpty ? 'Sin conductor identificado' : conductor,
        placa: placa.isEmpty ? 'Vehículo sin placa identificada' : placa,
        km: km,
        horas: horas,
        fecha: fecha,
      );

      viajes.add(recorrido);

      viajesConductor[recorrido.conductor] =
          (viajesConductor[recorrido.conductor] ?? 0) + 1;

      viajesVehiculo[recorrido.placa] =
          (viajesVehiculo[recorrido.placa] ?? 0) + 1;

      if (km > 0) {
        kmConductor[recorrido.conductor] =
            (kmConductor[recorrido.conductor] ?? 0) + km;

        kmVehiculo[recorrido.placa] = (kmVehiculo[recorrido.placa] ?? 0) + km;
      } else {
        sinKm++;
      }

      if (horas != null && horas > 0) {
        horasConductor[recorrido.conductor] =
            (horasConductor[recorrido.conductor] ?? 0) + horas;
      } else {
        sinTiempo++;
      }
    }

    for (final doc in combustibleDocs) {
      final datos = doc.data();

      final fecha = _findDate(datos, ['fecha', 'creado_en', 'createdAt']);

      if (fecha == null || fecha.isBefore(inicio) || !fecha.isBefore(fin)) {
        continue;
      }

      final placa = _textValue(datos, ['placa', 'vehiculo_placa']);

      final litros = _parseNumber(
        datos['litros_equivalentes'] ??
            datos['litros'] ??
            datos['cantidad_litros'],
      );

      if (placa.isNotEmpty && litros > 0) {
        combustibleVehiculo[placa] = (combustibleVehiculo[placa] ?? 0) + litros;
      }
    }

    return _Summary(
      recorridos: viajes,
      viajesConductor: viajesConductor,
      viajesVehiculo: viajesVehiculo,
      kmConductor: kmConductor,
      kmVehiculo: kmVehiculo,
      horasConductor: horasConductor,
      combustibleVehiculo: combustibleVehiculo,
      recorridosSinKm: sinKm,
      recorridosSinTiempo: sinTiempo,
    );
  }

  Future<void> _exportarPdf(_Summary resumen) async {
    if (_generatingPdf) return;

    setState(() => _generatingPdf = true);

    try {
      final pdf = pw.Document();
      final generado = DateFormat(
        'dd/MM/yyyy HH:mm',
        'es',
      ).format(DateTime.now());
      final periodo = DateFormat('MMMM yyyy', 'es').format(_selectedMonth);

      final azulPdf = PdfColor.fromHex('#003580');
      final azulClaro = PdfColor.fromHex('#E8F0FF');

      List<MapEntry<String, num>> ordenar(Map<String, num> datos) {
        final lista = datos.entries.toList()
          ..sort((a, b) => b.value.compareTo(a.value));
        return lista;
      }

      pw.Widget titulo(String texto) => pw.Container(
        width: double.infinity,
        margin: const pw.EdgeInsets.only(top: 16, bottom: 7),
        padding: const pw.EdgeInsets.all(8),
        color: azulPdf,
        child: pw.Text(
          texto,
          style: pw.TextStyle(
            color: PdfColors.white,
            fontWeight: pw.FontWeight.bold,
          ),
        ),
      );

      pw.Widget tabla(
        String primeraColumna,
        String segundaColumna,
        List<MapEntry<String, num>> datos,
        String unidad,
      ) {
        return pw.Table(
          border: pw.TableBorder.all(color: PdfColors.grey300, width: 0.5),
          children: [
            pw.TableRow(
              decoration: pw.BoxDecoration(color: azulClaro),
              children: [
                pw.Padding(
                  padding: const pw.EdgeInsets.all(6),
                  child: pw.Text(
                    primeraColumna,
                    style: pw.TextStyle(fontWeight: pw.FontWeight.bold),
                  ),
                ),
                pw.Padding(
                  padding: const pw.EdgeInsets.all(6),
                  child: pw.Text(
                    segundaColumna,
                    style: pw.TextStyle(fontWeight: pw.FontWeight.bold),
                  ),
                ),
              ],
            ),
            ...datos.map(
              (e) => pw.TableRow(
                children: [
                  pw.Padding(
                    padding: const pw.EdgeInsets.all(6),
                    child: pw.Text(e.key),
                  ),
                  pw.Padding(
                    padding: const pw.EdgeInsets.all(6),
                    child: pw.Text('${e.value.toStringAsFixed(2)} $unidad'),
                  ),
                ],
              ),
            ),
          ],
        );
      }

      pdf.addPage(
        pw.MultiPage(
          pageFormat: PdfPageFormat.a4,
          margin: const pw.EdgeInsets.all(32),
          header: (_) => pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Text(
                'CONTROL DE FLOTA VEHICULAR',
                style: pw.TextStyle(
                  color: azulPdf,
                  fontSize: 18,
                  fontWeight: pw.FontWeight.bold,
                ),
              ),
              pw.Text('Informe estadístico mensual: $periodo'),
              pw.Text(
                'Generado: $generado',
                style: const pw.TextStyle(fontSize: 9),
              ),
              pw.Divider(color: azulPdf, thickness: 2),
            ],
          ),
          footer: (ctx) => pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              pw.Text(
                'Informe estadístico de flota',
                style: const pw.TextStyle(fontSize: 8),
              ),
              pw.Text(
                'Página ${ctx.pageNumber} de ${ctx.pagesCount}',
                style: const pw.TextStyle(fontSize: 8),
              ),
            ],
          ),
          build: (_) => [
            titulo('1. RESUMEN GENERAL'),
            pw.Table(
              border: pw.TableBorder.all(color: PdfColors.grey300),
              children:
                  [
                        ['Indicador', 'Resultado'],
                        ['Total de recorridos', '${resumen.totalRecorridos}'],
                        [
                          'Kilómetros registrados',
                          '${resumen.kmTotal.toStringAsFixed(2)} km',
                        ],
                        [
                          'Horas de conducción registradas',
                          '${resumen.horasTotal.toStringAsFixed(2)} h',
                        ],
                        [
                          'Combustible registrado',
                          '${resumen.litrosTotal.toStringAsFixed(2)} L',
                        ],
                        [
                          'Recorridos sin kilometraje',
                          '${resumen.recorridosSinKm}',
                        ],
                        [
                          'Recorridos sin duración calculable',
                          '${resumen.recorridosSinTiempo}',
                        ],
                      ]
                      .map(
                        (fila) => pw.TableRow(
                          children: fila
                              .map(
                                (celda) => pw.Padding(
                                  padding: const pw.EdgeInsets.all(6),
                                  child: pw.Text(celda),
                                ),
                              )
                              .toList(),
                        ),
                      )
                      .toList(),
            ),
            titulo('2. ACTIVIDAD POR CONDUCTOR'),
            tabla(
              'Conductor',
              'Recorridos',
              ordenar(resumen.viajesConductor),
              'viajes',
            ),
            titulo('3. KILÓMETROS POR CONDUCTOR'),
            tabla('Conductor', 'Distancia', ordenar(resumen.kmConductor), 'km'),
            titulo('4. HORAS REGISTRADAS POR CONDUCTOR'),
            tabla('Conductor', 'Tiempo', ordenar(resumen.horasConductor), 'h'),
            titulo('5. ACTIVIDAD POR VEHÍCULO'),
            tabla(
              'Placa',
              'Recorridos',
              ordenar(resumen.viajesVehiculo),
              'viajes',
            ),
            titulo('6. KILÓMETROS POR VEHÍCULO'),
            tabla('Placa', 'Distancia', ordenar(resumen.kmVehiculo), 'km'),
            titulo('7. COMBUSTIBLE POR VEHÍCULO'),
            tabla(
              'Placa',
              'Combustible',
              ordenar(resumen.combustibleVehiculo),
              'L',
            ),
            titulo('8. OBSERVACIONES AUTOMÁTICAS'),
            pw.Bullet(
              text: resumen.totalRecorridos == 0
                  ? 'No existen recorridos registrados para el mes seleccionado.'
                  : 'Se registraron ${resumen.totalRecorridos} recorridos durante el periodo.',
            ),
            if (resumen.vehicleWithMostDistance != null)
              pw.Bullet(
                text:
                    'Vehículo con mayor kilometraje registrado: '
                    '${resumen.vehicleWithMostDistance}.',
              ),
            if (resumen.driverWithMostDistance != null)
              pw.Bullet(
                text:
                    'Conductor con mayor distancia registrada: '
                    '${resumen.driverWithMostDistance}.',
              ),
            if (resumen.driverWithMostHours != null)
              pw.Bullet(
                text:
                    'Conductor con más horas registradas: '
                    '${resumen.driverWithMostHours}.',
              ),
            if (resumen.recorridosSinKm > 0)
              pw.Bullet(
                text:
                    '${resumen.recorridosSinKm} recorridos no tienen '
                    'kilometraje válido.',
              ),
            if (resumen.recorridosSinTiempo > 0)
              pw.Bullet(
                text:
                    '${resumen.recorridosSinTiempo} recorridos no tienen '
                    'duración calculable. Revise las fechas de salida y llegada.',
              ),
            pw.SizedBox(height: 10),
            pw.Text(
              'Nota: las estadísticas se calculan a partir de los datos '
              'registrados en el sistema. Las horas y distancias incompletas '
              'no se estiman como si fueran valores confirmados.',
              style: const pw.TextStyle(fontSize: 9),
            ),
          ],
        ),
      );

      final directorio = await getTemporaryDirectory();
      final archivo = File(
        '${directorio.path}/informe_flota_'
        '${_selectedMonth.year}_'
        '${_selectedMonth.month.toString().padLeft(2, '0')}.pdf',
      );

      await archivo.writeAsBytes(await pdf.save());
      await OpenFile.open(archivo.path);

      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Informe PDF generado.')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('No se pudo generar el PDF: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _generatingPdf = false);
    }
  }

  Widget _tarjeta(
    String titulo,
    String valor,
    IconData icono, {
    String? detalle,
  }) {
    return Card(
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          children: [
            Icon(icono, size: 30, color: _azul),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(titulo, style: const TextStyle(fontSize: 12)),
                  const SizedBox(height: 5),
                  Text(
                    valor,
                    style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: _azul,
                    ),
                  ),
                  if (detalle != null)
                    Text(
                      detalle,
                      style: const TextStyle(
                        fontSize: 11,
                        color: Colors.black54,
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _ranking(
    String titulo,
    Map<String, num> datos,
    String unidad,
    IconData icono,
  ) {
    final ordenados = datos.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: ExpansionTile(
        leading: Icon(icono, color: _azul),
        title: Text(
          titulo,
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        subtitle: Text('${ordenados.length} registros'),
        children: ordenados.isEmpty
            ? [const ListTile(title: Text('Sin datos para este periodo.'))]
            : ordenados.map((e) {
                final maximo = ordenados.first.value.toDouble();
                final valor = e.value.toDouble();
                final porcentaje = maximo > 0
                    ? (valor / maximo).clamp(0.0, 1.0)
                    : 0.0;

                return ListTile(
                  leading: const Icon(Icons.bar_chart),
                  title: Text(e.key),
                  subtitle: Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: LinearProgressIndicator(
                      value: porcentaje,
                      color: _azul,
                      backgroundColor: Colors.black12,
                    ),
                  ),
                  trailing: Text(
                    '${valor.toStringAsFixed(1)} $unidad',
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                );
              }).toList(),
      ),
    );
  }

  Widget _analysis(_Summary r) {
    final observaciones = <String>[];

    if (r.totalRecorridos == 0) {
      observaciones.add('No hay recorridos para el mes seleccionado.');
    } else {
      observaciones.add(
        'Se registraron ${r.totalRecorridos} recorridos y '
        '${r.kmTotal.toStringAsFixed(1)} km.',
      );
    }

    if (r.vehicleWithMostDistance != null) {
      observaciones.add(
        'Mayor kilometraje por vehículo: ${r.vehicleWithMostDistance}.',
      );
    }

    if (r.mostActiveVehicle != null) {
      observaciones.add('Vehículo con más recorridos: ${r.mostActiveVehicle}.');
    }

    if (r.topDriver != null) {
      observaciones.add('Conductor con más recorridos: ${r.topDriver}.');
    }

    if (r.driverWithMostHours != null) {
      observaciones.add('Más horas registradas: ${r.driverWithMostHours}.');
    }

    if (r.recorridosSinKm > 0 || r.recorridosSinTiempo > 0) {
      observaciones.add(
        'Hay registros incompletos. Revise kilometrajes y horas de salida '
        'y llegada antes de tomar decisiones.',
      );
    }

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Row(
              children: [
                Icon(Icons.psychology, color: _azul, size: 28),
                SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Análisis automático',
                    style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            ...observaciones.map(
              (texto) => Padding(
                padding: const EdgeInsets.only(bottom: 9),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(Icons.insights, color: _azul, size: 18),
                    const SizedBox(width: 8),
                    Expanded(child: Text(texto)),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _content(_Summary r) {
    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
            child: Row(
              children: [
                IconButton(
                  tooltip: 'Mes anterior',
                  onPressed: () {
                    setState(() {
                      _selectedMonth = DateTime(
                        _selectedMonth.year,
                        _selectedMonth.month - 1,
                      );
                    });
                  },
                  icon: const Icon(Icons.chevron_left),
                ),
                Expanded(
                  child: Column(
                    children: [
                      const Text(
                        'PERIODO DEL INFORME',
                        style: TextStyle(fontSize: 11),
                      ),
                      Text(
                        _monthName.toUpperCase(),
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          color: _azul,
                          fontSize: 17,
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  tooltip: 'Mes siguiente',
                  onPressed: () {
                    final actual = DateTime.now();
                    final siguiente = DateTime(
                      _selectedMonth.year,
                      _selectedMonth.month + 1,
                    );

                    if (!siguiente.isAfter(
                      DateTime(actual.year, actual.month),
                    )) {
                      setState(() => _selectedMonth = siguiente);
                    }
                  },
                  icon: const Icon(Icons.chevron_right),
                ),
              ],
            ),
          ),
        ),
        GridView.count(
          crossAxisCount: MediaQuery.of(context).size.width > 700 ? 4 : 2,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          crossAxisSpacing: 8,
          mainAxisSpacing: 8,
          childAspectRatio: 1.65,
          children: [
            _tarjeta('Recorridos', '${r.totalRecorridos}', Icons.route),
            _tarjeta(
              'Kilómetros',
              r.kmTotal.toStringAsFixed(1),
              Icons.speed,
              detalle: 'km registrados',
            ),
            _tarjeta(
              'Horas al volante',
              r.horasTotal.toStringAsFixed(1),
              Icons.schedule,
              detalle: 'horas calculables',
            ),
            _tarjeta(
              'Combustible',
              r.litrosTotal.toStringAsFixed(1),
              Icons.local_gas_station,
              detalle: 'litros registrados',
            ),
          ],
        ),
        const SizedBox(height: 12),
        _analysis(r),
        const SizedBox(height: 12),
        _ranking(
          'Vehículos con más recorridos',
          r.viajesVehiculo,
          'viajes',
          Icons.directions_car,
        ),
        _ranking(
          'Vehículos con más kilometraje',
          r.kmVehiculo,
          'km',
          Icons.route,
        ),
        _ranking(
          'Conductores con más recorridos',
          r.viajesConductor,
          'viajes',
          Icons.people,
        ),
        _ranking(
          'Conductores con más kilómetros',
          r.kmConductor,
          'km',
          Icons.speed,
        ),
        _ranking(
          'Conductores con más horas registradas',
          r.horasConductor,
          'h',
          Icons.access_time,
        ),
        _ranking(
          'Combustible por vehículo',
          r.combustibleVehiculo,
          'L',
          Icons.local_gas_station,
        ),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Calidad de los datos',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                Text('Recorridos sin kilometraje: ${r.recorridosSinKm}'),
                Text(
                  'Recorridos sin duración calculable: ${r.recorridosSinTiempo}',
                ),
                const SizedBox(height: 8),
                const Text(
                  'Las horas solo se calculan cuando hay datos válidos '
                  'de inicio y fin. Las estadísticas no eliminan los '
                  'registros originales.',
                  style: TextStyle(color: Colors.black54, fontSize: 12),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        ElevatedButton.icon(
          onPressed: _generatingPdf ? null : () => _exportarPdf(r),
          style: ElevatedButton.styleFrom(
            backgroundColor: _azul,
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(vertical: 15),
          ),
          icon: _generatingPdf
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white,
                  ),
                )
              : const Icon(Icons.picture_as_pdf),
          label: Text(
            _generatingPdf
                ? 'Generando informe...'
                : 'Exportar informe mensual en PDF',
          ),
        ),
        const SizedBox(height: 20),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final recorridosStream = FirebaseFirestore.instance
        .collection('recorridos')
        .snapshots();

    final combustibleStream = FirebaseFirestore.instance
        .collection('combustible')
        .snapshots();

    return Scaffold(
      backgroundColor: _fondo,
      appBar: AppBar(
        title: const Text('Dashboard de flota'),
        backgroundColor: _azul,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            tooltip: 'Volver al mes actual',
            onPressed: () {
              final ahora = DateTime.now();
              setState(() {
                _selectedMonth = DateTime(ahora.year, ahora.month);
              });
            },
            icon: const Icon(Icons.today),
          ),
        ],
      ),
      body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: recorridosStream,
        builder: (context, recorridosSnap) {
          if (recorridosSnap.hasError) {
            return Center(
              child: Text(
                'Error al cargar recorridos: ${recorridosSnap.error}',
              ),
            );
          }

          if (!recorridosSnap.hasData) {
            return const Center(child: CircularProgressIndicator());
          }

          return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
            stream: combustibleStream,
            builder: (context, combustibleSnap) {
              if (combustibleSnap.hasError) {
                return Center(
                  child: Text(
                    'Error al cargar combustible: ${combustibleSnap.error}',
                  ),
                );
              }

              if (!combustibleSnap.hasData) {
                return const Center(child: CircularProgressIndicator());
              }

              return FutureBuilder<_Summary>(
                future: _calculateSummary(
                  recorridosSnap.data!.docs,
                  combustibleSnap.data!.docs,
                ),
                builder: (context, resumenSnap) {
                  if (resumenSnap.hasError) {
                    return Center(
                      child: Text(
                        'Error al calcular estadísticas: ${resumenSnap.error}',
                      ),
                    );
                  }

                  if (!resumenSnap.hasData) {
                    return const Center(child: CircularProgressIndicator());
                  }

                  return _content(resumenSnap.data!);
                },
              );
            },
          );
        },
      ),
    );
  }
}
