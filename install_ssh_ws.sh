#!/bin/bash
# ═══════════════════════════════════════════════════════════════
#  SSH WebSocket Installer v1.0
#  Instala y configura SSH sobre WebSocket (WS/WSS)
#  Puerto 80 (WS) y 443 (WSS con TLS)
#  Autor: Depwise | github.com/Depwisescript
# ═══════════════════════════════════════════════════════════════

set -e

# ── Colores ──
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
PURPLE='\033[0;35m'
BOLD='\033[1m'
NC='\033[0m'

WS_PORT=80
WSS_PORT=443
SSH_PORT=22
CERT_DIR="/etc/ssh-ws/certs"
SERVICE_WS="ssh-ws"
SERVICE_WSS="ssh-wss"
PROXY_SCRIPT="/usr/local/bin/ssh-ws-proxy.py"

# ── Verificación de root ──
check_root() {
    if [ "$(id -u)" != "0" ]; then
        echo -e "${RED}[✘] Este script debe ejecutarse como root (sudo).${NC}"
        exit 1
    fi
}

# ── Banner ──
show_banner() {
    clear
    echo -e "${PURPLE}╔══════════════════════════════════════════════╗${NC}"
    echo -e "${PURPLE}║${CYAN}${BOLD}     SSH WebSocket Installer v1.0            ${NC}${PURPLE}║${NC}"
    echo -e "${PURPLE}║${NC}     WS (:80) + WSS (:443) con TLS          ${PURPLE}║${NC}"
    echo -e "${PURPLE}║${NC}     github.com/Depwisescript                ${PURPLE}║${NC}"
    echo -e "${PURPLE}╚══════════════════════════════════════════════╝${NC}"
    echo ""
}

# ── Instalar dependencias ──
install_deps() {
    echo -e "${CYAN}[1/5] Instalando dependencias...${NC}"
    apt-get update -qq > /dev/null 2>&1
    apt-get install -y -qq python3 openssl openssh-server > /dev/null 2>&1

    echo -e "${GREEN}  ✔ Python3, OpenSSL y OpenSSH instalados.${NC}"
}

# ── Generar certificado SSL auto-firmado ──
generate_ssl_cert() {
    echo -e "${CYAN}[2/5] Generando certificado SSL...${NC}"
    mkdir -p "$CERT_DIR"

    if [ ! -f "$CERT_DIR/cert.pem" ] || [ ! -f "$CERT_DIR/key.pem" ]; then
        openssl req -x509 -newkey rsa:2048 \
            -keyout "$CERT_DIR/key.pem" \
            -out "$CERT_DIR/cert.pem" \
            -days 3650 -nodes \
            -subj "/C=US/ST=Cloud/L=VPS/O=SSH-WS/CN=ssh-websocket" \
            > /dev/null 2>&1
        echo -e "${GREEN}  ✔ Certificado SSL generado (válido 10 años).${NC}"
    else
        echo -e "${YELLOW}  ⚠ Certificado SSL ya existe, reutilizando.${NC}"
    fi
}

