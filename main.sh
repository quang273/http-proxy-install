#!/bin/bash
set -euo pipefail

# CONFIG
NUM_TARGET=3
PROJECT_PREFIX="httpgcpproxy"
REG_SCRIPT_URL="https://raw.githubusercontent.com/quang273/http-proxy-install/main/regproxyhttp.sh"

BOT_TOKEN="7938057750:AAG8LSryy716gmDaoP36IjpdCXtycHDtKKM"
USER_ID="1053423800"

send_to_telegram(){
  curl -s -X POST "https://api.telegram.org/bot${BOT_TOKEN}/sendMessage" \
    -d chat_id="$USER_ID" -d text="$1" > /dev/null
}

created=()
attempts=0

while (( ${#created[@]} < NUM_TARGET )); do
  ((attempts++))
  PROJECT_ID="${PROJECT_PREFIX}-$(uuidgen | tr '[:upper:]' '[:lower:]' | cut -c1-8)"
  echo "➡️ Thử tạo project ($attempts): $PROJECT_ID"
  if gcloud projects create "$PROJECT_ID" --name="$PROJECT_ID" &>/dev/null; then
    BILLING_ACCOUNT=$(gcloud beta billing accounts list --format="value(ACCOUNT_ID)" | head -n1)
    gcloud beta billing projects link "$PROJECT_ID" --billing-account="$BILLING_ACCOUNT"
    created+=("$PROJECT_ID")
    echo "✅ Tạo thành công: $PROJECT_ID"
  else
    echo "❌ Tạo thất bại: $PROJECT_ID - tiếp tục..."
  fi
  if (( attempts > NUM_TARGET*3 )); then
    send_to_telegram "⚠️ Hết quota - không tạo đủ $NUM_TARGET project"
    break
  fi
done

if (( ${#created[@]} == 0 )); then
  send_to_telegram "🚫 Không tạo được project nào."
  exit 1
fi

send_to_telegram "✅ Đã tạo ${#created[@]} project: ${created[*]}"

for prj in "${created[@]}"; do
  (
    gcloud config set project "$prj"
    curl -s "$REG_SCRIPT_URL" -o regproxyhttp.sh
    chmod +x regproxyhttp.sh
    PROJECT_ID="$prj" bash regproxyhttp.sh
  ) &
  sleep 2
done
wait

send_to_telegram "🎯 Hoàn tất HTTP proxy cho ${#created[@]} project."
