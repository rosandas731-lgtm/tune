import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';
import 'package:just_audio_background/just_audio_background.dart';
import 'package:youtube_explode_dart/youtube_explode_dart.dart';

const green = Color(0xFF1DB954);
const bg = Color(0xFF0B0B0B);
const card = Color(0xFF181818);

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await JustAudioBackground.init(
    androidNotificationChannelId: 'com.tune.audio.playback',
    androidNotificationChannelName: 'Tune playback',
    androidNotificationOngoing: true,
  );
  runApp(const TuneApp());
}

String fmt(Duration? d) {
  final s = d?.inSeconds ?? 0;
  return '${s ~/ 60}:${(s % 60).toString().padLeft(2, '0')}';
}

/// All app state: search results/queue, current song, suggestions, playback.
class Controller extends ChangeNotifier {
  final yt = YoutubeExplode();
  final player = AudioPlayer();
  List<Video> queue = [];
  List<Video> suggestions = [];
  int index = -1;
  int _token = 0;
  bool loadingSuggestions = false;
  String status = 'Search for a song or artist.';

  Video? get current => index >= 0 && index < queue.length ? queue[index] : null;

  Controller() {
    player.processingStateStream.listen((s) {
      if (s == ProcessingState.completed) next();
    });
  }

  Future<void> search(String q) async {
    if (q.trim().isEmpty) return;
    status = 'Searching...';
    notifyListeners();
    try {
      final r = await yt.search.search(q);
      queue = r.toList();
      index = -1;
      status = queue.isEmpty ? 'No results.' : 'Results for "$q"';
    } catch (_) {
      status = 'Search failed. Check your connection.';
    }
    notifyListeners();
  }

  Future<void> playAt(int i) async {
    if (i < 0 || i >= queue.length) return;
    final t = ++_token;
    index = i;
    status = 'Loading audio...';
    notifyListeners();
    final v = queue[i];
    _loadSuggestions(v, t);
    try {
      // audio-only stream: no video is ever requested
      final m = await yt.videos.streamsClient.getManifest(v.id);
      if (t != _token) return;
      final audio = m.audioOnly.withHighestBitrate();
      await player.setAudioSource(AudioSource.uri(audio.url,
          tag: MediaItem(
            id: v.id.value,
            title: v.title,
            artist: v.author,
            artUri: Uri.parse(v.thumbnails.highResUrl),
          )));
      if (t != _token) return;
      status = 'Playing';
      notifyListeners();
      player.play();
    } catch (_) {
      if (t == _token) {
        status = "Couldn't load that song. Try another.";
        notifyListeners();
      }
    }
  }

  Future<void> _loadSuggestions(Video v, int t) async {
    suggestions = [];
    loadingSuggestions = true;
    notifyListeners();
    List<Video> list = [];
    try {
      final rel = await yt.videos.getRelatedVideos(v);
      list = rel?.toList() ?? [];
    } catch (_) {}
    if (list.isEmpty) {
      try {
        list = (await yt.search.search('${v.author} songs')).toList();
      } catch (_) {}
    }
    if (t != _token) return;
    final seen = queue.map((e) => e.id.value).toSet();
    suggestions = list
        .where((e) =>
            !seen.contains(e.id.value) &&
            (e.duration == null || e.duration!.inMinutes < 12))
        .take(12)
        .toList();
    loadingSuggestions = false;
    notifyListeners();
  }

  Future<void> playSuggestion(Video v) async {
    queue.insert(index + 1, v);
    await playAt(index + 1);
  }

  Future<void> next() async {
    if (index + 1 < queue.length) return playAt(index + 1);
    if (suggestions.isNotEmpty) return playSuggestion(suggestions.first);
  }

  Future<void> prev() async {
    if (player.position.inSeconds > 3) return player.seek(Duration.zero);
    return playAt(index - 1);
  }

  void toggle() => player.playing ? player.pause() : player.play();
}

class TuneApp extends StatelessWidget {
  const TuneApp({super.key});
  @override
  Widget build(BuildContext context) => MaterialApp(
        title: 'Tune',
        debugShowCheckedModeBanner: false,
        theme: ThemeData.dark(useMaterial3: true).copyWith(
          scaffoldBackgroundColor: bg,
          colorScheme: const ColorScheme.dark(primary: green),
          sliderTheme: const SliderThemeData(
            trackHeight: 4,
            activeTrackColor: Colors.white,
            inactiveTrackColor: Colors.white24,
            thumbColor: Colors.white,
            thumbShape: RoundSliderThumbShape(enabledThumbRadius: 6),
            overlayShape: RoundSliderOverlayShape(overlayRadius: 14),
          ),
        ),
        home: const Home(),
      );
}

