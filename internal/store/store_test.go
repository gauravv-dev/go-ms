package store

import (
	"testing"

	"github.com/example/go-ms/internal/model"
)

func TestMemoryStore_Create(t *testing.T) {
	st := NewMemoryStore()

	book := &model.Book{
		Title:  "Test Book",
		Author: "Test Author",
		ISBN:   "123-456",
	}

	created, err := st.Create(book)
	if err != nil {
		t.Fatalf("expected no error, got %v", err)
	}

	if created.ID == "" {
		t.Error("expected non-empty ID")
	}
	if created.Title != book.Title {
		t.Errorf("expected title %s, got %s", book.Title, created.Title)
	}
}

func TestMemoryStore_Get(t *testing.T) {
	st := NewMemoryStore()

	book, _ := st.Create(&model.Book{Title: "Test", Author: "Author"})

	found, err := st.Get(book.ID)
	if err != nil {
		t.Fatalf("expected no error, got %v", err)
	}
	if found.Title != book.Title {
		t.Errorf("expected title %s, got %s", book.Title, found.Title)
	}

	_, err = st.Get("non-existent")
	if err != ErrNotFound {
		t.Errorf("expected ErrNotFound, got %v", err)
	}
}

func TestMemoryStore_List(t *testing.T) {
	st := NewMemoryStore()

	st.Create(&model.Book{Title: "Book 1", Author: "Author 1"})
	st.Create(&model.Book{Title: "Book 2", Author: "Author 2"})

	books := st.List()
	if len(books) != 2 {
		t.Errorf("expected 2 books, got %d", len(books))
	}
}

func TestMemoryStore_Update(t *testing.T) {
	st := NewMemoryStore()

	book, _ := st.Create(&model.Book{Title: "Original", Author: "Author"})

	updates := &model.Book{Title: "Updated"}
	updated, err := st.Update(book.ID, updates)
	if err != nil {
		t.Fatalf("expected no error, got %v", err)
	}

	if updated.Title != "Updated" {
		t.Errorf("expected title 'Updated', got %s", updated.Title)
	}
	if updated.Author != "Author" {
		t.Errorf("expected author 'Author', got %s", updated.Author)
	}

	_, err = st.Update("non-existent", updates)
	if err != ErrNotFound {
		t.Errorf("expected ErrNotFound, got %v", err)
	}
}

func TestMemoryStore_Delete(t *testing.T) {
	st := NewMemoryStore()

	book, _ := st.Create(&model.Book{Title: "Delete Me", Author: "Author"})

	err := st.Delete(book.ID)
	if err != nil {
		t.Fatalf("expected no error, got %v", err)
	}

	_, err = st.Get(book.ID)
	if err != ErrNotFound {
		t.Error("expected book to be deleted")
	}

	err = st.Delete("non-existent")
	if err != ErrNotFound {
		t.Errorf("expected ErrNotFound, got %v", err)
	}
}
