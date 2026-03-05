

# ✈ TravelSync — Product Requirements Document
**Version:** v1.0 | **Date:** March 2026 | **Platform:** Android & iOS | **Stack:** Flutter + Supabase
make backend with supabase i already setup mcp server for supabase project name travel 
---

## 1. EXECUTIVE SUMMARY

TravelSync is a 100% free-stack, production-ready mobile application built with Flutter and Supabase that transforms how people track, analyse, and share their travel journeys. The app combines passive background GPS tracking, local AI suggestions, a gamification engine, real-time group collaboration, and a rich analytics dashboard — all without requiring paid third-party APIs.

**Problem Statement:**
Modern travellers lack a unified tool that passively records every journey, rewards exploration, surfaces personalised place recommendations, and lets groups plan trips together in real time. Existing solutions are either expensive (Google Maps APIs), require manual logging, or lack community features.

**Vision:**
"Every kilometre tells a story." TravelSync makes travel data beautiful, social, and actionable — rewarding curiosity, simplifying group coordination, and turning raw GPS coordinates into lifetime memories.

**Goals at a Glance:**
- Passive Tracking → 95% of location events captured with <5% battery overhead
- AI Suggestions → 70%+ suggestion acceptance rate in user testing
- Gamification → DAU retention +40% vs baseline via XP/badge loop
- Group Sync → <500ms real-time latency on Supabase Realtime
- Privacy → GDPR-compliant; tracking can be paused in <2 taps

---

## 2. STAKEHOLDERS & TARGET USERS

### 2.1 Primary Personas

**The Road Tripper** (25–40)
- Profile: Drives long routes solo or with friends, loves data and nostalgia
- Core Need: Auto-track every km, share beautiful route maps on social media

**The City Hopper** (22–35)
- Profile: Travels frequently for work, collects cities like stamps
- Core Need: Quickly see new cities visited, earn badges, discover hidden gems nearby

**The Group Traveller** (Any age)
- Profile: Plans trips with family/friends, needs shared coordination
- Core Need: Realtime shared checklist, group itinerary, budget tracking

**The Stats Nerd** (Any age)
- Profile: Data-driven traveller, loves analytics and year-in-review
- Core Need: Rich dashboards, heat maps, monthly graphs, lifetime stats

**The Backpacker** (18–30)
- Profile: Budget traveller, offline-first, visits many countries
- Core Need: Low data usage, country counter, level progression

---

## 3. FEATURE REQUIREMENTS

### 3.1 Authentication & User Profile

| ID   | Feature              | Description                                              | Priority      |
|------|----------------------|----------------------------------------------------------|---------------|
| A-01 | Email/Password Auth  | Supabase GoTrue with email confirm, forgot password      | Must Have     |
| A-02 | Profile Setup        | Name, bio, avatar upload to Supabase Storage             | Must Have     |
| A-03 | Public Profile Link  | travelsync.app/user/{username} shows stats, badges, map  | Should Have   |
| A-04 | Social OAuth         | Google + Apple Sign-In via Supabase                      | Nice to Have  |
| A-05 | Delete Account       | Full GDPR data deletion from all tables + Storage        | Must Have     |

---

### 3.2 Background Location Tracking

Implemented via geolocator + workmanager. All location data is encrypted in transit (TLS 1.3). Only changes >100m are persisted to reduce noise and battery usage.

| ID   | Feature              | Description                                                        | Priority     |
|------|----------------------|--------------------------------------------------------------------|--------------|
| T-01 | Interval Tracking    | 30 min / 1 hr / 3 hr configurable background wakeup               | Must Have    |
| T-02 | Distance Tracking    | Trigger on 500m or 1km displacement (user choice)                 | Must Have    |
| T-03 | Reverse Geocoding    | OSM Nominatim API — detect city, state, country per point         | Must Have    |
| T-04 | New City Alert       | In-app push if first visit to detected city; award XP             | Must Have    |
| T-05 | Privacy Toggle       | Pause/resume tracking in 1 tap from home screen widget            | Must Have    |
| T-06 | Battery Guard        | Exponential back-off on low battery; skip if <15%                 | Should Have  |
| T-07 | Offline Cache        | Queue points locally (SQLite) when offline; sync on reconnect     | Should Have  |

