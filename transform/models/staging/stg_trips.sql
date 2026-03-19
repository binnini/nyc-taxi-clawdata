{{
    config(
        materialized='table',
        order_by=['pickup_at', 'pickup_location_id']
    )
}}

SELECT
    vendor_id,
    tpep_pickup_datetime                              AS pickup_at,
    tpep_dropoff_datetime                             AS dropoff_at,
    passenger_count::INTEGER                          AS passenger_count,
    trip_distance::DOUBLE                             AS trip_distance,
    "PULocationID"                                    AS pickup_location_id,
    "DOLocationID"                                    AS dropoff_location_id,
    fare_amount::DOUBLE                               AS fare_amount,
    tip_amount::DOUBLE                                AS tip_amount,
    total_amount::DOUBLE                              AS total_amount
FROM read_parquet(
    's3://nyc-tlc/trip data/yellow_tripdata_201[9-9]*.parquet',
    's3://nyc-tlc/trip data/yellow_tripdata_202[0-3]*.parquet'
)
WHERE
    tpep_pickup_datetime IS NOT NULL
    AND tpep_dropoff_datetime IS NOT NULL
    AND tpep_dropoff_datetime > tpep_pickup_datetime
    AND trip_distance > 0
    AND fare_amount >= 0
    AND passenger_count BETWEEN 1 AND 9
    AND EXTRACT(YEAR FROM tpep_pickup_datetime) BETWEEN 2019 AND 2023
