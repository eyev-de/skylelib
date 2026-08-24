// Flutter also defines a `ConnectionState` (for StreamBuilder); hide it so the
// one from flutter_skyle is unambiguous.
import 'package:flutter/material.dart' hide ConnectionState;
import 'package:flutter_skyle_riverpod/flutter_skyle_riverpod.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'positioning_view.dart';
import 'video_view.dart';

void main() {
  runApp(const ProviderScope(child: SkyleApp()));
}

enum ViewMode { positioning, video }

class SkyleApp extends StatelessWidget {
  const SkyleApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Skyle — Flutter Example',
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark(useMaterial3: true).copyWith(
        scaffoldBackgroundColor: const Color(0xFF1B1B1F),
      ),
      home: const HomePage(),
    );
  }
}

class HomePage extends ConsumerStatefulWidget {
  const HomePage({super.key});

  @override
  ConsumerState<HomePage> createState() => _HomePageState();
}

class _HomePageState extends ConsumerState<HomePage> {
  ViewMode _mode = ViewMode.positioning;

  @override
  void initState() {
    super.initState();
    // Start the handshake once the first frame is up.
    WidgetsBinding.instance.addPostFrameCallback((_) => _connect());
  }

  /// Connect, retrying briefly: on some platforms (e.g. macOS) the plugin wires
  /// up its USB transport asynchronously at startup, so the first attempt can
  /// land before "transport write" is set. Retrying a few times covers that
  /// without a manual Connect button.
  Future<void> _connect() async {
    final client = ref.read(skyleClientProvider);
    for (var attempt = 0; attempt < 10 && mounted; attempt++) {
      try {
        await client.connect();
        return;
      } catch (_) {
        await Future<void>.delayed(const Duration(milliseconds: 300));
      }
    }
  }

  /// Subscribe to the streams the UI needs. Only valid once LINK_SYNCED.
  void _applyStreams() {
    if (!ref.read(skyleConnectionStateProvider).isReady) return;
    final client = ref.read(skyleClientProvider);
    client.enableGaze(true); // gaze readout is always live
    client.enablePositioning(_mode == ViewMode.positioning);
    client.enableVideo(_mode == ViewMode.video); // off when hidden saves bandwidth
  }

  @override
  Widget build(BuildContext context) {
    // Re-apply streams as soon as the link comes up.
    ref.listen(skyleConnectionStateProvider, (_, next) {
      if (next.isReady) _applyStreams();
    });

    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const _ConnectionBar(),
              const SizedBox(height: 14),
              _SegmentedControl(
                mode: _mode,
                onChanged: (m) {
                  setState(() => _mode = m);
                  _applyStreams();
                },
              ),
              const SizedBox(height: 14),
              const _HostControls(),
              const SizedBox(height: 14),
              Expanded(
                child: _mode == ViewMode.positioning
                    ? const PositioningView()
                    : const VideoView(),
              ),
              const SizedBox(height: 14),
              const _GazeReadout(),
            ],
          ),
        ),
      ),
    );
  }
}

/// Colored dot + label reflecting the connection state.
class _ConnectionBar extends ConsumerWidget {
  const _ConnectionBar();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(skyleConnectionStateStreamProvider).value ??
        ConnectionState.disconnected;

    late final Color color;
    late final String label;
    if (state == ConnectionState.error) {
      color = const Color(0xFFE74C3C);
      label = 'Error';
    } else if (state.isReady) {
      color = const Color(0xFF2ECC71);
      label = 'Streaming';
    } else if (state.isConnected) {
      color = const Color(0xFFF1C40F);
      label = 'Connecting…';
    } else {
      color = const Color(0xFF888888);
      label = 'Disconnected';
    }

    return Row(
      children: [
        Container(
          width: 14,
          height: 14,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 8),
        Text(label,
            style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
        const Spacer(),
        Text('Skyle · VID 0x3729 / PID 0x7333',
            style: TextStyle(fontSize: 12, color: Colors.grey.shade500)),
      ],
    );
  }
}

/// Two joined segments, styled like the Avalonia/SwiftUI examples.
class _SegmentedControl extends StatelessWidget {
  const _SegmentedControl({required this.mode, required this.onChanged});

  final ViewMode mode;
  final ValueChanged<ViewMode> onChanged;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: SegmentedButton<ViewMode>(
        showSelectedIcon: false,
        segments: const [
          ButtonSegment(value: ViewMode.positioning, label: Text('Positioning')),
          ButtonSegment(value: ViewMode.video, label: Text('Video')),
        ],
        selected: {mode},
        onSelectionChanged: (s) => onChanged(s.first),
      ),
    );
  }
}

/// Host-control test buttons: fire-and-forget Skyle Link commands to the app
/// hosting the hub (Skyle X). They only work while this app runs as a link
/// client; a refused send (hub owner / direct USB) shows a SnackBar. The
/// toggle state is app-local - the host restores hidden UI itself when this
/// app disconnects.
class _HostControls extends ConsumerStatefulWidget {
  const _HostControls();

  @override
  ConsumerState<_HostControls> createState() => _HostControlsState();
}

class _HostControlsState extends ConsumerState<_HostControls> {
  bool _menuBarVisible = true;
  bool _pointerVisible = true;

  Future<void> _send(Future<bool> Function(SkyleClient client) action,
      VoidCallback onAccepted) async {
    final accepted = await action(ref.read(skyleClientProvider));
    if (accepted) {
      onAccepted();
    } else if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Host control refused - not connected to a Skyle Link hub'),
      ));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        OutlinedButton.icon(
          icon: Icon(_menuBarVisible ? Icons.visibility_off : Icons.visibility,
              size: 18),
          label: Text(_menuBarVisible ? 'Hide menu bar' : 'Show menu bar'),
          onPressed: () => _send(
            (c) => c.setHostMenuBarVisible(!_menuBarVisible),
            () => setState(() => _menuBarVisible = !_menuBarVisible),
          ),
        ),
        const SizedBox(width: 10),
        OutlinedButton.icon(
          icon: Icon(_pointerVisible ? Icons.visibility_off : Icons.visibility,
              size: 18),
          label: Text(_pointerVisible ? 'Hide pointer' : 'Show pointer'),
          onPressed: () => _send(
            (c) => c.setHostPointerVisible(!_pointerVisible),
            () => setState(() => _pointerVisible = !_pointerVisible),
          ),
        ),
        const SizedBox(width: 10),
        OutlinedButton.icon(
          icon: const Icon(Icons.center_focus_strong, size: 18),
          label: const Text('Start calibration'),
          onPressed: () => _send((c) => c.startHostCalibration(), () {}),
        ),
      ],
    );
  }
}

/// Live gaze location in screen pixels + movement classification.
class _GazeReadout extends ConsumerWidget {
  const _GazeReadout();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final gaze = ref.watch(skyleGazeDataStreamProvider).value;
    final String text;
    if (gaze == null || (gaze.gazeX == 0 && gaze.gazeY == 0)) {
      text = 'Gaze: —';
    } else {
      final movement = gaze.combined.type.name;
      text = 'Gaze: (${gaze.gazeX.toStringAsFixed(0)}, '
          '${gaze.gazeY.toStringAsFixed(0)}) px · $movement';
    }
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(text,
          style: const TextStyle(fontFamily: 'monospace', fontSize: 16)),
    );
  }
}
