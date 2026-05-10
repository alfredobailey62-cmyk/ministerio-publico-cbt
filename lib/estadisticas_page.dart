import 'dart:io';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:open_file/open_file.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

// ─────────────────────────────────────────────
//  MODELOS DE DATOS CALCULADOS EN TIEMPO REAL
// ─────────────────────────────────────────────
class _Stats {
  final int totalCarpetas;
  final Map<String, int> carpetasPorFiscalia;
  final Map<String, int> diligenciasPorConductor;
  final Map<String, double> kmPorConductor;
  final Map<String, double> combustiblePorVehiculo;

  const _Stats({
    required this.totalCarpetas,
    required this.carpetasPorFiscalia,
    required this.diligenciasPorConductor,
    required this.kmPorConductor,
    required this.combustiblePorVehiculo,
  });
}

// ─────────────────────────────────────────────
//  PÁGINA PRINCIPAL
// ─────────────────────────────────────────────
class EstadisticasPage extends StatelessWidget {
  const EstadisticasPage({super.key});

  // Combina tres colecciones y calcula todas las métricas
  Stream<_Stats> _statsStream() {
    final recorridosStream =
        FirebaseFirestore.instance.collection('recorridos').snapshots();
    final combustibleStream =
        FirebaseFirestore.instance.collection('combustible').snapshots();
    final carpetasStream =
        FirebaseFirestore.instance.collection('carpetas').snapshots();

    // Combina los tres streams usando StreamBuilder anidados en el build
    // Aquí devolvemos sólo el stream de recorridos; la combinación se hace en build
    return recorridosStream.asyncMap((_) async {
      return _calcularStats();
    });
  }

  Future<_Stats> _calcularStats() async {
    final recorridosSnap =
        await FirebaseFirestore.instance.collection('recorridos').get();
    final combustibleSnap =
        await FirebaseFirestore.instance.collection('combustible').get();
    final carpetasSnap =
        await FirebaseFirestore.instance.collection('carpetas').get();

    // ── Diligencias y km por conductor ──────────────
    final Map<String, int> diligenciasConductor = {};
    final Map<String, double> kmConductor = {};

    for (var doc in recorridosSnap.docs) {
      final d = doc.data();
      final conductor = (d['conductor'] ?? 'Sin nombre').toString();
      final km = (d['km_recorrido'] ?? 0).toDouble();
      diligenciasConductor[conductor] =
          (diligenciasConductor[conductor] ?? 0) + 1;
      kmConductor[conductor] = (kmConductor[conductor] ?? 0) + km;
    }

    // ── Combustible por vehículo ─────────────────────
    final Map<String, double> combustibleVehiculo = {};
    for (var doc in combustibleSnap.docs) {
      final d = doc.data();
      final placa = (d['placa'] ?? 'Sin placa').toString();
      final litros = (d['litros'] ?? 0).toDouble();
      combustibleVehiculo[placa] =
          (combustibleVehiculo[placa] ?? 0) + litros;
    }

    // ── Carpetas por fiscalía ────────────────────────
    final Map<String, int> carpetasFiscalia = {};
    int totalCarpetas = carpetasSnap.docs.length;

    for (var doc in carpetasSnap.docs) {
      final d = doc.data();
      final fiscalia = (d['fiscalia'] ?? 'Sin fiscalía').toString();
      carpetasFiscalia[fiscalia] = (carpetasFiscalia[fiscalia] ?? 0) + 1;
    }

    return _Stats(
      totalCarpetas: totalCarpetas,
      carpetasPorFiscalia: carpetasFiscalia,
      diligenciasPorConductor: diligenciasConductor,
      kmPorConductor: kmConductor,
      combustiblePorVehiculo: combustibleVehiculo,
    );
  }

