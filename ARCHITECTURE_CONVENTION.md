# Architecture Convention — Ruby on Rails 풀스택 아키텍처 구성 규약

**버전**: 1.0.0
**최종 수정일**: 2026-09-21
**문서 기준**: https://guides.rubyonrails.org/ 공식 문서 (Rails 8.1)

---

## 이 문서의 목적

이 문서는 **Ruby on Rails 풀스택 웹 애플리케이션의 디렉토리 구조, 계층 분리, 의존성 규칙, 네이밍 컨벤션, 품질 게이트(정적 분석), 프론트엔드-백엔드 통합 패턴**에 대한 표준을 정의한다. 백엔드는 Rails 최신 버전 (Ruby 최신 버전, Bundler 의존성 관리, ERB 템플릿)을 기준으로, 프론트엔드는 **ERB + Hotwire (Turbo + Stimulus)** 스택을 기준으로 한다.

사내 모든 Rails 풀스택 프로젝트는 이 규약에 따라 아키텍처를 구성하며, 프로젝트 규모와 도메인 복잡도에 맞게 조정한다.

---

## 목차

1. [아키텍처 개요](#1-아키텍처-개요)
2. [표준 디렉토리 구조](#2-표준-디렉토리-구조)
3. [각 계층별 규칙](#3-각-계층별-규칙)
4. [의존성 방향 규칙](#4-의존성-방향-규칙)
5. [네이밍 컨벤션](#5-네이밍-컨벤션)
6. [정적 분석과 품질 게이트](#6-정적-분석과-품질-게이트)
7. [ERB + Hotwire 프론트엔드 규칙](#7-erb--hotwire-프론트엔드-규칙)
8. [도메인 분할 기준](#8-도메인-분할-기준)
9. [확장 패턴 — 프로젝트 규모별 조정](#9-확장-패턴--프로젝트-규모별-조정)
10. [Anti-Patterns](#10-anti-patterns)
11. [백그라운드 작업과 실시간 처리 규칙](#11-백그라운드-작업과-실시간-처리-규칙)

---

## 1. 아키텍처 개요

### 1.1 전체 아키텍처 도식

```
┌──────────────────────────────────────────────────────────────┐
│                         Browser                              │
│  ┌──────────────────┐  ┌──────────────┐  ┌───────────────┐  │
│  │   ERB Template    │  │    Turbo     │  │   Stimulus    │  │
│  │  (서버 렌더링 HTML) │  │ (부분 갱신)   │  │ (클라이언트 꾸미기)│
│  └────────┬─────────┘  └──────┬───────┘  └───────┬───────┘  │
└───────────┼───────────────────┼───────────────────┼──────────┘
            │                   │                   │
     전체 페이지           Frame/Stream          data-action
     (Turbo Drive)        (HTML 조각)           (로컬 UI 동작)
            │                   │                   │
┌───────────▼───────────────────▼───────────────────▼──────────┐
│                    HTTP Layer (Rack / Puma)                   │
│  ┌──────────────────────────────────────────────────────┐    │
│  │                Middleware Stack                       │    │
│  │  HostAuth → Static → Executor → MethodOverride        │    │
│  │  → RequestId → Logger → ShowExceptions                │    │
│  │  → Cookies → Session → Flash → ConditionalGet/ETag    │    │
│  └──────────────────────┬───────────────────────────────┘    │
│                         ▼                                     │
│  ┌──────────────────────────────────────────────────────┐    │
│  │           Router (config/routes.rb)                   │    │
│  │  resources :posts → 7개 표준 액션 (RESTful)            │    │
│  └──────────────────────┬───────────────────────────────┘    │
│                         ▼                                     │
│  ┌──────────────────────────────────────────────────────┐    │
│  │           Controller Layer (얇은 액션)                 │    │
│  │  ┌─ before_action (인증/권한/@객체 로딩)               │    │
│  │  ├─ Strong Parameters (params.expect)                 │    │
│  │  ├─ Form Object 검증 / Service 호출                    │    │
│  │  └─ 응답 결정: 전체 페이지 or Turbo Stream or Redirect  │    │
│  └──────────────────────┬───────────────────────────────┘    │
└─────────────────────────┼────────────────────────────────────┘
                          │
┌─────────────────────────▼────────────────────────────────────┐
│              Service / Query / Form (선택, 복잡한 로직만)      │
│  ┌─ 다단계 비즈니스 로직 (트랜잭션, 오케스트레이션)            │
│  ├─ 여러 모델 조합 / 복잡한 조회 조건                         │
│  └─ 외부 서비스 연동 (이메일, 파일, API)                      │
└──────────────┬───────────────────────────┬───────────────────┘
               │                           │
               ▼                           ▼
┌──────────────────────┐   ┌──────────────────────────────────┐
│   Model (AR) + Scope  │   │  Infrastructure                   │
│   (Active Record)     │   │  ├─ Cache (Solid Cache (기본값) / Redis)   │
│   ┌─ 필드 + 연관       │   │  ├─ Mailer (Action Mailer)        │
│   ├─ 검증/콜백         │   │  ├─ Storage (Active Storage (기본값)/S3)   │
│   ├─ scope 조회 로직   │   │  ├─ Queue (Solid Queue(기본값)/Sidekiq)   │
│   └─ 도메인 메서드      │   │  └─ Realtime (Action Cable)       │
└──────────────────────┘   └──────────────────────────────────┘
```

### 1.2 핵심 원칙

| 원칙 | 설명 |
|:---|:---|
| **MVC 기반 단방향 의존성** | Controller → (Form/Service) → Model + Scope. 하위 계층은 상위 계층을 모른다 |
| **Skinny Controller, Fat Model** | 단순 CRUD는 컨트롤러를 얇게 유지하고 로직을 모델 도메인 메서드로. 모델이 비대해지면 Service로 분리한다 |
| **관례가 설정을 대신한다 (CoC)** | `resources :posts` 기반 RESTful 라우팅, 액션 7종, 액션명-뷰 경로 관례를 표준으로 한다. 관례를 깨는 커스텀 라우트/액션은 예외적으로만 |
| **서버가 HTML을 렌더링한다** | JSON API가 아닌 ERB로 HTML을 생성한다. Turbo가 HTML 조각(Frame/Stream)을 받아 DOM을 부분 갱신한다 |
| **클라이언트 상태는 최소화** | 상태는 서버가 소유하고, Stimulus는 UI 표현(토글, 입력 보조)만 담당한다 |
| **점진적 향상** | Turbo Drive가 `<a>`/`<form>`을 가로채되, JS 없는 기본 동작을 해치지 않는다 |
| **품질 게이트** | Rails는 무타입 언어이므로 **RuboCop(린트) 0 에러 + Brakeman(보안) 0 경고 + 테스트 통과**가 커밋/병합/배포 조건이다 — [6. 정적 분석과 품질 게이트](#6-정적-분석과-품질-게이트) 참조 |
| **관심사별 파일 분리** | Model ≠ Controller ≠ View ≠ Form ≠ Service ≠ Job. 하나의 파일은 하나의 역할만 담당한다 |
| **도메인 = 네임스페이스 단위** | Rails는 단일 앱이 기본이다. 기능은 컨트롤러/모델의 네임스페이스로 분리한다 — [8. 도메인 분할 기준](#8-도메인-분할-기준) 참조 |
| **요청 스레드는 동기, 지연은 Job** | 요청-응답은 동기로 작성한다. 시간이 걸리는 작업은 Active Job으로 분리한다 — [11. 백그라운드 작업과 실시간 처리 규칙](#11-백그라운드-작업과-실시간-처리-규칙) 참조 |

### 1.3 기술 스택 구성

```
[Ruby]         최신
[웹 프레임워크]  Rails 최신버전
[웹서버]        Puma 최신버전 (멀티스레드, Rack 인터페이스)
[버전 관리]     mise (ruby 버전 고정)
[의존성 관리]   Bundler (Gemfile + Gemfile.lock)
[린트]          RuboCop (rubocop-rails-omakase 설정)
[보안 분석]     Brakeman
[ORM]          Active Record (Active Record 패턴 — Repository 별도 두지 않음)
[템플릿]       ERB
[DB]           SQLite
[자산]          Propshaft + importmap-rails (Node/npm 불필요)
[Dynamic HTML] Turbo (Drive / Frames / Streams)
[Reactivity]   Stimulus (경량 클라이언트 UI)
[CSS]          Tailwind CSS (rails new --css tailwind)
[Testing]      minitest + fixtures (RSpec은 프로젝트 단위 선택)
[Cache/Queue]  Solid Cache / Solid Queue (Rails 8 기본, DB 기반)
[Realtime]     Action Cable (Solid Cable 기본)
[배포]          Kamal 2 (컨테이너, zero-downtime)
```

### 1.4 요청-응답 흐름 (전체 페이지 vs Turbo)

```
[사용자 클릭 / 폼 제출]
    │
    ├── 일반 <a>/<form> → Turbo Drive가 fetch로 교체
    │        Controller#액션 → 액션명.html.erb 렌더 (레이아웃 포함)
    │        → 완전한 HTML 응답 → <body> 교체
    │
    └── turbo_frame_tag 안의 링크/폼 → Frame 요청
             Controller → 동일 액션, 뷰는 <turbo-frame>로 감싸 반환
             → 프레임 내용만 교체

[생성/수정/삭제 성공 (폼)]
    → redirect_to + 303 (Turbo Drive가 뒤따라 전체 갱신)
    또는 .turbo_stream.erb 응답 → append/remove/replace 지시 실행

[다른 사용자 브라우저]
    → broadcasts_to + turbo_stream_from → Action Cable 경유 실시간 갱신
```

> **핵심:** 하나의 액션이 `format`/`turbo_frame` 요청 여부에 따라 전체 페이지 또는 HTML 조각을 반환한다. 동일한 비즈니스 로직, 여러 렌더링 방식. 실패하는 폼 렌더는 반드시 `status: :unprocessable_entity`(422), 성공 리다이렉트는 `status: :see_other`(303)를 붙인다 — Turbo의 규약이다.

---

## 2. 표준 디렉토리 구조

### 2.1 전체 구조

```
my-app/
├── .mise.toml                     # Ruby 버전 고정 (커밋)
├── Gemfile                        # 의존성 선언
├── Gemfile.lock                   # 잠긴 의존성 (커밋 필수)
├── Dockerfile                     # Rails 8 기본 생성 (커밋)
├── config.ru                      # Rack 진입점
│
├── app/                           # 애플리케이션 코드 (전부 자동 로딩)
│   ├── controllers/
│   │   ├── application_controller.rb     # 공통 베이스 (인증/에러 처리)
│   │   ├── concerns/                     # 컨트롤러 공용 믹스인
│   │   ├── posts_controller.rb           # 도메인: 블로그
│   │   ├── comments_controller.rb
│   │   └── admin/                         # 관리자 네임스페이스 (선택)
│   │       └── posts_controller.rb        #   Admin::PostsController
│   │
│   ├── models/
│   │   ├── application_record.rb          # 모델 공통 베이스
│   │   ├── concerns/                      # 모델 공용 믹스인 (Sluggable 등)
│   │   ├── post.rb                        # Post
│   │   ├── comment.rb                     # Comment
│   │   └── tag.rb                         # Tag
│   │
│   ├── views/
│   │   ├── layouts/
│   │   │   ├── application.html.erb       # 기본 레이아웃 (flash 표시 포함)
│   │   │   └── admin.html.erb             # 관리자 레이아웃 (선택)
│   │   ├── posts/                         # views/컨트롤러명/액션명.html.erb
│   │   │   ├── index.html.erb             #   전체 페이지
│   │   │   ├── show.html.erb
│   │   │   ├── new.html.erb
│   │   │   ├── edit.html.erb
│   │   │   ├── _post.html.erb             #   파셜 (컬렉션 렌더용)
│   │   │   ├── _form.html.erb             #   폼 파셜 (new/edit 공유)
│   │   │   └── index.turbo_stream.erb     #   Turbo Stream 응답 (필요 시)
│   │   └── shared/                        # 도메인 공용 파셜
│   │       ├── _flash.html.erb
│   │       ├── _empty_state.html.erb
│   │       └── _pagination.html.erb
│   │
│   ├── helpers/                            # 뷰 헬퍼 (표현 로직만)
│   │   └── application_helper.rb
│   │
│   ├── services/                           # Service 객체 (선택, §3.5)
│   │   └── posts/
│   │       └── publish_service.rb          #   Posts::PublishService
│   │
│   ├── queries/                            # Query 객체 (선택, §3.2)
│   │   └── posts/
│   │       └── feed_query.rb               #   Posts::FeedQuery
│   │
│   ├── forms/                              # Form 객체 (선택, §3.4)
│   │   └── posts/
│   │       └── import_form.rb              #   Posts::ImportForm
│   │
│   ├── jobs/                               # Active Job (§11)
│   │   ├── application_job.rb
│   │   └── post_cleanup_job.rb
│   │
│   ├── mailers/                            # Action Mailer
│   │   └── post_mailer.rb
│   │
│   ├── channels/                           # Action Cable (자체 채널 필요 시)
│   │   └── application_cable/
│   │
│   └── assets/                             # 자산 (Propshaft 대상)
│       ├── stylesheets/application.css
│       └── images/
│
├── javascript/                             # importmap 진입점 + Stimulus
│   ├── application.js
│   └── controllers/                        # Stimulus 컨트롤러 (§7.5)
│       ├── application.js
│       └── index.js
│
├── config/
│   ├── routes.rb                           # 라우팅 (도메인별 블록/주석으로 구분)
│   ├── application.rb                      # 공통 설정
│   ├── environments/                       # development / test / production
│   ├── initializers/                       # 부팅 시 실행 설정
│   ├── locales/                            # ko.yml 등 i18n
│   ├── database.yml                        # DB 접속 (환경별)
│   ├── storage.yml                         # Active Storage 서비스
│   ├── importmap.rb                        # JS 핀 매핑
│   ├── deploy.yml                          # Kamal 배포 정의
│   └── ci.rb                               # 로컬 CI 정의 (Rails 8.1)
│
├── db/
│   ├── migrate/                            # 마이그레이션 (커밋 필수)
│   ├── schema.rb                           # 스키마 스냅샷 (커밋 필수)
│   └── seeds.rb                            # 초기 데이터
│
├── test/                                   # minitest
│   ├── fixtures/                           # 테스트 데이터 (YAML)
│   ├── models/
│   ├── controllers/
│   ├── services/                           # 서비스 테스트 (선택 디렉토리)
│   ├── system/                             # 브라우저 E2E
│   └── application_system_test_case.rb
│
├── public/                                 # 정적 파일 (파이프라인 밖)
├── storage/                                # 개발 SQLite/업로드 (커밋 금지)
├── log/ , tmp/ , node_modules 없음          # (커밋 금지)
└── bin/                                    # rails, dev, setup, ci, rubocop...
```

### 2.2 각 디렉토리의 책임

| 디렉토리/파일 | 책임 | 의존 방향 | 비고 |
|:---|:---|:---|:---|
| `config/` | 전역 설정, 라우팅, 환경 | 모든 계층 | 로직 담지 않음 |
| `app/models/` | DB 테이블 매핑, 검증·연관·도메인 메서드·scope | 없음 (최하위) | Active Record — 쿼리 + 영속성 내장 |
| `app/models/concerns/` | 여러 모델 공용 믹스인 | Model | `Sluggable` 등 횡단 관심사 |
| `app/queries/` | 복잡한 조회 조합 (Query Object) | Model | 선택. scope로 부족할 때 |
| `app/services/` | 다단계 비즈니스 로직, 트랜잭션 | Model, Query | 선택. 컨트롤러가 복잡해질 때 도입 |
| `app/forms/` | 다중 모델/비AR 입력 (Form Object) | Model | 선택. 단일 모델은 모델 검증으로 충분 |
| `app/controllers/` | HTTP 요청 수신, 파라미터 허용, 응답 결정 | Form, Service, Model | 얇게 유지. 로직 금지 |
| `app/views/` | ERB 렌더링, 파셜 | 컨트롤러 @변수만 | DB 쿼리 직접 호출 금지 |
| `app/helpers/` | 표현 로직 (포맷·조건부 클래스) | 없음 | 3줄 넘는 뷰 로직은 여기로 |
| `app/jobs/` | 백그라운드 작업 (§11) | Model, Service | 지연·비동기 처리 |
| `javascript/controllers/` | Stimulus 컨트롤러 (§7.5) | 없음 | UI 꾸미기 전용 |
| `test/` | 모델/통합/시스템 테스트 + fixtures | 전 계층 | 품질 게이트의 일부 (§6) |

### 2.3 통일 응답 전략 — 전체 페이지 vs Turbo Frame vs Stream

Rails 풀스택 앱은 세 가지 응답 방식을 상황에 따라 사용한다:

| 응답 유형 | 트리거 | 컨트롤러 동작 | 반환 |
|:---|:---|:---|:---|
| **전체 페이지** | 일반 링크(Turbo Drive), 주소창 입력 | 액션명 뷰 + 레이아웃 렌더 | 완전한 HTML 문서 |
| **Turbo Frame** | `turbo_frame_tag` 안의 링크/폼 | 같은 액션, 뷰가 프레임으로 감쌈 | `<turbo-frame>` 조각 |
| **Turbo Stream** | 폼 성공 후 부분 갱신 | `*.turbo_stream.erb` 렌더 | append/replace/remove 지시 |
| **Redirect** | 생성/수정 성공 | `redirect_to ..., status: :see_other` | `303` + Turbo Drive가 따라감 |
| **실시간 push** | 모델 `broadcasts_to` | 뷰 없음 (Job/콜백에서 발송) | Action Cable → 브라우저 갱신 |

**컨트롤러에서의 분기 패턴:**

```ruby
# app/controllers/comments_controller.rb
class CommentsController < ApplicationController
  def create
    @post = Post.find(params[:post_id])
    @comment = @post.comments.build(comment_params.merge(user: Current.user))

    respond_to do |format|
      if @comment.save
        format.html { redirect_to @post, status: :see_other, notice: "댓글이 등록되었습니다." }
        format.turbo_stream      # create.turbo_stream.erb — 프레임 갱신 응답
      else
        format.html { render :new, status: :unprocessable_entity }
        format.turbo_stream { render :create, status: :unprocessable_entity, locals: { comment: @comment } }
      end
    end
  end
end
```

> **핵심:** 브라우저가 Turbo 요청이면 `format.turbo_stream`이, 아니면 `format.html`이 응답한다. 비즈니스 로직(`save`)은 하나 — 렌더링만 분기된다.

---

## 3. 각 계층별 규칙

### 3.1 Model — Domain / Persistence Layer

**책임**: 데이터베이스 테이블과 1:1로 매핑되는 Active Record 객체. 필드, 검증, 연관, scope, 간단한 도메인 규칙(파생 속성·상태 전환)을 포함한다.

**규칙**:
1. Active Record 패턴을 따른다 — Repository/DAO는 별도로 두지 않는다
2. 컬럼 정의는 마이그레이션이 원천이다. `null: false`, `default`, 인덱스를 정확히 지정한다
3. **간단한 도메인 규칙**은 모델 메서드로 둔다. 다른 모델을 여러 개 조작하는 로직은 Service로
4. 상태 컬럼은 `enum`으로 정의한다 (질의 `?`, 전환 `!`, scope 자동 생성)
5. 연관은 반드시 `dependent:`를 명시한다
6. 조회 로직은 scope로 추출해 체인 가능하게 둔다 (§3.2)
7. `to_s`를 정의해 콘솔/로그에서 읽을 수 있게 한다
8. 콜백은 3개 이하로 — 늘어나면 Service로 승격한다

```ruby
# app/models/post.rb
class Post < ApplicationRecord
  belongs_to :user
  has_many :comments, dependent: :destroy
  has_many :post_tags, dependent: :destroy
  has_many :tags, through: :post_tags
  has_one_attached :cover

  enum :status, { draft: 0, published: 1, archived: 2 }, default: :draft

  validates :title, presence: true, length: { maximum: 200 }
  validates :slug, presence: true, uniqueness: true
  validates :published_at, presence: true, if: :published?

  scope :recent, -> { order(created_at: :desc) }
  scope :by_tag, ->(name) { joins(:tags).where(tags: { name: }).distinct }

  def to_s = title.to_s

  def publish!(at: Time.current)
    update!(status: :published, published_at: at)
  end
end
```

### 3.2 Scope / Query Object — 조회 로직 재사용

**책임**: 반복되는 필터·정렬·집계를 재사용 가능한 형태로 캡슐화한다.

**규칙**:
1. 단일 모델의 반복 조건은 **scope**로 — 항상 Relation을 반환해 체인이 이어지게 한다
2. 조건부 scope은 조건 불충족 시 `all`을 반환하는 패턴으로 작성한다
3. 조인 2개 이상·동적 조합·집계가 섞인 조회는 **Query Object**(`app/queries/`)로 분리한다
4. Query Object는 `.call`로 Relation을 반환한다 — 컨트롤러/서비스 어디서도 체인 가능

```ruby
# app/models/post.rb — scope
class Post < ApplicationRecord
  scope :published, -> { where(status: :published) }
  scope :by_term, ->(q) { q.present? ? where("title LIKE ?", "%#{q}%") : all }
end
```

```ruby
# app/queries/posts/feed_query.rb
module Posts
  class FeedQuery
    def initialize(user:, tag: nil, page: 1)
      @user = user
      @tag = tag
      @page = page
    end

    def call
      scope = Post.published.includes(:user, :tags).recent
      scope = scope.by_tag(@tag) if @tag
      scope.page(@page)      # kaminari 등 페이지네이션
    end
  end
end

# 사용: Posts::FeedQuery.new(user: Current.user, tag: "ruby").call
```

> **기준**: `where` 조건 2개 이하면 scope, 그 이상이거나 여러 모델을 조합하면 Query Object.

### 3.3 Controller — HTTP Layer

**책임**: HTTP 요청을 받아 파라미터를 허용하고 (Form/Service를 통해) 처리한 후, 결과를 HTML(또는 리다이렉트/스트림)로 렌더링한다.

**규칙**:
1. 액션은 표준 7종(index/show/new/create/edit/update/destroy)을 기본으로 한다 — 커스텀 액션은 member/collection 또는 별도 컨트롤러로 정당화할 때만
2. `before_action :set_post, only: [...]`로 @객체 로딩을 통일한다
3. **Strong Parameters는 `params.expect`로, `private #xxx_params` 메서드에만 둔다**
4. 성공 → `redirect_to ..., status: :see_other` / 실패 → `render ..., status: :unprocessable_entity`
5. 액션 하나의 본문은 10줄 이내. 초과하면 Service/모델 메서드로 로직을 내린다
6. 로직이 조건 3개 이상 분기되면 그 즉시 Service로 분리한다
7. 인증/권한은 `before_action`에서 — 액션 본문에 인증 if문을 두지 않는다

```ruby
# app/controllers/posts_controller.rb
class PostsController < ApplicationController
  before_action :set_post, only: [:show, :edit, :update, :destroy]
  before_action :require_ownership, only: [:edit, :update, :destroy]

  def index
    @posts = Posts::FeedQuery.new(user: Current.user, tag: params[:tag]).call
  end

  def show
    # before_action의 @post 사용 — 본문 불필요
  end

  def create
    @post = Current.user.posts.build(post_params)
    if @post.save
      redirect_to @post, status: :see_other, notice: "게시글이 저장되었습니다."
    else
      render :new, status: :unprocessable_entity
    end
  end

  def update
    if @post.update(post_params)
      redirect_to @post, status: :see_other, notice: "수정되었습니다."
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    @post.destroy!
    redirect_to posts_path, status: :see_other, notice: "삭제되었습니다."
  end

  private

  def set_post
    @post = Post.find(params[:id])
  end

  def post_params
    params.expect(post: [:title, :body, :slug, { tag_ids: [] }])
  end

  def require_ownership
    head :forbidden unless @post.user_id == Current.user.id
  end
end
```

### 3.4 Form — Request Validation Layer

**책임**: 요청 입력의 구조와 검증을 담당한다.

**규칙**:
1. **단일 모델 폼은 별도 폼 클래스를 만들지 않는다** — `form_with model:` + 모델 검증(validates)이 표준이다 (Rails의 "폼 = 모델 검증" 관례)
2. 여러 모델을 한 폼에서 편집할 때는 `accepts_nested_attributes_for` 또는 Form Object 중 선택한다
3. 모델 없는 입력(검색·설정·가져오기)이 복잡하면 **Form Object**(`app/forms/`)를 둔다 — `ActiveModel::Model` 기반
4. Form Object도 검증 에러 표시·필드 보존 규약은 모델 폼과 동일하게 (`errors.full_messages` + `field_with_errors`)

```ruby
# app/forms/posts/import_form.rb — Form Object (선택)
module Posts
  class ImportForm
    include ActiveModel::Model     # 검증·네이밍·속성 API 제공
    include ActiveModel::Attributes

    attribute :file
    attribute :mode, :string, default: "replace"

    validates :file, presence: true
    validates :mode, inclusion: { in: %w[replace append] }

    def save
      return false unless valid?

      Posts::ImportService.new(file:, mode:).call
      true
    rescue Posts::ImportError => e
      errors.add(:base, e.message)
      false
    end
  end
end
```

```ruby
# 컨트롤러에서 — 모델 폼과 동일한 성공/실패 패턴
def create
  @form = Posts::ImportForm.new(import_params)
  if @form.save
    redirect_to posts_path, status: :see_other, notice: "가져오기를 완료했습니다."
  else
    render :new, status: :unprocessable_entity
  end
end
```

### 3.5 Service — Business Logic Layer (선택)

**책임**: 여러 모델을 조작하는 다단계 비즈니스 로직, 트랜잭션, 외부 서비스 오케스트레이션.

**규칙**:
1. **도입 기준**: ① 2개 이상의 모델을 쓰기 조작하거나 ② 트랜잭션 경계가 필요하거나 ③ 외부 API 호출이 섞일 때
2. 네이밍: `동사 + 목적어 + Service` (`Posts::PublishService`) — 도메인 네임스페이스 하위에 둔다
3. 진입점은 `#call` 하나 — 생성자는 데이터만 받고 HTTP 객체(params/request/Current)를 받지 않는다
4. 여러 쓰기를 묶을 때는 반드시 `ActiveRecord::Base.transaction`으로 감싼다
5. 실패는 예외로 (`StandardError` 계열 사용자 정의 예외) — 컨트롤러/Job이 rescue_from으로 일괄 처리
6. 반환값은 결과 객체 또는 self — 상태 플래그를 흩뿌리지 않는다

```ruby
# app/services/posts/publish_service.rb
module Posts
  class PublishService
    class AlreadyPublished < StandardError; end

    def initialize(post:, notify_followers: true)
      @post = post
      @notify = notify_followers
    end

    def call
      raise AlreadyPublished, "이미 공개된 게시글입니다" if @post.published?

      ActiveRecord::Base.transaction do
        @post.publish!
        @post.user.increment!(:published_count)
      end

      PostMailer.with(post: @post).published.deliver_later if @notify
      @post
    end
  end
end
```

```ruby
# 컨트롤러에서
def publish
  @post = Post.find(params[:id])
  Posts::PublishService.new(post: @post).call
  redirect_to @post, status: :see_other, notice: "공개되었습니다."
rescue Posts::PublishService::AlreadyPublished => e
  redirect_to @post, status: :see_other, alert: e.message
end
```

### 3.6 View / Helper — Presentation Layer (ERB)

**책임**: 응답 HTML 조립. 로직 최소화.

**규칙**:
1. 뷰는 **컨트롤러의 @변수, 헬퍼, 파셜**만 사용한다 — 뷰에서 DB 쿼리/모델 클래스 메서드 호출 금지
2. 반복되는 조각은 파셜 `_이름.html.erb`로 — 컬렉션은 `render @posts` 관용구 사용
3. new/edit 공유 폼은 `_form.html.erb` 하나로
4. 표현 로직(포맷·조건부 클래스·반복 텍스트)이 3줄 넘으면 헬퍼로 추출한다
5. 사용자 입력 출력은 `<%= %>` 기본 이스케이프에 맡긴다 — `raw`/`html_safe`는 상수·신뢰 HTML에만, 사용자 입력에는 `sanitize`
6. 레이아웃 `application.html.erb`에 flash 표시와 `<%= yield %>`를 둔다

```erb
<%# app/views/posts/index.html.erb %>
<h1>게시글</h1>
<%= render "shared/empty_state", message: "게시글이 없습니다." if @posts.empty? %>

<div id="posts">
  <%= render @posts %>      <%# 각 post마다 posts/_post.html.erb 렌더 %>
</div>
```

### 3.7 Routes — 라우팅 계층

**책임**: URL → Controller#action 매핑. RESTful 자원 설계.

**규칙**:
1. **`resources`가 기본** — 7종 표준 액션 외 커스텀 액션은 `member`/`collection`으로 정당화하고 주석을 남긴다
2. 중첩은 1단계까지, `shallow: true`로 자원 id만 남긴다
3. 관리자·버전 등 횡단 그룹은 `namespace`로 (URL + 컨트롤러 접두)
4. 라우트 파일은 도메인별 주석 블록으로 구분한다
5. URL 하드코딩 금지 — 항상 경로 헬퍼(`posts_path`, `post_path(@post)`)

```ruby
# config/routes.rb
Rails.application.routes.draw do
  root "posts#index"

  # ── 블로그 도메인 ─────────────────────
  resources :posts, shallow: true do
    resources :comments, only: [:create, :destroy]
    member { patch :publish }        # 상태 전환 — PostsController#publish
  end

  # ── 관리자 ───────────────────────────
  namespace :admin do
    resources :posts, only: [:index, :show, :destroy]
  end
end
```

---

## 4. 의존성 방향 규칙

### 4.1 의존성 그래프

```
Routes ──→ Controller ──→ (Form Object) ──→ Model + Scope ──→ Database
              │
              ├──→ Service ──→ Model / Query Object
              ├──→ View(ERB) ←─ 컨트롤러 @변수만 주입
              └──→ Model 직접 호출 가능 — 단순 조회/CRUD는 Form/Service 없이

Helper ──→ (전달받은 객체만 — 쿼리 금지)
View ──→ @변수 / 헬퍼 / 파셜만 — ORM·Service 호출 금지
Job ──→ Service / Model (컨트롤러를 모름)
Mailer ──→ Model (전달받은 객체만)
```

### 4.2 금지된 의존성

| 금지 | 이유 | 대안 |
|:---|:---|:---|
| **Model → Controller** | 영속성 계층이 Presentation을 알면 재사용 불가 | 컨트롤러에서 모델 호출 |
| **Model → Service** | 순환 참조 발생. 모델은 데이터 + 검증 + 간단한 규칙만 | 서비스에서 모델 사용 |
| **Service → Controller / params / request** | Service가 HTTP에 결합되면 Job/콘솔에서 재사용 불가 | 필요한 값만 생성자로 전달 |
| **Service → Current** | 전역 요청 상태 의존은 테스트를 오염시킨다 | `Current.user`를 컨트롤러에서 풀어 `user:`로 전달 |
| **View → ORM 쿼리** | 뷰에서 `Post.where(...)`는 MVC 붕괴 + N+1 온상 | 컨트롤러/Query Object에서 조회해 @변수로 |
| **Helper → Model 쓰기** | 표현 계층의 부수효과 | 읽기만, 쓰기는 Service |
| **Job → Controller / View** | 백그라운드에서 HTTP 계층은 무의미 | Job은 Service/모델만 호출 |

### 4.3 도메인 간 의존성

네임스페이스가 다른 도메인의 Service 내부를 직접 호출하지 않는다. 조합은 컨트롤러(또는 상위 Service)에서:

```ruby
# ❌ 잘못된 패턴 — 블로그 서비스가 알림 도메인 내부를 호출
module Posts
  class PublishService
    def call
      Notifications::SmsSender.new.call(user.phone, "...")   # 타 도메인 내부 구현
    end
  end
end

# ✅ 올바른 패턴 — 도메인의 공개 인터페이스(진입점)만 호출
module Posts
  class PublishService
    def call
      Notifications.deliver(:post_published, user:, post: @post)  # 공개 API
    end
  end
end
```

```ruby
# ✅ 올바른 패턴 — 컨트롤러에서 여러 도메인 조합
def create
  @post = Current.user.posts.build(post_params)
  if @post.save
    Notifications.deliver(:post_created, user: Current.user, post: @post)
    redirect_to @post, status: :see_other, notice: "저장되었습니다."
  else
    render :new, status: :unprocessable_entity
  end
end
```

**기준**: 한 도메인이 다른 도메인을 참조할 때 의존하는 것은 **공개 진입점(단일 모듈 메서드/퍼사드)** 뿐이며, 내부 클래스·private 메서드·테이블에는 접근하지 않는다. 대규모 프로젝트는 Packwerk(§9.3)로 이 규칙을 기계적으로 검사한다.

**예외**: 공통 인프라(캐시·메일·스토리지)는 `Rails.cache`, `ApplicationMailer`, Active Storage 등 프레임워크 내장 인터페이스로 접근한다.

---

## 5. 네이밍 컨벤션

### 5.1 디렉토리/파일명

| 규칙 | 예시 |
|:---|:---|
| 파일 전체: 소문자 snake_case | `posts_controller.rb`, `publish_service.rb` |
| 모델 | `app/models/{단수}.rb` (`post.rb`) — 클래스 `Post` ↔ 테이블 `posts` 자동 매핑 |
| 컨트롤러 | `app/controllers/{복수}_controller.rb` (`posts_controller.rb`) |
| 네임스페이스 디렉토리 | `app/services/posts/publish_service.rb` → `Posts::PublishService` |
| 뷰 | `app/views/{컨트롤러명}/{액션명}.html.erb` |
| 파셜 | `_{이름}.html.erb` (`_form.html.erb`, `_post.html.erb`) |
| Turbo Stream 응답 | `{액션명}.turbo_stream.erb` (`create.turbo_stream.erb`) |
| 마이그레이션 | 자동 생성 UTC 접두 형식 유지 (`20260921xxxxxx_add_user_to_posts.rb`) |
| Stimulus 컨트롤러 | `javascript/controllers/{기능}_controller.js` (`dropdown_controller.js`) |

### 5.2 클래스/모듈명

| 유형 | 패턴 | 예시 |
|:---|:---|:---|
| **Model** | `{도메인}` (단수) | `Post`, `Comment`, `Tag` |
| **Controller** | `{도메인복수}Controller` | `PostsController`, `Admin::PostsController` |
| **Service** | `{동사}{목적어}Service` | `Posts::PublishService`, `Users::RegisterService` |
| **Query Object** | `{목적}Query` | `Posts::FeedQuery` |
| **Form Object** | `{목적}Form` | `Posts::ImportForm` |
| **Job** | `{동사}{목적어}Job` | `PostCleanupJob`, `PublishNotifyJob` |
| **Mailer** | `{도메인}Mailer` | `PostMailer` |
| **Concern** | `{형용사/능력형}형` | `Sluggable`, `Publishable` |
| **사용자 정의 예외** | `{문제상황}` + `Error`/도메인 예외 | `Posts::ImportError`, `PermissionDenied` |
| **Test** | `{대상}Test` | `PostTest`, `PostsControllerTest` |

### 5.3 메서드명

| 패턴 | 용도 | 예시 |
|:---|:---|:---|
| `{형용사}?` | 조건 질의 — true/false 반환 | `published?`, `archived?`, `owned_by?(user)` |
| `{동사}!` | 상태 변경/예외 발생 버전 | `publish!`, `save!`, `update!` |
| `{동사}` (무표식) | 실패 시 nil/false 반환 버전 | `save`, `authenticate` |
| `set_{자원}` | before_action 로딩 | `set_post` |
| `require_{조건}` | before_action 가드 | `require_login`, `require_ownership` |
| `{자원}_params` | Strong Parameters | `post_params` |
| `call` | Service/Query 진입점 | `PublishService#call` |
| `to_s` | 사람이 읽는 표현 | `Post#to_s` → title |
| scope | 동사/전치사형 조회 | `published`, `recent`, `by_tag` |
| `perform` | Job 진입점 | `PostCleanupJob#perform` |

### 5.4 변수/상수명

| 규칙 | 예시 |
|:---|:---|
| 변수/메서드: snake_case | `post_list`, `feed_query` |
| 인스턴스 변수(@): 뷰에 전달할 것만 | `@posts`, `@post`, `@form` |
| 상수: UPPER_SNAKE_CASE | `DEFAULT_PAGE_SIZE`, `MAX_TAG_COUNT` |
| 상수는 얼리고 클래스 내부에 | `STATUSES = %w[draft published].freeze` |
| enum 값: 소문자 스네이크 | `draft`, `published`, `in_review` |
| 블록 파라미터: 단수형 | `@posts.each { |post| ... }` |

### 5.5 DB 컬럼/필드명

| 규칙 | 예시 |
|:---|:---|
| **snake_case** | `user_id`, `post_id`, `created_at` |
| **FK**: `{참조모델}_id` (마이그레이션은 `references`) | `author_id` (author 컬럼), `post_id` |
| **날짜/시간**: `{동작}_at` | `created_at`, `published_at`, `deleted_at` |
| **날짜**: `{동작}_on` | `published_on` |
| **Boolean**: `{형용사}?` 는 컬럼 불가 → `is_` 없이 형용사만 | `published`, `active`, `featured` |
| **횟수**: `{명사}_count` (counter_cache 호환) | `comments_count`, `views_count` |
| **조인 테이블**: `{모델들복수}` 또는 `{모델}Tag` 조인 모델 | `post_tags` |
| **enum 컬럼**: integer + enum 선언 | `status:integer` |

### 5.6 URL 패턴

| 규칙 | 예시 |
|:---|:---|
| `/{복수형}` | 목록: `/posts` |
| `/{복수형}/new` · `/{복수형}/{id}/edit` | 폼 |
| `/{복수형}/{id}` | 상세/수정(PATCH)/삭제(DELETE) — 메서드로 구분 |
| 부모-자식은 1단계 중첩 + shallow | `/posts/{post_id}/comments` → `/comments/{id}` |
| 관리자는 `/admin` 접두 | `/admin/posts` |
| URL에 동사 금지 | `/createPost` ❌ → `POST /posts` ✅ |
| 상태 전환 등 예외적 동사는 member로 | `PATCH /posts/{id}/publish` |

---

## 6. 정적 분석과 품질 게이트

### 6.1 핵심 원칙

Ruby는 동적 언어이며, Rails 본체와 주류 생태계는 **무타입**을 기본값으로 한다. Python/Django의 `mypy --strict`에 대응하는 단일 표준 도구가 존재하지 않으므로, 이 규약은 **린트 + 보안 분석 + 테스트**를 품질 게이트로 삼고 타입 체크는 프로젝트 규모에 따라 선택적으로 도입한다.

> **`bin/ci`(RuboCop 0 에러 + Brakeman 0 경고 + `bin/rails test` 통과)가 성공해야만 커밋/병합/배포가 가능하다.** — 이것이 이 규약에서 "구조가 맞지 않으면 실행되지 않는다"를 구현하는 방식이다.

### 6.2 게이트 구성 (모든 프로젝트 필수)

| 게이트 | 도구 | 기준 | 비고 |
|:---|:---|:---|:---|
| 린트/포맷 | RuboCop (`rubocop-rails-omakase`) | 0 에러 (`Layout` 자동 교정) | Rails 8 기본 생성 설정 사용 |
| 보안 정적 분석 | Brakeman | 0 경고 (`--exit-on-warn`) | SQL 인젝션/XSS/CSR 검사 |
| 의존성 취약점 | `bundler-audit` (+ importmap 사용 시 `bin/importmap audit`) | 0 취약점 | 주기적 실행 |
| 테스트 | minitest | 전체 통과 | 모델 테스트 최우선 |
| 자동 로딩 | `bin/rails zeitwerk:check` | 통과 | 파일/상수명 규약 위반 검출 |

```yaml
# .github/workflows/ci.yml (요지)
name: CI
on: [push, pull_request]
jobs:
  test:
    runs-on: ubuntu-latest
    env: { RAILS_ENV: test }
    steps:
      - uses: actions/checkout@v4
      - uses: ruby/setup-ruby@v1
        with: { ruby-version: "3.4", bundler-cache: true }
      - run: bin/rails db:setup
      - run: bin/rubocop            # 게이트 1 — 0 에러
      - run: bin/brakeman --quiet --no-pager --exit-on-warn --exit-on-error   # 게이트 2
      - run: bin/rails test         # 게이트 3
```

로컬에서는 Rails 8.1의 `bin/ci`(`config/ci.rb` 정의)로 동일 게이트를 커밋 전 실행한다.

### 6.3 구조 규칙의 기계적 검증

타입 체커가 없는 대신, 구조 규칙을 다음으로 검증한다:

| 규칙 | 검증 수단 |
|:---|:---|
| 파일명 = 상수명 (Zeitwerk) | `bin/rails zeitwerk:check` |
| 네임스페이스 = 디렉토리 | Zeitwerk가 부팅 시 강제 |
| 컨트롤러 액션 10줄 이내 | RuboCop `Metrics/MethodLength` (커스터마이즈) |
| 뷰의 쿼리 호출 | 코드 리뷰 + `Metrics/BlockLength` 힌트 |
| 도메인 간 의존 (대규모) | Packwerk package 독립성 검사 (§9.3) |
| 콜백 3개 이하 | 코드 리뷰 체크리스트 |

### 6.4 타입 체크 (선택)

타입 체크는 **강제하지 않으며**, 다음 기준으로만 도입한다:

| 프로젝트 규모 | 권장 |
|:---|:---|
| 소규모 (모델 ≤ 8) | 무타입 — 게이트는 §6.2로 충분 |
| 중규모 (모델 10~30) | 무타입 기본. 핵심 도메인 서비스부터 선택적 Sorbet(`typed: true`) |
| 대규모 (모델 30+) | **Sorbet 전면 도입 + `typed: strict`** 를 권장 (Tapioca RBI 관리 포함). 공식 표준을 따르려면 Steep + RBS |

```ruby
# Sorbet 도입 시 (선택)
# typed: strict
extend T::Sig

module Posts
  class PublishService
    sig { params(post: Post, notify: T::Boolean).void }
    def initialize(post:, notify_followers: true) = ...
  end
end
```

도입 시 `bundle exec srb tc`를 CI 게이트에 추가한다. 신규 파일은 `# typed: true`부터 시작해 점진적으로 `strict`로 올린다 — 초기부터 strict 강제는 금지(이관 비용 폭증).

---

## 7. ERB + Hotwire 프론트엔드 규칙

### 7.1 기술별 역할 분리

| 기술 | 역할 | 하지 않는 것 |
|:---|:---|:---|
| **ERB** | HTML 구조와 서버 데이터 출력 | 로직 (3줄 이상은 헬퍼/모델로) |
| **Turbo Drive** | 페이지 전환 AJAX화 (body 교체) | 끄거나 커스터마이즈하지 않는다 — 기본 동작이 표준 |
| **Turbo Frames** | 영역별 부분 갱신 (탭, 인라인 편집, 모달 폼) | 페이지 전체 상태 관리 |
| **Turbo Streams** | 생성/삭제의 즉시 반영, 실시간 push | 단순 페이지 전환 |
| **Stimulus** | 기존 HTML에 JS 동작 부착 (토글, 입력 보조, 써드파티 위젯) | API 호출로 서버 상태 이중화 |
| **CSS(Tailwind)** | 표현 | — |

```
상태 소유: 서버(세션+DB)가 1차 소유.
Stimulus는 표시 상태(열림/닫힘 등 세션과 무관한 것)만.
```

### 7.2 뷰 파일 구조

```
app/views/
├── layouts/application.html.erb       # 공통 셸 — flash, importmap, yield
├── shared/                            # 도메인 공용
│   ├── _flash.html.erb
│   ├── _empty_state.html.erb
│   └── _modal.html.erb
└── posts/
    ├── index.html.erb                 # 전체 페이지
    ├── show.html.erb
    ├── new.html.erb / edit.html.erb   # 둘 다 _form 렌더
    ├── _post.html.erb                 # 목록 아이템 (컬렉션 렌더)
    ├── _form.html.erb                 # 공유 폼
    ├── _post.turbo_stream.erb         # 스트림용 조각 (선택)
    └── create.turbo_stream.erb        # 스트림 응답 (선택)
```

- 프레임으로 갱신되는 영역은 `id`를 갖는 DOM(`#posts`, `#comments`)으로 감싼다 — 스트림 append/remove의 대상이다
- 파셜 이름은 **명사형**으로 무엇인지 드러낸다 (`_post_card.html.erb` ❌ `_post.html.erb` ✅)

### 7.3 전체 페이지 vs Frame vs Stream 선택 기준

| 상황 | 응답 | 구현 |
|:---|:---|:---|
| 페이지 이동(링크) | 전체 HTML | Turbo Drive 기본 — 구현 불필요 |
| 페이지 내 일부 영역 편집(인라인 폼, 탭) | Frame | `turbo_frame_tag` + 같은 id 매칭 |
| 생성/삭제 후 목록 갱신 | Stream | `create.turbo_stream.erb` (append/remove) |
| 다른 사용자에게도 즉시 반영 | Stream + Cable | 모델 `broadcasts_to` + 뷰 `turbo_stream_from` |
| 검색/필터 | Frame 또는 전체 | URL 유지 필요하면 전체 페이지 + Turbo Drive |

### 7.4 Turbo 사용 규칙

1. Frame id는 `dom_id(@post)`(`post_1`) 또는 `명사_복수`(`comments`) 컨벤션을 따른다 — 임의 문자열 id 금지
2. 폼 성공은 `303` + redirect, 실패 재렌더는 `422` — 이 상태 코드 규약이 Turbo 폼 교체의 전제다
3. 프레임 밖으로 링크를 내보낼 때만 `data: { turbo_frame: "_top" }`를 명시한다
4. 파괴적 버튼은 `button_to` + `data: { turbo_confirm: "..." }`
5. 스트림 액션은 `append`/`prepend`/`replace`/`remove`만 — 창의적 DOM 조작은 Stimulus+프레임으로
6. 실시간 갱신은 모델에 `broadcasts_to :post` 한 줄이 표준 — 수동 `broadcast_render_to`는 예외적

```erb
<%# app/views/posts/show.html.erb — 표준 조합 %>
<%= turbo_stream_from @post %>                       <%# 실시간 구독 %>
<h1><%= @post.title %></h1>

<div id="comments">
  <%= render @post.comments %>                        <%# 컬렉션 파셜 %>
</div>

<%= turbo_frame_tag "new_comment", src: new_post_comment_path(@post) %>   <%# 지연 로딩 폼 %>
```

```erb
<%# app/views/comments/create.turbo_stream.erb %>
<%= turbo_stream.append "comments" do %>
  <%= render "comments/comment", comment: @comment %>
<% end %>
<%= turbo_stream.update "comment_count", pluralize(@post.comments.size, "comment") %>
```

### 7.5 Stimulus 사용 규칙

1. 컨트롤러는 **하나의 UI 동작**만 담당 (`dropdown`, `modal`, `autocomplete`) — 비즈니스 로직 금지
2. 상태 변경이 필요하면 서버로 폼/요청을 보내 렌더 결과로 해결 — Stimulus 내부에 도메인 상태를 두지 않는다
3. 네이밍: `data-controller="기능"`, `data-action="기능#메서드"`, `data-{기능}-target`, `data-{기능}-{속성}-value`
4. 표준 속성(values/targets)을 쓰고, DOM에서 데이터를 긁어오는 코드를 최소화한다

```js
// javascript/controllers/dropdown_controller.js
import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["menu"]
  static classes = ["open"]              // data-dropdown-open-class

  toggle() { this.menuTarget.classList.toggle(...this.openClasses) }
}
```

```erb
<div data-controller="dropdown">
  <button data-action="dropdown#toggle">메뉴</button>
  <ul data-dropdown-target="menu" data-dropdown-open-class="hidden">...</ul>
</div>
```

### 7.6 CSRF 통합

- Rails 폼(`form_with`/`button_to`)은 authenticity_token을 **자동** 삽입한다 — 토큰 수동 관리 금지
- 레이아웃의 `<%= csrf_meta_tags %>`가 Turbo의 fetch에 토큰을 주입한다 — 제거 금지
- 프레임워크 보호(`default_protect_from_forgery`)는 항상 on — 끄는 커밋은 리뷰 거부 사유

---

## 8. 도메인 분할 기준

### 8.1 Rails의 분할 단위

Django의 "앱"에 해당하는 분할 단위가 Rails에는 없다(기본 단일 앱). 이 규약은 **도메인 = 네임스페이스 + 라우트 블록**으로 분할한다:

| 도메인 | 컨트롤러 | 모델 | 라우트 | 뷰 |
|:---|:---|:---|:---|:---|
| 블로그 | `PostsController`, `CommentsController` | `Post`, `Comment`, `Tag`, `PostTag` | `resources :posts` 블록 | `views/posts/` |
| 인증 | `SessionsController`, `PasswordsController` | `User`, `Session` | 제너레이터 생성 경로 | `views/sessions/` |
| 관리자 | `Admin::PostsController` | (블로그 모델 재사용) | `namespace :admin` | `views/admin/posts/` |

**분할 기준**:
1. 하나의 도메인은 하나의 라우트 블록 + 컨트롤러 그룹 + 모델 그룹으로 대응된다
2. 모델은 도메인 소유 디렉토리(`app/models/billing/`)보다 **루트 `app/models/` 단순 목록**을 소규모까지 유지한다 (§9.3에서 분리)
3. 공용 모델(User, Organization)은 루트에 두고 `app/models/concerns/`로 횡단 로직 공유
4. 한 컨트롤러의 액션이 7종 + 2개를 넘으면 도메인 분할 신호다

### 8.2 도메인 내부 모듈 분할

```
app/
├── controllers/posts_controller.rb        # HTTP 진입 (얇게)
├── models/
│   ├── post.rb                            # 데이터 + 검증 + 도메인 메서드
│   └── concerns/sluggable.rb              # 횡단 믹스인
├── queries/posts/feed_query.rb            # 조회 조합
├── services/posts/publish_service.rb      # 다단계 쓰기
└── views/posts/                           # 표현
```

각 파일이 담는 것은 정확히 하나: **컨트롤러는 HTTP 번역, 모델은 도메인 규칙, Query는 조회, Service는 오케스트레이션, 뷰는 표현.**

---

## 9. 확장 패턴 — 프로젝트 규모별 조정

### 9.1 소규모 (도메인 ≤ 3, 모델 ≤ 8)

`rails new` 기본 구조를 그대로 사용한다. Service/Query/Form 없이 **Model 도메인 메서드 + scope + 얇은 컨트롤러**로 충분하다.

```
app/
├── controllers/posts_controller.rb     # 표준 CRUD + before_action
├── models/post.rb                      # 검증 + scope + 도메인 메서드
├── views/posts/
└── helpers/
```

- 이 단계에서 `app/services/`를 미리 만들지 않는다 — 필요할 때(§3.5 기준) 도입한다

### 9.2 중규모 (도메인 4~10, 모델 10~30)

`services/`, `queries/`, `forms/`를 도입해 컨트롤러와 모델을 함께 얇게 유지한다. 관리자 화면은 `namespace :admin`으로 분리.

```
app/
├── controllers/
│   ├── posts_controller.rb
│   ├── comments_controller.rb
│   └── admin/posts_controller.rb
├── models/
│   ├── post.rb · comment.rb · tag.rb
│   └── concerns/sluggable.rb
├── queries/posts/feed_query.rb
├── services/posts/publish_service.rb
├── forms/posts/import_form.rb
└── views/
    ├── posts/ · comments/
    └── admin/posts/
```

- 모델 하나가 300줄을 넘으면: 도메인 메서드 → Service, 조회 → Query, 횡단 → Concern으로 분리한다
- 테스트도 `test/services/`, `test/queries/` 디렉토리를 추가한다

### 9.3 대규모 (도메인 10+, 모델 30+) — 모듈형 모놀리스

**도메인별 패키지 구조**로 재편한다. 마이크로서비스가 아니라 단일 앱 내 경계 강화다:

```
app/
├── controllers/
│   ├── admin/                    # 관리자
│   └── billing/ · catalog/ ·    # 도메인별 네임스페이스
├── models/
│   ├── billing/                  # Billing::Invoice, Billing::Subscription
│   ├── catalog/                  # Catalog::Product
│   └── user.rb                   # 공용 모델은 루트
├── services/billing/
├── queries/catalog/
└── views/
    ├── billing/ · catalog/
    └── admin/

packs/                            # Packwerk 패키지 (선택, 경계 강제 시)
├── billing/
└── catalog/
```

- 도메인 간 호출은 **공개 인터페이스만** (§4.3) — Packwerk `package_todo.yml`로 의존성 방향을 기계 검사한다
- 공용 모델(User, Organization)과 공용 Concern은 루트/공용 패키지에
- Rails Engine 분리는 **최후 수단** — 팀·배포 주기가 분리될 때만 고려한다

### 9.4 환경 분리 (모든 규모 공통)

```
config/environments/development.rb    # 리로드 on, 상세 에러 on
config/environments/test.rb           # 병렬 테스트, 롤백
config/environments/production.rb     # force_ssl, 로그 레벨, 자산 precompile
```

환경별 분기는 `Rails.env` 직접 비교보다 **환경 설정 파일과 `config.xxx` 플래그**로. 시크릿은 credentials 또는 ENV — 코드/커밋 금지.

---

## 10. Anti-Patterns

### 10.1 계층 관련

| Anti-Pattern | 문제점 | 올바른 접근 |
|:---|:---|:---|
| **컨트롤러에 비즈니스 로직** | if/else·쿼리가 액션에 쌓이면 재사용 불가, 테스트 어려움 | 로직은 Service/모델로, 액션은 10줄 이내 |
| **뷰에서 DB 쿼리** | `Post.where(...)` in ERB — MVC 붕괴 + N+1 | 컨트롤러/Query에서 조회해 @변수로 |
| **Service에 params/Current 주입** | HTTP 결합으로 Job/콘솔 재사용 불가 | 값을 풀어서 생성자로: `PublishService.new(post:)` |
| **모델에 과도한 오케스트레이션** | 다른 모델 조작·외부 API가 모델에 쌓임 | 2개 이상 모델 쓰기는 Service로 |
| **scaffold 남용 후 방치** | 생성 코드를 이해 없이 누적 | 관례(7종 액션) 이해 후 수정. 새 도메인도 결국 §3 형태로 정리 |
| **커스텀 액션 난사** | `activate`, `deactivate`, `duplicate`... 컨트롤러 비대화 | 상태 전환은 member 액션 1개 + 모델 메서드, 또는 별도 컨트롤러 |
| **Concern에 상태 숨기기** | `included do`에서 조건 로직까지 주입 | Concern은 선언적 믹스인만, 로직은 Service |

### 10.2 프론트엔드 관련

| Anti-Pattern | 문제점 | 올바른 접근 |
|:---|:---|:---|
| **Stimulus로 API 조회/상태 관리** | 서버 상태 이중화, 동기화 버그 | Turbo(서버 HTML)로 갱신 |
| **Turbo로 UI 토글 제어** | 열림/닫힘에 서버 요청 — 과잉 | Stimulus `toggle` |
| **모든 갱신을 전체 페이지로** | 검색·페이징마다 풀로드 | Frame/Stream 부분 갱신 |
| **422/303 상태 코드 누락** | Turbo가 폼 실패/성공을 못 알아봄 | 실패 `:unprocessable_entity`, 성공 `:see_other` |
| **프레임 id 즉흥 부여** | `"frame1"` — 스트림 타깃 불일치 | `dom_id(@post)` / 명사_복수 컨벤션 |
| **사용자 입력에 `raw`/`html_safe`** | XSS | `<%= %>` 기본 이스케이프, 필요 시 `sanitize` |
| **JS 번들러 조기 도입** | npm 빌드 체계 유지비 | importmap 기본 유지, 필요가 확인되면 jsbundling |

### 10.3 네이밍 관련

| Anti-Pattern | 문제점 | 올바른 접근 |
|:---|:---|:---|
| 모델 클래스명 복수형 | `Posts` — 테이블 매핑 관례 붕괴 | `Post` (단수) |
| 컨트롤러 단수형 | `PostController` — 라우트/헬퍼 관례 붕괴 | `PostsController` (복수) |
| Service에 `Manager`/`Helper` 접미 | 역할 불명확 | 동사+목적어+`Service`/`Query`/`Form` |
| Boolean 컬럼 `is_` 접두 | Rails 관례 이탈 (`is_published` ❌) | 형용사만 (`published`) |
| 파일명과 상수명 불일치 | Zeitwerk 로딩 실패 | `posts/feed_query.rb` ↔ `Posts::FeedQuery` |

### 10.4 의존성/품질 관련

| Anti-Pattern | 문제점 | 올바른 접근 |
|:---|:---|:---|
| **lib/에 비즈니스 로직** | 자동 로딩 밖, 테스트·리로드 문제 | `app/` 하위 객체로 (§2.1) |
| **초기 마이그레이션 수정** | 히스토리 불일치로 팀 스키마 붕괴 | 새 마이그레이션 추가 |
| **게이트 우회 커밋** | `--no-verify` 습관화 | `bin/ci` 실패는 수정 후 커밋 |
| **테스트 없는 Service** | 도입 기준 미달 Service만 늘어남 | Service마다 대응 테스트, 기준 미달이면 Service 삭제 |
| **도메인 간 테이블 직접 조인 남용** | 경계 침식, 변경 파장 확대 | 공개 인터페이스 경유 (§4.3) |

### 10.5 백그라운드 관련

| Anti-Pattern | 문제점 | 올바른 접근 |
|:---|:---|:---|
| **Job에 ActiveRecord 객체 전달** | 직렬화 실패/재실행 시 stale | id만 전달해 Job에서 재조회 |
| **Job에 params 통째로 전달** | HTTP 결합 | 필요한 스칼라 값만 |
| **요청 안에서 외부 API 대기** | 타임아웃·스레드 점유 | `perform_later`로 지연 |
| **비멱등 Job + 무한 retry** | 중복 부수효과 | 멱등 설계 + 제한된 retry (§11) |

---

## 11. 백그라운드 작업과 실시간 처리 규칙

### 11.1 기본 원칙

| 원칙 | 설명 |
|:---|:---|
| **요청은 동기, 지연은 Job** | 웹 응답 시간이 1초를 넘을 작업(메일, 외부 API, 대량 가공)은 Active Job으로 |
| **큐 어댑터는 교체 가능하게** | 기본 Solid Queue(DB 기반). 코드는 어댑터를 모르게 — `perform_later`만 |
| **Job은 얇게** | 오케스트레이션은 Service, Job은 "예약된 진입점" 역할만 |
| **실시간은 Turbo 브로드캐스트 우선** | 자체 Action Cable 채널은 양방향(채팅 등) 필요 시만 |

### 11.2 Active Job 규칙

1. 인자는 **직렬화 가능한 스칼라**(id, 문자열, 숫자, 날짜)만 — ActiveRecord 객체/params 금지
2. Job은 **멱등**하게 — 같은 작업이 두 번 실행돼도 같은 결과가 되게 (중복 체크/UPSERT)
3. retry는 `retry_on`으로 명시적으로 제한한다
4. Job 안의 예외는 로그+재시도 정책으로 — 조용한 수정자 rescue 금지
5. 대량 처리는 `find_each`/`in_batches`로 배치 처리한다

```ruby
class PublishNotifyJob < ApplicationJob
  queue_as :default
  retry_on Timeout::Error, wait: 30.seconds, attempts: 3
  discard_on ActiveJob::DeserializationError

  def perform(post_id)                     # 객체가 아니라 id
    post = Post.find(post_id)
    PostMailer.with(post: post).published.deliver_now   # Job 안에서는 deliver_now
  end
end

# 컨트롤러/서비스에서
PublishNotifyJob.perform_later(post.id)
PublishNotifyJob.set(wait: 10.minutes, queue: :low).perform_later(post.id)
```

### 11.3 큐·캐시 인프라 — Solid 기본값과 운영 토폴로지

**선택 기준:**

| 규모 | 큐 | 캐시 | 케이블 |
|:---|:---|:---|:---|
| 소~중 (단일 서버) | Solid Queue (기본) | Solid Cache (기본) | Solid Cable (기본) |
| 대량 잡/다중 앱 서버 | Sidekiq(Redis) | Redis 또는 Memcached | Redis 어댑터 |

**운영 토폴로지 규칙 (Solid 기본 유지 시):**

1. **웹(Puma)과 잡(`bin/jobs`)은 별도 프로세스로 운영한다** — Kamal의 `config/deploy.yml`에 포함된 `job:` 서비스(`cmd: bin/jobs`)를 제거/수정하지 않는다. 잡을 웹 프로세스에 인라인으로 넣는 구성(puma 플러그인)은 예외 승인 시에만
2. Solid 3종의 **전용 자식 DB 구성(cache/queue/cable)을 유지**한다 — 앱 DB에 테이블을 합치는 변경 금지. `bin/rails db:prepare`가 전부 준비한다
3. Solid Cable은 웹 프로세스 내 폴링 동작이 기본이다 — 별도 프로세스/어댑터 교체는 실시간 규모가 문제될 때만
4. 캐시 키는 `{도메인}/{식별자}` 컨벤션(`posts/123/toc`)으로, `expires_in`을 명시한다. 캐시 무효화는 모델 콜백이 아니라 **명시적 갱신 지점(Service)**에서 수행한다
5. 전환은 컴포넌트별로 독립적으로 (`queue_adapter` / `cache_store` / cable.yml). **전환 후에도 `perform_later`, `Rails.cache.fetch`, `broadcasts_to` 애플리케이션 코드는 변경하지 않는다** — 이 어댑터 추상화가 전제인 규칙이다

### 11.4 실시간 갱신 (Turbo Streams + Action Cable)

```ruby
# 모델 — 생성/수정/삭제마다 해당 글 채널로 스트림 발송
class Comment < ApplicationRecord
  belongs_to :post
  broadcasts_to :post, inserts_by: :append, target: "comments"
end
```

```erb
<%# 구독 측 뷰 %> 
<%= turbo_stream_from @post %>
<div id="comments"><%= render @post.comments %></div>
```

규칙:
1. 실시간 대상 DOM에는 항상 `id`가 있다 (`broadcasts_to`의 target과 일치)
2. 구독 범위는 최소 자원 단위로 (`:post` — 전역 채널 금지)
3. 자체 채널(`app/channels/`)은 사용자 입력을 서버로 올리는 양방향이 필요할 때만 생성한다
4. 백엔드는 기본 Solid Cable — Redis 도입은 채널 규모가 문제될 때만

### 11.5 이벤트와 관측 (Rails 8.1)

구조화 이벤트는 로그 문자열 대신 사용한다:

```ruby
Rails.event.notify("post.published", post_id: post.id, user_id: post.user_id)

# subscriber에서 메트릭/알림으로 후처리
Rails.event.subscribe("post.published") do |event|
  Metrics.increment("post_published", event.payload[:user_id])
end
```

이벤트 이름은 `{도메인}.{동사과거형}` 컨벤션(`post.published`, `user.signup`)으로 통일한다.

### 11.6 스레드 안전 규칙

Puma는 멀티스레드로 동작한다:

1. 가변 클래스 변수(`@@`)/전역 상태에 상태를 두지 않는다 — 인스턴스(@)·DB·캐시에
2. 요청 간 공유가 필요한 값은 `Current` 속성(요청 스코프) 또는 세션에
3. 무상태 Service/Query 객체는 재사용 안 해도 되게 생성 비용을 최소화한다 — 스레드 안전은 무상태로 보장한다

---

> **이 문서는 사내 모든 Rails 풀스택 프로젝트의 아키텍처 구성 기준입니다.**
> 프로젝트별 편차가 필요한 경우, 이 문서의 원칙 범위 내에서 AGENTS.md에 예외 사항을 명시하세요.
>
> **변경 이력:**
> | 날짜 | 버전 | 변경 내용 |
> |------|------|----------|
> | 2026-09-21 | 1.0.0 | 최초 제정 — Rails 8.1 + ERB + Hotwire + Bundler + RuboCop/Brakeman 품질 게이트 풀스택 아키텍처 컨벤션 |