**Stored per location point:** latitude, longitude, altitude, speed, heading, GPS accuracy, city, state, country, country code, transport mode, device timestamp, server arrival time.

---

### 3.3 Route & Roadmap System

OSRM free API provides routing and distance. Polylines are encoded (Google Polyline format) to minimise storage. Routes are rendered on flutter_map using OSM tiles.

| ID   | Feature            | Description                                                   | Priority     |
|------|--------------------|---------------------------------------------------------------|--------------|
| R-01 | Route Replay       | Animate past trips on the map with speed colouring           | Must Have    |
| R-02 | Daily/Weekly Stats | Distance today, this week, longest single trip               | Must Have    |
| R-03 | OSRM Navigation    | Turn-by-turn directions, ETA, road distance                  | Should Have  |
| R-04 | Traffic Heuristics | Colour route segments by recorded speed vs typical speed     | Should Have  |
| R-05 | Export GPX         | Download any trip as GPX for third-party apps                | Nice to Have |

---

### 3.4 AI Suggestion Engine (Local / Free)

All AI logic runs locally — rule-based + lightweight scoring. No paid API required. Uses OSM Overpass API for POI discovery.

| ID    | Feature                  | Logic / Description                                                                               | Priority     |
|-------|--------------------------|---------------------------------------------------------------------------------------------------|--------------|
| AI-01 | Nearby POI Recs          | Overpass radius query → score by distance + category preference + time-of-day                    | Must Have    |
| AI-02 | Unvisited Place Alert    | Cross-reference POIs with visited_places; push card for unvisited within 10km                    | Must Have    |
| AI-03 | Best Time Window         | Open-Meteo weather + distance + crowd heuristic → "Best in next 2 hours"                         | Should Have  |
| AI-04 | Low Traffic Route        | Compare recorded speeds on segments → flag congested roads → suggest alternate OSRM route        | Should Have  |
| AI-05 | Destination Prediction   | Weekday/weekend pattern + most visited POI category + geo-cluster of frequent destinations        | Nice to Have |
| AI-06 | Personalised Itinerary   | Given destination + hours available → ranked POI list using scoring model                        | Nice to Have |

**POI Scoring Formula:**
```
score(poi) =
  (1 / distance_km)               × 0.40
  + category_affinity(user, type) × 0.35
  + popularity_score(poi)         × 0.15
  + weather_bonus(poi, forecast)  × 0.10
```

**Category Affinity:** Computed from visited_places history. Each category (museum, park, restaurant, etc.) receives a normalised weight 0–1 based on frequency of past visits. New users get equal weights (cold start = uniform distribution).

**Destination Prediction Logic:**
- Cluster past GPS endpoints by k-means (k=5 default)
- Identify weekday vs weekend travel patterns from travel_logs
- Weight clusters by recency (exponential decay, half-life = 30 days)
- Return top-3 predicted destinations with confidence %

---

### 3.5 Travel Level & Gamification System

**XP Events:**
- Visit new village → +10 XP
- Visit new city → +25 XP
- Visit new state/province → +50 XP
- Visit new country → +200 XP
- Travel 50km in one day → +20 XP
- Complete a trip plan → +15 XP
- 7-day travel streak → +30 XP
- Upload trip photo → +5 XP
- First group trip → +40 XP

**Level Ladder:**
- Level 1 — Traveler (0 XP)
- Level 2 — Explorer (100 XP)
- Level 3 — Adventurer (500 XP)
- Level 4 — Roadmaster (1,500 XP)
- Level 5 — Global Nomad (5,000 XP)
- Level 6 — Legend (15,000 XP) [NEW]

**Badge System (User-Suggested):**