class Thumb extends StatelessWidget {
  final String url;
  final double size;
  final double radius;
  const Thumb(this.url, {super.key, this.size = 52, this.radius = 8});
  @override
  Widget build(BuildContext context) => ClipRRect(
        borderRadius: BorderRadius.circular(radius),
        child: SizedBox(
          width: size,
          height: size,
          child: Image.network(url,
              fit: BoxFit.cover,
              errorBuilder: (_, __, ___) => Container(
                  color: Colors.white12,
                  child: const Icon(Icons.music_note, color: Colors.white38))),
        ),
      );
}

class SongTile extends StatelessWidget {
  final Video v;
  final bool active;
  final VoidCallback onTap;
  const SongTile(this.v, {super.key, this.active = false, required this.onTap});
  @override
  Widget build(BuildContext context) => ListTile(
        onTap: onTap,
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
        leading: Thumb(v.thumbnails.mediumResUrl),
        title: Text(v.title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
                fontWeight: FontWeight.w600, color: active ? green : Colors.white)),
        subtitle: Text('${v.author}  •  ${fmt(v.duration)}',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(color: Colors.white54, fontSize: 13)),
        trailing: active ? const Icon(Icons.graphic_eq, color: green) : null,
      );
}

class PlayButton extends StatelessWidget {
  final Controller c;
  final double size;
  const PlayButton(this.c, {super.key, this.size = 64});
  @override
  Widget build(BuildContext context) => StreamBuilder<PlayerState>(
        stream: c.player.playerStateStream,
        builder: (_, snap) {
          final playing = snap.data?.playing ?? false;
          final ps = snap.data?.processingState;
          final busy = ps == ProcessingState.loading || ps == ProcessingState.buffering;
          return GestureDetector(
            onTap: c.toggle,
            child: Container(
              width: size,
              height: size,
              decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle),
              child: busy
                  ? Padding(
                      padding: EdgeInsets.all(size * 0.3),
                      child: const CircularProgressIndicator(strokeWidth: 2.5, color: Colors.black))
                  : Icon(playing ? Icons.pause_rounded : Icons.play_arrow_rounded,
                      color: Colors.black, size: size * 0.6),
            ),
          );
        },
      );
}

class Home extends StatefulWidget {
  const Home({super.key});
  @override
  State<Home> createState() => _HomeState();
}

class _HomeState extends State<Home> {
  final c = Controller();
  final ctrl = TextEditingController();

  @override
  void dispose() {
    c.player.dispose();
    c.yt.close();
    super.dispose();
  }

  void openPlayer() => showModalBottomSheet(
        context: context,
        isScrollControlled: true,
        useSafeArea: true,
        backgroundColor: Colors.transparent,
        builder: (_) => PlayerSheet(c),
      );

  @override
  Widget build(BuildContext context) => Scaffold(
        body: SafeArea(
          child: ListenableBuilder(
            listenable: c,
            builder: (_, __) => Column(children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 12),
                child: Row(children: [
                  Container(
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(color: green, borderRadius: BorderRadius.circular(10)),
                    child: const Icon(Icons.music_note_rounded, color: Colors.black, size: 20),
                  ),
                  const SizedBox(width: 10),
                  const Text('Tune',
                      style: TextStyle(fontSize: 24, fontWeight: FontWeight.w800, letterSpacing: -0.5)),
                ]),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: TextField(
                  controller: ctrl,
                  textInputAction: TextInputAction.search,
                  onSubmitted: (q) {
                    FocusScope.of(context).unfocus();
                    c.search(q);
                  },
                  decoration: InputDecoration(
                    hintText: 'Songs, artists, albums',
                    prefixIcon: const Icon(Icons.search_rounded),
                    filled: true,
                    fillColor: const Color(0xFF232323),
                    contentPadding: EdgeInsets.zero,
                    border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 14, 20, 6),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text(c.status,
                      style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
                ),
              ),
              Expanded(
                child: c.queue.isEmpty
                    ? const Center(
                        child: Icon(Icons.headphones_rounded, size: 88, color: Colors.white12))
                    : ListView.builder(
                        itemCount: c.queue.length,
                        itemBuilder: (_, i) => SongTile(c.queue[i],
                            active: i == c.index, onTap: () => c.playAt(i)),
                      ),
              ),
              if (c.current != null) miniPlayer(c.current!),
            ]),
          ),
        ),
      );

  Widget miniPlayer(Video v) => GestureDetector(
        onTap: openPlayer,
        child: Container(
          margin: const EdgeInsets.fromLTRB(8, 4, 8, 8),
          decoration: BoxDecoration(color: card, borderRadius: BorderRadius.circular(14)),
          clipBehavior: Clip.antiAlias,
          child: Column(children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 8, 12, 8),
              child: Row(children: [
                Thumb(v.thumbnails.mediumResUrl, size: 48),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(v.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontWeight: FontWeight.w600)),
                    Text(v.author,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(color: Colors.white54, fontSize: 12)),
                  ]),
                ),
                PlayButton(c, size: 40),
                IconButton(onPressed: c.next, icon: const Icon(Icons.skip_next_rounded, size: 28)),
              ]),
            ),
            StreamBuilder<Duration>(
              stream: c.player.positionStream,
              builder: (_, snap) {
                final d = c.player.duration?.inMilliseconds ?? 0;
                final p = snap.data?.inMilliseconds ?? 0;
                return LinearProgressIndicator(
                  value: d > 0 ? (p / d).clamp(0.0, 1.0) : 0,
                  minHeight: 2.5,
                  color: green,
                  backgroundColor: Colors.white12,
                );
              },
            ),
          ]),
        ),
      );
}

