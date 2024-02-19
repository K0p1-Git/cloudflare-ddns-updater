# Cloudflare Dynamic DNS IP Updater

This script is used to update Dynamic DNS (DDNS) service based on Cloudflare! Access your home network remotely via a custom domain name without a static IP! Written in pure BASH.

This version of this script allows you to update **multiple domains/sub domains with the same public IP for IPv4**, IPv6 version remains per single domain.

## Clone

```bash
git clone https://github.com/joeltgray/cloudflare-ddns-updater.git
```

## Usage
This version of the script is used with systemd. Update the paths in config below to match your setup.
If you need to know how to use systemd services check out my blog here: 
[Running A Service on Systemd](https://graycode.ie/blog/run-anything-as-a-service-on-linux/)

### Make the Script Executable
`chmod u+x /path/to/your/cloudflare-ddns-updater/cloudflare-dns-updater.sh`

### Make the service file
`nano /etc/systemd/system/cloudflare-ddns-updater.service`
```
[Unit]
Description=Service to update Cloudflare servers with this servers public IP

[Service]
ExecStart=/bin/bash  /path/to/your/cloudflare-ddns-updater/cloudflare-dns-updater.sh
Restart=
EnvironmentFile=/etc/environment

[Install]
WantedBy=multi-user.target
```

### Make the service timer file
`nano /etc/systemd/system/cloudflare-ddns-updater.timer`
```
[Unit]
Description=Run the script for Cloudflare SDNS updates every 5 minutes

[Timer]
OnCalendar=*-*-* *:00/5:05
OnBootSec=5
Persistent=true

[Install]
WantedBy=timers.target
```

### Enable and start the service
`systemctl daemon-reload`
`systemctl enable cloudflare-ddns-updater.service`
`systemctl enable cloudflare-ddns-updater.timer`
`systemctl start cloudflare-ddns-updater.timer`

## Tested Environments:
**Original:** <br />
macOS Mojave version 10.14.6 (x86_64) <br />
AlmaLinux 9.3 (Linux kernel: 5.14.0 | x86_64) <br />
Debian Bullseye 11 (Linux kernel: 6.1.28 | aarch64) <br />

**This version:** <br />
Debian 11 (Linux kernel: 6.1.0-0.deb11.13-amd64 | x86_64) <br />
Arch rolling (Linux kernel: 6.7.4-arch1-1 | x86_64) <br />
Raspbian 11 (Linux kernel: 6.1.21-v8+ | aarch64) <br />


## Contributing
Pull requests are welcome. For major changes, please open an issue first to discuss what you would like to change.

## Reference
This script was originally made by [Keld Norman](https://www.youtube.com/watch?v=vSIBkH7sxos) video, I've adapted from [Jason K](https://github.com/K0p1-Git)'s version

## License
[MIT](https://github.com/K0p1-Git/cloudflare-ddns-updater/blob/main/LICENSE)
