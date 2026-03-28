#!r6rs
;;;
;;; Seed3 Nanopass Compiler — Vau with generic specialization
;;;
;;; R6RS Library Interface
;;;

(library (seed3)
  (export
    ;; Core compilation pipeline
    parse annotate classify analyze-binding-time generate-code compile

    ;; AST conversion functions
    ast-to-source ast-to-source-form

    ;; Runtime and evaluation
    seed-evaluate environment-ground run run-with-environment run-file dump-file

    ;; File operations
    read-all-forms transform-top-level

    ;; Development utilities
    configure-development-mode normalize-environment-parameter

    ;; Analysis predicates
    ast-uses-eval? ast-has-free-variables? ast-references-environment?
    ast-collect-free-variables ast-has-define? ast-has-unknown-operative-calls?
    vau-info?

    ;; Specialization
    specialize specialize-expression generate-code-in-context

    ;; Define helpers
    collect-define-nodes generate-code-for-begin

    ;; Runtime helpers
    environment-lookup environment-lookup-unbox bind-parameters
    seed-evaluate-statement

    ;; BTA helpers
    compute-parameter-binding-times
    collect-direct-eval-parameters collect-bare-variable-uses

    ;; Helpers
    filter-map extract-parameter-names)

  (import
    (except (chezscheme) compile)
    (prefix (only (chezscheme) compile) chez:)
    (only (match) match guard))

  ;; Alias for chez:compile used inside seed3.scm
  (define chez-compile chez:compile)

  ;; Load implementation from src/seed3/seed3.scm
  (include "src/seed3/seed3.scm")

  ;; Initialize: production mode by default
  (configure-development-mode #f))
