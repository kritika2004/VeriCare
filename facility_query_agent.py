import os
import json
import time
import requests

DATABRICKS_HOST = "https://dbc-b0fd8bcb-9965.cloud.databricks.com"
DATABRICKS_TOKEN = os.environ.get("DATABRICKS_TOKEN", "dapi5221b4e2daa979e38929fb4fc98c978f")
WAREHOUSE_ID = "827d15523d65cc03"
LLM_ENDPOINT = "databricks-meta-llama-3-3-70b-instruct"

HEADERS = {
    "Authorization": f"Bearer {DATABRICKS_TOKEN}",
    "Content-Type": "application/json",
}

TABLE_SCHEMA = """
Table: workspace.default.clean_facilities
Columns:
  - facility_id (string): unique ID
  - name (string): facility name
  - address_city (string): city name
  - address_stateOrRegion (string): state or region
  - address_country (string): country
  - address_zipOrPostcode (string): postal code
  - facilityTypeId (string): type of facility
  - operatorTypeId (string): operator type
  - specialties (string): medical specialties offered
  - has_emergency (boolean): has emergency department
  - has_icu (boolean): has ICU
  - has_obg (boolean): has OB/GYN
  - has_surgery (boolean): has surgery
  - has_pharmacy (boolean): has pharmacy
  - has_lab (boolean): has laboratory
  - has_xray (boolean): has X-ray
  - has_ambulance (boolean): has ambulance
  - numberDoctors (int): number of doctors
  - capacity (int): bed capacity
  - latitude (double): GPS latitude
  - longitude (double): GPS longitude
  - description (string): facility description
"""

SYSTEM_PROMPT = f"""You are a SQL expert for a healthcare facility database on Databricks.

{TABLE_SCHEMA}

When asked a question about facilities:
1. Write a single valid Databricks SQL query to answer it.
2. Return ONLY a JSON object in this exact format, nothing else:
{{"sql": "SELECT ..."}}

Rules:
- Use LOWER() and LIKE '%value%' for city/name matching (cities may be spelled differently)
- Always alias aggregates with meaningful names (e.g., COUNT(*) AS facility_count)
- Keep queries simple and correct
- Do not add explanation, only return the JSON
"""

PRESENTER_SYSTEM = """You are a concise data analyst presenting query results about healthcare facilities.
Given a SQL query and its results, explain what was found in 2-3 clear sentences.
Be direct and specific — include the exact numbers from the data."""


def call_llm(system: str, user: str, endpoint: str = LLM_ENDPOINT) -> str:
    payload = {
        "messages": [
            {"role": "system", "content": system},
            {"role": "user", "content": user},
        ],
        "max_tokens": 512,
        "temperature": 0,
    }
    resp = requests.post(
        f"{DATABRICKS_HOST}/serving-endpoints/{endpoint}/invocations",
        headers=HEADERS,
        json=payload,
        timeout=60,
    )
    resp.raise_for_status()
    return resp.json()["choices"][0]["message"]["content"].strip()


def run_sql(sql: str) -> list[dict]:
    # Submit statement
    resp = requests.post(
        f"{DATABRICKS_HOST}/api/2.0/sql/statements",
        headers=HEADERS,
        json={"statement": sql, "warehouse_id": WAREHOUSE_ID, "wait_timeout": "30s"},
        timeout=60,
    )
    resp.raise_for_status()
    data = resp.json()

    # Poll if still pending
    statement_id = data["statement_id"]
    while data["status"]["state"] in ("PENDING", "RUNNING"):
        time.sleep(2)
        resp = requests.get(
            f"{DATABRICKS_HOST}/api/2.0/sql/statements/{statement_id}",
            headers=HEADERS,
            timeout=30,
        )
        resp.raise_for_status()
        data = resp.json()

    if data["status"]["state"] != "SUCCEEDED":
        raise RuntimeError(f"Query failed: {data['status']}")

    columns = [c["name"] for c in data["manifest"]["schema"]["columns"]]
    rows = data["result"].get("data_array", [])
    return [dict(zip(columns, row)) for row in rows]


def ask(question: str) -> None:
    print(f"\nQuestion: {question}")
    print("-" * 50)

    # Step 1: LLM generates SQL
    print("Generating SQL...")
    raw = call_llm(SYSTEM_PROMPT, question)

    # Parse JSON from LLM response (strip markdown fences if present)
    clean = raw.strip().removeprefix("```json").removeprefix("```").removesuffix("```").strip()
    try:
        sql = json.loads(clean)["sql"]
    except (json.JSONDecodeError, KeyError) as e:
        print(f"Could not parse LLM response:\n{raw}")
        raise e

    print(f"SQL: {sql}")

    # Step 2: Execute SQL
    print("Running query...")
    results = run_sql(sql)
    print(f"Raw results: {results}")

    # Step 3: LLM presents results
    context = f"Question: {question}\nSQL used: {sql}\nResults: {json.dumps(results, indent=2)}"
    summary = call_llm(PRESENTER_SYSTEM, context)
    print(f"\nAnswer: {summary}")


if __name__ == "__main__":
    ask("How many facilities are in Delhi?")
