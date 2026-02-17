package middleware

import (
	"net/http"
	"strings"
)

// Auth validates API keys
func Auth(apiKeys []string) func(http.Handler) http.Handler {
	return func(next http.Handler) http.Handler {
		return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
			// Skip auth for OPTIONS requests
			if r.Method == "OPTIONS" {
				next.ServeHTTP(w, r)
				return
			}

			// Get API key from header
			apiKey := r.Header.Get("X-API-Key")
			if apiKey == "" {
				respondError(w, http.StatusUnauthorized, "missing API key")
				return
			}

			// Validate API key
			if !isValidAPIKey(apiKey, apiKeys) {
				respondError(w, http.StatusUnauthorized, "invalid API key")
				return
			}

			next.ServeHTTP(w, r)
		})
	}
}

func isValidAPIKey(key string, validKeys []string) bool {
	for _, validKey := range validKeys {
		if strings.EqualFold(key, validKey) {
			return true
		}
	}
	return false
}

func respondError(w http.ResponseWriter, status int, message string) {
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(status)
	w.Write([]byte(`{"error":"` + message + `"}`))
}
