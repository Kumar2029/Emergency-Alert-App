from flask import Flask, render_template, request, jsonify, send_from_directory
import os
import smtplib
import datetime
import jwt
import time
from functools import wraps
from flask_sqlalchemy import SQLAlchemy
from flask_bcrypt import Bcrypt
from flask_cors import CORS
from email.message import EmailMessage
from twilio.rest import Client

app = Flask(__name__)
CORS(app) 
bcrypt = Bcrypt(app)

def get_env_config():
    """Manually parse .env to be 100% sure we get the latest values."""
    config = {}
    try:
        if os.path.exists(".env"):
            with open(".env", "r", encoding="utf-8") as f:
                for line in f:
                    line = line.strip()
                    if "=" in line and not line.startswith("#"):
                        key, val = line.split("=", 1)
                        config[key.strip()] = val.strip()
    except Exception as e:
        print(f"⚠️ Error reading .env: {e}")
    return config

# --- CONFIGURATION & ENV LOADING ---
env_config = get_env_config()
# Using a 32-character secure default to silence InsecureKeyLengthWarning
app.config['SECRET_KEY'] = env_config.get('SECRET_KEY', 'guardian-elite-secure-32-char-key-xyz-789')
app.config['SQLALCHEMY_DATABASE_URI'] = 'sqlite:///emergency_system.db'
app.config['SQLALCHEMY_TRACK_MODIFICATIONS'] = False

# Ensure upload folder exists
UPLOAD_FOLDER = 'uploads'
if not os.path.exists(UPLOAD_FOLDER):
    os.makedirs(UPLOAD_FOLDER)
app.config['UPLOAD_FOLDER'] = UPLOAD_FOLDER

db = SQLAlchemy(app)


# --- DATABASE MODELS ---
class User(db.Model):
    id = db.Column(db.Integer, primary_key=True)
    email = db.Column(db.String(120), unique=True, nullable=False)
    password = db.Column(db.String(60), nullable=False)
    full_name = db.Column(db.String(100))
    medical_notes = db.Column(db.Text)
    current_location = db.Column(db.String(255))
    battery_level = db.Column(db.String(10))
    sos_category = db.Column(db.String(50), default="General")
    rescue_pin = db.Column(db.String(4), default="1234")
    is_sos_active = db.Column(db.Boolean, default=False)
    audio_evidence = db.Column(db.String(255))
    contacts = db.relationship('EmergencyContact', backref='owner', lazy=True)

class EmergencyContact(db.Model):
    id = db.Column(db.Integer, primary_key=True)
    name = db.Column(db.String(100), nullable=False)
    email = db.Column(db.String(120), nullable=False)
    phone = db.Column(db.String(20))
    user_id = db.Column(db.Integer, db.ForeignKey('user.id'), nullable=False)

with app.app_context():
    db.create_all()

# --- AUTH DECORATOR ---
def token_required(f):
    @wraps(f)
    def decorated(*args, **kwargs):
        token = request.headers.get('Authorization')
        if not token:
            return jsonify({'message': 'Token is missing!'}), 401
        try:
            token = token.split(" ")[1]
            data = jwt.decode(token, app.config['SECRET_KEY'], algorithms=["HS256"])
            current_user = db.session.get(User, data['user_id'])
        except Exception as e:
            return jsonify({'message': 'Token is invalid!', 'error': str(e)}), 401
        return f(current_user, *args, **kwargs)
    return decorated

# --- ROUTES ---

@app.route("/")
def home():
    return render_template("index.html")

@app.route("/register", methods=["POST"])
def register():
    data = request.get_json()
    if User.query.filter_by(email=data['email']).first():
        return jsonify({"message": "User already exists"}), 400
    hashed_password = bcrypt.generate_password_hash(data['password']).decode('utf-8')
    new_user = User(
        email=data['email'], 
        password=hashed_password, 
        full_name=data.get('full_name', ''),
        rescue_pin=str(data.get('rescue_pin', '1234'))
    )
    db.session.add(new_user)
    db.session.commit()
    return jsonify({"message": "User created successfully"}), 201

