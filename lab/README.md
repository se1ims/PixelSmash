# Lab

Scripts that build and prepare the vulnerable environment.

## setup_lab.sh

One-time setup. Installs build dependencies, builds FFmpeg 8.0.1 from
source into /usr/local, clones the PoC, and optionally builds the Qt
player. Run once per VM.

    sudo lab/setup_lab.sh

## prepare_payloads.sh

Generates a calibrated exploit AVI. The filename is derived from the
payload command.

    lab/prepare_payloads.sh "xcalc &"                  
    lab/prepare_payloads.sh "id > /tmp/pwned"          

AVIs are written to `~/$REPO_DIR/vids/`.

**Disable ASLR before running the demo.** The script prints the command.
