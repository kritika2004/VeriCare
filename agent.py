import os
import json
import time
import requests
from dotenv import load_dotenv

load_dotenv()

DATABRICKS_HOST = os.getenv("DATABRICKS_HOST")
DATABRICKS_TOKEN = os.getenv("DATABRICKS_TOKEN")
WAREHOUSE_ID = os.getenv("WAREHOUSE_ID")
LLM_ENDPOINT = os.getenv("LLM_ENDPOINT", "databricks-meta-llama-3-3-70b-instruct")


def _headers():
    return {
        "Authorization": f"Bearer {DATABRICKS_TOKEN}",
        "Content-Type": "application/json",
    }


SQL_SYSTEM = """You are a SQL expert for VeriCare — India's healthcare facility database on Databricks Unity Catalog.

## TABLE: workspace.default.clean_facilities

Key columns:
- name, facilityTypeId, description, full_text_blob  (rich text — LLM reads these to answer questions)
- address_city, address_stateOrRegion, address_line1, address_postalCode
- latitude (string), longitude (string)
- clean_phone, email, officialWebsite
- specialties (array<string>), procedure (array<string>), equipment (array<string>)
- has_emergency, has_icu, has_obg, has_surgery, has_pharmacy, has_lab (boolean — often NULL, don't rely on these)
- numberDoctors (int), facility_id

facilityTypeId values: 'hospital', 'clinic', 'dentist', 'doctor', 'pharmacy'

## QUERY RULES

**Always SELECT **** — return full rows so the LLM can read description, full_text_blob, specialties.

**Keep WHERE simple** — filter only by location and optionally facilityTypeId. Do NOT filter on boolean capability columns (has_icu, has_emergency etc.) — those are sparse and unreliable. Let the LLM read the text to determine capabilities.

**Location matching** — always use LOWER() + LIKE:
  LOWER(address_stateOrRegion) LIKE '%bihar%'
  LOWER(address_city) LIKE '%patna%'

**Facility type** — only filter facilityTypeId when the user explicitly says "hospital", "clinic", "dentist", "pharmacy", "doctor":
  facilityTypeId = 'hospital'

**Ordering** — always: ORDER BY CASE WHEN clean_phone IS NOT NULL THEN 1 ELSE 2 END, name

**Limit** — always LIMIT 20 (enough for the LLM to read and reason about)

## QUERY PATTERNS

Single location:
  SELECT * FROM workspace.default.clean_facilities
  WHERE LOWER(address_stateOrRegion) LIKE '%bihar%'
  ORDER BY CASE WHEN clean_phone IS NOT NULL THEN 1 ELSE 2 END, name
  LIMIT 20

With facility type:
  SELECT * FROM workspace.default.clean_facilities
  WHERE LOWER(address_city) LIKE '%mumbai%' AND facilityTypeId = 'hospital'
  ORDER BY CASE WHEN clean_phone IS NOT NULL THEN 1 ELSE 2 END, name
  LIMIT 20

Comparing two states/cities (wrap each in a subquery before UNION ALL):
  SELECT * FROM (
    SELECT *, 'Bihar' AS queried_region FROM workspace.default.clean_facilities
    WHERE LOWER(address_stateOrRegion) LIKE '%bihar%' AND facilityTypeId = 'hospital'
    ORDER BY CASE WHEN clean_phone IS NOT NULL THEN 1 ELSE 2 END LIMIT 10
  )
  UNION ALL
  SELECT * FROM (
    SELECT *, 'Uttar Pradesh' AS queried_region FROM workspace.default.clean_facilities
    WHERE LOWER(address_stateOrRegion) LIKE '%uttar pradesh%' AND facilityTypeId = 'hospital'
    ORDER BY CASE WHEN clean_phone IS NOT NULL THEN 1 ELSE 2 END LIMIT 10
  )

Count by state/city (analytics only):
  SELECT address_stateOrRegion, COUNT(*) AS total
  FROM workspace.default.clean_facilities
  GROUP BY address_stateOrRegion ORDER BY total DESC LIMIT 15

## OUTPUT
Return ONLY valid JSON, no markdown, no explanation:
{"sql": "SELECT ...", "is_emergency": false}

Set is_emergency=true if the question contains: emergency, urgent, bleeding, chest pain, not breathing,
labour, stroke, heart attack, accident, critical, unconscious, dying."""

PRESENT_SYSTEM = """You are VeriCare Intelligence — an AI healthcare routing assistant for underserved India.

You are given full facility rows including description, specialties, procedure, and full_text_blob.
READ these text fields to determine what a facility actually offers and answer the user's question intelligently.

RULES:
- If is_emergency=true, ALWAYS start with: ⚠️ LIFE-THREATENING EMERGENCY — CALL 108 IMMEDIATELY
- If no facilities found, say so clearly — never invent facilities
- Answer the user's actual question first (e.g. "Yes, there are X hospitals with ICU in Delhi based on their descriptions")
- For comparisons (two states/cities), directly compare: counts, types, notable facilities
- List top 3-5 relevant facilities: name, city, phone (or "no phone listed"), and one line on what they offer
- Warn if many facilities lack phone numbers
- Keep response under 250 words
- Recommend calling ahead to confirm before traveling"""


