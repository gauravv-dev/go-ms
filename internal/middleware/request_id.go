package middleware

import (
	"context"
	"fmt"
	"log/slog"
	"net/http"

	"github.com/google/uuid"
)

type contextKey string

const RequestIDKey contextKey = "request_id"

// RequestID adds a unique request ID to each request
func RequestID(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		// Get existing request ID from header or generate new one
		reqID := r.Header.Get("X-Request-ID")
		if reqID == "" {
			reqID = uuid.New().String()
		}

		// Add to context
		ctx := context.WithValue(r.Context(), RequestIDKey, reqID)

		// Add to response header
		w.Header().Set("X-Request-ID", reqID)

		next.ServeHTTP(w, r.WithContext(ctx))
	})
}

// GetRequestID retrieves the request ID from context
func GetRequestID(ctx context.Context) string {
	if reqID, ok := ctx.Value(RequestIDKey).(string); ok {
		return reqID
	}
	return "unknown"
}

// RequestIDLogger is a slog handler that adds request ID to logs
type RequestIDHandler struct {
	slog.Handler
}

func NewRequestIDHandler(handler slog.Handler) *RequestIDHandler {
	return &RequestIDHandler{Handler: handler}
}

func (h *RequestIDHandler) Handle(ctx context.Context, r slog.Record) error {
	// Add request ID to all log records if present
	if reqID := GetRequestID(ctx); reqID != "unknown" {
		r.AddAttrs(slog.String("request_id", reqID))
	}
	return h.Handler.Handle(ctx, r)
}

// FormatRequestID formats request ID for display
func FormatRequestID(reqID string) string {
	if len(reqID) <= 8 {
		return reqID
	}
	return fmt.Sprintf("%s...%s", reqID[:4], reqID[len(reqID)-4:])
}
