package config

import (
	"fmt"
	"os"
	"strconv"
	"strings"
)

// Config holds application configuration
type Config struct {
	// Server configuration
	Port     int
	Host     string
	LogLevel string

	// Database configuration
	DatabaseURL string

	// Authentication
	APIKeys []string
	AuthEnabled bool

	// CORS
	AllowedOrigins []string
}

// Load loads configuration from environment variables
func Load() *Config {
	cfg := &Config{
		Port:         getEnvInt("PORT", 8080),
		Host:         getEnv("HOST", "0.0.0.0"),
		LogLevel:     getEnv("LOG_LEVEL", "info"),
		DatabaseURL:  getEnv("DATABASE_URL", ""),
		AuthEnabled:  getEnvBool("AUTH_ENABLED", true),
		AllowedOrigins: strings.Split(getEnv("ALLOWED_ORIGINS", "*"), ","),
	}

	// Parse API keys
	apiKeysStr := getEnv("API_KEYS", "dev-key-123")
	if apiKeysStr != "" {
		cfg.APIKeys = strings.Split(apiKeysStr, ",")
		for i := range cfg.APIKeys {
			cfg.APIKeys[i] = strings.TrimSpace(cfg.APIKeys[i])
		}
	}

	return cfg
}

// Addr returns the server address
func (c *Config) Addr() string {
	return fmt.Sprintf("%s:%d", c.Host, c.Port)
}

// getEnv gets an environment variable or returns a default value
func getEnv(key, defaultValue string) string {
	if value := os.Getenv(key); value != "" {
		return value
	}
	return defaultValue
}

// getEnvInt gets an environment variable as an integer or returns a default value
func getEnvInt(key string, defaultValue int) int {
	if value := os.Getenv(key); value != "" {
		if intVal, err := strconv.Atoi(value); err == nil {
			return intVal
		}
	}
	return defaultValue
}

// getEnvBool gets an environment variable as a boolean or returns a default value
func getEnvBool(key string, defaultValue bool) bool {
	if value := os.Getenv(key); value != "" {
		if boolVal, err := strconv.ParseBool(value); err == nil {
			return boolVal
		}
	}
	return defaultValue
}