  // ── Generación y apertura del PDF ───────────────────
  Future<void> _exportarPDF(BuildContext context, _Stats stats) async {
    final pdf = pw.Document();
    final ahora = DateFormat('dd/MM/yyyy HH:mm').format(DateTime.now());

    // Ordenar datos para los rankings
    final topConductoresDilig = stats.diligenciasPorConductor.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final topConductoresKm = stats.kmPorConductor.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final topVehiculos = stats.combustiblePorVehiculo.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final topFiscalias = stats.carpetasPorFiscalia.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    // Colores
    final azulOscuro = PdfColor.fromHex('#003580');
    final azulClaro = PdfColor.fromHex('#E8F0FF');
    final gris = PdfColor.fromHex('#F5F5F5');

    pw.TableRow _headerRow(List<String> cols) => pw.TableRow(
          decoration: pw.BoxDecoration(color: azulOscuro),
          children: cols
              .map((c) => pw.Padding(
                    padding: const pw.EdgeInsets.symmetric(
                        horizontal: 8, vertical: 6),
                    child: pw.Text(c,
                        style: pw.TextStyle(
                            color: PdfColors.white,
                            fontWeight: pw.FontWeight.bold,
                            fontSize: 10)),
                  ))
              .toList(),
        );

    pw.TableRow _dataRow(List<String> cols, bool alterno) => pw.TableRow(
          decoration:
              pw.BoxDecoration(color: alterno ? azulClaro : PdfColors.white),
          children: cols
              .map((c) => pw.Padding(
                    padding: const pw.EdgeInsets.symmetric(
                        horizontal: 8, vertical: 5),
                    child: pw.Text(c, style: const pw.TextStyle(fontSize: 9)),
                  ))
              .toList(),
        );

    pw.Widget _seccionTitulo(String titulo) => pw.Container(
          margin: const pw.EdgeInsets.only(top: 16, bottom: 6),
          padding:
              const pw.EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          decoration: pw.BoxDecoration(
            color: azulOscuro,
            borderRadius: pw.BorderRadius.circular(4),
          ),
          child: pw.Text(titulo,
              style: pw.TextStyle(
                  color: PdfColors.white,
                  fontWeight: pw.FontWeight.bold,
                  fontSize: 11)),
        );

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.letter,
        margin: const pw.EdgeInsets.all(32),
        header: (ctx) => pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
                pw.Text('REPORTE DE ESTADÍSTICAS',
                    style: pw.TextStyle(
                        fontSize: 18,
                        fontWeight: pw.FontWeight.bold,
                        color: azulOscuro)),
                pw.Text('Generado: $ahora',
                    style: pw.TextStyle(
                        fontSize: 8, color: PdfColors.grey600)),
              ],
            ),
            pw.Divider(color: azulOscuro, thickness: 2),
            pw.SizedBox(height: 4),
          ],
        ),
        footer: (ctx) => pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          children: [
            pw.Text('Fiscalía General - Sistema de Transporte',
                style:
                    pw.TextStyle(fontSize: 8, color: PdfColors.grey600)),
            pw.Text('Página ${ctx.pageNumber} de ${ctx.pagesCount}',
                style:
                    pw.TextStyle(fontSize: 8, color: PdfColors.grey600)),
          ],
        ),
        build: (ctx) => [
          // ── KPI resumen ──────────────────────────────────
          pw.Container(
            padding: const pw.EdgeInsets.all(12),
            decoration: pw.BoxDecoration(
              color: gris,
              borderRadius: pw.BorderRadius.circular(6),
            ),
            child: pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceAround,
              children: [
                _kpiPdf('Total Carpetas', '${stats.totalCarpetas}',
                    azulOscuro),
                _kpiPdf('Conductores',
                    '${stats.diligenciasPorConductor.length}', azulOscuro),
                _kpiPdf('Vehículos',
                    '${stats.combustiblePorVehiculo.length}', azulOscuro),
                _kpiPdf(
                    'Fiscalías', '${stats.carpetasPorFiscalia.length}', azulOscuro),
              ],
            ),
          ),

          // ── 1. Conductor con más diligencias ────────────
          _seccionTitulo('1. Conductores con Más Diligencias'),
          pw.Table(
            border: pw.TableBorder.all(color: PdfColors.grey300, width: 0.5),
            columnWidths: {
              0: const pw.FlexColumnWidth(3),
              1: const pw.FlexColumnWidth(1.5),
              2: const pw.FlexColumnWidth(1.5),
            },
            children: [
              _headerRow(['Conductor', 'Diligencias', '% del Total']),
              ...topConductoresDilig.asMap().entries.map((e) {
                final pct = stats.diligenciasPorConductor.values
                        .fold(0, (a, b) => a + b) >
                    0
                    ? (e.value.value /
                            stats.diligenciasPorConductor.values
                                .fold(0, (a, b) => a + b) *
                            100)
                        .toStringAsFixed(1)
                    : '0';
                return _dataRow(
                    [e.value.key, '${e.value.value}', '$pct%'],
                    e.key.isOdd);
              }),
            ],
          ),

          // ── 2. Conductor con más distancia ──────────────
          _seccionTitulo('2. Conductores con Mayor Distancia Recorrida'),
          pw.Table(
            border: pw.TableBorder.all(color: PdfColors.grey300, width: 0.5),
            columnWidths: {
              0: const pw.FlexColumnWidth(3),
              1: const pw.FlexColumnWidth(2),
            },
            children: [
              _headerRow(['Conductor', 'Kilómetros Totales']),
              ...topConductoresKm.asMap().entries.map((e) => _dataRow(
                  [e.value.key, '${e.value.value.toStringAsFixed(2)} km'],
                  e.key.isOdd)),
            ],
          ),

          // ── 3. Vehículo con más consumo ─────────────────
          _seccionTitulo('3. Vehículos con Mayor Consumo de Combustible'),
          pw.Table(
            border: pw.TableBorder.all(color: PdfColors.grey300, width: 0.5),
            columnWidths: {
              0: const pw.FlexColumnWidth(2),
              1: const pw.FlexColumnWidth(2),
            },
            children: [
              _headerRow(['Placa / Vehículo', 'Litros Consumidos']),
              ...topVehiculos.asMap().entries.map((e) => _dataRow(
                  [e.value.key, '${e.value.value.toStringAsFixed(2)} L'],
                  e.key.isOdd)),
            ],
          ),

          // ── 4. Fiscalía con más diligencias ─────────────
          _seccionTitulo('4. Fiscalías con Más Diligencias'),
          pw.Table(
            border: pw.TableBorder.all(color: PdfColors.grey300, width: 0.5),
            columnWidths: {
              0: const pw.FlexColumnWidth(3),
              1: const pw.FlexColumnWidth(1.5),
            },
            children: [
              _headerRow(['Fiscalía', 'Carpetas Diligenciadas']),
              ...topFiscalias.asMap().entries.map((e) => _dataRow(
                  [e.value.key, '${e.value.value}'], e.key.isOdd)),
            ],
          ),

          // ── 5. Total carpetas diligenciadas ─────────────
          _seccionTitulo('5. Total de Carpetas Diligenciadas'),
          pw.Container(
            padding: const pw.EdgeInsets.all(14),
            decoration: pw.BoxDecoration(
              color: azulClaro,
              borderRadius: pw.BorderRadius.circular(6),
            ),
            child: pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.center,
              children: [
                pw.Text('Total General de Carpetas: ',
                    style: pw.TextStyle(
                        fontSize: 13, color: azulOscuro)),
                pw.Text('${stats.totalCarpetas}',
                    style: pw.TextStyle(
                        fontSize: 18,
                        fontWeight: pw.FontWeight.bold,
                        color: azulOscuro)),
              ],
            ),
          ),
        ],
      ),
    );

    // Guardar y abrir
    final dir = await getTemporaryDirectory();
    final file = File(
        '${dir.path}/estadisticas_${DateTime.now().millisecondsSinceEpoch}.pdf');
    await file.writeAsBytes(await pdf.save());
    await OpenFile.open(file.path);

    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('PDF generado correctamente'),
          backgroundColor: Color(0xFF003580),
        ),
      );
    }
  }

  pw.Widget _kpiPdf(String titulo, String valor, PdfColor color) =>
      pw.Column(children: [
        pw.Text(valor,
            style: pw.TextStyle(
                fontSize: 20, fontWeight: pw.FontWeight.bold, color: color)),
        pw.Text(titulo,
            style: pw.TextStyle(fontSize: 8, color: PdfColors.grey700)),
      ]);

  // ─────────────────────────────────────────────
  //  BUILD
  // ─────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF0F4FF),
      appBar: AppBar(
        title: const Text('Estadísticas en Tiempo Real'),
        backgroundColor: const Color(0xFF003580),
        foregroundColor: Colors.white,
        elevation: 0,
        actions: [
          // Botón PDF dentro del AppBar, accede a stats vía StreamBuilder
          _PdfButton(calcularStats: _calcularStats),
        ],
      ),
      body: StreamBuilder<_Stats>(
        stream: _statsStream(),
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting) {
            return const Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  CircularProgressIndicator(color: Color(0xFF003580)),
                  SizedBox(height: 12),
                  Text('Cargando estadísticas…'),
                ],
              ),
            );
          }
          if (snap.hasError) {
            return Center(child: Text('Error: ${snap.error}'));
          }

          final s = snap.data!;

          // Ordenados para mostrar #1 primero
          final topDilig = s.diligenciasPorConductor.entries.toList()
            ..sort((a, b) => b.value.compareTo(a.value));
          final topKm = s.kmPorConductor.entries.toList()
            ..sort((a, b) => b.value.compareTo(a.value));
          final topComb = s.combustiblePorVehiculo.entries.toList()
            ..sort((a, b) => b.value.compareTo(a.value));
          final topFisc = s.carpetasPorFiscalia.entries.toList()
            ..sort((a, b) => b.value.compareTo(a.value));

          return SingleChildScrollView(
            padding:
                const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // ── KPIs en grid ──────────────────────────
                GridView.count(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  crossAxisCount: 2,
                  crossAxisSpacing: 12,
                  mainAxisSpacing: 12,
                  childAspectRatio: 1.6,
                  children: [
                    _kpiCard('Total Carpetas',
                        '${s.totalCarpetas}', Icons.folder_copy, Colors.blue),
                    _kpiCard(
                        'Conductores',
                        '${s.diligenciasPorConductor.length}',
                        Icons.person,
                        Colors.teal),
                    _kpiCard(
                        'Vehículos',
                        '${s.combustiblePorVehiculo.length}',
                        Icons.directions_car,
                        Colors.orange),
                    _kpiCard(
                        'Fiscalías',
                        '${s.carpetasPorFiscalia.length}',
                        Icons.account_balance,
                        Colors.purple),
                  ],
                ),

                const SizedBox(height: 20),

                // ── 1. Conductor con más diligencias ──────
                _seccionTitulo(
                    Icons.emoji_events, '1. Conductor con más diligencias'),
                _rankingList(
                  items: topDilig,
                  labelFn: (e) => e.key,
                  valueFn: (e) => '${e.value} dilig.',
                  color: Colors.blue,
                  maxVal: topDilig.isEmpty ? 1 : topDilig.first.value.toDouble(),
                ),

                const SizedBox(height: 16),

                // ── 2. Conductor con más distancia ─────────
                _seccionTitulo(
                    Icons.route, '2. Conductor con mayor distancia'),
                _rankingList(
                  items: topKm,
                  labelFn: (e) => e.key,
                  valueFn: (e) => '${e.value.toStringAsFixed(1)} km',
                  color: Colors.green,
                  maxVal: topKm.isEmpty ? 1 : topKm.first.value,
                  rawVal: (e) => e.value,
                ),

                const SizedBox(height: 16),

                // ── 3. Vehículo con más consumo ─────────────
                _seccionTitulo(
                    Icons.local_gas_station,
                    '3. Vehículo con mayor consumo'),
                _rankingList(
                  items: topComb,
                  labelFn: (e) => e.key,
                  valueFn: (e) => '${e.value.toStringAsFixed(1)} L',
                  color: Colors.orange,
                  maxVal: topComb.isEmpty ? 1 : topComb.first.value,
                  rawVal: (e) => e.value,
                ),

                const SizedBox(height: 16),

                // ── 4. Fiscalía con más diligencias ─────────
                _seccionTitulo(
                    Icons.account_balance,
                    '4. Fiscalía con más diligencias'),
                _rankingList(
                  items: topFisc,
                  labelFn: (e) => e.key,
                  valueFn: (e) => '${e.value} carpetas',
                  color: Colors.purple,
                  maxVal:
                      topFisc.isEmpty ? 1 : topFisc.first.value.toDouble(),
                ),

                const SizedBox(height: 24),
              ],
            ),
          );
        },
      ),
    );
  }

  // ── Widgets de apoyo ────────────────────────────────────
  Widget _seccionTitulo(IconData icon, String titulo) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Row(
          children: [
            Icon(icon, color: const Color(0xFF003580), size: 20),
            const SizedBox(width: 8),
            Text(titulo,
                style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF003580))),
          ],
        ),
      );

  Widget _kpiCard(
      String titulo, String valor, IconData icon, Color color) =>
      Card(
        elevation: 3,
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            gradient: LinearGradient(
              colors: [color.withOpacity(0.12), Colors.white],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
          ),
          padding: const EdgeInsets.all(12),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, color: color, size: 26),
              const SizedBox(height: 6),
              Text(valor,
                  style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: color)),
              Text(titulo,
                  style: const TextStyle(fontSize: 11, color: Colors.grey),
                  textAlign: TextAlign.center),
            ],
          ),
        ),
      );

  Widget _rankingList<T>({
    required List<T> items,
    required String Function(T) labelFn,
    required String Function(T) valueFn,
    required Color color,
    required double maxVal,
    double Function(T)? rawVal,
  }) {
    if (items.isEmpty) {
      return const Card(
        child: Padding(
          padding: EdgeInsets.all(14),
          child: Center(child: Text('Sin datos')),
        ),
      );
    }
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Column(
          children: items.asMap().entries.map((entry) {
            final i = entry.key;
            final item = entry.value;
            final raw = rawVal != null ? rawVal(item) : 0.0;
            final intVal = rawVal == null
                ? double.tryParse(
                        valueFn(item).replaceAll(RegExp(r'[^0-9.]'), '')) ??
                    0
                : raw;
            final pct = maxVal > 0 ? (intVal / maxVal).clamp(0.0, 1.0) : 0.0;

            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 5),
              child: Row(
                children: [
                  // Medalla / número
                  Container(
                    width: 26,
                    height: 26,
                    decoration: BoxDecoration(
                      color: i == 0
                          ? Colors.amber
                          : i == 1
                              ? Colors.grey.shade400
                              : i == 2
                                  ? const Color(0xFFCD7F32)
                                  : Colors.grey.shade200,
                      shape: BoxShape.circle,
                    ),
                    child: Center(
                      child: Text('${i + 1}',
                          style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                              color:
                                  i < 3 ? Colors.white : Colors.grey)),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(labelFn(item),
                            style: const TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w500),
                            overflow: TextOverflow.ellipsis),
                        const SizedBox(height: 3),
                        LinearProgressIndicator(
                          value: pct,
                          backgroundColor: Colors.grey.shade200,
                          color: color,
                          minHeight: 5,
                          borderRadius: BorderRadius.circular(4),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 10),
                  Text(valueFn(item),
                      style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: color)),
                ],
              ),
            );
          }).toList(),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────
