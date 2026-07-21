import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'screens/explorer_screen.dart';
import 'services/fs_service.dart';
import 'services/search_index.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  final index = SearchIndexService();
  String cacheFile;
  try {
    final support = await getApplicationSupportDirectory();
    cacheFile = p.join(support.path, 'rover_index.txt');
  } catch (_) {
    cacheFile = p.join(Directory.systemTemp.path, 'rover_index.txt');
  }

  // Index the user's home tree for instant Everything-style search; other
  // locations can still be browsed normally and searched via "current folder"
  // once visited (they get indexed on rescan if under a chosen root).
  await index.start(roots: [FsService.homeDir], cacheFile: cacheFile);

  runApp(RoverExplorerApp(index: index));
}

class RoverExplorerApp extends StatelessWidget {
  final SearchIndexService index;
  const RoverExplorerApp({super.key, required this.index});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Rover Explorer',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: false,
        fontFamily: 'Tahoma',
        scrollbarTheme: ScrollbarThemeData(
          thumbVisibility: const WidgetStatePropertyAll(true),
          thumbColor: const WidgetStatePropertyAll(Color(0xFFC8C4B8)),
          radius: const Radius.circular(2),
          thickness: const WidgetStatePropertyAll(12),
        ),
      ),
      home: Scaffold(
        backgroundColor: const Color(0xFFECE9D8),
        body: ExplorerScreen(index: index),
      ),
    );
  }
}
