"""Private-Wi-Fi HTTPS for run_local.py. Phone must trust the generated public CA.

No tunnel, public deployment, browser security bypass or production settings change.
Uses only Python's standard library and the system OpenSSL executable.
"""

import argparse
import http.client
import ipaddress
import os
import ssl
import subprocess
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from urllib.parse import urlsplit


def certificates(folder: Path, address: str) -> tuple[Path, Path]:
    folder.mkdir(parents=True, exist_ok=True, mode=0o700)
    folder.chmod(0o700)
    ca, ca_key = folder / "phone-test-ca.crt", folder / "ca.key"
    cert, key = folder / "server.crt", folder / "server.key"

    def openssl(*args):
        subprocess.run(["openssl", *map(str, args)], check=True, capture_output=True, timeout=30)

    # Files with private keys stay local, outside the web root and Git.
    previous = os.umask(0o077)
    try:
        if not ca.exists():
            config = folder / "ca.conf"
            config.write_text(
                "[req]\nprompt=no\ndistinguished_name=dn\nx509_extensions=ca\n"
                "[dn]\nCN=ERP private Wi-Fi test CA\n[ca]\n"
                "basicConstraints=critical,CA:TRUE\n"
                "keyUsage=critical,keyCertSign,cRLSign\nsubjectKeyIdentifier=hash\n"
                "authorityKeyIdentifier=keyid:always\n"
            )
            openssl(
                "req",
                "-x509",
                "-newkey",
                "rsa:2048",
                "-nodes",
                "-sha256",
                "-days",
                "30",
                "-keyout",
                ca_key,
                "-out",
                ca,
                "-config",
                config,
            )
        if not ca_key.is_file():
            raise RuntimeError("Local CA private key is missing; use a fresh TLS folder.")
        config = folder / "server.conf"
        config.write_text(
            "[req]\nprompt=no\ndistinguished_name=dn\n[dn]\nCN=ERP Wi-Fi test\n"
            "[server]\nbasicConstraints=critical,CA:FALSE\n"
            "keyUsage=critical,digitalSignature,keyEncipherment\n"
            "extendedKeyUsage=serverAuth\n"
            "subjectKeyIdentifier=hash\nauthorityKeyIdentifier=keyid,issuer\n"
            f"subjectAltName=IP:{address},IP:127.0.0.1,DNS:localhost\n"
        )
        csr = folder / "server.csr"
        openssl(
            "req",
            "-new",
            "-newkey",
            "rsa:2048",
            "-nodes",
            "-keyout",
            key,
            "-out",
            csr,
            "-config",
            config,
        )
        openssl(
            "x509",
            "-req",
            "-in",
            csr,
            "-CA",
            ca,
            "-CAkey",
            ca_key,
            "-CAcreateserial",
            "-out",
            cert,
            "-days",
            "7",
            "-sha256",
            "-extfile",
            config,
            "-extensions",
            "server",
        )
    finally:
        os.umask(previous)
    return cert, key


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--address", required=True, help="This laptop's private Wi-Fi IPv4")
    parser.add_argument("--port", type=int, default=8443)
    parser.add_argument("--upstream-port", type=int, default=8000)
    parser.add_argument("--data", type=Path, default=Path("local-data/https"))
    args = parser.parse_args()
    address = ipaddress.IPv4Address(args.address)
    networks = [ipaddress.ip_network(n) for n in ("10.0.0.0/8", "172.16.0.0/12", "192.168.0.0/16")]
    if not any(address in network for network in networks):
        parser.error("Use a private Wi-Fi IPv4 address; this helper is not public hosting.")
    if not all(1 <= port <= 65535 for port in (args.port, args.upstream_port)):
        parser.error("Ports must be between 1 and 65535.")
    if args.port == args.upstream_port:
        parser.error("HTTPS and upstream ports must differ.")
    cert, key = certificates(args.data.resolve(), str(address))
    allowed_hosts = {str(address), "127.0.0.1", "localhost"}
    hop_headers = {
        "connection",
        "keep-alive",
        "proxy-authenticate",
        "proxy-authorization",
        "te",
        "trailer",
        "transfer-encoding",
        "upgrade",
    }

    class Proxy(BaseHTTPRequestHandler):
        protocol_version = "HTTP/1.1"

        def log_message(self, *_):
            pass  # Do not print URLs, request bodies, cookies or session tokens.

        def forward(self):
            self.connection.settimeout(30)
            target = urlsplit(self.path)
            host = urlsplit("//" + self.headers.get("Host", "")).hostname
            if host not in allowed_hosts or target.scheme or target.netloc:
                self.send_error(400)
                return
            if self.headers.get("Transfer-Encoding"):
                self.send_error(501)
                return
            try:
                length = int(self.headers.get("Content-Length", "0"))
            except ValueError:
                self.send_error(400)
                return
            if length < 0 or length > 16 * 1024 * 1024:
                self.send_error(413)
                return
            headers = {
                k: v
                for k, v in self.headers.items()
                if k.lower() not in hop_headers and not k.lower().startswith("x-forwarded-")
            }
            connection = http.client.HTTPConnection("127.0.0.1", args.upstream_port, timeout=60)
            responded = False
            try:
                connection.request(
                    self.command,
                    self.path,
                    body=self.rfile.read(length),
                    headers=headers,
                )
                response = connection.getresponse()
                self.send_response(response.status)
                responded = True
                for name, value in response.getheaders():
                    if name.lower() not in hop_headers:
                        self.send_header(name, value)
                self.send_header("Connection", "close")
                self.end_headers()
                if self.command != "HEAD":
                    while block := response.read(65536):
                        self.wfile.write(block)
            except (ConnectionError, TimeoutError, OSError):
                if not responded:
                    self.send_error(502)
                self.close_connection = True
            finally:
                connection.close()
                self.close_connection = True

        do_GET = do_HEAD = do_POST = do_PUT = do_PATCH = do_DELETE = do_OPTIONS = forward

    server = ThreadingHTTPServer((str(address), args.port), Proxy)
    context = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
    context.minimum_version = ssl.TLSVersion.TLSv1_2
    context.load_cert_chain(cert, key)
    server.socket = context.wrap_socket(server.socket, server_side=True)
    print(f"Phone address: https://{address}:{args.port}/", flush=True)
    print(
        "Install and trust ONLY this public CA certificate on the test phone: "
        f"{args.data.resolve() / 'phone-test-ca.crt'}",
        flush=True,
    )
    print(
        "Keep the laptop and phone on private Wi-Fi. Stop with Ctrl+C. "
        "Certificates are for local testing only.",
        flush=True,
    )
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        pass
    finally:
        server.server_close()


if __name__ == "__main__":
    main()
