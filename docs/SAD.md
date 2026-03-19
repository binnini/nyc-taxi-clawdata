# SAD: NYC Taxi Data Engineering on DuckDB

## 1. 문서 목적

이 문서는 NYC Taxi POC의 아키텍처 결정 사항과 그 근거를 기술한다.
각 결정은 대안과의 비교를 포함하며, 향후 Phase 확장 시 의사결정 참고 자료로 활용한다.

---

## 2. 시스템 개요

```
┌─────────────────────────────────────────────────────────────┐
│                        AWS Cloud                            │
│                                                             │
│  사용자 S3(임시)          EC2 c7i-flex.large                       │
│  ┌──────────┐           ┌───────────────────────────────┐   │
│  │ NYC Taxi │─(1)──────▶│ dbt (최초 1회 적재)            │   │
│  │ Parquet  │           │                               │   │
│  │ 2019-23  │           │  warehouse.duckdb (EBS)       │   │
│  └──────────┘           │  ├── stg_trips                │   │
│  (적재 후 삭제)           │  ├── stg_locations            │   │
│                         │  └── (Phase 2) mart_trips     │   │
│                         │                               │   │
│                         │ OpenClaw Gateway              │   │
│                         │  └── Agent 실행 환경 (CLI)    │   │
│                         └───────────────┬───────────────┘   │
└─────────────────────────────────────────┼───────────────────┘
                                          │ WebSocket
                    ┌─────────────────────▼─────────────────┐
                    │          로컬 Mac (Docker)             │
                    │                                       │
                    │  ClawData                             │
                    │  ├── FastAPI (API)                    │
                    │  ├── Next.js (Chat UI)                │
                    │  └── Agent                            │
                    │      ├── [CLI] → EC2 Gateway          │
                    │      │   └── duckdb, dbt, s3 CLI      │
                    │      └── [API] → 클라우드 서비스 직접  │
                    │          ├── Snowflake                │
                    │          ├── BigQuery                 │
                    │          ├── GitHub                   │
                    │          └── Fivetran ...             │
                    └───────────────────────────────────────┘
```

**(1) dbt run 시 1회 적재. 이후 쿼리는 EBS 로컬 I/O로 처리.**

---

## 3. 아키텍처 결정 기록 (ADR)

### ADR-01: 쿼리 엔진 — DuckDB 선택

**결정**: DuckDB

**대안 검토**
| 대안 | 배제 이유 |
|------|----------|
| Amazon Athena | 쿼리 플랜 직접 관찰 불가, 콜드 스타트 지연, SLA 달성 불확실 |
| Amazon Redshift Serverless | 비용 예측 어려움, POC 규모 대비 과도한 복잡도 |
| PostgreSQL | 행 기반 엔진으로 OLAP 집계 성능 부적합 |

**선택 근거**
- 컬럼형 벡터화 엔진으로 OLAP 집계에 최적화
- Parquet 직접 읽기 (httpfs 확장) — ETL 불필요
- Zone Map(Min/Max 인덱스) 기반 블록 스킵으로 풀스캔 회피
- 단일 프로세스 임베디드 DB — 설정 overhead 없음
- dbt-duckdb 어댑터 공식 지원

---

### ADR-02: ClawData 배포 위치 — 로컬 + EC2 Gateway 분리

**결정**: ClawData(UI/API)는 로컬, OpenClaw Gateway는 EC2

**배경**
DuckDB는 파일 기반 임베디드 DB로 원격 접속 프로토콜이 없다.
에이전트가 DuckDB에 접근하려면 같은 머신에서 CLI를 직접 실행해야 한다.

**역할 분리**
| 컴포넌트 | 위치 | 이유 |
|---------|------|------|
| Next.js (Chat UI) | 로컬 Docker | 브라우저 접근 편의 |
| FastAPI (API) | 로컬 Docker | UI와 동일 네트워크 |
| OpenClaw Gateway | EC2 | DuckDB 파일 직접 접근, CLI 실행 환경 |
| DuckDB + dbt | EC2 | 데이터 처리 |

**스킬 실행 방식**
| 스킬 유형 | 실행 위치 | 예시 |
|----------|----------|------|
| CLI/파일 기반 | EC2 Gateway | duckdb, dbt, spark, s3 CLI |
| API 기반 | 인터넷 직접 연결 | Snowflake, BigQuery, GitHub, Fivetran |

