package store

import (
	"context"
	"time"

	"github.com/example/go-ms/internal/db"
	"github.com/example/go-ms/internal/model"
	"github.com/jackc/pgx/v5"
)

// PostgresStore implements Store using PostgreSQL
type PostgresStore struct {
	pool *db.Pool
}

// NewPostgresStore creates a new PostgreSQL store
func NewPostgresStore(pool *db.Pool) *PostgresStore {
	return &PostgresStore{pool: pool}
}

func (s *PostgresStore) Create(book *model.Book) (*model.Book, error) {
	ctx := context.Background()
	book.ID = generateID()
	book.CreatedAt = time.Now()
	book.UpdatedAt = time.Now()

	query := `
		INSERT INTO books (id, title, author, isbn, published, created_at, updated_at)
		VALUES ($1, $2, $3, $4, $5, $6, $7)
		RETURNING id, title, author, isbn, published, created_at, updated_at
	`

	row := s.pool.QueryRow(ctx, query,
		book.ID, book.Title, book.Author, book.ISBN, book.Published,
		book.CreatedAt, book.UpdatedAt,
	)

	return scanBook(row)
}

func (s *PostgresStore) Get(id string) (*model.Book, error) {
	ctx := context.Background()

	query := `
		SELECT id, title, author, isbn, published, created_at, updated_at
		FROM books WHERE id = $1
	`

	row := s.pool.QueryRow(ctx, query, id)
	book, err := scanBook(row)
	if err == pgx.ErrNoRows {
		return nil, ErrNotFound
	}
	return book, err
}

func (s *PostgresStore) List() []*model.Book {
	ctx := context.Background()

	query := `
		SELECT id, title, author, isbn, published, created_at, updated_at
		FROM books ORDER BY created_at DESC
	`

	rows, _ := s.pool.Query(ctx, query)
	defer rows.Close()

	var books []*model.Book
	for rows.Next() {
		book, err := pgx.RowToStructByName[model.Book](rows)
		if err == nil {
			books = append(books, &book)
		}
	}
	return books
}

func (s *PostgresStore) Update(id string, updates *model.Book) (*model.Book, error) {
	ctx := context.Background()

	query := `
		UPDATE books
		SET
			title = COALESCE($2, title),
			author = COALESCE($3, author),
			isbn = COALESCE($4, isbn),
			published = COALESCE($5, published),
			updated_at = $6
		WHERE id = $1
		RETURNING id, title, author, isbn, published, created_at, updated_at
	`

	row := s.pool.QueryRow(ctx, query,
		id, updates.Title, updates.Author, updates.ISBN,
		updates.Published, time.Now(),
	)

	book, err := scanBook(row)
	if err == pgx.ErrNoRows {
		return nil, ErrNotFound
	}
	return book, err
}

func (s *PostgresStore) Delete(id string) error {
	ctx := context.Background()

	result, err := s.pool.Exec(ctx, "DELETE FROM books WHERE id = $1", id)
	if err != nil {
		return err
	}

	if result.RowsAffected() == 0 {
		return ErrNotFound
	}
	return nil
}

func scanBook(row pgx.Row) (*model.Book, error) {
	var book model.Book
	err := row.Scan(
		&book.ID, &book.Title, &book.Author, &book.ISBN,
		&book.Published, &book.CreatedAt, &book.UpdatedAt,
	)
	return &book, err
}
