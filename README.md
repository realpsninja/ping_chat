# Ping Chat

A lightweight, secure, and anonymous 1‑on‑1 chat application for Android and iOS.
Built for those who prioritize privacy, simplicity, and stability.
Fully open‑source, including the backend.

---

## Features

### Security & Anonymity

* End‑to‑End Encryption (E2EE)
    – RSA for key exchange
    – AES‑CBC for message encryption
    – Keys serialized in hex format
    – FortunaRandom for secure key generation
* No personal data
    – No phone numbers, emails, or usernames required
    – Registration via PIN‑only
    – Auto‑generated anonymous nicknames

##### Auto‑Deletion

* Entire chat is automatically deleted 10 minutes after the first message
* Timer runs independently of online/offline status
* Complete removal from the server

#####  Core Functionality

* PIN‑based registration & login
* Search for other users
* Real‑time chat list
* E2EE messaging over WebSocket
* Lightweight and fast UI

---

## Project Structure

#### Frontend (Flutter)

```
lib/
├── main.dart
├── services/
│   ├── api_service.dart       # HTTP requests
│   ├── crypto_service.dart    # E2EE encryption logic
│   └── socket_service.dart    # WebSocket management
└── screens/
    ├── auth_screen.dart       # Registration / Login
    ├── chats_screen.dart      # Chat list
    ├── search_screen.dart     # User search
    └── chat_screen.dart       # Chat interface
```

#### Backend

* Runtime: Node.js
* Database: PostgreSQL
* Designed for easy deployment even on basic servers with root access.

---

### Getting Started

#### Prerequisites

* Flutter SDK (for mobile build)
* Node.js & PostgreSQL (for backend)
* Root access to server (for simple setup)

#### Backend Setup

1. Clone the repository
2. Install dependencies: npm install
3. Set up PostgreSQL database and configure connection
4. Run migrations (if any)
5. Start the server: npm start

#### Mobile Build

1. Ensure Flutter environment is ready
2. Update API/WebSocket endpoints in services/
3. Run flutter pub get
4. Build for Android/iOS: flutter build apk / flutter build ios

---

### Technical Highlights

* E2EE Implementation:
    Combines RSA key exchange with AES‑CBC for message encryption. Keys are hex‑serialized for transmission.
* Auto‑Deletion Engine:
    Server‑side timer starts at first message; after 10 minutes, chat data is permanently purged.
* Anonymous Identity:
    Users are identified only by auto‑generated nicknames and a PIN. No recoverable personal data is stored.
* Lightweight Design:
    Minimal dependencies, clean architecture, and straightforward configuration for easy hosting.

---

### License

Open‑source under MIT License.

---

### Contributing

Contributions are welcome!
Please open an issue or submit a pull request for any improvements, bug fixes, or features.

---

#### ⚠️ Disclaimer

This project is intended for privacy‑conscious users and educational purposes.
Developers are not responsible for misuse of the application.

---

##### Stay anonymous. Stay secure.🔒
