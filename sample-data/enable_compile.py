"""Turn semantic compilation on, once, when the operator asked for it.

Semantic compilation is opt-in: it only runs when the ``semantic_compilation_enabled``
row in ``frontend.configurations`` is ``"true"`` (what the Settings toggle writes).
This inserts that row so a fresh stack starts compiling by itself.

* An existing row is left alone, so a choice already made in Settings (even
  "false") is never overridden.
* The table belongs to the frontend's Prisma migration, so this waits for it.
* Exits non-zero only if it could not do it, and the caller treats that as a
  warning rather than a reason to stop the stack.
"""

import os
import sys
import time

import psycopg
from psycopg.conninfo import make_conninfo

KEY = "semantic_compilation_enabled"


def connect() -> psycopg.Connection:
    return psycopg.connect(
        make_conninfo(
            host=os.environ.get("POSTGRES_HOST", "postgres"),
            port=os.environ.get("POSTGRES_PORT", "5432"),
            user=os.environ.get("POSTGRES_USER", "postgres"),
            password=os.environ.get("POSTGRES_PASSWORD", ""),
            dbname=os.environ.get("POSTGRES_DATABASE", "auto_ontology"),
        ),
        connect_timeout=10,
        autocommit=True,
    )


def main() -> int:
    # The frontend migration normally finishes before this runs; the wait is a safety net.
    deadline = time.time() + int(os.environ.get("ENABLE_COMPILE_WAIT_SECONDS", "120"))
    last_error: Exception | None = None
    while time.time() < deadline:
        try:
            with connect() as conn:
                if conn.execute("SELECT to_regclass('frontend.configurations')").fetchone()[0] is None:
                    raise RuntimeError("frontend.configurations does not exist yet")
                inserted = conn.execute(
                    "INSERT INTO frontend.configurations (key, value, updated_at) "
                    "VALUES (%s, 'true', now()) ON CONFLICT (key) DO NOTHING",
                    (KEY,),
                ).rowcount
                if inserted:
                    print("sample-data: semantic compilation switched ON (SAMPLE_AUTO_COMPILE=true).")
                else:
                    current = conn.execute(
                        "SELECT value FROM frontend.configurations WHERE key = %s", (KEY,)
                    ).fetchone()[0]
                    print(
                        f"sample-data: semantic compilation is already set to '{current}' "
                        "in Settings; left unchanged."
                    )
                return 0
        except Exception as exc:  # table not there yet, or the DB is still starting
            last_error = exc
            time.sleep(3)
    print(f"sample-data: could not switch semantic compilation on: {last_error}", file=sys.stderr)
    return 1


if __name__ == "__main__":
    sys.exit(main())
