from pathlib import Path
import sys

try:
    import pandas as pd
except ModuleNotFoundError:
    print("Error: pandas is not installed in this Python environment.")
    print(f"Python in use: {sys.executable}")
    print("Install with: python -m pip install pandas")
    raise


def generate_sql():
    script_dir = Path(__file__).resolve().parent
    csv_path = script_dir / "train_stops_kl.csv"
    output_path = script_dir / "insert_connections.sql"

    # 1. Load the data from your Supabase CSV export
    try:
        df = pd.read_csv(csv_path)
    except FileNotFoundError:
        print(f"Error: CSV file not found at: {csv_path}")
        return

    # 2. Clean the data: Remove empty sequences and ensure they are integers
    df = df.dropna(subset=["sequence_order"])
    df["sequence_order"] = df["sequence_order"].astype(int)

    # 3. Sort the data: Group by the train line, then order numerically (1, 2, 3...)
    df = df.sort_values(by=["route_id", "sequence_order"])

    print("Generating SQL script...")

    # 4. Start the SQL statement
    sql_lines = [
        "-- Auto-generated Standard Train Connections",
        "INSERT INTO route_connections (from_stop_id, to_stop_id, route_id, connection_type, travel_time_minutes)",
        "VALUES",
    ]

    values = []

    # 5. The Graph Logic: Loop through each line and connect Stop A to Stop B
    for route, group in df.groupby("route_id"):
        stops = group["stop_id"].tolist()

        for i in range(len(stops) - 1):
            stop_a = stops[i]
            stop_b = stops[i + 1]

            # Note: We set a default travel time of 2 minutes between standard stops.
            # We insert TWICE because trains travel in both directions!
            values.append(f"  ('{stop_a}', '{stop_b}', '{route}', 'standard_stop', 2)")
            values.append(f"  ('{stop_b}', '{stop_a}', '{route}', 'standard_stop', 2)")

    # 6. Format and save the final SQL file
    final_sql = "\n".join(sql_lines) + "\n" + ",\n".join(values) + ";"

    with open(output_path, "w", encoding="utf-8") as f:
        f.write(final_sql)

    print(f"Success! Generated {len(values)} connections.")
    print(f"Open '{output_path}' and paste it into Supabase.")


if __name__ == "__main__":
    generate_sql()
