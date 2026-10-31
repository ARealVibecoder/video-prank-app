import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  MediaKit.ensureInitialized();
  runApp(const MaterialApp(home: TestPage()));
}

class TestPage extends StatefulWidget {
  const TestPage({super.key});
  @override
  State<TestPage> createState() => _TestPageState();
}

class _TestPageState extends State<TestPage> {
  static const _ch = MethodChannel('saf_test');
  final player = Player();
  late final controller = VideoController(player);
  String status = 'Tap the button and pick an mkv/avi/mov/mp4';

  @override
  void initState() {
    super.initState();
    player.stream.error.listen((e) => setState(() => status = 'ERROR: $e'));
    player.stream.duration.listen((d) {
      if (d > Duration.zero) setState(() => status = 'OK, duration $d');
    });
  }

  Future<void> pick() async {
    try {
      final res = await _ch.invokeMapMethod<String, dynamic>('pick');
      if (res == null) return;
      // fd:// lets libmpv read the SAF file through a file descriptor.
      await player.open(Media('fd://${res['fd']}'));
      setState(() => status = 'Opened ${res['name']}\n${res['uri']}');
    } catch (e) {
      setState(() => status = 'Pick failed: $e');
    }
  }

  @override
  void dispose() {
    player.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('SAF playback test')),
        body: Column(children: [
          AspectRatio(aspectRatio: 16 / 9, child: Video(controller: controller)),
          Padding(padding: const EdgeInsets.all(12), child: Text(status)),
          ElevatedButton(onPressed: pick, child: const Text('Pick video')),
        ]),
      );
}
