const connectionState = document.querySelector("#connectionState");
const transportState = document.querySelector("#transportState");
const pairingCode = document.querySelector("#pairingCode");

const macStatusPill = document.querySelector("#macStatusPill");
const macStatusText = document.querySelector("#macStatusText");
const macTransportLabel = document.querySelector("#macTransportLabel");
const macTransportNote = document.querySelector("#macTransportNote");
const androidTransportLabel = document.querySelector("#androidTransportLabel");
const androidTransportNote = document.querySelector("#androidTransportNote");
const macCodeText = document.querySelector("#macCodeText");
const macDigits = document.querySelector("#macDigits");
const androidDigits = document.querySelector("#androidDigits");

const connectionCopy = {
  trusted: {
    pill: "Trusted",
    text: "Ready to auto reconnect",
  },
  pairing: {
    pill: "Pairing",
    text: "4-digit confirmation pending",
  },
  active: {
    pill: "Android Control Mode",
    text: "Keyboard and pointer routed to Android",
  },
  disconnected: {
    pill: "Disconnected",
    text: "Waiting for tablet session",
  },
};

const transportCopy = {
  "usb-adb": {
    label: "USB ADB MVP",
    note: "가장 빠른 구현 경로. Android USB debugging 필요.",
  },
  "usb-aoa": {
    label: "USB AOA Candidate",
    note: "프로덕션 USB 목표. Galaxy Tab S11 실기기 검증 전에는 확정하면 안 됨.",
  },
  udp: {
    label: "UDP Tunnel Ready",
    note: "실제 IP 경로가 있을 때만 사용 가능. Thunderbolt 4만으로는 Android UDP 경로가 생기지 않음.",
  },
  pending: {
    label: "USB Direct Pending",
    note: "케이블은 연결됐지만 앱 전송 계층은 아직 확정되지 않음.",
  },
};

function renderDigits(target, code) {
  target.innerHTML = "";
  const normalized = code.replace(/\D/g, "").slice(0, 4).padEnd(4, "•");

  [...normalized].forEach((digit) => {
    const node = document.createElement("div");
    node.className = target.id === "androidDigits" ? "digit small" : "digit";
    node.textContent = digit;
    target.appendChild(node);
  });
}

function renderConnection() {
  const state = connectionCopy[connectionState.value];
  macStatusPill.textContent = state.pill;
  macStatusText.textContent = state.text;
}

function renderTransport() {
  const state = transportCopy[transportState.value];
  macTransportLabel.textContent = state.label;
  macTransportNote.textContent = state.note;
  androidTransportLabel.textContent = state.label;
  androidTransportNote.textContent = state.note;
}

function renderCode() {
  const code = pairingCode.value.replace(/\D/g, "").slice(0, 4);
  pairingCode.value = code;
  macCodeText.textContent = code || "----";
  renderDigits(macDigits, code);
  renderDigits(androidDigits, code);
}

connectionState.addEventListener("change", renderConnection);
transportState.addEventListener("change", renderTransport);
pairingCode.addEventListener("input", renderCode);

renderConnection();
renderTransport();
renderCode();
