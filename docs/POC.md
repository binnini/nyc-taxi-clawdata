# POC: NYC Taxi Data Engineering on DuckDB

## 1. 목적

NYC Taxi 공개 데이터셋을 활용하여 DuckDB 기반 OLAP 환경을 구축하고,
ClawData 에이전트를 통한 데이터 분석 워크플로우를 검증한다.

비즈니스 로직보다 **기술적 구현과 설계 결정의 근거**를 문서화하는 것이 주목적이다.

---

## 2. 데이터셋

### 소스
- **NYC TLC 공식 배포 (CloudFront)**
- URL: `https://d37ci6vzurychx.cloudfront.net/trip-data/`
- 포맷: Parquet

> **접근 제한 이슈 (확인됨)**
> AWS RODA `s3://nyc-tlc/` 버킷은 현재 외부 익명/인증 접근 모두 차단 상태 (`AccessDenied`).
> CloudFront URL은 서울 리전 EC2 IP에서 403 Geo-block 발생.
> **우회 방안**: AWS CloudShell(Seoul)에서 CloudFront 접근 가능 → 사용자 S3 버킷 경유 → EC2 적재 (상세: 아키텍처 섹션 참조)

### 범위
- 대상: Yellow Taxi Trip Records
- 기간: 2019년 1월 ~ 2023년 12월 (5년치)
- 예상 규모: 약 2억 건 / 약 25GB (Parquet 압축 기준)
- 선정 이유: c7i-flex.large (4GB RAM) 메모리 제약 챌린지 유효화, COVID-19(2020~2021) 기간 데이터 패턴 변화 포함
- 인스턴스 선정 이유: t3.medium 동일 RAM(4GB), Intel Sapphire Rapids 아키텍처로 컴퓨팅 성능 우수, 네트워크 최대 12.5Gbps

### 주요 컬럼
| 컬럼 | 설명 |
|------|------|
| tpep_pickup_datetime | 승차 시각 |
| tpep_dropoff_datetime | 하차 시각 |
| passenger_count | 탑승 인원 |
| trip_distance | 운행 거리 (마일) |
| PULocationID | 승차 존 ID |
| DOLocationID | 하차 존 ID |
| fare_amount | 요금 |
| tip_amount | 팁 |
| total_amount | 총 결제 금액 |

### 보조 데이터
- Taxi Zone Lookup: `https://d37ci6vzurychx.cloudfront.net/misc/taxi_zone_lookup.csv`
  - LocationID, Borough, Zone, service_zone 포함
  - CloudFront에서 직접 접근 가능 (EC2 IP 차단 없음 — 소용량 파일)

---

## 3. 기술 스택

| 구성 요소 | 선택 | 근거 |
|----------|------|------|
| 인프라 | AWS EC2 c7i-flex.large | 리소스 제약 챌린지, t3.medium 동일 RAM(4GB) |
| 스토리지 | AWS EBS | EC2 stop 시 데이터 유지 |
| 원본 데이터 | CloudFront + 사용자 S3(임시) | S3 RODA 접근 차단으로 CloudShell 우회 경유 |
| 쿼리 엔진 | DuckDB | 컬럼형 OLAP, HTTPS 직접 쿼리, 설정 zero |
| 변환 도구 | dbt-duckdb | SQL 모듈화, 테스트, 문서화 |
| 분석 도구 | ClawData Agent | 자연어 기반 쿼리, 인라인 시각화 |

---

## 4. 아키텍처

### Phase 1: Staging only

```
CloudFront (NYC Taxi Parquet)
        ↓ AWS CloudShell (Seoul) — EC2 IP 차단 우회
    사용자 S3 버킷 (ap-northeast-2, 임시)
        ↓ dbt run (최초 1회, table materialization)
    stg_trips        정제된 원본 데이터 (EBS에 적재)
    stg_locations    존 메타데이터 (EBS에 적재, CloudFront 직접 접근)
        ↓
    warehouse.duckdb (EBS)
        ↓
    [사용자 S3 버킷 삭제]
        ↓
    ClawData Agent   Staging 직접 쿼리 + 시각화
```

> **데이터 수집 1회성 절차** (반복 불필요)
> 1. CloudShell에서 parquet 60개를 사용자 S3 버킷으로 다운로드
> 2. EC2에서 `dbt run` 실행 → warehouse.duckdb (EBS) 적재
> 3. 사용자 S3 버킷 삭제 (EBS에 데이터 영속)