# ── Crear el proxy WebSocket en Python ──
create_proxy_script() {
    echo -e "${CYAN}[3/5] Creando proxy WebSocket...${NC}"

    cat > "$PROXY_SCRIPT" << 'PYEOF'
#!/usr/bin/env python3
"""
SSH WebSocket Proxy Server v2.0 (Raw TCP)
Acepta conexiones HTTP/WS, responde 101 Switching Protocols,
y hace pipe bidireccional raw TCP al servidor SSH local.

Compatible con: HTTP Injector, HTTP Custom, HA Tunnel Plus, etc.
Sin dependencias externas — solo stdlib de Python.
"""

import asyncio
import sys
import ssl
import signal
import os

BUFFER_SIZE = 65536
SSH_HOST = "127.0.0.1"
SSH_PORT = 22

# Respuestas HTTP estándar
RESPONSE_101 = (
    b"HTTP/1.1 101 Switching Protocols\r\n"
    b"Upgrade: websocket\r\n"
    b"Connection: Upgrade\r\n"
    b"\r\n"
)

RESPONSE_200 = (
    b"HTTP/1.1 200 Connection established\r\n"
    b"\r\n"
)

active_connections = 0

async def pipe(reader, writer, label=""):
    """Pipe bidireccional de datos entre dos streams."""
    try:
        while True:
            data = await reader.read(BUFFER_SIZE)
            if not data:
                break
            writer.write(data)
            await writer.drain()
    except (ConnectionResetError, BrokenPipeError, OSError):
        pass
    except Exception:
        pass
    finally:
        try:
            writer.close()
        except:
            pass


async def handle_client(client_reader, client_writer):
    """Maneja cada conexión entrante."""
    global active_connections
    active_connections += 1

    # Obtener IP del cliente
    client_ip = "unknown"
    try:
        peername = client_writer.get_extra_info("peername")
        if peername:
            client_ip = peername[0]
    except:
        pass

    ssh_writer = None
    try:
        # 1. Leer el payload HTTP del cliente
        try:
            payload = await asyncio.wait_for(client_reader.read(BUFFER_SIZE), timeout=10)
        except asyncio.TimeoutError:
            client_writer.close()
            active_connections -= 1
            return

        if not payload:
            client_writer.close()
            active_connections -= 1
            return

        # 2. Detectar tipo de request y responder
        payload_str = payload.decode("utf-8", errors="ignore").upper()

        if "UPGRADE" in payload_str or "WEBSOCKET" in payload_str:
            # WebSocket upgrade → responder 101
            client_writer.write(RESPONSE_101)
        elif "CONNECT" in payload_str:
            # HTTP CONNECT → responder 200
            client_writer.write(RESPONSE_200)
        else:
            # Cualquier otro HTTP → responder 200 (compatibilidad máxima)
            client_writer.write(RESPONSE_200)

        await client_writer.drain()

        # 3. Conectar al servidor SSH local
        try:
            ssh_reader, ssh_writer = await asyncio.open_connection(SSH_HOST, SSH_PORT)
        except ConnectionRefusedError:
            print(f"[!] SSH no disponible en {SSH_HOST}:{SSH_PORT}")
            client_writer.close()
            active_connections -= 1
            return
        except Exception as e:
            print(f"[!] Error SSH: {e}")
            client_writer.close()
            active_connections -= 1
            return

        print(f"[+] Conectado: {client_ip} → SSH (total: {active_connections})")

        # 4. Pipe bidireccional: Cliente ↔ SSH
        await asyncio.gather(
            pipe(client_reader, ssh_writer, "C→S"),
            pipe(ssh_reader, client_writer, "S→C"),
        )

    except Exception:
        pass
    finally:
        active_connections -= 1
        print(f"[-] Desconectado: {client_ip} (total: {active_connections})")
        try:
            client_writer.close()
        except:
            pass
        if ssh_writer:
            try:
                ssh_writer.close()
            except:
                pass


async def start_server(port, ssl_context=None):
    """Inicia el servidor TCP proxy."""
    mode = "WSS+TLS" if ssl_context else "WS"
    server = await asyncio.start_server(
        handle_client, "0.0.0.0", port, ssl=ssl_context
    )
    print(f"[*] SSH WebSocket Proxy v2.0 ({mode}) → puerto {port}")
    print(f"[*] Redirigiendo a SSH {SSH_HOST}:{SSH_PORT}")
    print(f"[*] Esperando conexiones...")

    async with server:
        await server.serve_forever()


def main():
    if len(sys.argv) < 2:
        print("Uso: ssh-ws-proxy.py <puerto> [cert_dir]")
        sys.exit(1)

    port = int(sys.argv[1])
    ssl_context = None

    if len(sys.argv) >= 3:
        cert_dir = sys.argv[2]
        cert_file = os.path.join(cert_dir, "cert.pem")
        key_file = os.path.join(cert_dir, "key.pem")

        if os.path.exists(cert_file) and os.path.exists(key_file):
            ssl_context = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
            ssl_context.load_cert_chain(cert_file, key_file)
            print(f"[*] TLS habilitado: {cert_file}")
        else:
            print(f"[!] Certificados no encontrados en {cert_dir}")
            sys.exit(1)

    loop = asyncio.new_event_loop()
    asyncio.set_event_loop(loop)

    for sig in (signal.SIGTERM, signal.SIGINT):
        try:
            loop.add_signal_handler(sig, lambda: loop.stop())
        except NotImplementedError:
            pass

    try:
        loop.run_until_complete(start_server(port, ssl_context))
    except KeyboardInterrupt:
        print("\n[*] Servidor detenido.")
    finally:
        loop.close()


if __name__ == "__main__":
    main()
PYEOF

    chmod +x "$PROXY_SCRIPT"
    echo -e "${GREEN}  ✔ Proxy WebSocket creado en ${PROXY_SCRIPT}${NC}"
}