class PlayerSheet extends StatelessWidget {
  final Controller c;
  const PlayerSheet(this.c, {super.key});

  @override
  Widget build(BuildContext context) => Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [Color(0xFF1F4D33), bg],
              stops: [0, 0.6]),
        ),
        child: ListenableBuilder(
          listenable: c,
          builder: (context, _) {
            final v = c.current;
            if (v == null) return const SizedBox();
            return ListView(padding: const EdgeInsets.only(bottom: 24), children: [
              Align(
                alignment: Alignment.centerLeft,
                child: IconButton(
                  icon: const Icon(Icons.keyboard_arrow_down_rounded, size: 34),
                  onPressed: () => Navigator.pop(context),
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 28),
                child: AspectRatio(
                  aspectRatio: 1,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(18),
                      boxShadow: const [
                        BoxShadow(color: Colors.black54, blurRadius: 30, offset: Offset(0, 14))
                      ],
                    ),
                    child: LayoutBuilder(
                        builder: (_, k) => Thumb(v.thumbnails.highResUrl,
                            size: k.maxWidth, radius: 18)),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(28, 28, 28, 0),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(v.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800)),
                  const SizedBox(height: 4),
                  Text(v.author, style: const TextStyle(color: Colors.white60, fontSize: 15)),
                ]),
              ),
              StreamBuilder<Duration>(
                stream: c.player.positionStream,
                builder: (_, snap) {
                  final pos = snap.data ?? Duration.zero;
                  final dur = c.player.duration ?? Duration.zero;
                  final max = dur.inMilliseconds > 0 ? dur.inMilliseconds.toDouble() : 1.0;
                  return Padding(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                    child: Column(children: [
                      Slider(
                        value: pos.inMilliseconds.toDouble().clamp(0, max),
                        max: max,
                        onChanged: (x) => c.player.seek(Duration(milliseconds: x.toInt())),
                      ),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                          Text(fmt(pos), style: const TextStyle(fontSize: 12, color: Colors.white54)),
                          Text(fmt(dur), style: const TextStyle(fontSize: 12, color: Colors.white54)),
                        ]),
                      ),
                    ]),
                  );
                },
              ),
              Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                IconButton(
                    iconSize: 42,
                    onPressed: c.prev,
                    icon: const Icon(Icons.skip_previous_rounded)),
                const SizedBox(width: 20),
                PlayButton(c, size: 68),
                const SizedBox(width: 20),
                IconButton(
                    iconSize: 42, onPressed: c.next, icon: const Icon(Icons.skip_next_rounded)),
              ]),
              const Padding(
                padding: EdgeInsets.fromLTRB(20, 28, 20, 8),
                child: Text('Up next · Suggested for you',
                    style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
              ),
              if (c.loadingSuggestions)
                const Padding(
                  padding: EdgeInsets.all(24),
                  child: Center(
                      child: CircularProgressIndicator(strokeWidth: 2.5, color: green)),
                )
              else if (c.suggestions.isEmpty)
                const Padding(
                  padding: EdgeInsets.all(20),
                  child: Text('No suggestions found.', style: TextStyle(color: Colors.white54)),
                )
              else
                for (final s in c.suggestions) SongTile(s, onTap: () => c.playSuggestion(s)),
            ]);
          },
        ),
      );
}
