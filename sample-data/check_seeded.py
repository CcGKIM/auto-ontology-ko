"""Exit 0 when the sample database is fully loaded, 1 otherwise.

"Fully loaded" means the database exists, the biggest fact table has rows, and
the foreign keys exist. The seed script applies foreign keys last, so a load
that stopped half way is reported as not loaded and gets redone.
"""

import os
import sys

import psycopg
from psycopg.conninfo import make_conninfo


def connect(dbname: str) -> psycopg.Connection:
    return psycopg.connect(
        make_conninfo(
            host=os.environ.get("POSTGRES_HOST", "postgres"),
            port=os.environ.get("POSTGRES_PORT", "5432"),
            user=os.environ.get("POSTGRES_USER", "postgres"),
            password=os.environ.get("POSTGRES_PASSWORD", ""),
            dbname=dbname,
        ),
        connect_timeout=10,
    )


def main() -> int:
    database = sys.argv[1]
    try:
        with connect(os.environ.get("POSTGRES_DATABASE", "auto_ontology")) as admin:
            exists = admin.execute(
                "SELECT 1 FROM pg_database WHERE datname = %s", (database,)
            ).fetchone()
        if not exists:
            return 1
        with connect(database) as conn:
            rows = conn.execute("SELECT count(*) FROM sales.invoicelines").fetchone()[0]
            fks = conn.execute(
                "SELECT count(*) FROM pg_constraint WHERE contype = 'f'"
            ).fetchone()[0]
        return 0 if rows > 0 and fks > 0 else 1
    except Exception:
        return 1


if __name__ == "__main__":
    sys.exit(main())