API 기반 스킬은 Gateway 위치와 무관하게 동작한다.
따라서 이 구조에서 ClawData의 모든 스킬을 그대로 활용할 수 있다.

**확장성**
```
로컬 ClawData
├── Agent A → EC2 Gateway → DuckDB (NYC Taxi)
├── Agent B → EC2 Gateway → dbt (다른 프로젝트)
└── Agent C → Snowflake API (직접 연결)
```
여러 데이터 파이프라인을 로컬 ClawData 하나에서 관리 가능하다.

**연결 방식: Tailscale (Mesh VPN)**

SSH 터널링은 세션 타임아웃 및 네트워크 변동 시 연결이 끊어지고 데몬화 관리가 까다롭다.
Tailscale을 EC2와 로컬에 설치하면 퍼블릭 포트 개방 없이 `100.x.x.x` 사설 IP로
안전하고 영구적인 L3 터널이 확보된다. Docker 샌드박스 네트워크 사상과도 일치한다.

```
로컬 Mac (Tailscale 100.x.x.1)
    ↓ Tailscale VPN (암호화, 퍼블릭 포트 불필요)
EC2 (Tailscale 100.x.x.2)
    └── OpenClaw Gateway :18789
```

EC2 Security Group 인바운드 룰: SSH(22)만 허용. 18789 포트 퍼블릭 개방 불필요.

**DuckDB 동시성 통제 (File Lock 리스크)**

DuckDB는 Single-writer / Multiple-reader 모델이다.
Gateway가 `warehouse.duckdb`를 점유한 상태에서 `dbt run`이 Write를 시도하면
`IO Error: Could not set lock on file` 에러가 발생한다.

**통제 규칙**: 에이전트의 DuckDB 연결은 반드시 `read_only=True`로 강제한다.

```python
# OpenClaw Gateway DuckDB 스킬 설정
duckdb.connect('warehouse.duckdb', read_only=True)
```

`dbt run`은 에이전트와 독립적으로 수동 실행하며, 실행 전 Gateway의 DuckDB
연결이 없는 상태임을 확인한다. 이 규칙을 `phase1/queries.md`에 운영 절차로 명시한다.

---

### ADR-03: 인프라 — EC2 c7i-flex.large 선택

**결정**: EC2 c7i-flex.large (2 vCPU, 4GB RAM, 최대 12.5Gbps)

**대안 검토**
| 대안 | 배제 이유 |
|------|----------|
| t3.medium | AWS 계정 플랜 제한으로 사용 불가 |
| m7i-flex.large (8GB) | 메모리 제약 챌린지 무효화 |
| t3.small (2GB) | Out-of-Core 스필 과다로 SLA 달성 불가 |
| 로컬 머신 | 25GB 데이터 로컬 저장 부담, 재현 환경 불일치 |

**선택 근거**
- t3.medium과 동일한 RAM(4GB) → 원래 챌린지 조건 유지
- Intel Sapphire Rapids 아키텍처 → t3.medium 대비 컴퓨팅 성능 우수
- 네트워크 최대 12.5Gbps → S3 적재 속도 유리 (t3.medium 5Gbps 대비 2.5배)
- 비용 최소화 (미사용 시 stop으로 과금 중단, ~$0.068/h)

**리스크**
- dbt run 중 OOM 위험 → ADR-06에서 완화

---

### ADR-04: 루트 볼륨 크기 — 60GB 설정

**결정**: EC2 생성 시 루트 볼륨 크기를 60GB로 설정

**배경**
EC2에는 EBS 루트 볼륨이 기본 포함된다. 기본값은 8GB로 데이터 저장에 부족하다.

**용량 산정**
| 항목 | 예상 크기 |
|------|----------|
| OS + 기타 | ~5GB |
| stg_trips (Phase 1) | ~20GB |
| mart_trips (Phase 2) | ~10GB |
| DuckDB 스필 임시 파일 | ~10GB |
| 여유 | ~15GB |
| **합계** | **~60GB** |

> SLA 미달 시 IOPS/처리량 증설 전에 쿼리 플랜 최적화를 먼저 시도한다.

---

### ADR-05: dbt Materialization — table 선택

**결정**: `table` materialization

**대안 검토**
| 대안 | 배제 이유 |
|------|----------|
| view | 매 쿼리마다 S3 httpfs 읽기 → SLA 달성 불가 |
| incremental | 초기 전량 적재 이후 유효, Phase 1에서는 불필요 |
| ephemeral | 중간 변환용, 최종 모델에 부적합 |

