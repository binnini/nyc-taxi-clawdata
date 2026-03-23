-- NYC Taxi 벤치마크 쿼리 Q1~Q5
-- 실행: duckdb /workspace/nyc-taxi/warehouse.duckdb < docs/phase1/queries.sql

.timer on

-- ============================================================
-- Q1: vendor_id별 COUNT | SLA: 2초
-- ============================================================
SELECT
    vendor_id,
    COUNT(*) AS trip_count
FROM staging.stg_trips
GROUP BY vendor_id
ORDER BY vendor_id;

-- ============================================================
-- Q2: passenger_count별 AVG(total_amount) | SLA: 2초
-- ============================================================
SELECT
    passenger_count,
    AVG(total_amount) AS avg_total_amount
FROM staging.stg_trips
GROUP BY passenger_count
ORDER BY passenger_count;

-- ============================================================
-- Q3: passenger_count + 연도별 COUNT | SLA: 2초
-- ============================================================
SELECT
    passenger_count,
    EXTRACT(YEAR FROM pickup_at) AS year,
    COUNT(*) AS trip_count
FROM staging.stg_trips
GROUP BY passenger_count, year
ORDER BY passenger_count, year;

-- ============================================================
-- Q4: passenger_count + 연도 + 거리(반올림) 3중 GROUP BY | SLA: 5초
-- ============================================================
SELECT
    passenger_count,
    EXTRACT(YEAR FROM pickup_at)  AS year,
    ROUND(trip_distance)          AS distance_bucket,
    COUNT(*)                      AS trip_count
FROM staging.stg_trips
GROUP BY passenger_count, year, distance_bucket
ORDER BY year, trip_count DESC;

-- ============================================================
-- Q5: pickup_zone JOIN + COUNT | SLA: 5초
-- ============================================================
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
