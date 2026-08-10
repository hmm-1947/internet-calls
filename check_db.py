import subprocess, sys
env = open('backend/.env', encoding='utf-8-sig').read()
db_url = None
for line in env.splitlines():
    if line.startswith('DATABASE_URL'):
        db_url = line.split('=', 1)[1].strip()
try:
    import psycopg2
except ImportError:
    subprocess.run([sys.executable, '-m', 'pip', 'install', '--break-system-packages', 'psycopg2-binary', '-q'])
    import psycopg2

conn = psycopg2.connect(db_url)
cur = conn.cursor()
cur.execute("""
    SELECT id, room_name, status, call_type, connected_at, duration_seconds,
           coins_deducted, billed_minutes, created_at
    FROM calls ORDER BY id DESC LIMIT 8
""")
for row in cur.fetchall():
    print(row)

