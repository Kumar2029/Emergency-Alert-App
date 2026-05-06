function sendHelp() {
    const status = document.getElementById("status");

    navigator.geolocation.getCurrentPosition(
        function(position) {
            let location = `https://maps.google.com/?q=${position.coords.latitude},${position.coords.longitude}`;

            fetch("/send_alert", {
                method: "POST",
                headers: {
                    "Content-Type": "application/json"
                },
                body: JSON.stringify({ location: location })
            })
            .then(res => res.json())
            .then(data => {
                status.innerHTML = data.status;
            });
        }
    );
}