**Materialization 결정: `table` (S3 Direct Query 배제)**

c7i-flex.large 네트워크 대역폭(최대 5Gbps)과 S3 API 지연을 고려할 때,
S3 Direct Query(httpfs) 방식으로는 Q1~Q3 2초 SLA 달성이 불가능에 가깝다.
Parquet Projection/Filter Pushdown이 작동하더라도 I/O 병목이 발생한다.
따라서 dbt run 시 EBS로 전량 적재(table)하는 것을 기본 전제로 한다.

| 방식 | SLA 달성 가능성 | 선택 |
|------|---------------|------|
| S3 Direct Query (view) | 낮음 (네트워크 I/O 병목) | ❌ |
| EBS 적재 (table) | 높음 | ✅ |

**물리적 정렬(Ordering) 전략**

DuckDB는 Zone Map(Min/Max 인덱스)을 활용한 블록 스킵을 지원한다.
쿼리 조건으로 자주 사용되는 컬럼을 기준으로 정렬하여 적재하면 필터링 효율이 극대화된다.

```sql
-- stg_trips 적재 시 정렬 기준
ORDER BY tpep_pickup_datetime, PULocationID
```

> 정렬 전/후 쿼리 플랜(`EXPLAIN ANALYZE`) 비교를 phase1/queries.md에 기록한다.

### Phase 2: Mart 추가

```
stg_trips + stg_locations
        ↓ dbt run
    mart_trips       파생 컬럼 포함, 존 denormalize
        ↓
    ClawData Agent   Mart 우선 → 부족하면 Staging
```

---

## 5. 제약 조건 (챌린지)

| 제약 | 내용 | 목적 |
|------|------|------|
| 인스턴스 | c7i-flex.large (2 vCPU, 4GB RAM, 최대 12.5Gbps) | Out-of-Core 처리 강제 |
| 단순 집계 쿼리 SLA | 2초 이내 (Q1~Q3) | 쿼리 플랜 최적화 유도 |
| 복합 쿼리 SLA | 5초 이내 (Q4~Q5) | 파티셔닝/정렬 전략 유도 |
| Staging 재처리 금지 | dbt run은 최초 1회 원칙 | Incremental 전략 유도 |

### DuckDB 엔진 초기화 설정 (필수)

25GB 데이터를 4GB RAM에서 처리하므로 Out-of-Core 처리가 반드시 트리거된다.
설정 누락 시 dbt run 중 OOM 킬러에 의해 프로세스가 종료될 위험이 있다.

```sql
SET memory_limit = '3GB';           -- RAM 4GB 중 OS 여유분 확보
SET temp_directory = '/tmp/duckdb'; -- 스필(Spill) 디렉토리 명시
SET threads = 2;                    -- c7i-flex.large vCPU 수에 맞춤
```

> SAD에서 설정값 근거를 상세히 기술한다.

---

## 6. 데이터 품질 체크

Staging 모델 적재 전 원본 데이터의 품질을 검증한다.
dbt test 또는 DuckDB 직접 쿼리로 수행하며 결과를 `phase1/findings.md`에 기록한다.

### NULL 체크
| 컬럼 | 허용 여부 |
|------|----------|
| tpep_pickup_datetime | 불가 |
| tpep_dropoff_datetime | 불가 |
| PULocationID | 불가 |
| DOLocationID | 불가 |
| passenger_count | 허용 (NULL → 제외 처리) |
| trip_distance | 불가 |

### 범위 이상 체크
| 항목 | 조건 | 처리 |
|------|------|------|
| 음수 요금 | `fare_amount < 0` | 제외 |
| 음수 거리 | `trip_distance < 0` | 제외 |
| 음수 팁 | `tip_amount < 0` | 제외 |
| 승객 수 0 | `passenger_count = 0` | 제외 |
| 승객 수 초과 | `passenger_count > 9` | 제외 |
| 거리 0 | `trip_distance = 0` | 제외 |

