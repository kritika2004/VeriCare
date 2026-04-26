# VeriCare
Challenge 03: Serving A Nation — Building Agentic Healthcare Maps for 1.4 Billion Lives 
AI-powered healthcare facility routing and intelligence platform for India. Ask natural language questions to find, compare, and locate healthcare facilities across 29+ states — results appear on an interactive map with trust-scored, validated answers.

**AI and data infrastructure powered by [Databricks](https://databricks.com).**

---

## Powered by Databricks

VeriCare's intelligence layer runs on **Databricks**:

| Capability | Databricks Product |
|------------|--------------------|
| LLM inference — SQL generation & responses | **Databricks Mosaic AI Model Serving** (Meta Llama 3.3 70B Instruct) |
| LLM inference — answer validation | **Databricks Mosaic AI Model Serving** (Meta Llama 3.1 405B Instruct) |
| Facility data warehouse | **Databricks SQL Warehouse** |
| Data storage | **Delta Lake** on Databricks |
| Data cleaning pipeline | **Databricks Notebooks** (PySpark) |

The LLMs that power VeriCare — Meta Llama 3.3 70B and Llama 3.1 405B — are served directly through **Databricks Mosaic AI Model Serving**, with no external AI provider dependencies. Every SQL query runs against a **Databricks SQL Warehouse** over the **Databricks SQL Statements API**.

---

## What It Does

- **Natural language queries** — "Find hospitals with ICU in Pune" or "Compare cardiac centers in Delhi vs Mumbai"
- **AI-generated SQL via Databricks Mosaic AI** — Meta Llama 3.3 70B (served via Databricks Model Serving) translates your question into SQL, executed on a **Databricks SQL Warehouse** of ~10,000 Indian healthcare facilities
- **Interactive map** — Results plotted on a Leaflet map, color-coded by medical capability (emergency, ICU, government, general)
- **Databricks Mosaic AI trust scoring** — Meta Llama 3.1 405B validates every answer and assigns a confidence score (0–100)
- **Emergency detection** — Life-threatening queries trigger a 108 emergency banner instantly
- **Analytics dashboard** — R Shiny dashboard with facility coverage and access metrics across India

---

## Tech Stack

| Layer | Technology |
|-------|------------|
| Backend | Python 3, FastAPI, Uvicorn |
| Frontend | TypeScript, Leaflet.js, ESBuild, Marked.js |
| AI — SQL Generation & Response | Meta Llama 3.3 70B via **Databricks Mosaic AI Model Serving** |
| AI — Validation & Trust Score | Meta Llama 3.1 405B via **Databricks Mosaic AI Model Serving** |
| Data Warehouse | **Databricks SQL Warehouse** |
| Data Storage | **Delta Lake** on Databricks |
| Data Cleaning Pipeline | **Databricks Notebooks** (PySpark) |
| Analytics | R Shiny (shinyapps.io) |

---

## How It Works

1. **User question** → `POST /chat`
2. **SQL Generation** — **Databricks Mosaic AI** (Llama 3.3 70B) converts the question to SQL using the `clean_facilities` schema
3. **Query Execution** — **Databricks SQL Warehouse** runs the query via the Databricks SQL Statements API (up to 20 results)
4. **Answer Generation** — **Databricks Mosaic AI** (Llama 3.3 70B) produces a natural language answer from the raw warehouse results
5. **Validation** — **Databricks Mosaic AI** (Llama 3.1 405B) cross-checks the answer against source data and returns a trust score
6. **Map Rendering** — Frontend plots facilities as color-coded markers; map auto-centers and zooms to results

See [TECH_STACK.md](TECH_STACK.md) for the full data flow, schema, and API reference.

---

## Data — Cleaned and Served on Databricks

The `clean_facilities` **Delta Lake** table on Databricks contains ~10,000 Indian healthcare facilities (hospitals, clinics, pharmacies, dental, doctors) across 29+ states.

The raw data was prepared in a **Databricks PySpark notebook pipeline**:

- De-duplication and address normalization using Databricks Runtime (PySpark)
- Coordinate validation for India's bounding box
- Phone number standardization
- Capability extraction into a `full_text_blob` column for LLM context
- Final output written as a **Delta Lake** table: `workspace.default.clean_facilities`

At query time, the **Databricks SQL Warehouse** serves this table via the **Databricks SQL Statements REST API**, returning results in milliseconds.

---

## Quick Start

### Prerequisites

- Python 3.9+
- Node.js 18+
- A **Databricks workspace** with:
  - `clean_facilities` Delta table loaded and queryable via a **Databricks SQL Warehouse**
  - **Databricks Mosaic AI Model Serving** endpoints enabled for Llama 3.3 70B and Llama 3.1 405B

### Setup

```bash
git clone https://github.com/your-org/VeriCare.git
cd VeriCare

# Backend
pip install -r requirements.txt

# Create .env (never commit this)
cat > .env << EOF
DATABRICKS_HOST=https://<your-workspace>.cloud.databricks.com
DATABRICKS_TOKEN=<your-databricks-personal-access-token>
WAREHOUSE_ID=<your-databricks-sql-warehouse-id>
LLM_ENDPOINT=databricks-meta-llama-3-3-70b-instruct
VALIDATE_ENDPOINT=databricks-meta-llama-3.1-405b-instruct
EOF

# Frontend
npm install
npm run build

# Start server
python main.py
```

Open [http://localhost:8000](http://localhost:8000).

---

## Project Structure

```
VeriCare/
├── main.py                  # FastAPI app, routes, CORS, static file serving
├── agent.py                 # Core AI orchestration (Databricks Mosaic AI + SQL Warehouse)
├── facility_query_agent.py  # Standalone query agent (dev/testing)
├── requirements.txt         # Python dependencies
├── package.json             # Node dependencies and build scripts
├── tsconfig.json            # TypeScript compiler config
├── src/
│   ├── main.ts              # App init and tab routing
│   ├── chat.ts              # Chat UI, message rendering, Databricks API calls
│   ├── map.ts               # Leaflet map, markers, popups
│   └── types.ts             # TypeScript interfaces
├── static/
│   ├── index.html           # UI shell with embedded styles
│   └── bundle.js            # Compiled frontend (generated by esbuild)
├── TECH_STACK.md            # Detailed technical implementation docs
└── .env                     # Databricks credentials (DO NOT COMMIT)
```

---

## Map Legend

| Color | Meaning |
|-------|---------|
| Red | Emergency capability |
| Purple | ICU capability |
| Green | Government facility |
| Cyan | General / other |

---

## Environment Variables

| Variable | Description |
|----------|-------------|
| `DATABRICKS_HOST` | Databricks workspace URL |
| `DATABRICKS_TOKEN` | Databricks personal access token |
| `WAREHOUSE_ID` | Databricks SQL Warehouse ID |
| `LLM_ENDPOINT` | Databricks Mosaic AI serving endpoint — Llama 3.3 70B |
| `VALIDATE_ENDPOINT` | Databricks Mosaic AI serving endpoint — Llama 3.1 405B (optional) |

---

## Development

```bash
# Watch mode — recompiles TypeScript on change
npm run dev

# Production build
npm run build
```

Backend auto-reloads are not enabled by default; restart `python main.py` after backend changes.

---

## Security Notes

- Never commit `.env` — Databricks credentials must stay out of version control
- Rotate the Databricks personal access token if it has been exposed
- CORS is currently open (`allow_origins=["*"]`); restrict to your deployment origin in production
