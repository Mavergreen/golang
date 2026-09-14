package main

import (
	"crypto/x509"
	"fmt"
	"net/http"
	"os"
	"time"
)

func init() { x509.SetFallbackRoots(x509.NewCertPool()) } // what x509roots/fallback does

func main() {
	resp, err := (&http.Client{Timeout: 20 * time.Second}).Get("https://valid-isrgrootx1.letsencrypt.org/")
	if err != nil {
		fmt.Println("REJECTED:", err)
		os.Exit(1)
	}
	resp.Body.Close()
	fmt.Println("VERIFIED:", resp.Status)
}
