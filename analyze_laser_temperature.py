from __future__ import annotations

import csv
from pathlib import Path
from statistics import mean
from typing import Iterable, List, Sequence

DATA_PATTERN = "platformtest_*C.csv"
LOW_LEVEL = 6
HIGH_LEVEL = 10
CHANNELS = ("laser0", "laser1", "laser2")


def find_data_files(pattern: str) -> List[Path]:
    paths = sorted(
        path
        for path in Path.cwd().glob(pattern)
        if not path.name.endswith(".bck")
    )
    if not paths:
        raise FileNotFoundError(f"No files matched pattern {pattern!r}")
    return paths


def read_rows(path: Path) -> List[dict]:
    with path.open(newline="") as handle:
        return list(csv.DictReader(handle))


def compute_channel_means(rows: Iterable[dict], level: float, channels: Sequence[str]) -> List[float]:
    values = []
    for row in rows:
        if float(row["test_level"]) == level:
            values.append([float(row[channel]) for channel in channels])
    if not values:
        raise ValueError(f"No rows found for level {level}.")
    column_totals = [0.0] * len(channels)
    for row_values in values:
        for idx, value in enumerate(row_values):
            column_totals[idx] += value
    return [total / len(values) for total in column_totals]


def compute_differences(rows: Iterable[dict], low_level: float, high_level: float, channels: Sequence[str]) -> List[float]:
    low_means = compute_channel_means(rows, low_level, channels)
    high_means = compute_channel_means(rows, high_level, channels)
    return [low - high for low, high in zip(low_means, high_means)]


def compute_temperature_mean(rows: Iterable[dict]) -> float:
    temps = [float(row["temperature"]) for row in rows]
    if not temps:
        raise ValueError("No temperature readings found.")
    return mean(temps)


def linear_fit(x_values: Sequence[float], y_values: Sequence[float]) -> tuple[float, float]:
    if len(x_values) != len(y_values):
        raise ValueError("x and y must have the same length")
    if len(x_values) < 2:
        raise ValueError("At least two points are required for a linear fit")
    x_mean = mean(x_values)
    y_mean = mean(y_values)
    numerator = sum((x - x_mean) * (y - y_mean) for x, y in zip(x_values, y_values))
    denominator = sum((x - x_mean) ** 2 for x in x_values)
    if denominator == 0:
        raise ValueError("Cannot compute slope because all x values are identical")
    slope = numerator / denominator
    intercept = y_mean - slope * x_mean
    return slope, intercept


def main() -> None:
    files = find_data_files(DATA_PATTERN)
    results = []
    for path in files:
        rows = read_rows(path)
        diffs = compute_differences(rows, LOW_LEVEL, HIGH_LEVEL, CHANNELS)
        temp_mean = compute_temperature_mean(rows)
        results.append({
            "filename": path.name,
            "temperature": temp_mean,
            "laser0_diff": diffs[0],
            "laser1_diff": diffs[1],
            "laser2_diff": diffs[2],
        })

    results.sort(key=lambda item: item["temperature"])

    header = ("filename", "temperature", "laser0_diff", "laser1_diff", "laser2_diff")
    print(", ".join(header))
    for row in results:
        print(", ".join(
            f"{row[key]:.9f}" if key != "filename" else row[key]
            for key in header
        ))

    print("\nLinear fits (difference = slope * temperature + intercept):")
    for channel in CHANNELS:
        column = f"{channel}_diff"
        slope, intercept = linear_fit(
            [row["temperature"] for row in results],
            [row[column] for row in results],
        )
        print(f"  {column}: slope = {slope:.9f} mm/°C, intercept = {intercept:.9f} mm")


if __name__ == "__main__":
    main()
