package handler

import (
	"encoding/json"
	"errors"
	"net/http"
	"strings"

	"github.com/example/go-ms/internal/model"
	"github.com/example/go-ms/internal/store"
)

// Handler handles HTTP requests
type Handler struct {
	store store.Store
}

// New creates a new handler
func New(store store.Store) *Handler {
	return &Handler{store: store}
}

// RegisterRoutes registers all routes on the given mux
func (h *Handler) RegisterRoutes(mux *http.ServeMux) {
	mux.HandleFunc("POST /books", h.handleCreateBook)
	mux.HandleFunc("GET /books", h.handleListBooks)
	mux.HandleFunc("GET /books/", h.handleGetBook)
	mux.HandleFunc("PUT /books/", h.handleUpdateBook)
	mux.HandleFunc("DELETE /books/", h.handleDeleteBook)
	mux.HandleFunc("GET /health", h.handleHealth)
}

func (h *Handler) handleCreateBook(w http.ResponseWriter, r *http.Request) {
	var book model.Book
	if err := json.NewDecoder(r.Body).Decode(&book); err != nil {
		respondError(w, http.StatusBadRequest, "invalid request body")
		return
	}

	if book.Title == "" || book.Author == "" {
		respondError(w, http.StatusBadRequest, "title and author are required")
		return
	}

	created, err := h.store.Create(&book)
	if err != nil {
		respondError(w, http.StatusInternalServerError, err.Error())
		return
	}

	respondJSON(w, http.StatusCreated, created)
}

func (h *Handler) handleGetBook(w http.ResponseWriter, r *http.Request) {
	id := strings.TrimPrefix(r.URL.Path, "/books/")
	if id == "" {
		h.handleListBooks(w, r)
		return
	}

	book, err := h.store.Get(id)
	if err != nil {
		if errors.Is(err, store.ErrNotFound) {
			respondError(w, http.StatusNotFound, "book not found")
			return
		}
		respondError(w, http.StatusInternalServerError, err.Error())
		return
	}

	respondJSON(w, http.StatusOK, book)
}

func (h *Handler) handleListBooks(w http.ResponseWriter, r *http.Request) {
	books := h.store.List()
	respondJSON(w, http.StatusOK, books)
}

func (h *Handler) handleUpdateBook(w http.ResponseWriter, r *http.Request) {
	id := strings.TrimPrefix(r.URL.Path, "/books/")
	if id == "" {
		respondError(w, http.StatusBadRequest, "book id required")
		return
	}

	var updates model.Book
	if err := json.NewDecoder(r.Body).Decode(&updates); err != nil {
		respondError(w, http.StatusBadRequest, "invalid request body")
		return
	}

	book, err := h.store.Update(id, &updates)
	if err != nil {
		if errors.Is(err, store.ErrNotFound) {
			respondError(w, http.StatusNotFound, "book not found")
			return
		}
		respondError(w, http.StatusInternalServerError, err.Error())
		return
	}

	respondJSON(w, http.StatusOK, book)
}

func (h *Handler) handleDeleteBook(w http.ResponseWriter, r *http.Request) {
	id := strings.TrimPrefix(r.URL.Path, "/books/")
	if id == "" {
		respondError(w, http.StatusBadRequest, "book id required")
		return
	}

	if err := h.store.Delete(id); err != nil {
		if errors.Is(err, store.ErrNotFound) {
			respondError(w, http.StatusNotFound, "book not found")
			return
		}
		respondError(w, http.StatusInternalServerError, err.Error())
		return
	}

	w.WriteHeader(http.StatusNoContent)
}

func (h *Handler) handleHealth(w http.ResponseWriter, r *http.Request) {
	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(map[string]string{"status": "healthy"})
}

func respondJSON(w http.ResponseWriter, status int, data interface{}) {
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(status)
	json.NewEncoder(w).Encode(data)
}

func respondError(w http.ResponseWriter, status int, message string) {
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(status)
	json.NewEncoder(w).Encode(map[string]string{"error": message})
}
