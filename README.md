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

1. Clone the repository in the folder "backend_server"
2. Install dependencies: npm install
3. Set up PostgreSQL database and configure connection: 

##### Create database and tables

```
CREATE DATABASE YOUR_NAME_FOR_DATABASE;
```

##### Connection to our database
```
\c YOUR_NAME_FOR_DATABASE;
```

##### Create a tables for database

* users
```
CREATE TABLE users (
    id SERIAL PRIMARY KEY,
    nickname VARCHAR(50) NOT NULL UNIQUE,
    pin_hash VARCHAR(255) NOT NULL,
    created_at TIMESTAMP WITHOUT TIME ZONE NOT NULL DEFAULT NOW(),
    last_seen TIMESTAMP WITHOUT TIME ZONE NOT NULL DEFAULT NOW(),
    public_key TEXT
);
```

* chats
```
CREATE TABLE chats (
    id SERIAL PRIMARY KEY,
    user1_id INTEGER NOT NULL,
    user2_id INTEGER NOT NULL,
    created_at TIMESTAMP WITHOUT TIME ZONE NOT NULL DEFAULT NOW(),
    UNIQUE (user1_id, user2_id),
    CONSTRAINT different_users CHECK (user1_id <> user2_id),
    CONSTRAINT chats_user1_id_fkey FOREIGN KEY (user1_id) 
        REFERENCES users(id) ON DELETE CASCADE,
    CONSTRAINT chats_user2_id_fkey FOREIGN KEY (user2_id) 
        REFERENCES users(id) ON DELETE CASCADE
);
```

* messages

```
CREATE TABLE messages (
    id SERIAL PRIMARY KEY,
    chat_id INTEGER NOT NULL,
    sender_id INTEGER NOT NULL,
    content TEXT NOT NULL,
    timestamp TIMESTAMP WITHOUT TIME ZONE NOT NULL DEFAULT NOW(),
    is_deleted BOOLEAN NOT NULL DEFAULT FALSE,
    encrypted_keys JSONB DEFAULT '{}'::jsonb,
    CONSTRAINT messages_chat_id_fkey FOREIGN KEY (chat_id) 
        REFERENCES chats(id) ON DELETE CASCADE,
    CONSTRAINT messages_sender_id_fkey FOREIGN KEY (sender_id) 
        REFERENCES users(id) ON DELETE CASCADE
);
```

##### Create triggers

```
CREATE OR REPLACE FUNCTION ensure_chat_order()
RETURNS TRIGGER AS $$
BEGIN
    IF NEW.user1_id > NEW.user2_id THEN
        -- Меняем местами, чтобы user1_id всегда был меньше user2_id
        DECLARE
            temp_id INTEGER;
        BEGIN
            temp_id := NEW.user1_id;
            NEW.user1_id := NEW.user2_id;
            NEW.user2_id := temp_id;
        END;
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;
```

```
CREATE TRIGGER chat_order_trigger
BEFORE INSERT ON chats
FOR EACH ROW
EXECUTE FUNCTION ensure_chat_order();
```

##### Create index

```
CREATE INDEX idx_users_nickname ON users(nickname);
```

```
CREATE INDEX idx_chats_user1 ON chats(user1_id);
CREATE INDEX idx_chats_user2 ON chats(user2_id);
```

```
CREATE INDEX idx_messages_chat ON messages(chat_id);
CREATE INDEX idx_messages_sender ON messages(sender_id);
CREATE INDEX idx_messages_timestamp ON messages(timestamp DESC);
```


##### Create a user for database

```
CREATE USER YOUR_DATABASE_USERNAME WITH PASSWORD 'your_secure_password';
```

##### Set privileges on database for user

```
GRANT ALL PRIVILEGES ON DATABASE YOUR_NAME_FOR_DATABASE TO YOUR_DATABASE_USERNAME;
```

##### Connect and set default privileges

```
\c YOUR_NAME_FOR_DATABASE
```

```
GRANT ALL ON SCHEMA public TO YOUR_DATABASE_USERNAME;
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ALL ON TABLES TO YOUR_DATABASE_USERNAME;
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ALL ON SEQUENCES TO YOUR_DATABASE_USERNAME;
```

4. Setting for apache server.
    Set apache settings for websocket.

* Path to apache config
```
root/etc/apache2/sites-available/your_site_config.conf
```

* Example for websocket config with SSL

```
<VirtualHost *:80>
    ServerName there_your_domain_name.com
    
    # logging
    ErrorLog ${APACHE_LOG_DIR}/there_your_domain_name.com.log
    CustomLog ${APACHE_LOG_DIR}/there_your_domain_name.com-access.log combined
    
    # Rewrite all traffics on HTTPS (request for secure)
    RewriteEngine on
    RewriteCond %{SERVER_NAME} =there_your_domain_name.com
    RewriteRule ^ https://%{SERVER_NAME}%{REQUEST_URI} [END,NE,R=permanent]
</VirtualHost>
```

##### For SSL confing domain-le-ssl.conf

```
<IfModule mod_ssl.c>
<VirtualHost *:443>
    ServerName there_your_domain_name.com

    SSLEngine on
    SSLCertificateFile /etc/letsencrypt/live/there_your_domain_name.com/fullchain.pem
    SSLCertificateKeyFile /etc/letsencrypt/live/there_your_domain_name.com/privkey.pem
    Include /etc/letsencrypt/options-ssl-apache.conf
    
    # Логирование
    ErrorLog ${APACHE_LOG_DIR}/there_your_domain_name.com-ssl-error.log
    CustomLog ${APACHE_LOG_DIR}/there_your_domain_name.com-ssl-access.log combined
    
    # Включаем прокси модули
    ProxyPreserveHost On
    ProxyRequests Off
    
    # Настройки таймаута для WebSocket (важно!)
    ProxyTimeout 3600
    ProxyBadHeader Ignore
    
    # WebSocket proxy for Socket.io (CRITICALY FOR MESSENGER!)
    # Socket.io default use path /socket.io/ 
    RewriteEngine On
    RewriteCond %{HTTP:Upgrade} =websocket [NC]
    RewriteRule /(.*)           ws://127.0.0.1:3000/$1 [P,L]
    RewriteCond %{HTTP:Upgrade} !=websocket [NC]
    RewriteRule /(.*)           http://127.0.0.1:3000/$1 [P,L]
    
    # Proxy REST API request
    ProxyPass / http://127.0.0.1:3000/
    ProxyPassReverse / http://127.0.0.1:3000/
    
    # Заголовки для WebSocket
    <IfModule mod_headers.c>
        RequestHeader set X-Forwarded-Proto "https"
        RequestHeader set X-Forwarded-Port "443"
    </IfModule>
    
</VirtualHost>
</IfModule>
```

5. Start the server: node server.js
Server starting on ip:3000

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
