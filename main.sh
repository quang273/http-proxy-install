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

# Check Billing Account availability
BILLING_ACCOUNT=$(gcloud beta billing accounts list --format="value(ACCOUNT_ID)" | head -n1 || true)
if [[ -z "$BILLING_ACCOUNT" ]]; then
  echo "❌ Không tìm thấy Billing Account. Hãy tạo trước tại https://console.cloud.google.com/billing"
  send_to_telegram "❌ Không tìm thấy Billing Account. Vui lòng tạo thủ công trước khi chạy script."
  exit 1
fi

created=()
attempts=0

while (( ${#created[@]} < NUM_TARGET )); do
  ((attempts++))
  PROJECT_ID="${PROJECT_PREFIX}-$(uuidgen | tr '[:upper:]' '[:lower:]' | cut -c1-8)"
  echo "➡️ Thử tạo project ($attempts): $PROJECT_ID"

  if gcloud projects create "$PROJECT_ID" --name="$PROJECT_ID" &>/dev/null; then
    echo "🔗 Gán billing cho $PROJECT_ID"
    gcloud beta billing projects link "$PROJECT_ID" --billing-account="$BILLING_ACCOUNT"

    echo "✅ Bật các API cần thiết cho $PROJECT_ID"
    gcloud services enable compute.googleapis.com \
                           iam.googleapis.com \
                           cloudresourcemanager.googleapis.com \
                           serviceusage.googleapis.com \
                           --project="$PROJECT_ID"

    created+=("$PROJECT_ID")
    echo "✅ Tạo thành công: $PROJECT_ID"
  else
    echo "❌ Tạo thất bại: $PROJECT_ID - tiếp tục..."
  fi

  if (( attempts > NUM_TARGET*4 )); then
    send_to_telegram "⚠️ Hết quota hoặc bị lỗi - không tạo đủ $NUM_TARGET project."
    break
  fi
done

if (( ${#created[@]} == 0 )); then
  send_to_telegram "🚫 Không tạo được project nào."
  exit 1
fi

send_to_telegram "✅ Đã tạo ${#created[@]} project: ${created[*]}"

# Gọi script tạo proxy cho từng project
for prj in "${created[@]}"; do
  (
    echo "🔧 Đang xử lý project: $prj"
    gcloud config set project "$prj"
    curl -s "$REG_SCRIPT_URL" -o regproxyhttp.sh
    chmod +x regproxyhttp.sh
    PROJECT_ID="$prj" bash regproxyhttp.sh
  ) &
  sleep 2
done
wait

send_to_telegram "🎯 Hoàn tất tạo HTTP proxy cho ${#created[@]} project."