**선택 근거**
- c7i-flex.large 네트워크 대역폭(최대 12.5Gbps)이지만 S3 API 지연은 여전히 존재
- EBS 적재 후 쿼리는 로컬 I/O로 처리 → SLA 달성 가능
- dbt run은 최초 1회 원칙 (Staging 재처리 금지 제약)

**적재 시 물리적 정렬 전략**
```sql
-- stg_trips 모델 마지막에 명시
ORDER BY tpep_pickup_datetime, PULocationID
```
- `tpep_pickup_datetime`: 시계열 필터 쿼리의 Zone Map 효율 극대화
- `PULocationID`: 존 기반 GROUP BY/JOIN 성능 향상

---

### ADR-06: DuckDB 엔진 초기화 설정

**결정**: profiles.yml에 초기화 pragma 명시

**배경**
25GB 데이터를 4GB RAM에서 처리 시 Out-of-Core 처리가 반드시 발생한다.
설정 누락 시 dbt run 중 OOM 킬러에 의해 프로세스가 강제 종료될 위험이 있다.

**설정값**
```yaml
# transform/profiles.yml
nyc_taxi:
  target: dev
  outputs:
    dev:
      type: duckdb
      path: /workspace/nyc-taxi/warehouse.duckdb
      settings:
        memory_limit: '3GB'
        temp_directory: '/tmp/duckdb_spill'
        threads: 2
        s3_region: 'us-east-1'
        s3_endpoint: 's3.amazonaws.com'
```

**설정 근거**
| 설정 | 값 | 근거 |
|------|-----|------|
| memory_limit | 3GB | RAM 4GB 중 OS + dbt 프로세스 여유분 1GB 확보 |
| temp_directory | /tmp/duckdb_spill | 스필 파일 분리로 warehouse.duckdb I/O 경합 최소화 |
| threads | 2 | c7i-flex.large vCPU 수와 일치, 컨텍스트 스위칭 overhead 방지 |
| s3_region | ap-northeast-2 | 사용자 S3 버킷(Seoul) 리전 고정 |
| s3_endpoint | s3.amazonaws.com | 리전 불일치로 인한 인증 스캔 지연 제거 |

---

### ADR-07: 데이터 레이어 설계

**결정**: Staging → (Phase 2) Mart 2레이어

**레이어 정의**

| 레이어 | 모델 | Materialization | 목적 |
|--------|------|----------------|------|
| Staging | stg_trips | table | 원본 정제, 타입 변환, DQ 필터 적용 |
| Staging | stg_locations | table | 존 메타데이터 정제 |
| Mart | mart_trips | table | 파생 컬럼 사전 계산, 존 denormalize |

**stg_trips 변환 내용**
```sql
SELECT
    vendor_id,
    tpep_pickup_datetime                          AS pickup_at,
    tpep_dropoff_datetime                         AS dropoff_at,
    passenger_count::INTEGER                      AS passenger_count,
    trip_distance::DOUBLE                         AS trip_distance,
    "PULocationID"                                AS pickup_location_id,
    "DOLocationID"                                AS dropoff_location_id,
    fare_amount::DOUBLE                           AS fare_amount,
    tip_amount::DOUBLE                            AS tip_amount,
    total_amount::DOUBLE                          AS total_amount
FROM source
WHERE
    tpep_pickup_datetime IS NOT NULL
    AND tpep_dropoff_datetime IS NOT NULL
    AND tpep_dropoff_datetime > tpep_pickup_datetime  -- 시간 역전 제외
    AND trip_distance > 0
    AND fare_amount >= 0
    AND passenger_count BETWEEN 1 AND 9
    AND EXTRACT(YEAR FROM tpep_pickup_datetime) BETWEEN 2019 AND 2023
ORDER BY tpep_pickup_datetime, pickup_location_id
```

**mart_trips 추가 컬럼 (Phase 2)**
```sql
DATEDIFF('minute', pickup_at, dropoff_at)         AS trip_duration_min,
trip_distance / NULLIF(trip_duration_min/60.0, 0) AS trip_speed_mph,
CASE EXTRACT(hour FROM pickup_at)
    WHEN BETWEEN 6  AND 11 THEN 'morning'
    WHEN BETWEEN 12 AND 17 THEN 'afternoon'
    WHEN BETWEEN 18 AND 21 THEN 'evening'
    ELSE 'night'
END                                               AS time_of_day,
strftime(pickup_at, '%A')                         AS day_of_week,
pickup_zone_name,   -- stg_locations JOIN 후 denormalize
dropoff_zone_name
```

