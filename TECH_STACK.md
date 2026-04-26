# VeriCare — Technical Implementation

## Overview

VeriCare is an AI-powered healthcare facility routing and intelligence platform for India. Users ask natural language questions about healthcare facilities; an AI agent generates SQL via **Databricks Mosaic AI**, executes it against a **Databricks SQL Warehouse**, validates the response with a second model on **Databricks Mosaic AI Model Serving**, and returns an interactive map with trust-scored results.

---

## Tech Stack

### Backend

| Component | Technology | Version |
|-----------|------------|---------|
| Web Framework | FastAPI | 0.115.0 |
| ASGI Server | Uvicorn | 0.30.6 |
| Language | Python | 3.x |
| HTTP Client | Requests | 2.32.3 |
| Data Validation | Pydantic | 2.9.2 |
| Env Management | python-dotenv | 1.0.1 |

### Frontend

| Component | Technology | Version |
|-----------|------------|---------|
| Language | TypeScript | 5.5.0 |
| Bundler | ESBuild | 0.21.0 |
| Mapping | Leaflet.js | 1.9.4 |
| Markdown Rendering | Marked.js | 18.0.2 |
| Styles | Custom CSS3 | — |

### AI / LLMs — Databricks Mosaic AI

Both LLMs are served via **Databricks Mosaic AI Model Serving** endpoints with no external AI provider dependency.

| Role | Model | Serving Platform |
|------|-------|-----------------|
| SQL Generation + Response Generation | Meta Llama 3.3 70B Instruct | **Databricks Mosaic AI Model Serving** |
| Answer Validation + Trust Scoring | Meta Llama 3.1 405B Instruct | **Databricks Mosaic AI Model Serving** |

Calls go to the **Databricks `/serving-endpoints/{endpoint}/invocations`** API using an OpenAI-compatible `/chat/completions` interface.

### Data Platform — Databricks

| Component | Technology |
|-----------|------------|
| Data Warehouse | **Databricks SQL Warehouse** |
| Table Format | **Delta Lake** |
| Query API | **Databricks SQL Statements REST API** (`/api/2.0/sql/statements`) |
| Data Cleaning Pipeline | **Databricks Notebooks** (PySpark / Databricks Runtime) |
| Primary Table | `workspace.default.clean_facilities` |
| Coverage | ~10,000 facilities, 29+ states across India |
| Basemap | CARTO Light (via Leaflet tile layer) |

### Analytics

| Component | Technology |
|-----------|------------|
| Dashboard | R Shiny (hosted on shinyapps.io) |

---

## Architecture

```
┌──────────────────────────────────────────────────────────────────────┐
│                          Browser (Client)                             │
│                                                                        │
│  ┌──────────────────────┐     ┌──────────────────────────────────┐   │
│  │      Chat Panel       │     │     Map Panel (Leaflet.js)       │   │
│  │  (src/chat.ts)        │     │     (src/map.ts)                 │   │
│  │  - Message history    │     │  - CARTO basemap tiles           │   │
│  │  - Suggestion chips   │     │  - Color-coded markers           │   │
│  │  - Trust score strip  │     │  - Facility popups               │   │
│  │  - Emergency banner   │     │  - Auto-center / zoom            │   │
│  └──────────┬───────────┘     └──────────────────────────────────┘   │
│             │ POST /chat                                                │
└─────────────┼──────────────────────────────────────────────────────┘
              │
┌─────────────▼──────────────────────────────────────────────────────┐
│                   FastAPI Backend (main.py / agent.py)               │
│                                                                       │
│   Routes: GET /health    POST /chat    GET / (static files)          │
│                                                                       │
│   agent.py  →  process_question()                                    │
│      Step 1: SQL Generation                                          │
│      Step 2: SQL Execution                                           │
│      Step 3: Response Generation                                     │
│      Step 4: Validation + Trust Score                                │
│      Step 5: Facility Extraction                                     │
│      Step 6: Map Config Calculation                                  │
└──────────────┬────────────────────────────────────────────────────┘
               │
     ┌─────────┼────────────────────────┐
     │         │                        │
     ▼         ▼                        ▼
┌─────────────────────┐   ┌──────────────────────────────────────────┐
│  Databricks         │   │  Databricks Mosaic AI Model Serving       │
│  SQL Warehouse      │   │                                           │
│                     │   │  ┌─────────────────────────────────────┐  │
│  /api/2.0/sql/      │   │  │ Llama 3.3 70B Instruct              │  │
│  statements         │   │  │  - SQL generation (Steps 1)         │  │
│                     │   │  │  - Response generation (Step 3)     │  │
│  Table:             │   │  └─────────────────────────────────────┘  │
│  workspace.default. │   │                                           │
│  clean_facilities   │   │  ┌─────────────────────────────────────┐  │
│  (Delta Lake)       │   │  │ Llama 3.1 405B Instruct             │  │
│  ~10K rows          │   │  │  - Validation + trust score (Step 4)│  │
└─────────────────────┘   │  └─────────────────────────────────────┘  │
     │                    └──────────────────────────────────────────┘
     │
┌────▼──────────────────────────────────────────────────────────────┐
│           Databricks Data Platform (Offline Pipeline)              │
│                                                                     │
│   Databricks Notebooks (PySpark / Databricks Runtime)             │
│   Raw facility data ──► clean_facilities Delta table               │
│                                                                     │
│   Pipeline stages:                                                  │
│   1. Ingest raw records                                            │
│   2. De-duplicate (name + address)                                 │
│   3. Normalize Indian addresses & pincodes                         │
│   4. Validate / impute lat-lng                                     │
│   5. Standardize phone numbers → clean_phone                       │
│   6. Extract capabilities → has_* flags + arrays                   │
│   7. Build full_text_blob for LLM context                          │
│   8. Write Delta Lake table to Databricks SQL Warehouse            │
└────────────────────────────────────────────────────────────────────┘
```

