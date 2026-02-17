package store

import (
	"math/rand/v2"
	"sync"
	"time"

	"github.com/example/go-ms/internal/model"
)

// MemoryStore implements Store using in-memory storage
type MemoryStore struct {
	mu    sync.RWMutex
	books map[string]*model.Book
}

// NewMemoryStore creates a new in-memory store
func NewMemoryStore() *MemoryStore {
	return &MemoryStore{
		books: make(map[string]*model.Book),
	}
}

func (s *MemoryStore) Create(book *model.Book) (*model.Book, error) {
	s.mu.Lock()
	defer s.mu.Unlock()

	book.ID = generateID()
	book.CreatedAt = time.Now()
	book.UpdatedAt = time.Now()

	s.books[book.ID] = book
	return book, nil
}

func (s *MemoryStore) Get(id string) (*model.Book, error) {
	s.mu.RLock()
	defer s.mu.RUnlock()

	book, exists := s.books[id]
	if !exists {
		return nil, ErrNotFound
	}
	return book, nil
}

func (s *MemoryStore) List() []*model.Book {
	s.mu.RLock()
	defer s.mu.RUnlock()

	books := make([]*model.Book, 0, len(s.books))
	for _, book := range s.books {
		books = append(books, book)
	}
	return books
}

func (s *MemoryStore) Update(id string, updates *model.Book) (*model.Book, error) {
	s.mu.Lock()
	defer s.mu.Unlock()

	book, exists := s.books[id]
	if !exists {
		return nil, ErrNotFound
	}

	if updates.Title != "" {
		book.Title = updates.Title
	}
	if updates.Author != "" {
		book.Author = updates.Author
	}
	if updates.ISBN != "" {
		book.ISBN = updates.ISBN
	}
	if updates.Published != 0 {
		book.Published = updates.Published
	}
	book.UpdatedAt = time.Now()

	return book, nil
}

func (s *MemoryStore) Delete(id string) error {
	s.mu.Lock()
	defer s.mu.Unlock()

	if _, exists := s.books[id]; !exists {
		return ErrNotFound
	}
	delete(s.books, id)
	return nil
}

func generateID() string {
	const charset = "abcdefghijklmnopqrstuvwxyz0123456789"
	b := make([]byte, 8)
	for i := range b {
		b[i] = charset[rand.IntN(len(charset))]
	}
	return string(b)
}

func init() {
	rand.New(rand.NewPCG(uint64(time.Now().UnixNano()), uint64(time.Now().UnixNano())))
}
