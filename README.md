# Cloudflare Dynamic DNS IP Updater
<img alt="GitHub" src="https://img.shields.io/github/license/K0p1-Git/cloudflare-ddns-updater?color=black"> <img alt="GitHub last commit (branch)" src="https://img.shields.io/github/last-commit/K0p1-Git/cloudflare-ddns-updater/main"> <img alt="GitHub contributors" src="https://img.shields.io/github/contributors/K0p1-Git/cloudflare-ddns-updater">

This script is used to update Dynamic DNS (DDNS) service based on Cloudflare! Access your home network remotely via a custom domain name without a static IP! Written in pure BASH.

## Support Me
[![Donate Via Paypal](https://www.paypalobjects.com/en_US/i/btn/btn_donateCC_LG.gif)](https://www.paypal.me/Jasonkkf)

## Installation

```bash
git clone https://github.com/K0p1-Git/cloudflare-ddns-updater.git
```

## Configuration

The scripts can be configured either by editing the configuration section inside the script or by providing environment variables.

Environment variables override values configured in the script.

### Common environment variables

| Variable | Description |
| --- | --- |
| `AUTH_EMAIL` | Cloudflare account email |
| `AUTH_METHOD` | Authentication method (`token` or `global`) |
| `AUTH_KEY` | Cloudflare API Token or Global API Key |
| `ZONE_IDENTIFIER` | Cloudflare Zone ID |
| `RECORD_NAME` | DNS record to update |
| `TTL` | DNS TTL in seconds |
| `PROXY` | Enable Cloudflare proxy (`true`/`false`) |
| `SITENAME` | Site name used in notifications |
| `SLACK_CHANNEL` | Slack notification channel |
| `SLACK_URI` | Slack webhook URL |
| `DISCORD_URI` | Discord webhook URL |

### IPv6-specific environment variables

| Variable | Description |
| --- | --- |
| `STATIC_IPV6_MODE` | Enable static IPv6 mode |
| `LAST_NOTABLE_HEXES` | IPv6 suffix pattern used in static IPv6 mode |

Example:

```bash
export AUTH_EMAIL="user@example.com"
export AUTH_KEY="your-api-token"
export ZONE_IDENTIFIER="your-zone-id"
export RECORD_NAME="home.example.com"

./cloudflare-ddns.sh
```

## Usage
This script is used with crontab. Specify the frequency of execution through crontab.

```bash
# ┌───────────── minute (0 - 59)
# │ ┌───────────── hour (0 - 23)
# │ │ ┌───────────── day of the month (1 - 31)
# │ │ │ ┌───────────── month (1 - 12)
# │ │ │ │ ┌───────────── day of the week (0 - 6) (Sunday to Saturday 7 is also Sunday on some systems)
# │ │ │ │ │ ┌───────────── command to issue                               
# │ │ │ │ │ │
# │ │ │ │ │ │
# * * * * * /bin/bash {Location of the script}
```

## Tested Environments:
macOS Mojave version 10.14.6 (x86_64) <br />
AlmaLinux 9.3 (Linux kernel: 5.14.0 | x86_64) <br />
Debian Bullseye 11 (Linux kernel: 6.1.28 | aarch64) <br />

## Contributing
Pull requests are welcome. For major changes, please open an issue first to discuss what you would like to change.

## Reference
This script was made with reference from [Keld Norman](https://www.youtube.com/watch?v=vSIBkH7sxos) video.

## License
[MIT](https://github.com/K0p1-Git/cloudflare-ddns-updater/blob/main/LICENSE)