| Badge               | Trigger                              | XP Bonus |
|---------------------|--------------------------------------|----------|
| Early Bird          | Travel before 6 AM (5 trips)         | +25 XP   |
| Night Owl           | Travel after 10 PM (5 trips)         | +25 XP   |
| Continent Collector | Visit 3+ continents                  | +150 XP  |
| Speed Demon         | Avg speed >120 km/h on highway trip  | +30 XP   |
| Team Player         | Complete 3 group trips               | +50 XP   |
| Storyteller         | Add photos to 10 trips               | +40 XP   |
| Streak Master       | 30-day travel streak                 | +100 XP  |

---

### 3.6 Travel Statistics Dashboard

Powered by fl_chart. All data queried from Supabase with client-side aggregation fallback.

| Widget                   | Data Source                                  | Chart Type                    |
|--------------------------|----------------------------------------------|-------------------------------|
| Total Distance           | SUM(distance) from travel_logs               | Stat card + sparkline         |
| Monthly Travel Graph     | GROUP BY month from travel_logs              | Bar chart (fl_chart)          |
| Travel Heatmap           | lat/lng clusters from travel_logs            | flutter_map + heatmap layer   |
| Countries / Cities       | COUNT from visited_countries/cities          | World map choropleth + counter|
| Average Speed            | AVG(speed) from travel_logs                  | Gauge chart                   |
| Longest Trip             | MAX(distance) from routes                    | Stat card                     |
| Time Travelling          | SUM(duration) from routes                    | Donut chart by transport mode |
| Year in Review [NEW]     | Aggregated yearly stats                      | Animated summary card         |

---

### 3.7 Live Group Travel Sync

Supabase Realtime (PostgreSQL logical replication) powers sub-second checklist and location sync across group members.

| ID   | Feature               | Description                                                       | Priority     |
|------|-----------------------|-------------------------------------------------------------------|--------------|
| G-01 | Create Travel Group   | Generate 6-char invite code; invite via link or QR               | Must Have    |
| G-02 | Shared To-Do List     | CRUD tasks; check/uncheck syncs in real time to all members      | Must Have    |
| G-03 | Trip Plan             | Destination, date range, budget, member list, packing checklist  | Must Have    |
| G-04 | Live Member Map       | Opt-in: show member locations on shared map in real time         | Should Have  |
| G-05 | Budget Tracker [NEW]  | Split expenses, add receipts, see who owes what                  | Should Have  |
| G-06 | Group Chat [NEW]      | In-app messaging thread per group via Supabase Realtime          | Nice to Have |
| G-07 | Voting / Polls [NEW]  | Group votes on destination or activity options                   | Nice to Have |

---

### 3.8 User-Suggested Features ⭐

These features were sourced from direct user interviews and community feedback:

| Feature                    | User Pain Point Solved                                                   | Release |
|----------------------------|--------------------------------------------------------------------------|---------|
| Trip Photo Journal         | "I want to attach memories to specific GPS points on my route"           | v1.1    |
| Weather Integration        | "Warn me before I set off if weather is bad at my destination"           | v1.0    |
| Transport Mode Detection   | "Auto-detect if I'm walking, cycling, or driving"                        | v1.1    |
| Trip Cost Estimator        | "How much did this road trip cost in fuel?"                              | v1.2    |
| Travel Calendar View       | "Show all my trips in a calendar heat-map like GitHub"                   | v1.1    |
| Smart Reminders            | "Remind me to take photos at tourist spots"                              | v1.2    |
| Global Leaderboard         | "I want to compare XP with other travellers globally"                    | v1.2    |
| Instagram Story Export     | "Generate a shareable route card I can post on Instagram"                | v1.3    |
| QR Group Join              | "Joining a group by typing a code is annoying — use QR"                  | v1.0    |
| Future Trip Planner        | "Let me plan a trip before I leave, not just track after"                | v1.2    |
| Offline Maps Download      | "I travel to remote areas with no signal — I need offline maps"          | v2.0    |
| AI Trip Summariser         | "Write a summary of my trip so I can share it"                           | v2.0    |

---

## 4. DATABASE SCHEMA (SUPABASE / POSTGRESQL)

