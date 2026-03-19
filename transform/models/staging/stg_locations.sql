{{
    config(materialized='table')
}}

SELECT
    LocationID    AS location_id,
    Borough       AS borough,
    Zone          AS zone_name,
    service_zone
FROM read_csv_auto(
    's3://nyc-tlc/misc/taxi_zone_lookup.csv',
    header=true
)
WHERE LocationID IS NOT NULL
