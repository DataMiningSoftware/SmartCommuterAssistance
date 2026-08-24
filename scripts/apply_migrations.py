from __future__ import annotations

import os
import sys
from pathlib import Path

MIGRATIONS = [
    "migration_crowd_system.sql",
    "migration_day_of_week.sql",
    "migration_trip_feedback.sql",
    "migration_get_unique_stations.sql",
    "migration_cleanup.sql",
    "rls_policies.sql",
]


def main() -> None:
    url = os.getenv("DATABASE_URL", "").strip()
    if not url:
        print(
            "Set DATABASE_URL to your Supabase connection string:\n"
            "  Supabase Dashboard > Project Settings > Database > Connection string (Session pooler or Direct)\n"
            "  e.g. postgresql://postgres.<ref>:<password>@aws-0-ap-southeast-1.pooler.supabase.com:5432/postgres\n"
            "\nInstall driver first: pip install psycopg2-binary"
        )
        sys.exit(1)

    import psycopg2

    base = Path(__file__).resolve().parents[1] / "supabase"
    conn = psycopg2.connect(url)
    conn.autocommit = True

    with conn.cursor() as cur:
        for name in MIGRATIONS:
            path = base / name
            if not path.exists():
                print(f"  SKIP (missing): {name}")
                continue
            sql = path.read_text(encoding="utf-8")
            print(f"Applying {name} ...")
            cur.execute(sql)

    conn.close()
    print("All migrations applied.")


if __name__ == "__main__":
    main()
