#!/bin/bash

##### BASE : LUNATIC TUNNELING x GPT #####
reset_ui() {    
    tput cup 0 0 && printf "\033c"    
    printf "\033[H"
    sleep 0.05
    tput clear    
}

set -e
reset_ui

NC='\e[0m'
WHITE='\033[1;97m'
CYAN='\033[38;5;51m'
CYAN_SOFT='\033[38;5;117m'
GREEN='\033[38;5;82m'
RED='\033[38;5;196m'
YELLOW='\033[38;5;226m'
DIM='\033[2m'

run_step() {
    local text="$1"
    local spin='|/-\'
    local i=0

    tput civis
    for ((j=0; j<14; j++)); do
        i=$(( (i+1) %4 ))
        printf "\r ${CYAN}%c${NC} ${WHITE}%-50s${DIM}...${NC}" \
        "${spin:$i:1}" "$text"
        sleep 0.12
    done

    printf "\r ${GREEN}✔${NC} ${WHITE}%-50s${NC}\n" "$text"
    tput cnorm
}

echo -e "${CYAN_SOFT}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${WHITE}     TELEGRAM BOT + VPS API INSTALLER${NC}"
echo -e "${CYAN_SOFT}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""

run_step "Updating package repository"
apt update -y &> /dev/null

run_step "Installing required dependencies"
apt install -y unzip wget curl sqlite3 openssl &> /dev/null

run_step "Removing previous Node.js installation"
apt purge -y nodejs npm &> /dev/null || true
rm -rf /usr/lib/node_modules ~/.npm /usr/bin/node /usr/bin/npm &> /dev/null || true

run_step "Installing Node.js v20"
curl -fsSL https://deb.nodesource.com/setup_20.x | bash - &> /dev/null
apt install -y nodejs &> /dev/null

run_step "Downloading bot package"
wget -q -O bot.zip https://raw.githubusercontent.com/yansyntax/TBOT/main/VPNBOT/bot.zip

if [[ ! -f "bot.zip" ]]; then
    echo -e "${RED}✖ Failed to download bot package${NC}"
    exit 1
fi

run_step "Extracting bot files"
rm -rf /tmp/bot_EXTRACT
mkdir -p /tmp/bot_EXTRACT
unzip -o bot.zip -d /tmp/bot_EXTRACT &> /dev/null

BOT_FOLDER=$(find /tmp/bot_EXTRACT -maxdepth 1 -type d ! -name "*EXTRACT" | head -n 1)
[[ -z "$BOT_FOLDER" ]] && { echo -e "${RED}✖ Bot folder not found${NC}"; exit 1; }