@app.route("/login", methods=["POST"])
def login():
    data = request.get_json()
    user = User.query.filter_by(email=data['email']).first()
    if user and bcrypt.check_password_hash(user.password, data['password']):
        token = jwt.encode({
            'user_id': user.id,
            'exp': datetime.datetime.utcnow() + datetime.timedelta(hours=24)
        }, app.config['SECRET_KEY'])
        return jsonify({'token': token, 'full_name': user.full_name})
    return jsonify({"message": "Invalid credentials"}), 401

@app.route("/profile", methods=["GET", "POST"])
@token_required
def profile(current_user):
    if request.method == "POST":
        data = request.get_json()
        current_user.full_name = data.get('full_name', current_user.full_name)
        current_user.medical_notes = data.get('medical_notes', current_user.medical_notes)
        current_user.rescue_pin = data.get('rescue_pin', current_user.rescue_pin)
        if 'contacts' in data:
            EmergencyContact.query.filter_by(user_id=current_user.id).delete()
            for c in data['contacts']:
                new_contact = EmergencyContact(
                    name=c['name'], 
                    email=c['email'], 
                    phone=c.get('phone', ''),
                    user_id=current_user.id
                )
                db.session.add(new_contact)
        db.session.commit()
        return jsonify({"message": "Profile updated successfully"})
    contacts = [{"name": c.name, "email": c.email, "phone": c.phone} for c in current_user.contacts]
    return jsonify({
        "full_name": current_user.full_name, 
        "email": current_user.email, 
        "medical_notes": current_user.medical_notes, 
        "rescue_pin": current_user.rescue_pin,
        "contacts": contacts
    })

@app.route("/update_location", methods=["POST"])
@token_required
def update_location(current_user):
    data = request.get_json(silent=True) or {}
    
    # Try all possible keys from mobile app
    lat = data.get("latitude")
    lng = data.get("longitude")
    loc_str = data.get("location")
    battery = data.get("battery")

    if lat and lng:
        current_user.current_location = f"{lat},{lng}"
    elif loc_str:
        current_user.current_location = loc_str
    
    if battery:
        current_user.battery_level = str(battery)
    
    # Handle audio if sent in the same request
    audio_file = request.files.get('audio') or request.files.get('file')
    if audio_file:
        filename = f"sos_{current_user.id}_{int(time.time())}.m4a"
        audio_file.save(os.path.join(app.config['UPLOAD_FOLDER'], filename))
        current_user.audio_evidence = filename
        
    db.session.commit()
    print(f"🛰️ SIGNAL RECEIVED: User {current_user.id} ({current_user.full_name}) is at {current_user.current_location} | Audio: {current_user.audio_evidence}")
    return jsonify({"status": "Updated", "location": current_user.current_location, "audio": current_user.audio_evidence})

