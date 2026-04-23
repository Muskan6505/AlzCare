# AlzCare v2 — Flutter Web
## Running the Flutter App in a Browser

---

## What Changed: Mobile → Web

| Feature | Mobile Version | Web Version |
|---|---|---|
| Audio recording | `record` package (native) | `record` package (MediaRecorder API) |
| Mic permission | `permission_handler` | Browser prompt (automatic) |
| File storage | `path_provider` + `File` | In-memory `Uint8List` / Blob URL |
| Audio playback | `just_audio` file path | `just_audio` URL stream |
| Navigation | Bottom tabs | Sidebar (desktop) + bottom bar (mobile web) |
| Socket.io | Same package | Same package (works on web) |
| Package removed | — | `permission_handler`, `path_provider` |
| Package added | — | `universal_html`, `audio_session` |

---

## Project Structure

```
flutter-app/
├── web/
│   ├── index.html          ← Custom HTML with loading overlay + PWA meta
│   └── manifest.json       ← PWA install manifest
├── lib/
│   ├── main.dart           ← Web entry point (no orientation lock)
│   ├── models/models.dart
│   ├── screens/
│   │   ├── patient_screen.dart    ← Web layout: centred card + sidebar
│   │   └── caregiver_screen.dart  ← Wide: sidebar nav | Narrow: bottom tabs
│   ├── services/
│   │   ├── app_config.dart        ← Server URLs
│   │   ├── audio_service.dart     ← Web-compatible audio (Blob URL approach)
│   │   ├── api_service.dart       ← Uses Uint8List instead of file path
│   │   └── socket_service.dart    ← Unchanged — socket_io_client works on web
│   └── widgets/
│       └── shared_widgets.dart    ← Added: SideNavItem, AlzCard, MouseRegion
└── pubspec.yaml            ← Removed: permission_handler, path_provider
```

---

## 1. Enable Flutter Web (one-time setup)

```bash
# Check Flutter version (needs >= 3.3.0)
flutter --version

# Enable web support
flutter config --enable-web

# Verify web is listed
flutter devices
# Should show: Chrome (web)
```

---

## 2. Install Dependencies

```bash
cd flutter-app
flutter pub get
```

---

## 3. Configure Server URLs

Edit `lib/services/app_config.dart`:

```dart
// Development
static const String nodeBaseUrl   = 'http://localhost:4000';
static const String pythonBaseUrl = 'http://localhost:8001';
static const String socketUrl     = 'http://localhost:4000';
```

> **CORS Note:** Both backends already have `cors({ origin: '*' })` configured.
> For production, restrict to your domain.

---

## 4. Run in Browser (Development)

```bash
# Run in Chrome (default)
flutter run -d chrome

# Run on a specific port
flutter run -d chrome --web-port 3000

# Run on Edge
flutter run -d edge

# Run with hot reload (default in web dev mode)
# Just save any file — browser auto-refreshes
```

---

## 5. Build for Production

```bash
# Build optimised web bundle
flutter build web --release

# Output is in: build/web/
# Deploy the contents of build/web/ to any static host:
#   - Nginx
#   - Apache
#   - Netlify / Vercel / Firebase Hosting
#   - AWS S3 + CloudFront
```

### Deploy with Nginx (example config)

```nginx
server {
    listen 80;
    server_name alzcare.yourdomain.com;
    root /var/www/alzcare_web;
    index index.html;

    # Flutter web needs this for client-side routing
    location / {
        try_files $uri $uri/ /index.html;
    }

    # Proxy Node.js backend (avoids CORS in production)
    location /api/ {
        proxy_pass http://localhost:4000;
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection "upgrade";
    }

    # Proxy Python pipeline
    location /ai/ {
        proxy_pass http://localhost:8001;
    }

    # Proxy Socket.io
    location /socket.io/ {
        proxy_pass http://localhost:4000;
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_read_timeout 86400;
    }
}
```

---

## 6. Browser Microphone Notes

On web, the browser controls microphone permissions — no `permission_handler` needed.

- **Chrome / Edge:** First-time mic prompt appears automatically when recording starts
- **Firefox:** Same behaviour
- **Safari:** Works on macOS 14.1+ / iOS 17+ — ensure HTTPS in production
- **HTTPS required in production:** All modern browsers block mic access on plain HTTP (except `localhost`)

---

## 7. Full Quick Start (All Services + Web)

```bash
# Terminal 1 — Node.js backend
cd backend-nodejs && npm install && npm run dev

# Terminal 2 — Python AI pipeline
cd python-ai-pipeline
pip install -r requirements.txt
uvicorn main:app --host 0.0.0.0 --port 8001

# Terminal 3 — Flutter Web
cd flutter-app
flutter pub get
flutter run -d chrome
```

Open: **http://localhost:PORT** (Flutter will print the port)

---

## 8. PWA Installation

After building for production (`flutter build web`), the app can be installed as a
Progressive Web App (PWA) on any device:

- **Desktop Chrome/Edge:** Click the install icon in the address bar
- **Android Chrome:** "Add to Home Screen" prompt appears automatically
- **iOS Safari:** Share → "Add to Home Screen"

The installed PWA runs fullscreen, looks like a native app, and remembers the last URL.

---

## 9. Responsive Behaviour

| Screen Width | Layout |
|---|---|
| ≥ 900px (desktop) | Sidebar navigation + content panel |
| 600–899px (tablet) | Compact sidebar or top bar |
| < 600px (mobile web) | Bottom tab navigation (like native app) |

The Flutter web app uses the same codebase for all screen sizes — no separate mobile/desktop builds needed.

---

## 10. Troubleshooting

### "MicrophoneNotAllowedError" in browser
- Click the 🔒 lock icon in the address bar → Site settings → Allow Microphone

### CORS errors in browser console
- Ensure both backends are running
- Check `cors({ origin: '*' })` is active in Node.js `app.js`
- Python FastAPI also has `CORSMiddleware(allow_origins=["*"])`

### Socket.io disconnects immediately
- Ensure `socketUrl` points to Node.js (port 4000), not Python
- Check browser console for WebSocket errors
- Node.js must be running before opening the web app

### Audio doesn't play after response
- Browser autoplay policy: audio plays if user interacted with the page first
- The mic button click counts as interaction — audio should always play after recording
