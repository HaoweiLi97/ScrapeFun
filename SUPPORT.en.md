# Support and feedback

[简体中文](./SUPPORT.md) · **English**

> Updated: 2026-09-28

## Choose a contact route

| Topic | Contact |
| --- | --- |
| Publicly reproducible product bugs and feature requests | [GitHub Issues](https://github.com/HaoweiLi97/ScrapeFun/issues) |
| Usage and deployment | [Documentation](./docs/README.en.md) · [Product feedback](https://scrapefun.com/?lang=en#/contact) |
| Accounts, orders, Pro activation, and private materials | `scrapefun@outlook.com` |
| Commercial deployment, customer delivery, and licensing partnerships | `lihaowei977@gmail.com` |
| Vulnerabilities and exposed credentials | [Security reporting](./SECURITY.en.md) |

The public repository does not promise response times, repair deadlines, or an SLA. A separate written support contract governs where applicable.

## Report a bug

Include the following information to help diagnose the issue:

- Server and Client versions, and the stable / beta channel.
- Operating system, CPU architecture, and deployment method; for playback issues, add GPU and media codec details.
- Minimal reproduction steps, expected and actual results, and the time of the error.
- Relevant logs or screenshots with sensitive information removed; Docker reports may include Compose service status.
- Whether the issue appeared after an update, and the last version that worked.

Do not post passwords, activation codes, session tokens, complete WebDAV addresses, signed resource URLs, databases, or backup files in public issues. If you cannot safely remove sensitive details, describe the symptoms by email first.

## Common checks

| Symptom | Check |
| --- | --- |
| Client cannot connect | Whether Server is running, the address and port are correct, and LAN access and the firewall allow the connection |
| Data looks wrong after a Docker update | Whether the original host data root is still mounted at `/app/data`; see [recovery](./DOCKER_DATA_AND_BACKUP.en.md) |
| Installer or application will not start | CPU architecture, system requirements, and signing and first-launch instructions for the specific release |
| Pro cannot activate | Instance clock, network connectivity, and the license page message; keep activation codes private |
| Download or update fails | Whether the release exists, the file downloaded completely, and that update method is supported on the platform |

## Partnerships and customization

See [licensing and agreements](./legal/README.en.md) for internal organizational deployment, customer delivery, hosting, and software redistribution. When requesting deployment assistance or commercial licensing, describe your use case, deployment size, and platforms.