//  BOTÓN PDF SEPARADO (tiene su propio contexto)
// ─────────────────────────────────────────────
class _PdfButton extends StatefulWidget {
  final Future<_Stats> Function() calcularStats;
  const _PdfButton({required this.calcularStats});

  @override
  State<_PdfButton> createState() => _PdfButtonState();
}

class _PdfButtonState extends State<_PdfButton> {
  bool _generando = false;

  Future<void> _generar() async {
    if (_generando) return;
    setState(() => _generando = true);
    try {
      final stats = await widget.calcularStats();
      await _exportarPDF(context, stats);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error al generar PDF: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _generando = false);
    }
  }

  // Copia local del método de exportación PDF
  Future<void> _exportarPDF(BuildContext context, _Stats stats) async {
    final pdf = pw.Document();
    final ahora = DateFormat('dd/MM/yyyy HH:mm').format(DateTime.now());

    final topConductoresDilig = stats.diligenciasPorConductor.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final topConductoresKm = stats.kmPorConductor.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final topVehiculos = stats.combustiblePorVehiculo.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final topFiscalias = stats.carpetasPorFiscalia.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    final azulOscuro = PdfColor.fromHex('#003580');
    final azulClaro = PdfColor.fromHex('#E8F0FF');
    final gris = PdfColor.fromHex('#F5F5F5');

    pw.TableRow headerRow(List<String> cols) => pw.TableRow(
          decoration: pw.BoxDecoration(color: azulOscuro),
          children: cols
              .map((c) => pw.Padding(
                    padding: const pw.EdgeInsets.symmetric(
                        horizontal: 8, vertical: 6),
                    child: pw.Text(c,
                        style: pw.TextStyle(
                            color: PdfColors.white,
                            fontWeight: pw.FontWeight.bold,
                            fontSize: 10)),
                  ))
              .toList(),
        );

    pw.TableRow dataRow(List<String> cols, bool alt) => pw.TableRow(
          decoration: pw.BoxDecoration(
              color: alt ? azulClaro : PdfColors.white),
          children: cols
              .map((c) => pw.Padding(
                    padding: const pw.EdgeInsets.symmetric(
                        horizontal: 8, vertical: 5),
                    child: pw.Text(c, style: const pw.TextStyle(fontSize: 9)),
                  ))
              .toList(),
        );

    pw.Widget seccion(String t) => pw.Container(
          margin: const pw.EdgeInsets.only(top: 16, bottom: 6),
          padding:
              const pw.EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          decoration: pw.BoxDecoration(
              color: azulOscuro,
              borderRadius: pw.BorderRadius.circular(4)),
          child: pw.Text(t,
              style: pw.TextStyle(
                  color: PdfColors.white,
                  fontWeight: pw.FontWeight.bold,
                  fontSize: 11)),
        );

    pdf.addPage(pw.MultiPage(
      pageFormat: PdfPageFormat.letter,
      margin: const pw.EdgeInsets.all(32),
      header: (ctx) => pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Text('REPORTE DE ESTADÍSTICAS',
                      style: pw.TextStyle(
                          fontSize: 18,
                          fontWeight: pw.FontWeight.bold,
                          color: azulOscuro)),
                  pw.Text('Generado: $ahora',
                      style: pw.TextStyle(
                          fontSize: 8, color: PdfColors.grey600)),
                ]),
            pw.Divider(color: azulOscuro, thickness: 2),
            pw.SizedBox(height: 4),
          ]),
      footer: (ctx) => pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          children: [
            pw.Text('Fiscalía General - Sistema de Transporte',
                style: pw.TextStyle(fontSize: 8, color: PdfColors.grey600)),
            pw.Text('Página ${ctx.pageNumber} de ${ctx.pagesCount}',
                style: pw.TextStyle(fontSize: 8, color: PdfColors.grey600)),
          ]),
      build: (ctx) => [
        // KPIs resumen
        pw.Container(
          padding: const pw.EdgeInsets.all(12),
          decoration: pw.BoxDecoration(
              color: gris, borderRadius: pw.BorderRadius.circular(6)),
          child: pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceAround,
              children: [
                _kpiPdfWidget(
                    'Total Carpetas', '${stats.totalCarpetas}', azulOscuro),
                _kpiPdfWidget('Conductores',
                    '${stats.diligenciasPorConductor.length}', azulOscuro),
                _kpiPdfWidget('Vehículos',
                    '${stats.combustiblePorVehiculo.length}', azulOscuro),
                _kpiPdfWidget('Fiscalías',
                    '${stats.carpetasPorFiscalia.length}', azulOscuro),
              ]),
        ),

        // Sección 1
        seccion('1. Conductores con Más Diligencias'),
        pw.Table(
          border:
              pw.TableBorder.all(color: PdfColors.grey300, width: 0.5),
          columnWidths: {
            0: const pw.FlexColumnWidth(3),
            1: const pw.FlexColumnWidth(1.5),
            2: const pw.FlexColumnWidth(1.5),
          },
          children: [
            headerRow(['Conductor', 'Diligencias', '% del Total']),
            ...topConductoresDilig.asMap().entries.map((e) {
              final total = stats.diligenciasPorConductor.values
                  .fold(0, (a, b) => a + b);
              final pct =
                  total > 0 ? (e.value.value / total * 100).toStringAsFixed(1) : '0';
              return dataRow(
                  [e.value.key, '${e.value.value}', '$pct%'],
                  e.key.isOdd);
            }),
          ],
        ),

        // Sección 2
        seccion('2. Conductores con Mayor Distancia Recorrida'),
        pw.Table(
          border:
              pw.TableBorder.all(color: PdfColors.grey300, width: 0.5),
          columnWidths: {
            0: const pw.FlexColumnWidth(3),
            1: const pw.FlexColumnWidth(2),
          },
          children: [
            headerRow(['Conductor', 'Kilómetros Totales']),
            ...topConductoresKm.asMap().entries.map((e) => dataRow(
                [e.value.key, '${e.value.value.toStringAsFixed(2)} km'],
                e.key.isOdd)),
          ],
        ),

        // Sección 3
        seccion('3. Vehículos con Mayor Consumo de Combustible'),
        pw.Table(
          border:
              pw.TableBorder.all(color: PdfColors.grey300, width: 0.5),
          columnWidths: {
            0: const pw.FlexColumnWidth(2),
            1: const pw.FlexColumnWidth(2),
          },
          children: [
            headerRow(['Placa / Vehículo', 'Litros Consumidos']),
            ...topVehiculos.asMap().entries.map((e) => dataRow(
                [e.value.key, '${e.value.value.toStringAsFixed(2)} L'],
                e.key.isOdd)),
          ],
        ),

        // Sección 4
        seccion('4. Fiscalías con Más Diligencias'),
        pw.Table(
          border:
              pw.TableBorder.all(color: PdfColors.grey300, width: 0.5),
          columnWidths: {
            0: const pw.FlexColumnWidth(3),
            1: const pw.FlexColumnWidth(1.5),
          },
          children: [
            headerRow(['Fiscalía', 'Carpetas Diligenciadas']),
            ...topFiscalias.asMap().entries.map((e) => dataRow(
                [e.value.key, '${e.value.value}'], e.key.isOdd)),
          ],
        ),

        // Sección 5 — total
        seccion('5. Total de Carpetas Diligenciadas'),
        pw.Container(
          padding: const pw.EdgeInsets.all(14),
          decoration: pw.BoxDecoration(
              color: azulClaro,
              borderRadius: pw.BorderRadius.circular(6)),
          child: pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.center,
              children: [
                pw.Text('Total General de Carpetas: ',
                    style: pw.TextStyle(fontSize: 13, color: azulOscuro)),
                pw.Text('${stats.totalCarpetas}',
                    style: pw.TextStyle(
                        fontSize: 18,
                        fontWeight: pw.FontWeight.bold,
                        color: azulOscuro)),
              ]),
        ),
      ],
    ));

    final dir = await getTemporaryDirectory();
    final file = File(
        '${dir.path}/estadisticas_${DateTime.now().millisecondsSinceEpoch}.pdf');
    await file.writeAsBytes(await pdf.save());
    await OpenFile.open(file.path);

    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('PDF generado correctamente'),
          backgroundColor: Color(0xFF003580),
        ),
      );
    }
  }

  pw.Widget _kpiPdfWidget(String titulo, String valor, PdfColor color) =>
      pw.Column(children: [
        pw.Text(valor,
            style: pw.TextStyle(
                fontSize: 20,
                fontWeight: pw.FontWeight.bold,
                color: color)),
        pw.Text(titulo,
            style:
                pw.TextStyle(fontSize: 8, color: PdfColors.grey700)),
      ]);

  @override
  Widget build(BuildContext context) => IconButton(
        tooltip: 'Exportar PDF',
        icon: _generando
            ? const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                    color: Colors.white, strokeWidth: 2),
              )
            : const Icon(Icons.picture_as_pdf),
        onPressed: _generar,
      );
}