---

## Data Flow: User Query to Map Response

```
User types question
        │
        ▼
POST /chat { "question": "..." }
        │
        ▼
[Step 1] SQL Generation — Databricks Mosaic AI (Llama 3.3 70B)
   API:    POST /serving-endpoints/{LLM_ENDPOINT}/invocations
   System: SQL_SYSTEM prompt (clean_facilities schema + query rules)
   Input:  user question
   Output: { "sql": "SELECT * FROM workspace.default.clean_facilities WHERE ...", "is_emergency": false }
        │
        ▼
[Step 2] SQL Execution — Databricks SQL Warehouse
   API:    POST /api/2.0/sql/statements
   Auth:   Bearer DATABRICKS_TOKEN
   Params: warehouse_id = WAREHOUSE_ID, wait_timeout = "30s"
   Output: rows[] (up to 20 facilities from Delta Lake table)
        │
        ▼
[Step 3] Response Generation — Databricks Mosaic AI (Llama 3.3 70B)
   API:    POST /serving-endpoints/{LLM_ENDPOINT}/invocations
   System: PRESENT_SYSTEM prompt
   Input:  user question + SQL Warehouse results (JSON)
   Output: human-readable markdown answer
        │
        ▼
[Step 4] Validation — Databricks Mosaic AI (Llama 3.1 405B)
   API:    POST /serving-endpoints/{VALIDATE_ENDPOINT}/invocations
   System: VALIDATE_SYSTEM prompt
   Input:  user question + answer + raw warehouse rows
   Output: { "trust_score": 92, "is_accurate": true, "note": "..." }
        │
        ▼
[Step 5] Facility Extraction
   Parse lat/lng, contact, capabilities from Databricks SQL Warehouse rows
   Build Facility[] list for map rendering
        │
        ▼
[Step 6] Map Config Calculation
   Center = mean(lat), mean(lng) across all returned facilities
   Zoom   = function of latitude spread
              < 0.2° → 12 (city)
              < 1°   → 10 (district)
              < 3°   → 8  (state)
              ≥ 3°   → 6  (multi-state)
        │
        ▼
JSON Response:
{
  "answer": "...",
  "facilities": [...],
  "map": { "center": [...], "zoom": 10 },
  "is_emergency": false,
  "trust_score": 92,
  "validation_note": "..."
}
```

---

## Databricks SQL Warehouse — `clean_facilities` Schema

**Table**: `workspace.default.clean_facilities` (Delta Lake)

| Column | Type | Description |
|--------|------|-------------|
| `facility_id` | string | Unique identifier |
| `name` | string | Facility display name |
| `facilityTypeId` | string | `hospital`, `clinic`, `dentist`, `doctor`, `pharmacy` |
| `description` | string | Human-readable description |
| `full_text_blob` | string | Rich text for Databricks Mosaic AI context (capabilities, specialties, etc.) |
| `address_city` | string | City |
| `address_stateOrRegion` | string | State or region |
| `address_line1` | string | Street address |
| `address_postalCode` | string | Postal code |
| `latitude` | string | Latitude (converted to float at query time) |
| `longitude` | string | Longitude (converted to float at query time) |
| `clean_phone` | string | Standardized phone number (from Databricks pipeline) |
| `email` | string | Contact email |
| `officialWebsite` | string | Website URL |
| `specialties` | array | Medical specialties |
| `procedure` | array | Procedures offered |
| `equipment` | array | Medical equipment |
| `has_emergency` | boolean (nullable) | Emergency flag (unreliable; prefer `full_text_blob`) |
| `has_icu` | boolean (nullable) | ICU flag |
| `has_obg` | boolean (nullable) | OB/GYN flag |
| `has_surgery` | boolean (nullable) | Surgery flag |
| `has_pharmacy` | boolean (nullable) | In-house pharmacy flag |
| `has_lab` | boolean (nullable) | Lab services flag |
| `numberDoctors` | int | Physician count |

