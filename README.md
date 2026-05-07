# 🚨 Emergency Alert System (SOS Command Center)

A robust, multi-channel emergency response system designed for high-stakes safety scenarios. The system integrates mobile hardware triggers with cloud-based notifications and real-time forensic tracking.

## ✨ Key Features
- **Physical Deterrents**: High-decibel Police Siren and Camera Strobe to scare off attackers.
- **Native SOS Engine**: Direct SIM-based SMS broadcasting (bypassing Android restrictions).
- **Multi-Channel Alerts**: Simultaneous notification via **WhatsApp API**, **Email (SMTP)**, and **SMS**.
- **Live Command Center**: Real-time map tracking with a high-tech "Radar" dashboard for emergency contacts.
- **Forensic Evidence**: 15-second silent audio recording, automatically uploaded and shared via a secure link.

---

## 🛠️ Tech Stack
- **Frontend**: Flutter (Android/iOS)
- **Backend**: Python Flask (REST API)
- **Database**: SQLite (SQLAlchemy ORM)
- **Integrations**: Twilio API (WhatsApp), Gmail SMTP (Email), Leaflet.js (Mapping)

---

## 🚀 Setup Instructions

### 1. Backend Setup (Python)
1. Navigate to the root directory.
2. Install dependencies:
   ```bash
   pip install flask flask-sqlalchemy flask-bcrypt flask-cors PyJWT twilio flask-mail
   ```
3. Create a `.env` file in the root directory:
   ```env
   ALERT_EMAIL=your-email@gmail.com
   ALERT_APP_PASSWORD=your-google-app-password
   TWILIO_ACCOUNT_SID=your-twilio-sid
   TWILIO_AUTH_TOKEN=your-twilio-token
   TWILIO_WHATSAPP_NUMBER=whatsapp:+14155238886
   ```
4. Start the server:
   ```bash
   python app.py
   ```

### 2. Frontend Setup (Flutter)
1. Navigate to the `emergency_mobile` directory.
2. **CRITICAL STEP**: Open `lib/api_service.dart` and update the `baseUrl` variable:
   ```dart
   static const String baseUrl = 'http://127.0.0.1:5000'; // Replace with your laptop's IP
   ```
3. Install Flutter packages:
   ```bash
   flutter pub get
   ```
4. Build the APK:
   ```bash
   flutter build apk --debug
   ```

---

## 📍 How to Use
1. **Join Twilio Sandbox**: The emergency contact must text `join your-code` to your Twilio number to receive WhatsApp alerts.
2. **Profile Setup**: Open the app, go to **Profile**, and add your emergency contacts (Name, Email, Phone). **Click Save.**
3. **Trigger SOS**: Hold the central **SOS button** for 3 seconds.
4. **Tracking**: The contacts will receive a link to the **Live Command Center** where they can watch your movement and listen to the recorded audio.

---

## ⚠️ Important Note (Android Permissions)
Since this is a side-loaded app, Android may block SMS permissions. 
- Go to **App Info > Restricted Settings**.
- Click the three dots (top right) and select **"Allow restricted settings."**
- Enable **SMS**, **Microphone**, and **Location** permissions.

---

## ⚖️ License
This project is for educational and emergency demonstration purposes.
