# AlzCare v2 — "Compassionate Guardian"
## Alzheimer's AI Support System

```
alzcare_v2/
├── python-ai-pipeline/          # FastAPI — AI inference micro-service (port 8001)
│   ├── main.py                  # Startup — loads all models once
│   ├── requirements.txt         # ✅ NO cmake — pre-built wheels only
│   ├── .env.example
│   ├── routers/
│   │   └── pipeline.py          # /process-multimodal | /generate-reminder
│   │                            # /embed-and-store | /tts-speak | /tts-audio
│   └── utils/
│       ├── config.py            # Centralised env config
│       ├── stt.py               # faster-whisper (CTranslate2, CPU int8)
│       ├── emotion.py           # Wav2Vec2 emotion classifier (HuggingFace)
│       ├── embedder.py          # all-MiniLM-L6-v2 → 384-dim vectors
│       ├── llm.py               # ctransformers GGUF (no cmake)
│       ├── tts.py               # Azure Cognitive TTS — emotion-adaptive SSML
│       └── distress_analyser.py # librosa pitch/silence analysis
│
├── backend-nodejs/              # Express + Socket.io + Mongoose (port 4000)
│   ├── package.json
│   ├── .env.example
│   ├── config/
│   │   ├── database.js          # Mongoose → MongoDB Atlas
│   │   └── logger.js            # Winston
│   └── src/
│       ├── server.js            # HTTP + Socket.io + cron bootstrap
│       ├── app.js               # Express routes + middleware
│       ├── models/index.js      # 5 collections — all patient_id scoped
│       ├── routes/
│       │   ├── patients.js      # Patient profile CRUD
│       │   ├── memories.js      # Long-term RAG + Atlas Vector Search
│       │   ├── notes.js         # Short-term notes + Atlas Vector Search
│       │   ├── reminders.js     # Persistent Nagger CRUD + /ack endpoint
│       │   ├── distress.js      # Distress log write/read
│       │   └── alerts.js        # Agitation broadcast → Socket.io
│       ├── services/
│       │   └── reminderEngine.js # node-cron Persistent Nagger + web-push escalation
│       ├── sockets/
│       │   └── socketHub.js     # Socket.io rooms — patient + caregiver monitors
│       └── middleware/
│           └── errorHandler.js
│
└── flutter-app/                 # Flutter cross-platform UI
    ├── pubspec.yaml
    └── lib/
        ├── main.dart            # App entry + theme
        ├── models/models.dart   # All data models
        ├── screens/
        │   ├── patient_screen.dart   # Mic + emotion bubble + Nagger overlay
        │   └── caregiver_screen.dart # 4-tab dashboard
        ├── services/
        │   ├── app_config.dart  # Server URLs
        │   ├── api_service.dart # HTTP (http package)
        │   └── socket_service.dart # Socket.io auto-reconnect client
        └── widgets/
            └── shared_widgets.dart  # Colors, EmotionChip, ReminderBanner, etc.
```

---

## Service Port Map

| Service | Port | Protocol |
|---|---|---|
| Python AI Pipeline (FastAPI) | **8001** | HTTP |
| Node.js Backend (Express + Socket.io) | **4000** | HTTP + Socket.io |
| MongoDB Atlas | cloud | Mongoose driver |

---

## 1. MongoDB Atlas Setup

