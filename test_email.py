import smtplib
import os
from email.message import EmailMessage

# Manually loading .env values to be 100% sure
def get_env():
    env = {}
    with open(".env", "r") as f:
        for line in f:
            if "=" in line:
                k, v = line.strip().split("=", 1)
                env[k] = v
    return env

config = get_env()
EMAIL = config.get("ALERT_EMAIL")
PASSWORD = config.get("ALERT_APP_PASSWORD", "").replace(" ", "").strip()

print(f"--- DIAGNOSTIC START ---")
print(f"Testing with: {EMAIL}")
print(f"Password Length: {len(PASSWORD)} characters")

msg = EmailMessage()
msg.set_content("This is a diagnostic test from your Emergency App.")
msg["Subject"] = "DIAGNOSTIC TEST"
msg["From"] = EMAIL
msg["To"] = EMAIL # Send to yourself

try:
    print("Connecting to Gmail (smtp.gmail.com:587)...")
    server = smtplib.SMTP("smtp.gmail.com", 587)
    server.set_debuglevel(1) # This shows the RAW conversation
    server.starttls()
    
    print("Attempting login...")
    server.login(EMAIL, PASSWORD)
    
    print("Sending message...")
    server.send_message(msg)
    server.quit()
    print("\n✅ SUCCESS! Google accepted your credentials.")

except Exception as e:
    print(f"\n❌ FAILED!")
    print(f"Error Details: {e}")
    print("\n--- WHAT TO DO NEXT ---")
    if "535" in str(e):
        print("1. Your password or email is still incorrect.")
        print("2. Check if 2-Step Verification is definitely ON.")
        print("3. Try generating a NEW app password and double-check the email spelling.")
