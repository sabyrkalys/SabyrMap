# AlpineQuest SaaS

Multi-tenant offline-map platform (waypoints, tracks, sharing, plugins).
Forked infra from Drone Ops; fresh schema. See `docs/` in project-main for
design and roadmap specs.

## Local dev

    docker compose up -d db
    cd api && pip install -r requirements.txt
    alembic upgrade head
    uvicorn app.main:app --reload
