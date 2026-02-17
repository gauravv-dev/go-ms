package main

import (
	"context"
	"log/slog"
	"net/http"
	"os"
	"time"

	"github.com/example/go-ms/internal/config"
	"github.com/example/go-ms/internal/db"
	"github.com/example/go-ms/internal/handler"
	"github.com/example/go-ms/internal/middleware"
	"github.com/example/go-ms/internal/store"
)

func main() {
	// Load configuration
	cfg := config.Load()

	// Setup structured logging with request ID support
	logHandler := slog.NewJSONHandler(os.Stdout, &slog.HandlerOptions{
		Level: parseLogLevel(cfg.LogLevel),
	})
	logger := slog.New(middleware.NewRequestIDHandler(logHandler))
	slog.SetDefault(logger)

	slog.Info("starting book service",
		"port", cfg.Port,
		"database_url", maskDatabaseURL(cfg.DatabaseURL),
		"auth_enabled", cfg.AuthEnabled,
	)

	// Initialize store
	var st store.Store
	if cfg.DatabaseURL != "" {
		pool, err := db.NewPool(context.Background(), cfg.DatabaseURL)
		if err != nil {
			slog.Error("failed to connect to database", "error", err)
			os.Exit(1)
		}
		defer pool.Close()
		st = store.NewPostgresStore(pool)
		slog.Info("using postgresql store")
	} else {
		st = store.NewMemoryStore()
		slog.Info("using in-memory store")
	}

	// Setup handler and routes
	h := handler.New(st)
	mux := http.NewServeMux()
	h.RegisterRoutes(mux)

	// Build middleware chain
	var handler http.Handler = mux
	handler = middleware.CORS(cfg.AllowedOrigins)(handler)
	if cfg.AuthEnabled {
		handler = middleware.Auth(cfg.APIKeys)(handler)
	}
	handler = middleware.Logger(handler)
	handler = middleware.RequestID(handler)
	handler = middleware.Recovery(handler)

	// Start server
	server := &http.Server{
		Addr:         cfg.Addr(),
		Handler:      handler,
		ReadTimeout:  15 * time.Second,
		WriteTimeout: 15 * time.Second,
		IdleTimeout:  60 * time.Second,
	}

	slog.Info("server listening", "addr", server.Addr)
	if err := server.ListenAndServe(); err != nil && err != http.ErrServerClosed {
		slog.Error("server error", "error", err)
		os.Exit(1)
	}
}

func parseLogLevel(level string) slog.Level {
	switch level {
	case "debug":
		return slog.LevelDebug
	case "info":
		return slog.LevelInfo
	case "warn":
		return slog.LevelWarn
	case "error":
		return slog.LevelError
	default:
		return slog.LevelInfo
	}
}

func maskDatabaseURL(url string) string {
	if url == "" {
		return "none (in-memory)"
	}
	if len(url) > 20 {
		return url[:20] + "..."
	}
	return url
}
