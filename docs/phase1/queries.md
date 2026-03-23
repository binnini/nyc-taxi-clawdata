# Phase 1 벤치마크 쿼리 (Q1~Q5)

Mark Litwintschik 벤치마크 기준. 모든 쿼리는 `staging.stg_trips` 대상.

**실행 방법**
```bash
duckdb /workspace/nyc-taxi/warehouse.duckdb < docs/phase1/queries.sql
```

또는 개별 실행:
```bash
duckdb /workspace/nyc-taxi/warehouse.duckdb -c ".timer on" -c "<쿼리>"
```

**DuckDB 동시성 주의사항**
에이전트 실행 중에는 Gateway가 `read_only=True`로 연결을 점유한다.
`dbt run`이 필요한 경우 Gateway 연결 해제 후 실행할 것.

---

## Q1 — vendor_id별 COUNT

**SLA 목표**: 2초 이내

```sql
SELECT
    vendor_id,
    COUNT(*) AS trip_count
FROM staging.stg_trips
GROUP BY vendor_id
ORDER BY vendor_id;
```

---

## Q2 — passenger_count별 AVG(total_amount)

**SLA 목표**: 2초 이내

```sql
SELECT
    passenger_count,
    AVG(total_amount) AS avg_total_amount
FROM staging.stg_trips
GROUP BY passenger_count
ORDER BY passenger_count;
```

---

## Q3 — passenger_count + 연도별 COUNT

**SLA 목표**: 2초 이내

```sql
SELECT
    passenger_count,
    EXTRACT(YEAR FROM pickup_at) AS year,
    COUNT(*) AS trip_count
FROM staging.stg_trips
GROUP BY passenger_count, year
ORDER BY passenger_count, year;
```

---

## Q4 — passenger_count + 연도 + 거리(반올림) 3중 GROUP BY

**SLA 목표**: 5초 이내

```sql
SELECT
    passenger_count,
    EXTRACT(YEAR FROM pickup_at)  AS year,
    ROUND(trip_distance)          AS distance_bucket,
    COUNT(*)                      AS trip_count
FROM staging.stg_trips
GROUP BY passenger_count, year, distance_bucket
ORDER BY year, trip_count DESC;
```

---

## Q5 — pickup_zone JOIN + COUNT (존 분석)

**SLA 목표**: 5초 이내

```sql
SELECT
    l.borough,
    l.zone,
    COUNT(*) AS trip_count
FROM staging.stg_trips t
JOIN staging.stg_locations l
  ON t.pickup_location_id = l.location_id
GROUP BY l.borough, l.zone
ORDER BY trip_count DESC
LIMIT 20;
```

---

## 실행 결과 기록

> 실행 후 `phase1/findings.md`에 아래 항목을 기록한다.

| 쿼리 | 실행 시간 | SLA 달성 | 비고 |
|------|----------|---------|------|
| Q1   |          |         |      |
| Q2   |          |         |      |
| Q3   |          |         |      |
| Q4   |          |         |      |
| Q5   |          |         |      |
