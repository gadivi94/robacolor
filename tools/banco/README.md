# Banco de pruebas del copiado de look

Mide cuánto se parece el resultado de Robacolor a un preset de verdad.

1. `make_grades.py` aplica ocho looks conocidos (teal & orange, película mate, oscuro, dorado, blanco y negro sepia, proceso cruzado, frío suave y «sin editar») a diez fotos reales, con código propio que no comparte nada con el motor de la app.
2. `medir.js` extrae el look de `look(A)`, lo aplica a otra foto `B` y lo compara con `look(B)`, para todos los pares. El error es la distancia media en Oklab ×100 (parecido a ΔE).

```
FOTOS=ruta/a/opencv/samples/data/ DATOS=datos/ python3 tools/banco/make_grades.py
DATOS=datos/ node tools/banco/medir.js web/robacolor.html
```

Referencia (oct 2026): motor anterior 10,7 de media y 26,6 en el peor caso; motor actual 4,4 y 16,7. «Sin tocar» la foto da 3,9: con una sola imagen de referencia no se puede recuperar un preset exacto, así que el motor es prudente a propósito.
