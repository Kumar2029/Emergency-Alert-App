# 🛡️ Guardian Elite: Advanced Emergency Response System

**Guardian Elite** is a production-hardened, real-time emergency orchestration platform designed to provide maximum situational awareness during a crisis. It combines native mobile telemetry (GPS, Audio Evidence, Battery Status) with a high-fidelity Tactical Command Center for emergency responders.

---

## ⚡ Quick-Copy Command Reference

### 1. Setup Backend (Run once)
```cmd
pip install flask flask-sqlalchemy flask-cors flask-bcrypt pyjwt
```

### 2. Launch the System (The 3-Terminal Flow)
**Terminal 1 (Backend Engine):**
```cmd
python app.py
```

**Terminal 2 (Global Tunnel):**
```cmd
ngrok http 5000
```

**Terminal 3 (Mobile App):**
```cmd
cd emergency_mobile && flutter pub get && flutter run
```

---

## 🛰️ Project Overview
*   **Mobile App (Flutter)**: One-tap SOS trigger with native siren/strobe, real-time GPS streaming, and forensic audio recording.
*   **Backend (Flask/Python)**: Secure JWT-authenticated API with self-healing SQLite database and automated SOS deactivation protocols.
*   **Command Center (Web)**: Real-time Leaflet.js dashboard with "Stealth Mode," movement history, and nearby emergency service scanning (Hospitals/Police).

---

## 🛠️ Prerequisites
Before starting, ensure you have the following installed on your system:

### 1. Python (Backend)
*   Download and install **Python 3.10+** from [python.org](https://www.python.org/).
*   **IMPORTANT**: Check the box that says **"Add Python to PATH"** during installation.

### 2. Flutter & Android Studio (The Mobile Stack)
This project requires the Flutter SDK and a configured Android development environment.

#### **A. Install the Flutter SDK**
1.  **Download**: Get the latest stable Flutter SDK from [flutter.dev](https://docs.flutter.dev/get-started/install/windows).
2.  **Extract**: Extract the zip file to a permanent folder (e.g., `C:\src\flutter`). **DO NOT** install it in `C:\Program Files`.
3.  **PATH Configuration (CRITICAL)**:
    *   Search for "Environment Variables" in Windows Search.
    *   Under "User variables," find **Path** and click **Edit**.
    *   Click **New** and paste the path to your flutter bin folder (e.g., `C:\src\flutter\bin`).
4.  **Verify CLI**: Open a **new** terminal and type `flutter --version`. If it shows a version number, the CLI is ready!

#### **B. Setup Android Studio**
1.  **Install**: Download [Android Studio](https://developer.android.com/studio).
2.  **Plugins**: Open Android Studio -> **Settings** -> **Plugins**. Search for and install the **Flutter** and **Dart** plugins.
3.  **SDK Tools**:
    *   Go to **Settings** -> **Languages & Frameworks** -> **Android SDK** -> **SDK Tools**.
    *   Check **Android SDK Command-line Tools (latest)** and click **Apply**.
4.  **Licenses**: Open your terminal and run:
    ```cmd
    flutter doctor --android-licenses
    ```
    (Press `y` for every prompt to accept the terms).

#### **D. Useful Flutter Setup Commands**
| Action | Command |
| :--- | :--- |
| **Check Path** | `where flutter` |
| **Health Check** | `flutter doctor` |
| **Licenses** | `flutter doctor --android-licenses` |
| **Reset Cache** | `flutter clean && flutter pub get` |
| **Run App** | `flutter run` |

---

### 3. Ngrok (Global Tunneling)
*   Sign up for a free account at [ngrok.com](https://ngrok.com/).
*   Download the Ngrok CLI and authenticate it using your authtoken.

---

## 🚀 Installation & Setup

### 1. Clone & Prepare Backend
Open your terminal (CMD or PowerShell) and navigate to the project folder:
```cmd
cd "Emergency Alert\Emergency Alert"
```

**Install Python Dependencies:**
```cmd
pip install flask flask-sqlalchemy flask-cors flask-bcrypt pyjwt
```

### 2. Prepare Mobile App
Navigate to the mobile directory:
```cmd
cd emergency_mobile
```

**Fetch Flutter Packages:**
```cmd
flutter pub get
```

---

## 🛰️ Running the System (The 3-Step Sequence)

For the system to work globally, you MUST follow this exact sequence:

### Step 1: Start the Python Engine
In your terminal:
```cmd
python app.py
```
*Your server is now running locally on port 5000.*

### Step 2: Open the Global Tunnel (Ngrok)
In a **new** terminal window:
```cmd
ngrok http 5000
```
*Copy the `Forwarding` URL (e.g., `https://abcd-123.ngrok-free.dev`).*

### Step 3: Sync the App
1.  Open `lib/api_service.dart` in the Flutter project.
2.  Update the `baseUrl` with your **new Ngrok URL**:
    ```dart
    static const String baseUrl = "https://your-new-url.ngrok-free.dev";
    ```
3.  **Launch the App**:
    ```cmd
    flutter run
    ```

---

## 🔐 Security & Features
*   **Rescue PIN**: A mandatory 4-digit code (Default: `1234`) required to stop tracking. Change this in your **Safety Profile**.
*   **Stealth Mode**: Tap **HIDE UI** on the dashboard to see a full-screen map without clutter.
*   **Nearby Services**: The dashboard automatically scans a 5km radius for hospitals and police stations using the Overpass API.

---

## ❓ Troubleshooting
*   **Error: `no such column`**: Delete the `instance/emergency_system.db` file and restart `app.py`.
*   **App won't connect**: Ensure the Ngrok URL in `api_service.dart` matches your active tunnel.
*   **Map not moving**: Ensure you are not touching a UI card; the center of the screen is "Touch-Through" to the map.

---

**Built with 🦾 for Kumar Vasanth by Antigravity.** 
*Guardian Elite: Because every second counts.*
