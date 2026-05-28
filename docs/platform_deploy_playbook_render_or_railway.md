# Platform Deployment Playbook (Railway)

## Goal

Deploy the backend in platform/ using GitHub Actions with repository-level secrets and variables.

## What is prepared in this repo

- Railway workflow: .github/workflows/platform-deploy-railway-test.yml
- Port binding for managed platforms: platform/src/main/resources/application.yml

---

## 1. Configure repository-level CI/CD values

In GitHub repository settings:

1. Open Secrets and variables > Actions.
2. Add repository secret:
   - RAILWAY_TOKEN
3. Add repository variables:
   - RAILWAY_PROJECT_ID
   - RAILWAY_SERVICE
   - RAILWAY_ENVIRONMENT

---

## 2. Configure Railway service

1. Create a Railway project and service connected to this repository.
2. Set service root directory to platform.
3. Configure service variables:
   - Preferred option: DB_URL (full JDBC PostgreSQL URL)
   - Alternative supported: DATABASE_PUBLIC_URL (Railway public PostgreSQL URL)
   - SPRING_PROFILES_ACTIVE=test (optional)
   - DB_HOST
   - DB_PORT
   - DB_NAME
   - DB_USER
   - DB_PASSWORD
   - REDIS_HOST
   - REDIS_PORT
   - ADMIN_API_KEY
   - PORT (usually injected automatically by Railway)

If DB_URL is set, the app will use it directly and you do not need DB_HOST, DB_PORT, DB_NAME, DB_USER, and DB_PASSWORD.
If DATABASE_PUBLIC_URL is set (without jdbc prefix), the app automatically adapts it to a JDBC URL.

Example DB_URL format:

- jdbc:postgresql://user:password@host:5432/database

Example DATABASE_PUBLIC_URL format:

- postgresql://user:password@host:5432/database

The app already supports PORT fallback in application.yml.

---

## 3. Trigger deployment

- Manual: run workflow Platform Deploy (Railway).
- Automatic: push to main changing platform/**.

Optional manual overrides are available for service and environment in workflow_dispatch.

---

## 4. Validation checklist

1. Open Railway deployment logs.
2. Confirm app started on assigned PORT.
3. Check OpenAPI endpoint: /v3/api-docs.
4. Check a lightweight API path with required headers.
5. Confirm DB and Redis connectivity in logs.

---

## 5. Rollback

- Roll back or redeploy previous successful release from Railway dashboard.

---

## 6. Recommended next hardening

- Add dedicated health endpoint and smoke test in workflow.
- Add migration-safe deploy step before deployment.
- Restrict deploy trigger to manual only until first stable test cycle.
