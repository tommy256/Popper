% popper.pl - Main control loop for the Prolog Popper rewrite

:- module(popper,
        [ popper/2,                 % +KbDir, -Program
            popper/3,                 % +KbDir, +Options, -Program
            popper/4,                 % +KbDir, +Options, -Program, -Outcome
            run/1,                    % +KbDir
            run/2,                    % +KbDir, +Options
            program_clauses/2         % +Program, -ListOfClauseStrings
        ]).

:- use_module(library(option)).
:- use_module(library(apply)).

:- use_module(solver).
:- use_module(generate).
:- use_module(order).
:- use_module(tester).
:- use_module(core).

%% popper(+KbDir, -Program)
%  Convenience predicate with default options.
popper(KbDir, Program) :-
    popper(KbDir, [], Program).

%% popper(+KbDir, +Options, -Program)
%  Return the first program that is complete and consistent.
popper(KbDir, Options, Program) :-
    popper(KbDir, Options, Program, outcome(all, none)), !.

%% popper(+KbDir, +Options, -Program, -Outcome)
%  Search for programs ordered by increasing literal count. Produces
%  every candidate program with its evaluation outcome on backtracking.
popper(KbDir, Options, Program, Outcome) :-
    option(max_literals(MaxLits), Options, 3),
    tester:tester_initialise(KbDir, Options),
    option(max_models(MaxModels), Options, 0),
    option(clingo_timeout(ClingoTimeout), Options, 0),
    between(1, MaxLits, LiteralCount),
    solver:clingo_models(KbDir, LiteralCount, ClingoTimeout, AllModels),
    maybe_limit_models(MaxModels, AllModels, Models),
    member(ModelAtoms, Models),
    generate:unordered_program_from_model(ModelAtoms, Unordered),
    safe_order(Unordered, Ordered),
    tester:tester_evaluate(Ordered, Outcome),
    Program = Ordered.

%% run(+KbDir)
%  Execute Popper with default options and print the resulting program.
run(KbDir) :-
    run(KbDir, []).

%% run(+KbDir, +Options)
%  Execute Popper and print all discovered programs with their outcome.
run(KbDir, Options) :-
    (   popper(KbDir, Options, Program, Outcome),
        tester:tester_outcome_summary(Outcome, Summary),
        format('Outcome: ~w~n', [Summary]),
        program_to_output(Program),
        fail
    ;   true
    ).

% ---------------------------------------------------------------------------
% Helpers

maybe_limit_models(0, Models, Models) :- !.
maybe_limit_models(Max, Models, Limited) :-
    Max > 0,
    length(Limited, Max),
    append(Limited, _, Models), !.
maybe_limit_models(_, Models, Models).

safe_order(Unordered, Ordered) :-
    catch(order:unordered_to_ordered(Unordered, Ordered), Error, handle_order_error(Error)).

handle_order_error(error(cannot_ground(_, _), _)) :-
    !, fail.
handle_order_error(Error) :-
    throw(Error).

program_to_output(Program) :-
    program_clauses(Program, Clauses),
    forall(member(Atom, Clauses),
           format('  ~w~n', [Atom]) ).

program_clauses(ordered_program(Clauses, _), ClauseAtoms) :-
    maplist(clause_atom, Clauses, ClauseAtoms).

clause_atom(ordered_clause([Head], Body, _), Atom) :-
    core:literal_code(Head, HeadCode),
    maplist(core:literal_code, Body, BodyCodes),
    (   BodyCodes == []
    ->  format(atom(Atom), '~w.', [HeadCode])
    ;   atomic_list_concat(BodyCodes, ', ', BodyAtom),
        format(atom(Atom), '~w :- ~w.', [HeadCode, BodyAtom])
    ).