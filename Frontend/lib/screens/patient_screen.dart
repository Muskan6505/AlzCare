// flutter-app/lib/screens/patient_screen.dart
// Redesigned with:
//  • Bottom navigation: Speak | Reminders | Notes
//  • Speak tab: Warm mic UI with emotion bubble
//  • Reminders tab: Patient can view their schedule (with ack/snooze/dismiss)
//  • Notes tab: Patient can view AND add their own daily notes

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

import '../models/models.dart';
import '../services/api_service.dart';
import '../services/audio_service.dart';
import '../services/socket_service.dart';
import '../widgets/shared_widgets.dart';

// ── Tab enum ──────────────────────────────────────────────────────────────────
enum _PatientTab { speak, reminders, notes }

class PatientScreen extends StatefulWidget {
  final AppSession   session;
  final VoidCallback onSignOut;
  const PatientScreen({super.key, required this.session, required this.onSignOut});

  @override
  State<PatientScreen> createState() => _PatientScreenState();
}

class _PatientScreenState extends State<PatientScreen>
    with TickerProviderStateMixin {
  String get _patientId => widget.session.patientId;

  // ── Tab state ────────────────────────────────────────────────────────────
  _PatientTab _currentTab = _PatientTab.speak;

  // ── Speak tab state ──────────────────────────────────────────────────────
  bool   _isRecording  = false;
  bool   _isProcessing = false;
  String _status       = '';
  String _emotion      = 'Neutral';
  String _transcript   = '';
  bool   _micHovered   = false;

  // ── Reminder overlay ─────────────────────────────────────────────────────
  SocketEvent? _activeReminder;
  String?      _pendingReminderId;

  // ── Reminders tab state ──────────────────────────────────────────────────
  List<Reminder> _reminders        = [];
  bool           _loadingReminders = true;

  // ── Notes tab state ──────────────────────────────────────────────────────
  List<CaregiverNote> _notes        = [];
  bool                _loadingNotes = true;

  // ── Animations ───────────────────────────────────────────────────────────
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

    _pulseCtrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 900))
      ..repeat(reverse: true);
    _pulseScale = Tween<double>(begin: 1.0, end: 1.08)
        .animate(CurvedAnimation(parent: _pulseCtrl, curve: Curves.easeInOut));
    _pulseCtrl.stop();

    _ringCtrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 1400))
      ..repeat();
    _ringAnim = CurvedAnimation(parent: _ringCtrl, curve: Curves.easeOut);
    _ringCtrl.stop();

    _fadeCtrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 700));
    _fadeAnim = CurvedAnimation(parent: _fadeCtrl, curve: Curves.easeIn);
    _fadeCtrl.forward();

    _reminderCtrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 380));
    _reminderSlide = CurvedAnimation(parent: _reminderCtrl, curve: Curves.easeOutCubic);

    SocketService.instance.connectAsPatient(_patientId);
    _socketSub = SocketService.instance.eventStream.listen(_onSocketEvent);

    _loadReminders();
    _loadNotes();
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

  // ── Data loaders ──────────────────────────────────────────────────────────
  Future<void> _loadReminders() async {
    final data = await ApiService.instance.fetchReminders(_patientId);
    if (mounted) setState(() { _reminders = data; _loadingReminders = false; });
  }

  Future<void> _loadNotes() async {
    final data = await ApiService.instance.fetchNotes(_patientId);
    if (mounted) setState(() { _notes = data; _loadingNotes = false; });
  }

  // ── Socket ────────────────────────────────────────────────────────────────
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
        if (event.audioUrl.isNotEmpty) AudioService.instance.playFromUrl(event.audioUrl);
        _loadReminders(); // refresh list so status updates
        break;
      case SocketEventType.playAudio:
        AudioService.instance.playFromUrl(event.audioUrl);
        break;
      default:
        break;
    }
  }

  // ── Mic logic ─────────────────────────────────────────────────────────────
  Future<void> _onMicTap() async {
    if (_isProcessing) return;
    HapticFeedback.mediumImpact();
    _isRecording ? await _stopAndProcess() : await _startRecording();
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
    _pulseCtrl.stop(); _pulseCtrl.reset();
    _ringCtrl.stop();  _ringCtrl.reset();
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
          _emotion      = result.emotion;
          _status       = result.llmReply;
          _transcript   = result.transcript;
          _isProcessing = false;
        });
        if (_pendingReminderId != null) {
          final t = result.transcript.toLowerCase();
          if (t.contains('yes') || t.contains('done') || t.contains('ok') ||
              t.contains('finished') || t.contains('did it')) {
            await _acknowledgeReminder();
          }
        }
        if (result.audioUrl.isNotEmpty) await AudioService.instance.playFromUrl(result.audioUrl);
      } else {
        _setStatus("I didn't catch that — please try speaking again.");
      }
    } catch (_) {
      _setStatus("Connection error. Is the server running?");
    }
  }

  // ── Reminder actions ──────────────────────────────────────────────────────
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
    _loadReminders();
  }

  Future<void> _snoozeReminder({String? id}) async {
    final remId = id ?? _pendingReminderId;
    if (remId == null) return;
    await ApiService.instance.snoozeReminder(reminderId: remId, patientId: _patientId);
    if (id == null && mounted) {
      _reminderCtrl.reverse();
      await Future.delayed(const Duration(milliseconds: 400));
      if (mounted) setState(() { _activeReminder = null; _pendingReminderId = null; });
    }
    _loadReminders();
  }

  Future<void> _dismissReminder({String? id}) async {
    final remId = id ?? _pendingReminderId;
    if (remId == null) return;
    await ApiService.instance.dismissReminder(reminderId: remId, patientId: _patientId);
    if (id == null && mounted) {
      _reminderCtrl.reverse();
      await Future.delayed(const Duration(milliseconds: 400));
      if (mounted) setState(() { _activeReminder = null; _pendingReminderId = null; });
    }
    _loadReminders();
  }

  Future<void> _ackReminderById(String id) async {
    await ApiService.instance.acknowledgeReminder(reminderId: id, patientId: _patientId);
    SocketService.instance.emitReminderAck(_patientId, id);
    _loadReminders();
  }

  void _setStatus(String msg) => setState(() {
        _status = msg; _isRecording = false; _isProcessing = false;
      });

  Color get _emotionColor => emotionColor(_emotion);

  // ── Build ─────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    final wide = isWideScreen(context);
    return Scaffold(
      backgroundColor: const Color(0xFFF5F0E8),
      body: FadeTransition(
        opacity: _fadeAnim,
        child: Stack(children: [
          Positioned(top: -80, right: -60,
            child: _DecorCircle(size: 280, color: const Color(0xFF1A5276).withOpacity(0.06))),
          Positioned(bottom: -100, left: -80,
            child: _DecorCircle(size: 320, color: const Color(0xFF2E86AB).withOpacity(0.05))),

          wide ? _buildWideLayout() : _buildNarrowLayout(),

          // Reminder overlay always on top
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

  // ── Wide layout: sidebar + content ────────────────────────────────────────
  Widget _buildWideLayout() => Row(children: [
        _buildSidebar(),
        Expanded(child: _buildTabContent()),
      ]);

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
              const Text('AlzCare', style: TextStyle(color: Colors.white, fontSize: 20,
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
                Row(children: [
                  Container(width: 8, height: 8,
                      decoration: BoxDecoration(shape: BoxShape.circle, color: _emotionColor)),
                  const SizedBox(width: 6),
                  Text(_emotion, style: TextStyle(color: _emotionColor, fontSize: 11,
                      fontWeight: FontWeight.w600)),
                ]),
                const SizedBox(height: 8),
                Text(widget.session.patientName, style: const TextStyle(color: Colors.white,
                    fontSize: 15, fontWeight: FontWeight.w700)),
                const SizedBox(height: 2),
                Text(_patientId, style: const TextStyle(color: Colors.white54, fontSize: 11)),
              ]),
            ),
          ),
          const SizedBox(height: 24),
          const Divider(color: Colors.white12, indent: 20, endIndent: 20),
          const SizedBox(height: 8),
          SideNavItem(
            icon: Icons.mic_rounded, label: 'Speak',
            selected: _currentTab == _PatientTab.speak,
            onTap: () => setState(() => _currentTab = _PatientTab.speak),
          ),
          SideNavItem(
            icon: Icons.alarm_rounded, label: 'My Schedule',
            selected: _currentTab == _PatientTab.reminders,
            onTap: () => setState(() => _currentTab = _PatientTab.reminders),
            badgeCount: _reminders.where((r) => r.status == 'escalated').length,
          ),
          SideNavItem(
            icon: Icons.note_alt_outlined, label: 'My Notes',
            selected: _currentTab == _PatientTab.notes,
            onTap: () => setState(() => _currentTab = _PatientTab.notes),
          ),
          if (_activeReminder != null)
            GestureDetector(
              onTap: () => _reminderCtrl.forward(from: 0),
              child: Container(
                margin: const EdgeInsets.fromLTRB(12, 12, 12, 0),
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                decoration: BoxDecoration(
                  color: Colors.orange.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.orange.withOpacity(0.4)),
                ),
                child: const Row(children: [
                  Icon(Icons.alarm, color: Colors.orange, size: 16),
                  SizedBox(width: 8),
                  Expanded(child: Text('Reminder active',
                      style: TextStyle(color: Colors.orange, fontSize: 12,
                          fontWeight: FontWeight.w700))),
                ]),
              ),
            ),
          const Spacer(),
          const Divider(color: Colors.white12, indent: 20, endIndent: 20),
          SideNavItem(
            icon: Icons.logout_rounded, label: 'Switch Account',
            selected: false, onTap: widget.onSignOut,
          ),
          const SizedBox(height: 28),
        ]),
      );

  // ── Narrow layout: top bar + bottom nav ───────────────────────────────────
  Widget _buildNarrowLayout() => Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(
          backgroundColor: AlzColors.navy,
          foregroundColor: Colors.white,
          title: Row(children: [
            const Icon(Icons.favorite_rounded, size: 18),
            const SizedBox(width: 8),
            Text(widget.session.patientName,
                style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
          ]),
          actions: [
            if (_activeReminder != null)
              IconButton(
                icon: const Icon(Icons.alarm, color: Colors.orange),
                onPressed: () => _reminderCtrl.forward(from: 0),
              ),
            TextButton(
              onPressed: widget.onSignOut,
              child: const Text('Switch', style: TextStyle(color: Colors.white70)),
            ),
          ],
        ),
        body: _buildTabContent(),
        bottomNavigationBar: NavigationBar(
          selectedIndex: _currentTab.index,
          onDestinationSelected: (i) =>
              setState(() => _currentTab = _PatientTab.values[i]),
          destinations: [
            const NavigationDestination(
              icon: Icon(Icons.mic_outlined),
              selectedIcon: Icon(Icons.mic_rounded),
              label: 'Speak',
            ),
            NavigationDestination(
              icon: Badge(
                isLabelVisible: _reminders.any((r) => r.status == 'escalated'),
                child: const Icon(Icons.alarm_outlined),
              ),
              selectedIcon: const Icon(Icons.alarm_rounded),
              label: 'Schedule',
            ),
            const NavigationDestination(
              icon: Icon(Icons.note_alt_outlined),
              selectedIcon: Icon(Icons.note_alt_rounded),
              label: 'Notes',
            ),
          ],
        ),
      );

  Widget _buildTabContent() {
    return switch (_currentTab) {
      _PatientTab.speak     => _buildSpeakTab(),
      _PatientTab.reminders => _buildRemindersTab(),
      _PatientTab.notes     => _buildNotesTab(),
    };
  }

  // ══════════════════════════════════════════════════════════════════════════
  // SPEAK TAB
  // ══════════════════════════════════════════════════════════════════════════
  Widget _buildSpeakTab() => SingleChildScrollView(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 680),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 40),
              child: Column(children: [
                _buildGreetingCard(),
                const SizedBox(height: 28),
                if (_transcript.isNotEmpty) ...[
                  _buildTranscriptCard(),
                  const SizedBox(height: 20),
                ],
                _buildStatusBubble(),
                const SizedBox(height: 48),
                _buildMicButton(),
                const SizedBox(height: 18),
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
                    style: TextStyle(fontSize: 15, height: 1.5,
                        color: _isRecording ? const Color(0xFFB03A2E) : Colors.black38),
                  ),
                ),
                const SizedBox(height: 48),
              ]),
            ),
          ),
        ),
      );

  Widget _buildGreetingCard() => Container(
        width: double.infinity,
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: Colors.black.withOpacity(0.06)),
          boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.04),
              blurRadius: 16, offset: const Offset(0, 4))],
        ),
        child: Column(children: [
          Builder(builder: (_) {
            final hour = DateTime.now().hour;
            final greeting = hour < 12 ? 'Good morning' : hour < 18 ? 'Good afternoon' : 'Good evening';
            final icon = hour < 12 ? '🌤' : hour < 18 ? '☀️' : '🌙';
            return Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              Text(icon, style: const TextStyle(fontSize: 20)),
              const SizedBox(width: 8),
              Text(greeting, style: const TextStyle(fontSize: 16,
                  fontWeight: FontWeight.w600, color: AlzColors.navy)),
            ]);
          }),
          const SizedBox(height: 8),
          Text(widget.session.patientName, style: const TextStyle(fontSize: 28,
              fontWeight: FontWeight.w800, color: AlzColors.textDark, height: 1.1)),
          const SizedBox(height: 6),
          Text("I'm your AI companion. I'm here to listen and help.",
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 14, color: Colors.black38, height: 1.5)),
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
          const Icon(Icons.record_voice_over_rounded, color: Colors.black26, size: 18),
          const SizedBox(width: 10),
          Expanded(child: Text(_transcript, style: const TextStyle(fontSize: 14,
              color: Colors.black45, fontStyle: FontStyle.italic, height: 1.5))),
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
        if (_emotion != 'Neutral') ...[EmotionChip(_emotion), const SizedBox(height: 12)],
        Text(
          _status.isEmpty ? "I'm ready to listen. Tap the microphone below." : _status,
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 19, height: 1.55,
              fontWeight: FontWeight.w500, color: color.withOpacity(0.85)),
        ),
      ]),
    );
  }

  Widget _buildMicButton() {
    final isActive  = _isRecording;
    final baseColor = isActive ? const Color(0xFFB03A2E) : AlzColors.navy;
    return SizedBox(
      width: 180, height: 180,
      child: Stack(alignment: Alignment.center, children: [
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
                    child: Container(width: 160, height: 160,
                        decoration: BoxDecoration(shape: BoxShape.circle,
                            color: baseColor.withOpacity(0.15))),
                  ),
                );
              }).toList(),
            ),
          ),
        AnimatedBuilder(
          animation: isActive ? _pulseScale : kAlwaysCompleteAnimation,
          builder: (_, child) => Transform.scale(
              scale: isActive ? _pulseScale.value : 1.0, child: child),
          child: MouseRegion(
            cursor: _isProcessing ? SystemMouseCursors.wait : SystemMouseCursors.click,
            onEnter: (_) => setState(() => _micHovered = true),
            onExit:  (_) => setState(() => _micHovered = false),
            child: GestureDetector(
              onTap: _onMicTap,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                width: 160, height: 160,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: RadialGradient(colors: isActive
                      ? [const Color(0xFFD85A30), const Color(0xFFB03A2E)]
                      : _micHovered
                          ? [const Color(0xFF2E86AB), const Color(0xFF1A5276)]
                          : [const Color(0xFF1A5276), const Color(0xFF0F3A50)]),
                  boxShadow: [BoxShadow(
                      color: baseColor.withOpacity(_micHovered ? 0.5 : 0.3),
                      blurRadius: _micHovered ? 40 : 24,
                      spreadRadius: _micHovered ? 6 : 2)],
                ),
                child: _isProcessing
                    ? const Center(child: SizedBox(width: 44, height: 44,
                        child: CircularProgressIndicator(color: Colors.white, strokeWidth: 3)))
                    : Icon(isActive ? Icons.stop_rounded : Icons.mic_rounded,
                        size: 80, color: Colors.white),
              ),
            ),
          ),
        ),
      ]),
    );
  }

  // ══════════════════════════════════════════════════════════════════════════
  // REMINDERS TAB
  // ══════════════════════════════════════════════════════════════════════════
  Widget _buildRemindersTab() => Column(children: [
        Container(
          padding: const EdgeInsets.fromLTRB(24, 28, 24, 20),
          decoration: BoxDecoration(
            color: Colors.white,
            border: Border(bottom: BorderSide(color: Colors.black.withOpacity(0.07))),
          ),
          child: Row(children: [
            Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('My Schedule', style: TextStyle(fontSize: 24,
                  fontWeight: FontWeight.w800, color: AlzColors.textDark)),
              Text('Your reminders for today',
                  style: TextStyle(fontSize: 14, color: Colors.black38)),
            ]),
            const Spacer(),
            IconButton(
              onPressed: () { setState(() => _loadingReminders = true); _loadReminders(); },
              icon: const Icon(Icons.refresh_rounded, color: AlzColors.navy),
              tooltip: 'Refresh',
            ),
          ]),
        ),
        Expanded(
          child: _loadingReminders
              ? const Center(child: CircularProgressIndicator())
              : _reminders.isEmpty
                  ? const EmptyState(
                      icon: Icons.alarm_off_rounded,
                      title: 'No reminders yet',
                      subtitle: 'Your caregiver hasn\'t added any reminders yet')
                  : RefreshIndicator(
                      onRefresh: _loadReminders,
                      child: ListView.builder(
                        padding: const EdgeInsets.all(20),
                        itemCount: _reminders.length,
                        itemBuilder: (_, i) => _patientReminderCard(_reminders[i]),
                      ),
                    ),
        ),
      ]);

  Widget _patientReminderCard(Reminder r) {
    Color statusColor;
    String statusLabel;
    IconData statusIcon;
    switch (r.status) {
      case 'escalated':
        statusColor = AlzColors.red;   statusLabel = 'NEEDS ATTENTION'; statusIcon = Icons.warning_rounded;  break;
      case 'completed':
        statusColor = AlzColors.green; statusLabel = 'DONE ✓';          statusIcon = Icons.check_circle;     break;
      case 'paused':
        statusColor = AlzColors.grey;  statusLabel = 'PAUSED';           statusIcon = Icons.pause_circle;     break;
      default:
        statusColor = AlzColors.navy;  statusLabel = 'UPCOMING';         statusIcon = Icons.alarm_rounded;
    }

    final isPending = r.status == 'pending' || r.status == 'escalated';

    return AlzCard(
      borderColor: r.status == 'escalated' ? AlzColors.red : null,
      padding: const EdgeInsets.all(18),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Container(
            width: 52, height: 52,
            decoration: BoxDecoration(color: statusColor.withOpacity(0.12),
                borderRadius: BorderRadius.circular(14)),
            child: Icon(statusIcon, color: statusColor, size: 28),
          ),
          const SizedBox(width: 14),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(r.task, style: const TextStyle(fontSize: 18,
                fontWeight: FontWeight.w700, color: AlzColors.textDark)),
            const SizedBox(height: 4),
            Row(children: [
              const Icon(Icons.access_time_rounded, size: 14, color: Colors.black38),
              const SizedBox(width: 4),
              Text('${r.time}  ·  ${r.frequency}',
                  style: const TextStyle(fontSize: 13, color: Colors.black45)),
              const SizedBox(width: 10),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(color: statusColor.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(6)),
                child: Text(statusLabel, style: TextStyle(fontSize: 11,
                    fontWeight: FontWeight.w700, color: statusColor)),
              ),
            ]),
          ])),
        ]),

        // Action buttons for pending/escalated
        if (isPending) ...[
          const SizedBox(height: 14),
          const Divider(height: 1),
          const SizedBox(height: 12),
          Row(children: [
            Expanded(child: _ReminderActionButton(
              label: "Done! ✓",
              color: AlzColors.green,
              icon: Icons.check_circle_outline_rounded,
              onTap: () => _ackReminderById(r.id),
            )),
            const SizedBox(width: 8),
            Expanded(child: _ReminderActionButton(
              label: "Snooze",
              color: AlzColors.navy,
              icon: Icons.snooze_rounded,
              onTap: () => _snoozeReminder(id: r.id),
            )),
            const SizedBox(width: 8),
            Expanded(child: _ReminderActionButton(
              label: "Later",
              color: AlzColors.grey,
              icon: Icons.notifications_off_outlined,
              onTap: () => _dismissReminder(id: r.id),
            )),
          ]),
        ],

        // Completed congratulation
        if (r.status == 'completed') ...[
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: AlzColors.green.withOpacity(0.08),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Row(children: [
              Icon(Icons.check_circle, color: AlzColors.green, size: 16),
              SizedBox(width: 6),
              Text("Great job! You completed this task.",
                  style: TextStyle(fontSize: 13, color: AlzColors.green,
                      fontWeight: FontWeight.w600)),
            ]),
          ),
        ],
      ]),
    );
  }

  // ══════════════════════════════════════════════════════════════════════════
  // NOTES TAB
  // ══════════════════════════════════════════════════════════════════════════
  Widget _buildNotesTab() => Column(children: [
        Container(
          padding: const EdgeInsets.fromLTRB(24, 28, 24, 20),
          decoration: BoxDecoration(
            color: Colors.white,
            border: Border(bottom: BorderSide(color: Colors.black.withOpacity(0.07))),
          ),
          child: Row(children: [
            Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('My Notes', style: TextStyle(fontSize: 24,
                  fontWeight: FontWeight.w800, color: AlzColors.textDark)),
              Text('Your daily notes and caregiver updates',
                  style: TextStyle(fontSize: 14, color: Colors.black38)),
            ]),
            const Spacer(),
            MouseRegion(
              cursor: SystemMouseCursors.click,
              child: GestureDetector(
                onTap: _showAddNoteDialog,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                  decoration: BoxDecoration(
                    color: AlzColors.ocean,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Row(mainAxisSize: MainAxisSize.min, children: [
                    Icon(Icons.add_rounded, color: Colors.white, size: 18),
                    SizedBox(width: 6),
                    Text('Add Note', style: TextStyle(color: Colors.white,
                        fontSize: 14, fontWeight: FontWeight.w700)),
                  ]),
                ),
              ),
            ),
          ]),
        ),
        Expanded(
          child: _loadingNotes
              ? const Center(child: CircularProgressIndicator())
              : _notes.isEmpty
                  ? _buildNotesEmpty()
                  : RefreshIndicator(
                      onRefresh: _loadNotes,
                      child: ListView.builder(
                        padding: const EdgeInsets.all(20),
                        itemCount: _notes.length,
                        itemBuilder: (_, i) => _patientNoteCard(_notes[i]),
                      ),
                    ),
        ),
      ]);

  Widget _buildNotesEmpty() => Center(
        child: Padding(
          padding: const EdgeInsets.all(48),
          child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
            Container(
              width: 80, height: 80,
              decoration: BoxDecoration(
                color: AlzColors.ocean.withOpacity(0.08),
                borderRadius: BorderRadius.circular(20),
              ),
              child: const Icon(Icons.note_alt_outlined, size: 40, color: AlzColors.ocean),
            ),
            const SizedBox(height: 20),
            const Text('No notes yet', style: TextStyle(fontSize: 20,
                fontWeight: FontWeight.w700, color: Colors.black38)),
            const SizedBox(height: 8),
            const Text('Add a note about how you\'re feeling today.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 15, color: Colors.black26, height: 1.5)),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: _showAddNoteDialog,
              icon: const Icon(Icons.add_rounded),
              label: const Text('Write your first note'),
              style: ElevatedButton.styleFrom(
                backgroundColor: AlzColors.ocean,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ),
          ]),
        ),
      );

  Widget _patientNoteCard(CaregiverNote n) {
    final time = DateFormat('MMM d, hh:mm a').format(n.createdAt.toLocal());
    // A note is "mine" if caregiverId is blank or matches the patientId
    final isOwnNote = n.caregiverId.isEmpty || n.caregiverId == _patientId;

    return AlzCard(
      borderColor: isOwnNote ? AlzColors.ocean : null,
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Container(
            width: 36, height: 36,
            decoration: BoxDecoration(
              color: isOwnNote
                  ? AlzColors.ocean.withOpacity(0.12)
                  : Colors.black.withOpacity(0.05),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(
              isOwnNote ? Icons.person_rounded : Icons.medical_services_outlined,
              color: isOwnNote ? AlzColors.ocean : Colors.black38,
              size: 18,
            ),
          ),
          const SizedBox(width: 10),
          Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(
              isOwnNote ? 'My note' : 'From my caregiver',
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700,
                  color: isOwnNote ? AlzColors.ocean : Colors.black45),
            ),
            Text(time, style: const TextStyle(fontSize: 12, color: Colors.black38)),
          ]),
        ]),
        const SizedBox(height: 12),
        Text(n.note, style: const TextStyle(fontSize: 16, height: 1.5,
            color: AlzColors.textDark)),
      ]),
    );
  }

  void _showAddNoteDialog() {
    final ctrl = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('Add a Note', style: TextStyle(fontSize: 20,
            fontWeight: FontWeight.w700)),
        content: SizedBox(
          width: 440,
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const Text(
              'Write something about how you\'re feeling, what you did today, or anything you want to remember.',
              style: TextStyle(fontSize: 14, color: Colors.black54, height: 1.5),
            ),
            const SizedBox(height: 14),
            AlzTextField(ctrl, 'Your note', Icons.edit_note_rounded,
                maxLines: 4,
                hint: 'e.g. I had a good morning. Feeling a bit tired today.'),
          ]),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
                backgroundColor: AlzColors.ocean, foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
            onPressed: () async {
              final text = ctrl.text.trim();
              if (text.isEmpty) return;
              Navigator.pop(ctx);
              await ApiService.instance.embedAndStore(
                patientId: _patientId,
                collection: 'notes',
                text: text,
              );
              _loadNotes();
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }

  // ══════════════════════════════════════════════════════════════════════════
  // REMINDER OVERLAY (popup when reminder fires via socket)
  // ══════════════════════════════════════════════════════════════════════════
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
                  boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.25),
                      blurRadius: 40, offset: const Offset(0, 16))],
                ),
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  Container(
                    padding: const EdgeInsets.fromLTRB(24, 24, 24, 20),
                    decoration: const BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topLeft, end: Alignment.bottomRight,
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
                              borderRadius: BorderRadius.circular(12)),
                          child: const Icon(Icons.alarm_rounded, color: Colors.white, size: 26),
                        ),
                        const SizedBox(width: 14),
                        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          const Text('Time for your reminder',
                              style: TextStyle(color: Colors.white70, fontSize: 13,
                                  fontWeight: FontWeight.w500)),
                          Text('Nudge ${reminder.attempts} of ${reminder.maxAttempts}',
                              style: TextStyle(color: Colors.white.withOpacity(0.6), fontSize: 12)),
                        ])),
                        Row(children: List.generate(reminder.maxAttempts, (i) => Container(
                          width: 8, height: 8, margin: const EdgeInsets.only(left: 4),
                          decoration: BoxDecoration(shape: BoxShape.circle,
                              color: i < reminder.attempts
                                  ? Colors.white : Colors.white.withOpacity(0.3)),
                        ))),
                      ]),
                      const SizedBox(height: 18),
                      Text(
                        reminder.task.isNotEmpty
                            ? 'It\'s time to ${reminder.task}'
                            : 'You have a reminder',
                        textAlign: TextAlign.center,
                        style: const TextStyle(color: Colors.white, fontSize: 24,
                            fontWeight: FontWeight.w800, height: 1.2),
                      ),
                    ]),
                  ),
                  Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(children: [
                      MouseRegion(
                        cursor: SystemMouseCursors.click,
                        child: GestureDetector(
                          onTap: _acknowledgeReminder,
                          child: Container(
                            width: double.infinity,
                            padding: const EdgeInsets.symmetric(vertical: 18),
                            decoration: BoxDecoration(
                              gradient: const LinearGradient(
                                  colors: [Color(0xFF1D8348), Color(0xFF27AE60)]),
                              borderRadius: BorderRadius.circular(16),
                              boxShadow: [BoxShadow(
                                  color: const Color(0xFF1D8348).withOpacity(0.35),
                                  blurRadius: 16, offset: const Offset(0, 6))],
                            ),
                            child: const Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                              Icon(Icons.check_circle_rounded, color: Colors.white, size: 26),
                              SizedBox(width: 10),
                              Text("Yes, I've done it!", style: TextStyle(color: Colors.white,
                                  fontSize: 20, fontWeight: FontWeight.w800)),
                            ]),
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      Row(children: [
                        Expanded(child: _SecondaryBtn(
                          icon: Icons.snooze_rounded, label: 'Snooze 10 min',
                          color: const Color(0xFF1A5276), onTap: _snoozeReminder,
                        )),
                        const SizedBox(width: 10),
                        Expanded(child: _SecondaryBtn(
                          icon: Icons.notifications_off_rounded, label: 'Dismiss',
                          color: const Color(0xFF888780), onTap: _dismissReminder,
                        )),
                      ]),
                      const SizedBox(height: 10),
                      Text(
                        'You can also say "Yes, I\'ve done it" into the microphone',
                        textAlign: TextAlign.center,
                        style: TextStyle(fontSize: 12, color: Colors.black38, height: 1.5),
                      ),
                    ]),
                  ),
                ]),
              ),
            ),
          ),
        ),
      ),
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

