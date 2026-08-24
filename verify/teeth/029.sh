# dientes del check 029 (builds esperados por NÚMERO, no lastBuild)
# Carrera de la corrida #9: lastBuild puede ser OTRO build disparado en
# el medio, y la fase da por bueno lo que no construyó.
rojo_1() { printf '\ncurl -s "$JENKINS/job/x/lastBuild/api/json"\n' >> "$AEGIS_ROOT/init/phases/50-jenkins.sh"; }
