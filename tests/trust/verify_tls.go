package main

import (
	"fmt"
	"net/http"
	"os"
	"time"
)

// Usage: verify_tls [url]
// The default target is Let's Encrypt's per-root test endpoint for ISRG Root X1.
// valid-isrgrootx1/x2.letsencrypt.org are the test endpoints Let's Encrypt keeps
// for each of its roots, which makes them stable distrust targets. The chain they
// serve still follows the CA hierarchy: valid-isrgrootx1 currently chains
// leaf -> YR2 -> ISRG Root YR (cross-signed) -> ISRG Root X1, so a CA bundle that
// carries Root YR as a self-signed root can anchor it without X1.
func main() {
	url := "https://valid-isrgrootx1.letsencrypt.org/"
	if len(os.Args) > 1 {
		url = os.Args[1]
	}
	c := &http.Client{Timeout: 20 * time.Second}
	resp, err := c.Get(url)
	if err != nil {
		fmt.Println("REJECTED:", err)
		os.Exit(1)
	}
	resp.Body.Close()
	fmt.Println("VERIFIED:", resp.Status)
}
