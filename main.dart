import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';

const appName = 'REELBOX'; // rename me
const ch = MethodChannel('saf_test');

// ---------------------------------------------------------------- models
class Vid {
  final String name, uri, folder;
  final int size;
  Vid(this.name, this.uri, this.size, this.folder);
  String get ext {
    final i = name.lastIndexOf('.');
    return i > 0 ? name.substring(i + 1).toUpperCase() : '';
  }

  String get title {
    var t = name;
    final i = t.lastIndexOf('.');
    if (i > 0) t = t.substring(0, i);
    return t.replaceAll('_', ' ').replaceAll('.', ' ').trim();
  }
}

class Sys {
  final String title, kind, key;
  const Sys(this.title, this.kind, this.key);
}

class Th {
  final String name;
  final Color bg, panel, accent, text, sub;
  final double sat, light;
  const Th(this.name, this.bg, this.panel, this.accent, this.text, this.sub,
      this.sat, this.light);
}

const themes = [
  Th('Classic Dark', Color(0xFF1B1F2A), Color(0xFF262B3A), Color(0xFF4FC3F7),
      Color(0xFFECEFF4), Color(0xFF9AA3B5), 0.5, 0.35),
  Th('Retro Green', Color(0xFF0B140B), Color(0xFF132213), Color(0xFF5CFF5C),
      Color(0xFFD6FFD6), Color(0xFF6FA06F), 0.6, 0.25),
  Th('Sunset', Color(0xFF2A1420), Color(0xFF3A1D2C), Color(0xFFFF8A65),
      Color(0xFFFFEFE8), Color(0xFFC79A9A), 0.65, 0.40),
  Th('AMOLED', Color(0xFF000000), Color(0xFF111111), Color(0xFFFFFFFF),
      Color(0xFFFFFFFF), Color(0xFF8A8A8A), 0.0, 0.25),
  Th('Light', Color(0xFFF2F4F8), Color(0xFFFFFFFF), Color(0xFF1565C0),
      Color(0xFF1B1F2A), Color(0xFF5A6478), 0.45, 0.55),
];

String fmt(int b) {
  if (b >= 1 << 30) return '${(b / (1 << 30)).toStringAsFixed(1)} GB';
  if (b >= 1 << 20) return '${(b / (1 << 20)).toStringAsFixed(0)} MB';
  return '${(b / 1024).toStringAsFixed(0)} KB';
}

LinearGradient gradFor(Th th, String label) {
  final h = (label.codeUnits.fold<int>(7, (a, b) => (a * 31 + b) & 0x7fffffff) % 360)
      .toDouble();
  final c1 = HSLColor.fromAHSL(1, h, th.sat, th.light).toColor();
  final c2 = HSLColor.fromAHSL(1, (h + 45) % 360, th.sat, th.light + 0.12).toColor();
  return LinearGradient(
      begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [c1, c2]);
}

// ---------------------------------------------------------------- store
class Store extends ChangeNotifier {
  String dir = '';
  List<Map<String, String>> folders = [];
  Set<String> favs = {};
  Map<String, List<String>> playlists = {};
  List<String> recent = [];
  String themeName = 'Classic Dark';
  String sort = 'name_asc';
  Map<String, List<Vid>> scanned = {};
  bool loading = false;

  Th get th => themes.firstWhere((t) => t.name == themeName, orElse: () => themes[0]);

  Future<void> init() async {
    try {
      dir = await ch.invokeMethod<String>('dataDir') ?? '';
      final f = File('$dir/state.json');
      if (await f.exists()) {
        final j = jsonDecode(await f.readAsString()) as Map<String, dynamic>;
        folders = (j['folders'] as List? ?? [])
            .map((e) => Map<String, String>.from(e as Map))
            .toList();
        favs = Set<String>.from(j['favs'] as List? ?? []);
        recent = List<String>.from(j['recent'] as List? ?? []);
        themeName = (j['theme'] as String?) ?? themeName;
        sort = (j['sort'] as String?) ?? sort;
        playlists = (j['playlists'] as Map? ?? {}).map<String, List<String>>(
            (k, v) => MapEntry(k as String, List<String>.from(v as List)));
      }
    } catch (_) {}
    notifyListeners();
    rescanAll();
  }

