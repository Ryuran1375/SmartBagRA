import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:google_maps_flutter/google_maps_flutter.dart';

void main() => runApp(const MyApp());

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  LatLng? currentLocation;
  bool buzzerOn = false;
  final String arduinoIP = "0.0.0.0";
  Timer? locationTimer;

  // Coordenadas de vista previa: Reynosa, Tamaulipas
  static const LatLng reynosaCenter = LatLng(26.0924, -98.2770);
  static const double previewZoom = 12.0;
  static const double gpsZoom = 15.0;

  final Completer<GoogleMapController> _controller = Completer();
  bool _movedToGps = false;

  @override
  void initState() {
    super.initState();
    // Poll GPS cada 15 segundos
    locationTimer = Timer.periodic(const Duration(seconds: 15), (_) {
      fetchLocation();
    });

    // Intentar obtener ubicación inmediatamente al iniciar
    fetchLocation();
  }

  @override
  void dispose() {
    locationTimer?.cancel();
    super.dispose();
  }

  bool _locationChanged(LatLng? oldLoc, LatLng newLoc) {
    if (oldLoc == null) return true;
    const threshold = 0.0001; // pequeño umbral para evitar micro-diferencias
    return (oldLoc.latitude - newLoc.latitude).abs() > threshold ||
        (oldLoc.longitude - newLoc.longitude).abs() > threshold;
  }

  Future<void> fetchLocation() async {
    try {
      final res = await http
          .get(Uri.parse('http://$arduinoIP/location'))
          .timeout(const Duration(seconds: 3));
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        // Asegurar que se parsean como double
        final lat = (data['lat'] is num)
            ? (data['lat'] as num).toDouble()
            : double.tryParse('${data['lat']}');
        final lon = (data['lon'] is num)
            ? (data['lon'] as num).toDouble()
            : double.tryParse('${data['lon']}');

        if (lat != null && lon != null) {
          final newLocation = LatLng(lat, lon);
          if (_locationChanged(currentLocation, newLocation)) {
            setState(() {
              currentLocation = newLocation;
            });
            // Animar la cámara a la nueva ubicación si aún no se hizo
            if (!_movedToGps) {
              _moveCameraTo(newLocation, zoom: gpsZoom);
              _movedToGps = true;
            } else {
              // Si ya se movió antes, simplemente actualizar marcador (no es necesario animar)
            }
          }
        } else {
          debugPrint("Respuesta de GPS inválida: $data");
        }
      } else {
        debugPrint("Error HTTP: ${res.statusCode}");
      }
    } catch (e) {
      debugPrint("Error al obtener GPS: $e");
    }
  }

  Future<void> _moveCameraTo(LatLng target, {double zoom = gpsZoom}) async {
    try {
      final controller = await _controller.future;
      await controller.animateCamera(
        CameraUpdate.newCameraPosition(
          CameraPosition(target: target, zoom: zoom),
        ),
      );
    } catch (e) {
      debugPrint("Error al mover cámara: $e");
    }
  }

  Future<void> toggleBuzzer() async {
    final newState = !buzzerOn;
    final stateStr = newState ? 'on' : 'off';

    try {
      final res = await http
          .post(Uri.parse('http://$arduinoIP/buzzer?state=$stateStr'))
          .timeout(const Duration(seconds: 3));

      if (res.statusCode == 200) {
        setState(() {
          buzzerOn = newState;
        });
      } else {
        debugPrint("Error HTTP al cambiar buzzer: ${res.statusCode}");
      }
    } catch (e) {
      debugPrint("Error al cambiar buzzer: $e");
    }
  }

  @override
  Widget build(BuildContext context) {
    final initialCamera = CameraPosition(
      target: reynosaCenter,
      zoom: previewZoom,
    );

    final marker = Marker(
      markerId: const MarkerId('gps'),
      position: currentLocation ?? reynosaCenter,
      infoWindow: InfoWindow(
        title: currentLocation == null
            ? 'Reynosa (vista previa)'
            : 'Ubicación GPS',
      ),
    );

    return MaterialApp(
      home: Scaffold(
        appBar: AppBar(title: const Text('Smartbag - Tracker')),
        body: Stack(
          children: [
            GoogleMap(
              initialCameraPosition: initialCamera,
              markers: {marker},
              myLocationEnabled: false,
              myLocationButtonEnabled: true,
              onMapCreated: (GoogleMapController controller) {
                if (!_controller.isCompleted) {
                  _controller.complete(controller);
                }
                // Si ya tenemos GPS cuando se crea el mapa, mover cámara al GPS
                if (currentLocation != null && !_movedToGps) {
                  _moveCameraTo(currentLocation!, zoom: gpsZoom);
                  _movedToGps = true;
                }
              },
            ),
            Positioned(
              left: 12,
              top: 12,
              right: 12,
              child: Card(
                color: Colors.white70,
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 8,
                  ),
                  child: Row(
                    children: [
                      Icon(
                        currentLocation == null ? Icons.map : Icons.gps_fixed,
                        color: currentLocation == null
                            ? Colors.orange
                            : Colors.green,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          currentLocation == null
                              ? 'Vista previa: Reynosa, Tamps — esperando señal GPS...'
                              : 'GPS encontrado — Lat ${currentLocation!.latitude.toStringAsFixed(5)}, Lon ${currentLocation!.longitude.toStringAsFixed(5)}',
                          style: const TextStyle(fontSize: 14),
                        ),
                      ),
                      IconButton(
                        tooltip: 'Recentrar a Reynosa',
                        onPressed: () {
                          _moveCameraTo(reynosaCenter, zoom: previewZoom);
                          _movedToGps = false;
                        },
                        icon: const Icon(Icons.location_city),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
        floatingActionButton: FloatingActionButton(
          onPressed: toggleBuzzer,
          backgroundColor: buzzerOn ? Colors.red : Colors.green,
          child: Icon(
            buzzerOn ? Icons.notifications_active : Icons.notifications_off,
          ),
        ),
      ),
    );
  }
}
