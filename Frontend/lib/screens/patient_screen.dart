// flutter-app/lib/screens/patient_screen.dart
// Redesigned with:
//  • Warm, organic aesthetic — soft gradients, rounded cards
//  • Prominent, accessible reminder overlay with snooze/dismiss/ack
//  • Animated mic button with waveform rings
//  • Status bubble with emotion-adaptive colour gradient
//  • Smoother state transitions

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/models.dart';
import '../services/api_service.dart';
import '../services/audio_service.dart';
import '../services/socket_service.dart';
import '../widgets/shared_widgets.dart';

class PatientScreen extends StatefulWidget {
  final AppSession  session;
  final VoidCallback onSignOut;
  const PatientScreen({super.key, required this.session, required this.onSignOut});

  @override
  State<PatientScreen> createState() => _PatientScreenState();
}

class _PatientScreenState extends State<PatientScreen>
    with TickerProviderStateMixin {
  String get _patientId => widget.session.patientId;

  // State
  bool   _isRecording  = false;
  bool   _isProcessing = false;
  String _status       = '';
  String _emotion      = 'Neutral';
  String _transcript   = '';
  bool   _micHovered   = false;

  // Reminder overlay
  SocketEvent? _activeReminder;
  String?      _pendingReminderId;

  // Animations
  late AnimationController _pulseCtrl;
  late Animation<double>   _pulseScale;
  late AnimationController _ringCtrl;
  late Animation<double>   _ringAnim;
  late AnimationController _fadeCtrl;
  late Animation<double>   _fadeAnim;
  late AnimationController _reminderCtrl;
  late Animation<double>   _reminderSlide;

  StreamSubscription<SocketEvent>? _socketSub;

  @override
  void initState() {
    super.initState();

    _status = 'Hello ${widget.session.patientName}, tap the microphone to speak with me';

    // Mic pulse
    _pulseCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 900))
      ..repeat(reverse: true);
    _pulseScale = Tween<double>(begin: 1.0, end: 1.08)
        .animate(CurvedAnimation(parent: _pulseCtrl, curve: Curves.easeInOut));
    _pulseCtrl.stop();

    // Expanding rings
    _ringCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 1400))
      ..repeat();
    _ringAnim = CurvedAnimation(parent: _ringCtrl, curve: Curves.easeOut);
    _ringCtrl.stop();

    // Page fade-in
    _fadeCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 700));
    _fadeAnim = CurvedAnimation(parent: _fadeCtrl, curve: Curves.easeIn);
    _fadeCtrl.forward();

    // Reminder slide-up
    _reminderCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 380));
    _reminderSlide = CurvedAnimation(
        parent: _reminderCtrl, curve: Curves.easeOutCubic);

    SocketService.instance.connectAsPatient(_patientId);
    _socketSub = SocketService.instance.eventStream.listen(_onSocketEvent);
  }

  @override
  void dispose() {
    _pulseCtrl.dispose();
    _ringCtrl.dispose();
    _fadeCtrl.dispose();
    _reminderCtrl.dispose();
    _socketSub?.cancel();
    AudioService.instance.dispose();
    super.dispose();
  }

  void _onSocketEvent(SocketEvent event) {
    if (!mounted) return;
    switch (event.type) {
      case SocketEventType.reminderAlert:
        if (event.data['type'] == 'ACK') return;
        setState(() {
          _activeReminder    = event;
          _pendingReminderId = event.reminderId;
        });
        _reminderCtrl.forward(from: 0);
        if (event.audioUrl.isNotEmpty) {
          AudioService.instance.playFromUrl(event.audioUrl);
        }
        break;
      case SocketEventType.playAudio:
        AudioService.instance.playFromUrl(event.audioUrl);
        break;
      default:
        break;
    }
  }

  // ── Mic ────────────────────────────────────────────────────────────────────
  Future<void> _onMicTap() async {
    if (_isProcessing) return;
    HapticFeedback.mediumImpact();
    if (_isRecording) {
      await _stopAndProcess();
    } else {
      await _startRecording();
    }
  }

  Future<void> _startRecording() async {
    final ok = await AudioService.instance.startRecording();
    if (!ok) {
      _setStatus("Microphone access was denied. Please allow it in your browser.");
      return;
    }
    setState(() {
      _isRecording = true;
      _status      = "I'm listening… tap again when you're done.";
      _transcript  = '';
    });
    _pulseCtrl.repeat(reverse: true);
    _ringCtrl.repeat();
  }

  Future<void> _stopAndProcess() async {
    final Uint8List? bytes = await AudioService.instance.stopRecording();
    _pulseCtrl.stop();
    _pulseCtrl.reset();
    _ringCtrl.stop();
    _ringCtrl.reset();

    if (bytes == null || bytes.isEmpty) {
      _setStatus("I didn't hear anything. Please try again.");
      return;
    }

    setState(() { _isRecording = false; _isProcessing = true; _status = "Let me think about that…"; });
    await _process(bytes);
  }

  Future<void> _process(Uint8List audioBytes) async {
    try {
      final result = await ApiService.instance.processMultimodal(
        audioBytes: audioBytes, patientId: _patientId,
      );
      if (result != null && mounted) {
        setState(() {
          _emotion     = result.emotion;
          _status      = result.llmReply;
          _transcript  = result.transcript;
          _isProcessing = false;
        });
        if (_pendingReminderId != null) {
          final t = result.transcript.toLowerCase();
          if (t.contains('yes') || t.contains('done') || t.contains('ok')
              || t.contains('finished') || t.contains('did it')) {
            await _acknowledgeReminder();
          }
        }
        if (result.audioUrl.isNotEmpty) {
          await AudioService.instance.playFromUrl(result.audioUrl);
        }
      } else {
        _setStatus("I didn't catch that — please try speaking again.");
      }
    } catch (_) {
      _setStatus("Connection error. Is the server running?");
    }
  }

  Future<void> _acknowledgeReminder() async {
    final id = _pendingReminderId;
    if (id == null) return;
    await ApiService.instance.acknowledgeReminder(reminderId: id, patientId: _patientId);
    SocketService.instance.emitReminderAck(_patientId, id);
    if (mounted) {
      _reminderCtrl.reverse();
      await Future.delayed(const Duration(milliseconds: 400));
      if (mounted) setState(() { _activeReminder = null; _pendingReminderId = null; });
    }
  }

  Future<void> _snoozeReminder() async {
    final id = _pendingReminderId;
    if (id == null) return;
    await ApiService.instance.snoozeReminder(reminderId: id, patientId: _patientId);
    if (mounted) {
      _reminderCtrl.reverse();
      await Future.delayed(const Duration(milliseconds: 400));
      if (mounted) {
        setState(() { _activeReminder = null; _pendingReminderId = null; });
        _setStatus("Reminder snoozed for 10 minutes. I'll remind you again soon.");
      }
    }
  }

  Future<void> _dismissReminder() async {
    final id = _pendingReminderId;
    if (id == null) return;
    await ApiService.instance.dismissReminder(reminderId: id, patientId: _patientId);
    if (mounted) {
      _reminderCtrl.reverse();
      await Future.delayed(const Duration(milliseconds: 400));
      if (mounted) setState(() { _activeReminder = null; _pendingReminderId = null; });
    }
  }

  void _setStatus(String msg) => setState(() {
        _status = msg; _isRecording = false; _isProcessing = false;
      });

  Color get _emotionColor => emotionColor(_emotion);

  // ── Build ──────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    final wide = isWideScreen(context);
    return Scaffold(
      backgroundColor: const Color(0xFFF5F0E8),
      body: FadeTransition(
        opacity: _fadeAnim,
        child: Stack(children: [
          // Background decorative circles
          Positioned(top: -80, right: -60,
            child: _DecorCircle(size: 280, color: const Color(0xFF1A5276).withOpacity(0.06))),
          Positioned(bottom: -100, left: -80,
            child: _DecorCircle(size: 320, color: const Color(0xFF2E86AB).withOpacity(0.05))),

          Row(children: [
            if (wide) _buildSidebar(),
            Expanded(child: _buildMain(wide)),
          ]),

          // Reminder overlay
          if (_activeReminder != null)
            AnimatedBuilder(
              animation: _reminderSlide,
              builder: (_, child) => Opacity(
                opacity: _reminderSlide.value,
                child: Transform.translate(
                  offset: Offset(0, 40 * (1 - _reminderSlide.value)),
                  child: child,
                ),
              ),
              child: _buildReminderOverlay(),
            ),
        ]),
      ),
    );
  }

  // ── Reminder overlay ───────────────────────────────────────────────────────
  Widget _buildReminderOverlay() {
    final reminder = _activeReminder!;
    return Positioned.fill(
      child: Container(
        color: Colors.black.withOpacity(0.55),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 500),
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Container(
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(28),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.25),
                      blurRadius: 40,
                      offset: const Offset(0, 16),
                    ),
                  ],
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Header
                    Container(
                      padding: const EdgeInsets.fromLTRB(24, 24, 24, 20),
                      decoration: const BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: [Color(0xFF1A5276), Color(0xFF2E86AB)],
                        ),
                        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
                      ),
                      child: Column(children: [
                        Row(children: [
                          Container(
                            width: 44, height: 44,
                            decoration: BoxDecoration(
                              color: Colors.white.withOpacity(0.2),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: const Icon(Icons.alarm_rounded, color: Colors.white, size: 26),
                          ),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                              const Text('Time for your reminder',
                                  style: TextStyle(color: Colors.white70, fontSize: 13, fontWeight: FontWeight.w500)),
                              Text(
                                'Nudge ${reminder.attempts} of ${reminder.maxAttempts}',
                                style: TextStyle(color: Colors.white.withOpacity(0.6), fontSize: 12),
                              ),
                            ]),
                          ),
                          // Attempt dots
                          Row(children: List.generate(reminder.maxAttempts, (i) => Container(
                            width: 8, height: 8,
                            margin: const EdgeInsets.only(left: 4),
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: i < reminder.attempts
                                  ? Colors.white
                                  : Colors.white.withOpacity(0.3),
                            ),
                          ))),
                        ]),
                        const SizedBox(height: 18),
                        Text(
                          reminder.task.isNotEmpty
                              ? 'It\'s time to ${reminder.task}'
                              : 'You have a reminder',
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 24,
                            fontWeight: FontWeight.w800,
                            height: 1.2,
                          ),
                        ),
                        if (reminder.reminderText.isNotEmpty &&
                            reminder.reminderText != reminder.task) ...[
                          const SizedBox(height: 10),
                          Text(
                            reminder.reminderText,
                            textAlign: TextAlign.center,
                            style: const TextStyle(color: Colors.white70, fontSize: 15, height: 1.5),
                          ),
                        ],
                      ]),
                    ),

                    // Action buttons
                    Padding(
                      padding: const EdgeInsets.all(24),
                      child: Column(children: [
                        // Primary: Done
                        MouseRegion(
                          cursor: SystemMouseCursors.click,
                          child: GestureDetector(
                            onTap: _acknowledgeReminder,
                            child: Container(
                              width: double.infinity,
                              padding: const EdgeInsets.symmetric(vertical: 18),
                              decoration: BoxDecoration(
                                gradient: const LinearGradient(
                                  colors: [Color(0xFF1D8348), Color(0xFF27AE60)],
                                ),
                                borderRadius: BorderRadius.circular(16),
                                boxShadow: [
                                  BoxShadow(
                                    color: const Color(0xFF1D8348).withOpacity(0.35),
                                    blurRadius: 16,
                                    offset: const Offset(0, 6),
                                  ),
                                ],
                              ),
                              child: const Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(Icons.check_circle_rounded, color: Colors.white, size: 26),
                                  SizedBox(width: 10),
                                  Text("Yes, I've done it!",
                                      style: TextStyle(
                                          color: Colors.white, fontSize: 20,
                                          fontWeight: FontWeight.w800)),
                                ],
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 12),
                        // Secondary row
                        Row(children: [
                          Expanded(child: _SecondaryBtn(
                            icon: Icons.snooze_rounded,
                            label: 'Snooze 10 min',
                            color: const Color(0xFF1A5276),
                            onTap: _snoozeReminder,
                          )),
                          const SizedBox(width: 10),
                          Expanded(child: _SecondaryBtn(
                            icon: Icons.notifications_off_rounded,
                            label: 'Dismiss',
                            color: const Color(0xFF888780),
                            onTap: _dismissReminder,
                          )),
                        ]),
                        const SizedBox(height: 10),
                        Text(
                          'You can also just say "Yes, I\'ve done it" into the microphone',
                          textAlign: TextAlign.center,
                          style: TextStyle(fontSize: 12, color: Colors.black38, height: 1.5),
                        ),
                      ]),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  // ── Sidebar ────────────────────────────────────────────────────────────────
  Widget _buildSidebar() => Container(
        width: 220,
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFF1A3F5C), Color(0xFF1A5276)],
          ),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const SizedBox(height: 36),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Row(children: [
              Container(
                width: 36, height: 36,
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(Icons.favorite_rounded, color: Colors.white, size: 20),
              ),
              const SizedBox(width: 10),
              const Text('AlzCare',
                  style: TextStyle(color: Colors.white, fontSize: 20,
                      fontWeight: FontWeight.w800, letterSpacing: -0.3)),
            ]),
          ),
          const SizedBox(height: 28),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.1),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: Colors.white.withOpacity(0.12)),
              ),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                // Emotion indicator
                Row(children: [
                  Container(
                    width: 8, height: 8,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: _emotionColor,
                    ),
                  ),
                  const SizedBox(width: 6),
                  Text(_emotion,
                      style: TextStyle(color: _emotionColor, fontSize: 11,
                          fontWeight: FontWeight.w600)),
                ]),
                const SizedBox(height: 8),
                Text(widget.session.patientName,
                    style: const TextStyle(color: Colors.white, fontSize: 15,
                        fontWeight: FontWeight.w700)),
                const SizedBox(height: 2),
                Text(_patientId,
                    style: const TextStyle(color: Colors.white54, fontSize: 11)),
              ]),
            ),
          ),
          const Spacer(),
          SideNavItem(
              icon: Icons.mic_rounded, label: 'Speak',
              selected: true, onTap: () {}),
          if (_activeReminder != null)
            Container(
              margin: const EdgeInsets.fromLTRB(12, 6, 12, 0),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: Colors.orange.withOpacity(0.2),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.orange.withOpacity(0.4)),
              ),
              child: Row(children: [
                const Icon(Icons.alarm, color: Colors.orange, size: 16),
                const SizedBox(width: 8),
                const Expanded(
                  child: Text('Reminder active',
                      style: TextStyle(color: Colors.orange, fontSize: 12,
                          fontWeight: FontWeight.w700)),
                ),
              ]),
            ),
          SideNavItem(
              icon: Icons.logout_rounded, label: 'Switch Account',
              selected: false, onTap: widget.onSignOut),
          const SizedBox(height: 28),
        ]),
      );

  // ── Main ───────────────────────────────────────────────────────────────────
  Widget _buildMain(bool wide) => SingleChildScrollView(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 680),
            child: Padding(
              padding: EdgeInsets.symmetric(
                  horizontal: wide ? 48 : 24, vertical: 40),
              child: Column(children: [
                if (!wide) _buildTopBar(),
                if (!wide) const SizedBox(height: 28),

                // Greeting card
                _buildGreetingCard(),
                const SizedBox(height: 28),

                // Transcript
                if (_transcript.isNotEmpty) ...[
                  _buildTranscriptCard(),
                  const SizedBox(height: 20),
                ],

                // Status bubble
                _buildStatusBubble(),
                const SizedBox(height: 48),

                // Mic button
                _buildMicButton(),
                const SizedBox(height: 18),

                // Helper text
                AnimatedSwitcher(
                  duration: const Duration(milliseconds: 300),
                  child: Text(
                    key: ValueKey(_isRecording ? 'r' : _isProcessing ? 'p' : 'i'),
                    _isRecording
                        ? "Tap the button again when you're done speaking"
                        : _isProcessing
                            ? "Processing your voice, one moment…"
                            : "Tap the microphone and speak to me",
                    textAlign: TextAlign.center,
                    style: TextStyle(
                        fontSize: 15, height: 1.5,
                        color: _isRecording
                            ? const Color(0xFFB03A2E)
                            : Colors.black38),
                  ),
                ),
                const SizedBox(height: 48),
              ]),
            ),
          ),
        ),
      );

  Widget _buildTopBar() => Row(children: [
        Container(
          width: 38, height: 38,
          decoration: BoxDecoration(
            color: AlzColors.navy,
            borderRadius: BorderRadius.circular(10),
          ),
          child: const Icon(Icons.favorite_rounded, color: Colors.white, size: 20),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('AlzCare AI',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: AlzColors.navy)),
            Text(widget.session.patientName,
                style: const TextStyle(fontSize: 13, color: Colors.black45),
                overflow: TextOverflow.ellipsis),
          ]),
        ),
        TextButton.icon(
          onPressed: widget.onSignOut,
          icon: const Icon(Icons.logout_rounded, size: 16),
          label: const Text('Switch'),
          style: TextButton.styleFrom(foregroundColor: AlzColors.navy),
        ),
      ]);

  Widget _buildGreetingCard() => Container(
        width: double.infinity,
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: Colors.black.withOpacity(0.06)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.04),
              blurRadius: 16,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Column(children: [
          // Time of day
          Builder(builder: (_) {
            final hour = DateTime.now().hour;
            final greeting = hour < 12 ? 'Good morning' : hour < 18 ? 'Good afternoon' : 'Good evening';
            final icon = hour < 12 ? '🌤' : hour < 18 ? '☀️' : '🌙';
            return Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              Text(icon, style: const TextStyle(fontSize: 20)),
              const SizedBox(width: 8),
              Text(greeting,
                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600,
                      color: AlzColors.navy)),
            ]);
          }),
          const SizedBox(height: 8),
          Text(widget.session.patientName,
              style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w800,
                  color: AlzColors.textDark, height: 1.1)),
          const SizedBox(height: 6),
          Text(
            'I\'m your AI companion. I\'m here to listen and help.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 14, color: Colors.black38, height: 1.5),
          ),
        ]),
      );

  Widget _buildTranscriptCard() => Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: Colors.black.withOpacity(0.03),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: Colors.black.withOpacity(0.06)),
        ),
        child: Row(children: [
          Icon(Icons.record_voice_over_rounded,
              color: Colors.black26, size: 18),
          const SizedBox(width: 10),
          Expanded(
            child: Text(_transcript,
                style: const TextStyle(fontSize: 14, color: Colors.black45,
                    fontStyle: FontStyle.italic, height: 1.5)),
          ),
        ]),
      );

  Widget _buildStatusBubble() {
    final color = _emotionColor;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 500),
      constraints: const BoxConstraints(maxWidth: 560),
      padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 22),
      decoration: BoxDecoration(
        color: color.withOpacity(0.06),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: color.withOpacity(0.25), width: 1.5),
      ),
      child: Column(children: [
        if (_emotion != 'Neutral') ...[
          EmotionChip(_emotion),
          const SizedBox(height: 12),
        ],
        Text(
          _status.isEmpty
              ? 'I\'m ready to listen. Tap the microphone below.'
              : _status,
          textAlign: TextAlign.center,
          style: TextStyle(
              fontSize: 19, height: 1.55,
              fontWeight: FontWeight.w500, color: color.withOpacity(0.85)),
        ),
      ]),
    );
  }

  Widget _buildMicButton() {
    final isActive = _isRecording;
    final baseColor = isActive ? const Color(0xFFB03A2E) : AlzColors.navy;

    return SizedBox(
      width: 180,
      height: 180,
      child: Stack(alignment: Alignment.center, children: [
        // Expanding rings when recording
        if (isActive)
          AnimatedBuilder(
            animation: _ringAnim,
            builder: (_, __) => Stack(
              alignment: Alignment.center,
              children: [1.4, 1.7, 2.0].map((scale) {
                final progress = (_ringAnim.value + (scale - 1.4) / 0.6) % 1.0;
                return Opacity(
                  opacity: (1 - progress) * 0.4,
                  child: Transform.scale(
                    scale: 1.0 + (scale - 1.0) * progress,
                    child: Container(
                      width: 160, height: 160,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: baseColor.withOpacity(0.15),
                      ),
                    ),
                  ),
                );
              }).toList(),
            ),
          ),

        // Pulse scale when recording
        AnimatedBuilder(
          animation: isActive ? _pulseScale : kAlwaysCompleteAnimation,
          builder: (_, child) => Transform.scale(
            scale: isActive ? _pulseScale.value : 1.0,
            child: child,
          ),
          child: MouseRegion(
            cursor: _isProcessing
                ? SystemMouseCursors.wait
                : SystemMouseCursors.click,
            onEnter:  (_) => setState(() => _micHovered = true),
            onExit:   (_) => setState(() => _micHovered = false),
            child: GestureDetector(
              onTap: _onMicTap,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                width: 160, height: 160,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: RadialGradient(
                    colors: isActive
                        ? [const Color(0xFFD85A30), const Color(0xFFB03A2E)]
                        : _micHovered
                            ? [const Color(0xFF2E86AB), const Color(0xFF1A5276)]
                            : [const Color(0xFF1A5276), const Color(0xFF0F3A50)],
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: baseColor.withOpacity(_micHovered ? 0.5 : 0.3),
                      blurRadius: _micHovered ? 40 : 24,
                      spreadRadius: _micHovered ? 6 : 2,
                    ),
                  ],
                ),
                child: _isProcessing
                    ? const Center(
                        child: SizedBox(
                          width: 44, height: 44,
                          child: CircularProgressIndicator(
                              color: Colors.white, strokeWidth: 3),
                        ))
                    : Icon(
                        isActive
                            ? Icons.stop_rounded
                            : Icons.mic_rounded,
                        size: 80, color: Colors.white),
              ),
            ),
          ),
        ),
      ]),
    );
  }
}

