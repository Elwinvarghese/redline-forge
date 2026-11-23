"""INTENTIONALLY VULNERABLE LAB CODE - ForgeTrack TryHackMe room.

The /diagnostics/ping endpoint passes user input to a shell with shell=True.
This is the intended easy web-to-OS foothold. Do not deploy outside an
isolated lab network.
"""

import subprocess

from flask import Blueprint, render_template, request

lab_bp = Blueprint("lab", __name__)


@lab_bp.get("/diagnostics")
def diagnostics():
    return render_template("diagnostics.html")


@lab_bp.get("/diagnostics/ping")
def diagnostics_ping():
    host = request.args.get("host", "127.0.0.1")

    # INTENTIONALLY VULNERABLE: shell=True + unsanitised user input.
    try:
        output = subprocess.check_output(
            f"ping -c 1 -W 2 {host}",
            shell=True,
            stderr=subprocess.STDOUT,
            text=True,
            timeout=10,
        )
    except subprocess.CalledProcessError as exc:
        output = exc.output or str(exc)
    except subprocess.TimeoutExpired:
        output = "Command timed out."

    return render_template("diagnostics.html", host=host, output=output)
