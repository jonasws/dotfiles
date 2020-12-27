#!/bin/sh -e

echo "# Netscape HTTP Cookie File"
sqlite3 -separator $'\t' $1 <<- EOF
	.mode tabs
	.header off
	select host,
	case substr(host,1,1)='.' when 0 then 'FALSE' else 'TRUE' end,
	path,
	case isSecure when 0 then 'FALSE' else 'TRUE' end,
	expiry,
	name,
	value
	from moz_cookies;

EOF
