#!/usr/bin/env bash
# End-to-end email bind + password reset flow using curl

set -euo pipefail

BASE="http://localhost:8080"
EMAIL="ygshgzhy@126.com"           # replace with a real inbox
USER="testuser$(date +%s)"       # unique username per run
PWD1="initPass123"               # initial password
PWD2="resetPass456"              # new password after reset

echo "Registering user ${USER}..."
curl -s -X POST "${BASE}/api/register" \
  -H "Content-Type: application/json" \
  -d "{\"username\":\"${USER}\",\"password\":\"${PWD1}\"}" | jq .

echo "Requesting bind code (check your email inbox)..."
curl -s -X POST "${BASE}/api/email/send" \
  -H "Content-Type: application/json" \
  -d "{\"username\":\"${USER}\",\"email\":\"${EMAIL}\",\"purpose\":\"bind\"}" | jq .
printf "Enter bind code from email: "
read -r BIND_CODE

echo "Binding email..."
curl -s -X POST "${BASE}/api/email/bind" \
  -H "Content-Type: application/json" \
  -d "{\"username\":\"${USER}\",\"email\":\"${EMAIL}\",\"code\":\"${BIND_CODE}\"}" | jq .

echo "Requesting reset code (check your email inbox)..."
curl -s -X POST "${BASE}/api/email/send" \
  -H "Content-Type: application/json" \
  -d "{\"username\":\"${USER}\",\"email\":\"${EMAIL}\",\"purpose\":\"reset\"}" | jq .
printf "Enter reset code from email: "
read -r RESET_CODE

echo "Resetting password..."
curl -s -X POST "${BASE}/api/password/reset" \
  -H "Content-Type: application/json" \
  -d "{\"username\":\"${USER}\",\"code\":\"${RESET_CODE}\",\"newPassword\":\"${PWD2}\"}" | jq .

echo "Verifying new password via login..."
curl -s -X POST "${BASE}/api/login" \
  -H "Content-Type: application/json" \
  -d "{\"username\":\"${USER}\",\"password\":\"${PWD2}\"}" | jq .