  Future<void> save() async {
    try {
      await File('$dir/state.json').writeAsString(jsonEncode({
        'folders': folders,
        'favs': favs.toList(),
        'recent': recent,
        'theme': themeName,
        'sort': sort,
        'playlists': playlists,
      }));
    } catch (_) {}
  }

  void _changed() {
    save();
    notifyListeners();
  }

  Future<void> rescanAll() async {
    loading = true;
    notifyListeners();
    for (final f in folders) {
      await rescan(f['uri']!, quiet: true);
    }
    loading = false;
    notifyListeners();
  }

  Future<void> rescan(String uri, {bool quiet = false}) async {
    if (!quiet) {
      loading = true;
      notifyListeners();
    }
    try {
      final res = await ch.invokeMethod<List<dynamic>>('scan', {'uri': uri});
      scanned[uri] = (res ?? []).map((e) {
        final m = e as Map;
        return Vid(m['name'] as String, m['uri'] as String,
            (m['size'] as num).toInt(), uri);
      }).toList();
    } catch (_) {
      scanned[uri] = [];
    }
    if (!quiet) {
      loading = false;
      notifyListeners();
    }
  }

  Future<void> addFolder() async {
    final uri = await ch.invokeMethod<String>('pickFolder');
    if (uri == null || folders.any((f) => f['uri'] == uri)) return;
    var name = Uri.decodeComponent(uri.split('/').last);
    if (name.contains(':')) name = name.split(':').last;
    if (name.contains('/')) name = name.split('/').last;
    if (name.isEmpty) name = 'Storage';
    folders.add({'name': name, 'uri': uri});
    _changed();
    await rescan(uri);
  }

  void removeFolder(String uri) {
    folders.removeWhere((f) => f['uri'] == uri);
    scanned.remove(uri);
    _changed();
  }

  void createPlaylist(String name) {
    playlists.putIfAbsent(name, () => []);
    _changed();
  }

  void deletePlaylist(String name) {
    playlists.remove(name);
    _changed();
  }

  void addToPlaylist(String name, String uri) {
    final l = playlists.putIfAbsent(name, () => []);
    if (!l.contains(uri)) l.add(uri);
    _changed();
  }

  void removeFromPlaylist(String name, String uri) {
    playlists[name]?.remove(uri);
    _changed();
  }

  void toggleFav(String uri) {
    if (!favs.remove(uri)) favs.add(uri);
    _changed();
  }

  void addRecent(String uri) {
    recent.remove(uri);
    recent.insert(0, uri);
    if (recent.length > 30) recent = recent.sublist(0, 30);
    _changed();
  }

  void setTheme(String n) {
    themeName = n;
    _changed();
  }

  void setSort(String s) {
    sort = s;
    _changed();
  }

  Map<String, Vid> get index {
    final m = <String, Vid>{};
    for (final l in scanned.values) {
      for (final v in l) {
        m[v.uri] = v;
      }
    }
    return m;
  }

  List<Sys> get systems => [
        const Sys('All Videos', 'all', ''),
        const Sys('Favourites', 'favs', ''),
        const Sys('Recently Played', 'recent', ''),
        for (final f in folders) Sys(f['name']!, 'folder', f['uri']!),
        for (final p in playlists.keys) Sys(p, 'playlist', p),
      ];

  List<Vid> sorted(List<Vid> l) {
    final r = [...l];
    int byName(Vid a, Vid b) => a.title.toLowerCase().compareTo(b.title.toLowerCase());
    if (sort == 'added') return r;
    if (sort == 'name_desc') {
      r.sort((a, b) => byName(b, a));
    } else if (sort == 'size_desc') {
      r.sort((a, b) => b.size.compareTo(a.size));
    } else if (sort == 'size_asc') {
      r.sort((a, b) => a.size.compareTo(b.size));
    } else if (sort == 'fav') {
      r.sort((a, b) {
        final fa = favs.contains(a.uri) ? 0 : 1;
        final fb = favs.contains(b.uri) ? 0 : 1;
        return fa != fb ? fa - fb : byName(a, b);
      });
    } else {
      r.sort(byName);
    }
    return r;
  }

