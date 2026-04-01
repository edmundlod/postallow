# Upgrading Postallow

## Upgrading from 3.x to 4.0.0

Version 4.0.0 introduces a significant security improvement: Postallow no
longer runs as root. Instead it runs as a dedicated unprivileged `postallow`
system user, with only the postfix reload step handled by the init system
with elevated privileges.

This is a breaking change. A fresh install approach is recommended.

### Step 1 — Remove your old root-based setup

If you were running Postallow via a root crontab:

    crontab -e   # as root — remove the postallow line

If you had a custom systemd service or timer:

    systemctl disable --now postallow.timer
    systemctl disable --now postallow.service
    rm /etc/systemd/system/postallow.*
    systemctl daemon-reload

### Step 2 — Install the new version

Copy the new `postallow` script to `/usr/local/bin/`:

    install -m 755 postallow /usr/local/bin/postallow

### Step 3 — Run the installer

The installer creates the `postallow` system user and sets up directories
with correct ownership:

    sh contrib/install.sh

### Step 4 — Migrate your configuration

If you had a custom `postallow.conf` or `allowlist_hosts`, copy them to
the new location:

    # Linux
    cp your-old-postallow.conf /etc/postallow/postallow.conf
    cp your-old-allowlist_hosts /etc/postallow/allowlist_hosts

    # FreeBSD
    cp your-old-postallow.conf /usr/local/etc/postallow/postallow.conf
    cp your-old-allowlist_hosts /usr/local/etc/postallow/allowlist_hosts

Review `postallow.conf` and update the `postfixpath` setting to the new
output directory:

    # Linux
    postfixpath=/var/lib/postallow

    # FreeBSD
    postfixpath=/var/db/postallow

### Step 5 — Fix ownership of existing cidr files

If you have an existing cidr file that Postallow needs to overwrite:

    # Linux
    chown postallow: /var/lib/postallow
    chown postallow: /var/lib/postallow/*.cidr

    # FreeBSD
    chown postallow: /var/db/postallow
    chown postallow: /var/db/postallow/*.cidr

### Step 6 — Install and enable the init scripts

**systemd (Linux):**

    cp contrib/postallow.service /etc/systemd/system/
    cp contrib/postallow.timer /etc/systemd/system/
    cp contrib/postallow-reload.service /etc/systemd/system/
    cp contrib/postallow.path /etc/systemd/system/
    systemctl daemon-reload
    systemctl enable --now postallow.timer

**FreeBSD:**

    cp contrib/postallow.rc /usr/local/etc/rc.d/postallow
    chmod 755 /usr/local/etc/rc.d/postallow
    sysrc postallow_enable="YES"
    service postallow start

### Step 7 — Update Postfix main.cf

If your `main.cf` referenced the old cidr file path, update it to the new
location and reload postfix:

    postconf -e "postscreen_access_list = permit_mynetworks, \
        cidr:/var/lib/postallow/postscreen_spf_allowlist.cidr"
    postfix reload

### Verify

Run Postallow manually once to confirm everything works:

    # Linux
    sudo -u postallow /usr/local/bin/postallow /etc/postallow/postallow.conf

    # FreeBSD
    su -s /bin/sh postallow -c \
        '/usr/local/bin/postallow /usr/local/etc/postallow/postallow.conf'

