import re
import subprocess
import sys
import textwrap

LIVEKIT_CMD = ["livekit-server.exe", "--config", "livekit.yaml"]

MAX_WIDTH = 120


def print_header(timestamp, level, location, message):
    print()
    print("=" * MAX_WIDTH)
    print(f"{timestamp} [{level}]")
    print(f"{location}")
    print(f"EVENT : {message}")
    print("=" * MAX_WIDTH)


def print_field(name, value):
    wrapped = textwrap.fill(
        str(value),
        width=MAX_WIDTH,
        subsequent_indent=" " * 22,
    )
    print(f"{name:<20}: {wrapped}")


process = subprocess.Popen(
    LIVEKIT_CMD,
    stdout=subprocess.PIPE,
    stderr=subprocess.STDOUT,
    text=True,
    encoding="utf-8",
    errors="replace",
)

pattern = re.compile(
    r"^(?P<time>\S+)\s+"
    r"(?P<level>\w+)\s+"
    r"(?P<location>\S+)\s+"
    r"(?P<message>.*?)\s+"
    r"(?P<data>\{.*\})?$"
)

for line in process.stdout:
    line = line.rstrip()

    m = pattern.match(line)
    if not m:
        print(line)
        continue

    print_header(
        m.group("time"),
        m.group("level"),
        m.group("location"),
        m.group("message"),
    )

    data = m.group("data")
    if data:
        data = data.strip("{}")

        parts = re.split(r',\s*"(?=[^"]+":)', data)

        for part in parts:
            part = part.strip()

            if part.startswith('"'):
                part = part[1:]

            if '":' in part:
                key, value = part.split('":', 1)
                print_field(key, value.strip())

        print()