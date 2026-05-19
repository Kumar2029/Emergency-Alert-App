import requests
import json
import io

BASE_URL = "http://127.0.0.1:5001"

def run_tests():
    print("🚀 Starting Guardian Elite Backend Tests...")
    
    # 1. Register a test user
    print("\n1. Registering test user...")
    res = requests.post(f"{BASE_URL}/register", json={
        "email": "test_extension@example.com",
        "password": "password123",
        "full_name": "Test Subject",
        "rescue_pin": "9999"
    })
    print(f"Register status: {res.status_code}")

    # 2. Login
    print("\n2. Logging in...")
    res = requests.post(f"{BASE_URL}/login", json={
        "email": "test_extension@example.com",
        "password": "password123"
    })
    if res.status_code != 200:
        print("Login failed, aborting tests.")
        return
        
    token = res.json().get("token")
    headers = {"Authorization": f"Bearer {token}"}
    print(f"Login successful. Token obtained.")

    # 3. Add an emergency contact so Twilio can trigger
    print("\n3. Setting up emergency contact...")
    res = requests.post(f"{BASE_URL}/profile", json={
        "contacts": [{"name": "Emergency Target", "email": "fake@example.com", "phone": "1234567890"}]
    }, headers=headers)
    print(f"Profile update status: {res.status_code}")

    # 4. Test Snapshot Upload
    print("\n4. Testing /upload_snapshot...")
    dummy_image = io.BytesIO(b"fake_image_data")
    files = {"image": ("test_snap.jpg", dummy_image, "image/jpeg")}
    res = requests.post(f"{BASE_URL}/upload_snapshot", headers=headers, files=files)
    print(f"Snapshot upload response ({res.status_code}): {res.json()}")

    # 5. Test Video Upload
    print("\n5. Testing /upload_video...")
    dummy_video = io.BytesIO(b"fake_video_data")
    files = {"video": ("test_vid.mp4", dummy_video, "video/mp4")}
    res = requests.post(f"{BASE_URL}/upload_video", headers=headers, files=files)
    print(f"Video upload response ({res.status_code}): {res.json()}")

    # 6. Test Trigger Call (Will likely fail due to missing/fake Twilio credentials, but shouldn't crash 500)
    print("\n6. Testing /trigger_emergency_call...")
    res = requests.post(f"{BASE_URL}/trigger_emergency_call", headers=headers)
    print(f"Emergency call response ({res.status_code}): {res.json()}")

    print("\n✅ Backend Extension Tests Completed.")

if __name__ == "__main__":
    try:
        run_tests()
    except requests.exceptions.ConnectionError:
        print("❌ Error: Flask server is not running on port 5001. Please start app.py first.")
