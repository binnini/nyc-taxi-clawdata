{{
    config(
        materialized='incremental',
        incremental_strategy='append',
        order_by=['pickup_at', 'pickup_location_id']
    )
}}

{% set current_year = var('year', 2019) %}

SELECT
    "VendorID"                                        AS vendor_id,
    tpep_pickup_datetime                              AS pickup_at,
    tpep_dropoff_datetime                             AS dropoff_at,
    passenger_count::INTEGER                          AS passenger_count,
    trip_distance::DOUBLE                             AS trip_distance,
    "PULocationID"                                    AS pickup_location_id,
    "DOLocationID"                                    AS dropoff_location_id,
    fare_amount::DOUBLE                               AS fare_amount,
    tip_amount::DOUBLE                                AS tip_amount,
    total_amount::DOUBLE                              AS total_amount
FROM read_parquet([
    {% for month in range(1, 13) %}
    's3://s3-nyc-taxi/trip-data/yellow_tripdata_{{ current_year }}-{{ "%02d" % month }}.parquet'{{ "," if not loop.last }}
    {% endfor %}
], union_by_name=true)
WHERE
    tpep_pickup_datetime IS NOT NULL
    AND tpep_dropoff_datetime IS NOT NULL
    AND tpep_dropoff_datetime > tpep_pickup_datetime
    AND trip_distance > 0
    AND fare_amount >= 0
    AND passenger_count BETWEEN 1 AND 9
    AND EXTRACT(YEAR FROM tpep_pickup_datetime) = {{ current_year }}
