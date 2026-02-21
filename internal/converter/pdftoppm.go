package converter

import (
	"context"
	"fmt"
	"os/exec"
	"path/filepath"
	"strconv"
)

func (c *Converter) pdfToPNG(ctx context.Context, pdfPath, outDir string, dpi int) (int, error) {
	absOut, _ := filepath.Abs(outDir)
	absPDF, _ := filepath.Abs(pdfPath)
	outPrefix := filepath.Join(absOut, "page")

	cmd := exec.CommandContext(ctx, "pdftoppm",
		"-png",
		"-rx", strconv.Itoa(dpi),
		"-ry", strconv.Itoa(dpi),
		absPDF,
		outPrefix,
	)

	output, err := cmd.CombinedOutput()
	if err != nil {
		return 0, fmt.Errorf("pdftoppm failed: %w\noutput: %s", err, output)
	}

	files, _ := filepath.Glob(filepath.Join(absOut, "page-*.png"))
	if len(files) == 0 {
		return 0, fmt.Errorf("no pages generated, output: %s", output)
	}
	return len(files), nil
}
