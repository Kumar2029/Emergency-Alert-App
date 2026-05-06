from flask import Flask, render_template, request, jsonify
import os
import smtplib
import datetime
import jwt
from functools import wraps
from flask_sqlalchemy import SQLAlchemy
from flask_bcrypt import Bcrypt
from flask_cors import CORS
from email.message import EmailMessage

app = Flask(__name__)
CORS(app) 
bcrypt = Bcrypt(app)

# --- CONFIGURATION & ENV LOADING ---
app.config['SECRET_KEY'] = "emergency-secret-123"
app.config['SQLALCHEMY_DATABASE_URI'] = 'sqlite:///emergency_system.db'
app.config['SQLALCHEMY_TRACK_MODIFICATIONS'] = False

db = SQLAlchemy(app)

def get_env_config():
    """Manually parse .env to be 100% sure we get the latest values."""
    config = {}
    try:
        with open(".env", "r", encoding="utf-8") as f:
            for line in f:
                line = line.strip()
                if "=" in line and not line.startswith("#"):
                    key, val = line.split("=", 1)
                    config[key.strip()] = val.strip()
    except Exception as e:
        print(f"⚠️ Error reading .env: {e}")
    return config

# --- DATABASE MODELS ---
class User(db.Model):
    id = db.Column(db.Integer, primary_key=True)
    email = db.Column(db.String(120), unique=True, nullable=False)
    password = db.Column(db.String(60), nullable=False)
    full_name = db.Column(db.String(100))
    medical_notes = db.Column(db.Text)
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
            # Use db.session.get for SQLAlchemy 2.0 compatibility
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
    new_user = User(email=data['email'], password=hashed_password, full_name=data.get('full_name', ''))
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
        "contacts": contacts
    })

@app.route("/send_alert", methods=["POST"])
@token_required
def send_alert(current_user):
    try:
        data = request.get_json(silent=True) or {}
        location = data.get("location")
        if not location:
            return jsonify({"status": "❌ Location not provided."}), 400

        contacts = current_user.contacts
        if not contacts:
            return jsonify({"status": "❌ No emergency contacts saved."}), 400

        # FORCE RE-LOAD OF .ENV
        config = get_env_config()
        EMAIL = config.get("ALERT_EMAIL")
        PASSWORD = config.get("ALERT_APP_PASSWORD", "").replace(" ", "").strip()

        if not EMAIL or not PASSWORD:
            return jsonify({"status": "❌ Server config error."}), 500

        print(f"🛰️ Sending alert for {current_user.full_name} via {EMAIL}...")

        with smtplib.SMTP("smtp.gmail.com", 587) as server:
            server.starttls()
            server.login(EMAIL, PASSWORD)

            for contact in contacts:
                msg = EmailMessage()
                msg["From"] = EMAIL
                msg["To"] = contact.email
                msg["Subject"] = f"EMERGENCY: {current_user.full_name} NEEDS HELP"
                msg.set_content(
                    f"URGENT ALERT!\n\n"
                    f"Sender: {current_user.full_name}\n"
                    f"Medical Info: {current_user.medical_notes or 'None'}\n"
                    f"Location Link:\n{location}\n"
                )
                server.send_message(msg)

        return jsonify({"status": "✅ Alert Sent Successfully!"})

    except Exception as e:
        print(f"❌ SERVER ERROR: {e}")
        return jsonify({"status": f"❌ Error: {str(e)}"}), 500

if __name__ == "__main__":
    app.run(debug=True, host='0.0.0.0')