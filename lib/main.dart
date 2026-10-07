import 'package:flutter/material.dart';

import 'screens/gallery_screen.dart';
import 'settings.dart';
import 'storage/home_server_backend.dart';
import 'storage/storage_backend.dart';

typedef BackendFactory = StorageBackend Function(ServerSettings settings);

StorageBackend _homeServer(ServerSettings s) =>
    HomeServerBackend(serverUrl: s.serverUrl, token: s.token);

void main() {
  runApp(const CloudApp());
}

class CloudApp extends StatelessWidget {
  final BackendFactory backendFactory;

  const CloudApp({super.key, this.backendFactory = _homeServer});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Моё облако',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(colorScheme: ColorScheme.fromSeed(seedColor: Colors.blue)),
      darkTheme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.blue, brightness: Brightness.dark),
      ),
      home: GalleryScreen(backendFactory: backendFactory),
    );
  }
}