  List<Vid> itemsFor(Sys y) {
    final idx = index;
    List<Vid> l;
    if (y.kind == 'all') {
      l = idx.values.toList();
    } else if (y.kind == 'favs') {
      l = favs.map((u) => idx[u]).whereType<Vid>().toList();
    } else if (y.kind == 'recent') {
      return recent.map((u) => idx[u]).whereType<Vid>().toList();
    } else if (y.kind == 'folder') {
      l = idx.values.where((v) => v.folder == y.key).toList();
    } else {
      l = (playlists[y.key] ?? []).map((u) => idx[u]).whereType<Vid>().toList();
    }
    return sorted(l);
  }
}

// ---------------------------------------------------------------- helpers
Future<String?> askText(BuildContext context, String title) {
  final t = TextEditingController();
  return showDialog<String>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(title),
      content: TextField(controller: t, autofocus: true),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
        TextButton(
            onPressed: () => Navigator.pop(ctx, t.text.trim()),
            child: const Text('OK')),
      ],
    ),
  );
}

Future<void> addToPlaylistDialog(BuildContext context, Store s, Vid v) async {
  final pick = await showDialog<String>(
    context: context,
    builder: (ctx) => SimpleDialog(
      title: const Text('Add to playlist'),
      children: [
        for (final n in s.playlists.keys)
          SimpleDialogOption(onPressed: () => Navigator.pop(ctx, n), child: Text(n)),
        SimpleDialogOption(
            onPressed: () => Navigator.pop(ctx, '\u0000new'),
            child: const Text('+ New playlist')),
      ],
    ),
  );
  if (pick == null) return;
  var name = pick;
  if (pick == '\u0000new') {
    if (!context.mounted) return;
    final n = await askText(context, 'Playlist name');
    if (n == null || n.isEmpty) return;
    name = n;
  }
  s.addToPlaylist(name, v.uri);
}

Future<void> themeDialog(BuildContext context, Store s) {
  return showDialog<void>(
    context: context,
    builder: (ctx) => SimpleDialog(
      title: const Text('Theme'),
      children: [
        for (final t in themes)
          SimpleDialogOption(
            onPressed: () {
              s.setTheme(t.name);
              Navigator.pop(ctx);
            },
            child: Row(children: [
              Container(width: 18, height: 18, color: t.accent),
              const SizedBox(width: 12),
              Text(t.name),
            ]),
          ),
      ],
    ),
  );
}

IconData iconFor(String kind) {
  switch (kind) {
    case 'all':
      return Icons.video_library;
    case 'favs':
      return Icons.star;
    case 'recent':
      return Icons.history;
    case 'folder':
      return Icons.folder;
    default:
      return Icons.queue_music;
  }
}

// ---------------------------------------------------------------- app
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  MediaKit.ensureInitialized();
  final s = Store();
  await s.init();
  runApp(MaterialApp(debugShowCheckedModeBanner: false, home: HomeScreen(s)));
}

// ---------------------------------------------------------------- home
class HomeScreen extends StatefulWidget {
  final Store s;
  const HomeScreen(this.s, {super.key});
  @override
  State<HomeScreen> createState() => _HomeState();
}

class _HomeState extends State<HomeScreen> {
  final pc = PageController(viewportFraction: 0.62);
  int idx = 0;