@app.route("/upload_evidence", methods=["POST"])
@token_required
def upload_evidence(current_user):
    audio_file = request.files.get('audio') or request.files.get('file')
    if not audio_file:
        return jsonify({"message": "No file part"}), 400
    
    filename = f"sos_{current_user.id}_{datetime.datetime.now().strftime('%Y%m%d_%H%M%S')}.m4a"
    audio_file.save(os.path.join(app.config['UPLOAD_FOLDER'], filename))
    current_user.audio_evidence = filename
    db.session.commit()
    
    config = get_env_config()
    evidence_url = f"http://{request.host}/uploads/{filename}"
    tracking_url = f"http://{request.host}/track/{current_user.id}"
    
    # Send Second Alert with Audio Link
    EMAIL = config.get("ALERT_EMAIL")
    PASSWORD = config.get("ALERT_APP_PASSWORD", "").replace(" ", "").strip()
    if EMAIL and PASSWORD:
        try:
            with smtplib.SMTP("smtp.gmail.com", 587, timeout=10) as server:
                server.starttls()
                server.login(EMAIL, PASSWORD)
                for contact in current_user.contacts:
                    if contact.email:
                        msg = EmailMessage()
                        msg["From"] = EMAIL
                        msg["To"] = contact.email
                        msg["Subject"] = f"🎙️ AUDIO EVIDENCE: {current_user.full_name}"
                        msg.set_content(f"Audio captured. Listen here: {evidence_url}\nLive Tracking: {tracking_url}")
                        server.send_message(msg)
        except: pass

    TWILIO_SID = config.get("TWILIO_ACCOUNT_SID")
    TWILIO_AUTH = config.get("TWILIO_AUTH_TOKEN")
    TWILIO_FROM = config.get("TWILIO_WHATSAPP_NUMBER")
    if TWILIO_SID and TWILIO_AUTH and TWILIO_FROM:
        try:
            client = Client(TWILIO_SID, TWILIO_AUTH)
            for contact in current_user.contacts:
                if contact.phone:
                    clean_phone = str(contact.phone).strip()
                    if not clean_phone.startswith('+'): clean_phone = f"+91{clean_phone}" if len(clean_phone) == 10 else f"+{clean_phone}"
                    client.messages.create(
                        body=f"🎙️ *Audio Evidence Ready*\n\n{evidence_url}\n\n🛰️ *Updated Tracking*:\n{tracking_url}",
                        from_=TWILIO_FROM,
                        to=f"whatsapp:{clean_phone}"
                    )
        except: pass

    return jsonify({"message": "Uploaded", "url": evidence_url})

@app.route("/track/<int:user_id>")
def live_track(user_id):
    return render_template("track.html", user_id=user_id)

@app.route("/get_location/<int:user_id>")
def get_location(user_id):
    user = User.query.get(user_id)
    if user:
        # Get latest audio file for this user (sorted by actual creation time)
        print(f"📡 DASHBOARD REQUEST: Serving User {user_id} data. Location: {user.current_location}")
        return jsonify({
            "status": "success",
            "full_name": user.full_name,
            "is_active": user.is_sos_active,
            "location": user.current_location,
            "battery": user.battery_level,
            "category": user.sos_category,
            "latest_audio": f"/uploads/{user.audio_evidence}" if getattr(user, 'audio_evidence', None) else None
        })
    return jsonify({"status": "error"}), 404

@app.route('/uploads/<path:filename>')
def serve_upload(filename):
    return send_from_directory(app.config['UPLOAD_FOLDER'], filename)