// ── Helper widgets ─────────────────────────────────────────────────────────────
class _DecorCircle extends StatelessWidget {
  final double size;
  final Color  color;
  const _DecorCircle({required this.size, required this.color});

  @override
  Widget build(BuildContext context) => Container(
        width: size, height: size,
        decoration: BoxDecoration(shape: BoxShape.circle, color: color),
      );
}

class _SecondaryBtn extends StatefulWidget {
  final IconData     icon;
  final String       label;
  final Color        color;
  final VoidCallback onTap;
  const _SecondaryBtn({required this.icon, required this.label,
      required this.color, required this.onTap});

  @override
  State<_SecondaryBtn> createState() => _SecondaryBtnState();
}

class _SecondaryBtnState extends State<_SecondaryBtn> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) => MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter:  (_) => setState(() => _hovered = true),
        onExit:   (_) => setState(() => _hovered = false),
        child: GestureDetector(
          onTap: widget.onTap,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 160),
            padding: const EdgeInsets.symmetric(vertical: 14),
            decoration: BoxDecoration(
              color: _hovered
                  ? widget.color.withOpacity(0.1)
                  : widget.color.withOpacity(0.06),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: widget.color.withOpacity(0.3), width: 1.5),
            ),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Icon(widget.icon, color: widget.color, size: 22),
              const SizedBox(height: 4),
              Text(widget.label,
                  style: TextStyle(color: widget.color, fontSize: 12,
                      fontWeight: FontWeight.w700)),
            ]),
          ),
        ),
      );
}