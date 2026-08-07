

# Dialecto de Kernel para Scheme Considerado de Ayuda

## Qué

Me impresionó Kernel, creado por John Nathan Shutt, durante varios años. Intenté dejarlo atrás, pero regresó a mi vida, algo así como Python, JavaScript o PHP, pero sin la misma elegancia o actitud. Quizás sea elitismo, o tal vez curiosidad intelectual y posiblemente tribalismo. Quizás sean los paréntesis. Me estoy repitiendo.

Kernel abarca casi 70 años de historia. Lisp comenzó en 1958 en el MIT, Scheme se ramificó en 1975, la tesis de Brian Cantwell Smith de 1982 sobre 3-Lisp es el antecesor intelectual de todo lo que hace Kernel con entornos reificados, y Common Lisp cristalizó otra rama en la era de Symbolics. Las ideas nunca dejaron de difundirse: Femtolisp impulsa el analizador de Julia, el edn de Clojure llevó la notación de datos s-expression a una audiencia mainstream, y Fennel encontró tracción en el desarrollo de videojuegos. Lo que comparten es el descubrimiento recurrente de que un núcleo pequeño y programable da frutos. El `vau` de Kernel es la siguiente idea en esa línea que espera su llegada: la unificación de macros y procedimientos.

[John Nathan Shutt](https://web.cs.wpi.edu/~jshutt/) logró cristalizar con brillantez y probablemente precisión formal el trabajo de toda la comunidad de Lisp desde sus inicios con el lanzamiento del intérprete SINK y el último borrador de la especificación del [lenguaje de programación Kernel](https://web.cs.wpi.edu/~jshutt/kernel.html), en particular el [Revised -1 Report on the Kernel Programming Language](https://ftp.cs.wpi.edu/pub/techreports/pdf/05-07.pdf) en 2009. Defendió su tesis [Fexprs as the basis of Lisp function application or `$vau` : the ultimate abstraction](https://web.cs.wpi.edu/~jshutt/dissertation/etd-090110-124904-Shutt-Dissertation.pdf) en 2010. Falleció en 2020. 

No fue el único en creer en las ideas que hay en Kernel. Por ejemplo, los entornos de primera clase se encuentran en MIT Scheme y Guile. Creo recordar que Gambit tiene continuaciones reificadas (y más), y los attachments de continuación llegaron a Chez Scheme, un mecanismo similar a las variables dinámicas con clave de Kernel. ¡Gambit de nuevo! los ha tenido bajo otra forma durante mucho más tiempo. Así que, Kernel, como cualquier otro Lisp, es un Lisp.

Lo que me enganchó a Kernel, a pesar de mi pasión por el código, fue la pereza. A pesar del excelente trabajo para documentar las reglas de sintaxis y syntax-case, como el trabajo de [“Extending a Language — Writing Powerful Macros in Scheme” de Marc Nieper-Wißkirchen](https://github.com/mnieper/scheme-macros), no suscribo este enfoque. Prefiero el `vau` de Kernel. Me gusta la idea de unificar macros y procedimientos para que no necesites dos sistemas metalingüísticos separados, un mecanismo en lugar de dos.

Sin embargo, vau estaba maldito. [En 1998, Wand, "The Theory of Fexprs is Trivial," ACM SIGPLAN Notices 33(9), 1998.](https://www.ccs.neu.edu/home/wand/pubs.html#Wand98) demostró que los [fexpr](https://en.wikipedia.org/wiki/Fexpr) hacen que el razonamiento ecuacional sea imposible porque no puedes sustituir iguales por iguales cuando no sabes si una expresión será evaluada. La compilación se consideró intratable. 

Hasta 2026. 

EDIT (2026-02-06): Me dirigieron a kraken-lang.org y en particular
[Practical compilation of fexprs using partial evaluation: Fexprs can
performantly replace macros in purely-functional
Lisp](https://arxiv.org/abs/2303.12254). La diferencia entre Kraken
y seed es que seed no es puramente funcional, seed soporta
`define` y `set!` pero no en entornos dinámicos, además `seed` es
una extensión de chezscheme.

## Cómo

Hacer inmutable el entorno dinámico de `vau` restaura suficiente conocimiento estático para compilar de forma competitiva. En Kernel estándar, un operando `vau` recibe el entorno dinámico del llamador como un valor de primera clase; puede leerlo, recorrerlo y, crucialmente, mutarlo. Ese último poder es lo que arruina la compilación. Si cualquier operando puede reescribir los enlaces del llamador en cualquier momento, el compilador no puede saber qué significa cualquier variable en cualquier sitio de llamada, por lo que no puede sustituir, inlinar ni optimizar nada. La solución es quirúrgica: pasar el entorno, pero hacerlo de solo lectura. El operando aún puede introspeccionar los enlaces del llamador, ese es todo el punto de `vau`, la capacidad de decidir si y cómo evaluar sus argumentos, pero no puede tener efectos secundarios en ellos. En la práctica, no puede definir o `set!` una variable en el entorno dinámico, por lo tanto no hay mutación, ni nuevos enlaces. Concretamente, en el compilador, cada llamada a un operando pasa el entorno como el primer elemento de un par `(env . args)`. El entorno es un valor, no un almacén mutable. Esa única restricción — la inmutabilidad — le devuelve al compilador suficiente conocimiento estático para razonar sobre el código, inlinar llamadas y generar código nativo de la misma calidad que Chez Scheme produce a partir de syntax-case.

Catamorfismo vs. syntax-case. Considere un evaluador de expresiones pequeño. En Scheme con syntax-case, escribe una macro que hace coincidencia de patrones en tiempo de compilación, luego una función de ejecución separada que recorre el árbol con car, cdr y cond. Dos mecanismos, dos lenguajes: el lenguaje de macros y el lenguaje de ejecución — mantenidos separados por diseño. En Kernel, `vau` con `match` hace ambas cosas de una vez. La cláusula `match` `(+ ,a ,b)` une `a` y `b` y recursa cuando la coma señala un catamorfismo, lo que significa que la transformación se aplica a subexpresiones automáticamente antes de que el cuerpo de la cláusula las vea. Sin llamadas recursivas explícitas, sin desmenuzar la estructura de listas a mano. La versión de Scheme es más verbosa no porque el programador sea menos hábil, sino porque el lenguaje fuerza la separación de dos preocupaciones que son, estructuralmente, la misma preocupación: transformación de entrada-árbol a salida-árbol. La legibilidad es subjetiva; el lector puede juzgar por sí mismo. El rendimiento no lo es.

## Experiencia del Desarrollador

vau no requiere aprender un nuevo DSL, el lenguaje específico de dominio de coincidencia de patrones de syntax-rules, y los trucos de syntax-object-fu de `syntax-case`. Las tres implementaciones implementan el mismo comportamiento, solo la última, que usa `vau`, es económica:

```scheme
;;; myor — three implementations of short-circuit OR
;;;
;;; The point: vau controls evaluation directly.
;;; syntax-rules and syntax-case generate code that controls evaluation.
;;; Same result. One is a program. The other two are programs that write programs.

;;; -------------------------------------------------------
;;; 1. syntax-rules (R5RS / R7RS)
;;;
;;; The macro language: pattern templates with ellipsis.
;;; Short-circuit requires a let-binding to avoid double
;;; evaluation — the template language has no way to
;;; "evaluate once and test," so it must generate code
;;; that does it at runtime.
;;; -------------------------------------------------------

(define-syntax myor
  (syntax-rules ()
    ((_) #f)
    ((_ e) e)
    ((_ e1 e2 ...)
     (let ((t e1))
       (if t t (myor e2 ...))))))

;;; -------------------------------------------------------
;;; 2. syntax-case (R6RS / Chez Scheme)
;;;
;;; More power: you can run arbitrary Scheme at expand time.
;;; But for this example, the extra power buys nothing —
;;; the structure is identical to syntax-rules. The reader
;;; still operates in two languages: the template language
;;; (#' quotes, ellipsis) and the runtime language.
;;; -------------------------------------------------------

(define-syntax myor
  (lambda (x)
    (syntax-case x ()
      ((_) #'#f)
      ((_ e) #'e)
      ((_ e1 e2 ...)
       #'(let ((t e1))
           (if t t (myor e2 ...)))))))

;;; -------------------------------------------------------
;;; 3. vau (Kernel / Seed)
;;;
;;; No template language. No phase separation. No ellipsis.
;;; The operative receives its arguments unevaluated and
;;; the caller's environment. It decides what to evaluate,
;;; when, and how many times — using ordinary code.
;;;
;;; The let-binding that syntax-rules must generate?
;;; Here it is just... a let-binding. Written by the
;;; programmer, not generated by a macro expander.
;;; -------------------------------------------------------

(define myor
  (vau args env
    (if (null? args) #f
      (let ((v (eval (car args) env)))
        (if v v
          (eval (cons myor (cdr args)) env))))))

;;; -------------------------------------------------------
;;; Usage — identical in all three:
;;;
;;;   (myor #f #f 42)       => 42
;;;   (myor #f #f #f)       => #f
;;;   (myor 1 (error "!"))  => 1  (second arg never evaluated)
;;; -------------------------------------------------------
```

## Benchmarks

```bash
# make-benchmark.sh
── N-Queens — exercising single CPU ──────────────────────────────
  scheme --script seedink.scm n-queen.seed    compile:      n/as  execute: 22.988239534s  wall:   23.598s
  scheme --script n-queen.scm                                    execute:   23.003s  wall:   23.398s

── Collatz — exercising syntax-rules ────────────────────────────
  scheme --script seedink.scm collatz.seed    compile:      n/as  execute: 9.995808085s  wall:   10.263s
  scheme --script collatz.scm                                    execute:   10.307s  wall:   10.342s

── Abacus — exercising syntax-case ───────────────────────────────
  scheme --script seedink.scm abacus.seed     compile:      n/as  tree: 1.174771122s  eval: 1.649855682s  wall:    3.356s
  scheme --script abacus.scm                                      tree:    1.259s  eval:    1.560s  wall:    3.108s

── Abacus2 — multi-operand match (ternary trees) ─────────────────
  scheme --script seedink.scm abacus2.seed    compile:      n/as  tree: 0.803791520s  eval: 3.897080440s  wall:    5.337s
  scheme --script abacus2.scm                                     tree:    0.810s  eval:    5.441s  wall:    6.879s

── Summary ────────────────────────────────────────────────────────
Benchmark             Driver              Monotonic    Wall Clock
────────────────────  ───────────────  ────────────  ────────────
N-Queens              seedink               22.988s       23.598s
N-Queens              scheme                23.003s       23.398s
Collatz               seedink                9.996s       10.263s
Collatz               scheme                10.307s       10.342s
Abacus                seedink                2.825s        3.356s
Abacus                scheme                 2.819s        3.108s
Abacus2               seedink                4.701s        5.337s
Abacus2               scheme                 6.251s        6.879s
────────────────────  ───────────────  ────────────  ────────────
TOTAL                 seedink               40.510s       42.554s
TOTAL                 scheme                42.381s       43.727s
```

## Comentarios y Lectura Adicional

Este proyecto se discutió en [r/scheme](https://old.reddit.com/r/scheme/comments/1r2v4ax/kernels_vau_can_be_faster_than_syntaxcase/) y se plantearon los siguientes puntos:

**Sobre `define-record-type` y la mutación del entorno** — WittyStick señaló que `$provide!` es la solución canónica de Kernel, y que compilar operandos con mutación de entorno es posible mediante tipos de entorno polimórficos por fila. Seed2 ahora soporta la extensión del entorno del llamador vía `call-with-values`: los nombres exportados se asignan como parámetros lambda, de forma inmutable. La antigua desventaja ("no puedes escribir `define-class`") ya no es válida cuando la lista de exportación se conoce estáticamente.

[**Sobre operandos de primera clase como parámetros de función** — datarama
identificó un error
real](https://lobste.rs/s/2debab/seed_adding_vau_with_immutable_dynamic#c_u7wldl):
los sitios de llamada para parámetros enlazados a lambda actualmente no emiten
despacho de operando/aplicativo. Este es un problema conocido.

**Referencias del hilo:**

- Mitchell Wand, [Type Inference for Record Concatenation and Multiple Inheritance](https://www.cs.tufts.edu/~nr/cs257/archive/mitch-wand/types-simple-objects.pdf) — la base teórica para entornos polimórficos por fila
- Alan Bawden, [First-class Macros Have Types](https://people.csail.mit.edu/alan/mtt/) — tipificación estática para macros de primera clase, directamente relevante para la inferencia de forma del entorno en tiempo de compilación

## Conclusión

Aquí está el código de Chez Scheme. ¡Realicen benchmarks! ¡Disfrútenlo! Y que haya… evaluación.

## Descargo de Responsabilidad

La implementación se desarrolló con Claude.AI como asistente de código. Yo dirigí el diseño y revisé el código. Este es un trabajo exploratorio: una prueba de concepto por curiosidad intelectual, no infraestructura de producción.

Claude es IA y yo puedo cometer errores. Por favor, verifiquen cualquier cosa.
