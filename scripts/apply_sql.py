from __future__ import annotations

import argparse
import os
from pathlib import Path


def main() -> None:
    parser = argparse.ArgumentParser(description="Apply a single SQL file to Supabase.")
    parser.add_argument("sql_file", type=Path)
    parser.add_argument("--url", default=os.getenv("DATABASE_URL", "").strip())
    args = parser.parse_args()

    if not args.url:
        raise SystemExit(
            "Set DATABASE_URL (Supabase Dashboard > Project Settings > Database > "
            "Connection string, Session pooler) or pass --url."
        )
    if not args.sql_file.exists():
        raise SystemExit(f"SQL file not found: {args.sql_file}")

    try:
        import psycopg2
    except ImportError as error:
        raise SystemExit("Install the driver first: pip install psycopg2-binary") from error

    sql = args.sql_file.read_text(encoding="utf-8")
    conn = psycopg2.connect(args.url)
    try:
        conn.autocommit = True
        with conn.cursor() as cursor:
            cursor.execute(sql)
    finally:
        conn.close()
    print(f"Applied {args.sql_file}")


if __name__ == "__main__":
    main()
