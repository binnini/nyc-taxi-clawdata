{{
    config(materialized='table')
}}

SELECT
    LocationID    AS location_id,
    Borough       AS borough,
    Zone          AS zone_name,
    service_zone
FROM read_csv_auto(
    'https://d37ci6vzurychx.cloudfront.net/misc/taxi_zone_lookup.csv',
    header=true
)
WHERE LocationID IS NOT NULL