# ── Crear servicios systemd ──
create_services() {
    echo -e "${CYAN}[4/5] Creando servicios systemd...${NC}"

    # Servicio WS (puerto 80)
    cat > "/etc/systemd/system/${SERVICE_WS}.service" << EOF
[Unit]
Description=SSH WebSocket Proxy (WS Puerto ${WS_PORT})
After=network.target sshd.service
Wants=sshd.service

[Service]
Type=simple
ExecStart=/usr/bin/python3 ${PROXY_SCRIPT} ${WS_PORT}
Restart=always
RestartSec=3
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
EOF

    # Servicio WSS (puerto 443 con TLS)
    cat > "/etc/systemd/system/${SERVICE_WSS}.service" << EOF
[Unit]
Description=SSH WebSocket Proxy SSL (WSS Puerto ${WSS_PORT})
After=network.target sshd.service
Wants=sshd.service

[Service]
Type=simple
ExecStart=/usr/bin/python3 ${PROXY_SCRIPT} ${WSS_PORT} ${CERT_DIR}
Restart=always
RestartSec=3
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
EOF

    systemctl daemon-reload
    echo -e "${GREEN}  ✔ Servicios ${SERVICE_WS} y ${SERVICE_WSS} creados.${NC}"
}

# ── Iniciar servicios ──
start_services() {
    echo -e "${CYAN}[5/5] Iniciando servicios...${NC}"

    # Verificar si los puertos están ocupados
    local ws_busy=false
    local wss_busy=false

    if ss -tlnp | grep -q ":${WS_PORT} " 2>/dev/null; then
        local ws_proc
        ws_proc=$(ss -tlnp | grep ":${WS_PORT} " | head -1)
        echo -e "${YELLOW}  ⚠ Puerto ${WS_PORT} ocupado por: ${ws_proc}${NC}"
        echo -e "${YELLOW}    → Deteniendo proceso en puerto ${WS_PORT}...${NC}"
        fuser -k ${WS_PORT}/tcp 2>/dev/null || true
        sleep 1
    fi

    if ss -tlnp | grep -q ":${WSS_PORT} " 2>/dev/null; then
        local wss_proc
        wss_proc=$(ss -tlnp | grep ":${WSS_PORT} " | head -1)
        echo -e "${YELLOW}  ⚠ Puerto ${WSS_PORT} ocupado por: ${wss_proc}${NC}"
        echo -e "${YELLOW}    → Deteniendo proceso en puerto ${WSS_PORT}...${NC}"
        fuser -k ${WSS_PORT}/tcp 2>/dev/null || true
        sleep 1
    fi

    systemctl enable "${SERVICE_WS}" > /dev/null 2>&1
    systemctl enable "${SERVICE_WSS}" > /dev/null 2>&1
    systemctl start "${SERVICE_WS}"
    systemctl start "${SERVICE_WSS}"

    sleep 2

    # Verificar estado
    if systemctl is-active --quiet "${SERVICE_WS}"; then
        echo -e "${GREEN}  ✔ SSH-WS  (Puerto ${WS_PORT})  → ACTIVO ✅${NC}"
    else
        echo -e "${RED}  ✘ SSH-WS  (Puerto ${WS_PORT})  → ERROR ❌${NC}"
        echo -e "${YELLOW}    Revisa logs: journalctl -u ${SERVICE_WS} -n 20${NC}"
    fi

    if systemctl is-active --quiet "${SERVICE_WSS}"; then
        echo -e "${GREEN}  ✔ SSH-WSS (Puerto ${WSS_PORT}) → ACTIVO ✅${NC}"
    else
        echo -e "${RED}  ✘ SSH-WSS (Puerto ${WSS_PORT}) → ERROR ❌${NC}"
        echo -e "${YELLOW}    Revisa logs: journalctl -u ${SERVICE_WSS} -n 20${NC}"
    fi
}