### 논리 이상 체크
| 항목 | 조건 | 처리 |
|------|------|------|
| 시간 역전 | `dropoff_datetime < pickup_datetime` | 제외 |
| 날짜 범위 이탈 | 분석 기간(2023년) 외 데이터 | 제외 |
| 요금 불일치 | `fare_amount + extra + tip_amount + tolls_amount ≠ total_amount` | 기록만 |
| 존 ID 불일치 | `PULocationID` 또는 `DOLocationID`가 taxi_zones에 없는 값 | 기록만 |

### 중복 체크
```sql
-- 동일한 (pickup_time, dropoff_time, PULocationID, passenger_count, trip_distance) 조합
SELECT COUNT(*) - COUNT(DISTINCT ...) AS duplicate_count FROM stg_trips;
```

### DQ 체크 실행 전략

2억 건 전체에 대해 모든 DQ 테스트를 수행하면 상당한 리소스와 시간이 소모된다.
다음 전략으로 범위를 제한한다:

| 단계 | 대상 | 방법 |
|------|------|------|
| 초기 탐색 | 월별 샘플 1개 (예: 2023-01) | DuckDB 직접 쿼리 |
| 연도별 검증 | 연도별 첫 달 파티션 | dbt source freshness + 샘플링 |
| 전체 검증 | 전체 데이터 | dbt run 완료 후 1회만 수행 |

```sql
-- 샘플 파티션 DQ 체크 예시 (적재 후 EBS에서 실행)
SELECT * FROM stg_trips
WHERE fare_amount < 0 OR passenger_count = 0 OR trip_distance <= 0
LIMIT 1000;
```

---

## 7. 검증 질문 (Phase 1)

에이전트에게 던져볼 핵심 질문 목록. Staging만으로 답할 수 있는지 검증한다.
Mark Litwintschik 벤치마크(Q1~Q4)를 기본 SLA 측정 기준으로 채택한다.

### 벤치마크 쿼리 (SLA 측정 기준)
Mark Litwintschik의 표준 4개 쿼리 — 30개 이상 DBMS가 동일하게 사용하는 쿼리셋.

| 쿼리 | 내용 | SLA 목표 |
|------|------|----------|
| Q1 | cab_type별 COUNT | 2초 이내 |
| Q2 | passenger_count별 AVG(total_amount) | 2초 이내 |
| Q3 | passenger_count + 연도별 COUNT | 2초 이내 |
| Q4 | passenger_count + 연도 + ROUND(distance) 3중 GROUP BY + ORDER BY | 5초 이내 |
| Q5 | pickup_zone JOIN + COUNT (존 분석) | 5초 이내 |

### 패턴 분석
- 시간대별 운행 패턴은?
- 요일별 운행 패턴은?
- 가장 많이 이용되는 승차/하차 존은?

### 복합 질문 (에이전트 한계 탐색)
- 픽업 존별, 시간대별 평균 운행 시간은?
- 운행 거리 대비 요금 이상 건수는?

---

## 8. 측정 항목

Phase 1과 Phase 2를 비교하기 위해 기록한다.

| 항목 | 측정 방법 |
|------|----------|
| 쿼리 응답 시간 | DuckDB `EXPLAIN ANALYZE` |
| 에이전트 SQL 정확도 | 질문 대비 정답 여부 수동 검토 |
| Mart로 해결 못한 질문 비율 | Phase 2 findings.md에 기록 |
| warehouse.duckdb 파일 크기 | Phase 1 vs Phase 2 비교 |

---

## 9. 제외 범위

- 수익/비용 분석 (비즈니스 로직 배제)
- 실시간 스트리밍 파이프라인
- 외부 데이터 조인 (날씨, 이벤트 등) — Phase 3 이후 고려
- 다중 사용자 동시 접속

---

## 10. 다음 단계

- [x] SAD 작성 (아키텍처 결정 근거 상세화)
- [x] EC2 인스턴스 설정 (c7i-flex.large, Tailscale, OpenClaw Gateway)
- [x] dbt 프로젝트 초기화
- [x] Staging 모델 작성 (stg_trips, stg_locations)
- [ ] S3 버킷 생성 및 CloudShell로 parquet 60개 업로드
- [ ] EC2 S3 접근 설정 (AWS credentials)
- [ ] dbt run 실행 → warehouse.duckdb 적재
- [ ] S3 버킷 삭제
- [ ] ClawData Agent 연동 검증 (벤치마크 쿼리 Q1~Q5)
