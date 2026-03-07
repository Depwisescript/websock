# 🌐 SSH WebSocket Installer

Instalador automático de **SSH sobre WebSocket** para servidores VPS Linux.

Permite conectar a SSH a través de los puertos **80 (WS)** y **443 (WSS/TLS)**, evitando bloqueos de firewall y DPI.

## ⚡ Instalación Rápida

```bash
apt update && apt install -y git
git clone https://github.com/Depwisescript/ssh-websocket-installer.git
cd ssh-websocket-installer
chmod +x install_ssh_ws.sh
./install_ssh_ws.sh
```

O en una sola línea:

```bash
bash <(curl -sL https://raw.githubusercontent.com/Depwisescript/ssh-websocket-installer/main/install_ssh_ws.sh) install
```

## 📋 Opciones

| Comando | Descripción |
|---|---|
| `./install_ssh_ws.sh` | Menú interactivo |
| `./install_ssh_ws.sh install` | Instalación directa |
| `./install_ssh_ws.sh status` | Ver estado de los servicios |
| `./install_ssh_ws.sh restart` | Reiniciar servicios |
| `./install_ssh_ws.sh uninstall` | Desinstalar completamente |

## 🏗️ Arquitectura

```
Cliente (HTTP Custom / Injector)
    │
    ├── ws://IP:80   ──→  [ssh-ws proxy]  ──→  sshd :22
    │
    └── wss://IP:443 ──→  [ssh-wss proxy] ──→  sshd :22
                           (con TLS)
```

## 📱 Configuración para HTTP Custom

| Campo | Valor |
|---|---|
| **Método** | WebSocket |
| **Host** | IP de tu VPS |
| **Puerto** | 80 (WS) o 443 (WSS) |
| **Payload** | `GET / HTTP/1.1[crlf]Host: [host][crlf]Upgrade: websocket[crlf][crlf]` |

## 🔧 Requisitos

- Ubuntu 18.04+ / Debian 10+
- Python 3.6+
- OpenSSH Server activo
- Acceso root

## 📊 Comandos Útiles

```bash
# Estado
systemctl status ssh-ws
systemctl status ssh-wss

# Logs en tiempo real
journalctl -u ssh-ws -f
journalctl -u ssh-wss -f

# Reiniciar ambos
systemctl restart ssh-ws ssh-wss

# Conexiones activas
ss -tnp | grep -E ':(80|443) '
```

## 📄 Licencia

MIT License - Uso libre.