# ── Mostrar resumen final ──
show_summary() {
    local PUBLIC_IP
    PUBLIC_IP=$(curl -s ifconfig.me 2>/dev/null || curl -s icanhazip.com 2>/dev/null || echo "N/A")

    echo ""
    echo -e "${PURPLE}╔══════════════════════════════════════════════╗${NC}"
    echo -e "${PURPLE}║${GREEN}${BOLD}       ✅ INSTALACIÓN COMPLETADA             ${NC}${PURPLE}║${NC}"
    echo -e "${PURPLE}╚══════════════════════════════════════════════╝${NC}"
    echo ""
    echo -e "${BOLD}📡 Datos de Conexión:${NC}"
    echo -e "  🌐 IP del servidor:  ${CYAN}${PUBLIC_IP}${NC}"
    echo -e "  🔓 WS  (sin SSL):   ${CYAN}ws://${PUBLIC_IP}:${WS_PORT}${NC}"
    echo -e "  🔒 WSS (con SSL):   ${CYAN}wss://${PUBLIC_IP}:${WSS_PORT}${NC}"
    echo -e "  🔑 SSH Port:         ${CYAN}${SSH_PORT}${NC}"
    echo ""
    echo -e "${BOLD}📋 Comandos Útiles:${NC}"
    echo -e "  Estado WS:   ${YELLOW}systemctl status ${SERVICE_WS}${NC}"
    echo -e "  Estado WSS:  ${YELLOW}systemctl status ${SERVICE_WSS}${NC}"
    echo -e "  Logs WS:     ${YELLOW}journalctl -u ${SERVICE_WS} -f${NC}"
    echo -e "  Logs WSS:    ${YELLOW}journalctl -u ${SERVICE_WSS} -f${NC}"
    echo -e "  Reiniciar:   ${YELLOW}systemctl restart ${SERVICE_WS} ${SERVICE_WSS}${NC}"
    echo ""
    echo -e "${BOLD}📱 Config para HTTP Custom / HTTP Injector:${NC}"
    echo -e "  Método:      ${CYAN}WebSocket${NC}"
    echo -e "  Host:        ${CYAN}${PUBLIC_IP}${NC}"
    echo -e "  Puerto WS:   ${CYAN}${WS_PORT}${NC}"
    echo -e "  Puerto WSS:  ${CYAN}${WSS_PORT}${NC}"
    echo -e "  Payload:     ${CYAN}GET / HTTP/1.1[crlf]Host: [host][crlf]Upgrade: websocket[crlf][crlf]${NC}"
    echo ""
}