> **Query strategy**: The Databricks Mosaic AI (Llama 3.3 70B) always generates `SELECT *` with a `LIMIT 20`, filtering only on location and facility type. Capability detection is delegated back to the LLM, which reads `full_text_blob` and `description` — boolean flags are too sparse to be reliable. Location filters use `LOWER(col) LIKE '%term%'` for fuzzy matching across the **Databricks SQL Warehouse**.

---

## Databricks Data Cleaning Pipeline

The raw healthcare facility dataset was prepared entirely in a **Databricks Notebook** using PySpark on **Databricks Runtime** before being written as a **Delta Lake** table.

**Pipeline stages:**

1. **Ingestion** — Load raw facility records into a Databricks Notebook (CSV / API / staging Delta table)
2. **De-duplication** — PySpark: remove duplicates by name + address proximity
3. **Address Normalization** — Standardize city, state, pincode formats for Indian addresses
4. **Coordinate Validation** — Validate and impute lat/lng; flag records outside India's bounding box
5. **Phone Cleaning** — Strip non-numeric characters, normalize to E.164-like format → `clean_phone`
6. **Capability Extraction** — Parse description text to populate `has_*` boolean flags and array columns
7. **`full_text_blob` Construction** — Concatenate name, address, description, specialties into a single column optimized for **Databricks Mosaic AI** LLM context
8. **Delta Lake Write** — Write final dataset to `workspace.default.clean_facilities` on the **Databricks SQL Warehouse**

---

## Databricks Mosaic AI Model Serving — API Details

Both LLMs are called via the **Databricks Model Serving REST API**, using an OpenAI-compatible interface:

```
POST https://{DATABRICKS_HOST}/serving-endpoints/{endpoint_name}/invocations

Headers:
  Authorization: Bearer {DATABRICKS_TOKEN}
  Content-Type: application/json

Body:
{
  "messages": [
    { "role": "system", "content": "..." },
    { "role": "user",   "content": "..." }
  ],
  "max_tokens": 1024,
  "temperature": 0
}
```

**Endpoints used:**

| Endpoint Name | Model | Use |
|---------------|-------|-----|
| `databricks-meta-llama-3-3-70b-instruct` | Meta Llama 3.3 70B Instruct | SQL generation, response generation |
| `databricks-meta-llama-3.1-405b-instruct` | Meta Llama 3.1 405B Instruct | Answer validation, trust scoring |

---

## Frontend Architecture

**Source files** (`src/`):

| File | Class / Module | Responsibility |
|------|---------------|----------------|
| `main.ts` | — | App init, tab routing (Pulse / Analytics), event wiring |
| `chat.ts` | `ChatUI` | Message rendering, calls to `/chat`, markdown via Marked.js, emergency banner, trust score strip |
| `map.ts` | `FacilityMap` | Leaflet map init, facility marker rendering, popups, map config from Databricks SQL results |
| `types.ts` | interfaces | `Facility`, `MapConfig`, `ChatResponse` TypeScript types |

**Build**: ESBuild compiles `src/` → `static/bundle.js` (minified IIFE, ES2020).

**Map Marker Colors** (derived from Databricks SQL Warehouse facility data):

| Color | Hex | Condition |
|-------|-----|-----------|
| Red | `#F43F5E` | Emergency capability |
| Purple | `#8B5CF6` | ICU capability |
| Green | `#10B981` | Government facility |
| Cyan | `#38BDF8` | Default |

Priority order: Emergency > ICU > Government > Default.

---

## API Reference

### `POST /chat`

**Request**:
```json
{ "question": "Find hospitals with ICU in Pune" }
```

**Response**:
```json
{
  "answer": "Here are hospitals with ICU in Pune...",
  "facilities": [
    {
      "name": "Ruby Hall Clinic",
      "lat": 18.532,
      "lng": 73.847,
      "address": "40 Sassoon Road, Pune",
      "phone": "+912066455555",
      "type": "hospital",
      "capabilities": ["ICU", "Emergency", "Surgery"]
    }
  ],
  "map": { "center": [18.532, 73.847], "zoom": 12 },
  "is_emergency": false,
  "trust_score": 88,
  "validation_note": "All facility names and phone numbers verified against Databricks SQL Warehouse source data."
}
```

### `GET /health`

Returns `{ "status": "ok" }`.

---

## Environment Variables

| Variable | Description |
|----------|-------------|
| `DATABRICKS_HOST` | Databricks workspace URL |
| `DATABRICKS_TOKEN` | Databricks personal access token |
| `WAREHOUSE_ID` | Databricks SQL Warehouse ID |
| `LLM_ENDPOINT` | Databricks Mosaic AI serving endpoint name — Llama 3.3 70B |
| `VALIDATE_ENDPOINT` | Databricks Mosaic AI serving endpoint name — Llama 3.1 405B (optional) |

---

## Local Development

```bash
# Backend
pip install -r requirements.txt
cp .env.example .env   # fill in Databricks workspace credentials
python main.py         # serves on http://localhost:8000

# Frontend (watch mode)
npm install
npm run dev            # recompiles src/ on change → static/bundle.js

# Frontend (production build)
npm run build
```