---

### ADR-08: DQ 체크 실행 전략

**결정**: 3단계 점진적 검증

**배경**
2억 건 전체에 대해 모든 DQ 테스트를 수행하면 dbt run 시간이 과도하게 증가한다.

**단계별 전략**
| 단계 | 시점 | 대상 | 방법 |
|------|------|------|------|
| 1. 탐색 | dbt run 전 | 월별 샘플 1개 | DuckDB 직접 쿼리 |
| 2. 연도별 검증 | dbt run 전 | 연도별 첫 달 파티션 | DuckDB 직접 쿼리 |
| 3. 전체 검증 | dbt run 후 | 전체 stg_trips | dbt test |

**dbt test 항목**
```yaml
# models/staging/schema.yml
models:
  - name: stg_trips
    columns:
      - name: pickup_at
        tests: [not_null]
      - name: dropoff_at
        tests: [not_null]
      - name: trip_distance
        tests:
          - dbt_utils.accepted_range:
              min_value: 0
              inclusive: false
      - name: passenger_count
        tests:
          - dbt_utils.accepted_range:
              min_value: 1
              max_value: 9
```

---

## 4. 비기능 요구사항

| 항목 | 목표 | 측정 방법 |
|------|------|----------|
| 단순 집계 SLA (Q1~Q3) | 2초 이내 | `EXPLAIN ANALYZE` |
| 복합 쿼리 SLA (Q4~Q5) | 5초 이내 | `EXPLAIN ANALYZE` |
| dbt run 최초 적재 시간 | 기록 (목표 없음) | 실측 후 phase1/findings.md 기록 |
| warehouse.duckdb 크기 | 기록 (목표 없음) | Phase 1 vs 2 비교 |

---

## 5. 보안 및 접근 제어

| 항목 | 방법 |
|------|------|
| S3 접근 | EC2 IAM Role (S3 Read-Only, nyc-tlc 버킷 한정) |
| EC2 접근 | SSH Key Pair, Security Group (본인 IP만 허용) |
| ClawData 연결 | VPC 내부 통신 또는 SSH 터널 |

---

## 6. Phase 확장 계획

| Phase | 내용 | 전제 조건 |
|-------|------|----------|
| Phase 1 | Staging + SLA 검증 | 현재 문서 |
| Phase 2 | Mart 추가 + Phase 1 비교 | Phase 1 SLA 달성 여부 측정 완료 |
| Phase 3 | Athena 마이그레이션 (선택) | DuckDB 단일 노드 한계 도달 시 |

---

## 7. ADR-09: 데이터 수집 경로 변경 (S3 RODA → CloudShell 우회)

**결정**: CloudShell(Seoul) → 사용자 S3 버킷(ap-northeast-2) → EC2 dbt run → EBS 적재 → S3 삭제

**배경**:
- `s3://nyc-tlc/` 버킷: 익명/인증 요청 모두 `AccessDenied` (버킷 정책 변경)
- CloudFront(`d37ci6vzurychx.cloudfront.net`): 서울 리전 EC2 IP 대역 403 Geo-block
- CloudShell(Seoul)에서는 CloudFront 200 OK 확인 → IP 대역 차이가 원인

**데이터 수집 절차** (1회성):
```
CloudShell(Seoul) → curl 다운로드 → aws s3 cp → 사용자 S3 버킷
EC2 → aws s3 cp → /workspace/nyc-taxi/data/ → dbt run → warehouse.duckdb(EBS)
사용자 S3 버킷 삭제
```

**비용**: S3 저장 비용 25GB × $0.025 = $0.63/월 (적재 완료 후 즉시 삭제)

---

## 8. 미결 사항

- [ ] EBS 볼륨 60GB 충분한지 실측 후 확인 (stg_trips 적재 후 파일 크기 기록)
- [ ] c7i-flex.large 네트워크 대역폭으로 dbt run 적재 시간 실측
- [ ] S3 버킷 생성 및 CloudShell 수집 스크립트 실행
- [ ] EC2 AWS credentials 설정 (S3 접근용)
- [ ] dbt_utils 패키지 버전 확정
