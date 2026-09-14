// capture prints the certificate chain a TLS server presents, as PEM. It does NOT verify:
// the output is test material (fixtures, certificates to import in Keychain Access).
//   usage: cd tests/trust/capture && go run . <host>
package main

import (
	"crypto/tls"
	"encoding/pem"
	"os"
)

func main() {
	host := os.Args[1]
	c, err := tls.Dial("tcp", host+":443", &tls.Config{InsecureSkipVerify: true, ServerName: host})
	if err != nil {
		panic(err)
	}
	defer c.Close()
	for _, cert := range c.ConnectionState().PeerCertificates {
		pem.Encode(os.Stdout, &pem.Block{Type: "CERTIFICATE", Bytes: cert.Raw})
	}
}
