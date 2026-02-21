package handlers

import (
	"encoding/json"
	"html/template"
	"net/http"

	"github.com/go-chi/chi/v5"
	"github.com/jonradoff/flipbook/internal/database"
	"github.com/jonradoff/flipbook/internal/models"
	"github.com/jonradoff/flipbook/internal/storage"
)

type ViewerHandler struct {
	db      *database.DB
	storage *storage.Storage
	tmpl    *template.Template
	baseURL string
}

func NewViewerHandler(db *database.DB, store *storage.Storage, tmpl *template.Template, baseURL string) *ViewerHandler {
	return &ViewerHandler{db: db, storage: store, tmpl: tmpl, baseURL: baseURL}
}

func (h *ViewerHandler) View(w http.ResponseWriter, r *http.Request) {
	slug := chi.URLParam(r, "slug")
	fb, err := h.db.GetFlipbookBySlug(slug)
	if err != nil || fb.Status != models.StatusReady {
		http.Error(w, "Flipbook not found", 404)
		return
	}

	go h.db.RecordView(fb.ID, r.Referer(), r.UserAgent())

	pageFmt := h.storage.DetectPageFormat(fb.ID)
	var pages []string
	var thumbs []string
	for i := 1; i <= fb.PageCount; i++ {
		pages = append(pages, h.storage.PageImageURL(fb.ID, pageFmt, i))
		thumbs = append(thumbs, h.storage.ThumbImageURL(fb.ID, pageFmt, i))
	}

	// Load extracted text for search (nil if unavailable)
	pageTexts := h.storage.LoadPageTexts(fb.ID)
	pageTextsJSON, _ := json.Marshal(pageTexts)

	h.tmpl.ExecuteTemplate(w, "viewer", map[string]interface{}{
		"Flipbook":      fb,
		"Pages":         pages,
		"Thumbs":        thumbs,
		"PageTextsJSON": template.JS(pageTextsJSON),
		"BaseURL":       h.baseURL,
		"EmbedCode":     embedCode(h.baseURL, fb.Slug),
	})
}
