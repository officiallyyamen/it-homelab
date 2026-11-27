"""Verbindet GLPI mit dem Active Directory von lab.local (nur lesend).

Aufruf:  GLPI_PASS=... LDAP_PASS_FILE=svc-glpi.txt python ldap.py
Danach auf LNX01:  docker exec glpi-glpi-1 php bin/console ldap:synchronize_users -c
"""
import os

from seed import call

FELDER = {
    "name": "lab.local (DC01)",
    "host": "ldaps://dc01.lab.local",
    "port": 636,
    "basedn": "OU=Benutzer,OU=Firma,DC=lab,DC=local",
    "rootdn": "svc-glpi@lab.local",
    "condition": "(&(objectClass=user)(objectCategory=person)(!(userAccountControl:1.2.840.113556.1.4.803:=2)))",
    "login_field": "samaccountname",
    "sync_field": "objectguid",
    "realname_field": "sn",
    "firstname_field": "givenname",
    "email1_field": "mail",
    "title_field": "title",
    "use_dn": 1,
    "is_default": 1,
    "is_active": 1,
}


def main():
    FELDER["rootdn_passwd"] = open(os.environ["LDAP_PASS_FILE"], encoding="utf-8").read().strip()
    token = call("GET", "/initSession")["session_token"]
    try:
        vorhanden = [r for r in call("GET", "/AuthLDAP", token=token) or [] if r["name"] == FELDER["name"]]
        if vorhanden:
            call("PUT", f"/AuthLDAP/{vorhanden[0]['id']}", {"input": FELDER}, token=token)
            print("LDAP-Verzeichnis aktualisiert")
        else:
            call("POST", "/AuthLDAP", {"input": FELDER}, token=token)
            print("LDAP-Verzeichnis angelegt")
    finally:
        call("GET", "/killSession", token=token)


if __name__ == "__main__":
    main()
