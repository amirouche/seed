#!r6rs
;;;
;;; Seed Nanopass style Compiler v3 — Unified Vau
;;;
;;; R6RS Library Interface
;;;

(library (seed)
  (export
    ;; Core compilation pipeline
    parse annotate classify bta codegen compile

    ;; AST conversion functions
    ast->src l2->src l3->src l4->src ast->src*

    ;; Runtime and evaluation
    seed-eval ground-env run run-with-env run-file dump-file

    ;; File operations
    read-all-forms transform-to-letrec

    ;; Development utilities
    dev! normalize-ep

    ;; Analysis and optimization
    uses-eval? has-free-vars? vau-info? static-value? static-value
    filter-map param-names value->ast try-fold-call bind-param-to-args
    free-symbols direct-eval-params bare-var-uses param-binding-times
    bind-params env-ref env-ref-unbox compile-eval-body inline-lambda
    fusible-match? subst-var-in-ast fix-free-to-local collect-assq-syms
    has-assq-refs? replace-assq-refs fuse-alist-lets thread-body
    specialize spec codegen*

    ;; Constants
    *primitives* *foldable-primitives*

    ;; Timing utilities
    current-nanoseconds

    ;; Expander integration
    seed-form? seed-expander enable-seed-expander! disable-seed-expander!)

  (import
    (except (chezscheme) compile)
    (prefix (only (chezscheme) compile) chez:)
    (only (match) match guard))

  ;; Load implementation from src/seed.scm
  (include "src/seed.scm")

  ;; Initialize: production mode by default
  (dev! #f))
