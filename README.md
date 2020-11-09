# Cloudflare Dynamic DNS IP Register

This script is used to update dynamic DNS entries for accounts on Cloudflare.

## Installation

```bash
git clone https://github.com/K0p1-Git/cloudflare-ddns-updater.git
```

## Usage
This script is used with crontab. Specify the frequency of running the script.

```bash
# minute | hour | (day of month) | month | (day of week) | command
* * * * * cd /{location of repo} && /{location of repo}/cloudflare-template.sh >> /cron.log 2>&1
0 0 */3 * * echo " " > /cloudflare-autoupdate.log >> /cron.log 2>&1
```

## Contributing
Pull requests are welcome. For major changes, please open an issue first to discuss what you would like to change.

Please make sure to update tests as appropriate.

## Reference
This script was made with reference from [Keld Norman](https://www.youtube.com/watch?v=vSIBkH7sxos) video.

## License
[MIT](https://github.com/K0p1-Git/cloudflare-ddns-updater/blob/main/LICENSE)
