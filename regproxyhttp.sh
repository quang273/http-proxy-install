#!/bin/bash
set -euo pipefail

REGIONS=("asia-northeast1" "asia-northeast2")
ZONE_SUFFIX="a"
USERNAME="soncoi"
PASSWORD="zxcv123"
PORT=8888

BOT_TOKEN="8002752987:AAGiuvuaiOAHr8UF1XCK5sFkqRH4n7bwcDQ"
USER_ID="6456880948"
PROJECT_ID=${PROJECT_ID:-$(gcloud config get-value project)}

send_to_telegram(){
  curl -s -X POST "https://api.telegram.org/bot${BOT_TOKEN}/sendMessage" \
    -d chat_id="$USER_ID" -d text="$1" > /dev/null
}

mkdir -p proxies

for region in "${REGIONS[@]}"; do
  for i in $(seq 1 4); do
    INSTANCE_NAME="proxy-$(echo $region | awk -F'-' '{print $3}')-$i"
    echo "🚀 Tạo VM $INSTANCE_NAME ở vùng $region"

    gcloud compute instances create "$INSTANCE_NAME" \
      --zone="${region}-${ZONE_SUFFIX}" \
      --machine-type=e2-micro \
      --image-family=debian-11 \
      --image-project=debian-cloud \
      --tags=http-proxy \
      --metadata=startup-script="#!/bin/bash
        apt update -y
        apt install -y tinyproxy apache2-utils
        htpasswd -cb /etc/tinyproxy/htpasswd ${USERNAME} ${PASSWORD}
        sed -i 's/^Port .*/Port ${PORT}/' /etc/tinyproxy/tinyproxy.conf
        sed -i 's/^#BasicAuth.*/BasicAuth ${USERNAME} ${PASSWORD}/' /etc/tinyproxy/tinyproxy.conf
        sed -i 's/^Allow 127.0.0.1/Allow 0.0.0.0\\/0/' /etc/tinyproxy/tinyproxy.conf
        echo \"BasicAuth ${USERNAME} ${PASSWORD}\" >> /etc/tinyproxy/tinyproxy.conf
        systemctl restart tinyproxy" \
      --boot-disk-size=10GB \
      --boot-disk-type=pd-balanced \
      --boot-disk-device-name="$INSTANCE_NAME" \
      --network-tier=STANDARD &
    sleep 1
  done
  wait
done

sleep 15
ALL_PROXY=""

for region in "${REGIONS[@]}"; do
  for i in $(seq 1 4); do
    INSTANCE_NAME="proxy-$(echo $region | awk -F'-' '{print $3}')-$i"
    IP=$(gcloud compute instances describe "$INSTANCE_NAME" \
         --zone="${region}-${ZONE_SUFFIX}" \
         --format='get(networkInterfaces[0].accessConfigs[0].natIP)')
    echo "$IP:$PORT:$USERNAME:$PASSWORD" | tee -a proxies/all_proxy.txt
    ALL_PROXY+="$IP:$PORT:$USERNAME:$PASSWORD"$'\n'
  done
done

# 🔥 Gửi duy nhất danh sách ip:port:user:pass
send_to_telegram "$ALL_PROXY"