### users
```
id                  uuid PK             auth.users FK
username            text UNIQUE NOT NULL URL slug
full_name           text
bio                 text
avatar_url          text                Supabase Storage path
travel_level        smallint DEFAULT 1  1–6
total_xp            int DEFAULT 0
total_distance_km   numeric(10,2)
countries_visited   int DEFAULT 0       Denormalised counter
cities_visited      int DEFAULT 0       Denormalised counter
is_public           bool DEFAULT true   Public profile toggle
created_at          timestamptz
```

### travel_logs
```
id              bigserial PK
user_id         uuid FK → users
latitude        double precision NOT NULL
longitude       double precision NOT NULL
altitude_m      real
speed_kmh       real
heading         real                    Degrees 0–360
accuracy_m      real                    GPS accuracy
city            text                    From Nominatim
state           text
country         text
country_code    char(2)                 ISO 3166-1 alpha-2
transport_mode  text                    walk/bike/car/train
recorded_at     timestamptz NOT NULL    Device timestamp
synced_at       timestamptz             Server arrival
```

### visited_cities / visited_states / visited_countries
```
id                bigserial PK
user_id           uuid FK → users
name              text NOT NULL
country_code      char(2)
lat               double precision        Centroid
lng               double precision        Centroid
first_visited_at  timestamptz
visit_count       int DEFAULT 1
xp_awarded        bool DEFAULT false      Prevent double XP
```

### routes
```
id              bigserial PK
user_id         uuid FK → users
name            text                    Auto or user-named
polyline        text                    Encoded Google Polyline
distance_km     numeric(10,2)
duration_min    int
avg_speed_kmh   real
start_lat       double precision
start_lng       double precision
end_lat         double precision
end_lng         double precision
started_at      timestamptz
ended_at        timestamptz
transport_mode  text
```

### travel_groups
```
id            uuid PK DEFAULT gen_random_uuid()
owner_id      uuid FK → users
name          text NOT NULL
invite_code   char(6) UNIQUE
destination   text
trip_date     daterange
budget        numeric(12,2)
created_at    timestamptz
```

### group_members
```
group_id      uuid FK → travel_groups    Composite PK
user_id       uuid FK → users            Composite PK
role          text DEFAULT 'member'      owner/member
joined_at     timestamptz
```

### group_todos
```
id            bigserial PK
group_id      uuid FK → travel_groups
created_by    uuid FK → users
text          text NOT NULL
is_done       bool DEFAULT false
assigned_to   uuid FK → users NULLABLE
created_at    timestamptz
updated_at    timestamptz
```

### achievements
```
id            bigserial PK
user_id       uuid FK → users
badge_key     text NOT NULL              e.g. 'early_bird'
earned_at     timestamptz DEFAULT now()
```

### xp_history
```
id            bigserial PK
user_id       uuid FK → users
delta         int NOT NULL               +/- XP change
reason        text                       Human-readable event
ref_id        bigint NULLABLE            FK to log/route/etc
created_at    timestamptz DEFAULT now()
```

---

## 5. TECHNICAL ARCHITECTURE

### 5.1 Clean Architecture Layers

```
lib/
  presentation/       Flutter widgets, screens, Riverpod providers
  domain/             Entities, use-cases, repository interfaces
  data/               Supabase datasources, Drift local DB, DTOs
  services/           Location, background worker, Nominatim, OSRM, Overpass
  core/               Router, theme, error handling, constants
```

### 5.2 Key Dependencies (pubspec.yaml)

```yaml
supabase_flutter:   ^2.x    # Auth, Database, Realtime, Storage
flutter_riverpod:   ^2.x    # State management
flutter_map:        ^6.x    # OSM map rendering
latlong2:           ^0.9    # Geo utilities
geolocator:         ^11.x   # GPS access
workmanager:        ^0.5.x  # Background tasks
fl_chart:           ^0.66   # Charts & graphs
drift:              ^2.x    # Local SQLite ORM
go_router:          ^13.x   # Navigation
freezed:            ^2.x    # Immutable models
image_picker:       ^1.x    # Avatar / trip photos
share_plus:         ^7.x    # Share route cards
qr_flutter:         ^4.x    # Group invite QR codes
mobile_scanner:     ^4.x    # Scan QR codes
http:               ^1.x    # OSRM / Nominatim / Overpass
```