  @override
  Widget build(BuildContext context) {
    final s = widget.s;
    return ListenableBuilder(
      listenable: s,
      builder: (context, _) {
        final th = s.th;
        final sys = s.systems;
        if (idx >= sys.length) idx = sys.length - 1;
        final cur = sys[idx];
        return Scaffold(
          backgroundColor: th.bg,
          body: SafeArea(
            child: Column(children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
                child: Row(children: [
                  Text(appName,
                      style: TextStyle(
                          color: th.accent,
                          fontSize: 22,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 3)),
                  const Spacer(),
                  if (s.loading)
                    SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2, color: th.accent)),
                ]),
              ),
              Expanded(
                child: PageView.builder(
                  controller: pc,
                  itemCount: sys.length,
                  onPageChanged: (i) => setState(() => idx = i),
                  itemBuilder: (_, i) {
                    final y = sys[i];
                    final on = i == idx;
                    return GestureDetector(
                      onTap: () {
                        if (on) {
                          Navigator.push(context,
                              MaterialPageRoute(builder: (_) => ListScreen(s, y)));
                        } else {
                          pc.animateToPage(i,
                              duration: const Duration(milliseconds: 250),
                              curve: Curves.easeOut);
                        }
                      },
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 200),
                        margin: EdgeInsets.symmetric(horizontal: 8, vertical: on ? 30 : 80),
                        decoration: BoxDecoration(
                          gradient: gradFor(th, y.title),
                          borderRadius: BorderRadius.circular(18),
                          border: on ? Border.all(color: th.accent, width: 3) : null,
                        ),
                        padding: const EdgeInsets.all(14),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(iconFor(y.kind), size: on ? 64 : 40, color: Colors.white),
                            const SizedBox(height: 12),
                            Text(y.title,
                                textAlign: TextAlign.center,
                                maxLines: 3,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.w800,
                                    fontSize: on ? 22 : 15)),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
              Text('${s.itemsFor(cur).length} videos',
                  style: TextStyle(color: th.sub, fontSize: 14)),
              const SizedBox(height: 8),
              Wrap(
                alignment: WrapAlignment.center,
                spacing: 4,
                children: [
                  TextButton.icon(
                      onPressed: s.addFolder,
                      icon: const Icon(Icons.create_new_folder),
                      label: const Text('Folder')),
                  TextButton.icon(
                      onPressed: () async {
                        final n = await askText(context, 'Playlist name');
                        if (n != null && n.isNotEmpty) s.createPlaylist(n);
                      },
                      icon: const Icon(Icons.playlist_add),
                      label: const Text('Playlist')),
                  TextButton.icon(
                      onPressed: () => themeDialog(context, s),
                      icon: const Icon(Icons.palette),
                      label: const Text('Theme')),
                  TextButton.icon(
                      onPressed: s.rescanAll,
                      icon: const Icon(Icons.refresh),
                      label: const Text('Rescan')),
                ],
              ),
              const SizedBox(height: 10),
            ]),
          ),
        );
      },
    );
  }
}

// ---------------------------------------------------------------- list
class ListScreen extends StatefulWidget {
  final Store s;
  final Sys sys;
  const ListScreen(this.s, this.sys, {super.key});
  @override
  State<ListScreen> createState() => _ListState();
}

class _ListState extends State<ListScreen> {
  int sel = 0;