### A. Create a Free Cluster
1. Go to [cloud.mongodb.com](https://cloud.mongodb.com)
2. Create a free **M0** cluster
3. Create a database user and whitelist your IP
4. Copy the connection string into `backend-nodejs/.env`

### B. Create Vector Search Indexes
In Atlas UI → your cluster → **Search** tab → **Create Search Index** → **JSON editor**.

Create **two indexes** — one per collection:

**Index 1 — Patient_Memories**
- Index name: `vector_index`
- Collection: `alzcare.Patient_Memories`
```json
{
  "fields": [
    {
      "type": "vector",
      "path": "embedding",
      "numDimensions": 384,
      "similarity": "cosine"
    },
    {
      "type": "filter",
      "path": "patient_id"
    }
  ]
}
```

**Index 2 — Caregiver_Notes**
- Index name: `vector_index`
- Collection: `alzcare.Caregiver_Notes`
```json
{
  "fields": [
    {
      "type": "vector",
      "path": "embedding",
      "numDimensions": 384,
      "similarity": "cosine"
    },
    {
      "type": "filter",
      "path": "patient_id"
    }
  ]
}
```

> **Important:** The `filter` field on `patient_id` enables the strict patient isolation used in all `$vectorSearch` queries.

---

## 2. Python AI Pipeline Setup

### Prerequisites
- Python 3.10+
- FFmpeg: `sudo apt install ffmpeg` or `brew install ffmpeg`
- **No cmake needed** — uses `ctransformers` + `faster-whisper` (pre-built wheels)

### Install
```bash
cd python-ai-pipeline
cp .env.example .env
# Edit .env — add your AZURE_SPEECH_KEY and optionally LLM_MODEL_PATH

pip install -r requirements.txt
```

### Download LLM model (optional but recommended)
```bash
mkdir gguf_models
# Download Mistral 7B Instruct Q4_K_M (~4 GB) from:
# https://huggingface.co/TheBloke/Mistral-7B-Instruct-v0.2-GGUF
# Place the .gguf file inside gguf_models/ and set LLM_MODEL_PATH in .env
# Without a model, the pipeline uses rule-based fallback replies.
```

### Run
```bash
uvicorn main:app --host 0.0.0.0 --port 8001
```

### AI Models Loaded at Startup
| Model | Purpose | Size | cmake? |
|---|---|---|---|
| faster-whisper base | STT | ~150 MB | ❌ |
| Wav2Vec2 (HuggingFace) | Emotion | ~360 MB | ❌ |
| all-MiniLM-L6-v2 | Embeddings | ~90 MB | ❌ |
| Mistral 7B Q4 (GGUF) | LLM reply | ~4 GB | ❌ |
| Azure Cognitive Speech | TTS (API) | cloud | ❌ |

---

## 3. Node.js Backend Setup

### Prerequisites
- Node.js 18+
- MongoDB Atlas cluster (from step 1)

### Install
```bash
cd backend-nodejs
cp .env.example .env
# Edit .env — add MONGO_URI

npm install
```

### Generate VAPID keys for push notifications
```bash
npx web-push generate-vapid-keys
# Paste output into .env as VAPID_PUBLIC_KEY and VAPID_PRIVATE_KEY
```

### Run
```bash
npm run dev    # development (nodemon)
npm start      # production
```

---

## 4. Flutter App Setup

### Install dependencies
```bash
cd flutter-app
flutter pub get
```

### Configure server IPs
Edit `lib/services/app_config.dart`:
```dart
static const String nodeBaseUrl   = 'http://YOUR_SERVER_IP:4000';
static const String pythonBaseUrl = 'http://YOUR_SERVER_IP:8001';
static const String socketUrl     = 'http://YOUR_SERVER_IP:4000';
```

### Android — `android/app/src/main/AndroidManifest.xml`
```xml
<uses-permission android:name="android.permission.RECORD_AUDIO"/>
<uses-permission android:name="android.permission.INTERNET"/>
```

### iOS — `ios/Runner/Info.plist`
```xml
<key>NSMicrophoneUsageDescription</key>
<string>AlzCare needs microphone access to hear your voice</string>
```

### Run
```bash
flutter run
```

---

## 5. Quick Start (All Services)

```bash
# Terminal 1 — Node.js backend (start first, needs DB)
cd backend-nodejs && npm install && npm run dev

# Terminal 2 — Python AI pipeline
cd python-ai-pipeline && pip install -r requirements.txt
uvicorn main:app --host 0.0.0.0 --port 8001

# Terminal 3 — Flutter
cd flutter-app && flutter pub get && flutter run
```

---

## 6. Full API Reference

### Python Pipeline (port 8001)

| Method | Endpoint | Description |
|---|---|---|
| POST | `/process-multimodal` | WAV + patient_id → full AI pipeline |
| GET | `/tts-audio/{patient_id}` | Latest synthesised WAV reply |
| POST | `/generate-reminder` | Personalised reminder TTS (called by Node cron) |
| POST | `/embed-and-store` | Embed text + store via Node/MongoDB |
| POST | `/tts-speak` | Raw TTS synthesis |
| GET | `/health` | Health check |

### Node.js Backend (port 4000)

| Method | Endpoint | Description |
|---|---|---|
| GET | `/health` | Health check |
| POST | `/api/patients` | Create patient profile |
| GET | `/api/patients/:patient_id` | Get patient profile |
| POST | `/api/patients/:id/subscribe` | Save push notification subscription |
| POST | `/api/memories` | Add long-term memory |
| GET | `/api/memories?patient_id=X` | List memories |
| DELETE | `/api/memories/:id?patient_id=X` | Delete memory |
| POST | `/api/memories/search` | Atlas Vector Search (called by Python) |
| POST | `/api/notes` | Add caregiver note |
| GET | `/api/notes?patient_id=X` | List notes |
| DELETE | `/api/notes/:id?patient_id=X` | Delete note |
| POST | `/api/notes/search` | Atlas Vector Search (called by Python) |
| GET | `/api/reminders?patient_id=X` | List reminders |
| POST | `/api/reminders` | Create reminder |
| PATCH | `/api/reminders/:id?patient_id=X` | Update/pause/resume |
| DELETE | `/api/reminders/:id?patient_id=X` | Soft delete |
| POST | `/api/reminders/:id/ack?patient_id=X` | Patient acknowledges reminder |
| POST | `/api/distress` | Write distress log |
| GET | `/api/distress?patient_id=X` | Read distress history |
| POST | `/api/alerts/agitation` | Broadcast distress to Socket.io |
| WS | `/socket.io` | Always-on Socket.io hub |

---

## 7. System Flow Diagrams

### Voice Interaction Flow
```
Patient speaks
  └── Flutter records WAV
      └── POST /process-multimodal (patient_id)
          ├── faster-whisper → transcript
          ├── Wav2Vec2 → emotion label
          ├── librosa → prosodic features
          ├── MiniLM embed → vector
          ├── POST /api/memories/search (patient_id scoped)  ─┐
          ├── POST /api/notes/search    (patient_id scoped)  ─┴ Dual-source RAG
          ├── ctransformers LLM (memory + notes context)
          ├── Azure TTS SSML (emotion-adaptive)
          ├── POST /api/distress  → MongoDB
          └── if distress_flag → POST /api/alerts/agitation
              └── Socket.io emit distress_alert → caregiver room
```

### Persistent Nagger Flow
```
node-cron (every minute)
  └── Query Reminders WHERE time=HH:MM AND status=pending
      └── For each due reminder:
            ├── POST /generate-reminder (Python) → personalised TTS
            ├── Socket.io emit reminder_alert → patient room + caregiver room
            ├── DB: attempts++ , last_notified=now
            └── if attempts >= 3:
                  ├── DB: status = 'escalated'
                  └── web-push → all caregiver devices

Patient hears reminder → taps "Yes, I've done it!"
  ├── Flutter: POST /api/reminders/:id/ack
  ├── Socket.io emit ack_reminder → caregiver monitor room
  └── DB: status = 'completed'
```

### Dual-Source RAG
```
Patient: "I'm not sure where I am..."
  ├── Embed → [0.12, -0.05, ...]
  ├── Patient_Memories search (patient_id=X):
  │     "I worked as a carpenter in Ohio for 40 years"
  │     "My wife is named Dorothy"
  └── Caregiver_Notes search (patient_id=X):
        "Robert seemed confused this morning — keep reminding him he's at home"
        "His daughter is visiting at 5 PM today"
  → LLM prompt combines both → personalised, grounded reply
```

---

## 8. Emotion → TTS SSML Mapping

| Emotion | TTS Style | Rate | Pitch | Notes |
|---|---|---|---|---|
| Agitated | whispering | -25% | +5% | Slow, very gentle |
| Fear | whispering | -25% | +5% | Calming tone |
| Sad | whispering | -25% | +5% | Warm, empathetic |
| Neutral | hopeful | -15% | +5% | Clear, reassuring |
| Happy | hopeful | -15% | +5% | Warm, matching energy |

Voice: `en-US-JennyNeural` (requires Azure region supporting Neural voices: East US, West Europe)

---

## 9. Security Notes

- All MongoDB queries filter by `patient_id` — no cross-patient data leakage
- Atlas Vector Search `filter` field enforces patient_id at the DB level
- In production: replace demo `patient_id` constants with JWT-based auth
- VAPID keys must be kept secret (server-side only)
