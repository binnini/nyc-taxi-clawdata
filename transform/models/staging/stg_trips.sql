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
FROM read_parquet([
    'https://d37ci6vzurychx.cloudfront.net/trip-data/yellow_tripdata_2019-01.parquet',
    'https://d37ci6vzurychx.cloudfront.net/trip-data/yellow_tripdata_2019-02.parquet',
    'https://d37ci6vzurychx.cloudfront.net/trip-data/yellow_tripdata_2019-03.parquet',
    'https://d37ci6vzurychx.cloudfront.net/trip-data/yellow_tripdata_2019-04.parquet',
    'https://d37ci6vzurychx.cloudfront.net/trip-data/yellow_tripdata_2019-05.parquet',
    'https://d37ci6vzurychx.cloudfront.net/trip-data/yellow_tripdata_2019-06.parquet',
    'https://d37ci6vzurychx.cloudfront.net/trip-data/yellow_tripdata_2019-07.parquet',
    'https://d37ci6vzurychx.cloudfront.net/trip-data/yellow_tripdata_2019-08.parquet',
    'https://d37ci6vzurychx.cloudfront.net/trip-data/yellow_tripdata_2019-09.parquet',
    'https://d37ci6vzurychx.cloudfront.net/trip-data/yellow_tripdata_2019-10.parquet',
    'https://d37ci6vzurychx.cloudfront.net/trip-data/yellow_tripdata_2019-11.parquet',
    'https://d37ci6vzurychx.cloudfront.net/trip-data/yellow_tripdata_2019-12.parquet',
    'https://d37ci6vzurychx.cloudfront.net/trip-data/yellow_tripdata_2020-01.parquet',
    'https://d37ci6vzurychx.cloudfront.net/trip-data/yellow_tripdata_2020-02.parquet',
    'https://d37ci6vzurychx.cloudfront.net/trip-data/yellow_tripdata_2020-03.parquet',
    'https://d37ci6vzurychx.cloudfront.net/trip-data/yellow_tripdata_2020-04.parquet',
    'https://d37ci6vzurychx.cloudfront.net/trip-data/yellow_tripdata_2020-05.parquet',
    'https://d37ci6vzurychx.cloudfront.net/trip-data/yellow_tripdata_2020-06.parquet',
    'https://d37ci6vzurychx.cloudfront.net/trip-data/yellow_tripdata_2020-07.parquet',
    'https://d37ci6vzurychx.cloudfront.net/trip-data/yellow_tripdata_2020-08.parquet',
    'https://d37ci6vzurychx.cloudfront.net/trip-data/yellow_tripdata_2020-09.parquet',
    'https://d37ci6vzurychx.cloudfront.net/trip-data/yellow_tripdata_2020-10.parquet',
    'https://d37ci6vzurychx.cloudfront.net/trip-data/yellow_tripdata_2020-11.parquet',
    'https://d37ci6vzurychx.cloudfront.net/trip-data/yellow_tripdata_2020-12.parquet',
    'https://d37ci6vzurychx.cloudfront.net/trip-data/yellow_tripdata_2021-01.parquet',
    'https://d37ci6vzurychx.cloudfront.net/trip-data/yellow_tripdata_2021-02.parquet',
    'https://d37ci6vzurychx.cloudfront.net/trip-data/yellow_tripdata_2021-03.parquet',
    'https://d37ci6vzurychx.cloudfront.net/trip-data/yellow_tripdata_2021-04.parquet',
    'https://d37ci6vzurychx.cloudfront.net/trip-data/yellow_tripdata_2021-05.parquet',
    'https://d37ci6vzurychx.cloudfront.net/trip-data/yellow_tripdata_2021-06.parquet',
    'https://d37ci6vzurychx.cloudfront.net/trip-data/yellow_tripdata_2021-07.parquet',
    'https://d37ci6vzurychx.cloudfront.net/trip-data/yellow_tripdata_2021-08.parquet',
    'https://d37ci6vzurychx.cloudfront.net/trip-data/yellow_tripdata_2021-09.parquet',
    'https://d37ci6vzurychx.cloudfront.net/trip-data/yellow_tripdata_2021-10.parquet',
    'https://d37ci6vzurychx.cloudfront.net/trip-data/yellow_tripdata_2021-11.parquet',
    'https://d37ci6vzurychx.cloudfront.net/trip-data/yellow_tripdata_2021-12.parquet',
    'https://d37ci6vzurychx.cloudfront.net/trip-data/yellow_tripdata_2022-01.parquet',
    'https://d37ci6vzurychx.cloudfront.net/trip-data/yellow_tripdata_2022-02.parquet',
    'https://d37ci6vzurychx.cloudfront.net/trip-data/yellow_tripdata_2022-03.parquet',
    'https://d37ci6vzurychx.cloudfront.net/trip-data/yellow_tripdata_2022-04.parquet',
    'https://d37ci6vzurychx.cloudfront.net/trip-data/yellow_tripdata_2022-05.parquet',
    'https://d37ci6vzurychx.cloudfront.net/trip-data/yellow_tripdata_2022-06.parquet',
    'https://d37ci6vzurychx.cloudfront.net/trip-data/yellow_tripdata_2022-07.parquet',
    'https://d37ci6vzurychx.cloudfront.net/trip-data/yellow_tripdata_2022-08.parquet',
    'https://d37ci6vzurychx.cloudfront.net/trip-data/yellow_tripdata_2022-09.parquet',
    'https://d37ci6vzurychx.cloudfront.net/trip-data/yellow_tripdata_2022-10.parquet',
    'https://d37ci6vzurychx.cloudfront.net/trip-data/yellow_tripdata_2022-11.parquet',
    'https://d37ci6vzurychx.cloudfront.net/trip-data/yellow_tripdata_2022-12.parquet',
    'https://d37ci6vzurychx.cloudfront.net/trip-data/yellow_tripdata_2023-01.parquet',
    'https://d37ci6vzurychx.cloudfront.net/trip-data/yellow_tripdata_2023-02.parquet',
    'https://d37ci6vzurychx.cloudfront.net/trip-data/yellow_tripdata_2023-03.parquet',
    'https://d37ci6vzurychx.cloudfront.net/trip-data/yellow_tripdata_2023-04.parquet',
    'https://d37ci6vzurychx.cloudfront.net/trip-data/yellow_tripdata_2023-05.parquet',
    'https://d37ci6vzurychx.cloudfront.net/trip-data/yellow_tripdata_2023-06.parquet',
    'https://d37ci6vzurychx.cloudfront.net/trip-data/yellow_tripdata_2023-07.parquet',
    'https://d37ci6vzurychx.cloudfront.net/trip-data/yellow_tripdata_2023-08.parquet',
    'https://d37ci6vzurychx.cloudfront.net/trip-data/yellow_tripdata_2023-09.parquet',
    'https://d37ci6vzurychx.cloudfront.net/trip-data/yellow_tripdata_2023-10.parquet',
    'https://d37ci6vzurychx.cloudfront.net/trip-data/yellow_tripdata_2023-11.parquet',
    'https://d37ci6vzurychx.cloudfront.net/trip-data/yellow_tripdata_2023-12.parquet'
], union_by_name=true)
WHERE
    tpep_pickup_datetime IS NOT NULL
    AND tpep_dropoff_datetime IS NOT NULL
    AND tpep_dropoff_datetime > tpep_pickup_datetime
    AND trip_distance > 0
    AND fare_amount >= 0
    AND passenger_count BETWEEN 1 AND 9
    AND EXTRACT(YEAR FROM tpep_pickup_datetime) BETWEEN 2019 AND 2023
