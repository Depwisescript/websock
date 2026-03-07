# 🌐 SSH WebSocket Installer

<p align="center">
  <img src="https://img.shields.io/badge/Version-1.0-blue?style=for-the-badge" alt="Version">
  <img src="https://img.shields.io/badge/License-MIT-green?style=for-the-badge" alt="License">
  <img src="https://img.shields.io/badge/OS-Ubuntu%2FDebian-orange?style=for-the-badge" alt="OS">
  <img src="https://img.shields.io/badge/Python-3.6+-yellow?style=for-the-badge&logo=python&logoColor=white" alt="Python">
</p>

Instalador automático de **SSH sobre WebSocket** para servidores VPS Linux.
Permite conectarse a SSH a través de los puertos **80 (WS)** y **443 (WSS/TLS)**, evitando bloqueos de firewall, NAT y Deep Packet Inspection (DPI).

---

## 🚀 ¿Qué es SSH WebSocket?

SSH WebSocket **encapsula el tráfico SSH dentro de una conexión WebSocket**. Esto hace que las conexiones SSH parezcan tráfico web normal, permitiendo:

- ✅ **Bypass de firewalls** que bloquean el puerto 22
- ✅ **Evasión de DPI** (inspección profunda de paquetes)
- ✅ Conexión a través de **redes móviles restringidas**
- ✅ Compatible con **HTTP Custom**, **HTTP Injector**, **HA Tunnel**, etc.
- ✅ Doble capa de cifrado: **SSH + TLS/SSL**

---

## 🏗️ Arquitectura

```
┌─────────────────────────────────────────────────────────────┐
│                    TU SERVIDOR VPS                          │
│                                                             │
│  ┌──────────────┐     ┌──────────────┐     ┌────────────┐  │
│  │  Puerto 80   │────▶│  ssh-ws      │────▶│            │  │
│  │  (WS)        │     │  proxy.py    │     │  OpenSSH   │  │
│  └──────────────┘     └──────────────┘     │  :22       │  │
│                                             │            │  │
│  ┌──────────────┐     ┌──────────────┐     │            │  │
│  │  Puerto 443  │────▶│  ssh-wss     │────▶│            │  │
│  │  (WSS + TLS) │     │  proxy.py    │     │            │  │
│  └──────────────┘     └──────────────┘     └────────────┘  │
│                                                             │
└─────────────────────────────────────────────────────────────┘
         ▲                                           
         │   WebSocket (ws:// o wss://)               
         │                                           
┌────────┴────────┐                                  
│  📱 Cliente     │                                  
│  HTTP Custom    │                                  
│  HTTP Injector  │                                  
│  HA Tunnel Plus │                                  
└─────────────────┘                                  
```

---

## ⚡ Instalación Rápida

### Opción 1: Una sola línea

```bash
bash <(curl -sL https://raw.githubusercontent.com/Depwisescript/websock/main/install_ssh_ws.sh) install
```

### Opción 2: Clonar y ejecutar

```bash
apt update && apt install -y git
git clone https://github.com/Depwisescript/websock.git
cd websock
chmod +x install_ssh_ws.sh
./install_ssh_ws.sh
```

---

## 📋 Menú Interactivo

Al ejecutar `./install_ssh_ws.sh` sin argumentos, verás:

```
╔══════════════════════════════════════════════╗
║     SSH WebSocket Installer v1.0             ║
║     WS (:80) + WSS (:443) con TLS           ║
╚══════════════════════════════════════════════╝

Selecciona una opción:

  1) 📥 Instalar SSH WebSocket (WS + WSS)
  2) 📊 Ver Estado
  3) 🔄 Reiniciar Servicios
  4) 🗑️  Desinstalar
  0) ❌ Salir
```

---

## 🔧 Comandos Directos

| Comando | Descripción |
|---|---|
| `./install_ssh_ws.sh` | Menú interactivo |
| `./install_ssh_ws.sh install` | Instalación directa sin menú |
| `./install_ssh_ws.sh status` | Ver estado de los servicios |
| `./install_ssh_ws.sh restart` | Reiniciar ambos servicios |
| `./install_ssh_ws.sh uninstall` | Desinstalar completamente |

---

## 📱 Configuración para Clientes VPN

### HTTP Custom

| Campo | Valor |
|---|---|
| **Método** | `WebSocket` |
| **Host** | `IP_DE_TU_VPS` |
| **Puerto** | `80` (WS) o `443` (WSS) |
| **Payload** | `GET / HTTP/1.1[crlf]Host: [host][crlf]Upgrade: websocket[crlf][crlf]` |

### HTTP Injector

| Campo | Valor |
|---|---|
| **SSH Host** | `IP_DE_TU_VPS` |
| **SSH Port** | `22` |
| **Proxy Type** | `WebSocket` |
| **WebSocket Host** | `ws://IP_DE_TU_VPS:80` o `wss://IP_DE_TU_VPS:443` |

### HA Tunnel Plus

| Campo | Valor |
|---|---|
| **Tipo** | `SSH + WebSocket` |
| **Host** | `IP_DE_TU_VPS` |
| **Puerto WS** | `80` |
| **Puerto WSS** | `443` |

---

## 📊 Monitoreo

```bash
# Estado de los servicios
systemctl status ssh-ws
systemctl status ssh-wss

# Logs en tiempo real
journalctl -u ssh-ws -f
journalctl -u ssh-wss -f

# Ver conexiones activas
ss -tnp | grep -E ':(80|443) '

# Reiniciar ambos servicios
systemctl restart ssh-ws ssh-wss
```

---

## 🛡️ Seguridad

- 🔐 **TLS Auto-generado:** Certificado SSL válido por 10 años para WSS
- 🔒 **Doble cifrado:** SSH encapsulado dentro de WebSocket + TLS
- 🔥 **Auto-restart:** Los servicios se reinician automáticamente si fallan
- 🧹 **Desinstalación limpia:** Elimina todos los archivos, servicios y certificados

---

## 📦 ¿Qué instala?

| Componente | Propósito |
|---|---|
| `python3` + `pip` | Runtime para el proxy WebSocket |
| `websockets` (pip) | Librería Python para WebSocket async |
| `openssl` | Generación de certificados SSL |
| `ssh-ws-proxy.py` | Script proxy en `/usr/local/bin/` |
| `ssh-ws.service` | Servicio systemd para WS (puerto 80) |
| `ssh-wss.service` | Servicio systemd para WSS (puerto 443) |
| Certificados SSL | En `/etc/ssh-ws/certs/` |

---

## ⚙️ Requisitos

- Ubuntu 18.04+ / Debian 10+
- Python 3.6+
- OpenSSH Server activo y funcionando
- Acceso root (`sudo`)
- Puertos 80 y 443 disponibles

---

## 🗑️ Desinstalación

```bash
./install_ssh_ws.sh uninstall
```

Esto elimina:
- ✅ Servicios systemd (`ssh-ws`, `ssh-wss`)
- ✅ Script proxy (`/usr/local/bin/ssh-ws-proxy.py`)
- ✅ Certificados SSL (`/etc/ssh-ws/`)
- ❌ **NO** toca OpenSSH ni Python

---

## 🤝 Contribuciones

Las contribuciones son bienvenidas. Abre un issue o envía un PR.

## 📄 Licencia

MIT License - Uso libre y sin restricciones.

---

<p align="center">
  <b>Hecho con ❤️ por <a href="https://github.com/Depwisescript">Depwisescript</a></b>
</p>