def call_llm(system: str, user: str, max_tokens: int = 1024) -> str:
    payload = {
        "messages": [
            {"role": "system", "content": system},
            {"role": "user", "content": user},
        ],
        "max_tokens": max_tokens,
        "temperature": 0,
    }
    resp = requests.post(
        f"{DATABRICKS_HOST}/serving-endpoints/{LLM_ENDPOINT}/invocations",
        headers=_headers(),
        json=payload,
        timeout=60,
    )
    resp.raise_for_status()
    return resp.json()["choices"][0]["message"]["content"].strip()


def run_sql(sql: str) -> list:
    resp = requests.post(
        f"{DATABRICKS_HOST}/api/2.0/sql/statements",
        headers=_headers(),
        json={"statement": sql, "warehouse_id": WAREHOUSE_ID, "wait_timeout": "50s"},
        timeout=90,
    )
    resp.raise_for_status()
    data = resp.json()

    statement_id = data["statement_id"]
    for _ in range(30):
        if data["status"]["state"] not in ("PENDING", "RUNNING"):
            break
        time.sleep(2)
        r = requests.get(
            f"{DATABRICKS_HOST}/api/2.0/sql/statements/{statement_id}",
            headers=_headers(),
            timeout=30,
        )
        r.raise_for_status()
        data = r.json()

    if data["status"]["state"] != "SUCCEEDED":
        raise RuntimeError(f"Query failed: {data['status']}")

    columns = [c["name"] for c in data["manifest"]["schema"]["columns"]]
    rows = data["result"].get("data_array", [])
    return [dict(zip(columns, row)) for row in rows]


def _parse_llm_json(raw: str) -> dict:
    clean = raw.strip()
    for fence in ("```json", "```"):
        if clean.startswith(fence):
            clean = clean[len(fence):]
    clean = clean.removesuffix("```").strip()
    return json.loads(clean)


def _extract_facilities(rows: list) -> list:
    out = []
    for r in rows:
        try:
            lat = float(r.get("latitude") or 0)
            lng = float(r.get("longitude") or 0)
            if not (lat and lng):
                continue
            out.append({
                "facility_id": r.get("facility_id"),
                "name": r.get("name", "Unknown"),
                "address": ", ".join(filter(None, [
                    r.get("address_line1"),
                    r.get("address_city"),
                    r.get("address_stateOrRegion"),
                ])),
                "city": r.get("address_city"),
                "phone": r.get("clean_phone"),
                "type": r.get("facilityTypeId"),
                "has_emergency": r.get("has_emergency") in (True, "true", "True"),
                "has_icu": r.get("has_icu") in (True, "true", "True"),
                "has_obg": r.get("has_obg") in (True, "true", "True"),
                "has_surgery": r.get("has_surgery") in (True, "true", "True"),
                "lat": lat,
                "lng": lng,
            })
        except (TypeError, ValueError):
            continue
    return out


def _map_config(facilities: list) -> dict:
    if not facilities:
        return {"center": [20.5937, 78.9629], "zoom": 5}
    lats = [f["lat"] for f in facilities]
    lngs = [f["lng"] for f in facilities]
    center = [sum(lats) / len(lats), sum(lngs) / len(lngs)]
    spread = max(lats) - min(lats)
    zoom = 12 if spread < 0.2 else (10 if spread < 1 else (8 if spread < 3 else 6))
    return {"center": center, "zoom": zoom}


def process_question(question: str) -> dict:
    # Step 1: LLM → SQL
    raw = call_llm(SQL_SYSTEM, question)
    parsed = _parse_llm_json(raw)
    sql = parsed["sql"]
    is_emergency = bool(parsed.get("is_emergency", False))

    # Step 2: Execute SQL
    results = run_sql(sql)

    # Step 3: LLM → natural language answer
    context = (
        f"User question: {question}\n"
        f"is_emergency: {is_emergency}\n"
        f"SQL used: {sql}\n"
        f"Total results: {len(results)}\n"
        f"Data (first 20 rows): {json.dumps(results[:20], indent=2)}"
    )
    answer = call_llm(PRESENT_SYSTEM, context, max_tokens=512)

    facilities = _extract_facilities(results)

    return {
        "answer": answer,
        "facilities": facilities,
        "map": _map_config(facilities),
        "is_emergency": is_emergency,
        "sql_used": sql,
        "result_count": len(results),
    }