# ── Mostrar estado ──
show_status() {
    show_banner
    echo -e "${BOLD}📊 Estado de los Servicios:${NC}"
    echo ""

    for svc in "$SERVICE_WS" "$SERVICE_WSS"; do
        if systemctl is-active --quiet "$svc"; then
            echo -e "  ${GREEN}● ${svc} → ACTIVO${NC}"
        else
            echo -e "  ${RED}● ${svc} → INACTIVO${NC}"
        fi
    done

    echo ""
    echo -e "${BOLD}🔌 Puertos Escuchando:${NC}"
    ss -tlnp | grep -E ":(${WS_PORT}|${WSS_PORT}) " 2>/dev/null || echo -e "  ${YELLOW}Ningún puerto activo.${NC}"
    echo ""

    echo -e "${BOLD}📊 Conexiones Activas:${NC}"
    ss -tnp | grep -E ":(${WS_PORT}|${WSS_PORT}) " 2>/dev/null | wc -l | xargs -I{} echo -e "  WebSocket: {} conexiones"
    echo ""
}

# ── Desinstalar ──
uninstall() {
    show_banner
    echo -e "${YELLOW}⚠ Desinstalando SSH WebSocket...${NC}"
    echo ""

    # Detener y deshabilitar servicios
    systemctl stop "${SERVICE_WS}" 2>/dev/null || true
    systemctl stop "${SERVICE_WSS}" 2>/dev/null || true
    systemctl disable "${SERVICE_WS}" 2>/dev/null || true
    systemctl disable "${SERVICE_WSS}" 2>/dev/null || true

    # Eliminar archivos
    rm -f "/etc/systemd/system/${SERVICE_WS}.service"
    rm -f "/etc/systemd/system/${SERVICE_WSS}.service"
    rm -f "$PROXY_SCRIPT"
    rm -rf "$CERT_DIR"
    rm -rf "/etc/ssh-ws"

    systemctl daemon-reload

    echo -e "${GREEN}✅ SSH WebSocket desinstalado completamente.${NC}"
    echo -e "  ${CYAN}Los servicios, certificados y scripts han sido eliminados.${NC}"
    echo -e "  ${CYAN}OpenSSH no fue afectado.${NC}"
    echo ""
}

# ── Menú Principal ──
show_menu() {
    show_banner
    echo -e "${BOLD}Selecciona una opción:${NC}"
    echo ""
    echo -e "  ${GREEN}1)${NC} 📥 Instalar SSH WebSocket (WS + WSS)"
    echo -e "  ${CYAN}2)${NC} 📊 Ver Estado"
    echo -e "  ${YELLOW}3)${NC} 🔄 Reiniciar Servicios"
    echo -e "  ${RED}4)${NC} 🗑️  Desinstalar"
    echo -e "  ${PURPLE}0)${NC} ❌ Salir"
    echo ""
    read -rp "Opción [0-4]: " opcion

    case "$opcion" in
        1)
            show_banner
            install_deps
            generate_ssl_cert
            create_proxy_script
            create_services
            start_services
            show_summary
            ;;
        2)
            show_status
            ;;
        3)
            show_banner
            echo -e "${CYAN}🔄 Reiniciando servicios...${NC}"
            systemctl restart "${SERVICE_WS}" 2>/dev/null
            systemctl restart "${SERVICE_WSS}" 2>/dev/null
            sleep 2
            show_status
            ;;
        4)
            uninstall
            ;;
        0)
            echo -e "${CYAN}Saliendo...${NC}"
            exit 0
            ;;
        *)
            echo -e "${RED}Opción inválida.${NC}"
            sleep 1
            show_menu
            ;;
    esac
}

# ── Soporte para argumentos directos ──
case "${1:-}" in
    install)
        check_root
        show_banner
        install_deps
        generate_ssl_cert
        create_proxy_script
        create_services
        start_services
        show_summary
        ;;
    status)
        check_root
        show_status
        ;;
    restart)
        check_root
        systemctl restart "${SERVICE_WS}" "${SERVICE_WSS}"
        echo -e "${GREEN}✅ Servicios reiniciados.${NC}"
        ;;
    uninstall)
        check_root
        uninstall
        ;;
    *)
        check_root
        show_menu
        ;;
esac
