# Checks a running example from inside the backend container, which shares the
# host's network: health, the web interface's login page and form, a refused
# password, an API login, and that the SOC 2, ISO 27001 and HIPAA libraries
# load and show up as frameworks, and that nothing listens beyond loopback.
# Pass "persisted" as the first argument after a restart: it then expects them
# to be loaded already rather than loading them.
import json
import sys
import time
import urllib.error
import urllib.parse
import urllib.request

API = "http://127.0.0.1:8000/api"
WEB = "http://127.0.0.1:3000"
EMAIL = "admin@example.com"
PASSWORD = "audit-binder-lantern"

# Library URN and the framework it should create. HIPAA comes as NIST SP 800-66
# rev 2, NIST's guide to the Security Rule.
LIBRARIES = {
    "urn:intuitem:risk:library:soc2-2017-rev-2022": "SOC2-2017 Trust Services Criteria (revision 2022)",
    "urn:intuitem:risk:library:iso27001-2022": "International standard ISO/IEC 27001:2022",
    "urn:intuitem:risk:library:nist-sp-800-66-rev2": "NIST SP-800-66 rev2 (HIPAA)",
}


class NoRedirect(urllib.request.HTTPRedirectHandler):
    def redirect_request(self, *args):
        return None


opener = urllib.request.build_opener(NoRedirect)


def call(url, data=None, headers=None, form=False):
    if data is not None:
        data = urllib.parse.urlencode(data).encode() if form else json.dumps(data).encode()
    h = {"Content-Type": "application/x-www-form-urlencoded" if form else "application/json"}
    req = urllib.request.Request(url, data=data, headers={**h, **(headers or {})})
    try:
        with opener.open(req, timeout=300) as r:
            return r.status, r.read().decode()
    except urllib.error.HTTPError as e:
        return e.code, e.read().decode()


def expect(ok, what):
    if not ok:
        sys.exit(f"FAILED: {what}")
    print(f"ok: {what}")


status, body = 0, ""
for _ in range(120):
    try:
        status, body = call(f"{API}/health/")
        if status == 200:
            break
    except OSError:
        pass
    time.sleep(5)
expect(status == 200, f"health answered {status}")

status, _ = call(f"{WEB}/login")
expect(status == 200, f"login page answered {status}")

status, body = call(
    f"{WEB}/login?/login",
    {"username": EMAIL, "password": PASSWORD},
    {"Origin": "http://localhost:3000", "Accept": "application/json"},
    form=True,
)
expect(status == 200 and '"redirect"' in body, f"login form through the web interface: {status} {body[:200]}")

login = f"{API}/_allauth/app/v1/auth/login"
status, _ = call(login, {"email": EMAIL, "password": "not-the-password"})
expect(status != 200, f"wrong password refused with {status}")

status, body = call(login, {"email": EMAIL, "password": PASSWORD})
expect(status == 200, f"API login answered {status}")
auth = {"Authorization": "Token " + json.loads(body)["meta"]["access_token"]}

status, _ = call(f"{API}/stored-libraries/")
expect(status == 401, f"library list without a token answered {status}")

for urn, name in LIBRARIES.items():
    if sys.argv[1:] != ["persisted"]:
        status, body = call(f"{API}/stored-libraries/{urn}/import/", {}, auth)
        expect(status == 200 and json.loads(body).get("status") == "success", f"{name} load: {status} {body[:200]}")
    status, body = call(f"{API}/frameworks/", headers=auth)
    names = [f.get("name") for f in json.loads(body).get("results", [])] if status == 200 else []
    expect(name in names, f"framework present: {name}")

# The host's listening sockets, since this container shares its network. Both
# ports have to be on loopback, as the example leaves them.
for port in (8000, 3000):
    hexport = f"{port:04X}"
    bound = {}
    for path in ("/proc/net/tcp", "/proc/net/tcp6"):
        for line in open(path).read().splitlines()[1:]:
            f = line.split()
            if f[3] == "0A" and f[1].endswith(":" + hexport):
                bound[f[1]] = True
    expect(list(bound) == [f"0100007F:{hexport}"], f"port {port} listens only on 127.0.0.1: {list(bound)}")

print("All checks passed.")
