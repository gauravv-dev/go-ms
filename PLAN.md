# Plan: Enhance Go Microservice with Database, Middleware, and Docker

## Current State
- Simple in-memory book CRUD service
- Single-file `main.go` with handlers and `Store` using `map[string]*Book`
- Basic unit tests in `main_test.go`

## Proposed Enhancements

### 1. Database Layer (PostgreSQL)

**Files to create:**
- `internal/db/db.go` - Database connection and migrations
- `internal/store/postgres.go` - PostgreSQL implementation of Store interface
- `migrations/001_create_books_table.up.sql` - Schema migration

**Key changes:**
- Extract `Store` as an interface with two implementations: `MemoryStore` and `PostgresStore`
- Use `pgx` driver for PostgreSQL
- Add connection pooling with sensible defaults
- Support for environment-based configuration (DATABASE_URL)

### 2. Middleware

**Files to create:**
- `internal/middleware/logger.go` - Structured logging (log/slog)
- `internal/middleware/request_id.go` - Request ID generation and propagation
- `internal/middleware/cors.go` - CORS headers
- `internal/middleware/auth.go` - Simple API key authentication
- `internal/middleware/recovery.go` - Panic recovery

**Middleware chain order:**
1. Recovery (outermost)
2. Request ID
3. Logger
4. CORS
5. Auth (optional, configurable)

### 3. Docker Setup

**Files to create:**
- `Dockerfile` - Multi-stage build for production
- `docker-compose.yml` - Orchestrate app + PostgreSQL
- `.dockerignore` - Exclude unnecessary files

**docker-compose features:**
- PostgreSQL service with named volume
- App service with hot-reload in development
- Environment configuration
- Health checks

### 4. Configuration & Structure

**Files to create/modify:**
- `internal/config/config.go` - Environment-based config
- `cmd/server/main.go` - Move main logic here
- `Makefile` - Common tasks (build, test, docker, migrate)

**New directory structure:**
```
go-ms/
├── cmd/
│   └── server/
│       └── main.go          # Entry point
├── internal/
│   ├── config/
│   │   └── config.go        # Configuration
│   ├── db/
│   │   └── db.go            # Database connection
│   ├── middleware/
│   │   ├── auth.go
│   │   ├── cors.go
│   │   ├── logger.go
│   │   ├── recovery.go
│   │   └── request_id.go
│   ├── model/
│   │   └── book.go          # Book model
│   └── store/
│       ├── store.go         # Store interface
│       ├── memory.go        # In-memory implementation
│       └── postgres.go      # PostgreSQL implementation
├── migrations/
│   └── 001_create_books_table.up.sql
├── Dockerfile
├── docker-compose.yml
├── Makefile
└── go.mod
```

### 5. Authentication Approach

Simple API key authentication:
- Check `X-API-Key` header against configured keys
- Configurable via `API_KEYS` environment variable (comma-separated)
- Skip auth for health endpoints

## Implementation Steps

1. Create new directory structure and move existing code
2. Extract Store interface and refactor existing code
3. Implement PostgreSQL store with migrations
4. Add configuration system
5. Implement middleware components
6. Wire everything together in new main.go
7. Create Dockerfile and docker-compose.yml
8. Add Makefile for convenience
9. Update tests to work with new structure

## Verification

- Run `make test` - all tests pass
- Run `make docker-up` - services start successfully
- Test CRUD operations via curl against containerized service
- Verify database persistence across restarts
- Check middleware logs include request IDs
- Verify CORS headers are present
- Test API key auth works correctly
