# Phone remote

The optional phone remote is a small web page served by Couch Remote on the Mac. A phone browser on the same Wi-Fi can use its trackpad pad, direction buttons, media controls, and text field without installing another app.

## Enable and connect

1. Open **Settings → Extras → Phone remote** (or the menu-bar phone toggle).
2. Approve macOS local-network access if requested.
3. Open the displayed `http://<Mac-local-address>:<port>` on a phone connected to the same trusted Wi-Fi, or scan the setup QR code.
4. Turn the phone remote off from the same setting/menu when finished.

The default port is configurable (the source defaults to 8723). If it cannot bind, choose another unused port. The Mac and phone must be able to reach each other on the local network; guest Wi-Fi/client isolation can prevent this.

## Security warning

The built-in server is **plain HTTP and unauthenticated**. The current web page uses commands that can move/click/type on the Mac and activate remote/media actions. Anyone who can reach the listening port may potentially control those functions. The service is intended for a trusted local network, not public Wi-Fi or the internet.

- Do not port-forward the port on your router.
- Do not expose it through a VPN, reverse proxy, or public tunnel.
- Disable it when not in use.
- Use a trusted Wi-Fi network; consider macOS firewall/network controls.
- Avoid typing sensitive passwords through the phone page.

See [Security](Security.md) for project-wide notes. Before expanding this feature, an authenticated transport and threat model should be considered.
