# titulo: la semilla es artefacto puro — sin bin/ y sin ejecutables
# origen: V-134 (02 §1) — nuevo en v3
check() {
# La mitad de la deuda de v2 salía de que el mismo código vivía en dos
# lugares (seed/platform/bin/ y platform/bin/) y hacía falta una
# herramienta entera para vigilar que las copias no se separaran.
# F1-F4 lo midieron: 3 de 12 comandos viajaban, el generador estaba 444
# renglones atrás, y el fallo aparecía «en otra máquina, no acá».
# v3 no vigila la copia: la elimina. El código vive en el producto.
D134=""
[[ -d "$P/bin" ]] && D134="$D134 volvió seed/platform/bin/ (el código vive en libexec/, no en el artefacto);"

# EXCEPCIÓN DECLARADA, con su motivo y su fecha — una excepción escrita
# es distinta de un agujero: tofu/tofu-apply.sh es el envoltorio que
# descifra los secretos y corre tofu DESDE el directorio de tofu, y el
# operador lo invoca a mano desde platform/tofu/ (protocolo vps-lab).
# Mudarlo a libexec/ cambia la resolución de -chdir (#46) y la de los
# secretos: es una decisión de diseño, no una limpieza.
# La copia la sigue cuidando `aegis dev seed diff`, que cubre tofu/.
# VERIFICAR (2026-08-23, T-02): decidir si pasa a ser `aegis tofu`.
EXCEPCIONES=("tofu/tofu-apply.sh")
while IFS= read -r f; do
    rel="${f#"$P/"}"
    for e in "${EXCEPCIONES[@]}"; do [[ "$rel" == "$e" ]] && continue 2; done
    D134="$D134 $rel es ejecutable dentro del artefacto y no está declarado;"
done < <(find "$P" -type f -perm -u+x)

# y el otro lado de la moneda: las excepciones declaradas TIENEN que
# existir, o la lista se vuelve folclore.
for e in "${EXCEPCIONES[@]}"; do
    [[ -f "$P/$e" ]] || D134="$D134 la excepción declarada $e ya no existe (sacala de la lista);"
done
if [[ -n "$D134" ]]; then fail "semilla con código:$D134"
else pass "la semilla no lleva bin/ ni ejecutables sin declarar (el código vive en el producto)"; fi
}
