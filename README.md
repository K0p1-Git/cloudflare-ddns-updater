# Cloudflare Dynamic DNS IP Updater
<img alt="GitHub" src="https://img.shields.io/github/license/K0p1-Git/cloudflare-ddns-updater?color=black"> <img alt="GitHub last commit (branch)" src="https://img.shields.io/github/last-commit/K0p1-Git/cloudflare-ddns-updater/main"> <img alt="GitHub contributors" src="https://img.shields.io/github/contributors/K0p1-Git/cloudflare-ddns-updater">

This script is used to update Dynamic DNS (DDNS) service based on Cloudflare! Access your home network remotely via a custom domain name without a static IP! Written in pure BASH.

## Support Me
[![Donate Via Paypal](https://www.paypalobjects.com/en_US/i/btn/btn_donateCC_LG.gif)](https://www.paypal.me/Jasonkkf)

## Table of Contents

- [Cloudflare Dynamic DNS IP Updater](#cloudflare-dynamic-dns-ip-updater)
  * [Support Me](#support-me)
  * [Table of Contents](#table-of-contents)
  * [Installation](#installation)
  * [Usage](#usage)
    + [Local variables](#local-variables)
    + [Configuration file](#configuration-file)
    + [Pass](#pass)
  * [Tested Environments:](#tested-environments)
  * [Contributing](#contributing)
  * [Reference](#reference)
  * [License](#license)

## Installation

```bash
git clone https://github.com/K0p1-Git/cloudflare-ddns-updater.git
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

### Local variables

If you want to use your variables inside the script fill the script with them and execute it like the following example:

```bash
./cloudflare-template.sh local
```

### Configuration file

If you want to use the configuration file to store your credentials execute the following commands:

```bash
mkdir -p ~/.cloudflare
cp config.ini ~/.cloudflare/config.ini

./cloudflare-template.sh file
```

### Pass

If you want to use [Pass](https://www.passwordstore.org/) you can execute the following commands:

```bash
gpg --batch --passphrase '' --quick-gen-key USER_ID default default
```

Get key:

```bash
gpg2 --list-secret-keys --keyid-format LONG

sec   4096R/AAAA2222CCCC4444 2021-03-18 [expires: 2023-03-18] uid         John Doe <jdoe@example.com>
```

Init pass:
```bash
pass init 'AAAA2222CCCC4444'
```

Execute:

```bash
pass insert -m credentials/cloudflare
```

Add your variables:

```text
auth_email=""                                       # The email used to login 'https://dash.cloudflare.com'
auth_method=""                                      # Set to "global" for Global API Key or "token" for Scoped API Token
auth_key=""                                         # Your API Token or Global API Key
zone_identifier=""                                  # Can be found in the "Overview" tab of your domain
record_name=""                                      # Which record you want to be synced
ttl="3600"                                          # Set the DNS TTL (seconds)
proxy="false"                                       # Set the proxy to true or false
sitename=""                                         # Title of site "Example Site"
slackchannel=""                                     # Slack Channel #example
slackuri=""                                         # URI for Slack WebHook "https://hooks.slack.com/services/xxxxx"
discorduri=""                                       # URI for Discord WebHook "https://discordapp.com/api/webhooks/xxxxx"
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
