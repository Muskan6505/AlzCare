// flutter-app/lib/screens/patient_screen.dart
// Patient-facing web UI — centred layout optimised for browser.
// Key differences from mobile:
//   • No permission_handler — browser shows mic prompt automatically
//   • AudioService.stopRecording() returns Uint8List (no file path)
//   • Centred card layout for desktop/tablet screens
//   • Hover-aware mic button with cursor feedback

import 'dart:async';
import 'dart:typed_data';
import 'package:flutter/material.dart';

import '../models/models.dart';
import '../services/api_service.dart';
import '../services/audio_service.dart';
import '../services/socket_service.dart';
import '../widgets/shared_widgets.dart';

class PatientScreen extends StatefulWidget {
  final AppSession session;
  final VoidCallback onSignOut;

  const PatientScreen({
    super.key,
    required this.session,
    required this.onSignOut,
  });

  @override
  State<PatientScreen> createState() => _PatientScreenState();
}

class _PatientScreenState extends State<PatientScreen>
    with TickerProviderStateMixin {
  String get _patientId => widget.session.patientId;

  // State
  bool   _isRecording  = false;
  bool   _isProcessing = false;
  String _status       = "Click the microphone and speak to me";
  String _emotion      = "Neutral";
  String _transcript   = "";
  bool   _micHovered   = false;

  // Nagger
  SocketEvent? _activeReminder;
  String?      _pendingReminderId;

  // Animation
  late AnimationController _pulseCtrl;
  late Animation<double>   _pulse;
  late AnimationController _fadeCtrl;
  late Animation<double>   _fade;

  StreamSubscription<SocketEvent>? _socketSub;

  @override
  void initState() {
    super.initState();
    _pulseCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 1100))
      ..repeat(reverse: true);
    _pulse = Tween<double>(begin: 1.0, end: 1.10)
        .animate(CurvedAnimation(parent: _pulseCtrl, curve: Curves.easeInOut));
    _pulseCtrl.stop();

    _fadeCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 600));
    _fade = CurvedAnimation(parent: _fadeCtrl, curve: Curves.easeIn);
    _fadeCtrl.forward();

    _status = 'Hello ${widget.session.patientName}, click the microphone and speak to me';
    SocketService.instance.connectAsPatient(_patientId);
    _socketSub = SocketService.instance.eventStream.listen(_onSocketEvent);
  }

  @override
  void dispose() {
    _pulseCtrl.dispose();
    _fadeCtrl.dispose();
    _socketSub?.cancel();
    AudioService.instance.dispose();
    super.dispose();
  }

  void _onSocketEvent(SocketEvent event) {
    if (!mounted) return;
    switch (event.type) {
      case SocketEventType.reminderAlert:
        if (event.data['type'] == 'ACK') return;
        setState(() { _activeReminder = event; _pendingReminderId = event.reminderId; });
        AudioService.instance.playFromUrl(event.audioUrl);
        break;
      case SocketEventType.playAudio:
        AudioService.instance.playFromUrl(event.audioUrl);
        break;
      default:
        break;
    }
  }

  // ── Mic logic ──────────────────────────────────────────────────────────────
  Future<void> _onMicTap() async {
    if (_isProcessing) return;
    if (_isRecording) {
      await _stopAndProcess();
    } else {
      await _startRecording();
    }
  }

  Future<void> _startRecording() async {
    final ok = await AudioService.instance.startRecording();
    if (!ok) {
      _setStatus("Browser microphone access was denied. Please allow mic in your browser.");
      return;
    }
    setState(() {
      _isRecording = true;
      _status      = "Listening… click again when you're done speaking.";
      _transcript  = "";
    });
    _pulseCtrl.repeat(reverse: true);
  }

  Future<void> _stopAndProcess() async {
    final Uint8List? bytes = await AudioService.instance.stopRecording();
    _pulseCtrl.stop();
    _pulseCtrl.reset();

    if (bytes == null || bytes.isEmpty) {
      _setStatus("Recording was empty. Please try speaking again.");
      return;
    }

    setState(() { _isRecording = false; _isProcessing = true; _status = "Thinking…"; });
    await _process(bytes);
  }

  Future<void> _process(Uint8List audioBytes) async {
    try {
      final result = await ApiService.instance.processMultimodal(
        audioBytes: audioBytes,
        patientId: _patientId,
      );
      if (result != null && mounted) {
        setState(() {
          _emotion     = result.emotion;
          _status      = result.llmReply;
          _transcript  = result.transcript;
          _isProcessing = false;
        });
        // Auto-ACK reminder if patient said yes/done/okay
        if (_pendingReminderId != null) {
          final t = result.transcript.toLowerCase();
          if (t.contains('yes') || t.contains('done') || t.contains('ok')) {
            await _acknowledgeReminder();
          }
        }
        await AudioService.instance.playFromUrl(result.audioUrl);
      } else {
        _setStatus("I didn't catch that. Please try again.");
      }
    } catch (_) {
      _setStatus("Connection error. Is the server running?");
    }
  }

  Future<void> _acknowledgeReminder() async {
    final id = _pendingReminderId;
    if (id == null) return;
    await ApiService.instance.acknowledgeReminder(
        reminderId: id, patientId: _patientId);
    SocketService.instance.emitReminderAck(_patientId, id);
    setState(() { _activeReminder = null; _pendingReminderId = null; });
  }

  void _setStatus(String msg) => setState(() {
        _status = msg; _isRecording = false; _isProcessing = false;
      });

  Color get _stateColor => emotionColor(_emotion);

  // ── Build ──────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    final wide = isWideScreen(context);
    return Scaffold(
      backgroundColor: AlzColors.warm,
      body: FadeTransition(
        opacity: _fade,
        child: Stack(children: [
          // Main layout
          Row(children: [
            // Left sidebar on wide screens
            if (wide) _buildSidebar(),
            // Main content
            Expanded(child: _buildMain(wide)),
          ]),
          // Nagger overlay
          if (_activeReminder != null)
            Positioned.fill(
              child: Container(
                color: Colors.black54,
                child: Center(
                  child: ReminderBanner(
                    task:          _activeReminder!.task,
                    attempts:      _activeReminder!.attempts,
                    maxAttempts:   _activeReminder!.maxAttempts,
                    onAcknowledge: _acknowledgeReminder,
                    onDismiss: () => setState(() => _activeReminder = null),
                  ),
                ),
              ),
            ),
        ]),
      ),
    );
  }

  Widget _buildSidebar() => Container(
        width: 220,
        color: AlzColors.navy,
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const SizedBox(height: 32),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: const Row(children: [
              Icon(Icons.favorite_rounded, color: Colors.white, size: 26),
              SizedBox(width: 10),
              Text('AlzCare AI',
                  style: TextStyle(color: Colors.white, fontSize: 20,
                      fontWeight: FontWeight.w800)),
            ]),
          ),
          const SizedBox(height: 32),
          SideNavItem(
              icon: Icons.mic_rounded, label: 'Speak',
              selected: true, onTap: () {}),
          Container(
            margin: const EdgeInsets.fromLTRB(12, 18, 12, 0),
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.08),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: Colors.white.withOpacity(0.10)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  widget.session.patientName,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  _patientId,
                  style: const TextStyle(color: Colors.white70, fontSize: 12),
                ),
              ],
            ),
          ),
          const Spacer(),
          SideNavItem(
              icon: Icons.logout_rounded,
              label: 'Switch Account',
              selected: false,
              onTap: widget.onSignOut),
          const SizedBox(height: 24),
        ]),
      );

  Widget _buildMain(bool wide) => SingleChildScrollView(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 700),
            child: Padding(
              padding: EdgeInsets.symmetric(
                  horizontal: wide ? 48 : 24, vertical: 40),
              child: Column(children: [
                // Header (only on narrow screens — wide has sidebar)
                if (!wide) _buildTopBar(),
                if (!wide) const SizedBox(height: 32),
                // Memory photo frame
                _buildPhotoFrame(),
                const SizedBox(height: 36),
                // Transcript display
                if (_transcript.isNotEmpty)
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: Colors.black.withOpacity(0.04),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(children: [
                      const Icon(Icons.record_voice_over,
                          color: AlzColors.grey, size: 18),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(_transcript,
                            style: const TextStyle(
                                fontSize: 15, color: Colors.black45,
                                fontStyle: FontStyle.italic)),
                      ),
                    ]),
                  ),
                if (_transcript.isNotEmpty) const SizedBox(height: 20),
                // Emotion chip
                if (_emotion != 'Neutral') ...[
                  EmotionChip(_emotion),
                  const SizedBox(height: 16),
                ],
                // Status / reply bubble
                StatusBubble(text: _status, color: _stateColor),
                const SizedBox(height: 48),
                // Mic button
                _buildMicButton(),
                const SizedBox(height: 20),
                // Helper text
                Text(
                  _isRecording
                      ? "Click to stop recording"
                      : _isProcessing
                          ? "Processing your voice…"
                          : "Click the microphone to speak",
                  style: TextStyle(
                      fontSize: 15,
                      color: _isRecording ? AlzColors.red : Colors.black38),
                ),
                const SizedBox(height: 40),
              ]),
            ),
          ),
        ),
      );

  Widget _buildTopBar() => Row(children: [
        const Icon(Icons.favorite_rounded, color: AlzColors.navy, size: 26),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('AlzCare AI',
                  style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800,
                      color: AlzColors.navy)),
              Text(
                widget.session.patientName,
                style: const TextStyle(fontSize: 13, color: Colors.black45),
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
        TextButton.icon(
          onPressed: widget.onSignOut,
          icon: const Icon(Icons.logout_rounded, size: 18),
          label: const Text('Switch account'),
          style: TextButton.styleFrom(foregroundColor: AlzColors.navy),
        ),
      ]);

  Widget _buildPhotoFrame() => Container(
        height: 200,
        width: double.infinity,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: AlzColors.navy, width: 2.5),
          boxShadow: [BoxShadow(
              color: Colors.black.withOpacity(0.07),
              blurRadius: 12, offset: const Offset(0, 4))],
        ),
        child: const Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          Icon(Icons.photo_album_outlined, size: 52, color: AlzColors.grey),
          SizedBox(height: 8),
          Text("Your memories will appear here",
              style: TextStyle(fontSize: 15, color: AlzColors.grey)),
        ]),
      );

  Widget _buildMicButton() {
    Widget btn = MouseRegion(
      cursor: _isProcessing
          ? SystemMouseCursors.wait
          : SystemMouseCursors.click,
      onEnter:  (_) => setState(() => _micHovered = true),
      onExit:   (_) => setState(() => _micHovered = false),
      child: GestureDetector(
        onTap: _onMicTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          width: 160, height: 160,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: _isRecording ? AlzColors.red : AlzColors.navy,
            boxShadow: [BoxShadow(
                color: (_isRecording ? AlzColors.red : AlzColors.navy)
                    .withOpacity(_micHovered ? 0.5 : 0.3),
                blurRadius: _micHovered ? 36 : 24,
                spreadRadius: _micHovered ? 6 : 3)],
          ),
          child: _isProcessing
              ? const Center(child: CircularProgressIndicator(
                  color: Colors.white, strokeWidth: 4))
              : Icon(
                  _isRecording ? Icons.stop_rounded : Icons.mic_rounded,
                  size: 80, color: Colors.white),
        ),
      ),
    );

    if (_isRecording) btn = ScaleTransition(scale: _pulse, child: btn);
    return btn;
  }
}
