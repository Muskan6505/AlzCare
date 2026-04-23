// flutter-app/lib/models/models.dart
// Data models — identical between mobile and web.

class MultimodalResult {
  final String patientId;
  final String transcript;
  final String emotion;
  final bool   distressFlag;
  final String prosodicState;
  final String llmReply;
  final String audioUrl;
  final String? distressLogId;

  const MultimodalResult({
    required this.patientId, required this.transcript, required this.emotion,
    required this.distressFlag, required this.prosodicState, required this.llmReply,
    required this.audioUrl, this.distressLogId,
  });

  factory MultimodalResult.fromJson(Map<String, dynamic> j) => MultimodalResult(
    patientId:     j['patient_id']     ?? '',
    transcript:    j['transcript']     ?? '',
    emotion:       j['emotion']        ?? 'Neutral',
    distressFlag:  j['distress_flag']  ?? false,
    prosodicState: j['prosodic_state'] ?? 'normal',
    llmReply:      j['llm_reply']      ?? '',
    audioUrl:      j['audio_url']      ?? '',
    distressLogId: j['distress_log_id'],
  );
}

class PatientProfile {
  final String patientId;
  final String name;
  final List<String> caregiverIds;

  const PatientProfile({
    required this.patientId,
    required this.name,
    required this.caregiverIds,
  });

  factory PatientProfile.fromJson(Map<String, dynamic> j) => PatientProfile(
        patientId: j['patient_id'] ?? '',
        name: j['name'] ?? '',
        caregiverIds: List<String>.from(j['caregiver_ids'] ?? const []),
      );
}

enum UserRole { patient, caregiver }

class AppSession {
  final UserRole role;
  final String patientId;
  final String patientName;
  final String? caregiverId;

  const AppSession({
    required this.role,
    required this.patientId,
    required this.patientName,
    this.caregiverId,
  });

  bool get isCaregiver => role == UserRole.caregiver;

  Map<String, dynamic> toJson() => {
        'role': role.name,
        'patient_id': patientId,
        'patient_name': patientName,
        'caregiver_id': caregiverId,
      };

  factory AppSession.fromJson(Map<String, dynamic> j) => AppSession(
        role: (j['role'] == UserRole.caregiver.name)
            ? UserRole.caregiver
            : UserRole.patient,
        patientId: j['patient_id'] ?? '',
        patientName: j['patient_name'] ?? '',
        caregiverId: j['caregiver_id'],
      );
}

class Reminder {
  final String id;
  final String patientId;
  final String task;
  final String time;
  final String frequency;
  final String status;
  final int    attempts;

  const Reminder({
    required this.id, required this.patientId, required this.task,
    required this.time, required this.frequency, required this.status,
    required this.attempts,
  });

  factory Reminder.fromJson(Map<String, dynamic> j) => Reminder(
    id:        j['_id']?.toString() ?? '',
    patientId: j['patient_id']      ?? '',
    task:      j['task']            ?? '',
    time:      j['time']            ?? '',
    frequency: j['frequency']       ?? 'daily',
    status:    j['status']          ?? 'pending',
    attempts:  (j['attempts']       ?? 0) as int,
  );

  bool get isEscalated => status == 'escalated';
  bool get isCompleted => status == 'completed';
  bool get isPaused    => status == 'paused';
}

class CaregiverNote {
  final String   id;
  final String   patientId;
  final String   note;
  final String   caregiverId;
  final DateTime createdAt;

  const CaregiverNote({
    required this.id, required this.patientId, required this.note,
    required this.caregiverId, required this.createdAt,
  });

  factory CaregiverNote.fromJson(Map<String, dynamic> j) {
    DateTime ts;
    try { ts = DateTime.parse(j['created_at'].toString()); } catch (_) { ts = DateTime.now(); }
    return CaregiverNote(
      id: j['_id']?.toString() ?? '', patientId: j['patient_id'] ?? '',
      note: j['note'] ?? '', caregiverId: j['caregiver_id'] ?? '', createdAt: ts,
    );
  }
}

class PatientMemory {
  final String       id;
  final String       content;
  final List<String> tags;

  const PatientMemory({required this.id, required this.content, required this.tags});

  factory PatientMemory.fromJson(Map<String, dynamic> j) => PatientMemory(
    id: j['_id']?.toString() ?? '', content: j['content'] ?? '',
    tags: List<String>.from(j['tags'] ?? []),
  );
}

class DistressEntry {
  final String   id;
  final String   patientId;
  final DateTime timestamp;
  final String   transcript;
  final String   emotion;
  final bool     distressFlag;
  final double   pitchVariance;
  final double   silenceRatio;

  const DistressEntry({
    required this.id, required this.patientId, required this.timestamp,
    required this.transcript, required this.emotion, required this.distressFlag,
    required this.pitchVariance, required this.silenceRatio,
  });

  factory DistressEntry.fromJson(Map<String, dynamic> j) {
    DateTime ts;
    try { ts = DateTime.parse(j['timestamp'].toString()); } catch (_) { ts = DateTime.now(); }
    return DistressEntry(
      id: j['_id']?.toString() ?? '', patientId: j['patient_id'] ?? '',
      timestamp: ts, transcript: j['transcript'] ?? '',
      emotion: j['emotion'] ?? 'Neutral',
      distressFlag:  j['distressFlag']   ?? false,
      pitchVariance: (j['pitchVariance'] ?? 0).toDouble(),
      silenceRatio:  (j['silenceRatio']  ?? 0).toDouble(),
    );
  }
}

enum SocketEventType { playAudio, reminderAlert, distressAlert, reminderAck, unknown }

class SocketEvent {
  final SocketEventType       type;
  final Map<String, dynamic>  data;
  const SocketEvent({required this.type, required this.data});

  String get audioUrl     => data['audioUrl']     ?? '';
  String get task         => data['task']          ?? '';
  String get emotion      => data['emotion']       ?? '';
  String get transcript   => data['transcript']    ?? '';
  String get reminderId   => data['reminderId']    ?? '';
  String get reminderText => data['reminderText']  ?? '';
  int    get attempts     => (data['attempts']     ?? 0) as int;
  int    get maxAttempts  => (data['maxAttempts']  ?? 3) as int;
}
