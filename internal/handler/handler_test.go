package handler

import (
	"bytes"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"testing"

	"github.com/example/go-ms/internal/model"
	"github.com/example/go-ms/internal/store"
)

func TestHandleCreateBook(t *testing.T) {
	st := store.NewMemoryStore()
	h := New(st)

	book := model.Book{
		Title:     "The Go Programming Language",
		Author:    "Alan Donovan",
		ISBN:      "978-0134190440",
		Published: 2015,
	}

	body, _ := json.Marshal(book)
	req := httptest.NewRequest("POST", "/books", bytes.NewReader(body))
	req.Header.Set("Content-Type", "application/json")
	w := httptest.NewRecorder()

	h.handleCreateBook(w, req)

	if w.Code != http.StatusCreated {
		t.Errorf("expected status 201, got %d", w.Code)
	}

	var resp model.Book
	json.NewDecoder(w.Body).Decode(&resp)

	if resp.Title != book.Title {
		t.Errorf("expected title %s, got %s", book.Title, resp.Title)
	}
	if resp.ID == "" {
		t.Error("expected non-empty ID")
	}
}

func TestHandleGetBook(t *testing.T) {
	st := store.NewMemoryStore()
	h := New(st)

	book, _ := st.Create(&model.Book{
		Title:  "Test Book",
		Author: "Test Author",
		ISBN:   "123-456",
	})

	req := httptest.NewRequest("GET", "/books/"+book.ID, nil)
	w := httptest.NewRecorder()

	h.handleGetBook(w, req)

	if w.Code != http.StatusOK {
		t.Errorf("expected status 200, got %d", w.Code)
	}

	var resp model.Book
	json.NewDecoder(w.Body).Decode(&resp)

	if resp.Title != book.Title {
		t.Errorf("expected title %s, got %s", book.Title, resp.Title)
	}
}

func TestHandleListBooks(t *testing.T) {
	st := store.NewMemoryStore()
	h := New(st)

	st.Create(&model.Book{Title: "Book 1", Author: "Author 1"})
	st.Create(&model.Book{Title: "Book 2", Author: "Author 2"})

	req := httptest.NewRequest("GET", "/books", nil)
	w := httptest.NewRecorder()

	h.handleListBooks(w, req)

	if w.Code != http.StatusOK {
		t.Errorf("expected status 200, got %d", w.Code)
	}

	var resp []*model.Book
	json.NewDecoder(w.Body).Decode(&resp)

	if len(resp) != 2 {
		t.Errorf("expected 2 books, got %d", len(resp))
	}
}

func TestHandleUpdateBook(t *testing.T) {
	st := store.NewMemoryStore()
	h := New(st)

	book, _ := st.Create(&model.Book{Title: "Original", Author: "Author"})

	updates := model.Book{Title: "Updated"}
	body, _ := json.Marshal(updates)
	req := httptest.NewRequest("PUT", "/books/"+book.ID, bytes.NewReader(body))
	req.Header.Set("Content-Type", "application/json")
	w := httptest.NewRecorder()

	h.handleUpdateBook(w, req)

	if w.Code != http.StatusOK {
		t.Errorf("expected status 200, got %d", w.Code)
	}

	var resp model.Book
	json.NewDecoder(w.Body).Decode(&resp)

	if resp.Title != "Updated" {
		t.Errorf("expected title 'Updated', got %s", resp.Title)
	}
	if resp.Author != "Author" {
		t.Errorf("expected author 'Author', got %s", resp.Author)
	}
}

func TestHandleDeleteBook(t *testing.T) {
	st := store.NewMemoryStore()
	h := New(st)

	book, _ := st.Create(&model.Book{Title: "Delete Me", Author: "Author"})

	req := httptest.NewRequest("DELETE", "/books/"+book.ID, nil)
	w := httptest.NewRecorder()

	h.handleDeleteBook(w, req)

	if w.Code != http.StatusNoContent {
		t.Errorf("expected status 204, got %d", w.Code)
	}

	_, err := st.Get(book.ID)
	if err != store.ErrNotFound {
		t.Error("expected book to be deleted")
	}
}

func TestHandleHealth(t *testing.T) {
	st := store.NewMemoryStore()
	h := New(st)

	req := httptest.NewRequest("GET", "/health", nil)
	w := httptest.NewRecorder()

	h.handleHealth(w, req)

	if w.Code != http.StatusOK {
		t.Errorf("expected status 200, got %d", w.Code)
	}

	var resp map[string]string
	json.NewDecoder(w.Body).Decode(&resp)

	if resp["status"] != "healthy" {
		t.Errorf("expected status 'healthy', got %s", resp["status"])
	}
}
