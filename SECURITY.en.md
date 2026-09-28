# Security information

[简体中文](./SECURITY.md) · **English**

> Updated: 2026-09-28

## Private reporting

Report authentication bypass, unauthorized access, remote code execution, data exposure, or update integrity issues to `scrapefun@outlook.com` with the subject `ScrapeFun Security`.

Include affected versions, deployment method, impact, minimal reproduction steps, and evidence with sensitive information removed. Do not publish exploitation details for unfixed vulnerabilities or user credentials in public issues. You can send a summary first and coordinate how to transfer sensitive materials.

This document does not promise a bug bounty, fixed response times, or long-term security maintenance for a particular historical version. Prefer the latest stable release for your platform. Assess prerelease status and older-version risks against the specific release information.

## Deployment boundaries

- Configure administrator credentials during initial setup before allowing external access.
- Use a separate random `APP_AUTH_SECRET` for production Docker deployments, and protect environment files.
- Configure HTTPS, access controls, and appropriate network isolation for public access.
- The updater mounts the Docker socket and can manage containers. Bind port `4182` to localhost only, and use the same update token for app and updater.
- Keep an independent backup before updating or restoring. Do not attach databases or configuration archives to public reports.

See [Compose deployment](./DOCKER_COMPOSE_DEPLOYMENT.en.md) and [backup and recovery](./DOCKER_DATA_AND_BACKUP.en.md) for configuration and procedures.

## Verify downloads

Download from the corresponding project's GitHub Release or official Docker repository. If a release provides `SHA256SUMS`, individual checksums, or GitHub asset SHA-256 digests, compare them with the actual files. Checksums help detect file corruption; publisher signatures and operating-system trust status require separate checks.

The ad-hoc signature on macOS Server 0.3.3 is not an Apple Developer ID signature or notarization. Check the specific release for other platforms' signing status. Hosting a file on GitHub does not establish that it is signed.

## Third-party components

Each third-party project governs its own licensing and security maintenance. Software licensing restrictions cannot override rights granted by third-party licenses. See [third-party component information](./THIRD_PARTY_NOTICES.en.md).
