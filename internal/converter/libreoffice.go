package converter

import (
	"context"
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
)

func (c *Converter) pptxToPDF(ctx context.Context, srcPath, outDir string) (string, error) {
	// Use a persistent profile dir to avoid first-run issues
	profileDir := filepath.Join(c.tmpDir, "lo-profile")
	os.MkdirAll(profileDir, 0755)

	// LibreOffice requires absolute paths
	absProfile, _ := filepath.Abs(profileDir)
	absSrc, _ := filepath.Abs(srcPath)
	absOut, _ := filepath.Abs(outDir)

	cmd := exec.CommandContext(ctx, c.libreOfficeBin,
		"--headless",
		"--invisible",
		"--nologo",
		"--nofirststartwizard",
		fmt.Sprintf("-env:UserInstallation=file://%s", absProfile),
		"--convert-to", "pdf",
		"--outdir", absOut,
		absSrc,
	)

	output, err := cmd.CombinedOutput()
	if err != nil {
		return "", fmt.Errorf("libreoffice failed: %w\noutput: %s", err, output)
	}

	baseName := strings.TrimSuffix(filepath.Base(absSrc), filepath.Ext(absSrc))
	pdfPath := filepath.Join(absOut, baseName+".pdf")

	if _, err := os.Stat(pdfPath); os.IsNotExist(err) {
		return "", fmt.Errorf("expected PDF not found at %s, output: %s", pdfPath, output)
	}
	return pdfPath, nil
}