class _ReminderActionButton extends StatefulWidget {
  final String       label;
  final Color        color;
  final IconData     icon;
  final VoidCallback onTap;
  const _ReminderActionButton({required this.label, required this.color,
      required this.icon, required this.onTap});
  @override
  State<_ReminderActionButton> createState() => _ReminderActionButtonState();
}

class _ReminderActionButtonState extends State<_ReminderActionButton> {
  bool _hovered = false;
  @override
  Widget build(BuildContext context) => MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => setState(() => _hovered = true),
        onExit:  (_) => setState(() => _hovered = false),
        child: GestureDetector(
          onTap: widget.onTap,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 160),
            padding: const EdgeInsets.symmetric(vertical: 10),
            decoration: BoxDecoration(
              color: _hovered
                  ? widget.color.withOpacity(0.12)
                  : widget.color.withOpacity(0.07),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: widget.color.withOpacity(0.3), width: 1.5),
            ),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Icon(widget.icon, color: widget.color, size: 20),
              const SizedBox(height: 3),
              Text(widget.label, style: TextStyle(color: widget.color,
                  fontSize: 12, fontWeight: FontWeight.w700)),
            ]),
          ),
        ),
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
        onEnter: (_) => setState(() => _hovered = true),
        onExit:  (_) => setState(() => _hovered = false),
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
              Text(widget.label, style: TextStyle(color: widget.color,
                  fontSize: 12, fontWeight: FontWeight.w700)),
            ]),
          ),
        ),
      );
}