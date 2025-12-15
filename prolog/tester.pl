% tester.pl - Evaluate candidate programs against examples

:- module(tester,
    [ tester_initialise/2,        % +KbDir, +Options
      tester_evaluate/2,         % +OrderedProgram, -Outcome
      tester_outcome_summary/2   % +Outcome, -SummaryAtom
    ]).

:- use_module(library(apply)).
:- use_module(library(lists)).
:- use_module(library(option)).

:- use_module(core).

:- dynamic tester_state/3.
:- dynamic cached_counts/2.

%% tester_initialise(+KbDir, +Options)
%  Load the knowledge base located at KbDir (expects bk.pl, exs.pl) and
%  prepare the evaluation environment. Options recognised:
%    - timeout(+Seconds)
%    - minimal(+Boolean)
%  Defaults: timeout(60), minimal(true).
tester_initialise(KbDir0, Options) :-
    absolute_file_name(KbDir0, KbDir, [file_type(directory)]),
    option(timeout(Timeout), Options, 60),
    option(minimal(Minimal0), Options, true),
    truthy(Minimal0, Minimal),
    retractall(tester_state(_, _, _)),
    asserta(tester_state(KbDir, Timeout, Minimal)),
    ensure_test_loaded,
    reset_example_facts,
    load_background(KbDir),
    load_examples(KbDir, PosTerms, NegTerms),
    assert_examples(PosTerms, NegTerms),
    length(PosTerms, NumPos),
    length(NegTerms, NumNeg),
    retractall(cached_counts(_, _)),
    asserta(cached_counts(NumPos, NumNeg)),
    assert_timeout(Timeout).

%% tester_evaluate(+OrderedProgram, -Outcome)
%  Evaluate the program and return outcome(PosOutcome,NegOutcome) atoms.
tester_evaluate(ordered_program(Clauses, _), outcome(Pos, Neg)) :-
    tester_state(_, _, Minimal),
    program_terms(Clauses, Terms),
    setup_call_cleanup(
        assert_program(Terms, Refs),
        run_tests(Minimal, Metrics),
        cleanup_program(Refs)
    ),
    metrics_outcome(Metrics, Pos, Neg).

tester_outcome_summary(outcome(Pos, Neg), Summary) :-
    format(atom(Summary), '~w/~w', [Pos, Neg]).

% ---------------------------------------------------------------------------
% Internal helpers

truthy(true, true)  :- !.
truthy(false, false) :- !.
truthy(yes, true) :- !.
truthy(no, false) :- !.
truthy(1, true) :- !.
truthy(0, false) :- !.
truthy(Value, true) :- Value \= false.

ensure_test_loaded :-
    absolute_file_name('prolog/test.pl', File, [file_type(regular)]),
    user:ensure_loaded(File).

reset_example_facts :-
    forall(member(Name/Arity, [pos/1, neg/1, num_pos/1, num_neg/1, timeout/1]),
           ( functor(Template, Name, Arity),
                         retractall(user:Template)
           )).

assert_timeout(Timeout) :-
        assertz(user:timeout(Timeout)).

load_background(KbDir) :-
    directory_file_path(KbDir, 'bk.pl', BKPath0),
    absolute_file_name(BKPath0, BKPath, [file_type(regular)]),
    user:ensure_loaded(BKPath).

load_examples(KbDir, Pos, Neg) :-
    directory_file_path(KbDir, 'exs.pl', ExsPath0),
    absolute_file_name(ExsPath0, ExsPath, [file_type(regular)]),
    setup_call_cleanup(
        open(ExsPath, read, In),
        read_example_terms(In, Pos, Neg),
        close(In)
    ).

read_example_terms(Stream, Pos, Neg) :-
    read_term(Stream, Term, []),
    (   Term == end_of_file
    ->  Pos = [],
        Neg = []
    ;   Term = pos(Example)
    ->  Pos = [Example|PosRest],
        read_example_terms(Stream, PosRest, Neg)
    ;   Term = neg(Example)
    ->  Neg = [Example|NegRest],
        read_example_terms(Stream, Pos, NegRest)
    ;   read_example_terms(Stream, Pos, Neg)
    ).

assert_examples(PosTerms, NegTerms) :-
    maplist(assert_pos, PosTerms),
    maplist(assert_neg, NegTerms),
    length(PosTerms, NumPos),
    length(NegTerms, NumNeg),
    assertz(user:num_pos(NumPos)),
    assertz(user:num_neg(NumNeg)).

assert_pos(Term) :-
    assertz(user:pos(Term)).

assert_neg(Term) :-
    assertz(user:neg(Term)).

program_terms(Clauses, Terms) :-
    maplist(clause_term, Clauses, Terms).

clause_term(ordered_clause([Head], Body, _), Term) :-
    core:literal_code(Head, HeadCode),
    maplist(core:literal_code, Body, BodyCodes),
    (   BodyCodes == []
    ->  format(atom(ClauseAtom), '~w.', [HeadCode])
    ;   atomic_list_concat(BodyCodes, ', ', BodyAtom),
        format(atom(ClauseAtom), '~w :- ~w.', [HeadCode, BodyAtom])
    ),
    term_string(Term, ClauseAtom).

assert_program(Terms, Refs) :-
    maplist(assert_clause, Terms, Refs).

assert_clause(Clause, Ref) :-
    assertz(user:Clause, Ref).

cleanup_program(Refs) :-
    maplist(erase, Refs).

run_tests(true, metrics(TP, FN, 0, FP)) :-
    user:do_test_minimal(TP, FN, 0, FP).
run_tests(false, metrics(TP, FN, TN, FP)) :-
    user:do_test(TP, FN, TN, FP).

metrics_outcome(metrics(TP, FN, _TN, FP), PosOutcome, NegOutcome) :-
    cached_counts(NumPos, _),
    (   TP =:= NumPos
    ->  PosOutcome = all
    ;   TP =:= 0,
        FN > 0
    ->  PosOutcome = none
    ;   PosOutcome = some
    ),
    (   FP =:= 0
    ->  NegOutcome = none
    ;   NegOutcome = some
    ).