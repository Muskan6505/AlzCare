// flutter-app/lib/screens/caregiver_screen.dart
// Caregiver web dashboard — full sidebar navigation for desktop,
// bottom-tab fallback for mobile web.
// 4 sections: Reminders | Notes | Memories | Distress History

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../models/models.dart';
import '../services/api_service.dart';
import '../services/socket_service.dart';
import '../widgets/shared_widgets.dart';

enum _CaregiverSection { reminders, notes, memories, distress }

class CaregiverScreen extends StatefulWidget {
  final AppSession session;
  final VoidCallback onSignOut;

  CaregiverScreen({
    super.key,
    required this.session,
    required this.onSignOut,
  }) : assert(session.caregiverId != null && session.caregiverId != '');

  @override
  State<CaregiverScreen> createState() => _CaregiverScreenState();
}

class _CaregiverScreenState extends State<CaregiverScreen> {
  _CaregiverSection _section = _CaregiverSection.reminders;

  String get _patientId => widget.session.patientId;
  String get _caregiverId => widget.session.caregiverId!;

  List<Reminder>      _reminders    = [];
  List<CaregiverNote> _notes        = [];
  List<PatientMemory> _memories     = [];
  List<DistressEntry> _distressLogs = [];
  List<SocketEvent>   _liveAlerts   = [];

  bool _loadingReminders = true;
  bool _loadingNotes     = true;
  bool _loadingMemories  = true;
  bool _loadingLogs      = true;

  StreamSubscription<SocketEvent>? _socketSub;

  @override
  void initState() {
    super.initState();
    _loadAll();
    _subscribeSocket();
  }

  @override
  void dispose() {
    _socketSub?.cancel();
    super.dispose();
  }

  void _subscribeSocket() {
    SocketService.instance.connectAsCaregiver(_caregiverId, _patientId);
    _socketSub = SocketService.instance.eventStream.listen((e) {
      if (!mounted) return;
      setState(() => _liveAlerts.insert(0, e));
      if (e.type == SocketEventType.distressAlert) _showDistressBanner(e);
      if (e.type == SocketEventType.reminderAck)   { _showAckSnackbar(e); _loadReminders(); }
    });
  }

  Future<void> _loadAll() => Future.wait([
        _loadReminders(), _loadNotes(), _loadMemories(), _loadLogs()
      ]);

  Future<void> _loadReminders() async {
    final d = await ApiService.instance.fetchReminders(_patientId);
    if (mounted) setState(() { _reminders = d; _loadingReminders = false; });
  }
  Future<void> _loadNotes() async {
    final d = await ApiService.instance.fetchNotes(_patientId);
    if (mounted) setState(() { _notes = d; _loadingNotes = false; });
  }
  Future<void> _loadMemories() async {
    final d = await ApiService.instance.fetchMemories(_patientId);
    if (mounted) setState(() { _memories = d; _loadingMemories = false; });
  }
  Future<void> _loadLogs() async {
    final d = await ApiService.instance.fetchDistressLogs(_patientId);
    if (mounted) setState(() { _distressLogs = d; _loadingLogs = false; });
  }

