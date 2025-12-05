% tests.pl - Regression checks for Popper Prolog rewrite

:- begin_tests(popper).

:- use_module(popper).

addlast_options([ max_literals(3),
                  max_models(500),
                  clingo_timeout(30),
                  timeout(30)
                ]).

test(addlast_complete_program, [nondet]) :-
    addlast_options(Opts),
    popper:popper('examples/addlast', Opts, Program, outcome(all, none)),
    popper:program_clauses(Program, Clauses),
    assertion(Clauses \= []),
    assertion(( member(Clause, Clauses), sub_atom(Clause, _, _, _, 'last') )),
    !.

:- end_tests(popper).

run_tests :-
    run_tests([popper]).
