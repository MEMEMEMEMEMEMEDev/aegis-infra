# dientes del check 033b (sin dpkg -i en fases)
rojo_1() { printf '\nsudo dpkg -i /tmp/algo.deb\n' >> "$AEGIS_ROOT/init/phases/05-host.sh"; }
control_1() { printf '\nsudo apt-get -o DPkg::Lock::Timeout=300 install -y ./algo.deb\n' >> "$AEGIS_ROOT/init/phases/05-host.sh"; }
