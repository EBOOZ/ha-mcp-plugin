# Security Policy

> [!IMPORTANT]
> This setup uses authorization type **None**: the webhook URL is the only credential for your Home Assistant.  
> **Treat it like a password.**

## Reporting Security Issues

Please **do not** open public issues for vulnerabilities.  
Report privately via:

- GitHub Security Advisories (**preferred**)  
- github[at]ebooz.nl

Include impact, reproduction steps, and affected version(s).

## Webhook URL Handling

- `config.json`, `build\`, and `*.zip` contain the webhook URL.
- They are in `.gitignore`.
- **Never commit or share them.**

The web configurator never uploads the URL.  
It only stores it in browser local storage if you tick **Remember the URL in this browser**.  
Do not use that option on shared computers.

## If URL May Have Leaked

If shared in chats, screenshots, or zip files:

1. Regenerate the webhook ID in `ha-mcp`
2. Update `config.json`
3. Bump version
4. Rebuild and redistribute

## Least-Privilege Recommendations

If you only need read access, use:

- Read-only endpoint (`/readonly`), or
- A Chat tool set without `ha_call_service`

The Chat agent is instructed to request confirmation before changing automations, scripts, dashboards, or configuration.