run_step "Deploying bot to system"
rm -rf /root/bot
mv "$BOT_FOLDER" /root/bot
chmod +x /root/bot/shell_script/* 2>/dev/null || true

reset_ui
echo -e "${CYAN_SOFT}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${WHITE}             BOT CONFIGURATION${NC}"
echo -e "${CYAN_SOFT}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""

read -rp " Bot Token      : " BOT_TOKEN
read -rp " Owner ID       : " OWNER_ID
read -rp " Pakasir Slug   : " PAKASIR_SLUG
read -rp " Pakasir API Key: " PAKASIR_API_KEY
read -rp " Bot Name       : " BOT_NAME

echo ""
echo -e "${CYAN_SOFT}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${WHITE}             VPS API CONFIGURATION${NC}"
echo -e "${CYAN_SOFT}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""

API_TOKEN=$(openssl rand -hex 24)
API_PORT=3456
SERVER_IP=$(curl -s ifconfig.me 2>/dev/null || hostname -I | awk '{print $1}')

echo -e " ${DIM}API Token dibuat otomatis${NC}"
echo -e " ${DIM}API Port : ${API_PORT}${NC}"
echo -e " ${DIM}Server IP: ${SERVER_IP}${NC}"
echo ""

read -rp " Nama server (contoh: SG/ID/JP) : " SERVER_NAME
SERVER_NAME=${SERVER_NAME:-SG}

read -rp " Limit akun server [90] : " SERVER_LIMIT
SERVER_LIMIT=${SERVER_LIMIT:-90}

mkdir -p /root/bot/data

run_step "Saving bot configuration"
cat > /root/bot/data/.avars.json << EOF
{
  "token": "$BOT_TOKEN",
  "owner_id": "$OWNER_ID",
  "pakasir_slug": "$PAKASIR_SLUG",
  "pakasir_api_key": "$PAKASIR_API_KEY",
  "bot_name": "$BOT_NAME"
}
EOF

run_step "Configuring server with API mode"
cat > /root/bot/data/server.js << EOF
const servers = [
  {
    "name": "${SERVER_NAME}",
    "ip": "${SERVER_IP}",
    "username": "root",
    "pass": "",
    "apiUrl": "http://${SERVER_IP}:${API_PORT}",
    "apiToken": "${API_TOKEN}",
    "limit": ${SERVER_LIMIT},
    "used": 0
  }
];

module.exports = servers;
EOF

cd /root/bot

run_step "Installing bot modules"
npm install &> /dev/null
npm install node-telegram-bot-api axios node-cron sqlite3 qrcode canvas &> /dev/null
npm rebuild &> /dev/null

run_step "Setting up VPS API Server"
mkdir -p /root/vps-api/shell_script

cat > /root/vps-api/package.json << 'PKGEOF'
{
  "name": "vps-bot-api",
  "version": "1.0.0",
  "scripts": { "start": "node server.js" },
  "dependencies": { "express": "^4.21.0" }
}
PKGEOF

cat > /root/vps-api/server.js << 'SRVEOF'
const express = require('express');
const { execFile } = require('child_process');
const fs = require('fs');
const path = require('path');

const app = express();
app.use(express.json({ limit: '5mb' }));

const PORT = process.env.API_PORT || 3456;
const TOKEN = process.env.API_TOKEN || '';

if (!TOKEN) {
  console.error('[API] API_TOKEN belum diset!');
  process.exit(1);
}

const SCRIPT_DIR = path.join(__dirname, 'shell_script');

function authMiddleware(req, res, next) {
  const token = req.headers['x-api-token'] || req.body.token;
  if (!token || token !== TOKEN) {
    return res.status(401).json({ error: 'Unauthorized', message: 'Token tidak valid' });
  }
  next();
}

app.use('/api', authMiddleware);

app.get('/api/ping', (req, res) => {
  res.json({ status: 'ok', timestamp: new Date().toISOString() });
});

app.post('/api/exec', (req, res) => {
  const { script, args } = req.body;
  if (!script) return res.status(400).json({ error: 'BAD_REQUEST', message: 'Parameter "script" wajib diisi' });
  if (!/^[a-zA-Z0-9_]+$/.test(script)) return res.status(400).json({ error: 'BAD_REQUEST', message: 'Nama script tidak valid' });

  const scriptPath = path.join(SCRIPT_DIR, script);
  if (!fs.existsSync(scriptPath)) return res.status(404).json({ error: 'SCRIPT_NOT_FOUND', message: `Script "${script}" tidak ditemukan` });

  const safeArgs = (args || []).map(a => String(a));
  execFile('bash', [scriptPath, ...safeArgs], { timeout: 30000 }, (err, stdout, stderr) => {
    if (err) {
      if (err.killed) return res.status(504).json({ error: 'TIMEOUT', message: 'Script timeout (30 detik)', output: stdout || '' });
      return res.json({ success: false, exitCode: err.code, output: ((stdout || '') + (stderr || '')).trim() });
    }
    res.json({ success: true, exitCode: 0, output: ((stdout || '') + (stderr || '')).trim() });
  });
});

app.post('/api/sync', (req, res) => {
  const { scripts } = req.body;
  if (!scripts || !Array.isArray(scripts) || scripts.length === 0) {
    return res.status(400).json({ error: 'BAD_REQUEST', message: 'Parameter "scripts" wajib diisi' });
  }
  if (!fs.existsSync(SCRIPT_DIR)) fs.mkdirSync(SCRIPT_DIR, { recursive: true });

  const results = [];
  for (const item of scripts) {
    if (!item.name || !item.content) { results.push({ name: item.name || '?', status: 'skipped', reason: 'nama atau isi kosong' }); continue; }
    if (!/^[a-zA-Z0-9_]+$/.test(item.name)) { results.push({ name: item.name, status: 'skipped', reason: 'nama tidak valid' }); continue; }
    try {
      const filePath = path.join(SCRIPT_DIR, item.name);
      fs.writeFileSync(filePath, item.content, 'utf8');
      fs.chmodSync(filePath, '755');
      results.push({ name: item.name, status: 'ok' });
    } catch (e) { results.push({ name: item.name, status: 'error', reason: e.message }); }
  }
  const ok = results.filter(r => r.status === 'ok').length;
  const failed = results.filter(r => r.status !== 'ok').length;
  res.json({ success: true, synced: ok, failed, details: results });
});

app.get('/api/scripts', (req, res) => {
  if (!fs.existsSync(SCRIPT_DIR)) return res.json({ scripts: [] });
  const files = fs.readdirSync(SCRIPT_DIR).filter(f => fs.statSync(path.join(SCRIPT_DIR, f)).isFile());
  res.json({ scripts: files });
});

app.listen(PORT, '0.0.0.0', () => {
  console.log(`[API] VPS Bot API running on port ${PORT}`);
  console.log(`[API] Script directory: ${SCRIPT_DIR}`);
});
SRVEOF

run_step "Syncing shell scripts to API"
cp /root/bot/shell_script/* /root/vps-api/shell_script/ 2>/dev/null || true

cd /root/vps-api
run_step "Installing API modules"
npm install &> /dev/null

run_step "Creating bot service"
cat > /etc/systemd/system/bot.service << EOF
[Unit]
Description=Telegram VPN Bot
After=network.target

[Service]
Type=simple
User=root
WorkingDirectory=/root/bot
ExecStart=/usr/bin/node index.js
Restart=always
RestartSec=5
Environment=NODE_ENV=production

[Install]
WantedBy=multi-user.target
EOF

run_step "Creating API service"
cat > /etc/systemd/system/vps-api.service << EOF
[Unit]
Description=VPS Bot API Server
After=network.target

[Service]
Type=simple
User=root
WorkingDirectory=/root/vps-api
ExecStart=/usr/bin/node server.js
Restart=always
RestartSec=5
Environment=API_TOKEN=${API_TOKEN}
Environment=API_PORT=${API_PORT}

[Install]
WantedBy=multi-user.target
EOF

run_step "Starting services"
systemctl daemon-reload
systemctl enable bot &> /dev/null
systemctl enable vps-api &> /dev/null
systemctl restart vps-api
systemctl restart bot

run_step "Cleaning temporary files"
cd ~
rm -f bot.zip
rm -rf /tmp/bot_EXTRACT

SAVE_FILE="/root/bot-credentials.txt"
cat > "$SAVE_FILE" << EOF
============================================
  BOT & API CREDENTIALS
  Tanggal: $(date '+%Y-%m-%d %H:%M:%S')
============================================

BOT TOKEN     : $BOT_TOKEN
OWNER ID      : $OWNER_ID
BOT NAME      : $BOT_NAME

SERVER NAME   : $SERVER_NAME
SERVER IP     : $SERVER_IP
API PORT      : $API_PORT
API TOKEN     : $API_TOKEN
API URL       : http://${SERVER_IP}:${API_PORT}

PAKASIR SLUG  : $PAKASIR_SLUG
PAKASIR API   : $PAKASIR_API_KEY

============================================
  SIMPAN FILE INI! /root/bot-credentials.txt
============================================
EOF
chmod 600 "$SAVE_FILE"

reset_ui
echo -e "${CYAN_SOFT}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${GREEN}✔ Installation completed successfully${NC}"
echo -e "${CYAN_SOFT}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""
echo -e " ${WHITE}Bot Service${NC}"
echo -e "   ${DIM}Status  :${NC} ${GREEN}Running${NC}"
echo -e "   ${DIM}Manage  :${NC} systemctl [start|stop|restart|status] bot"
echo -e "   ${DIM}Log     :${NC} journalctl -u bot -f"
echo ""
echo -e " ${WHITE}API Service${NC}"
echo -e "   ${DIM}Status  :${NC} ${GREEN}Running${NC}"
echo -e "   ${DIM}URL     :${NC} ${CYAN}http://${SERVER_IP}:${API_PORT}${NC}"
echo -e "   ${DIM}Manage  :${NC} systemctl [start|stop|restart|status] vps-api"
echo -e "   ${DIM}Log     :${NC} journalctl -u vps-api -f"
echo ""
echo -e "${CYAN_SOFT}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e " ${YELLOW}⚠  API Token & credentials disimpan di:${NC}"
echo -e "    ${WHITE}/root/bot-credentials.txt${NC}"
echo -e "${CYAN_SOFT}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""
echo -e " ${DIM}Test API:${NC}"
echo -e " curl -H 'X-Api-Token: ${API_TOKEN}' http://localhost:${API_PORT}/api/ping"
echo ""
