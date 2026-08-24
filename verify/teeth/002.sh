# dientes del check 002 (los YAML parsean)
#
# Hay que romper el PARSEO, no la existencia: borrar un archivo deja al
# check contando uno menos y siguiendo verde.
#
# Nota de método: el primer rojo que probé —una lista con sangría
# despareja— resultaba YAML VÁLIDO. El diente no mordía y el culpable
# era el diente. Por eso el runner los corre: un diente que se escribe
# y no se ejecuta es exactamente la promesa sin prueba que este
# mecanismo existe para impedir.

# un flujo abierto: [uno, dos  sin cerrar el corchete
rojo_1() {
    printf '\nclave_rota: [uno, dos\n' >> "$AEGIS_ROOT/semilla/plataforma/edge.yaml"
}

# un alias a un ancla que no existe, en el SEGUNDO documento: prueba
# de paso que el check usa safe_load_all y no safe_load (los
# manifiestos de k8s son multi-doc y con safe_load se leería solo el
# primero — el resto entraría al cluster sin que nadie los mirara).
# (El rojo anterior era una clave duplicada: PyYAML la acepta y pisa el
# valor. Otro diente que no mordía por culpa del diente.)
rojo_2() {
    printf '\n---\nreferencia: *ancla_que_no_existe\n' >> "$AEGIS_ROOT/semilla/plataforma/servicios.yaml"
}

# control: un comentario en un YAML sigue siendo YAML válido
control_1() { printf '\n# comentario legitimo\n' >> "$AEGIS_ROOT/semilla/plataforma/edge.yaml"; }
