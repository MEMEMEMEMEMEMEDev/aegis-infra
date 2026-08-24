# teeth of check 033b (no dpkg -i in the phases)
red_1() { printf '\nsudo dpkg -i /tmp/something.deb\n' >> "$AEGIS_ROOT/init/phases/05-host.sh"; }
control_1() { printf '\nsudo apt-get -o DPkg::Lock::Timeout=300 install -y ./something.deb\n' >> "$AEGIS_ROOT/init/phases/05-host.sh"; }