  void play(Vid v) {
    widget.s.addRecent(v.uri);
    Navigator.push(context, MaterialPageRoute(builder: (_) => PlayerScreen(v)));
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.s;
    final sys = widget.sys;
    return ListenableBuilder(
      listenable: s,
      builder: (context, _) {
        final th = s.th;
        final items = s.itemsFor(sys);
        if (sel >= items.length) sel = items.isEmpty ? 0 : items.length - 1;
        final cur = items.isEmpty ? null : items[sel];
        return Scaffold(
          backgroundColor: th.bg,
          body: SafeArea(
            child: Column(children: [
              Row(children: [
                IconButton(
                    icon: Icon(Icons.arrow_back, color: th.text),
                    onPressed: () => Navigator.pop(context)),
                Expanded(
                    child: Text(sys.title,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                            color: th.text, fontSize: 18, fontWeight: FontWeight.w800))),
                PopupMenuButton<String>(
                  icon: Icon(Icons.sort, color: th.text),
                  onSelected: s.setSort,
                  itemBuilder: (_) => const [
                    PopupMenuItem(value: 'name_asc', child: Text('Name A-Z')),
                    PopupMenuItem(value: 'name_desc', child: Text('Name Z-A')),
                    PopupMenuItem(value: 'size_desc', child: Text('Largest first')),
                    PopupMenuItem(value: 'size_asc', child: Text('Smallest first')),
                    PopupMenuItem(value: 'fav', child: Text('Favourites first')),
                    PopupMenuItem(value: 'added', child: Text('Order added')),
                  ],
                ),
                if (sys.kind == 'folder') ...[
                  IconButton(
                      icon: Icon(Icons.refresh, color: th.text),
                      onPressed: () => s.rescan(sys.key)),
                  IconButton(
                      icon: Icon(Icons.delete_outline, color: th.text),
                      onPressed: () {
                        s.removeFolder(sys.key);
                        Navigator.pop(context);
                      }),
                ],
                if (sys.kind == 'playlist')
                  IconButton(
                      icon: Icon(Icons.delete_outline, color: th.text),
                      onPressed: () {
                        s.deletePlaylist(sys.key);
                        Navigator.pop(context);
                      }),
              ]),
              if (cur != null)
                Container(
                  margin: const EdgeInsets.fromLTRB(12, 0, 12, 8),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                      color: th.panel, borderRadius: BorderRadius.circular(14)),
                  child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Container(
                      width: 110,
                      height: 110,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                          gradient: gradFor(th, cur.title),
                          borderRadius: BorderRadius.circular(10)),
                      child: Text(
                          cur.title.isEmpty ? '?' : cur.title.characters.first.toUpperCase(),
                          style: const TextStyle(
                              color: Colors.white, fontSize: 56, fontWeight: FontWeight.w900)),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(cur.title,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                                color: th.text, fontSize: 16, fontWeight: FontWeight.w800)),
                        const SizedBox(height: 4),
                        Text('${cur.ext}  •  ${fmt(cur.size)}',
                            style: TextStyle(color: th.sub, fontSize: 13)),
                        if (s.playlists.entries.any((e) => e.value.contains(cur.uri)))
                          Text(
                              'In: ${s.playlists.entries.where((e) => e.value.contains(cur.uri)).map((e) => e.key).join(', ')}',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(color: th.sub, fontSize: 12)),
                        const SizedBox(height: 6),
                        Wrap(spacing: 4, children: [
                          ElevatedButton.icon(
                              onPressed: () => play(cur),
                              icon: const Icon(Icons.play_arrow),
                              label: const Text('Play')),
                          IconButton(
                              icon: Icon(
                                  s.favs.contains(cur.uri) ? Icons.star : Icons.star_border,
                                  color: th.accent),
                              onPressed: () => s.toggleFav(cur.uri)),
                          IconButton(
                              icon: Icon(Icons.playlist_add, color: th.accent),
                              onPressed: () => addToPlaylistDialog(context, s, cur)),
                          if (sys.kind == 'playlist')
                            IconButton(
                                icon: Icon(Icons.remove_circle_outline, color: th.accent),
                                onPressed: () => s.removeFromPlaylist(sys.key, cur.uri)),
                        ]),
                      ]),
                    ),
                  ]),
                ),
              Expanded(
                child: items.isEmpty
                    ? Center(
                        child: Text('Nothing here yet', style: TextStyle(color: th.sub)))
                    : ListView.builder(
                        itemCount: items.length,
                        itemBuilder: (_, i) {
                          final v = items[i];
                          final on = i == sel;
                          return InkWell(
                            onTap: () => setState(() => sel = i),
                            onDoubleTap: () => play(v),
                            child: Container(
                              height: 54,
                              color: on ? th.accent.withAlpha(45) : Colors.transparent,
                              padding: const EdgeInsets.symmetric(horizontal: 16),
                              child: Row(children: [
                                SizedBox(
                                    width: 22,
                                    child: s.favs.contains(v.uri)
                                        ? Icon(Icons.star, size: 16, color: th.accent)
                                        : null),
                                Expanded(
                                    child: Text(v.title,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(
                                            color: on ? th.accent : th.text,
                                            fontWeight:
                                                on ? FontWeight.w800 : FontWeight.w500))),
                                Text(fmt(v.size),
                                    style: TextStyle(color: th.sub, fontSize: 12)),
                              ]),
                            ),
                          );
                        },
                      ),
              ),
            ]),
          ),
        );
      },
    );
  }
}

// ---------------------------------------------------------------- player
class PlayerScreen extends StatefulWidget {
  final Vid v;
  const PlayerScreen(this.v, {super.key});
  @override
  State<PlayerScreen> createState() => _PlayerState();
}

class _PlayerState extends State<PlayerScreen> {
  final player = Player();
  late final controller = VideoController(player);
  String? err;

  @override
  void initState() {
    super.initState();
    player.stream.error.listen((e) {
      if (mounted) setState(() => err = e);
    });
    _open();
  }

  Future<void> _open() async {
    try {
      final fd = await ch.invokeMethod<int>('openFd', {'uri': widget.v.uri});
      await player.open(Media('fd://$fd'));
    } catch (e) {
      if (mounted) setState(() => err = '$e');
    }
  }

  @override
  void dispose() {
    player.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(children: [
        Positioned.fill(child: Video(controller: controller)),
        SafeArea(
          child: Align(
            alignment: Alignment.topLeft,
            child: IconButton(
                icon: const Icon(Icons.arrow_back, color: Colors.white),
                onPressed: () => Navigator.pop(context)),
          ),
        ),
        if (err != null)
          Center(
              child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Text(err!, style: const TextStyle(color: Colors.white)))),
      ]),
    );
  }
}
