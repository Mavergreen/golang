// userdeny checks crypto/x509 against the REAL user trust domain of the account running it:
// every self-signed certificate the user marked "Never Trust" (for SSL, or for everything) must
// be rejected as signed by an unknown authority, and every self-signed one marked "Always Trust"
// must verify. Non-self-signed certificates are skipped: verifying one alone proves nothing
// about its trust setting. Each is verified inside its own validity window, so expiry cannot
// mask the result. cgo reads the settings through
// Security.framework, independently of crypto/x509's own enumeration. Exit 77 when the user has
// no such settings. Usage (on the Mavericks box): go build -o /tmp/userdeny . && /tmp/userdeny
package main

/*
#cgo LDFLAGS: -framework Security -framework CoreFoundation
#include <Security/Security.h>

static CFMutableArrayRef found;

// effective returns the user-domain SSL result for cert: 3 Deny, 1 TrustRoot, 2 TrustAsRoot,
// 0 none of those. Like Go and Apple, it stops at the first TrustRoot, TrustAsRoot or Deny.
static int effective(SecCertificateRef cert) {
	CFArrayRef settings = NULL;
	if (SecTrustSettingsCopyTrustSettings(cert, kSecTrustSettingsDomainUser, &settings) != errSecSuccess || settings == NULL)
		return 0;
	int out = 0;
	CFIndex n = CFArrayGetCount(settings);
	if (n == 0)
		out = kSecTrustSettingsResultTrustRoot;
	for (CFIndex i = 0; i < n && out == 0; i++) {
		CFDictionaryRef d = CFArrayGetValueAtIndex(settings, i);
		CFTypeRef pol = CFDictionaryGetValue(d, kSecTrustSettingsPolicy);
		if (pol) {
			CFDictionaryRef props = SecPolicyCopyProperties((SecPolicyRef)pol);
			CFTypeRef oid = props ? CFDictionaryGetValue(props, kSecPolicyOid) : NULL;
			int ssl = oid && CFEqual(oid, kSecPolicyAppleSSL);
			if (props)
				CFRelease(props);
			if (!ssl)
				continue;
		}
		if (CFDictionaryGetValue(d, kSecTrustSettingsPolicyString))
			continue;
		SInt32 v = kSecTrustSettingsResultTrustRoot;
		CFNumberRef r = CFDictionaryGetValue(d, kSecTrustSettingsResult);
		if (r && !CFNumberGetValue(r, kCFNumberSInt32Type, &v))
			continue; // an unreadable result is skipped, not taken as TrustRoot
		if (v == kSecTrustSettingsResultDeny || v == kSecTrustSettingsResultTrustRoot ||
		    v == kSecTrustSettingsResultTrustAsRoot)
			out = v;
	}
	CFRelease(settings);
	return out;
}

// collect gathers the DER of every user-domain certificate whose effective result is want.
static int collect(int want) {
	if (found)
		CFRelease(found);
	found = CFArrayCreateMutable(NULL, 0, &kCFTypeArrayCallBacks);
	CFArrayRef certs = NULL;
	if (SecTrustSettingsCopyCertificates(kSecTrustSettingsDomainUser, &certs) != errSecSuccess || certs == NULL)
		return 0;
	for (CFIndex i = 0; i < CFArrayGetCount(certs); i++) {
		SecCertificateRef c = (SecCertificateRef)CFArrayGetValueAtIndex(certs, i);
		if (effective(c) != want)
			continue;
		CFDataRef der = SecCertificateCopyData(c);
		if (der) {
			CFArrayAppendValue(found, der);
			CFRelease(der);
		}
	}
	CFRelease(certs);
	return (int)CFArrayGetCount(found);
}

static const UInt8 *der_at(int i, int *len) {
	CFDataRef d = CFArrayGetValueAtIndex(found, i);
	*len = (int)CFDataGetLength(d);
	return CFDataGetBytePtr(d);
}
*/
import "C"

import (
	"bytes"
	"crypto/x509"
	"errors"
	"fmt"
	"os"
	"unsafe"
)

func main() {
	checked, failed := 0, false
	wants := []int{3, 1}
	if os.Getenv("USERDENY_DENY_ONLY") != "" {
		// Apple's verifier applies the SSL policy to a CA certificate verified as a leaf, so an
		// Always Trust root need not verify there; Never Trust must still be rejected.
		wants = []int{3}
	}
	for _, want := range wants {
		n := int(C.collect(C.int(want)))
		for i := 0; i < n; i++ {
			var l C.int
			p := C.der_at(C.int(i), &l)
			cert, err := x509.ParseCertificate(C.GoBytes(unsafe.Pointer(p), l))
			if err != nil {
				continue
			}
			selfSigned := bytes.Equal(cert.RawSubject, cert.RawIssuer)
			if want == 3 && !selfSigned {
				fmt.Printf("skip user Never Trust %q: not self-signed, verifying it alone proves nothing\n", cert.Subject)
				continue
			}
			// Verify inside the cert's own validity window: an expired cert must not pass the Never Trust check for the wrong reason.
			mid := cert.NotBefore.Add(cert.NotAfter.Sub(cert.NotBefore) / 2)
			_, verr := cert.Verify(x509.VerifyOptions{KeyUsages: []x509.ExtKeyUsage{x509.ExtKeyUsageAny}, CurrentTime: mid})
			var uae x509.UnknownAuthorityError
			switch {
			case want == 3 && verr == nil:
				fmt.Printf("FAIL user Never Trust %q still verifies\n", cert.Subject)
				failed = true
			case want == 3 && !errors.As(verr, &uae):
				fmt.Printf("FAIL user Never Trust %q rejected for the wrong reason: %v\n", cert.Subject, verr)
				failed = true
			case want == 3:
				fmt.Printf("ok   user Never Trust %q rejected: %v\n", cert.Subject, verr)
			case !selfSigned:
				continue // Always Trust on a non-root anchors nothing by itself
			case verr != nil:
				fmt.Printf("FAIL user Always Trust %q does not verify: %v\n", cert.Subject, verr)
				failed = true
			default:
				fmt.Printf("ok   user Always Trust %q verifies\n", cert.Subject)
			}
			checked++
		}
	}
	if checked == 0 {
		fmt.Println("no user-domain Never/Always Trust settings to check -- skipping")
		os.Exit(77)
	}
	if failed {
		os.Exit(1)
	}
}