### 5.3 Free API Stack

| API                   | Use Case            | Endpoint                                        |
|-----------------------|---------------------|-------------------------------------------------|
| OSM Nominatim         | Reverse geocoding   | nominatim.openstreetmap.org/reverse             |
| OSRM                  | Routing & distance  | router.project-osrm.org/route/v1                |
| Overpass API          | POI discovery       | overpass-api.de/api/interpreter                 |
| Open-Meteo            | Weather forecasts   | api.open-meteo.com/v1/forecast                  |
| OSM Tile Server       | Map tiles           | tile.openstreetmap.org/{z}/{x}/{y}.png          |

---

## 6. NON-FUNCTIONAL REQUIREMENTS

| Category      | Requirement                    | Target                                  |
|---------------|--------------------------------|-----------------------------------------|
| Performance   | App cold start                 | <2 seconds on mid-range Android         |
| Performance   | Map tile render                | <300ms with cached tiles                |
| Performance   | Realtime latency               | <500ms end-to-end                       |
| Battery       | Background tracking overhead   | <5% extra drain per hour                |
| Security      | Transit encryption             | TLS 1.3 on all requests                 |
| Security      | Row Level Security             | Supabase RLS on every table             |
| Privacy       | Tracking pause                 | Accessible in 2 taps or fewer           |
| Privacy       | GDPR data export               | JSON download within 30 days            |
| Offline       | Location queueing              | Store up to 72 hours of points locally  |
| Scalability   | Supabase free tier             | Designed for 500 MB DB, 1 GB storage    |
| Accessibility | WCAG 2.1 AA                    | Contrast ratio 4.5:1, scalable text     |

---

## 7. RELEASE ROADMAP

**v1.0 MVP — Month 1–3**
Auth, background tracking, OSM map, route display, XP system, group to-do, public profile, weather widget, QR group join, privacy toggle.

**v1.1 — Month 4–5**
Trip photo journal, transport mode detection, travel calendar heatmap, AI unvisited place alert, full badge system.

**v1.2 — Month 6–7**
Budget tracker, trip cost estimator, smart reminders, global leaderboard, future trip planner.

**v1.3 — Month 8–9**
Instagram story export card, group chat, polls/voting, destination prediction AI.

**v2.0 — Month 10–12**
Offline map download, AI trip summariser, Legend level (Lv 6), social feed, Apple Watch companion app.

---

## 8. PRIVACY & COMPLIANCE

**Data Minimisation:**
- Location points skipped if displacement <100m
- Speed set to null when stationary >5 minutes
- Precise lat/lng fuzzy-rounded to 4 decimal places on public profile API

**User Controls:**

| Control                     | Where                                          |
|-----------------------------|------------------------------------------------|
| Pause / resume tracking     | Home screen quick-toggle + Settings            |
| Delete all location history | Settings → Privacy → Wipe Location Data        |
| Export my data (GDPR)       | Settings → Export → JSON download              |
| Make profile private        | Settings → Privacy → Public Profile toggle     |
| Delete account              | Settings → Delete Account (cascades all data)  |

---

## 9. RISKS & OPEN QUESTIONS

| Risk                                    | Mitigation                                                        | Owner   |
|-----------------------------------------|-------------------------------------------------------------------|---------|
| Nominatim rate limit (1 req/s)          | Client-side debounce + local city cache                          | Backend |
| OSRM public instance downtime           | Self-host OSRM Docker as fallback; straight-line distance failover | Infra  |
| iOS background location restrictions   | Significant Location Change mode + "Always Allow" prompt flow    | Mobile  |
| Supabase free tier row limits           | Auto-archive logs older than 1 year to cold storage table        | Backend |
| GDPR compliance for EU users            | Consent banner; Supabase EU region; privacy policy               | Legal   |

---

*TravelSync PRD — Confidential — v1.0 — March 2026*