@app.route("/send_alert", methods=["POST"])
@token_required
def send_alert(current_user):
    # Immediate Activation for Dashboard
    current_user.is_sos_active = True
    db.session.commit()
    # ... existing alert logic ...
    try:
        data = request.get_json(silent=True) or {}
        location = data.get("location")
        category = data.get("category", "General")
        
        if not location:
            return jsonify({"status": "❌ Location missing"}), 400

        current_user.sos_category = category
        db.session.commit()

        config = get_env_config()
        tracking_url = f"http://{request.host}/track/{current_user.id}"
        
        # 1. EMAIL
        EMAIL = config.get("ALERT_EMAIL")
        PASSWORD = config.get("ALERT_APP_PASSWORD", "").replace(" ", "").strip()
        if EMAIL and PASSWORD:
            try:
                with smtplib.SMTP("smtp.gmail.com", 587, timeout=10) as server:
                    server.starttls()
                    server.login(EMAIL, PASSWORD)
                    for contact in current_user.contacts:
                        if contact.email:
                            # Log transmission attempt
                            msg = EmailMessage()
                            msg["From"] = EMAIL
                            msg["To"] = contact.email
                            msg["Subject"] = f"🚨 {category.upper()} SOS: {current_user.full_name}"
                            
                            html_content = f"""
                            <div style="background-color: #050505; color: #ffffff; padding: 40px; font-family: 'Helvetica', sans-serif; border-radius: 10px;">
                                <h1 style="color: #ff3e3e; margin-bottom: 20px;">🚨 {category.upper()} EMERGENCY</h1>
                                <p style="font-size: 18px;"><b>{current_user.full_name}</b> has triggered a <b>{category}</b> SOS signal.</p>
                                <div style="background: #1a1a1a; padding: 20px; border-left: 4px solid #ff3e3e; margin: 20px 0;">
                                    <p><b>Location:</b> {location}</p>
                                </div>
                                <a href="{tracking_url}" style="background-color: #ff3e3e; color: white; padding: 15px 25px; text-decoration: none; border-radius: 5px; font-weight: bold; display: inline-block; margin-top: 20px;">
                                    VIEW LIVE COMMAND CENTER
                                </a>
                                <p style="color: #888; font-size: 12px; margin-top: 30px;">
                                    This is an automated emergency alert from the Guardian Elite Safety System.
                                </p>
                            </div>
                            """
                            msg.add_alternative(html_content, subtype="html")
                            server.send_message(msg)
                            # Email success
            except Exception as e: 
                # Email error handled silently
                pass

        # 2. WHATSAPP
        TWILIO_SID = config.get("TWILIO_ACCOUNT_SID")
        TWILIO_AUTH = config.get("TWILIO_AUTH_TOKEN")
        TWILIO_FROM = config.get("TWILIO_WHATSAPP_NUMBER")
        if TWILIO_SID and TWILIO_AUTH and TWILIO_FROM:
            try:
                client = Client(TWILIO_SID, TWILIO_AUTH)
                for contact in current_user.contacts:
                    if contact.phone:
                        # Professional Sanitization
                        clean_phone = "".join(filter(str.isdigit, str(contact.phone)))
                        if not clean_phone.startswith('+'):
                            clean_phone = f"+91{clean_phone}" if len(clean_phone) == 10 else f"+{clean_phone}"
                        if not clean_phone.startswith('+'): clean_phone = f"+{clean_phone}"
                        # Log WhatsApp attempt
                        client.messages.create(
                            body=f"🔴 *{category.upper()} EMERGENCY: {current_user.full_name.upper()}*\n\n📍 *Current Location*:\n{location}\n\n🛰️ *Live Tracking Dashboard*:\n{tracking_url}",
                            from_=TWILIO_FROM,
                            to=f"whatsapp:{clean_phone}"
                        )
                        # WhatsApp success
            except Exception as twilio_e: 
                # WhatsApp error handled silently
                pass

        return jsonify({"status": "✅ Alerts Dispatched"})
    except Exception as e:
        return jsonify({"status": f"❌ Error: {str(e)}"}), 500

@app.route("/activate_sos", methods=["POST"])
@token_required
def activate_sos(current_user):
    current_user.is_sos_active = True
    db.session.commit()
    return jsonify({"message": "SOS activated"})

@app.route("/deactivate_sos", methods=["POST"])
@token_required
def deactivate_sos(current_user):
    current_user.is_sos_active = False
    db.session.commit()
    return jsonify({"message": "SOS deactivated"})

@app.route('/uploads/<path:filename>')
def download_file(filename):
    return send_from_directory(app.config['UPLOAD_FOLDER'], filename)

if __name__ == '__main__':
    with app.app_context():
        db.create_all()
        # Zero-Failure Migration: Check for all security columns
        from sqlalchemy import inspect, text
        inspector = inspect(db.engine)
        columns = [c['name'] for c in inspector.get_columns('user')]
        
        with db.engine.connect() as conn:
            if 'sos_category' not in columns:
                conn.execute(text('ALTER TABLE user ADD COLUMN sos_category VARCHAR(50) DEFAULT "General"'))
            if 'rescue_pin' not in columns:
                conn.execute(text('ALTER TABLE user ADD COLUMN rescue_pin VARCHAR(4) DEFAULT "1234"'))
            if 'is_sos_active' not in columns:
                conn.execute(text('ALTER TABLE user ADD COLUMN is_sos_active BOOLEAN DEFAULT 0'))
            if 'audio_evidence' not in columns:
                conn.execute(text('ALTER TABLE user ADD COLUMN audio_evidence VARCHAR(255)'))
            conn.commit()
    app.run(host='0.0.0.0', port=5001, debug=True)