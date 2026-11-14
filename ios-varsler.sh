#!/bin/bash
# Skulz: gjør iPhone-appen klar for varsler (kjøres én gang i skuls-ios-mappen på Macen)
set -e
if [ ! -f capacitor.config.json ] || [ ! -d ios/App/App ]; then
  echo "Feil mappe. Gå inn i skuls-ios-mappen først (se oppskriften)."; exit 1
fi

echo "1/4 Installerer varsel-tillegget …"
npm install @capacitor/push-notifications@^8 --save --no-fund --no-audit

echo "2/4 Oppdaterer innstillingene …"
cat > /tmp/skulz-varsler.js <<'JS'
const fs = require('fs');
// varsler vises også når appen er åpen
const cfg = JSON.parse(fs.readFileSync('capacitor.config.json', 'utf8'));
cfg.plugins = cfg.plugins || {};
cfg.plugins.PushNotifications = { presentationOptions: ['badge', 'sound', 'alert'] };
fs.writeFileSync('capacitor.config.json', JSON.stringify(cfg, null, 2) + '\n');
// «npm run hent» henter alltid den nyeste index.html (ikke en gammel kopi fra GitHub)
const pkg = JSON.parse(fs.readFileSync('package.json', 'utf8'));
pkg.scripts.hent = 'curl -fsSL "https://raw.githubusercontent.com/sondreaustadhove-dotcom/Skulz/main/index.html?v=$(date +%s)" -o www/index.html && npx cap sync ios';
fs.writeFileSync('package.json', JSON.stringify(pkg, null, 2) + '\n');
// AppDelegate sender telefonens varselnøkkel videre til appen
const f = 'ios/App/App/AppDelegate.swift';
let s = fs.readFileSync(f, 'utf8');
if (!s.includes('capacitorDidRegisterForRemoteNotifications')) {
  const add = `
    func application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        NotificationCenter.default.post(name: .capacitorDidRegisterForRemoteNotifications, object: deviceToken)
    }

    func application(_ application: UIApplication, didFailToRegisterForRemoteNotificationsWithError error: Error) {
        NotificationCenter.default.post(name: .capacitorDidFailToRegisterForRemoteNotifications, object: error)
    }
`;
  const i = s.lastIndexOf('}');
  s = s.slice(0, i) + add + s.slice(i);
  fs.writeFileSync(f, s);
}
JS
node /tmp/skulz-varsler.js
rm -f /tmp/skulz-varsler.js

echo "3/4 Henter nyeste versjon av appen …"
npm run hent

echo "4/4 Ferdig! Åpner Xcode …"
npx cap open ios || true
echo ""
echo "✅ Klart. Fortsett med steg i Xcode (Signing & Capabilities → + Capability → Push Notifications)."
