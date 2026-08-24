# teeth of check 033a (apt-get waits for the dpkg lock)
red_1() { printf '\nsudo apt-get install -y cowsay\n' >> "$AEGIS_ROOT/init/phases/05-host.sh"; }
control_1() { printf '\nsudo apt-get -o DPkg::Lock::Timeout=300 install -y cowsay\n' >> "$AEGIS_ROOT/init/phases/05-host.sh"; }
