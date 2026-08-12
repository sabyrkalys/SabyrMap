from fastapi import FastAPI

app = FastAPI(title="AlpineQuest SaaS API")


@app.get("/health")
def health():
    return {"status": "ok"}