  // ── Live alerts ───────────────────────────────────────────────────────────
  void _showDistressBanner(SocketEvent e) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showMaterialBanner(MaterialBanner(
      backgroundColor: AlzColors.red,
      leading: const Icon(Icons.warning_rounded, color: Colors.white, size: 30),
      content: Text(
        '🚨 DISTRESS (${e.emotion}) — "${e.transcript}"',
        style: const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w600),
      ),
      actions: [TextButton(
        onPressed: () => ScaffoldMessenger.of(context).hideCurrentMaterialBanner(),
        child: const Text('DISMISS', style: TextStyle(color: Colors.white70, fontWeight: FontWeight.w700)),
      )],
    ));
    Future.delayed(const Duration(seconds: 10), () {
      if (mounted) ScaffoldMessenger.of(context).hideCurrentMaterialBanner();
    });
  }

  void _showAckSnackbar(SocketEvent e) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      backgroundColor: AlzColors.green,
      content: Text('✅ Patient acknowledged: "${e.task}"',
          style: const TextStyle(color: Colors.white, fontSize: 15)),
      duration: const Duration(seconds: 5),
    ));
  }

  // ── Build ──────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    final wide = isWideScreen(context);
    return Scaffold(
      backgroundColor: AlzColors.warm,
      body: wide ? _buildWideLayout() : _buildNarrowLayout(),
    );
  }

  // ── Wide screen: sidebar + content ────────────────────────────────────────
  Widget _buildWideLayout() => Row(children: [
        _buildSidebar(),
        Expanded(child: _buildContent()),
      ]);

  Widget _buildSidebar() => Container(
        width: 240,
        color: AlzColors.navy,
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const SizedBox(height: 32),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: const Row(children: [
              Icon(Icons.medical_services_rounded, color: Colors.white, size: 24),
              SizedBox(width: 10),
              Flexible(child: Text('AlzCare', style: TextStyle(
                  color: Colors.white, fontSize: 20, fontWeight: FontWeight.w800))),
            ]),
          ),
          const Padding(
            padding: EdgeInsets.only(left: 20, top: 4),
            child: Text('Caregiver Dashboard',
                style: TextStyle(color: Colors.white54, fontSize: 12)),
          ),
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
                  'Patient: $_patientId',
                  style: const TextStyle(color: Colors.white70, fontSize: 12),
                ),
                const SizedBox(height: 2),
                Text(
                  'Caregiver: $_caregiverId',
                  style: const TextStyle(color: Colors.white70, fontSize: 12),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          const Divider(color: Colors.white12, indent: 20, endIndent: 20),
          const SizedBox(height: 8),
          SideNavItem(
            icon: Icons.alarm, label: 'Reminders',
            selected: _section == _CaregiverSection.reminders,
            onTap: () => setState(() => _section = _CaregiverSection.reminders),
          ),
          SideNavItem(
            icon: Icons.note_alt_outlined, label: 'Daily Notes',
            selected: _section == _CaregiverSection.notes,
            onTap: () => setState(() => _section = _CaregiverSection.notes),
          ),
          SideNavItem(
            icon: Icons.psychology, label: 'Memories',
            selected: _section == _CaregiverSection.memories,
            onTap: () => setState(() => _section = _CaregiverSection.memories),
          ),
          SideNavItem(
            icon: Icons.history, label: 'Distress History',
            selected: _section == _CaregiverSection.distress,
            onTap: () => setState(() => _section = _CaregiverSection.distress),
            badgeCount: _liveAlerts.where((a) => a.type == SocketEventType.distressAlert).length,
          ),
          const Spacer(),
          const Divider(color: Colors.white12, indent: 20, endIndent: 20),
          SideNavItem(
            icon: Icons.logout_rounded, label: 'Switch Account',
            selected: false, onTap: widget.onSignOut,
          ),
          // Live alerts indicator
          if (_liveAlerts.isNotEmpty)
            GestureDetector(
              onTap: _showAlertsPanel,
              child: Container(
                margin: const EdgeInsets.fromLTRB(12, 8, 12, 0),
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                decoration: BoxDecoration(
                  color: AlzColors.red.withOpacity(0.18),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: AlzColors.red.withOpacity(0.4)),
                ),
                child: Row(children: [
                  const Icon(Icons.notifications_active, color: AlzColors.red, size: 18),
                  const SizedBox(width: 8),
                  Text('${_liveAlerts.length} live alert${_liveAlerts.length == 1 ? '' : 's'}',
                      style: const TextStyle(
                          color: AlzColors.red, fontSize: 13, fontWeight: FontWeight.w700)),
                ]),
              ),
            ),
          const SizedBox(height: 24),
        ]),
      );

  // ── Narrow (mobile web): bottom tabs ──────────────────────────────────────
  Widget _buildNarrowLayout() => Scaffold(
        backgroundColor: AlzColors.warm,
        appBar: AppBar(
          backgroundColor: AlzColors.navy,
          foregroundColor: Colors.white,
          title: const Text('AlzCare — Caregiver',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
          actions: [
            if (_liveAlerts.isNotEmpty)
              IconButton(
                icon: const Icon(Icons.notifications_active),
                onPressed: _showAlertsPanel,
              ),
            TextButton(
              onPressed: widget.onSignOut,
              child: const Text('Switch', style: TextStyle(color: Colors.white70)),
            ),
          ],
        ),
        body: _buildContent(),
        bottomNavigationBar: NavigationBar(
          selectedIndex: _section.index,
          onDestinationSelected: (i) =>
              setState(() => _section = _CaregiverSection.values[i]),
          destinations: const [
            NavigationDestination(icon: Icon(Icons.alarm), label: 'Reminders'),
            NavigationDestination(icon: Icon(Icons.note_alt_outlined), label: 'Notes'),
            NavigationDestination(icon: Icon(Icons.psychology), label: 'Memories'),
            NavigationDestination(icon: Icon(Icons.history), label: 'Distress'),
          ],
        ),
      );

  Widget _buildContent() {
    return switch (_section) {
      _CaregiverSection.reminders => _buildRemindersPage(),
      _CaregiverSection.notes     => _buildNotesPage(),
      _CaregiverSection.memories  => _buildMemoriesPage(),
      _CaregiverSection.distress  => _buildDistressPage(),
    };
  }

  // ── Section header bar ─────────────────────────────────────────────────────
  Widget _sectionHeader(String title, String subtitle,
      {required Widget action}) =>
      Container(
        padding: const EdgeInsets.fromLTRB(32, 28, 32, 20),
        decoration: BoxDecoration(
          color: Colors.white,
          border: Border(bottom: BorderSide(color: Colors.black.withOpacity(0.07))),
        ),
        child: Row(children: [
          Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(title, style: const TextStyle(
                fontSize: 24, fontWeight: FontWeight.w800, color: AlzColors.textDark)),
            Text(subtitle, style: const TextStyle(fontSize: 14, color: Colors.black38)),
          ]),
          const Spacer(),
          action,
        ]),
      );

  Widget _webAddButton(String label, IconData icon, VoidCallback onTap) =>
      MouseRegion(
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
            decoration: BoxDecoration(
              color: AlzColors.navy,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Icon(icon, color: Colors.white, size: 18),
              const SizedBox(width: 8),
              Text(label, style: const TextStyle(
                  color: Colors.white, fontSize: 14, fontWeight: FontWeight.w700)),
            ]),
          ),
        ),
      );

  // ────────────────────────────────────────────────────────────────────────────
  // REMINDERS PAGE
  // ────────────────────────────────────────────────────────────────────────────
  Widget _buildRemindersPage() => Column(children: [
        _sectionHeader('Reminders', 'Persistent Nagger — up to 3 nudges',
            action: _webAddButton('Add Reminder', Icons.add, _showAddReminderDialog)),
        Expanded(
          child: _loadingReminders
              ? const Center(child: CircularProgressIndicator())
              : _reminders.isEmpty
                  ? const EmptyState(
                      icon: Icons.alarm_off,
                      title: 'No reminders yet',
                      subtitle: 'Add a scheduled reminder for the patient')
                  : RefreshIndicator(
                      onRefresh: _loadReminders,
                      child: ListView.builder(
                        padding: const EdgeInsets.all(28),
                        itemCount: _reminders.length,
                        itemBuilder: (_, i) => _reminderCard(_reminders[i]),
                      ),
                    ),
        ),
      ]);

  Widget _reminderCard(Reminder r) {
    Color statusColor;
    String statusLabel;
    IconData statusIcon;
    switch (r.status) {
      case 'escalated':
        statusColor = AlzColors.red;    statusLabel = 'ESCALATED'; statusIcon = Icons.warning_rounded; break;
      case 'completed':
        statusColor = AlzColors.green;  statusLabel = 'DONE';      statusIcon = Icons.check_circle;    break;
      case 'paused':
        statusColor = AlzColors.grey;   statusLabel = 'PAUSED';    statusIcon = Icons.pause_circle;    break;
      default:
        statusColor = AlzColors.navy;   statusLabel = 'PENDING';   statusIcon = Icons.alarm;
    }

    return AlzCard(
      borderColor: r.isEscalated ? AlzColors.red : null,
      padding: const EdgeInsets.all(18),
      child: Row(children: [
        Container(
          width: 48, height: 48,
          decoration: BoxDecoration(
              color: statusColor.withOpacity(0.10),
              borderRadius: BorderRadius.circular(12)),
          child: Icon(statusIcon, color: statusColor, size: 26),
        ),
        const SizedBox(width: 16),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(r.task, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
          const SizedBox(height: 4),
          Row(children: [
            Text('${r.time}  ·  ${r.frequency}',
                style: const TextStyle(fontSize: 14, color: Colors.black45)),
            const SizedBox(width: 12),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: statusColor.withOpacity(0.10),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(statusLabel,
                  style: TextStyle(
                      fontSize: 11, fontWeight: FontWeight.w700, color: statusColor)),
            ),
            if (r.attempts > 0 && r.status == 'pending') ...[
              const SizedBox(width: 8),
              Text('${r.attempts} nudge${r.attempts == 1 ? '' : 's'} sent',
                  style: const TextStyle(
                      fontSize: 12, color: AlzColors.amber, fontWeight: FontWeight.w600)),
            ],
          ]),
        ])),
        Row(mainAxisSize: MainAxisSize.min, children: [
          if (r.status == 'pending' || r.status == 'escalated')
            _iconBtn(Icons.pause_rounded, AlzColors.ocean, 'Pause', () async {
              await ApiService.instance.toggleReminder(r.id, _patientId, 'paused');
              _loadReminders();
            }),
          if (r.status == 'paused')
            _iconBtn(Icons.play_arrow_rounded, AlzColors.green, 'Resume', () async {
              await ApiService.instance.toggleReminder(r.id, _patientId, 'pending');
              _loadReminders();
            }),
          _iconBtn(Icons.delete_outline, AlzColors.red, 'Delete', () async {
            await ApiService.instance.deleteReminder(r.id, _patientId);
            _loadReminders();
          }),
        ]),
      ]),
    );
  }

  Widget _iconBtn(IconData icon, Color color, String tooltip, VoidCallback onTap) =>
      MouseRegion(
        cursor: SystemMouseCursors.click,
        child: Tooltip(
          message: tooltip,
          child: GestureDetector(
            onTap: onTap,
            child: Container(
              margin: const EdgeInsets.only(left: 6),
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                  color: color.withOpacity(0.08), borderRadius: BorderRadius.circular(8)),
              child: Icon(icon, color: color, size: 22),
            ),
          ),
        ),
      );

  // ────────────────────────────────────────────────────────────────────────────
  // NOTES PAGE
  // ────────────────────────────────────────────────────────────────────────────
  Widget _buildNotesPage() => Column(children: [
        _sectionHeader("Daily Notes", "Short-term context fed into the AI",
            action: _webAddButton("Add Note", Icons.note_add, _showAddNoteDialog)),
        Expanded(
          child: _loadingNotes
              ? const Center(child: CircularProgressIndicator())
              : _notes.isEmpty
                  ? const EmptyState(
                      icon: Icons.note_alt_outlined,
                      title: "No notes yet",
                      subtitle: "Add today's context for the patient's AI")
                  : RefreshIndicator(
                      onRefresh: _loadNotes,
                      child: ListView.builder(
                        padding: const EdgeInsets.all(28),
                        itemCount: _notes.length,
                        itemBuilder: (_, i) {
                          final n    = _notes[i];
                          final time = DateFormat('MMM d, hh:mm a').format(n.createdAt.toLocal());
                          return AlzCard(
                            borderColor: AlzColors.ocean,
                            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                              Row(children: [
                                const Icon(Icons.note_alt, color: AlzColors.ocean, size: 18),
                                const SizedBox(width: 8),
                                Text(time, style: const TextStyle(fontSize: 13, color: Colors.black38)),
                              ]),
                              const SizedBox(height: 10),
                              Text(n.note, style: const TextStyle(fontSize: 16, height: 1.45)),
                            ]),
                          );
                        },
                      ),
                    ),
        ),
      ]);

  // ────────────────────────────────────────────────────────────────────────────
  // MEMORIES PAGE
  // ────────────────────────────────────────────────────────────────────────────
  Widget _buildMemoriesPage() => Column(children: [
        _sectionHeader("Long-term Memories", "Permanent context for the AI",
            action: _webAddButton("Add Memory", Icons.add_circle_outline, _showAddMemoryDialog)),
        Expanded(
          child: _loadingMemories
              ? const Center(child: CircularProgressIndicator())
              : _memories.isEmpty
                  ? const EmptyState(
                      icon: Icons.psychology,
                      title: 'No memories yet',
                      subtitle: "Add the patient's life history and key facts")
                  : RefreshIndicator(
                      onRefresh: _loadMemories,
                      child: ListView.builder(
                        padding: const EdgeInsets.all(28),
                        itemCount: _memories.length,
                        itemBuilder: (_, i) {
                          final m = _memories[i];
                          return AlzCard(
                            child: Row(children: [
                              Container(
                                width: 44, height: 44,
                                decoration: BoxDecoration(
                                    color: AlzColors.softBlue,
                                    borderRadius: BorderRadius.circular(12)),
                                child: const Icon(Icons.psychology, color: AlzColors.navy, size: 22),
                              ),
                              const SizedBox(width: 16),
                              Expanded(child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(m.content,
                                        style: const TextStyle(fontSize: 16, height: 1.4)),
                                    if (m.tags.isNotEmpty) ...[
                                      const SizedBox(height: 6),
                                      Wrap(spacing: 6, children: m.tags
                                          .map((t) => Chip(
                                                label: Text(t, style: const TextStyle(fontSize: 11)),
                                                padding: EdgeInsets.zero,
                                                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                              ))
                                          .toList()),
                                    ],
                                  ])),
                            ]),
                          );
                        },
                      ),
                    ),
        ),
      ]);

  // ────────────────────────────────────────────────────────────────────────────
  // DISTRESS HISTORY PAGE
  // ────────────────────────────────────────────────────────────────────────────
  Widget _buildDistressPage() => Column(children: [
        _sectionHeader("Distress History", "Voice emotion timeline",
            action: _webAddButton("Refresh", Icons.refresh, _loadLogs)),
        Expanded(
          child: _loadingLogs
              ? const Center(child: CircularProgressIndicator())
              : _distressLogs.isEmpty
                  ? const EmptyState(
                      icon: Icons.sentiment_satisfied_alt,
                      title: 'No distress events',
                      subtitle: 'The patient has been calm — wonderful!')
                  : RefreshIndicator(
                      onRefresh: _loadLogs,
                      child: ListView.builder(
                        padding: const EdgeInsets.all(28),
                        itemCount: _distressLogs.length,
                        itemBuilder: (_, i) => _distressCard(_distressLogs[i]),
                      ),
                    ),
        ),
      ]);

  Widget _distressCard(DistressEntry e) {
    final color   = emotionColor(e.emotion);
    final timeStr = DateFormat('MMM d, hh:mm a').format(e.timestamp.toLocal());
    return AlzCard(
      borderColor: color,
      padding: const EdgeInsets.all(18),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Container(
          width: 8, height: 70, margin: const EdgeInsets.only(right: 16),
          decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(4)),
        ),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            EmotionChip(e.emotion),
            const SizedBox(width: 12),
            Text(timeStr, style: const TextStyle(fontSize: 13, color: Colors.black38)),
          ]),
          const SizedBox(height: 8),
          Text('"${e.transcript.isEmpty ? 'No transcript' : e.transcript}"',
              style: const TextStyle(fontSize: 15, fontStyle: FontStyle.italic, color: Colors.black54),
              maxLines: 2, overflow: TextOverflow.ellipsis),
          const SizedBox(height: 6),
          Text(
            'Pitch variance: ${e.pitchVariance.toStringAsFixed(1)}  ·  '
            'Silence: ${(e.silenceRatio * 100).toStringAsFixed(0)}%',
            style: const TextStyle(fontSize: 12, color: Colors.black38),
          ),
        ])),
      ]),
    );
  }

  // ── Dialogs ────────────────────────────────────────────────────────────────
  void _showAddReminderDialog() {
    final taskCtrl = TextEditingController();
    final timeCtrl = TextEditingController(text: '08:00');
    String freq = 'daily';
    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(builder: (_, sl) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('Add Reminder', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700)),
        content: SizedBox(
          width: 420,
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            AlzTextField(taskCtrl, 'Task (e.g. Take medication)', Icons.task_alt),
            const SizedBox(height: 14),
            AlzTextField(timeCtrl, 'Time  HH:MM  (24-hour)', Icons.access_time),
            const SizedBox(height: 14),
            DropdownButtonFormField<String>(
              initialValue: freq,
              decoration: InputDecoration(
                labelText: 'Frequency',
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              ),
              items: ['daily', 'weekdays', 'weekends']
                  .map((f) => DropdownMenuItem(value: f, child: Text(f)))
                  .toList(),
              onChanged: (v) => sl(() => freq = v ?? 'daily'),
            ),
          ]),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
                backgroundColor: AlzColors.navy, foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
            onPressed: () async {
              Navigator.pop(ctx);
              await ApiService.instance.addReminder(
                patientId: _patientId, task: taskCtrl.text.trim(),
                time: timeCtrl.text.trim(), frequency: freq,
              );
              _loadReminders();
            },
            child: const Text('Add'),
          ),
        ],
      )),
    );
  }

  void _showAddNoteDialog() {
    final ctrl = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text("Add Daily Note", style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700)),
        content: SizedBox(
          width: 440,
          child: AlzTextField(ctrl, "Note for today's context", Icons.note_alt_outlined,
              maxLines: 4,
              hint: "e.g. Robert felt lonely today. His daughter visits at 5 PM."),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
                backgroundColor: AlzColors.ocean, foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
            onPressed: () async {
              Navigator.pop(ctx);
              await ApiService.instance.embedAndStore(
                patientId: _patientId, collection: 'notes', text: ctrl.text.trim(),
              );
              _loadNotes();
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }

  void _showAddMemoryDialog() {
    final memCtrl = TextEditingController();
    final tagCtrl = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('Add Long-term Memory', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700)),
        content: SizedBox(
          width: 440,
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            AlzTextField(memCtrl, 'Memory content', Icons.psychology,
                hint: "e.g. Worked as a carpenter in Ohio for 40 years"),
            const SizedBox(height: 12),
            AlzTextField(tagCtrl, 'Tags (comma separated)', Icons.label_outline,
                hint: "career, family, hobbies"),
          ]),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
                backgroundColor: AlzColors.green, foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
            onPressed: () async {
              Navigator.pop(ctx);
              final tags = tagCtrl.text
                  .split(',').map((t) => t.trim()).where((t) => t.isNotEmpty).toList();
              await ApiService.instance.embedAndStore(
                patientId: _patientId, collection: 'memories',
                text: memCtrl.text.trim(), tags: tags,
              );
              _loadMemories();
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }

  void _showAlertsPanel() {
    showDialog(
      context: context,
      builder: (ctx) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        child: SizedBox(
          width: 480, height: 520,
          child: Column(children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 20, 16, 8),
              child: Row(children: [
                const Icon(Icons.notifications_active, color: AlzColors.red, size: 26),
                const SizedBox(width: 10),
                Text('Live Alerts (${_liveAlerts.length})',
                    style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700)),
                const Spacer(),
                TextButton(
                  onPressed: () { setState(() => _liveAlerts.clear()); Navigator.pop(ctx); },
                  child: const Text('Clear all'),
                ),
              ]),
            ),
            const Divider(height: 1),
            Expanded(
              child: _liveAlerts.isEmpty
                  ? const Center(child: Text('No alerts yet.'))
                  : ListView.separated(
                      padding: const EdgeInsets.all(16),
                      itemCount: _liveAlerts.length,
                      separatorBuilder: (_, __) => const Divider(height: 1),
                      itemBuilder: (_, i) {
                        final a = _liveAlerts[i];
                        final isD = a.type == SocketEventType.distressAlert;
                        final isA = a.type == SocketEventType.reminderAck;
                        return ListTile(
                          leading: Icon(
                            isD ? Icons.warning_rounded : isA ? Icons.check_circle : Icons.alarm,
                            color: isD ? AlzColors.red : isA ? AlzColors.green : AlzColors.navy,
                            size: 28,
                          ),
                          title: Text(
                            isD ? 'DISTRESS — ${a.emotion}'
                                : isA ? 'ACK: "${a.task}"'
                                : 'Reminder: "${a.task}"',
                            style: TextStyle(
                                fontSize: 15, fontWeight: FontWeight.w700,
                                color: isD ? AlzColors.red : isA ? AlzColors.green : AlzColors.navy),
                          ),
                          subtitle: a.data['timestamp'] != null
                              ? Text(a.data['timestamp'].toString(),
                                  style: const TextStyle(fontSize: 12))
                              : null,
                        );
                      },
                    ),
            ),
          ]),
        ),
      ),
    );
  }
}
