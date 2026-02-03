import 'package:flutter/material.dart';
import 'core/app/app.dart';
import 'core/app/app_services.dart';

void main() {
  final services = AppServices.create();
  runApp(SoundboardApp(services: services));
}
