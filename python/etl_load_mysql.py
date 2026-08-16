"""
ETL: clean the raw AtliQ Mart CSVs and load them into the MySQL star schema
defined in sql/00_schema_mysql.sql.

Source CSVs mix two date formats and a UTF-8 BOM on some headers, so this
does real cleaning rather than a straight LOAD DATA INFILE.

Credentials are read from environment variables rather than hardcoded, since
this repo is meant to be pushed to a public GitHub — set ATLIQ_DB_PASSWORD
before running (see .env.example).
"""
import os
from pathlib import Path

import pandas as pd
from sqlalchemy import create_engine

ROOT = Path(__file__).resolve().parent.parent
DATASET_DIR = ROOT / "dataset"

DB_USER = os.environ.get("ATLIQ_DB_USER", "atliq_analyst")
DB_PASSWORD = os.environ["ATLIQ_DB_PASSWORD"]
DB_HOST = os.environ.get("ATLIQ_DB_HOST", "localhost")
DB_NAME = os.environ.get("ATLIQ_DB_NAME", "atliq_mart_supplychain")

engine = create_engine(f"mysql+pymysql://{DB_USER}:{DB_PASSWORD}@{DB_HOST}/{DB_NAME}")


def load_dim_customers() -> pd.DataFrame:
    df = pd.read_csv(DATASET_DIR / "dim_customers.csv", encoding="utf-8-sig")
    df.to_sql("dim_customers", engine, if_exists="append", index=False)
    return df


def load_dim_products() -> pd.DataFrame:
    df = pd.read_csv(DATASET_DIR / "dim_products.csv", encoding="utf-8-sig")
    # Data-quality fix: source data has inconsistent casing ("Dairy", "Food", "beverages")
    df["category"] = df["category"].str.title()
    df.to_sql("dim_products", engine, if_exists="append", index=False)
    return df


def load_dim_date() -> pd.DataFrame:
    df = pd.read_csv(DATASET_DIR / "dim_date.csv", encoding="utf-8-sig")
    df["date"] = pd.to_datetime(df["date"], format="%d-%b-%y")
    df = df.rename(columns={"date": "calendar_date"})
    df.to_sql("dim_date", engine, if_exists="append", index=False)
    return df


def load_dim_targets_orders() -> pd.DataFrame:
    df = pd.read_csv(DATASET_DIR / "dim_targets_orders.csv", encoding="utf-8-sig")
    df = df.rename(
        columns={
            "ontime_target%": "ontime_target_pct",
            "infull_target%": "infull_target_pct",
            "otif_target%": "otif_target_pct",
        }
    )
    df.to_sql("dim_targets_orders", engine, if_exists="append", index=False)
    return df


def load_fact_order_lines() -> pd.DataFrame:
    df = pd.read_csv(DATASET_DIR / "fact_order_lines.csv", encoding="utf-8-sig")
    df = df.rename(
        columns={
            "In Full": "in_full",
            "On Time": "on_time",
            "On Time In Full": "on_time_in_full",
        }
    )
    for col in ["order_placement_date", "agreed_delivery_date", "actual_delivery_date"]:
        df[col] = pd.to_datetime(df[col], format="%A, %B %d, %Y")
    df.to_sql("fact_order_lines", engine, if_exists="append", index=False, chunksize=5000)
    return df


def load_fact_orders_aggregate() -> pd.DataFrame:
    df = pd.read_csv(DATASET_DIR / "fact_orders_aggregate.csv", encoding="utf-8-sig")
    df["order_placement_date"] = pd.to_datetime(df["order_placement_date"], format="%d-%b-%y")
    df.to_sql("fact_orders_aggregate", engine, if_exists="append", index=False, chunksize=5000)
    return df


def verify_row_counts(expected: dict[str, int]) -> None:
    with engine.connect() as conn:
        for table, expected_count in expected.items():
            actual = conn.exec_driver_sql(f"SELECT COUNT(*) FROM {table}").scalar()
            status = "OK" if actual == expected_count else "MISMATCH"
            print(f"  {table:<25} expected={expected_count:<7} actual={actual:<7} [{status}]")


def main() -> None:
    print("Loading dimension tables...")
    customers = load_dim_customers()
    products = load_dim_products()
    dates = load_dim_date()
    targets = load_dim_targets_orders()

    print("Loading fact tables...")
    lines = load_fact_order_lines()
    orders = load_fact_orders_aggregate()

    print("\nVerifying row counts (source CSV vs MySQL table):")
    verify_row_counts(
        {
            "dim_customers": len(customers),
            "dim_products": len(products),
            "dim_date": len(dates),
            "dim_targets_orders": len(targets),
            "fact_order_lines": len(lines),
            "fact_orders_aggregate": len(orders),
        }
    )
    print("\nETL complete.")


if __name__ == "__main__":
    main()
