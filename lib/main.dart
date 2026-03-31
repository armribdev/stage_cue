import 'package:flutter/material.dart';
import 'package:flutter_soloud/flutter_soloud.dart';
import 'core/app/app.dart';
import 'core/app/app_services.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await SoLoud.instance.init(
    bufferSize: 1024, // Latence réduite pour soundboard réactif
  );
  final services = AppServices.create();
  runApp(SoundboardApp(services: services));
}
