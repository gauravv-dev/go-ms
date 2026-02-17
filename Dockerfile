# Build stage
FROM golang:1.24-alpine AS builder

WORKDIR /app

# Install dependencies
RUN apk add --no-cache git

# Copy go mod files
COPY go.mod go.sum ./
RUN go mod download

# Copy source code
COPY . .

# Build the application
RUN CGO_ENABLED=0 GOOS=linux go build -a -installsuffix cgo -o book-service ./cmd/server

# Runtime stage
FROM alpine:latest

RUN apk --no-cache add ca-certificates

# Create non-root user
RUN addgroup -g 1000 appuser && \
    adduser -D -u 1000 -G appuser appuser

WORKDIR /app

# Copy the binary from builder with correct ownership
COPY --from=builder --chown=appuser:appuser /app/book-service .
RUN chmod +x book-service

# Copy migrations
COPY --from=builder --chown=appuser:appuser /app/migrations ./migrations

# Switch to non-root user
USER appuser

EXPOSE 8080

CMD ["./book-service"]
