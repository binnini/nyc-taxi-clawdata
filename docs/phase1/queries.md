# Phase 1 벤치마크 쿼리 (Q1~Q5)

Mark Litwintschik 벤치마크 기준. 모든 쿼리는 `main_staging.stg_trips` 대상.

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
FROM main_staging.stg_trips
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
FROM main_staging.stg_trips
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
FROM main_staging.stg_trips
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
FROM main_staging.stg_trips
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
FROM main_staging.stg_trips t
JOIN main_staging.stg_locations l
  ON t.pickup_location_id = l.location_id
GROUP BY l.borough, l.zone
ORDER BY trip_count DESC
LIMIT 20;
```

---

## 물리적 정렬 전략 (Zone Map)

`stg_trips`는 `pickup_at, pickup_location_id` 순으로 정렬되어 적재된다.
DuckDB는 row group별 **Zone Map(min/max 인덱스)**을 유지하며, 정렬 기준 컬럼으로 필터링 시 조건 범위 밖의 블록을 통째로 스킵한다.

| 컬럼 | 정렬 기준 포함 | Zone Map 효과 |
|------|-------------|--------------|
| `pickup_at` | ✅ | 시간 범위 필터 시 블록 스킵 |
| `pickup_location_id` | ✅ | 존 필터 시 블록 스킵 |
| `passenger_count` | ❌ | 전체 스캔 불가피 → Q2/Q3 SLA 초과 원인 |

### EXPLAIN ANALYZE — Zone Map 효과 확인

**Zone Map이 작동하는 쿼리** (pickup_at 범위 필터):

```sql
EXPLAIN ANALYZE
SELECT COUNT(*)
FROM main_staging.stg_trips
WHERE pickup_at BETWEEN '2022-01-01' AND '2022-12-31';
```

**Zone Map이 작동하지 않는 쿼리** (passenger_count 필터):

```sql
EXPLAIN ANALYZE
SELECT COUNT(*)
FROM main_staging.stg_trips
WHERE passenger_count = 1;
```

> 두 쿼리의 플랜에서 `Rows Scanned` 차이를 비교하여 Zone Map 효과를 확인한다.
> 결과는 `phase1/findings.md`에 기록한다.

---

## 실행 결과 기록

> 실행 후 `phase1/findings.md`에 아래 항목을 기록한다.

| 쿼리 | 실행 시간 | SLA 목표 | SLA 달성 | 비고 |
|------|----------|---------|---------|------|
| Q1   | 0.447s   | 2초     | ✅      |      |
| Q2   | 4.188s   | 2초     | ❌      | passenger_count 풀스캔, Zone Map 미적용 |
| Q3   | 8.329s   | 2초     | ❌      | 동상, Out-of-Core 스필 추정 |
| Q4   | 3.734s   | 5초     | ✅      |      |
| Q5   | 3.227s   | 5초     | ✅      |      |
