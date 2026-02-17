package store

import "github.com/example/go-ms/internal/model"

// Store defines the interface for book storage operations
type Store interface {
	Create(book *model.Book) (*model.Book, error)
	Get(id string) (*model.Book, error)
	List() []*model.Book
	Update(id string, updates *model.Book) (*model.Book, error)
	Delete(id string) error
}

// ErrNotFound is returned when a resource is not found
var ErrNotFound = storeError("not found")

type storeError string

func (e storeError) Error() string {
	return string(e)
}
